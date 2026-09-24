//! Command line front end for the agent playtest harness.

use clap::Parser;
use fragr_playtest::{check_thresholds, run, Config};
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(
    name = "fragr-playtest",
    version,
    about = "Scripted agents play fragr rounds in-process and file a metrics report."
)]
struct Cli {
    /// Run the local fighter and spectator delivery matrix instead of a round.
    #[arg(long)]
    fanout_matrix: bool,
    /// Seconds measured in each of the twelve fanout matrix rows.
    #[arg(long, default_value_t = 10)]
    fanout_seconds: u64,
    /// Number of scripted agents.
    #[arg(long, default_value_t = 4)]
    agents: usize,
    /// Rounds to complete before stopping.
    #[arg(long, default_value_t = 1)]
    rounds: u32,
    /// Map ID 1 through 6, or its server map name.
    #[arg(long, default_value = "1")]
    map: String,
    /// Frag limit for each round.
    #[arg(long, default_value_t = 5)]
    frag_limit: u32,
    /// Round time limit in seconds.
    #[arg(long, default_value_t = 60)]
    time_limit_seconds: u32,
    /// Hard stop for the whole run, in seconds of match time.
    #[arg(long, default_value_t = 120)]
    max_seconds: u64,
    /// Where to write the JSON report.
    #[arg(long, default_value = ".agents/playtest/report.json")]
    report: PathBuf,
    /// Exit non-zero when a frustration threshold is crossed.
    #[arg(long)]
    assert: bool,
    /// Simulation seed, so a run can be reproduced and two runs compared.
    #[arg(long, default_value_t = 1)]
    seed: u64,
    /// Agent policies, dealt round robin: reflex, planner, or a comma
    /// separated mix such as `reflex,planner` for an even split.
    #[arg(long, default_value = "reflex")]
    tiers: String,
    /// Soak instead of a round: the real server binary with rule bots,
    /// `--agents` reflex agents and `--soak-spectators` spectators, sampled
    /// through `GET /status?clients=1` into NDJSON.
    #[arg(long, conflicts_with = "fanout_matrix")]
    soak: bool,
    /// Measured soak length in seconds.
    #[arg(long, default_value_t = 3600)]
    soak_seconds: u64,
    /// Seconds between status samples.
    #[arg(long, default_value_t = 60)]
    soak_sample_seconds: u64,
    /// Server rule bots during the soak.
    #[arg(long, default_value_t = 4)]
    soak_bots: usize,
    /// Spectators that read the whole stream during the soak.
    #[arg(long, default_value_t = 2)]
    soak_spectators: usize,
    /// Rotate maps each round during the soak.
    #[arg(long)]
    soak_map_rotate: bool,
    /// The `fragr-server` binary to soak. Defaults to the one beside this tool.
    #[arg(long)]
    soak_server: Option<PathBuf>,
    /// NDJSON sample log. The server's own log is written beside it.
    #[arg(long, default_value = ".agents/soak/soak.ndjson")]
    soak_log: PathBuf,
}

fn soak_config(cli: &Cli) -> Result<fragr_playtest::soak::SoakConfig, String> {
    let map = fragr_server::sim::MapKind::from_cli(&cli.map)
        .ok_or_else(|| format!("invalid --map {:?}", cli.map))?;
    let binary = cli
        .soak_server
        .clone()
        .or_else(fragr_playtest::soak::default_server_binary)
        .ok_or("no fragr-server beside this tool; build it or pass --soak-server")?;
    Ok(fragr_playtest::soak::SoakConfig {
        seconds: cli.soak_seconds,
        sample_seconds: cli.soak_sample_seconds,
        bots: cli.soak_bots,
        agents: cli.agents,
        spectators: cli.soak_spectators,
        map,
        map_rotate: cli.soak_map_rotate,
        seed: cli.seed,
        launch: fragr_playtest::soak::Launch::Binary(binary),
        log: cli.soak_log.clone(),
    })
}

fn print_soak(verdict: &fragr_playtest::soak::Verdict, log: &std::path::Path) {
    let s = &verdict.summary;
    let mib = |bytes: Option<u64>| {
        bytes.map_or("unavailable".to_string(), |b| {
            format!("{:.1} MiB", b as f64 / (1024.0 * 1024.0))
        })
    };
    println!(
        "soak: {} samples over {:.0} s, ticks {} to {} ({:.2} Hz), window p50/p95/p99 {:.2}/{:.2}/{:.2} ms at start and {:.2}/{:.2}/{:.2} ms at end, lifetime p99 {:.2} ms max {:.2} ms, {:.0} out and {:.0} in bytes per client per second, rss {} to {} (max {})",
        s.samples,
        s.measured_s,
        s.ticks_start,
        s.ticks_end,
        s.tick_rate_hz,
        s.window_start.p50_ms,
        s.window_start.p95_ms,
        s.window_start.p99_ms,
        s.window_end.p50_ms,
        s.window_end.p95_ms,
        s.window_end.p99_ms,
        s.lifetime_end.p99_ms,
        s.lifetime_end.max_ms,
        s.out_bytes_per_client_per_s,
        s.in_bytes_per_client_per_s,
        mib(s.rss_start),
        mib(s.rss_end),
        mib(s.rss_max),
    );
    for note in &verdict.notes {
        println!("note: {note}");
    }
    for problem in &verdict.problems {
        println!("soak problem: {problem}");
    }
    println!("log: {}", log.display());
}

fn config_from(cli: &Cli) -> Result<Config, String> {
    let map = fragr_server::sim::MapKind::from_cli(&cli.map)
        .ok_or_else(|| format!("invalid --map {:?}", cli.map))?;
    Ok(Config {
        agents: cli.agents,
        rounds: cli.rounds,
        map,
        frag_limit: cli.frag_limit,
        time_limit_ticks: cli.time_limit_seconds * 20,
        max_ticks: cli.max_seconds * 20,
        seed: cli.seed,
        tiers: fragr_playtest::Policy::parse_list(&cli.tiers)
            .map_err(|e| format!("invalid --tiers {:?}: {e}", cli.tiers))?,
    })
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn")),
        )
        .with_writer(std::io::stderr)
        .init();
    let cli = Cli::parse();
    if cli.soak {
        let config = match soak_config(&cli) {
            Ok(config) => config,
            Err(error) => {
                eprintln!("error: {error}");
                std::process::exit(2);
            }
        };
        let log = config.log.clone();
        let verdict = match fragr_playtest::soak::run_soak(config).await {
            Ok(verdict) => verdict,
            Err(error) => {
                eprintln!("error: {error}");
                std::process::exit(2);
            }
        };
        print_soak(&verdict, &log);
        if cli.assert && !verdict.passed {
            std::process::exit(1);
        }
        return;
    }
    if cli.fanout_matrix {
        let report = match fragr_playtest::fanout::matrix(cli.fanout_seconds).await {
            Ok(report) => report,
            Err(error) => {
                eprintln!("error: {error}");
                std::process::exit(2);
            }
        };
        if let Some(parent) = cli.report.parent() {
            if let Err(error) = std::fs::create_dir_all(parent) {
                eprintln!("error: cannot create {}: {error}", parent.display());
                std::process::exit(2);
            }
        }
        let json = serde_json::to_string_pretty(&report).expect("fanout report serializes");
        if let Err(error) = std::fs::write(&cli.report, format!("{json}\n")) {
            eprintln!("error: cannot write {}: {error}", cli.report.display());
            std::process::exit(2);
        }
        for row in &report.rows {
            println!(
                "{}: {} fighters, {} spectators, {} frames, {:.0} text KiB/s, {} missing ticks, {} disconnects",
                row.map,
                row.fighters,
                row.spectators,
                row.watcher_snapshots,
                row.watcher_text_bytes_per_second / 1024.0,
                row.missing_snapshot_ticks,
                row.watcher_disconnects
            );
        }
        println!("report: {}", cli.report.display());
        return;
    }
    let config = match config_from(&cli) {
        Ok(config) => config,
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(2);
        }
    };
    let (report, _observation) = match run(config).await {
        Ok(result) => result,
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(2);
        }
    };
    if let Some(parent) = cli.report.parent() {
        if !parent.as_os_str().is_empty() {
            if let Err(err) = std::fs::create_dir_all(parent) {
                eprintln!("error: cannot create {}: {err}", parent.display());
                std::process::exit(2);
            }
        }
    }
    match serde_json::to_string_pretty(&report) {
        Ok(json) => {
            if let Err(err) = std::fs::write(&cli.report, format!("{json}\n")) {
                eprintln!("error: cannot write {}: {err}", cli.report.display());
                std::process::exit(2);
            }
        }
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(2);
        }
    }
    println!(
        "playtest: {} agents, {} round(s), {:.1} s, {} frags ({:.2} per minute), first frag {}, longest gap {:.1} s, {} spawn deaths ({} at the opening), {:.0} bytes per snapshot",
        report.agents,
        report.rounds_completed,
        report.seconds,
        report.frags,
        report.frags_per_minute,
        report
            .time_to_first_frag_s
            .map(|s| format!("{s:.1} s"))
            .unwrap_or_else(|| "never".to_string()),
        report.longest_gap_without_frag_s,
        report.spawn_deaths,
        report.opening_spawn_deaths,
        report.snapshot_bytes_per_tick
    );
    println!("report: {}", cli.report.display());
    let problems = check_thresholds(&report);
    for problem in &problems {
        println!("threshold: {problem}");
    }
    if cli.assert && !problems.is_empty() {
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_defaults_and_map() {
        let cli = Cli::try_parse_from(["fragr-playtest"]).unwrap();
        let config = config_from(&cli).unwrap();
        assert_eq!(config.agents, 4);
        assert_eq!(config.rounds, 1);
        assert_eq!(config.frag_limit, 5);
        assert_eq!(config.time_limit_ticks, 1200);
        assert_eq!(config.max_ticks, 2400);
        assert_eq!(config.map, fragr_server::sim::MapKind::ArenaDuel);
        assert!(!cli.assert);
        assert!(!cli.fanout_matrix);
        assert_eq!(cli.fanout_seconds, 10);
    }

    #[test]
    fn parses_custom_arguments() {
        let cli = Cli::try_parse_from([
            "fragr-playtest",
            "--agents",
            "8",
            "--rounds",
            "2",
            "--map",
            "compliance-yard",
            "--frag-limit",
            "3",
            "--time-limit-seconds",
            "45",
            "--max-seconds",
            "200",
            "--assert",
        ])
        .unwrap();
        let config = config_from(&cli).unwrap();
        assert_eq!(config.agents, 8);
        assert_eq!(config.rounds, 2);
        assert_eq!(config.map, fragr_server::sim::MapKind::ComplianceYard);
        assert_eq!(config.frag_limit, 3);
        assert_eq!(config.time_limit_ticks, 900);
        assert_eq!(config.max_ticks, 4000);
        assert!(cli.assert);
        let bad = Cli::try_parse_from(["fragr-playtest", "--map", "moon"]).unwrap();
        assert!(config_from(&bad).is_err());
    }

    #[test]
    fn parses_soak_arguments_and_prints_a_verdict() {
        let cli = Cli::try_parse_from([
            "fragr-playtest",
            "--soak",
            "--soak-seconds",
            "120",
            "--soak-sample-seconds",
            "15",
            "--soak-bots",
            "6",
            "--soak-spectators",
            "3",
            "--agents",
            "5",
            "--soak-map-rotate",
            "--soak-server",
            "server-under-test",
            "--soak-log",
            ".agents/soak/ci.ndjson",
            "--map",
            "2",
        ])
        .unwrap();
        let config = soak_config(&cli).unwrap();
        assert_eq!((config.seconds, config.sample_seconds), (120, 15));
        assert_eq!((config.bots, config.agents, config.spectators), (6, 5, 3));
        assert!(config.map_rotate);
        assert_eq!(config.map, fragr_server::sim::MapKind::ComplianceYard);
        assert!(matches!(
            config.launch,
            fragr_playtest::soak::Launch::Binary(ref path) if path == std::path::Path::new("server-under-test")
        ));
        let defaults = Cli::try_parse_from(["fragr-playtest", "--soak"]).unwrap();
        assert_eq!(defaults.soak_seconds, 3600);
        assert_eq!(defaults.soak_sample_seconds, 60);
        assert_eq!(defaults.soak_log, PathBuf::from(".agents/soak/soak.ndjson"));
        assert!(Cli::try_parse_from(["fragr-playtest", "--soak", "--fanout-matrix"]).is_err());
        let bad = Cli::try_parse_from(["fragr-playtest", "--soak", "--map", "moon"]).unwrap();
        assert!(soak_config(&bad).is_err());
        print_soak(
            &fragr_playtest::soak::check_soak(
                &[],
                fragr_playtest::soak::Expected {
                    agents: 1,
                    spectators: 0,
                },
            ),
            std::path::Path::new("x.ndjson"),
        );
    }
}
