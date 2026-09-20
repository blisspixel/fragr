//! Desktop child readiness and ownership. Gameplay still uses the normal wire.
use crate::maps::AuthoredSource;
use crate::protocol::{MissionId, GAMEPLAY_VERSION};
use crate::run::{run_server, ServerOptions};
use serde::{Deserialize, Serialize};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, SocketAddr};
use tokio::sync::oneshot;

const MAX_CONTROL_BYTES: u64 = 256;

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Ready {
    pub version: u32,
    pub mission: MissionId,
    pub url: String,
    pub gameplay_version: u32,
}

impl Ready {
    fn new(mission: MissionId, address: SocketAddr) -> io::Result<Self> {
        if address.ip() != Ipv4Addr::LOCALHOST || address.port() == 0 {
            return Err(io::Error::other(
                "local child readiness requires IPv4 loopback",
            ));
        }
        Ok(Self {
            version: 1,
            mission,
            url: format!("ws://{address}"),
            gameplay_version: GAMEPLAY_VERSION,
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
    input: impl Read + Send + 'static,
    output: impl Write,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
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
        seed,
        status_every_s: 0,
        ..Default::default()
    };
    let server = run_server(
        options,
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    );
    tokio::pin!(server);
    let address = tokio::select! {
        result = &mut server => return result,
        owner = &mut owner_rx => { owner??; return Ok(()); },
        ready = &mut ready_rx => ready?,
    };
    Ready::new(mission, address)?.write(output)?;
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
            assert!(Ready::new(MissionId::RecallNotice, address.parse().unwrap()).is_err());
        }
        let ready = Ready::new(MissionId::RecallNotice, "127.0.0.1:6767".parse().unwrap()).unwrap();
        let mut bytes = Vec::new();
        ready.write(&mut bytes).unwrap();
        assert_eq!(bytes.iter().filter(|c| **c == b'\n').count(), 1);
        assert_eq!(serde_json::from_slice::<Ready>(&bytes).unwrap(), ready);
        assert_eq!(ready.url, "ws://127.0.0.1:6767");
    }
}
