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
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
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

/// Custom log event formatter enforcing the 16-color ANSI level roles with zero magenta.
#[derive(Debug, Clone, Copy)]
pub struct FragrFormatter {
    pub ansi: bool,
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

/// Initialize tracing with the custom formatter, color gating, and the provided default filter.
pub fn init_logging_with_default(default_filter: &str, color: ColorChoice) {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(default_filter));
    let use_ansi = color.resolve();
    tracing_subscriber::fmt()
        .with_ansi(use_ansi)
        .event_format(FragrFormatter { ansi: use_ansi })
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .init();
}

/// Initialize server tracing for quiet (bench/preview) or standard operation.
pub fn init_logging(quiet: bool, color: ColorChoice) {
    let default = if quiet {
        "warn"
    } else {
        "info,fragr_server=debug"
    };
    init_logging_with_default(default, color);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_color_precedence() {
        // Explicit always wins over NO_COLOR
        let mut env = HashMap::new();
        env.insert("NO_COLOR".to_string(), "1".to_string());
        assert!(resolve_color_with(ColorChoice::Always, |k| env.get(k).cloned(), false));

        // Explicit never wins over FORCE_COLOR
        let mut env = HashMap::new();
        env.insert("FORCE_COLOR".to_string(), "1".to_string());
        assert!(!resolve_color_with(ColorChoice::Never, |k| env.get(k).cloned(), true));

        // Auto with NO_COLOR set
        let mut env = HashMap::new();
        env.insert("NO_COLOR".to_string(), "1".to_string());
        assert!(!resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), true));

        // Auto with empty NO_COLOR does not disable color
        let mut env = HashMap::new();
        env.insert("NO_COLOR".to_string(), "".to_string());
        assert!(resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), true));

        // Auto with FORCE_COLOR=1 enables color even when not a terminal
        let mut env = HashMap::new();
        env.insert("FORCE_COLOR".to_string(), "1".to_string());
        assert!(resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), false));

        // Auto with FORCE_COLOR=0 does not force color
        let mut env = HashMap::new();
        env.insert("FORCE_COLOR".to_string(), "0".to_string());
        assert!(!resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), false));

        // Auto with TERM=dumb disables color
        let mut env = HashMap::new();
        env.insert("TERM".to_string(), "dumb".to_string());
        assert!(!resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), true));

        // Auto on terminal without env vars enables color
        let env: HashMap<String, String> = HashMap::new();
        assert!(resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), true));

        // Auto without terminal disables color
        let env: HashMap<String, String> = HashMap::new();
        assert!(!resolve_color_with(ColorChoice::Auto, |k| env.get(k).cloned(), false));
    }
}
