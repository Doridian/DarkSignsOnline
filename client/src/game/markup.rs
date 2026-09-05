//! The `{{...}}` markup scripts use to style console output.
//!
//! A line is split into segments by `{{|}}`, and each segment carries its own
//! font, size, colour and effects. A tag applies to the segment it appears
//! in; a few tags — alignment and the leading indent — belong to the line and
//! are only read from the first segment, matching `basConsole`.
//!
//! Parsing lives here rather than in the renderer so the UI receives styled
//! runs it can draw directly.

/// Separates one styled run from the next.
const SEGMENT_SEPARATOR: &str = "{{|}}";

/// The console will not render text larger than this.
pub const MAX_FONT_SIZE: i32 = 144;

/// The smallest size a tag can select.
pub const MIN_FONT_SIZE: i32 = 8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Align {
    Left,
    Center,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VAlign {
    Top,
    Middle,
    Bottom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flash {
    None,
    Normal,
    Fast,
    Slow,
}

/// One styled run of text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    pub text: String,
    pub font: String,
    pub size: i32,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strikethrough: bool,
    /// Colour packed the way VB's `RGB` does it, with red in the low byte.
    pub color: i32,
    pub flash: Flash,
    pub valign: VAlign,
    pub h_offset: i32,
    pub v_offset: i32,
}

impl Default for Segment {
    fn default() -> Segment {
        Segment {
            text: String::new(),
            // The client's shipped defaults.
            font: "Verdana".into(),
            size: 10,
            bold: true,
            italic: false,
            underline: false,
            strikethrough: false,
            color: 0xFFFFFF,
            flash: Flash::None,
            valign: VAlign::Middle,
            h_offset: 0,
            v_offset: 0,
        }
    }
}

/// A parsed line of console output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Line {
    pub segments: Vec<Segment>,
    pub align: Align,
    /// Whether the console indents this line.
    pub pre_space: bool,
}

impl Default for Line {
    fn default() -> Line {
        Line { segments: Vec::new(), align: Align::Left, pre_space: true }
    }
}

impl Line {
    /// The visible text, with all markup removed.
    pub fn text(&self) -> String {
        self.segments.iter().map(|s| s.text.as_str()).collect()
    }
}

/// The named colours, in VB's packing (red in the low byte).
///
/// `lred` and `pink` really do share a value in the original, and `black` is
/// 1 rather than 0 so it stays distinguishable from an unset colour.
fn named_color(name: &str) -> Option<i32> {
    Some(match name {
        "white" => 0xFFFFFF,
        "black" => 0x000001,
        "purple" => 0xC000C0,
        "pink" => 0x8080FF,
        "orange" => 0x0080FF,
        "lorange" => 0x80C0FF,
        "blue" => 0xE99A9C,
        "dblue" => 0xCE5B35,
        "lblue" => 0xFFFF00,
        "green" => 0x3DCF44,
        "dgreen" => 0x008000,
        "lgreen" => 0x7EE084,
        "gold" => 0x06C9F2,
        "yellow" => 0x00FFFF,
        "lyellow" => 0x80FFFF,
        "dyellow" => 0x00C0C0,
        "brown" => 0x5E7386,
        "lbrown" => 0x8B9DAD,
        "dbrown" => 0x42505B,
        "maroon" => 0x293C83,
        "grey" => 0x808080,
        "dgrey" => 0x404040,
        "lgrey" => 0xE0E0E0,
        "red" => 0x0000FF,
        "lred" => 0x8080FF,
        "dred" => 0x0000C0,
        _ => return None,
    })
}

/// Tag names that select a font, mapped to the family they name.
fn named_font(name: &str) -> Option<&'static str> {
    Some(match name {
        "arial" => "Arial",
        "arial_black" => "Arial Black",
        "comic_sans_ms" => "Comic Sans MS",
        "courier_new" => "Courier New",
        "georgia" => "Georgia",
        "impact" => "Impact",
        "lucida_console" => "Lucida Console",
        "tahoma" => "Tahoma",
        "times_new_roman" => "Times New Roman",
        "trebuchet_ms" => "Trebuchet MS",
        "verdana" => "Verdana",
        "wingdings" => "Wingdings",
        "webdings" => "Webdings",
        _ => return None,
    })
}

/// Parse a line of console output into its styled segments.
pub fn parse(text: &str) -> Line {
    // Output stops at the first newline, as the console renders one line.
    let text = text.split(['\r', '\n']).next().unwrap_or("");

    let mut line = Line::default();
    let sources: Vec<&str> = text.split(SEGMENT_SEPARATOR).collect();

    for (index, source) in sources.iter().enumerate() {
        let mut segment = Segment::default();
        for tag in tags(source) {
            apply_tag(&tag, &mut segment, &mut line, index == 0);
        }
        segment.text = caption(source);
        line.segments.push(segment);
    }
    line
}

/// The tag words inside a segment's `{{...}}` groups.
///
/// Commas separate tags just as spaces do, and runs of separators collapse.
fn tags(source: &str) -> Vec<String> {
    let mut collected = String::new();
    let chars: Vec<char> = source.chars().collect();
    let mut i = 0;
    let mut inside = false;
    while i < chars.len() {
        if !inside && chars[i] == '{' && chars.get(i + 1) == Some(&'{') {
            inside = true;
            collected.push(' ');
            i += 2;
            continue;
        }
        if inside && chars[i] == '}' && chars.get(i + 1) == Some(&'}') {
            inside = false;
            i += 2;
            continue;
        }
        if inside {
            collected.push(chars[i]);
        }
        i += 1;
    }

    collected
        .replace(',', " ")
        .split_whitespace()
        .map(|t| t.to_ascii_lowercase())
        .collect()
}

/// A segment's visible text: everything outside its `{{...}}` groups.
fn caption(source: &str) -> String {
    let mut out = String::new();
    let chars: Vec<char> = source.chars().collect();
    let mut i = 0;
    let mut inside = false;
    while i < chars.len() {
        if !inside && chars[i] == '{' && chars.get(i + 1) == Some(&'{') {
            inside = true;
            i += 2;
            continue;
        }
        if inside && chars[i] == '}' && chars.get(i + 1) == Some(&'}') {
            inside = false;
            i += 2;
            continue;
        }
        if !inside && chars[i] != super::values::INVISIBLE_CHAR {
            out.push(chars[i]);
        }
        i += 1;
    }
    out
}

fn apply_tag(tag: &str, seg: &mut Segment, line: &mut Line, first_segment: bool) {
    if let Some(font) = named_font(tag) {
        seg.font = font.into();
        return;
    }
    if let Some(color) = named_color(tag) {
        seg.color = color;
        return;
    }

    match tag {
        "strikethrough" | "strikethru" => seg.strikethrough = true,
        "nostrikethrough" | "nostrikethru" => seg.strikethrough = false,
        "italic" | "italics" => seg.italic = true,
        "noitalic" | "noitalics" => seg.italic = false,
        "bold" => seg.bold = true,
        "nobold" => seg.bold = false,
        "underline" | "underlined" => seg.underline = true,
        "nounderline" | "nounderlined" => seg.underline = false,

        "noflash" => seg.flash = Flash::None,
        "flash" => seg.flash = Flash::Normal,
        "flashfast" => seg.flash = Flash::Fast,
        "flashslow" => seg.flash = Flash::Slow,

        "top" => seg.valign = VAlign::Top,
        "bottom" => seg.valign = VAlign::Bottom,
        "middle" => seg.valign = VAlign::Middle,

        _ => {
            if let Some(v) = tag.strip_prefix("hoff:") {
                seg.h_offset = v.parse().unwrap_or(0);
            } else if let Some(v) = tag.strip_prefix("voff:") {
                seg.v_offset = v.parse().unwrap_or(0);
            } else if let Some(v) = tag.strip_prefix("rgb:") {
                if let Some(c) = parse_rgb(v) {
                    seg.color = c;
                }
            } else if let Ok(size) = tag.parse::<i32>() {
                seg.size = size.clamp(MIN_FONT_SIZE, MAX_FONT_SIZE);
            } else if first_segment {
                // Line-level tags are only honoured on the first segment.
                match tag {
                    "noprespace" => line.pre_space = false,
                    "prespace" => line.pre_space = true,
                    "center" => line.align = Align::Center,
                    "right" => line.align = Align::Right,
                    "left" => line.align = Align::Left,
                    _ => {}
                }
            }
        }
    }
}

/// `rgb:R:G:B`, or `rgb:N` where N is an already-packed colour. A component
/// outside 0..255 leaves the colour unchanged, as the client does.
fn parse_rgb(rest: &str) -> Option<i32> {
    let parts: Vec<&str> = rest.split(':').map(|p| p.trim()).collect();
    match parts.len() {
        1 => parts[0].parse::<i32>().ok(),
        _ => {
            let r: i64 = parts.first()?.parse().ok()?;
            let g: i64 = parts.get(1)?.parse().ok()?;
            let b: i64 = parts.get(2)?.parse().ok()?;
            if !(0..=255).contains(&r) || !(0..=255).contains(&g) || !(0..=255).contains(&b) {
                return None;
            }
            Some(super::values::rgb_join(r, g, b))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_text_is_one_default_segment() {
        let line = parse("hello");
        assert_eq!(line.segments.len(), 1);
        assert_eq!(line.segments[0].text, "hello");
        assert_eq!(line.segments[0].font, "Verdana");
        assert_eq!(line.segments[0].size, 10);
        assert!(line.segments[0].bold);
        assert_eq!(line.align, Align::Left);
        assert!(line.pre_space);
    }

    #[test]
    fn a_colour_tag_applies_to_its_segment() {
        let line = parse("{{green}}hello");
        assert_eq!(line.segments[0].color, 0x3DCF44);
        assert_eq!(line.segments[0].text, "hello");
    }

    #[test]
    fn tags_may_appear_after_the_text_they_style() {
        // Scripts routinely write the colour at the end of the line.
        let line = parse("hello{{green}}");
        assert_eq!(line.segments[0].color, 0x3DCF44);
        assert_eq!(line.segments[0].text, "hello");
    }

    #[test]
    fn several_tags_share_one_group() {
        let line = parse("{{red bold 24 impact}}x");
        let s = &line.segments[0];
        assert_eq!(s.color, 0x0000FF);
        assert!(s.bold);
        assert_eq!(s.size, 24);
        assert_eq!(s.font, "Impact");
    }

    #[test]
    fn commas_separate_tags_like_spaces() {
        let line = parse("{{red,bold,24}}x");
        assert_eq!(line.segments[0].size, 24);
        assert_eq!(line.segments[0].color, 0x0000FF);
    }

    #[test]
    fn the_separator_starts_a_freshly_defaulted_segment() {
        let line = parse("{{red}}a{{|}}b");
        assert_eq!(line.segments.len(), 2);
        assert_eq!(line.segments[0].color, 0x0000FF);
        // The second segment does not inherit the first one's colour.
        assert_eq!(line.segments[1].color, 0xFFFFFF);
        assert_eq!(line.text(), "ab");
    }

    #[test]
    fn negations_turn_attributes_back_off() {
        let line = parse("{{nobold italic}}x");
        assert!(!line.segments[0].bold);
        assert!(line.segments[0].italic);
    }

    #[test]
    fn font_size_is_clamped_to_what_the_console_renders() {
        assert_eq!(parse("{{2}}x").segments[0].size, MIN_FONT_SIZE);
        assert_eq!(parse("{{9999}}x").segments[0].size, MAX_FONT_SIZE);
    }

    #[test]
    fn rgb_accepts_components_and_a_packed_value() {
        assert_eq!(parse("{{rgb:255:0:0}}x").segments[0].color, 0x0000FF);
        assert_eq!(parse("{{rgb:6220700}}x").segments[0].color, 6_220_700);
    }

    #[test]
    fn an_out_of_range_rgb_component_leaves_the_colour_alone() {
        assert_eq!(parse("{{rgb:300:0:0}}x").segments[0].color, 0xFFFFFF);
    }

    #[test]
    fn alignment_and_indent_are_line_properties() {
        let line = parse("{{center noprespace}}x");
        assert_eq!(line.align, Align::Center);
        assert!(!line.pre_space);
    }

    #[test]
    fn line_properties_are_ignored_outside_the_first_segment() {
        let line = parse("a{{|}}{{center}}b");
        assert_eq!(line.align, Align::Left, "only the first segment sets alignment");
    }

    #[test]
    fn flash_modes_are_mutually_exclusive() {
        assert_eq!(parse("{{flash}}x").segments[0].flash, Flash::Normal);
        assert_eq!(parse("{{flashfast}}x").segments[0].flash, Flash::Fast);
        assert_eq!(parse("{{flash flashslow}}x").segments[0].flash, Flash::Slow);
        assert_eq!(parse("{{flash noflash}}x").segments[0].flash, Flash::None);
    }

    #[test]
    fn offsets_are_read_as_numbers() {
        let line = parse("{{hoff:12 voff:-3}}x");
        assert_eq!(line.segments[0].h_offset, 12);
        assert_eq!(line.segments[0].v_offset, -3);
    }

    #[test]
    fn escaped_markup_is_shown_rather_than_applied() {
        // `ConsoleEscape` breaks the braces with an invisible character,
        // which the parser drops from the caption without acting on it.
        let escaped = super::super::values::console_escape("{{red}}");
        let line = parse(&escaped);
        assert_eq!(line.text(), "{{red}}");
        assert_eq!(line.segments[0].color, 0xFFFFFF, "the tag did not apply");
    }

    #[test]
    fn output_stops_at_a_newline() {
        assert_eq!(parse("visible\r\nhidden").text(), "visible");
    }

    #[test]
    fn an_unknown_tag_is_ignored() {
        let line = parse("{{notatag}}x");
        assert_eq!(line.text(), "x");
        assert_eq!(line.segments[0].color, 0xFFFFFF);
    }

    #[test]
    fn a_real_startup_line_parses() {
        // From `system/startup.ds`.
        let line = parse(
            "{{center impact nobold 48 lyellow}}[{{|}}{{white impact nobold 48}} D A R K S I G N S {{|}}]{{lyellow impact nobold 48}}",
        );
        assert_eq!(line.align, Align::Center);
        assert_eq!(line.segments.len(), 3);
        assert_eq!(line.text(), "[ D A R K S I G N S ]");
        assert_eq!(line.segments[0].color, 0x80FFFF);
        assert_eq!(line.segments[1].color, 0xFFFFFF);
        assert!(line.segments.iter().all(|s| s.font == "Impact" && s.size == 48 && !s.bold));
    }
}
