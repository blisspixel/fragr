//! Command line for the decision-brain agent.
//!
//! `play` joins a server and fights; `ask` sends one decision for a state you
//! type (or prints the request with `--dry-run`); `spend` shows the ledger;
//! `key` reads an OpenRouter key's own limit. Paid providers refuse to start
//! until `--max-spend-usd` names a cap. The free local model providers
//! (`ollama`, `openjev`) need no key and no cap, and talk to loopback only
//! unless `--allow-remote-model` is given.

use clap::{Args, Parser, Subcommand};
use fragr_brain::bot::{run_bot, BotConfig};
use fragr_brain::budget::{Budget, Caps, Pricing};
use fragr_brain::decision::{tactical_questions, Gate};
use fragr_brain::dotenv::resolve_key;
use fragr_brain::local_model;
use fragr_brain::provider::{
    decide, decision_request, key_request, parse_key_status, HttpTransport, Provider, Transport,
};
use fragr_brain::Error;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(
    name = "fragr-brain",
    version,
    about = "A fragr agent whose intent comes from a decision model (TypeSafe Jev, natively or through OpenRouter) under a hard spend cap, or from a free open-weights decision model on this machine; local rules play for free."
)]
struct Cli {
    #[command(flatten)]
    common: Common,
    #[command(subcommand)]
    command: Command,
}

#[derive(Args, Debug, Clone)]
struct Common {
    /// Decision source: local (free rules, default), ollama (free local
    /// APUS-OpenJev), openjev (free self-hosted server, non-commercial
    /// weights), typesafe, or openrouter.
    #[arg(long, default_value = "local", global = true)]
    provider: String,
    /// Model id; defaults to jev-1.13.0 (typesafe), typesafe/jev-1.13
    /// (openrouter), hf.co/apus-ailab/APUS-OpenJev-v1-4B-GGUF:Q8_0 (ollama) or
    /// openjev (openjev).
    #[arg(long, global = true)]
    model: Option<String>,
    /// Base URL of a local model server; defaults to http://127.0.0.1:11434
    /// (ollama) or http://127.0.0.1:3000 (openjev). Loopback only by default.
    #[arg(long, global = true)]
    model_url: Option<String>,
    /// Allow a local model provider to reach a non-loopback host.
    #[arg(long, global = true)]
    allow_remote_model: bool,
    /// Dollars this run may spend. Zero (the default) means no paid call at all.
    #[arg(long, default_value_t = 0.0, global = true)]
    max_spend_usd: f64,
    /// Dollars the ledger may reach across every run.
    #[arg(long, global = true)]
    max_total_usd: Option<f64>,
    /// Paid calls this run may make, whatever they cost.
    #[arg(long, global = true)]
    max_calls: Option<u64>,
    /// Ledger of every paid call; totals carry across runs.
    #[arg(long, default_value = ".agents/spend/brain.jsonl", global = true)]
    ledger: PathBuf,
    /// Keep the ledger in memory for free play, key checks or dry runs only.
    #[arg(long, global = true)]
    no_ledger: bool,
    /// Dollars per million input tokens used for estimates and settlement.
    #[arg(long, default_value_t = fragr_brain::budget::JEV_INPUT_PER_MILLION, global = true)]
    price_input_per_million: f64,
    /// Dollars per million output tokens.
    #[arg(long, default_value_t = fragr_brain::budget::JEV_OUTPUT_PER_MILLION, global = true)]
    price_output_per_million: f64,
    /// Read keys from this .env file when the environment has none.
    #[arg(long, default_value = ".env", global = true)]
    env_file: PathBuf,
    /// Read the key from this file instead of the environment.
    #[arg(long, global = true)]
    api_key_file: Option<PathBuf>,
    /// Per-call HTTP timeout; for a local model, the budget for the whole
    /// decision, every question included. Late answers fall back to rules.
    #[arg(long, default_value_t = 2000, global = true)]
    timeout_ms: u64,
}

#[derive(Subcommand, Debug, Clone)]
enum Command {
    /// Join a server as an agent and fight.
    Play {
        #[arg(long, default_value = "ws://127.0.0.1:6767")]
        server: String,
        /// Display name; falls back to FRAGR_AGENT_NAME, then "Brain".
        #[arg(long)]
        name: Option<String>,
        /// Decisions per second (0.1 to 5).
        #[arg(long, default_value_t = 3.0)]
        decision_hz: f64,
        /// Accept an answer whose top option leads the runner-up by at least this.
        #[arg(long, default_value_t = 0.2)]
        margin_floor: f64,
        /// Also accept an answer whose reported confidence reaches this.
        #[arg(long, default_value_t = 0.65)]
        confidence_floor: f64,
        /// Leave after this many seconds.
        #[arg(long)]
        max_seconds: Option<u64>,
        /// Save a bounded campaign trace for local diagnosis.
        #[arg(long)]
        timeline_path: Option<PathBuf>,
    },
    /// Send one decision for a state string and print the answers.
    Ask {
        /// The state text; use the same line format the bot sends.
        #[arg(long)]
        state: String,
        /// Print the request (token masked) and the estimate, send nothing.
        #[arg(long)]
        dry_run: bool,
    },
    /// Print the ledger totals.
    Spend,
    /// Print the calling key's limit and usage (OpenRouter).
    Key,
}

fn parse_provider(text: &str) -> Result<Provider, Error> {
    Provider::parse(text).ok_or_else(|| {
        Error::InvalidArgument(format!(
            "unknown provider {text:?}; use local, ollama, openjev, typesafe, or openrouter"
        ))
    })
}

fn budget_from(common: &Common, provider: Provider) -> Result<Budget, Error> {
    let caps = Caps {
        run_usd: common.max_spend_usd,
        total_usd: common.max_total_usd,
        run_calls: common.max_calls,
    };
    caps.validate()?;
    let pricing = Pricing {
        input_per_million: common.price_input_per_million,
        output_per_million: common.price_output_per_million,
    };
    pricing.validate()?;
    if provider.is_paid() && pricing.input_per_million <= 0.0 && caps.run_calls.is_none() {
        return Err(Error::InvalidArgument(
            "a zero input price would disable the dollar cap; pass --max-calls as well".to_string(),
        ));
    }
    if common.no_ledger {
        Ok(Budget::new(caps, pricing))
    } else {
        Budget::with_ledger(caps, pricing, &common.ledger)
    }
}

fn key_for(common: &Common, provider: Provider) -> Result<Option<String>, Error> {
    if !provider.is_paid() {
        return Ok(None);
    }
    let env = |name: &str| std::env::var(name).ok();
    resolve_key(
        provider.key_names(),
        &env,
        Some(&common.env_file),
        common.api_key_file.as_deref(),
    )
}

fn require_key(common: &Common, provider: Provider) -> Result<String, Error> {
    key_for(common, provider)?.ok_or_else(|| Error::MissingApiKey(provider.key_names().join(", ")))
}

/// The checked base URL of a local model provider, `None` for the others.
fn model_url_for(common: &Common, provider: Provider) -> Result<Option<String>, Error> {
    let Some(default) = provider.default_base_url() else {
        return Ok(None);
    };
    let url = common.model_url.as_deref().unwrap_or(default);
    local_model::checked_base_url(url, common.allow_remote_model).map(Some)
}

fn decision_budget(common: &Common) -> Result<Duration, Error> {
    if common.timeout_ms == 0 {
        return Err(Error::InvalidArgument(
            "--timeout-ms must be above zero".to_string(),
        ));
    }
    Ok(Duration::from_millis(common.timeout_ms))
}

fn resolve_name(name: Option<&str>, fallback: &str) -> String {
    name.map(str::trim)
        .filter(|n| !n.is_empty())
        .map(str::to_string)
        .or_else(|| {
            std::env::var("FRAGR_AGENT_NAME")
                .ok()
                .filter(|n| !n.trim().is_empty())
        })
        .unwrap_or_else(|| fallback.to_string())
}

fn run(cli: Cli, transport: Arc<dyn Transport>, out: &mut dyn std::io::Write) -> Result<(), Error> {
    let provider = parse_provider(&cli.common.provider)?;
    let model = cli
        .common
        .model
        .clone()
        .unwrap_or_else(|| provider.default_model().to_string());
    match cli.command {
        Command::Play {
            server,
            name,
            decision_hz,
            margin_floor,
            confidence_floor,
            max_seconds,
            timeline_path,
        } => {
            let mut budget = budget_from(&cli.common, provider)?;
            if provider.is_paid() {
                budget.check(0.0)?;
            }
            for (name, value) in [
                ("--decision-hz", decision_hz),
                ("--margin-floor", margin_floor),
                ("--confidence-floor", confidence_floor),
            ] {
                if !value.is_finite() || value < 0.0 {
                    return Err(Error::InvalidArgument(format!(
                        "{name} must be a finite non-negative number, got {value}"
                    )));
                }
            }
            let api_key = key_for(&cli.common, provider)?;
            if provider.is_paid() && api_key.is_none() {
                return Err(Error::MissingApiKey(provider.key_names().join(", ")));
            }
            if provider.is_paid() && cli.common.no_ledger {
                return Err(Error::InvalidArgument(
                    "paid play requires a durable ledger; remove --no-ledger".into(),
                ));
            }
            let model_url = model_url_for(&cli.common, provider)?;
            let budget_time = decision_budget(&cli.common)?;
            if let (Provider::Ollama, Some(url)) = (provider, model_url.as_deref()) {
                tracing::info!("loading {model} in Ollama at {url}");
                local_model::warm_up(transport.as_ref(), url, &model)?;
            }
            let config = BotConfig {
                server_url: server,
                name: resolve_name(name.as_deref(), "Brain"),
                provider,
                model,
                api_key,
                model_url,
                decision_budget: budget_time,
                decision_hz,
                gate: Gate {
                    confidence_floor,
                    margin_floor,
                },
                max_seconds,
                timeline_path,
            };
            let budget = Arc::new(Mutex::new(budget));
            let runtime = tokio::runtime::Runtime::new()
                .map_err(|err| Error::Transport(format!("runtime: {err}")))?;
            let summary = runtime.block_on(run_bot(
                config,
                transport,
                budget,
                Arc::new(AtomicBool::new(false)),
            ))?;
            let text = serde_json::to_string_pretty(&summary)
                .map_err(|err| Error::Malformed(err.to_string()))?;
            writeln!(out, "{text}")?;
            Ok(())
        }
        Command::Ask { state, dry_run } if provider.is_local_model() => {
            let url = model_url_for(&cli.common, provider)?.unwrap_or_default();
            let budget_time = decision_budget(&cli.common)?;
            let state = state_value(state);
            let questions = tactical_questions();
            if dry_run {
                let requests: Vec<serde_json::Value> = match provider {
                    Provider::Ollama => {
                        let text = local_model::state_text(&state)?;
                        questions
                            .values()
                            .filter_map(local_model::scoring_for)
                            .map(|scoring| {
                                let prompt = local_model::render_prompt(&text, &scoring);
                                local_model::ollama_request(&url, &model, &prompt, budget_time)
                                    .redacted()
                            })
                            .collect()
                    }
                    _ => vec![local_model::systemone_request(
                        &url,
                        &model,
                        &state,
                        &questions,
                        budget_time,
                    )
                    .redacted()],
                };
                let shown = serde_json::json!({"requests": requests, "estimated_usd": 0.0});
                writeln!(
                    out,
                    "{}",
                    serde_json::to_string_pretty(&shown).unwrap_or_default()
                )?;
                return Ok(());
            }
            if provider == Provider::Ollama {
                // Loading the weights is not part of the decision's budget.
                local_model::warm_up(transport.as_ref(), &url, &model)?;
            }
            let started = std::time::Instant::now();
            let response = local_model::decide(
                transport.as_ref(),
                provider,
                &url,
                &model,
                &state,
                &questions,
                budget_time,
            )?;
            let shown = serde_json::json!({
                "model": response.model,
                "provider": response.provider,
                "answers": answers_json(&response.answers),
                "latency_ms": started.elapsed().as_millis() as u64,
                "run_usd": 0.0,
            });
            writeln!(
                out,
                "{}",
                serde_json::to_string_pretty(&shown).unwrap_or_default()
            )?;
            Ok(())
        }
        Command::Ask { state, dry_run } => {
            if !provider.is_paid() {
                return Err(Error::InvalidArgument(
                    "ask needs a model provider (ollama, openjev, typesafe or openrouter)"
                        .to_string(),
                ));
            }
            let budget = budget_from(&cli.common, provider)?;
            let api_key = if dry_run {
                key_for(&cli.common, provider)?.unwrap_or_else(|| "dry-run".to_string())
            } else {
                require_key(&cli.common, provider)?
            };
            let state = state_value(state);
            let request =
                decision_request(provider, &model, &api_key, &state, &tactical_questions())?;
            let estimate = fragr_brain::provider::estimate_cost(&request, &budget.pricing);
            if dry_run {
                let shown = serde_json::json!({
                    "request": request.redacted(),
                    "estimated_usd": estimate,
                    "run_cap_usd": budget.caps.run_usd,
                    "ledger_total_usd": budget.total_usd(),
                });
                writeln!(
                    out,
                    "{}",
                    serde_json::to_string_pretty(&shown).unwrap_or_default()
                )?;
                return Ok(());
            }
            if cli.common.no_ledger {
                return Err(Error::InvalidArgument(
                    "paid ask requires a durable ledger; remove --no-ledger".into(),
                ));
            }
            let budget = Mutex::new(budget);
            let decision = decide(transport.as_ref(), &budget, provider, &model, &request)?;
            let guard = budget.lock().unwrap_or_else(|p| p.into_inner());
            let shown = serde_json::json!({
                "model": decision.response.model,
                "answers": answers_json(&decision.response.answers),
                "charge": decision.charge,
                "run_usd": guard.run_usd(),
                "ledger_total_usd": guard.total_usd(),
            });
            writeln!(
                out,
                "{}",
                serde_json::to_string_pretty(&shown).unwrap_or_default()
            )?;
            Ok(())
        }
        Command::Spend => {
            let budget = budget_from(&cli.common, provider)?;
            let ledger = budget.ledger();
            let shown = serde_json::json!({
                "ledger": budget.ledger_path().map(|p| p.display().to_string()),
                "pending_request": budget.pending_receipt().map(|p| p.display().to_string()),
                "calls": ledger.calls(),
                "total_usd": ledger.total_usd(),
                "run_cap_usd": budget.caps.run_usd,
                "total_cap_usd": budget.caps.total_usd,
            });
            writeln!(
                out,
                "{}",
                serde_json::to_string_pretty(&shown).unwrap_or_default()
            )?;
            Ok(())
        }
        Command::Key => {
            let api_key = require_key(&cli.common, provider)?;
            let request = key_request(provider, &api_key)?;
            let response = transport.send(&request)?;
            let status = parse_key_status(&response)?;
            writeln!(
                out,
                "{}",
                serde_json::to_string_pretty(&status).unwrap_or_default()
            )?;
            if status.limit.is_none() {
                writeln!(
                    out,
                    "note: this key has no provider-side limit; set one in the OpenRouter dashboard as a backstop"
                )?;
            }
            Ok(())
        }
    }
}

/// A JSON object is sent as given; anything else goes as a plain string.
fn state_value(state: String) -> serde_json::Value {
    serde_json::from_str::<serde_json::Value>(&state)
        .ok()
        .filter(serde_json::Value::is_object)
        .unwrap_or(serde_json::Value::String(state))
}

fn answers_json(
    answers: &std::collections::BTreeMap<String, fragr_brain::decision::Answer>,
) -> serde_json::Value {
    use fragr_brain::decision::Answer;
    let mut out = serde_json::Map::new();
    for (name, answer) in answers {
        let value = match answer {
            Answer::Noul { noul } => serde_json::json!({"type": "noul", "noul": noul}),
            Answer::Choice {
                choice,
                confidence,
                probabilities,
            } => serde_json::json!({
                "type": "choice", "choice": choice, "confidence": confidence, "probabilities": probabilities
            }),
            Answer::Score {
                score,
                confidence,
                probabilities,
                ..
            } => serde_json::json!({
                "type": "score", "score": score, "confidence": confidence, "probabilities": probabilities
            }),
        };
        out.insert(name.clone(), value);
    }
    serde_json::Value::Object(out)
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_writer(std::io::stderr)
        .init();
    let cli = Cli::parse();
    let timeout = Duration::from_millis(cli.common.timeout_ms);
    let local = Provider::parse(&cli.common.provider).is_some_and(Provider::is_local_model);
    let built = if local {
        HttpTransport::local(timeout)
    } else {
        HttpTransport::new(timeout)
    };
    let transport = match built {
        Ok(transport) => Arc::new(transport),
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(2);
        }
    };
    let mut stdout = std::io::stdout();
    if let Err(err) = run(cli, transport, &mut stdout) {
        eprintln!("error: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fragr_brain::provider::{HttpRequest, HttpResponse};
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Scripted {
        body: serde_json::Value,
        status: u16,
        calls: AtomicUsize,
    }

    impl Transport for Scripted {
        fn send(&self, _request: &HttpRequest) -> Result<HttpResponse, Error> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(HttpResponse {
                status: self.status,
                body: self.body.to_string().into_bytes(),
            })
        }
    }

    fn scripted(status: u16, body: serde_json::Value) -> Arc<Scripted> {
        Arc::new(Scripted {
            body,
            status,
            calls: AtomicUsize::new(0),
        })
    }

    fn parse(args: &[&str]) -> Cli {
        Cli::try_parse_from(std::iter::once("fragr-brain").chain(args.iter().copied()))
            .expect("args parse")
    }

    fn temp(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("fragr-brain-main-{name}-{}", std::process::id()))
    }

    fn answers() -> serde_json::Value {
        serde_json::json!({
            "model": "jev-1.13.0",
            "answers": {
                "stance": {"type": "choice", "choice": "hold_angle", "confidence": 0.7},
                "danger": {"type": "score", "score": 1.0},
                "extra": {"type": "noul", "noul": 0.2}
            },
            "usage": {"input_tokens": 100, "output_tokens": 0, "cost": 0.0000042}
        })
    }

    #[test]
    fn args_parse_every_command() {
        let cli = parse(&[
            "play",
            "--server",
            "ws://h:1",
            "--name",
            "X",
            "--max-seconds",
            "5",
            "--timeline-path",
            ".agents/watch/test-timeline.json",
            "--margin-floor",
            "0.3",
        ]);
        assert!(
            matches!(cli.command, Command::Play { ref server, ref name, max_seconds: Some(5), .. } if server == "ws://h:1" && name.as_deref() == Some("X"))
        );
        assert!(
            matches!(cli.command, Command::Play { timeline_path: Some(ref path), .. } if path == &PathBuf::from(".agents/watch/test-timeline.json"))
        );
        assert!(
            matches!(cli.command, Command::Play { margin_floor, .. } if (margin_floor - 0.3).abs() < 1e-9)
        );
        assert_eq!(cli.common.provider, "local");
        assert_eq!(cli.common.max_spend_usd, 0.0);
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--max-spend-usd",
            "5",
            "ask",
            "--state",
            "s",
            "--dry-run",
        ]);
        assert!(matches!(cli.command, Command::Ask { dry_run: true, .. }));
        assert_eq!(cli.common.max_spend_usd, 5.0);
        assert!(matches!(parse(&["spend"]).command, Command::Spend));
        assert!(matches!(parse(&["key"]).command, Command::Key));
        assert!(Cli::try_parse_from(["fragr-brain"]).is_err());
        assert_eq!(parse_provider("openrouter").unwrap(), Provider::OpenRouter);
        assert!(parse_provider("cloud").is_err());
        assert_eq!(resolve_name(Some(" Z "), "Brain"), "Z");
        assert_eq!(resolve_name(Some("  "), "Brain"), "Brain");
    }

    #[test]
    fn budget_from_validates_and_loads_ledger() {
        let mut cli = parse(&["--no-ledger", "spend"]);
        let budget = budget_from(&cli.common, Provider::Local).unwrap();
        assert_eq!(budget.ledger_path(), None);
        cli.common.max_spend_usd = -1.0;
        assert!(budget_from(&cli.common, Provider::Local).is_err());
        cli.common.max_spend_usd = f64::NAN;
        assert!(budget_from(&cli.common, Provider::Local).is_err());
        cli.common.max_spend_usd = 5.01;
        assert!(
            budget_from(&cli.common, Provider::Local).is_err(),
            "the per-run ceiling is enforced"
        );
        cli.common.max_spend_usd = 1.0;
        cli.common.price_input_per_million = -1.0;
        assert!(budget_from(&cli.common, Provider::Local).is_err());
        cli.common.price_input_per_million = 0.0;
        assert!(
            budget_from(&cli.common, Provider::Local).is_ok(),
            "free provider, free price"
        );
        assert!(
            budget_from(&cli.common, Provider::Typesafe).is_err(),
            "a zero price needs a call cap on a paid provider"
        );
        cli.common.max_calls = Some(10);
        assert!(budget_from(&cli.common, Provider::Typesafe).is_ok());
        let ledger = temp("ledger.json");
        let _ = std::fs::remove_file(&ledger);
        let cli = parse(&["--ledger", ledger.to_str().unwrap(), "spend"]);
        let budget = budget_from(&cli.common, Provider::Local).unwrap();
        assert_eq!(budget.ledger_path(), Some(ledger.as_path()));
        let mut out = Vec::new();
        run(cli, scripted(200, answers()), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\"calls\": 0"));
    }

    #[test]
    fn play_refuses_paid_without_cap_or_key() {
        let env_file = temp("empty.env");
        std::fs::write(&env_file, "# nothing\n").unwrap();
        // A blank key file keeps the test away from the developer's real environment.
        let blank_key = temp("blank.key");
        std::fs::write(&blank_key, "\n").unwrap();
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--no-ledger",
            "--env-file",
            env_file.to_str().unwrap(),
            "--api-key-file",
            blank_key.to_str().unwrap(),
            "play",
            "--max-seconds",
            "1",
        ]);
        let mut out = Vec::new();
        let err = run(cli, scripted(200, answers()), &mut out).unwrap_err();
        assert!(matches!(err, Error::Budget(_)), "{err}");
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--no-ledger",
            "--max-spend-usd",
            "1",
            "--env-file",
            env_file.to_str().unwrap(),
            "--api-key-file",
            blank_key.to_str().unwrap(),
            "play",
            "--max-seconds",
            "1",
        ]);
        let err = run(cli, scripted(200, answers()), &mut out).unwrap_err();
        assert!(matches!(err, Error::MissingApiKey(_)), "{err}");
        std::fs::write(&blank_key, "sk_test\n").unwrap();
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--no-ledger",
            "--max-spend-usd",
            "1",
            "--env-file",
            env_file.to_str().unwrap(),
            "--api-key-file",
            blank_key.to_str().unwrap(),
            "play",
            "--max-seconds",
            "1",
        ]);
        let err = run(cli, scripted(200, answers()), &mut out).unwrap_err();
        assert!(matches!(err, Error::InvalidArgument(_)), "{err}");
        let _ = std::fs::remove_file(env_file);
        let _ = std::fs::remove_file(blank_key);
    }

    #[test]
    fn play_local_fails_cleanly_when_no_server() {
        let free = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = free.local_addr().unwrap().port();
        drop(free);
        let server = format!("ws://127.0.0.1:{port}");
        let cli = parse(&[
            "--no-ledger",
            "play",
            "--server",
            &server,
            "--max-seconds",
            "1",
        ]);
        let mut out = Vec::new();
        let err = run(cli, scripted(200, answers()), &mut out).unwrap_err();
        assert!(matches!(err, Error::Transport(_)), "{err}");
        let cli = parse(&[
            "--no-ledger",
            "play",
            "--server",
            &server,
            "--decision-hz",
            "nan",
        ]);
        let err = run(cli, scripted(200, answers()), &mut Vec::new()).unwrap_err();
        assert!(matches!(err, Error::InvalidArgument(_)), "{err}");
    }

    #[test]
    fn ask_dry_run_sends_nothing_and_masks_the_key() {
        let env_file = temp("key.env");
        std::fs::write(&env_file, "typesafe=sk_secret\n").unwrap();
        let transport = scripted(200, answers());
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--no-ledger",
            "--env-file",
            env_file.to_str().unwrap(),
            "ask",
            "--state",
            "SELF hp=10",
            "--dry-run",
        ]);
        let mut out = Vec::new();
        run(cli, transport.clone(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("Bearer ***"));
        assert!(!text.contains("sk_secret"));
        assert!(text.contains("estimated_usd"));
        assert!(
            text.contains("\"state\": \"SELF hp=10\""),
            "plain text stays a string: {text}"
        );
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--no-ledger",
            "--env-file",
            env_file.to_str().unwrap(),
            "ask",
            "--state",
            "{\"self\":{\"health\":\"low\"}}",
            "--dry-run",
        ]);
        let mut out = Vec::new();
        run(cli, transport.clone(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(
            text.contains("\"health\": \"low\""),
            "JSON objects go through as objects: {text}"
        );
        assert_eq!(transport.calls.load(Ordering::SeqCst), 0);
        let cli = parse(&["--no-ledger", "ask", "--state", "x"]);
        assert!(
            run(cli, transport.clone(), &mut Vec::new()).is_err(),
            "local cannot ask"
        );
        let _ = std::fs::remove_file(env_file);
    }

    #[test]
    fn ask_sends_under_a_cap_and_reports_the_charge() {
        let env_file = temp("key2.env");
        std::fs::write(&env_file, "OPENROUTER_API_KEY=sk_or\n").unwrap();
        let ledger = temp("ask-ledger.jsonl");
        let _ = std::fs::remove_file(&ledger);
        let transport = scripted(200, answers());
        let cli = parse(&[
            "--provider",
            "openrouter",
            "--ledger",
            ledger.to_str().unwrap(),
            "--max-spend-usd",
            "0.01",
            "--env-file",
            env_file.to_str().unwrap(),
            "ask",
            "--state",
            "SELF hp=10",
        ]);
        let mut out = Vec::new();
        run(cli, transport.clone(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\"choice\": \"hold_angle\""));
        assert!(text.contains("\"noul\": 0.2"));
        assert!(text.contains("\"score\": 1.0"));
        assert!(text.contains("\"estimated_usd\""));
        assert_eq!(transport.calls.load(Ordering::SeqCst), 1);
        let cli = parse(&[
            "--provider",
            "openrouter",
            "--ledger",
            ledger.to_str().unwrap(),
            "--env-file",
            env_file.to_str().unwrap(),
            "ask",
            "--state",
            "SELF hp=10",
        ]);
        let err = run(cli, transport.clone(), &mut Vec::new()).unwrap_err();
        assert!(matches!(err, Error::Budget(_)));
        assert_eq!(
            transport.calls.load(Ordering::SeqCst),
            1,
            "refused calls are not sent"
        );
        let failing = scripted(429, serde_json::json!({"error": {"message": "slow down"}}));
        let cli = parse(&[
            "--provider",
            "openrouter",
            "--ledger",
            ledger.to_str().unwrap(),
            "--max-spend-usd",
            "1",
            "--env-file",
            env_file.to_str().unwrap(),
            "ask",
            "--state",
            "s",
        ]);
        let err = run(cli, failing, &mut Vec::new()).unwrap_err();
        assert!(err.to_string().contains("slow down"));
        let no_ledger = parse(&[
            "--provider",
            "openrouter",
            "--no-ledger",
            "--max-spend-usd",
            "1",
            "--env-file",
            env_file.to_str().unwrap(),
            "ask",
            "--state",
            "s",
        ]);
        assert!(matches!(
            run(no_ledger, transport.clone(), &mut Vec::new()),
            Err(Error::InvalidArgument(_))
        ));
        assert_eq!(transport.calls.load(Ordering::SeqCst), 1);
        let _ = std::fs::remove_file(env_file);
        let _ = std::fs::remove_file(ledger);
    }

    fn letter_reply() -> serde_json::Value {
        serde_json::json!({
            "response": "B",
            "logprobs": [{"token": "B", "logprob": -0.1, "top_logprobs": [
                {"token": "B", "logprob": -0.1}, {"token": "A", "logprob": -2.5},
                {"token": "C", "logprob": -3.0}, {"token": "D", "logprob": -4.0},
                {"token": "E", "logprob": -5.0}
            ]}]
        })
    }

    #[test]
    fn local_models_default_to_loopback_and_refuse_elsewhere() {
        let cli = parse(&["--provider", "ollama", "ask", "--state", "s"]);
        assert_eq!(
            parse_provider(&cli.common.provider).unwrap(),
            Provider::Ollama
        );
        assert_eq!(
            model_url_for(&cli.common, Provider::Ollama)
                .unwrap()
                .as_deref(),
            Some("http://127.0.0.1:11434")
        );
        assert_eq!(
            model_url_for(&cli.common, Provider::OpenJev)
                .unwrap()
                .as_deref(),
            Some("http://127.0.0.1:3000")
        );
        assert_eq!(
            model_url_for(&cli.common, Provider::Typesafe).unwrap(),
            None
        );
        let remote = parse(&[
            "--provider",
            "openjev",
            "--model-url",
            "http://192.168.1.5:3000",
            "ask",
            "--state",
            "s",
        ]);
        let transport = scripted(200, answers());
        let err = run(remote, transport.clone(), &mut Vec::new()).unwrap_err();
        assert!(err.to_string().contains("--allow-remote-model"), "{err}");
        assert_eq!(transport.calls.load(Ordering::SeqCst), 0, "nothing is sent");
        let allowed = parse(&[
            "--provider",
            "openjev",
            "--model-url",
            "http://192.168.1.5:3000",
            "--allow-remote-model",
            "ask",
            "--state",
            "s",
        ]);
        assert!(model_url_for(&allowed.common, Provider::OpenJev).is_ok());
        let zero = parse(&[
            "--provider",
            "ollama",
            "--timeout-ms",
            "0",
            "ask",
            "--state",
            "s",
        ]);
        assert!(matches!(
            run(zero, transport.clone(), &mut Vec::new()),
            Err(Error::InvalidArgument(_))
        ));
        let key = parse(&["--provider", "ollama", "--no-ledger", "key"]);
        assert!(run(key, transport.clone(), &mut Vec::new()).is_err());
    }

    #[test]
    fn ask_a_local_model_for_free() {
        let transport = scripted(200, letter_reply());
        let cli = parse(&[
            "--provider",
            "ollama",
            "--no-ledger",
            "ask",
            "--state",
            "{\"self\":{\"health\":\"low\"}}",
        ]);
        let mut out = Vec::new();
        run(cli, transport.clone(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\"provider\": \"ollama\""), "{text}");
        assert!(
            text.contains("\"choice\": \"hold_angle\""),
            "B is the second stance: {text}"
        );
        assert!(text.contains("\"run_usd\": 0.0"));
        assert_eq!(
            transport.calls.load(Ordering::SeqCst),
            4,
            "a warmup, then one call per question"
        );

        let dry = parse(&["--provider", "ollama", "ask", "--state", "s", "--dry-run"]);
        let mut out = Vec::new();
        run(dry, transport.clone(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("/api/generate") && text.contains("\"raw\": true"));
        assert!(text.contains("\"estimated_usd\": 0.0"));
        assert_eq!(
            transport.calls.load(Ordering::SeqCst),
            4,
            "a dry run sends nothing"
        );

        let openjev = scripted(
            200,
            serde_json::json!({"answers": {
                "stance": {"type": "choice", "choice": "kite_distance", "probabilities": {"kite_distance": 0.8, "push_enemy": 0.2}},
                "weapon": {"type": "choice", "choice": "rail"},
                "danger": {"type": "score", "score": 2.0}
            }}),
        );
        let dry = parse(&["--provider", "openjev", "ask", "--state", "s", "--dry-run"]);
        let mut out = Vec::new();
        run(dry, openjev.clone(), &mut out).unwrap();
        assert!(String::from_utf8(out).unwrap().contains("/v1/systemone"));
        let cli = parse(&[
            "--provider",
            "openjev",
            "--no-ledger",
            "ask",
            "--state",
            "s",
        ]);
        let mut out = Vec::new();
        run(cli, openjev.clone(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\"choice\": \"kite_distance\""), "{text}");
        assert_eq!(openjev.calls.load(Ordering::SeqCst), 1);
        let bad = scripted(
            200,
            serde_json::json!({"answers": {"stance": {"type": "choice", "choice": "fly"}}}),
        );
        let cli = parse(&[
            "--provider",
            "openjev",
            "--no-ledger",
            "ask",
            "--state",
            "s",
        ]);
        assert!(matches!(
            run(cli, bad, &mut Vec::new()),
            Err(Error::Malformed(_))
        ));
    }

    #[test]
    fn play_with_ollama_warms_up_and_names_a_missing_model() {
        let missing = scripted(404, serde_json::json!({"error": "model not found"}));
        let cli = parse(&[
            "--provider",
            "ollama",
            "--no-ledger",
            "play",
            "--server",
            "ws://127.0.0.1:9",
            "--max-seconds",
            "1",
        ]);
        let err = run(cli, missing.clone(), &mut Vec::new()).unwrap_err();
        assert!(err.to_string().contains("ollama pull"), "{err}");
        assert_eq!(missing.calls.load(Ordering::SeqCst), 1);
        let free = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = free.local_addr().unwrap().port();
        drop(free);
        let server = format!("ws://127.0.0.1:{port}");
        let loaded = scripted(200, serde_json::json!({"done": true}));
        let cli = parse(&[
            "--provider",
            "ollama",
            "--no-ledger",
            "play",
            "--server",
            &server,
            "--max-seconds",
            "1",
        ]);
        let err = run(cli, loaded.clone(), &mut Vec::new()).unwrap_err();
        assert!(
            matches!(err, Error::Transport(_)),
            "warm, then no game server: {err}"
        );
        assert_eq!(loaded.calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn key_reads_openrouter_status() {
        let key_file = temp("key.txt");
        std::fs::write(&key_file, "sk_or\n").unwrap();
        let transport = scripted(
            200,
            serde_json::json!({"data": {"label": "fragr", "limit": null, "limit_remaining": null, "usage": 0.25}}),
        );
        let cli = parse(&[
            "--provider",
            "openrouter",
            "--no-ledger",
            "--api-key-file",
            key_file.to_str().unwrap(),
            "key",
        ]);
        let mut out = Vec::new();
        run(cli, transport, &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\"usage\": 0.25"));
        assert!(text.contains("no provider-side limit"));
        let cli = parse(&[
            "--provider",
            "typesafe",
            "--no-ledger",
            "--api-key-file",
            key_file.to_str().unwrap(),
            "key",
        ]);
        assert!(run(cli, scripted(200, serde_json::json!({})), &mut Vec::new()).is_err());
        let _ = std::fs::remove_file(key_file);
    }
}
