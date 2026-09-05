//! The console scripts write to and read from.
//!
//! The desktop client draws a proportional-font terminal, so widths are in
//! pixels and `{{...}}` markup selects fonts and colours. That rendering
//! stays in the client; this trait is the part scripts can see, and
//! [`RecordingConsole`] is a character-cell implementation for tests and
//! headless runs.

use super::values::strip_markup;

/// A horizontal rule's fill style, as `Draw` names them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DrawMode {
    Solid,
    FadeInverse,
    FadeCenter,
    Other(String),
}

impl DrawMode {
    pub fn parse(s: &str) -> DrawMode {
        match s.to_ascii_lowercase().as_str() {
            "solid" => DrawMode::Solid,
            "fadeinverse" => DrawMode::FadeInverse,
            "fadecenter" => DrawMode::FadeCenter,
            other => DrawMode::Other(other.to_string()),
        }
    }
}

/// Where a line of output was sent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Channel {
    /// Ordinary script output.
    Say,
    /// The communications channel, which the client styles differently.
    Comm,
    /// Chat.
    Chat,
}

pub trait Console {
    /// Write a line. `channel` says which stream it belongs to.
    fn say(&mut self, channel: Channel, text: &str);

    /// Write a line at a fixed row, replacing whatever was there.
    fn say_at(&mut self, text: &str, y: i64) {
        let _ = y;
        self.say(Channel::Say, text);
    }

    /// Write a line one character at a time. The delay is per character.
    fn say_slow(&mut self, text: &str, delay_ms: i64, color: &str) {
        let _ = (delay_ms, color);
        self.say(Channel::Say, text);
    }

    /// Erase the console.
    fn clear(&mut self);

    /// Move the cursor up one line, so the next write overwrites it.
    fn line_up(&mut self);

    /// Draw a horizontal rule.
    fn draw(&mut self, y: i64, rgb: i64, mode: DrawMode, segments: i64);

    /// Draw a rule from explicit width/colour pairs.
    fn draw_custom(&mut self, y: i64, widths_and_colors: &[i64]);

    /// Draw a rule split evenly between colours.
    fn draw_even(&mut self, y: i64, colors: &[i64]);

    /// Read a line from the player. Returning `None` means input ended,
    /// which aborts the script.
    fn read_line(&mut self, prompt: &str, rgb: i64) -> Option<String>;

    /// Wait for a single key, returning its virtual-key code.
    fn get_key(&mut self) -> i64;

    /// Wait for a single key, returning its character code.
    fn get_ascii(&mut self) -> i64;

    /// Width of the console's text area, in the same units as
    /// [`Console::text_width`].
    fn console_width(&self) -> i64;

    /// Width of the indent the console puts before each line.
    fn pre_space_width(&self) -> i64;

    /// Width of `text` once its markup is applied.
    fn text_width(&self, text: &str) -> i64;

    /// Height of `text` once its markup is applied.
    fn text_height(&self, text: &str) -> i64;

    /// Set the vertical divider position.
    fn set_y_div(&mut self, value: i64) {
        let _ = value;
    }

    /// Open the editor on a file.
    fn edit(&mut self, path: &str) {
        let _ = path;
    }

    /// Run a music command.
    fn music(&mut self, command: &str) {
        let _ = command;
    }

    /// Open the mail window.
    fn mail(&mut self) {}

    /// Show or hide chat.
    fn set_chat_visible(&mut self, visible: bool) {
        let _ = visible;
    }
}

/// One thing a script did to the console, kept so tests can assert on it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConsoleEvent {
    Say { channel: Channel, text: String },
    SayAt { text: String, y: i64 },
    Clear,
    LineUp,
    Draw { y: i64, rgb: i64, mode: DrawMode, segments: i64 },
    DrawCustom { y: i64, values: Vec<i64> },
    DrawEven { y: i64, colors: Vec<i64> },
    Edit(String),
    Music(String),
    Mail,
    ChatVisible(bool),
    YDiv(i64),
}

/// A console that records what it was told and replays queued input.
///
/// Widths are counted in characters, which is what a fixed-pitch terminal
/// gives; the desktop client overrides them with real font metrics.
#[derive(Default)]
pub struct RecordingConsole {
    pub events: Vec<ConsoleEvent>,
    /// Lines handed to `ReadLine`, oldest first.
    pub input: std::collections::VecDeque<String>,
    /// Key codes handed to `GetKey` and `GetASCII`.
    pub keys: std::collections::VecDeque<i64>,
    pub width: i64,
}

impl RecordingConsole {
    pub fn new() -> RecordingConsole {
        RecordingConsole { width: 80, ..Default::default() }
    }

    /// Queue lines for the script to read.
    pub fn with_input<I: IntoIterator<Item = S>, S: Into<String>>(mut self, lines: I) -> Self {
        self.input.extend(lines.into_iter().map(Into::into));
        self
    }

    pub fn with_keys<I: IntoIterator<Item = i64>>(mut self, keys: I) -> Self {
        self.keys.extend(keys);
        self
    }

    /// Everything written to the main channel, in order.
    pub fn output(&self) -> Vec<String> {
        self.events
            .iter()
            .filter_map(|e| match e {
                ConsoleEvent::Say { channel: Channel::Say, text } => Some(text.clone()),
                ConsoleEvent::SayAt { text, .. } => Some(text.clone()),
                _ => None,
            })
            .collect()
    }

    /// The main channel's output with markup removed and lines joined.
    pub fn plain_output(&self) -> String {
        self.output()
            .iter()
            .map(|l| strip_markup(l))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

impl Console for RecordingConsole {
    fn say(&mut self, channel: Channel, text: &str) {
        self.events.push(ConsoleEvent::Say { channel, text: text.into() });
    }
    fn say_at(&mut self, text: &str, y: i64) {
        self.events.push(ConsoleEvent::SayAt { text: text.into(), y });
    }
    fn clear(&mut self) {
        self.events.push(ConsoleEvent::Clear);
    }
    fn line_up(&mut self) {
        self.events.push(ConsoleEvent::LineUp);
    }
    fn draw(&mut self, y: i64, rgb: i64, mode: DrawMode, segments: i64) {
        self.events.push(ConsoleEvent::Draw { y, rgb, mode, segments });
    }
    fn draw_custom(&mut self, y: i64, widths_and_colors: &[i64]) {
        self.events
            .push(ConsoleEvent::DrawCustom { y, values: widths_and_colors.to_vec() });
    }
    fn draw_even(&mut self, y: i64, colors: &[i64]) {
        self.events.push(ConsoleEvent::DrawEven { y, colors: colors.to_vec() });
    }
    fn read_line(&mut self, prompt: &str, _rgb: i64) -> Option<String> {
        if !prompt.is_empty() {
            self.say(Channel::Say, prompt);
        }
        self.input.pop_front()
    }
    fn get_key(&mut self) -> i64 {
        self.keys.pop_front().unwrap_or(0)
    }
    fn get_ascii(&mut self) -> i64 {
        self.keys.pop_front().unwrap_or(0)
    }
    fn console_width(&self) -> i64 {
        self.width
    }
    fn pre_space_width(&self) -> i64 {
        0
    }
    fn text_width(&self, text: &str) -> i64 {
        strip_markup(text).chars().count() as i64
    }
    fn text_height(&self, _text: &str) -> i64 {
        1
    }
    fn set_y_div(&mut self, value: i64) {
        self.events.push(ConsoleEvent::YDiv(value));
    }
    fn edit(&mut self, path: &str) {
        self.events.push(ConsoleEvent::Edit(path.into()));
    }
    fn music(&mut self, command: &str) {
        self.events.push(ConsoleEvent::Music(command.into()));
    }
    fn mail(&mut self) {
        self.events.push(ConsoleEvent::Mail);
    }
    fn set_chat_visible(&mut self, visible: bool) {
        self.events.push(ConsoleEvent::ChatVisible(visible));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_output_per_channel() {
        let mut c = RecordingConsole::new();
        c.say(Channel::Say, "hello");
        c.say(Channel::Comm, "system");
        assert_eq!(c.output(), vec!["hello"], "only the main channel");
        assert_eq!(c.events.len(), 2, "but both are recorded");
    }

    #[test]
    fn measures_text_without_its_markup() {
        let c = RecordingConsole::new();
        assert_eq!(c.text_width("hello"), 5);
        assert_eq!(c.text_width("{{red}}hello{{white}}"), 5);
        assert_eq!(c.text_width(""), 0);
    }

    #[test]
    fn replays_queued_input_then_reports_end() {
        let mut c = RecordingConsole::new().with_input(["one", "two"]);
        assert_eq!(c.read_line("", -1).as_deref(), Some("one"));
        assert_eq!(c.read_line("", -1).as_deref(), Some("two"));
        assert_eq!(c.read_line("", -1), None, "input runs out");
    }

    #[test]
    fn a_prompt_is_written_before_reading() {
        let mut c = RecordingConsole::new().with_input(["x"]);
        c.read_line("Name?", -1);
        assert_eq!(c.output(), vec!["Name?"]);
    }

    #[test]
    fn draw_modes_parse_by_name() {
        assert_eq!(DrawMode::parse("solid"), DrawMode::Solid);
        assert_eq!(DrawMode::parse("FadeCenter"), DrawMode::FadeCenter);
        assert_eq!(DrawMode::parse("wobble"), DrawMode::Other("wobble".into()));
    }

    #[test]
    fn plain_output_strips_markup_and_joins_lines() {
        let mut c = RecordingConsole::new();
        c.say(Channel::Say, "{{green}}a");
        c.say(Channel::Say, "b{{white}}");
        assert_eq!(c.plain_output(), "a\nb");
    }
}
