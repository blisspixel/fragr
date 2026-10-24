//! Terminal logging configuration, color gating, and ANSI level styling.

use std::fmt;
use std::io::IsTerminal;
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::fmt::{
    format::Writer, time::FormatTime, FmtContext, FormatEvent, FormatFields, FormattedFields,
};
use tracing_subscriber::registry::LookupSpan;
use tracing_subscriber::EnvFilter;

/// Color mode for command-line log output.
#[derive(
    clap::ValueEnum,
    Clone,
    Copy,
    Debug,
    PartialEq,
    Eq,
    Default,
    serde::Serialize,
    serde::Deserialize,
)]
#[serde(rename_all = "kebab-case")]
pub enum ColorChoice {
    #[default]
    Auto,
    Always,
    Never,
}

impl ColorChoice {
    /// Resolve whether ANSI color escape sequences should be emitted.
    pub fn resolve(self) -> bool {
        resolve_color_with(
            self,
            |var| std::env::var_os(var).map(|s| s.to_string_lossy().into_owned()),
            std::io::stderr().is_terminal(),
        )
    }
}

/// Resolve color choice against environment variables and terminal status.
///
/// Precedence:
/// 1. Explicit `always` -> true.
/// 2. Explicit `never` -> false.
/// 3. `auto`:
///    - `NO_COLOR` set and non-empty -> false.
///    - `FORCE_COLOR` set, non-empty, and != "0" -> true.
///    - `TERM == "dumb"` -> false.
///    - `is_terminal` -> true if terminal, else false.
pub fn resolve_color_with<F>(choice: ColorChoice, get_env: F, is_terminal: bool) -> bool
where
    F: Fn(&str) -> Option<String>,
{
    match choice {
        ColorChoice::Always => true,
        ColorChoice::Never => false,
        ColorChoice::Auto => {
            if let Some(val) = get_env("NO_COLOR") {
                if !val.is_empty() {
                    return false;
                }
            }
            if let Some(val) = get_env("FORCE_COLOR") {
                if !val.is_empty() && val != "0" {
                    return true;
                }
            }
            if let Some(val) = get_env("TERM") {
                if val == "dumb" {
                    return false;
                }
            }
            is_terminal
        }
    }
}

/// Routine match feed: frags, pickups, bot spawns, Host reactions and similar
/// play-by-play. The text is unchanged; only the target separates it so the
/// operator overview can leave it out while a log keeps it.
pub const FEED_TARGET: &str = "fragr_server::feed";

/// Startup narrative that the operator overview's ready card summarises.
/// Warnings on this target still print in every mode.
pub const STARTUP_TARGET: &str = "fragr_server::startup";

/// Default filter for the full log stream (unchanged from #415).
pub const LOG_FILTER: &str = "info,fragr_server=debug";

/// Default filter for the operator overview. `RUST_LOG` still replaces it.
pub const OVERVIEW_FILTER: &str =
    "warn,fragr_server=info,fragr_server::feed=warn,fragr_server::startup=warn";

/// What a dedicated server writes to its terminal.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum OutputMode {
    /// Overview on an interactive terminal, the full log anywhere else.
    #[default]
    Auto,
    /// Ready card, one-line pulses, and notable events only.
    Overview,
    /// Every event line and the STATUS JSON, as before.
    Log,
}

impl OutputMode {
    /// True when this process should present the operator overview.
    pub fn resolve_overview(self) -> bool {
        resolve_overview_with(
            self,
            |var| std::env::var_os(var).map(|s| s.to_string_lossy().into_owned()),
            std::io::stdout().is_terminal(),
            std::io::stderr().is_terminal(),
        )
    }
}

/// `auto` presents the overview only when a person is plausibly reading both
/// streams: stdout and stderr are terminals and `TERM` is not `dumb`. Pipes,
/// redirected files, services and containers without a TTY keep the log.
/// `NO_COLOR` is about colour, not layout, and does not change this.
pub fn resolve_overview_with<F>(
    mode: OutputMode,
    get_env: F,
    stdout_terminal: bool,
    stderr_terminal: bool,
) -> bool
where
    F: Fn(&str) -> Option<String>,
{
    match mode {
        OutputMode::Overview => true,
        OutputMode::Log => false,
        OutputMode::Auto => {
            stdout_terminal && stderr_terminal && get_env("TERM").as_deref() != Some("dumb")
        }
    }
}

/// Whether escape sequences may be written to a stream with this terminal
/// state. On Windows a classic console shows raw `ESC[` text unless virtual
/// terminal processing is on, so `auto` asks the console first and falls back
/// to plain text when it refuses. An explicit `always` keeps colour.
pub fn ansi_for_stream(choice: ColorChoice, is_terminal: bool) -> bool {
    let wanted = resolve_color_with(
        choice,
        |var| std::env::var_os(var).map(|s| s.to_string_lossy().into_owned()),
        is_terminal,
    );
    wanted && (choice == ColorChoice::Always || console_accepts_ansi())
}

#[cfg(windows)]
fn console_accepts_ansi() -> bool {
    nu_ansi_term::enable_ansi_support().is_ok()
}

#[cfg(not(windows))]
fn console_accepts_ansi() -> bool {
    true
}

/// `+HH:MM:SS` since process start; hours grow past two digits on long nights.
pub fn uptime_stamp(uptime: std::time::Duration) -> String {
    let total = uptime.as_secs();
    format!(
        "+{:02}:{:02}:{:02}",
        total / 3600,
        (total / 60) % 60,
        total % 60
    )
}

/// Custom log event formatter enforcing the 16-color ANSI level roles with zero magenta.
/// `compact` is the operator overview line: process uptime, a level word only
/// for warnings and errors, and no module target.
#[derive(Debug, Clone, Copy)]
pub struct FragrFormatter {
    pub ansi: bool,
    pub compact: bool,
}

impl<S, N> FormatEvent<S, N> for FragrFormatter
where
    S: Subscriber + for<'a> LookupSpan<'a>,
    N: for<'a> FormatFields<'a> + 'static,
{
    fn format_event(
        &self,
        ctx: &FmtContext<'_, S, N>,
        mut writer: Writer<'_>,
        event: &Event<'_>,
    ) -> fmt::Result {
        if self.compact {
            return format_compact(self.ansi, ctx, writer, event);
        }
        let meta = event.metadata();
        let ansi = self.ansi;

        if ansi {
            write!(writer, "\x1b[2m")?;
            let _ = tracing_subscriber::fmt::time::SystemTime.format_time(&mut writer);
            write!(writer, "\x1b[0m ")?;
        } else {
            let _ = tracing_subscriber::fmt::time::SystemTime.format_time(&mut writer);
            write!(writer, " ")?;
        }

        if ansi {
            match *meta.level() {
                Level::ERROR => write!(writer, "\x1b[31mERROR\x1b[0m ")?,
                Level::WARN => write!(writer, "\x1b[33m WARN\x1b[0m ")?,
                Level::INFO => write!(writer, "\x1b[32m INFO\x1b[0m ")?,
                Level::DEBUG => write!(writer, "\x1b[2mDEBUG\x1b[0m ")?,
                Level::TRACE => write!(writer, "\x1b[2mTRACE\x1b[0m ")?,
            }
        } else {
            match *meta.level() {
                Level::ERROR => write!(writer, "ERROR ")?,
                Level::WARN => write!(writer, " WARN ")?,
                Level::INFO => write!(writer, " INFO ")?,
                Level::DEBUG => write!(writer, "DEBUG ")?,
                Level::TRACE => write!(writer, "TRACE ")?,
            }
        }

        if let Some(scope) = ctx.event_scope() {
            let mut seen = false;
            for span in scope.from_root() {
                if ansi {
                    write!(writer, "\x1b[1m{}\x1b[0m", span.metadata().name())?;
                } else {
                    write!(writer, "{}", span.metadata().name())?;
                }
                seen = true;

                let ext = span.extensions();
                if let Some(fields) = ext.get::<FormattedFields<N>>() {
                    if !fields.is_empty() {
                        if ansi {
                            write!(writer, "\x1b[1m{{\x1b[0m{}\x1b[1m}}\x1b[0m", fields)?;
                        } else {
                            write!(writer, "{{{}}}", fields)?;
                        }
                    }
                }
                if ansi {
                    write!(writer, "\x1b[2m:\x1b[0m")?;
                } else {
                    write!(writer, ":")?;
                }
            }
            if seen {
                write!(writer, " ")?;
            }
        }

        if ansi {
            write!(writer, "\x1b[2m{}\x1b[0m\x1b[2m:\x1b[0m ", meta.target())?;
        } else {
            write!(writer, "{}: ", meta.target())?;
        }

        ctx.format_fields(writer.by_ref(), event)?;

        writeln!(writer)
    }
}

fn format_compact<S, N>(
    ansi: bool,
    ctx: &FmtContext<'_, S, N>,
    mut writer: Writer<'_>,
    event: &Event<'_>,
) -> fmt::Result
where
    S: Subscriber + for<'a> LookupSpan<'a>,
    N: for<'a> FormatFields<'a> + 'static,
{
    let stamp = uptime_stamp(crate::metrics::process_uptime());
    if ansi {
        write!(writer, "\x1b[2m{stamp}\x1b[0m ")?;
    } else {
        write!(writer, "{stamp} ")?;
    }
    match (*event.metadata().level(), ansi) {
        (Level::ERROR, true) => write!(writer, "\x1b[31mERROR\x1b[0m ")?,
        (Level::WARN, true) => write!(writer, "\x1b[33mWARN\x1b[0m ")?,
        (Level::ERROR, false) => write!(writer, "ERROR ")?,
        (Level::WARN, false) => write!(writer, "WARN ")?,
        _ => {}
    }
    if let Some(scope) = ctx.event_scope() {
        for span in scope.from_root() {
            write!(writer, "{}: ", span.metadata().name())?;
        }
    }
    ctx.format_fields(writer.by_ref(), event)?;
    writeln!(writer)
}

/// Initialize tracing with the custom formatter, color gating, and the provided default filter.
pub fn init_logging_with_default(default_filter: &str, color: ColorChoice) {
    init_logging_with(default_filter, color, false);
}

fn init_logging_with(default_filter: &str, color: ColorChoice, compact: bool) {
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default_filter));
    let use_ansi = ansi_for_stream(color, std::io::stderr().is_terminal());
    tracing_subscriber::fmt()
        .with_ansi(use_ansi)
        .event_format(FragrFormatter {
            ansi: use_ansi,
            compact,
        })
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .init();
}

/// Initialize server tracing for quiet (bench/preview) or standard operation.
pub fn init_logging(quiet: bool, color: ColorChoice) {
    let default = if quiet { "warn" } else { LOG_FILTER };
    init_logging_with_default(default, color);
}

/// Operator overview: routine feed and startup narrative stay out, lines are compact.
pub fn init_overview_logging(color: ColorChoice) {
    init_logging_with(OVERVIEW_FILTER, color, true);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct Capture(Arc<Mutex<Vec<u8>>>);

    impl std::io::Write for Capture {
        fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(buf);
            Ok(buf.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    /// Emit one line of each audience through the real filter and formatter.
    fn capture(filter: &str, ansi: bool, compact: bool) -> String {
        let sink = Capture::default();
        let writer = sink.clone();
        let subscriber = tracing_subscriber::fmt()
            .with_ansi(ansi)
            .event_format(FragrFormatter { ansi, compact })
            .with_env_filter(EnvFilter::new(filter))
            .with_writer(move || writer.clone())
            .finish();
        tracing::subscriber::with_default(subscriber, || {
            tracing::info!(target: FEED_TARGET, "FRAG: Dan -> Linda (score: 1)");
            tracing::info!(target: FEED_TARGET, "PICKUP: Kid claimed Flechette");
            tracing::warn!(target: FEED_TARGET, "feed warning stays");
            tracing::info!(target: STARTUP_TARGET, "Map: Arena Duel (id 1)");
            tracing::warn!(target: STARTUP_TARGET, "Join check did not answer");
            tracing::info!(target: "fragr_server::session", "Player joined as Human");
            tracing::info!(target: "fragr_server::run", "STATUS {{\"ticks\":1}}");
            tracing::debug!(target: "fragr_server::net", "New connection from 127.0.0.1");
            tracing::info!(target: "fragr_server::audit", event = "reject", code = "banned");
            tracing::info!(target: "tokio_tungstenite", "library chatter");
            tracing::error!(target: "fragr_server::run", "bind failed");
        });
        let bytes = sink.0.lock().unwrap().clone();
        String::from_utf8(bytes).unwrap()
    }

    #[test]
    fn overview_filter_keeps_notable_lines_and_drops_routine_feed() {
        let text = capture(OVERVIEW_FILTER, false, true);
        for kept in [
            "feed warning stays",
            "WARN Join check did not answer",
            "Player joined as Human",
            "event=\"reject\"",
            "ERROR bind failed",
        ] {
            assert!(text.contains(kept), "missing {kept:?} in\n{text}");
        }
        for dropped in [
            "FRAG:",
            "PICKUP:",
            "Map: Arena Duel",
            "New connection",
            "library chatter",
        ] {
            assert!(!text.contains(dropped), "{dropped:?} leaked into\n{text}");
        }
        assert!(!text.contains('\x1b'), "no escapes without colour:\n{text}");
        for line in text.lines() {
            assert!(line.starts_with('+'), "uptime stamp first: {line}");
            assert!(!line.contains("fragr_server::"), "no module target: {line}");
            assert!(!line.contains(" INFO "), "no info level word: {line}");
        }
    }

    #[test]
    fn log_filter_still_prints_every_event_with_targets() {
        let text = capture(LOG_FILTER, false, false);
        for kept in [
            "INFO fragr_server::feed: FRAG: Dan -> Linda (score: 1)",
            "fragr_server::feed: PICKUP: Kid claimed Flechette",
            "fragr_server::startup: Map: Arena Duel (id 1)",
            "DEBUG fragr_server::net: New connection from 127.0.0.1",
            "STATUS {\"ticks\":1}",
            "library chatter",
        ] {
            assert!(text.contains(kept), "missing {kept:?} in\n{text}");
        }
        assert!(!text.contains('\x1b'), "{text}");
        let coloured = capture(LOG_FILTER, true, false);
        assert!(coloured.contains("\x1b[32m INFO\x1b[0m"), "{coloured}");
        let compact = capture(OVERVIEW_FILTER, true, true);
        assert!(compact.contains("\x1b[33mWARN\x1b[0m"), "{compact}");
        assert!(compact.contains("\x1b[31mERROR\x1b[0m"), "{compact}");
        assert!(!compact.contains("\x1b[35m"), "no magenta");
    }

    #[test]
    fn output_auto_needs_two_terminals_and_a_capable_term() {
        let none: HashMap<String, String> = HashMap::new();
        let dumb: HashMap<String, String> =
            HashMap::from([("TERM".to_string(), "dumb".to_string())]);
        let no_color: HashMap<String, String> =
            HashMap::from([("NO_COLOR".to_string(), "1".to_string())]);
        let auto = |env: &HashMap<String, String>, out: bool, err: bool| {
            resolve_overview_with(OutputMode::Auto, |k| env.get(k).cloned(), out, err)
        };
        assert!(auto(&none, true, true));
        assert!(!auto(&none, false, true), "stdout redirected");
        assert!(!auto(&none, true, false), "stderr redirected");
        assert!(!auto(&none, false, false), "service or pipe");
        assert!(!auto(&dumb, true, true), "TERM=dumb");
        assert!(auto(&no_color, true, true), "NO_COLOR is colour only");
        assert!(resolve_overview_with(
            OutputMode::Overview,
            |k| dumb.get(k).cloned(),
            false,
            false
        ));
        assert!(!resolve_overview_with(
            OutputMode::Log,
            |k| none.get(k).cloned(),
            true,
            true
        ));
        assert_eq!(OutputMode::default(), OutputMode::Auto);
    }

    #[test]
    fn uptime_stamp_is_fixed_width_until_a_long_night() {
        use std::time::Duration;
        assert_eq!(uptime_stamp(Duration::ZERO), "+00:00:00");
        assert_eq!(uptime_stamp(Duration::from_millis(3_723_900)), "+01:02:03");
        assert_eq!(uptime_stamp(Duration::from_secs(100 * 3600)), "+100:00:00");
    }

    #[test]
    fn stream_gate_follows_the_colour_choice_on_this_platform() {
        assert!(!ansi_for_stream(ColorChoice::Never, true));
        assert!(ansi_for_stream(ColorChoice::Always, false));
    }

    #[test]
    fn test_color_precedence() {
        // Explicit always wins over NO_COLOR
        let mut env = HashMap::new();
        env.insert("NO_COLOR".to_string(), "1".to_string());
        assert!(resolve_color_with(
            ColorChoice::Always,
            |k| env.get(k).cloned(),
            false
        ));

        // Explicit never wins over FORCE_COLOR
        let mut env = HashMap::new();
        env.insert("FORCE_COLOR".to_string(), "1".to_string());
        assert!(!resolve_color_with(
            ColorChoice::Never,
            |k| env.get(k).cloned(),
            true
        ));

        // Auto with NO_COLOR set
        let mut env = HashMap::new();
        env.insert("NO_COLOR".to_string(), "1".to_string());
        assert!(!resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            true
        ));

        // Auto with empty NO_COLOR does not disable color
        let mut env = HashMap::new();
        env.insert("NO_COLOR".to_string(), "".to_string());
        assert!(resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            true
        ));

        // Auto with FORCE_COLOR=1 enables color even when not a terminal
        let mut env = HashMap::new();
        env.insert("FORCE_COLOR".to_string(), "1".to_string());
        assert!(resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            false
        ));

        // Auto with FORCE_COLOR=0 does not force color
        let mut env = HashMap::new();
        env.insert("FORCE_COLOR".to_string(), "0".to_string());
        assert!(!resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            false
        ));

        // Auto with TERM=dumb disables color
        let mut env = HashMap::new();
        env.insert("TERM".to_string(), "dumb".to_string());
        assert!(!resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            true
        ));

        // Auto on terminal without env vars enables color
        let env: HashMap<String, String> = HashMap::new();
        assert!(resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            true
        ));

        // Auto without terminal disables color
        let env: HashMap<String, String> = HashMap::new();
        assert!(!resolve_color_with(
            ColorChoice::Auto,
            |k| env.get(k).cloned(),
            false
        ));
    }
}
