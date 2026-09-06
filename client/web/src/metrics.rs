//! Measuring text the way the page draws it.
//!
//! `TextWidth`, `ConsoleWidth` and `PreSpaceWidth` are one unit in the
//! original client — twips — and scripts subtract one from another to decide
//! where a column ends. Counting characters instead only works while every
//! run is the same monospaced size, which the console's markup makes untrue
//! the moment a script picks a font.
//!
//! So everything here is CSS pixels, the unit the page lays out in, and the
//! measuring is done with an `OffscreenCanvas`. A worker may have one, which
//! is what makes this affordable: `TextWidth` is called in loops, and a round
//! trip to the page for each call would not be.

use std::cell::RefCell;
use std::collections::HashMap;

use wasm_bindgen::{JsCast, JsValue};
use web_sys::{OffscreenCanvas, OffscreenCanvasRenderingContext2d};

use vbscript::game::markup::{Line, Segment};

/// Points to CSS pixels, the conversion the page's `font-size: Npt` makes.
const PX_PER_POINT: f64 = 96.0 / 72.0;

/// `line-height` on `.line`, so a measured height matches the row drawn.
const LINE_HEIGHT: f64 = 1.425;

/// `min-height` on `.line`: a row is never shorter than this.
const MIN_LINE_HEIGHT: f64 = 19.0;

/// Roughly the average glyph width of the console's Verdana Bold, as a
/// fraction of the font size. Only used where no canvas exists — a test
/// harness under Node — so that widths stay in pixels rather than changing
/// unit when measurement is unavailable.
const ESTIMATED_GLYPH_RATIO: f64 = 0.6;

/// Entries kept before the cache is dropped and started again.
///
/// Scripts measure a string that grows a word at a time, so the cache fills
/// with strings that will not be asked for twice. A cap keeps a long session
/// from growing without bound; clearing wholesale beats tracking an order.
const CACHE_LIMIT: usize = 4096;

pub struct TextMetrics {
    /// `None` where the environment has no `OffscreenCanvas`.
    ctx: Option<OffscreenCanvasRenderingContext2d>,
    /// Family name to the CSS stack the page renders it with, so a fallback
    /// is measured rather than the font the machine does not have.
    fonts: HashMap<String, String>,
    cache: RefCell<HashMap<String, f64>>,
}

impl TextMetrics {
    /// `fonts` is the page's family-to-stack table, as a plain object.
    pub fn new(fonts: &JsValue) -> TextMetrics {
        TextMetrics {
            ctx: context(),
            fonts: font_table(fonts),
            cache: RefCell::new(HashMap::new()),
        }
    }

    /// The width of a parsed line, which is what `TextWidth` reports.
    ///
    /// Segments sit side by side, so the line is as wide as their sum. The
    /// leading indent is not part of it: `PreSpaceWidth` is the separate
    /// number scripts subtract for themselves.
    pub fn line_width(&self, line: &Line) -> f64 {
        line.segments.iter().map(|s| self.segment_width(s)).sum()
    }

    /// The height of a parsed line: the tallest run on it, floored at the
    /// row height an empty line still occupies.
    pub fn line_height(&self, line: &Line) -> f64 {
        line.segments
            .iter()
            .map(|s| f64::from(s.size) * PX_PER_POINT * LINE_HEIGHT)
            .fold(MIN_LINE_HEIGHT, f64::max)
    }

    fn segment_width(&self, segment: &Segment) -> f64 {
        if segment.text.is_empty() {
            return 0.0;
        }
        let font = self.css_font(segment);
        // The key holds the font too: the same text in Impact 48 is not the
        // width it is in Verdana 10.
        let key = format!("{font}\u{0}{}", segment.text);
        if let Some(width) = self.cache.borrow().get(&key) {
            return *width;
        }

        let width = self
            .measure(&font, &segment.text)
            .unwrap_or_else(|| estimate(segment));

        let mut cache = self.cache.borrow_mut();
        if cache.len() >= CACHE_LIMIT {
            cache.clear();
        }
        cache.insert(key, width);
        width
    }

    fn measure(&self, font: &str, text: &str) -> Option<f64> {
        let ctx = self.ctx.as_ref()?;
        ctx.set_font(font);
        ctx.measure_text(text).ok().map(|m| m.width())
    }

    /// The CSS `font` shorthand for a run, in the order the property wants:
    /// style, weight, size, family.
    fn css_font(&self, segment: &Segment) -> String {
        let style = if segment.italic { "italic " } else { "" };
        let weight = if segment.bold { "700" } else { "400" };
        format!("{style}{weight} {}pt {}", segment.size, self.stack(&segment.font))
    }

    fn stack(&self, family: &str) -> String {
        match self.fonts.get(family) {
            Some(stack) => stack.clone(),
            // The same shape as the page's fallback for a font it has no
            // entry for.
            None => format!("\"{family}\", \"DejaVu Sans\", sans-serif"),
        }
    }
}

/// A 1x1 canvas, which is all a measurement needs.
///
/// Absent outside a browser — the smoke test runs under Node — and the
/// failure is expected rather than reported.
fn context() -> Option<OffscreenCanvasRenderingContext2d> {
    let canvas = OffscreenCanvas::new(1, 1).ok()?;
    canvas
        .get_context("2d")
        .ok()
        .flatten()?
        .dyn_into::<OffscreenCanvasRenderingContext2d>()
        .ok()
}

fn estimate(segment: &Segment) -> f64 {
    let size = f64::from(segment.size) * PX_PER_POINT;
    segment.text.chars().count() as f64 * size * ESTIMATED_GLYPH_RATIO
}

/// Read the page's `{ family: stack }` table.
fn font_table(fonts: &JsValue) -> HashMap<String, String> {
    let mut table = HashMap::new();
    let Some(object) = fonts.dyn_ref::<js_sys::Object>() else {
        return table;
    };
    for entry in js_sys::Object::entries(object).iter() {
        let pair = js_sys::Array::from(&entry);
        if let (Some(name), Some(stack)) = (pair.get(0).as_string(), pair.get(1).as_string()) {
            table.insert(name, stack);
        }
    }
    table
}
