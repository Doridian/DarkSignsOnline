//! The console, as seen from a worker.
//!
//! Output is handed to the page as already-parsed styled runs, so the
//! renderer never has to understand `{{...}}` markup. Input is the awkward
//! direction: a script calls `ReadLine` and expects an answer, so the worker
//! blocks until the page supplies one. The blocking itself lives in
//! JavaScript, where `Atomics.wait` is natural.

use serde::Serialize;
use wasm_bindgen::prelude::*;

use vbscript::game::console::{Channel, Console, DrawMode};
use vbscript::game::markup;

/// A styled run of text, ready to render.
#[derive(Serialize)]
pub struct Run {
    pub text: String,
    pub font: String,
    pub size: i32,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strikethrough: bool,
    /// `#rrggbb`, converted from the game's red-in-the-low-byte packing.
    pub color: String,
    pub flash: &'static str,
}

/// Something the console was told to do.
#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Event {
    #[serde(rename_all = "camelCase")]
    Line {
        channel: &'static str,
        runs: Vec<Run>,
        align: &'static str,
        pre_space: bool,
        /// Set when the line replaces the one before it, which is how the
        /// typewriter effect and progress indicators work.
        replace: bool,
    },
    Clear,
    LineUp,
    #[serde(rename_all = "camelCase")]
    Draw { y: i64, color: String, mode: String, segments: i64 },
    #[serde(rename_all = "camelCase")]
    DrawCustom { y: i64, values: Vec<i64> },
    #[serde(rename_all = "camelCase")]
    DrawEven { y: i64, colors: Vec<i64> },
    Edit { path: String },
    Music { command: String },
    Mail,
    #[serde(rename_all = "camelCase")]
    ChatVisible { visible: bool },
    #[serde(rename_all = "camelCase")]
    YDiv { value: i64 },
}

/// The game packs colours with red in the low byte; CSS wants the reverse.
pub fn css_color(packed: i32) -> String {
    let [r, g, b] = vbscript::game::values::rgb_split(packed);
    format!("#{r:02x}{g:02x}{b:02x}")
}

/// The styled runs of a parsed line, for the page to render.
pub fn runs_json(line: &markup::Line) -> Vec<Run> {
    runs_of(line)
}

fn runs_of(line: &markup::Line) -> Vec<Run> {
    line.segments
        .iter()
        .map(|s| Run {
            text: s.text.clone(),
            font: s.font.clone(),
            size: s.size,
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            strikethrough: s.strikethrough,
            color: css_color(s.color),
            flash: match s.flash {
                markup::Flash::None => "none",
                markup::Flash::Normal => "normal",
                markup::Flash::Fast => "fast",
                markup::Flash::Slow => "slow",
            },
        })
        .collect()
}

/// The JavaScript side of the console.
///
/// `emit` receives one JSON event. `read_line` and `read_key` block until
/// the page answers; in a worker that is `Atomics.wait`, which is why the
/// page must be cross-origin isolated.
pub struct WorkerConsole {
    emit: js_sys::Function,
    read_line: js_sys::Function,
    read_key: js_sys::Function,
    /// Columns, for scripts that lay text out themselves.
    pub width: i64,
}

impl WorkerConsole {
    pub fn new(
        emit: js_sys::Function,
        read_line: js_sys::Function,
        read_key: js_sys::Function,
        width: i64,
    ) -> WorkerConsole {
        WorkerConsole { emit, read_line, read_key, width }
    }

    fn send(&self, event: &Event) {
        let Ok(json) = serde_json::to_string(event) else {
            return;
        };
        // A failed post means the page has gone; there is nothing useful to
        // do about it from here.
        let _ = self.emit.call1(&JsValue::NULL, &JsValue::from_str(&json));
    }

    fn line(&self, channel: &'static str, text: &str, replace: bool) {
        let parsed = markup::parse(text);
        self.send(&Event::Line {
            channel,
            runs: runs_of(&parsed),
            align: match parsed.align {
                markup::Align::Left => "left",
                markup::Align::Center => "center",
                markup::Align::Right => "right",
            },
            pre_space: parsed.pre_space,
            replace,
        });
    }
}

impl Console for WorkerConsole {
    fn say(&mut self, channel: Channel, text: &str) {
        let name = match channel {
            Channel::Say => "say",
            Channel::Comm => "comm",
            Channel::Chat => "chat",
        };
        self.line(name, text, false);
    }

    fn say_at(&mut self, text: &str, _y: i64) {
        // Writing at a row replaces whatever was there.
        self.line("say", text, true);
    }

    fn clear(&mut self) {
        self.send(&Event::Clear);
    }

    fn line_up(&mut self) {
        self.send(&Event::LineUp);
    }

    fn draw(&mut self, y: i64, rgb: i64, mode: DrawMode, segments: i64) {
        self.send(&Event::Draw {
            y,
            color: css_color(rgb as i32),
            mode: format!("{mode:?}").to_lowercase(),
            segments,
        });
    }

    fn draw_custom(&mut self, y: i64, values: &[i64]) {
        self.send(&Event::DrawCustom { y, values: values.to_vec() });
    }

    fn draw_even(&mut self, y: i64, colors: &[i64]) {
        self.send(&Event::DrawEven { y, colors: colors.to_vec() });
    }

    fn read_line(&mut self, prompt: &str, rgb: i64) -> Option<String> {
        if !prompt.is_empty() {
            self.say(Channel::Say, prompt);
        }
        let answer = self
            .read_line
            .call1(&JsValue::NULL, &JsValue::from_f64(rgb as f64))
            .ok()?;
        // A null answer means the page closed the input, which ends the
        // script the way closing the console does.
        answer.as_string()
    }

    fn get_key(&mut self) -> i64 {
        self.read_key
            .call0(&JsValue::NULL)
            .ok()
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0) as i64
    }

    fn get_ascii(&mut self) -> i64 {
        self.get_key()
    }

    fn console_width(&self) -> i64 {
        self.width
    }

    fn pre_space_width(&self) -> i64 {
        0
    }

    fn text_width(&self, text: &str) -> i64 {
        // Character cells. Measuring the real font would mean a round trip
        // to the page for every call, which scripts make in loops.
        markup::parse(text).text().chars().count() as i64
    }

    fn text_height(&self, _text: &str) -> i64 {
        1
    }

    fn set_y_div(&mut self, value: i64) {
        self.send(&Event::YDiv { value });
    }

    fn edit(&mut self, path: &str) {
        self.send(&Event::Edit { path: path.into() });
    }

    fn music(&mut self, command: &str) {
        self.send(&Event::Music { command: command.into() });
    }

    fn mail(&mut self) {
        self.send(&Event::Mail);
    }

    fn set_chat_visible(&mut self, visible: bool) {
        self.send(&Event::ChatVisible { visible });
    }
}
