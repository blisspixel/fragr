//! Command line front end for the agent playtest harness.

use clap::Parser;
use fragr_playtest::{
    check_contested_ctf, check_contested_sabotage, check_ctf_route_smoke,
    check_sabotage_route_smoke, check_thresholds, run, Config, Policy,
};
use std::path::{Path, PathBuf};
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(
    name = "fragr-playtest",
    version,
    about = "Scripted agents play fragr rounds in-process and file a metrics report."
)]
struct Cli {
    /// Prove a joined fighter takes and scores a flag through a real socket.
    #[arg(long, conflicts_with_all = [
        "ctf_contested", "fanout_matrix", "fanout_seconds", "soak",
        "agents", "rounds", "map", "frag_limit", "capture_limit",
        "time_limit_seconds", "max_seconds", "assert", "seed", "mode",
        "mutators", "tiers", "soak_seconds", "soak_sample_seconds",
        "soak_bots", "soak_spectators", "soak_map_rotate", "soak_server",
        "soak_log"
    ])]
    ctf_route_smoke: bool,
    /// Assert combat and flag replication in a contested CTF observation.
    #[arg(long, requires = "assert", conflicts_with_all = ["soak", "fanout_matrix"])]
    ctf_contested: bool,
    /// Prove an unopposed attacker plants and a defender defuses over a real
    /// socket on Sector 9, using the shared Sabotage controller.
    #[arg(long, conflicts_with_all = [
        "ctf_route_smoke", "ctf_contested", "sabotage_contested", "fanout_matrix",
        "soak", "agents", "rounds", "map", "frag_limit", "capture_limit",
        "time_limit_seconds", "max_seconds", "assert", "seed", "mode",
        "mutators", "tiers"
    ])]
    sabotage_route_smoke: bool,
    /// Assert a contested Sabotage round: results, frags, pickups and rules.
    #[arg(long, requires = "assert", conflicts_with_all = ["soak", "fanout_matrix", "ctf_contested"])]
    sabotage_contested: bool,
    /// Run the local fighter and spectator delivery matrix instead of a round.
    #[arg(long)]
    fanout_matrix: bool,
    /// Bots-only Sabotage survey on Sector 9: whole seeded matches of rule
    /// bots on the session, without sockets. Asserts plants, defuses, round
    /// wins for both sides and no stuck round when --assert is set.
    #[arg(long, conflicts_with_all = ["soak", "fanout_matrix", "ctf_route_smoke", "ctf_contested"])]
    sabotage_survey: bool,
    /// Matches the survey plays, one per seed from --seed upward.
    #[arg(long, default_value_t = 16, value_parser = clap::value_parser!(u64).range(1..=1000))]
    survey_seeds: u64,
    /// Rule bots in each surveyed match, split between the sides.
    #[arg(long, default_value_t = 8, value_parser = clap::value_parser!(u64).range(2..=16))]
    survey_bots: u64,
    /// Sabotage match length for --mode sabotage and the survey: short or match.
    #[arg(long, value_enum, default_value_t = fragr_server::protocol::SabotageFormat::Short)]
    sabotage_format: fragr_server::protocol::SabotageFormat,
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
    /// Captures that end a capture the flag round.
    #[arg(long, default_value_t = 3, value_parser = clap::value_parser!(u32).range(1..=99))]
    capture_limit: u32,
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
    /// Match mode: ffa, tdm, or ctf. Capture the flag runs on a map with stands.
    #[arg(long, value_enum, default_value_t = fragr_server::protocol::GameMode::Ffa)]
    mode: fragr_server::protocol::GameMode,
    /// A host rule twist, repeatable: rail-only, shotgun-only, fists-only,
    /// licence-to-kill, golden-rail, two-lives.
    #[arg(long = "mutator", value_enum)]
    mutators: Vec<fragr_server::protocol::Mutator>,
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
    /// Fill a local server with synthetic fighters and read-only spectators.
    /// Fighters send movement and fire. They do not pathfind.
    #[arg(long, conflicts_with_all = [
        "soak", "fanout_matrix", "ctf_route_smoke", "ctf_contested",
        "sabotage_route_smoke", "sabotage_contested", "sabotage_survey"
    ])]
    traffic: bool,
    /// Synthetic humans. Together with spectators, at most 64.
    #[arg(long, default_value_t = 8)]
    traffic_fighters: usize,
    /// Spectators that only read the live stream.
    #[arg(long, default_value_t = 4)]
    traffic_spectators: usize,
    /// Seconds to hold the roster after every client has a snapshot.
    #[arg(long, default_value_t = 10, value_parser = clap::value_parser!(u64).range(1..=3600))]
    traffic_seconds: u64,
    /// Actions per fighter per second. The server allows 256 inbound messages.
    #[arg(long, default_value_t = 60, value_parser = clap::value_parser!(u32).range(1..=120))]
    traffic_hz: u32,
    /// Rule bots beside the synthetic fighters. At most 32.
    #[arg(long, default_value_t = 4)]
    traffic_bots: usize,
    /// The `fragr-server` binary to stress. Defaults to the one beside this tool.
    #[arg(long)]
    traffic_server: Option<PathBuf>,
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

fn traffic_config(cli: &Cli) -> Result<fragr_playtest::traffic::TrafficConfig, String> {
    let map = fragr_server::sim::MapKind::from_cli(&cli.map)
        .ok_or_else(|| format!("invalid --map {:?}", cli.map))?;
    let binary = cli
        .traffic_server
        .clone()
        .or_else(fragr_playtest::soak::default_server_binary)
        .ok_or("no fragr-server beside this tool; build it or pass --traffic-server")?;
    let report = if cli.report.as_path() == Path::new(".agents/playtest/report.json") {
        PathBuf::from(".agents/traffic/report.json")
    } else {
        cli.report.clone()
    };
    Ok(fragr_playtest::traffic::TrafficConfig {
        seconds: cli.traffic_seconds,
        fighters: cli.traffic_fighters,
        spectators: cli.traffic_spectators,
        bots: cli.traffic_bots,
        hz: cli.traffic_hz,
        map,
        seed: cli.seed,
        launch: fragr_playtest::soak::Launch::Binary(binary),
        report,
    })
}

fn print_traffic(report: &fragr_playtest::traffic::TrafficReport) {
    println!(
        "traffic: {} fighters, {} spectators, {} bots, {} Hz for {} s, {} actions, {} fighter snapshots, {} spectator snapshots, {:.0} KiB in, ticks {} to {}, p99 {} ms, health {}",
        report.fighters,
        report.spectators,
        report.bots,
        report.hz,
        report.seconds,
        report.actions_sent,
        report.fighter_snapshots,
        report.spectator_snapshots,
        report.text_bytes as f64 / 1024.0,
        report.tick_start,
        report.tick_end,
        report
            .tick_p99_ms
            .map(|ms| format!("{ms:.2}"))
            .unwrap_or_else(|| "unavailable".into()),
        report.health.as_deref().unwrap_or("unavailable"),
    );
    for problem in &report.problems {
        println!("traffic problem: {problem}");
    }
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

fn print_survey(report: &fragr_playtest::sabotage::SurveyReport) {
    let finished = report.matches.iter().filter(|m| m.finished).count();
    println!(
        "sabotage survey: {} of {} matches finished, {} rounds, attackers won {:.0} percent, mean round {:.1} s, longest {:.1} s",
        finished,
        report.matches.len(),
        report.rounds.len(),
        report.attacker_round_share * 100.0,
        report.mean_round_seconds,
        report.longest_round_seconds
    );
    println!(
        "charge: {} plants started, {} planted, {} interrupted; {} defuses started, {} defused; {} detonations; {} drops, {} pickups; {} swaps",
        report.plants_started,
        report.plants,
        report.plants_interrupted,
        report.defuses_started,
        report.defuses,
        report.detonations,
        report.charge_drops,
        report.charge_pickups,
        report.swaps
    );
    let wins: Vec<String> = report
        .wins
        .iter()
        .map(|(key, count)| format!("{key} {count}"))
        .collect();
    println!("round wins: {}", wins.join(", "));
    let tally = |map: &std::collections::BTreeMap<String, u32>| {
        let mut rows: Vec<(&String, &u32)> = map.iter().collect();
        rows.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
        rows.iter()
            .map(|(key, count)| format!("{key} {count}"))
            .collect::<Vec<_>>()
            .join(", ")
    };
    println!("deaths: {}", tally(&report.deaths));
    println!("charge drops: {}", tally(&report.drop_callouts));
    let hot: std::collections::BTreeMap<String, u32> = report
        .death_grid
        .iter()
        .filter(|(_, count)| **count >= 3)
        .map(|(key, count)| (key.clone(), *count))
        .collect();
    println!("death cells (3 or more): {}", tally(&hot));
    println!("unarmed when live: {}", tally(&report.unarmed_at_live));
}

fn config_from(cli: &Cli) -> Result<Config, String> {
    if cli.ctf_route_smoke {
        return Ok(Config {
            agents: 1,
            rounds: 1,
            map: fragr_server::sim::MapKind::Sector9,
            capture_limit: 1,
            time_limit_ticks: 20 * 180,
            max_ticks: 20 * 190,
            seed: 42,
            tiers: vec![Policy::RouteProbe],
            rules: fragr_server::rules::RuleSet::new(
                fragr_server::protocol::GameMode::Ctf,
                &[],
                false,
            )
            .map_err(|error| format!("invalid CTF route rules: {error}"))?,
            ..Config::default()
        });
    }
    if cli.sabotage_route_smoke {
        return Ok(Config {
            agents: 2,
            rounds: 1,
            map: fragr_server::sim::MapKind::Sector9,
            time_limit_ticks: 20 * 105,
            max_ticks: 20 * 140,
            seed: 42,
            tiers: vec![Policy::RouteProbe],
            rules: fragr_server::rules::RuleSet::new(
                fragr_server::protocol::GameMode::Sabotage,
                &[],
                false,
            )
            .map_err(|error| format!("invalid Sabotage route rules: {error}"))?,
            sabotage: fragr_server::rules::SabotageConfig {
                muster_ticks: 20 * 3,
                ..fragr_server::rules::SabotageConfig::default()
            },
            ..Config::default()
        });
    }
    if cli.ctf_contested && cli.mode != fragr_server::protocol::GameMode::Ctf {
        return Err("--ctf-contested requires --mode ctf".into());
    }
    if cli.sabotage_contested && cli.mode != fragr_server::protocol::GameMode::Sabotage {
        return Err("--sabotage-contested requires --mode sabotage".into());
    }
    let map = fragr_server::sim::MapKind::from_cli(&cli.map)
        .ok_or_else(|| format!("invalid --map {:?}", cli.map))?;
    if cli.mode == fragr_server::protocol::GameMode::Ctf && map.ctf_stands().is_none() {
        return Err("ctf requires a map with validated flag stands".into());
    }
    if cli.mode == fragr_server::protocol::GameMode::Sabotage && map.sabotage_map().is_none() {
        return Err("sabotage requires a map with validated sites (map 4, Sector 9)".into());
    }
    Ok(Config {
        agents: cli.agents,
        rounds: cli.rounds,
        map,
        frag_limit: cli.frag_limit,
        capture_limit: cli.capture_limit,
        time_limit_ticks: cli.time_limit_seconds * 20,
        max_ticks: cli.max_seconds * 20,
        seed: cli.seed,
        tiers: fragr_playtest::Policy::parse_list(&cli.tiers)
            .map_err(|e| format!("invalid --tiers {:?}: {e}", cli.tiers))?,
        rules: fragr_server::rules::RuleSet::new(cli.mode, &cli.mutators, false)
            .map_err(|e| format!("invalid rule set: {e}"))?,
        // Harness rounds muster for three seconds; the live clock is
        // --time-limit-seconds.
        sabotage: fragr_server::rules::SabotageConfig {
            format: cli.sabotage_format,
            muster_ticks: 20 * 3,
            ..fragr_server::rules::SabotageConfig::default()
        },
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
    if cli.sabotage_survey {
        let config = fragr_playtest::sabotage::SurveyConfig {
            seeds: (cli.seed..cli.seed + cli.survey_seeds).collect(),
            bots: cli.survey_bots as usize,
            format: cli.sabotage_format,
            ..fragr_playtest::sabotage::SurveyConfig::default()
        };
        let report = fragr_playtest::sabotage::run_survey(&config);
        if let Some(parent) = cli.report.parent() {
            if !parent.as_os_str().is_empty() {
                if let Err(error) = std::fs::create_dir_all(parent) {
                    eprintln!("error: cannot create {}: {error}", parent.display());
                    std::process::exit(2);
                }
            }
        }
        let json = serde_json::to_string_pretty(&report).expect("survey report serializes");
        if let Err(error) = std::fs::write(
            &cli.report,
            format!(
                "{json}
"
            ),
        ) {
            eprintln!("error: cannot write {}: {error}", cli.report.display());
            std::process::exit(2);
        }
        print_survey(&report);
        println!("report: {}", cli.report.display());
        let problems = fragr_playtest::sabotage::check_survey(&report);
        for problem in &problems {
            println!("threshold: {problem}");
        }
        if cli.assert && !problems.is_empty() {
            std::process::exit(1);
        }
        return;
    }
    if cli.traffic {
        let config = match traffic_config(&cli) {
            Ok(config) => config,
            Err(error) => {
                eprintln!("error: {error}");
                std::process::exit(2);
            }
        };
        let report_path = config.report.clone();
        let report = match fragr_playtest::traffic::run(config).await {
            Ok(report) => report,
            Err(error) => {
                eprintln!("error: {error}");
                std::process::exit(2);
            }
        };
        print_traffic(&report);
        println!("report: {}", report_path.display());
        if cli.assert && !report.passed {
            std::process::exit(1);
        }
        return;
    }
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
    let (report, observation) = match run(config).await {
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
    if let Some(rules) = report.rules.as_ref() {
        println!(
            "rules: {}, sides {:?}, {} host reactions, {} team kills",
            rules.name, report.sides, report.host_reactions, report.team_kills
        );
        if rules.mode == fragr_server::protocol::GameMode::Sabotage {
            let rounds: Vec<String> = report
                .sabotage_rounds
                .iter()
                .map(|(winner, result)| {
                    format!(
                        "{} {}",
                        winner.map_or("none", |t| t.id()),
                        result.reason.id()
                    )
                })
                .collect();
            println!(
                "sabotage: events {:?}, rounds [{}]",
                report.sabotage_events,
                rounds.join(", ")
            );
        }
        if rules.mode == fragr_server::protocol::GameMode::Ctf {
            println!(
                "flags: {} takes, {} drops, {} returns, {} captures, {:.1} carrier seconds, last round {:?} {:?}",
                report.flag_takes,
                report.flag_drops,
                report.flag_returns,
                report.captures,
                report.carrier_seconds,
                report.last_round_reason,
                report.last_round_capture_scores
            );
        }
    }
    println!("report: {}", cli.report.display());
    let problems = if cli.ctf_route_smoke {
        check_ctf_route_smoke(&report, &observation)
    } else if cli.sabotage_route_smoke {
        check_sabotage_route_smoke(&report)
    } else if cli.ctf_contested {
        check_contested_ctf(&report, &observation)
    } else if cli.sabotage_contested {
        check_contested_sabotage(&report)
    } else {
        check_thresholds(&report)
    };
    for problem in &problems {
        println!("threshold: {problem}");
    }
    if (cli.assert || cli.ctf_route_smoke || cli.sabotage_route_smoke) && !problems.is_empty() {
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
    fn controlled_route_and_contested_ctf_have_distinct_gate_configs() {
        let route = Cli::try_parse_from(["fragr-playtest", "--ctf-route-smoke"]).unwrap();
        let config = config_from(&route).unwrap();
        assert_eq!(config.agents, 1);
        assert_eq!(config.map, fragr_server::sim::MapKind::Sector9);
        assert_eq!(config.tiers, vec![Policy::RouteProbe]);
        assert_eq!(config.capture_limit, 1);
        assert_eq!(config.rules.mode(), fragr_server::protocol::GameMode::Ctf);
        for extra in [["--map", "99"], ["--mode", "tdm"], ["--seed", "99"]] {
            assert!(Cli::try_parse_from([
                "fragr-playtest",
                "--ctf-route-smoke",
                extra[0],
                extra[1]
            ])
            .is_err());
        }

        let contested = Cli::try_parse_from([
            "fragr-playtest",
            "--mode",
            "ctf",
            "--map",
            "4",
            "--assert",
            "--ctf-contested",
        ])
        .unwrap();
        assert!(config_from(&contested).is_ok());
        assert!(Cli::try_parse_from(["fragr-playtest", "--ctf-contested"]).is_err());
        let wrong_mode =
            Cli::try_parse_from(["fragr-playtest", "--assert", "--ctf-contested"]).unwrap();
        assert!(config_from(&wrong_mode).is_err());
    }

    #[test]
    fn sabotage_gates_have_their_own_configs() {
        let route = Cli::try_parse_from(["fragr-playtest", "--sabotage-route-smoke"]).unwrap();
        let config = config_from(&route).unwrap();
        assert_eq!(config.agents, 2);
        assert_eq!(config.map, fragr_server::sim::MapKind::Sector9);
        assert_eq!(config.tiers, vec![Policy::RouteProbe]);
        assert_eq!(
            config.rules.mode(),
            fragr_server::protocol::GameMode::Sabotage
        );
        assert!(
            Cli::try_parse_from(["fragr-playtest", "--sabotage-route-smoke", "--map", "1"])
                .is_err()
        );
        let contested = Cli::try_parse_from([
            "fragr-playtest",
            "--mode",
            "sabotage",
            "--map",
            "4",
            "--assert",
            "--sabotage-contested",
        ])
        .unwrap();
        let config = config_from(&contested).unwrap();
        assert_eq!(config.sabotage.muster_ticks, 60);
        assert!(Cli::try_parse_from(["fragr-playtest", "--sabotage-contested"]).is_err());
        let wrong_mode =
            Cli::try_parse_from(["fragr-playtest", "--assert", "--sabotage-contested"]).unwrap();
        assert!(config_from(&wrong_mode).is_err());
        let no_sites = Cli::try_parse_from(["fragr-playtest", "--mode", "sabotage"]).unwrap();
        assert!(config_from(&no_sites).is_err(), "Arena Duel has no sites");
        let survey = Cli::try_parse_from([
            "fragr-playtest",
            "--sabotage-survey",
            "--survey-seeds",
            "3",
            "--survey-bots",
            "6",
        ])
        .unwrap();
        assert!(survey.sabotage_survey);
        assert_eq!((survey.survey_seeds, survey.survey_bots), (3, 6));
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
    fn parses_a_rule_set() {
        let cli = Cli::try_parse_from([
            "fragr-playtest",
            "--mode",
            "tdm",
            "--mutator",
            "rail-only",
            "--mutator",
            "licence-to-kill",
        ])
        .unwrap();
        let config = config_from(&cli).unwrap();
        assert!(config.rules.teams());
        assert_eq!(
            config.rules.name(),
            "Team Deathmatch: Rail Only, Licence to Kill"
        );
        let clash = Cli::try_parse_from([
            "fragr-playtest",
            "--mutator",
            "rail-only",
            "--mutator",
            "fists-only",
        ])
        .unwrap();
        assert!(config_from(&clash).is_err());
        let ctf_without_stands = Cli::try_parse_from([
            "fragr-playtest",
            "--mode",
            "ctf",
            "--map",
            "compliance-yard",
        ])
        .unwrap();
        assert!(
            config_from(&ctf_without_stands).is_err(),
            "Compliance Yard has no flag stands"
        );
        let ctf_default = Cli::try_parse_from(["fragr-playtest", "--mode", "ctf"]).unwrap();
        assert_eq!(
            config_from(&ctf_default).unwrap().map,
            fragr_server::sim::MapKind::ArenaDuel
        );
        let ctf = Cli::try_parse_from([
            "fragr-playtest",
            "--mode",
            "ctf",
            "--map",
            "4",
            "--capture-limit",
            "2",
        ])
        .unwrap();
        let ctf_config = config_from(&ctf).unwrap();
        assert_eq!(ctf_config.map, fragr_server::sim::MapKind::Sector9);
        assert_eq!(ctf_config.capture_limit, 2);
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
        assert!(Cli::try_parse_from(["fragr-playtest", "--traffic", "--soak"]).is_err());
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

    #[test]
    fn parses_traffic_arguments() {
        let cli = Cli::try_parse_from([
            "fragr-playtest",
            "--traffic",
            "--traffic-fighters",
            "12",
            "--traffic-spectators",
            "20",
            "--traffic-seconds",
            "30",
            "--traffic-hz",
            "30",
            "--traffic-bots",
            "0",
            "--traffic-server",
            "server-under-test",
            "--map",
            "4",
            "--seed",
            "9",
            "--assert",
        ])
        .unwrap();
        let config = traffic_config(&cli).unwrap();
        assert_eq!(config.fighters, 12);
        assert_eq!(config.spectators, 20);
        assert_eq!(config.seconds, 30);
        assert_eq!(config.hz, 30);
        assert_eq!(config.bots, 0);
        assert_eq!(config.seed, 9);
        assert_eq!(config.map, fragr_server::sim::MapKind::Sector9);
        assert_eq!(config.report, PathBuf::from(".agents/traffic/report.json"));
        assert!(cli.assert);
        let custom = Cli::try_parse_from([
            "fragr-playtest",
            "--traffic",
            "--report",
            ".agents/traffic/custom.json",
            "--traffic-server",
            "server-under-test",
        ])
        .unwrap();
        assert_eq!(
            traffic_config(&custom).unwrap().report,
            PathBuf::from(".agents/traffic/custom.json")
        );
        let bad = Cli::try_parse_from(["fragr-playtest", "--traffic", "--map", "moon"]).unwrap();
        assert!(traffic_config(&bad).is_err());
    }
}
