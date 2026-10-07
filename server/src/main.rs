use clap::{CommandFactory, FromArgMatches, Parser};
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

    /// Fixed rule bots, no bots, or automatic total fighter population.
    #[arg(long, value_enum, default_value = "fixed", conflicts_with_all = ["local_mission", "local_run_preview", "bench", "bench_verify_trace"])]
    bot_policy: fragr_server::bot_fill::BotPolicy,

    /// Desired total fighter count for automatic fill, 1 through 10.
    #[arg(long, default_value = "0", conflicts_with_all = ["local_mission", "local_run_preview", "bench", "bench_verify_trace"])]
    fill_target: usize,

    /// Map: 1/arena, 2/compliance-yard, 3/directive-17, 4/sector-9,
    /// 5/reclamation-gulch, 6/tripoint-works.
    #[arg(long, default_value = "1")]
    map: String,

    /// Load a local authored campaign development map. Requires --bots 0.
    #[arg(group = "campaign_source")]
    #[arg(long, conflicts_with_all = ["map", "map_rotate", "solo_broadcast", "bench", "bench_verify_trace", "no_round_events"])]
    map_file: Option<PathBuf>,

    /// Run the bundled mission for a desktop parent. Readiness is JSON on stdout;
    /// stdin shutdown or EOF ends this loopback-only child.
    #[arg(group = "campaign_source")]
    #[arg(long, value_parser = ["recall_notice", "persons_unknown", "scheduled_service", "notice_to_vacate", "no_forwarding_address", "port_of_entry", "declared_goods", "custodian_of_record", "passenger_manifest", "common_carrier", "right_of_search"], conflicts_with_all = ["bind", "bots", "map", "map_file", "map_rotate", "solo_broadcast", "no_round_events", "bench", "bench_verify_trace", "status_every_s"])]
    local_mission: Option<String>,

    /// Own a desktop TDM or five-per-side Sabotage server. Readiness is JSON
    /// on stdout; stdin shutdown or EOF ends only this explicit child.
    #[arg(long, conflicts_with_all = ["campaign_source", "run_mode", "local_run_preview", "map_rotate", "solo_broadcast", "no_round_events", "bench", "bench_verify_trace", "mutators", "friendly_fire", "frag_limit", "capture_limit", "sabotage_format"])]
    desktop_host: bool,

    /// Persist an owned desktop campaign run. Omit for ephemeral development runs.
    #[arg(long, value_enum, requires = "local_mission")]
    run_mode: Option<fragr_server::local::LocalRunMode>,

    /// Read-only compatibility summary for the local campaign menu.
    #[arg(long, conflicts_with_all = ["local_mission", "map_file", "map", "bots", "bind", "campaign_run", "difficulty", "bench", "bench_verify_trace"])]
    local_run_preview: bool,

    /// Shared campaign pressure. Fixed for this run; does not change arcade rules.
    #[arg(long, value_enum, requires = "campaign_source", conflicts_with_all = ["bench", "bench_verify_trace", "solo_broadcast", "map_rotate", "no_round_events"])]
    difficulty: Option<fragr_server::protocol::CampaignDifficulty>,

    /// One combatant, three mission-start continues. Leaving ends this run.
    #[arg(long, requires = "campaign_source")]
    campaign_run: bool,

    /// Move to the next map in the roster each round.
    #[arg(long, default_value_t = false)]
    map_rotate: bool,

    /// Stay up and rotate the built-in night list of maps and modes.
    /// Sabotage plays its short match, including the half-time swap, before
    /// the list moves. A fixed map, mode, mutator, or limit cannot combine.
    #[arg(long, default_value_t = false, conflicts_with_all = ["map", "map_rotate", "map_file", "local_mission", "desktop_host", "solo_broadcast", "mode", "mutators", "friendly_fire", "frag_limit", "capture_limit", "sabotage_format", "sabotage_five_v_five", "no_round_events", "bench", "bench_verify_trace", "campaign_run", "difficulty", "run_mode", "local_run_preview"])]
    playlist: bool,

    /// Contested Frequency Solo Broadcast Episode 0 (Calibration / Larak Lot).
    /// NODS clear + jammer dish + Auditor. MP unchanged when off.
    #[arg(long, default_value_t = false)]
    solo_broadcast: bool,

    /// Disable timed compliance slowdowns and boss spawns for arena practice.
    #[arg(long, conflicts_with_all = ["solo_broadcast", "bench", "bench_verify_trace"])]
    no_round_events: bool,

    /// Match mode: ffa, tdm, ctf, sabotage or conquest. Conquest uses Holdfast Atoll.
    /// Capture the flag runs on Arena
    /// Duel, Directive 17, or Sector 9; Sabotage runs on Sector 9.
    #[arg(long, value_enum, default_value_t = fragr_server::protocol::GameMode::Ffa, conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    mode: fragr_server::protocol::GameMode,

    /// A host rule twist, repeatable: rail-only, shotgun-only, fists-only,
    /// licence-to-kill, golden-rail, two-lives.
    #[arg(long = "mutator", value_enum, conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    mutators: Vec<fragr_server::protocol::Mutator>,

    /// Team damage lands. Needs a team mode. Off by default.
    #[arg(long, conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    friendly_fire: bool,

    /// Frags that end a round: a fighter's in ffa, a side's in tdm.
    /// Defaults to 10 in ffa and 25 in tdm; unavailable in ctf.
    #[arg(long, value_parser = clap::value_parser!(u32).range(1..=999), conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    frag_limit: Option<u32>,

    /// Captures that end a ctf round (default 3). Only valid with --mode ctf.
    #[arg(long, value_parser = clap::value_parser!(u32).range(1..=99), conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    capture_limit: Option<u32>,

    /// Sabotage match length: short (halves of 4, first to 5, the default)
    /// or match (halves of 8, first to 9). Only valid with --mode sabotage.
    #[arg(long, value_enum, conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    sabotage_format: Option<fragr_server::protocol::SabotageFormat>,

    /// Limit Sabotage to ten seated fighters, five per side. Spectators remain welcome.
    #[arg(long, conflicts_with_all = ["campaign_source", "solo_broadcast", "bench", "bench_verify_trace"])]
    sabotage_five_v_five: bool,

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

    /// Refuse these addresses. One IP or CIDR range per line, with optional
    /// `expires=YYYY-MM-DD` and `reason=...`. Read again every five seconds.
    #[arg(long, conflicts_with_all = ["local_mission", "local_run_preview", "bench", "bench_verify_trace"])]
    ban_list: Option<PathBuf>,

    /// Admit only these addresses, same format. A ban still wins.
    #[arg(long, conflicts_with_all = ["local_mission", "local_run_preview", "bench", "bench_verify_trace"])]
    allow_list: Option<PathBuf>,

    /// Local venue desk on this terminal: who, kick, ban, say, and stats.
    /// Closing the input leaves the match running.
    #[arg(
        long,
        default_value_t = false,
        conflicts_with_all = [
            "desktop_host",
            "local_mission",
            "local_run_preview",
            "bench",
            "bench_verify_trace",
            "map_file"
        ]
    )]
    console: bool,
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
    fragr_server::metrics::mark_process_start();
    let matches = Args::command().get_matches();
    let args = Args::from_arg_matches(&matches)?;
    if args.desktop_host
        && matches.value_source("bind") != Some(clap::parser::ValueSource::CommandLine)
    {
        return Err("--desktop-host requires an explicit --bind address".into());
    }
    // In benchmark mode the JSON report is the only thing on stdout, so logs
    // go to stderr and only warnings survive.
    init_tracing(args.bench.is_some() || args.local_run_preview);
    if args.local_run_preview {
        let preview =
            fragr_server::local::preview_run(fragr_server::protocol::MissionId::RecallNotice)?;
        println!("{}", serde_json::to_string(&preview)?);
        return Ok(());
    }
    if let Some(mission) = args.local_mission.as_deref() {
        let mission = match mission {
            "persons_unknown" => fragr_server::protocol::MissionId::PersonsUnknown,
            "scheduled_service" => fragr_server::protocol::MissionId::ScheduledService,
            "notice_to_vacate" => fragr_server::protocol::MissionId::NoticeToVacate,
            "no_forwarding_address" => fragr_server::protocol::MissionId::NoForwardingAddress,
            "port_of_entry" => fragr_server::protocol::MissionId::PortOfEntry,
            "custodian_of_record" => fragr_server::protocol::MissionId::CustodianOfRecord,
            "passenger_manifest" => fragr_server::protocol::MissionId::PassengerManifest,
            "common_carrier" => fragr_server::protocol::MissionId::CommonCarrier,
            "right_of_search" => fragr_server::protocol::MissionId::RightOfSearch,
            "declared_goods" => fragr_server::protocol::MissionId::DeclaredGoods,
            _ => fragr_server::protocol::MissionId::RecallNotice,
        };
        return fragr_server::local::serve_with_mode(
            mission,
            args.seed,
            args.difficulty.unwrap_or_default(),
            args.run_mode,
            std::io::stdin(),
            std::io::stdout(),
        )
        .await;
    }
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

    let join_secret = match fragr_server::join_ticket::JoinSecret::from_process_env() {
        Ok(secret) => secret.map(std::sync::Arc::new),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    };
    let access = fragr_server::access::AccessConfig {
        ban_list: args.ban_list,
        allow_list: args.allow_list,
    };
    if let Err(error) = fragr_server::access::validate(&access) {
        eprintln!("{error}");
        std::process::exit(1);
    }
    let rules =
        match fragr_server::rules::RuleSet::new(args.mode, &args.mutators, args.friendly_fire) {
            Ok(rules) => rules,
            Err(error) => {
                eprintln!("invalid rule set: {error}");
                std::process::exit(2);
            }
        };
    if rules.mode() == fragr_server::protocol::GameMode::Ctf && args.frag_limit.is_some() {
        return Err("ctf uses --capture-limit, not --frag-limit".into());
    }
    if rules.mode() == fragr_server::protocol::GameMode::Conquest && args.frag_limit.is_some() {
        return Err("conquest is decided by tickets; --frag-limit does not apply".into());
    }
    if rules.mode() != fragr_server::protocol::GameMode::Ctf && args.capture_limit.is_some() {
        return Err("--capture-limit requires --mode ctf".into());
    }
    if rules.mode() == fragr_server::protocol::GameMode::Sabotage && args.frag_limit.is_some() {
        return Err("sabotage is won by rounds, not --frag-limit".into());
    }
    if rules.mode() != fragr_server::protocol::GameMode::Sabotage && args.sabotage_format.is_some()
    {
        return Err("--sabotage-format requires --mode sabotage".into());
    }
    let mut match_config = match_config(rules, args.frag_limit, args.no_round_events);
    if args.sabotage_five_v_five && args.mode != fragr_server::protocol::GameMode::Sabotage {
        return Err("--sabotage-five-v-five requires --mode sabotage".into());
    }
    if let Some(config) = match_config.as_mut() {
        config.sabotage.five_vs_five = args.sabotage_five_v_five;
        if let Some(format) = args.sabotage_format {
            config.sabotage.format = format;
        }
        if config.rules.mode() == fragr_server::protocol::GameMode::Ctf {
            config.capture_limit = Some(
                args.capture_limit
                    .unwrap_or(fragr_server::rules::CTF_CAPTURE_LIMIT),
            );
        }
    }
    let options = ServerOptions {
        bind: args.bind,
        bots: args.bots,
        bot_policy: args.bot_policy,
        fill_target: args.fill_target,
        map,
        authored: args.map_file.map(fragr_server::maps::AuthoredSource::File),
        difficulty: args.difficulty,
        campaign_run: args.campaign_run,
        map_rotate: args.map_rotate,
        playlist: args.playlist,
        match_config,
        solo_broadcast: args.solo_broadcast,
        seed: args.seed,
        status_every_s: args.status_every_s,
        join_secret,
        access,
        console: args.console,
    };
    if args.desktop_host {
        fragr_server::local::serve_arena(options, std::io::stdin(), std::io::stdout()).await
    } else {
        run_server(options, std::future::pending::<()>(), None).await
    }
}

/// Arcade rules from the host's flags. None keeps the plain defaults, which
/// is also what an authored campaign map requires.
fn match_config(
    rules: fragr_server::rules::RuleSet,
    frag_limit: Option<u32>,
    no_round_events: bool,
) -> Option<fragr_server::sim::MatchConfig> {
    if rules.is_plain() && frag_limit.is_none() && !no_round_events {
        return None;
    }
    let defaults = fragr_server::sim::MatchConfig::default();
    let objective = rules.mode().objective();
    let sabotage = rules.mode() == fragr_server::protocol::GameMode::Sabotage;
    let conquest = rules.mode() == fragr_server::protocol::GameMode::Conquest;
    Some(fragr_server::sim::MatchConfig {
        frag_limit: (!objective).then(|| frag_limit.unwrap_or_else(|| rules.default_frag_limit())),
        // Sabotage runs its own muster, live and charge clocks.
        time_limit_ticks: if conquest {
            Some(20 * 60 * 10)
        } else {
            (!sabotage).then_some(defaults.time_limit_ticks).flatten()
        },
        boss_spawn_ticks: (!no_round_events && !objective)
            .then_some(defaults.boss_spawn_ticks)
            .flatten(),
        compliance_ping_ticks: (!no_round_events && !objective)
            .then_some(defaults.compliance_ping_ticks)
            .flatten(),
        rules,
        ..defaults
    })
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

    #[test]
    fn conquest_match_config_has_ten_minute_ticket_clock_without_round_events() {
        for no_round_events in [false, true] {
            let rules = fragr_server::rules::RuleSet::new(
                fragr_server::protocol::GameMode::Conquest,
                &[],
                false,
            )
            .unwrap();
            let config = match_config(rules, None, no_round_events).unwrap();
            assert_eq!(config.time_limit_ticks, Some(600 * 20));
            assert_eq!(config.frag_limit, None);
            assert_eq!(config.capture_limit, None);
            assert_eq!(config.boss_spawn_ticks, None);
            assert_eq!(config.compliance_ping_ticks, None);
        }
    }
    use futures_util::{SinkExt, StreamExt};
    use std::net::SocketAddr;
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    #[test]
    fn difficulty_is_explicit_campaign_only_configuration() {
        for tier in ["assisted", "standard", "severe"] {
            assert!(Args::try_parse_from([
                "fragr-server",
                "--local-mission",
                "recall_notice",
                "--difficulty",
                tier
            ])
            .is_ok());
            assert!(Args::try_parse_from([
                "fragr-server",
                "--map-file",
                "mission.json",
                "--bots",
                "0",
                "--difficulty",
                tier
            ])
            .is_ok());
            assert!(Args::try_parse_from(["fragr-server", "--difficulty", tier]).is_err());
            assert!(
                Args::try_parse_from(["fragr-server", "--bench", "16", "--difficulty", tier])
                    .is_err()
            );
        }
        assert!(Args::try_parse_from([
            "fragr-server",
            "--local-mission",
            "recall_notice",
            "--difficulty",
            "adaptive"
        ])
        .is_err());
    }

    #[test]
    fn local_mission_accepts_only_registered_bundled_missions() {
        for mission in [
            "recall_notice",
            "persons_unknown",
            "scheduled_service",
            "notice_to_vacate",
            "no_forwarding_address",
            "port_of_entry",
            "declared_goods",
            "custodian_of_record",
            "passenger_manifest",
            "common_carrier",
            "right_of_search",
        ] {
            let args = Args::try_parse_from(["fragr-server", "--local-mission", mission]).unwrap();
            assert_eq!(args.local_mission.as_deref(), Some(mission));
        }
        assert!(Args::try_parse_from(["fragr-server", "--local-mission", "m03"]).is_err());
    }

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
    fn playlist_is_a_night_list_not_a_fixed_mode() {
        let args = Args::try_parse_from(["fragr-server", "--playlist"]).unwrap();
        assert!(args.playlist);
        assert!(!args.map_rotate);
        for rejected in [
            &["fragr-server", "--playlist", "--map", "2"][..],
            &["fragr-server", "--playlist", "--mode", "tdm"][..],
            &["fragr-server", "--playlist", "--map-rotate"][..],
            &["fragr-server", "--playlist", "--mutator", "rail-only"][..],
            &["fragr-server", "--playlist", "--frag-limit", "5"][..],
            &["fragr-server", "--playlist", "--no-round-events"][..],
        ] {
            assert!(Args::try_parse_from(rejected).is_err(), "{rejected:?}");
        }
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

    #[test]
    fn host_picks_a_mode_and_repeatable_mutators() {
        use fragr_server::protocol::{GameMode, Mutator};
        let args = Args::try_parse_from([
            "fragr-server",
            "--mode",
            "tdm",
            "--mutator",
            "rail-only",
            "--mutator",
            "two-lives",
            "--friendly-fire",
            "--frag-limit",
            "30",
        ])
        .unwrap();
        assert_eq!(args.mode, GameMode::Tdm);
        assert_eq!(args.mutators, [Mutator::RailOnly, Mutator::TwoLives]);
        assert!(args.friendly_fire);
        let rules =
            fragr_server::rules::RuleSet::new(args.mode, &args.mutators, args.friendly_fire)
                .unwrap();
        let config = match_config(rules, args.frag_limit, args.no_round_events).unwrap();
        assert_eq!(config.frag_limit, Some(30));
        assert!(config.boss_spawn_ticks.is_some());
        assert_eq!(config.rules.lives(), Some(2));

        let defaults = Args::try_parse_from(["fragr-server"]).unwrap();
        assert_eq!(defaults.mode, GameMode::Ffa);
        assert!(defaults.mutators.is_empty());
        assert!(match_config(Default::default(), None, false).is_none());
        let team = fragr_server::rules::RuleSet::new(GameMode::Tdm, &[], false).unwrap();
        assert_eq!(
            match_config(team, None, false).unwrap().frag_limit,
            Some(25)
        );
        let quiet = match_config(Default::default(), None, true).unwrap();
        assert_eq!(quiet.boss_spawn_ticks, None);
        assert_eq!(quiet.compliance_ping_ticks, None);
        assert_eq!(quiet.frag_limit, Some(10));

        let ctf = Args::try_parse_from([
            "fragr-server",
            "--mode",
            "ctf",
            "--map",
            "4",
            "--capture-limit",
            "2",
        ])
        .unwrap();
        assert_eq!(ctf.mode, GameMode::Ctf);
        assert_eq!(ctf.capture_limit, Some(2));
        let ctf_rules = fragr_server::rules::RuleSet::new(GameMode::Ctf, &[], false).unwrap();
        let ctf_config = match_config(ctf_rules, None, false).unwrap();
        assert_eq!(ctf_config.boss_spawn_ticks, None);
        assert_eq!(ctf_config.compliance_ping_ticks, None);

        for bad in [
            vec!["fragr-server", "--mutator", "low-gravity"],
            vec!["fragr-server", "--frag-limit", "0"],
            vec!["fragr-server", "--mode", "tdm", "--solo-broadcast"],
            vec!["fragr-server", "--mutator", "rail-only", "--bench", "4"],
            vec![
                "fragr-server",
                "--local-mission",
                "recall_notice",
                "--mode",
                "tdm",
            ],
        ] {
            assert!(Args::try_parse_from(&bad).is_err(), "{bad:?}");
        }
    }

    #[tokio::test]
    async fn ctf_refuses_an_unvalidated_map_or_rotation_before_binding() {
        let rules =
            fragr_server::rules::RuleSet::new(fragr_server::protocol::GameMode::Ctf, &[], false)
                .unwrap();
        let config = match_config(rules, None, false).unwrap();
        for (map, rotate) in [
            (fragr_server::sim::MapKind::ComplianceYard, false),
            (fragr_server::sim::MapKind::ReclamationGulch, false),
            (fragr_server::sim::MapKind::TripointWorks, false),
            (fragr_server::sim::MapKind::Sector9, true),
            (fragr_server::sim::MapKind::ArenaDuel, true),
        ] {
            let error = run_server(
                ServerOptions {
                    map,
                    map_rotate: rotate,
                    match_config: Some(config.clone()),
                    bind: "127.0.0.1:0".to_string(),
                    ..ServerOptions::default()
                },
                std::future::pending::<()>(),
                None,
            )
            .await
            .unwrap_err();
            assert!(
                error.to_string().contains("validated flag stands"),
                "{map:?} rotate={rotate}: {error}"
            );
        }
    }

    #[tokio::test]
    async fn playlist_refuses_a_fixed_rule_set_before_binding() {
        let rules =
            fragr_server::rules::RuleSet::new(fragr_server::protocol::GameMode::Ffa, &[], false)
                .unwrap();
        let error = run_server(
            ServerOptions {
                playlist: true,
                match_config: match_config(rules, None, true),
                bind: "127.0.0.1:0".to_string(),
                status_every_s: 0,
                ..ServerOptions::default()
            },
            std::future::pending::<()>(),
            None,
        )
        .await
        .unwrap_err();
        assert!(error.to_string().contains("night playlist"), "{error}");
    }

    #[tokio::test]
    async fn playlist_speaks_the_current_contract_and_keeps_arena_seats() {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<SocketAddr>();
        let server = tokio::spawn(async move {
            run_server(
                ServerOptions {
                    bind: "127.0.0.1:0".to_string(),
                    bots: 0,
                    playlist: true,
                    status_every_s: 0,
                    ..Default::default()
                },
                async move {
                    let _ = shutdown_rx.await;
                },
                Some(ready_tx),
            )
            .await
            .map_err(|error| error.to_string())
        });
        let addr = tokio::time::timeout(Duration::from_secs(120), ready_rx)
            .await
            .expect("playlist ready timeout")
            .expect("playlist ready addr");
        let current = fragr_server::protocol::GAMEPLAY_VERSION;
        let geometry = fragr_server::protocol::GEOMETRY_VERSION;
        let mut held = Vec::new();
        for (version, geom, admitted) in [
            (current - 1, geometry, false),
            (current + 1, geometry, false),
            (current, 1, false),
            (current, geometry + 1, false),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
        ] {
            let (mut ws, _) = connect_async(format!("ws://{addr}")).await.unwrap();
            ws.send(Message::Text(
                serde_json::json!({
                    "type": "hello", "role": "human", "name": "Night",
                    "gameplay_version": version,
                    "geometry_version": geom,
                })
                .to_string(),
            ))
            .await
            .unwrap();
            let reply = tokio::time::timeout(Duration::from_secs(5), ws.next())
                .await
                .expect("playlist reply timeout");
            let welcomed = matches!(
                reply,
                Some(Ok(Message::Text(ref text))) if text.contains("\"welcome\"")
            );
            assert_eq!(
                welcomed, admitted,
                "capability {version} geometry {geom}: {reply:?}"
            );
            if admitted {
                held.push(ws);
            }
        }
        drop(held);
        let _ = shutdown_tx.send(());
        let _ = tokio::time::timeout(Duration::from_secs(5), server).await;
    }

    /// A shared team room speaks this binary's contract. Six fighters fit
    /// because an arena rule set is not a four-seat mission party.
    #[tokio::test]
    async fn a_shared_rule_set_speaks_the_current_contract() {
        tokio::task::spawn_blocking(fragr_server::session::GameSession::new)
            .await
            .expect("navigation fixture");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<SocketAddr>();
        let rules =
            fragr_server::rules::RuleSet::new(fragr_server::protocol::GameMode::Tdm, &[], false)
                .unwrap();
        let server = tokio::spawn(async move {
            run_server(
                ServerOptions {
                    bind: "127.0.0.1:0".to_string(),
                    bots: 0,
                    match_config: match_config(rules, None, true),
                    status_every_s: 0,
                    ..Default::default()
                },
                async move {
                    let _ = shutdown_rx.await;
                },
                Some(ready_tx),
            )
            .await
            .map_err(|e| e.to_string())
        });
        let addr = tokio::time::timeout(Duration::from_secs(5), ready_rx)
            .await
            .expect("ready timeout")
            .expect("ready addr");
        let current = fragr_server::protocol::GAMEPLAY_VERSION;
        let geometry = fragr_server::protocol::GEOMETRY_VERSION;
        let mut held = Vec::new();
        for (version, geom, admitted) in [
            (current - 1, geometry, false),
            (current + 1, geometry, false),
            (current, 1, false),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
            (current, geometry, true),
        ] {
            let (mut ws, _) = connect_async(format!("ws://{addr}")).await.unwrap();
            let hello = serde_json::json!({
                "type": "hello", "role": "human", "name": "Sided",
                "gameplay_version": version,
                "geometry_version": geom,
            });
            ws.send(Message::Text(hello.to_string())).await.unwrap();
            let reply = tokio::time::timeout(Duration::from_secs(5), ws.next())
                .await
                .expect("reply timeout");
            let welcomed = matches!(
                reply,
                Some(Ok(Message::Text(ref text))) if text.contains("\"welcome\"")
            );
            assert_eq!(
                welcomed, admitted,
                "capability {version} geometry {geom}: {reply:?}"
            );
            if admitted {
                held.push(ws);
            }
        }
        drop(held);
        let _ = shutdown_tx.send(());
        let _ = tokio::time::timeout(Duration::from_secs(5), server).await;
    }

    #[tokio::test]
    async fn ctf_speaks_the_current_contract_for_spectators_and_fighters() {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<SocketAddr>();
        let rules =
            fragr_server::rules::RuleSet::new(fragr_server::protocol::GameMode::Ctf, &[], false)
                .unwrap();
        let mut config = match_config(rules, None, true).unwrap();
        config.capture_limit = Some(3);
        let server = tokio::spawn(async move {
            run_server(
                ServerOptions {
                    bind: "127.0.0.1:0".to_string(),
                    bots: 0,
                    map: fragr_server::sim::MapKind::Sector9,
                    match_config: Some(config),
                    status_every_s: 0,
                    ..Default::default()
                },
                async move {
                    let _ = shutdown_rx.await;
                },
                Some(ready_tx),
            )
            .await
        });
        let addr = tokio::time::timeout(Duration::from_secs(20), ready_rx)
            .await
            .expect("ctf ready timeout")
            .expect("ctf ready addr");
        let current = fragr_server::protocol::GAMEPLAY_VERSION;
        let geometry = fragr_server::protocol::GEOMETRY_VERSION;
        for (version, geom, role, admitted) in [
            (current - 1, geometry, "spectator", false),
            (current - 1, geometry, "human", false),
            (current + 1, geometry, "human", false),
            (current, 1, "spectator", false),
            (current, geometry, "spectator", true),
            (current, geometry, "human", true),
        ] {
            let (mut ws, _) = connect_async(format!("ws://{addr}")).await.unwrap();
            ws.send(Message::Text(
                serde_json::json!({
                    "type": "hello", "role": role, "name": "FlagCheck",
                    "gameplay_version": version,
                    "geometry_version": geom,
                })
                .to_string(),
            ))
            .await
            .unwrap();
            let reply = tokio::time::timeout(Duration::from_secs(5), ws.next())
                .await
                .expect("ctf reply timeout");
            let welcomed = matches!(
                reply,
                Some(Ok(Message::Text(ref text))) if text.contains("\"welcome\"")
            );
            assert_eq!(
                welcomed, admitted,
                "{role} capability {version} geometry {geom}: {reply:?}"
            );
        }
        let _ = shutdown_tx.send(());
        let _ = tokio::time::timeout(Duration::from_secs(5), server).await;
    }

    #[test]
    fn sabotage_takes_a_format_and_no_frag_or_capture_limit() {
        use fragr_server::protocol::GameMode;
        let args = Args::try_parse_from([
            "fragr-server",
            "--mode",
            "sabotage",
            "--map",
            "4",
            "--sabotage-format",
            "match",
        ])
        .unwrap();
        assert_eq!(args.mode, GameMode::Sabotage);
        assert_eq!(
            args.sabotage_format,
            Some(fragr_server::protocol::SabotageFormat::Match)
        );
        let rules = fragr_server::rules::RuleSet::new(GameMode::Sabotage, &[], false).unwrap();
        let config = match_config(rules, None, false).unwrap();
        assert_eq!(config.frag_limit, None, "rounds decide sabotage");
        assert_eq!(
            config.time_limit_ticks, None,
            "sabotage keeps its own clocks"
        );
        assert_eq!(config.boss_spawn_ticks, None);
        assert_eq!(config.compliance_ping_ticks, None);
        assert!(Args::try_parse_from(["fragr-server", "--sabotage-format", "pairs"]).is_err());
    }

    #[tokio::test]
    async fn sabotage_refuses_a_map_without_sites_or_rotation_before_binding() {
        let rules = fragr_server::rules::RuleSet::new(
            fragr_server::protocol::GameMode::Sabotage,
            &[],
            false,
        )
        .unwrap();
        let config = match_config(rules, None, false).unwrap();
        for (map, rotate) in [
            (fragr_server::sim::MapKind::ArenaDuel, false),
            (fragr_server::sim::MapKind::Directive17, false),
            (fragr_server::sim::MapKind::Sector9, true),
        ] {
            let error = run_server(
                ServerOptions {
                    map,
                    map_rotate: rotate,
                    match_config: Some(config.clone()),
                    bind: "127.0.0.1:0".to_string(),
                    ..ServerOptions::default()
                },
                std::future::pending::<()>(),
                None,
            )
            .await
            .unwrap_err();
            assert!(
                error.to_string().contains("validated sites"),
                "{map:?} rotate={rotate}: {error}"
            );
        }
    }

    #[tokio::test]
    async fn sabotage_speaks_the_current_contract_for_spectators_and_fighters() {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<SocketAddr>();
        let rules = fragr_server::rules::RuleSet::new(
            fragr_server::protocol::GameMode::Sabotage,
            &[],
            false,
        )
        .unwrap();
        let config = match_config(rules, None, true).unwrap();
        let server = tokio::spawn(async move {
            run_server(
                ServerOptions {
                    bind: "127.0.0.1:0".to_string(),
                    bots: 0,
                    map: fragr_server::sim::MapKind::Sector9,
                    match_config: Some(config),
                    status_every_s: 0,
                    ..Default::default()
                },
                async move {
                    let _ = shutdown_rx.await;
                },
                Some(ready_tx),
            )
            .await
        });
        let addr = tokio::time::timeout(Duration::from_secs(20), ready_rx)
            .await
            .expect("sabotage ready timeout")
            .expect("sabotage ready addr");
        let current = fragr_server::protocol::GAMEPLAY_VERSION;
        let geometry = fragr_server::protocol::GEOMETRY_VERSION;
        for (version, geom, role, admitted) in [
            (current - 1, geometry, "spectator", false),
            (current - 1, geometry, "agent", false),
            (current + 1, geometry, "agent", false),
            (current, 1, "spectator", false),
            (current, geometry, "spectator", true),
            (current, geometry, "agent", true),
        ] {
            let (mut ws, _) = connect_async(format!("ws://{addr}")).await.unwrap();
            ws.send(Message::Text(
                serde_json::json!({
                    "type": "hello", "role": role, "name": "SiteCheck",
                    "gameplay_version": version,
                    "geometry_version": geom,
                })
                .to_string(),
            ))
            .await
            .unwrap();
            let reply = tokio::time::timeout(Duration::from_secs(5), ws.next())
                .await
                .expect("sabotage reply timeout");
            let welcomed = matches!(
                reply,
                Some(Ok(Message::Text(ref text))) if text.contains("\"welcome\"")
            );
            assert_eq!(
                welcomed, admitted,
                "{role} capability {version} geometry {geom}: {reply:?}"
            );
        }
        let _ = shutdown_tx.send(());
        let _ = tokio::time::timeout(Duration::from_secs(5), server).await;
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
                    campaign_run: false,
                    authored: None,
                    difficulty: None,
                    bind: "127.0.0.1:0".to_string(),
                    bots: 1,
                    bot_policy: fragr_server::bot_fill::BotPolicy::Fixed,
                    fill_target: 0,
                    map: fragr_server::sim::MapKind::ArenaDuel,
                    map_rotate: false,
                    playlist: false,
                    match_config: None,
                    solo_broadcast: false,
                    seed: 1,
                    status_every_s: 0,
                    join_secret: None,
                    access: Default::default(),
                    console: false,
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
            "name": "CovClimb",
            "gameplay_version": fragr_server::protocol::GAMEPLAY_VERSION,
            "geometry_version": fragr_server::protocol::GEOMETRY_VERSION,
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
    fn access_lists_are_dedicated_server_flags() {
        let args = Args::try_parse_from([
            "fragr-server",
            "--ban-list",
            "bans.txt",
            "--allow-list",
            "allow.txt",
        ])
        .unwrap();
        assert_eq!(args.ban_list, Some(PathBuf::from("bans.txt")));
        assert_eq!(args.allow_list, Some(PathBuf::from("allow.txt")));
        let defaults = Args::try_parse_from(["fragr-server"]).unwrap();
        assert!(defaults.ban_list.is_none() && defaults.allow_list.is_none());
        for flag in ["--ban-list", "--allow-list"] {
            assert!(Args::try_parse_from([
                "fragr-server",
                "--local-mission",
                "recall_notice",
                flag,
                "list.txt"
            ])
            .is_err());
            assert!(
                Args::try_parse_from(["fragr-server", "--bench", "4", flag, "list.txt"]).is_err()
            );
        }
    }

    #[tokio::test]
    async fn run_server_refuses_a_malformed_list_before_binding() {
        let path = std::env::temp_dir().join(format!(
            "fragr-main-ban-{}-{}.txt",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        std::fs::write(&path, "203.0.113.0/33\n").unwrap();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<SocketAddr>();
        let result = run_server(
            ServerOptions {
                bind: "127.0.0.1:0".to_string(),
                bots: 0,
                status_every_s: 0,
                access: fragr_server::access::AccessConfig {
                    ban_list: Some(path.clone()),
                    allow_list: None,
                },
                ..ServerOptions::default()
            },
            std::future::pending::<()>(),
            Some(ready_tx),
        )
        .await;
        let error = result
            .expect_err("a malformed list must not start")
            .to_string();
        assert!(error.contains("line 1"), "{error}");
        assert!(ready_rx.await.is_err(), "nothing was bound");
        let _ = std::fs::remove_file(path);
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
