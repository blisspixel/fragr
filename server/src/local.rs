//! Desktop child readiness and ownership. Gameplay still uses the normal wire.
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::mission::run_file::store::{RunProbe, RunStore};
use crate::mission::run_file::SavedStep;
use crate::protocol::{
    CampaignDifficulty, MissionId, M02_GAMEPLAY_VERSION, RECORD_GAMEPLAY_VERSION,
};
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
        difficulty: CampaignDifficulty,
        attempt: u32,
        continues: u8,
        pending_continue: bool,
    },
    Failed,
    Abandoned,
    AwaitingMission,
    Incompatible,
    Corrupt,
}

pub fn preview_run(mission: MissionId) -> io::Result<RunPreview> {
    let map = RuntimeMap::Authored(AuthoredSource::Mission(mission).load()?);
    let hash = map
        .content_sha256()
        .ok_or_else(|| io::Error::other("campaign content identity is unavailable"))?;
    match RunStore::inspect(&run_directory()?, hash)? {
        RunProbe::Missing => Ok(RunPreview::Missing),
        RunProbe::Incompatible => Ok(RunPreview::Incompatible),
        RunProbe::Corrupt => Ok(RunPreview::Corrupt),
        RunProbe::Compatible(document) => match &document.step {
            SavedStep::MissionEntry { .. } | SavedStep::PendingContinue { .. } => {
                Ok(RunPreview::Ready {
                    difficulty: document.rules.difficulty,
                    attempt: document.attempt(),
                    continues: document.remaining_continues,
                    pending_continue: matches!(&document.step, SavedStep::PendingContinue { .. }),
                })
            }
            SavedStep::Failed { .. } => Ok(RunPreview::Failed),
            SavedStep::Abandoned { .. } => Ok(RunPreview::Abandoned),
            SavedStep::AwaitingMission { .. } => Ok(RunPreview::AwaitingMission),
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
            gameplay_version: match mission {
                MissionId::RecallNotice => RECORD_GAMEPLAY_VERSION,
                MissionId::PersonsUnknown => M02_GAMEPLAY_VERSION,
            },
        })
    }

    fn write(&self, mut output: impl Write) -> io::Result<()> {
        serde_json::to_writer(&mut output, self)?;
        output.write_all(b"\n")?;
        output.flush()
    }
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

/// Only this explicit mode gives stdin process-lifetime meaning. A dedicated
/// host must remain independent of terminal input. The reader is a standard
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
    // M02 is a development entry: no durable run, continues or save carry yet.
    // Its party rules keep entry respawn and the shared wipe reset.
    let campaign_run = mission == MissionId::RecallNotice;
    if run_mode.is_some() && !campaign_run {
        return Err(io::Error::other("this mission has no durable local run yet").into());
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
    Ready::new(mission, selected_difficulty, address)?.write(output)?;
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
                address.parse().unwrap()
            )
            .is_err());
        }
        let ready = Ready::new(
            MissionId::RecallNotice,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
        )
        .unwrap();
        let mut bytes = Vec::new();
        ready.write(&mut bytes).unwrap();
        assert_eq!(bytes.iter().filter(|c| **c == b'\n').count(), 1);
        assert_eq!(serde_json::from_slice::<Ready>(&bytes).unwrap(), ready);
        assert_eq!(ready.url, "ws://127.0.0.1:6767");
        assert_eq!(ready.gameplay_version, RECORD_GAMEPLAY_VERSION);
        let m02 = Ready::new(
            MissionId::PersonsUnknown,
            CampaignDifficulty::Standard,
            "127.0.0.1:6767".parse().unwrap(),
        )
        .unwrap();
        assert_eq!(m02.gameplay_version, M02_GAMEPLAY_VERSION);
    }
}
