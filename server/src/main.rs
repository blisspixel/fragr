use clap::Parser;
use fragr_server::run::{run_server, ServerOptions};
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

// Eq is out because a threshold is a float; PartialEq still serves the tests.
#[derive(Parser, Debug, PartialEq)]
#[command(name = "fragr-server")]
#[command(about = "fragr authoritative game server")]
struct Args {
    #[arg(long, default_value = "0.0.0.0:6767")]
    bind: String,

    #[arg(long, default_value = "4")]
    bots: usize,

    /// Map: 1/arena, 2/compliance-yard, 3/directive-17, 4/sector-9,
    /// 5/reclamation-gulch, 6/tripoint-works.
    #[arg(long, default_value = "1")]
    map: String,

    /// Load a local authored campaign development map. Requires --bots 0.
    #[arg(long, conflicts_with_all = ["map", "map_rotate", "solo_broadcast", "bench", "bench_verify_trace", "no_round_events"])]
    map_file: Option<PathBuf>,

    /// Move to the next map in the roster each round.
    #[arg(long, default_value_t = false)]
    map_rotate: bool,

    /// Contested Frequency Solo Broadcast Episode 0 (Calibration / Larak Lot).
    /// NODS clear + jammer dish + Auditor. MP unchanged when off.
    #[arg(long, default_value_t = false)]
    solo_broadcast: bool,

    /// Disable timed compliance slowdowns and boss spawns for arena practice.
    #[arg(long, conflicts_with_all = ["solo_broadcast", "bench", "bench_verify_trace"])]
    no_round_events: bool,

    /// Benchmark instead of serving: run this many scripted fighters with no
    /// network, print one JSON report, and exit. The ruler for every change.
    #[arg(long)]
    bench: Option<usize>,

    /// Ticks to run in benchmark mode (20 per second of match time).
    #[arg(long, default_value_t = 1200, value_parser = clap::value_parser!(u64).range(1..))]
    bench_ticks: u64,

    /// Write a complete offline NDJSON recording to a new file. Parent directory
    /// must exist. No overwrite, network connection, or paid provider is involved.
    #[arg(long, requires = "bench")]
    bench_trace: Option<PathBuf>,

    /// Validate a recorded trace without opening a network connection.
    #[arg(long, conflicts_with = "bench")]
    bench_verify_trace: Option<PathBuf>,

    /// Run the benchmark twice and report whether the two matches agreed.
    #[arg(long, default_value_t = false, requires = "bench")]
    bench_check: bool,

    /// Seed for the simulation's random stream. The same seed gives the same
    /// match, which is what makes two runs comparable.
    #[arg(long, default_value_t = 1)]
    seed: u64,

    /// Print the status report (tick time, bytes, budget use) this often, in
    /// seconds. Zero turns it off.
    #[arg(long, default_value_t = 60)]
    status_every_s: u64,

    /// Exit non-zero when a benchmark crosses a threshold below. This is what
    /// CI runs, so a regression is a failed build rather than a note nobody
    /// reads.
    #[arg(long, default_value_t = false, requires = "bench")]
    bench_assert: bool,

    /// Largest share of the tick budget the p99 tick may use before
    /// `--bench-assert` fails. One tick in a hundred over half the budget
    /// means the next change has nowhere to go.
    #[arg(long, default_value_t = 0.5, value_parser = parse_budget_fraction)]
    bench_max_budget_p99: f64,
}

fn parse_budget_fraction(raw: &str) -> Result<f64, String> {
    let value: f64 = raw
        .parse()
        .map_err(|_| "expected a budget fraction".to_string())?;
    if value.is_finite() && value > 0.0 && value <= 1.0 {
        Ok(value)
    } else {
        Err("budget fraction must be finite and greater than zero, at most one".to_string())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let args = Args::parse();
    // In benchmark mode the JSON report is the only thing on stdout, so logs
    // go to stderr and only warnings survive.
    init_tracing(args.bench.is_some());
    if let Some(path) = args.bench_verify_trace {
        let reader = std::io::BufReader::new(std::fs::File::open(path)?);
        let summary = fragr_server::trace::verify_trace(reader)?;
        println!("{}", serde_json::to_string_pretty(&summary)?);
        return Ok(());
    }
    let map = fragr_server::sim::MapKind::from_cli(&args.map).ok_or_else(|| {
        let roster: Vec<String> = fragr_server::sim::MapKind::ALL
            .iter()
            .map(|m| format!("{} ({})", m.id(), m.name()))
            .collect();
        format!(
            "invalid --map {:?}; the roster is {}",
            args.map,
            roster.join(", ")
        )
    })?;
    if let Some(bots) = args.bench {
        let mut output = args
            .bench_trace
            .as_ref()
            .map(|path| {
                std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(path)
                    .map(std::io::BufWriter::new)
            })
            .transpose()?;
        let sink = output
            .as_mut()
            .map(|writer| writer as &mut dyn std::io::Write);
        let mut report = fragr_server::bench::run_bench_with_trace(
            bots,
            args.bench_ticks,
            map,
            args.seed,
            sink,
        )?;
        if args.bench_check {
            report = fragr_server::bench::check_repeated(report)?;
        }
        println!("{}", serde_json::to_string_pretty(&report)?);
        // A run that is not reproducible is a correctness failure, not a slow one.
        if report.deterministic == Some(false) {
            return Err("benchmark was not deterministic for this seed".into());
        }
        if args.bench_assert {
            let complaints =
                fragr_server::bench::check_thresholds(&report, args.bench_max_budget_p99);
            for complaint in &complaints {
                eprintln!("benchmark: {complaint}");
            }
            if !complaints.is_empty() {
                return Err("benchmark crossed a threshold".into());
            }
        }
        return Ok(());
    }

    let options = ServerOptions {
        bind: args.bind,
        bots: args.bots,
        map,
        map_file: args.map_file,
        map_rotate: args.map_rotate,
        match_config: args
            .no_round_events
            .then(|| fragr_server::sim::MatchConfig {
                boss_spawn_ticks: None,
                compliance_ping_ticks: None,
                ..Default::default()
            }),
        solo_broadcast: args.solo_broadcast,
        seed: args.seed,
        status_every_s: args.status_every_s,
    };
    run_server(options, std::future::pending::<()>(), None).await
}

fn init_tracing(quiet: bool) {
    let default = if quiet {
        "warn"
    } else {
        "info,fragr_server=debug"
    };
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default)),
        )
        .with_writer(std::io::stderr)
        .init();
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::{SinkExt, StreamExt};
    use std::net::SocketAddr;
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    #[test]
    fn args_default_bind_and_bots() {
        let args = Args::try_parse_from(["fragr-server"]).expect("defaults");
        assert_eq!(args.bind, "0.0.0.0:6767");
        assert_eq!(args.bots, 4);
        assert_eq!(args.map, "1");
        assert!(!args.map_rotate);
        assert!(!args.solo_broadcast);
    }

    #[test]
    fn args_custom_bind_and_bots() {
        let args = Args::try_parse_from(["fragr-server", "--bind", "127.0.0.1:0", "--bots", "2"])
            .expect("custom");
        assert_eq!(args.bind, "127.0.0.1:0");
        assert_eq!(args.bots, 2);
    }

    #[test]
    fn args_map_and_rotate() {
        let args =
            Args::try_parse_from(["fragr-server", "--map", "compliance-yard", "--map-rotate"])
                .expect("map args");
        assert_eq!(args.map, "compliance-yard");
        assert!(args.map_rotate);
        assert!(fragr_server::sim::MapKind::from_cli(&args.map).is_some());
    }

    #[test]
    fn args_solo_broadcast() {
        let args = Args::try_parse_from(["fragr-server", "--solo-broadcast"]).expect("solo");
        assert!(args.solo_broadcast);
        let practice = Args::try_parse_from(["fragr-server", "--no-round-events"]).unwrap();
        assert!(practice.no_round_events);
        assert!(
            Args::try_parse_from(["fragr-server", "--solo-broadcast", "--no-round-events"])
                .is_err()
        );
    }

    #[tokio::test]
    async fn run_server_ws_hello_welcome_tick_then_shutdown() {
        // This test times the wire handshake, not cold topology construction.
        // Prepare the same immutable roster before starting its network timers.
        tokio::task::spawn_blocking(fragr_server::session::GameSession::new)
            .await
            .expect("navigation fixture");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<SocketAddr>();

        let server = tokio::spawn(async move {
            run_server(
                ServerOptions {
                    map_file: None,
                    bind: "127.0.0.1:0".to_string(),
                    bots: 1,
                    map: fragr_server::sim::MapKind::ArenaDuel,
                    map_rotate: false,
                    match_config: None,
                    solo_broadcast: false,
                    seed: 1,
                    status_every_s: 0,
                },
                async move {
                    let _ = shutdown_rx.await;
                },
                Some(ready_tx),
            )
            .await
            .map_err(|e| e.to_string())
        });

        let addr = tokio::time::timeout(Duration::from_secs(2), ready_rx)
            .await
            .expect("ready timeout")
            .expect("ready addr");

        let url = format!("ws://{}", addr);
        let (ws, _) = connect_async(&url).await.expect("connect");
        let (mut sink, mut stream) = ws.split();

        let hello = serde_json::json!({
            "type": "hello",
            "role": "agent",
            "name": "CovClimb"
        });
        sink.send(Message::Text(hello.to_string()))
            .await
            .expect("send hello");

        let welcome = tokio::time::timeout(Duration::from_secs(2), stream.next())
            .await
            .expect("welcome timeout")
            .expect("welcome msg")
            .expect("welcome ok");
        let Message::Text(text) = welcome else {
            panic!("expected text welcome, got {welcome:?}");
        };
        let v: serde_json::Value = serde_json::from_str(&text).expect("welcome json");
        assert_eq!(v["type"], "welcome");
        assert!(v["player_id"].is_string(), "player_id={}", v["player_id"]);

        // A joiner is told the arena's shape once, then the tick broadcasts
        // begin. Read a few messages so the test does not depend on the order.
        let mut saw_map = false;
        let mut saw_tick = false;
        for _ in 0..8 {
            let msg = tokio::time::timeout(Duration::from_secs(2), stream.next())
                .await
                .expect("tick timeout")
                .expect("tick msg")
                .expect("tick ok");
            let Message::Text(text) = msg else {
                panic!("expected text broadcast, got {msg:?}");
            };
            let v: serde_json::Value = serde_json::from_str(&text).expect("json");
            match v["type"].as_str().unwrap_or("") {
                "map_info" => {
                    assert!(v["solids"].is_array(), "map_info carries solids: {text}");
                    assert!(v["half_extent"].as_f64().unwrap_or(0.0) > 0.0);
                    saw_map = true;
                }
                "snapshot" | "event" => saw_tick = true,
                other => panic!("unexpected message type {other}: {text}"),
            }
            if saw_map && saw_tick {
                break;
            }
        }
        assert!(saw_map, "a joining fighter should be told the map");
        assert!(saw_tick, "and then receive tick broadcasts");

        let _ = shutdown_tx.send(());
        let result = tokio::time::timeout(Duration::from_secs(2), server)
            .await
            .expect("server join timeout")
            .expect("server task");
        assert!(result.is_ok(), "{result:?}");
    }

    #[test]
    fn server_options_default_matches_cli_defaults() {
        let options = ServerOptions::default();
        let args = Args::try_parse_from(["fragr-server"]).expect("defaults");
        assert_eq!(options.bind, args.bind);
        assert_eq!(options.bots, args.bots);
        assert!(options.match_config.is_none());
    }

    #[test]
    fn benchmark_cli_rejects_invalid_limits_and_conflicting_operations() {
        for fraction in ["NaN", "inf", "0", "-0.5", "1.1", "garbage"] {
            assert!(
                Args::try_parse_from(["fragr-server", "--bench-max-budget-p99", fraction]).is_err()
            );
        }
        assert!(
            Args::try_parse_from(["fragr-server", "--bench", "4", "--bench-ticks", "0"]).is_err()
        );
        assert!(Args::try_parse_from(["fragr-server", "--bench-trace", "match.ndjson"]).is_err());
        assert!(Args::try_parse_from([
            "fragr-server",
            "--bench",
            "4",
            "--bench-verify-trace",
            "match.ndjson"
        ])
        .is_err());
        let args = Args::try_parse_from([
            "fragr-server",
            "--bench",
            "16",
            "--bench-check",
            "--bench-assert",
            "--bench-trace",
            "match.ndjson",
        ])
        .unwrap();
        assert_eq!(args.bench, Some(16));
        assert!(args.bench_check && args.bench_assert);
        assert_eq!(args.bench_trace, Some(PathBuf::from("match.ndjson")));
    }
}
