//! Desktop child readiness and ownership. Gameplay still uses the normal wire.
use crate::maps::AuthoredSource;
use crate::mission::run_file::store::{RunProbe, RunStore};
use crate::mission::run_file::SavedStep;
use crate::protocol::{BodyKind, CampaignDifficulty, GameMode, MissionId};
use crate::run::{run_local_server, run_server, LocalRunConfig, ServerOptions};
use serde::{Deserialize, Serialize};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use tokio::sync::oneshot;

const MAX_CONTROL_BYTES: u64 = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum LocalRunMode {
    New,
    Resume,
}

#[derive(Debug, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum RunPreview {
    Missing,
    Ready {
        mission: String,
        difficulty: CampaignDifficulty,
        attempt: u32,
        continues: u8,
        pending_continue: bool,
        body: Option<BodyKind>,
    },
    Failed,
    Abandoned,
    AwaitingMission {
        mission: String,
        difficulty: CampaignDifficulty,
        continues: u8,
        body: Option<BodyKind>,
    },
    Incompatible,
    Corrupt,
}

pub fn preview_run(_mission: MissionId) -> io::Result<RunPreview> {
    let hashes = crate::mission::run_file::store::CAMPAIGN_MISSIONS
        .map(AuthoredSource::bundled_content_sha256);
    match RunStore::inspect_with_hashes(&run_directory()?, hashes)? {
        RunProbe::Missing => Ok(RunPreview::Missing),
        RunProbe::Incompatible => Ok(RunPreview::Incompatible),
        RunProbe::Corrupt => Ok(RunPreview::Corrupt),
        RunProbe::Compatible(document) => match &document.step {
            SavedStep::MissionEntry { .. } | SavedStep::PendingContinue { .. } => {
                Ok(RunPreview::Ready {
                    mission: match document.stage_mission() {
                        MissionId::RecallNotice => "recall_notice",
                        MissionId::PersonsUnknown => "persons_unknown",
                        MissionId::ScheduledService => "scheduled_service",
                        MissionId::NoticeToVacate => "notice_to_vacate",
                        MissionId::NoForwardingAddress => "no_forwarding_address",
                        MissionId::PortOfEntry => "port_of_entry",
                        MissionId::CustodianOfRecord => "custodian_of_record",
                        MissionId::DeclaredGoods => "declared_goods",
                        MissionId::PassengerManifest => "passenger_manifest",
                        MissionId::CommonCarrier => "common_carrier",
                        MissionId::RightOfSearch => "right_of_search",
                    }
                    .into(),
                    difficulty: document.rules.difficulty,
                    attempt: document.attempt(),
                    continues: document.remaining_continues,
                    pending_continue: matches!(&document.step, SavedStep::PendingContinue { .. }),
                    body: document.body,
                })
            }
            SavedStep::Failed { .. } => Ok(RunPreview::Failed),
            SavedStep::Abandoned { .. } => Ok(RunPreview::Abandoned),
            SavedStep::AwaitingMission { next_mission, .. } => Ok(RunPreview::AwaitingMission {
                mission: next_mission.clone(),
                difficulty: document.rules.difficulty,
                continues: document.remaining_continues,
                body: document.body,
            }),
        },
    }
}

fn run_directory() -> io::Result<PathBuf> {
    if let Some(override_path) = std::env::var_os("FRAGR_RUN_DIR") {
        let path = PathBuf::from(override_path);
        if path.is_absolute() {
            return Ok(path);
        }
        return Err(io::Error::other("FRAGR_RUN_DIR must be absolute"));
    }
    #[cfg(target_os = "windows")]
    let base = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
    #[cfg(target_os = "macos")]
    let base = std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join("Library").join("Application Support"));
    #[cfg(all(unix, not(target_os = "macos")))]
    let base = std::env::var_os("XDG_DATA_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .map(|home| home.join(".local/share"))
        });
    let base = base.ok_or_else(|| io::Error::other("user data directory is unavailable"))?;
    if !base.is_absolute() {
        return Err(io::Error::other("user data directory must be absolute"));
    }
    Ok(base.join("fragr").join("runs"))
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Ready {
    pub version: u32,
    pub mission: MissionId,
    pub difficulty: CampaignDifficulty,
    pub url: String,
    pub gameplay_version: u32,
}

impl Ready {
    fn new(
        mission: MissionId,
        difficulty: CampaignDifficulty,
        address: SocketAddr,
        _durable: bool,
    ) -> io::Result<Self> {
        if address.ip() != Ipv4Addr::LOCALHOST || address.port() == 0 {
            return Err(io::Error::other(
                "local child readiness requires IPv4 loopback",
            ));
        }
        Ok(Self {
            version: 2,
            mission,
            difficulty,
            url: format!("ws://{address}"),
            // M06 adds a distinct envelope; earlier mission readers retain
            // their existing capability boundary and unchanged rules.
            gameplay_version: if mission == MissionId::RightOfSearch {
                crate::protocol::M11_GAMEPLAY_VERSION
            } else if mission == MissionId::CommonCarrier {
                crate::protocol::M10_GAMEPLAY_VERSION
            } else if mission == MissionId::PassengerManifest {
                crate::protocol::M09_GAMEPLAY_VERSION
            } else if mission == MissionId::DeclaredGoods {
                crate::protocol::M07_GAMEPLAY_VERSION
            } else if mission == MissionId::CustodianOfRecord {
                crate::protocol::M08_GAMEPLAY_VERSION
            } else if mission == MissionId::PortOfEntry {
                crate::protocol::M06_GAMEPLAY_VERSION
            } else {
                crate::protocol::M05_GAMEPLAY_VERSION
            },
        })
    }

    fn write(&self, mut output: impl Write) -> io::Result<()> {
        serde_json::to_writer(&mut output, self)?;
        output.write_all(b"\n")?;
        output.flush()
    }
}

/// Separate from campaign readiness: no mission identity or durable run is
/// implied by hosting an arena. The normal wire still owns every match fact.
#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ArenaReady {
    pub version: u32,
    pub kind: String,
    pub url: String,
    pub listen: String,
    pub map_id: u32,
    pub mode: GameMode,
    pub five_vs_five: bool,
    pub bots: usize,
    pub bot_policy: crate::bot_fill::BotPolicy,
    pub fill_target: usize,
    pub gameplay_version: u32,
}

impl ArenaReady {
    fn new(options: &ServerOptions, address: SocketAddr) -> io::Result<Self> {
        let expected = validate_arena_options(options)?;
        if address.ip() != expected.ip()
            || address.port() == 0
            || (expected.port() != 0 && address.port() != expected.port())
        {
            return Err(io::Error::other(
                "arena child readiness does not match its listener",
            ));
        }
        let config = options
            .match_config
            .as_ref()
            .expect("validated arena rules");
        Ok(Self {
            version: 1,
            kind: "arena".into(),
            url: format!("ws://127.0.0.1:{}", address.port()),
            listen: address.to_string(),
            map_id: options.map.id(),
            mode: config.rules.mode(),
            five_vs_five: config.sabotage.five_vs_five,
            bots: options.bots,
            bot_policy: options.bot_policy,
            fill_target: options.fill_target,
            gameplay_version: crate::protocol::GAMEPLAY_VERSION,
        })
    }

    fn write(&self, mut output: impl Write) -> io::Result<()> {
        serde_json::to_writer(&mut output, self)?;
        output.write_all(b"\n")?;
        output.flush()
    }
}

fn validate_arena_options(options: &ServerOptions) -> io::Result<SocketAddr> {
    options.validate_bot_policy().map_err(io::Error::other)?;
    let address: SocketAddr = options.bind.parse().map_err(|_| {
        io::Error::other("desktop host requires an IPv4 loopback or wildcard address")
    })?;
    if address.ip() != Ipv4Addr::LOCALHOST
        && (address.ip() != Ipv4Addr::UNSPECIFIED || address.port() == 0)
    {
        return Err(io::Error::other(
            "desktop host requires IPv4 loopback or a wildcard with a chosen nonzero port",
        ));
    }
    if options.bots > 10
        || options.authored.is_some()
        || options.difficulty.is_some()
        || options.campaign_run
        || options.map_rotate
        || options.playlist
        || options.solo_broadcast
    {
        return Err(io::Error::other("invalid desktop arena profile"));
    }
    let config = options
        .match_config
        .as_ref()
        .ok_or_else(|| io::Error::other("desktop host requires TDM or five-per-side Sabotage"))?;
    let valid_mode = match config.rules.mode() {
        GameMode::Tdm => !config.sabotage.five_vs_five,
        GameMode::Sabotage => {
            config.sabotage.five_vs_five && options.map == crate::sim::MapKind::Sector9
        }
        _ => false,
    };
    if !valid_mode || !config.rules.mutators().is_empty() || config.rules.friendly_fire() {
        return Err(io::Error::other(
            "desktop host requires an unmodified TDM or five-per-side Sabotage profile",
        ));
    }
    Ok(address)
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
enum Control {
    Shutdown {},
}

fn read_lease(input: impl Read) -> io::Result<()> {
    let mut frame = Vec::new();
    BufReader::new(input)
        .take(MAX_CONTROL_BYTES + 1)
        .read_until(b'\n', &mut frame)?;
    if frame.is_empty() {
        return Ok(());
    }
    if frame.len() as u64 > MAX_CONTROL_BYTES || frame.last() != Some(&b'\n') {
        return Err(io::Error::other(
            "invalid local parent control length or framing",
        ));
    }
    serde_json::from_slice::<Control>(&frame)
        .map(|Control::Shutdown {}| ())
        .map_err(|_| io::Error::other("invalid local parent control"))
}

/// The desktop parent owns this arena process, including an explicit LAN
/// listener. It uses the same bounded lease as campaign children, but never
/// opens campaign storage or modifies ordinary dedicated-server stdin policy.
pub async fn serve_arena(
    options: ServerOptions,
    input: impl Read + Send + 'static,
    output: impl Write,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    validate_arena_options(&options)?;
    let ready_options = options.clone();
    let (owner_tx, mut owner_rx) = oneshot::channel();
    std::thread::Builder::new()
        .name("arena-parent".into())
        .spawn(move || {
            let _ = owner_tx.send(read_lease(input));
        })?;
    let (ready_tx, mut ready_rx) = oneshot::channel();
    let (stop_tx, stop_rx) = oneshot::channel();
    let server = run_server(
        options,
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    );
    tokio::pin!(server);
    let address = tokio::select! {
        biased;
        owner = &mut owner_rx => { owner??; return Ok(()); },
        result = &mut server => return result,
        ready = &mut ready_rx => ready?,
    };
    // A parent that closed its lease while the map was preparing must not
    // receive a stale readiness record.
    match owner_rx.try_recv() {
        Ok(owner) => {
            let _ = stop_tx.send(());
            server.await?;
            owner?;
            return Ok(());
        }
        Err(oneshot::error::TryRecvError::Closed) => {
            let _ = stop_tx.send(());
            server.await?;
            return Err(io::Error::other("arena parent lease reader closed").into());
        }
        Err(oneshot::error::TryRecvError::Empty) => {}
    }
    if let Err(error) = ArenaReady::new(&ready_options, address).and_then(|r| r.write(output)) {
        let _ = stop_tx.send(());
        server.await?;
        return Err(error.into());
    }
    tokio::select! {
        result = &mut server => result,
        owner = &mut owner_rx => {
            let _ = stop_tx.send(());
            server.await?;
            owner??;
            Ok(())
        }
    }
}

/// Only this explicit mode gives stdin process-lifetime meaning. A dedicated
/// host must remain independent of terminal input. The venue desk is a separate
/// opt-in reader whose end does not shut the process down. This campaign lease
/// still does. The reader is a standard
/// thread so cancelling startup never strands a blocking task in Tokio shutdown.
pub async fn serve(
    mission: MissionId,
    seed: u64,
    difficulty: CampaignDifficulty,
    input: impl Read + Send + 'static,
    output: impl Write,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    serve_with_mode(mission, seed, difficulty, None, input, output).await
}

pub async fn serve_with_mode(
    mission: MissionId,
    seed: u64,
    difficulty: CampaignDifficulty,
    run_mode: Option<LocalRunMode>,
    input: impl Read + Send + 'static,
    output: impl Write,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Later missions without a run mode remain independent development parties.
    let campaign_run = mission == MissionId::RecallNotice || run_mode.is_some();
    if mission != MissionId::RecallNotice && run_mode == Some(LocalRunMode::New) {
        return Err(io::Error::other("a new durable run must start at M01").into());
    }
    let (owner_tx, mut owner_rx) = oneshot::channel();
    std::thread::Builder::new()
        .name("local-parent".into())
        .spawn(move || {
            let _ = owner_tx.send(read_lease(input));
        })?;
    let (ready_tx, mut ready_rx) = oneshot::channel();
    let (stop_tx, stop_rx) = oneshot::channel();
    let options = ServerOptions {
        bind: "127.0.0.1:0".into(),
        bots: 0,
        authored: Some(AuthoredSource::Mission(mission)),
        difficulty: Some(difficulty),
        campaign_run,
        seed,
        status_every_s: 0,
        join_secret: crate::join_ticket::JoinSecret::from_process_env()
            .map_err(std::io::Error::other)?
            .map(std::sync::Arc::new),
        ..Default::default()
    };
    let (difficulty_tx, difficulty_rx) = oneshot::channel();
    let server = async {
        if let Some(mode) = run_mode {
            run_local_server(
                options,
                async {
                    let _ = stop_rx.await;
                },
                ready_tx,
                LocalRunConfig {
                    directory: run_directory()?,
                    resume: matches!(mode, LocalRunMode::Resume),
                    difficulty_ready: difficulty_tx,
                },
            )
            .await
        } else {
            run_server(
                options,
                async {
                    let _ = stop_rx.await;
                },
                Some(ready_tx),
            )
            .await
        }
    };
    tokio::pin!(server);
    let address = tokio::select! {
        result = &mut server => return result,
        owner = &mut owner_rx => { owner??; return Ok(()); },
        ready = &mut ready_rx => ready?,
    };
    let selected_difficulty = if run_mode.is_some() {
        difficulty_rx.await?
    } else {
        difficulty
    };
    Ready::new(mission, selected_difficulty, address, run_mode.is_some())?.write(output)?;
    tokio::select! {
        result = &mut server => result,
        owner = &mut owner_rx => {
            let _ = stop_tx.send(());
            server.await?;
            owner??;
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arena_options() -> ServerOptions {
        ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            match_config: Some(crate::sim::MatchConfig {
                rules: crate::rules::RuleSet::new(GameMode::Tdm, &[], false).unwrap(),
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn arena_ready_matches_the_actual_listener_and_strict_schema() {
        let options = arena_options();
        let ready = ArenaReady::new(&options, "127.0.0.1:43210".parse().unwrap()).unwrap();
        assert_eq!(ready.map_id, options.map.id());
        assert_eq!(ready.mode, GameMode::Tdm);
        assert!(!ready.five_vs_five);
        assert_eq!(ready.gameplay_version, crate::protocol::GAMEPLAY_VERSION);
        let mut bytes = Vec::new();
        ready.write(&mut bytes).unwrap();
        assert_eq!(bytes.iter().filter(|c| **c == b'\n').count(), 1);
        assert_eq!(serde_json::from_slice::<ArenaReady>(&bytes).unwrap(), ready);
        let mut value = serde_json::to_value(&ready).unwrap();
        assert_eq!(value.as_object().unwrap().len(), 11);
        assert_eq!(value["bot_policy"], "fixed");
        assert_eq!(value["fill_target"], 0);
        value["extra"] = true.into();
        assert!(serde_json::from_value::<ArenaReady>(value).is_err());
        for actual in ["0.0.0.0:43210", "127.0.0.1:0"] {
            assert!(ArenaReady::new(&options, actual.parse().unwrap()).is_err());
        }
        let chosen = ServerOptions {
            bind: "0.0.0.0:43210".into(),
            ..options
        };
        let lan = ArenaReady::new(&chosen, "0.0.0.0:43210".parse().unwrap()).unwrap();
        assert_eq!(lan.url, "ws://127.0.0.1:43210");
        assert_eq!(lan.listen, "0.0.0.0:43210");
        assert!(ArenaReady::new(&chosen, "0.0.0.0:43211".parse().unwrap()).is_err());
    }

    #[test]
    fn desktop_profile_rejects_non_arena_sources_and_invisible_rule_changes() {
        let base = arena_options();
        for address in [
            "0.0.0.0:0",
            "[::1]:6767",
            "192.0.2.1:6767",
            "localhost:6767",
        ] {
            let options = ServerOptions {
                bind: address.into(),
                ..base.clone()
            };
            assert!(validate_arena_options(&options).is_err());
        }
        for changed in [
            ServerOptions {
                bots: 11,
                ..base.clone()
            },
            ServerOptions {
                authored: Some(AuthoredSource::Mission(MissionId::RecallNotice)),
                ..base.clone()
            },
            ServerOptions {
                difficulty: Some(CampaignDifficulty::Standard),
                ..base.clone()
            },
            ServerOptions {
                campaign_run: true,
                ..base.clone()
            },
            ServerOptions {
                map_rotate: true,
                ..base.clone()
            },
            ServerOptions {
                playlist: true,
                ..base.clone()
            },
            ServerOptions {
                solo_broadcast: true,
                ..base.clone()
            },
            ServerOptions {
                match_config: None,
                ..base.clone()
            },
        ] {
            assert!(validate_arena_options(&changed).is_err());
        }
        for (mode, mutators, friendly_fire, five, map, accepted) in [
            (
                GameMode::Tdm,
                vec![],
                false,
                false,
                crate::sim::MapKind::ArenaDuel,
                true,
            ),
            (
                GameMode::Tdm,
                vec![],
                false,
                true,
                crate::sim::MapKind::ArenaDuel,
                false,
            ),
            (
                GameMode::Ffa,
                vec![],
                false,
                false,
                crate::sim::MapKind::ArenaDuel,
                false,
            ),
            (
                GameMode::Ctf,
                vec![],
                false,
                false,
                crate::sim::MapKind::ArenaDuel,
                false,
            ),
            (
                GameMode::Tdm,
                vec![crate::protocol::Mutator::RailOnly],
                false,
                false,
                crate::sim::MapKind::ArenaDuel,
                false,
            ),
            (
                GameMode::Tdm,
                vec![],
                true,
                false,
                crate::sim::MapKind::ArenaDuel,
                false,
            ),
            (
                GameMode::Sabotage,
                vec![],
                false,
                false,
                crate::sim::MapKind::Sector9,
                false,
            ),
            (
                GameMode::Sabotage,
                vec![],
                false,
                true,
                crate::sim::MapKind::ArenaDuel,
                false,
            ),
            (
                GameMode::Sabotage,
                vec![],
                false,
                true,
                crate::sim::MapKind::Sector9,
                true,
            ),
        ] {
            let mut options = base.clone();
            options.map = map;
            let config = options.match_config.as_mut().unwrap();
            config.rules = crate::rules::RuleSet::new(mode, &mutators, friendly_fire).unwrap();
            config.sabotage.five_vs_five = five;
            assert_eq!(validate_arena_options(&options).is_ok(), accepted);
        }
    }

    struct FailedWriter;
    impl Write for FailedWriter {
        fn write(&mut self, _bytes: &[u8]) -> io::Result<usize> {
            Err(io::Error::other("closed readiness pipe"))
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn failed_readiness_output_retires_its_bound_listener() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let options = ServerOptions {
            bind: address.to_string(),
            ..arena_options()
        };
        let (sender, receiver) = std::sync::mpsc::channel();
        struct Lease(std::sync::mpsc::Receiver<()>);
        impl Read for Lease {
            fn read(&mut self, _buffer: &mut [u8]) -> io::Result<usize> {
                let _ = self.0.recv();
                Ok(0)
            }
        }
        let result = serve_arena(options, Lease(receiver), FailedWriter).await;
        drop(sender);
        assert!(result.is_err());
        assert!(
            std::net::TcpListener::bind(address).is_ok(),
            "listener leaked after failed readiness"
        );
    }

    #[test]
    fn bundled_byte_hash_matches_the_strict_runtime_loader() {
        for mission in [
            MissionId::RecallNotice,
            MissionId::PersonsUnknown,
            MissionId::ScheduledService,
        ] {
            let map =
                crate::maps::RuntimeMap::Authored(AuthoredSource::Mission(mission).load().unwrap());
            assert_eq!(
                map.content_sha256(),
                Some(AuthoredSource::bundled_content_sha256(mission))
            );
        }
    }

    #[test]
    fn lease_ends_only_with_eof_or_bounded_shutdown_and_rejects_bad_frames() {
        assert!(read_lease(&b""[..]).is_ok());
        assert!(read_lease(&b"{\"type\":\"shutdown\"}\n"[..]).is_ok());
        for value in [
            b"{\"type\":\"shutdown\"}".as_slice(),
            b"{\"type\":\"start\"}\n",
            b"{\"type\":\"shutdown\",\"extra\":1}\n",
            b"invalid\n",
            &[b' '; 257],
        ] {
            assert!(
                read_lease(value).is_err(),
                "accepted {:?}",
                String::from_utf8_lossy(value)
            );
        }
    }

    #[test]
    fn readiness_is_one_typed_loopback_record() {
        for address in ["0.0.0.0:6767", "[::1]:6767", "127.0.0.1:0"] {
            assert!(Ready::new(
                MissionId::RecallNotice,
                CampaignDifficulty::Standard,
                address.parse().unwrap(),
                true,
            )
            .is_err());
        }
        let ready = Ready::new(
            MissionId::RecallNotice,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
            true,
        )
        .unwrap();
        let mut bytes = Vec::new();
        ready.write(&mut bytes).unwrap();
        assert_eq!(bytes.iter().filter(|c| **c == b'\n').count(), 1);
        assert_eq!(serde_json::from_slice::<Ready>(&bytes).unwrap(), ready);
        assert_eq!(ready.url, "ws://127.0.0.1:6767");
        assert_eq!(
            ready.gameplay_version,
            crate::protocol::M05_GAMEPLAY_VERSION
        );
        let m02 = Ready::new(
            MissionId::PersonsUnknown,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
            false,
        )
        .unwrap();
        assert_eq!(m02.gameplay_version, crate::protocol::M05_GAMEPLAY_VERSION);
        let m03 = Ready::new(
            MissionId::ScheduledService,
            CampaignDifficulty::Severe,
            "127.0.0.1:6767".parse().unwrap(),
            false,
        )
        .unwrap();
        assert_eq!(m03.gameplay_version, crate::protocol::M05_GAMEPLAY_VERSION);
        assert_eq!(m03.mission, MissionId::ScheduledService);
        let m04 = Ready::new(
            MissionId::NoticeToVacate,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
            false,
        )
        .unwrap();
        assert_eq!(m04.gameplay_version, crate::protocol::M05_GAMEPLAY_VERSION);
        assert_eq!(m04.mission, MissionId::NoticeToVacate);
        let m06 = Ready::new(
            MissionId::PortOfEntry,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
            false,
        )
        .unwrap();
        assert_eq!(m06.gameplay_version, crate::protocol::M06_GAMEPLAY_VERSION);
        assert_eq!(m06.mission, MissionId::PortOfEntry);
        let m08 = Ready::new(
            MissionId::CustodianOfRecord,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
            false,
        )
        .unwrap();
        assert_eq!(m08.gameplay_version, crate::protocol::M08_GAMEPLAY_VERSION);
        assert_eq!(m08.mission, MissionId::CustodianOfRecord);
        let m11 = Ready::new(
            MissionId::RightOfSearch,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
            false,
        )
        .unwrap();
        assert_eq!(m11.gameplay_version, crate::protocol::M11_GAMEPLAY_VERSION);
        assert!(
            m11.gameplay_version == crate::protocol::GAMEPLAY_VERSION,
            "tender readiness advertises its playable capability"
        );
    }
}
