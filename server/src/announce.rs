//! LAN presence. One UDP broadcast names the game port. It is not a join,
//! not a status line, and not the planned game transport.

use std::net::{Ipv4Addr, SocketAddr};

/// Where a client listens for presence. Game traffic stays on the TCP port.
pub const BEACON_PORT: u16 = 6768;

const PREFIX: &str = "FRAGR/1 ";

/// A loopback listener is this computer only. Anything else can be seen on
/// the LAN, including a wildcard bind.
pub fn should_announce(bound: SocketAddr) -> bool {
    !bound.ip().is_loopback()
}

pub fn beacon_packet(game_port: u16) -> Vec<u8> {
    format!("{PREFIX}{game_port}\n").into_bytes()
}

/// The game port, or nothing. Extra bytes, a leading zero, and port 0 fail.
pub fn parse_beacon(buf: &[u8]) -> Option<u16> {
    let text = std::str::from_utf8(buf).ok()?;
    let rest = text.strip_prefix(PREFIX)?.strip_suffix('\n')?;
    if rest.is_empty() || rest.len() > 5 || rest.contains('\n') {
        return None;
    }
    if rest.len() > 1 && rest.as_bytes()[0] == b'0' {
        return None;
    }
    if !rest.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let port: u16 = rest.parse().ok()?;
    (port > 0).then_some(port)
}

/// Send one presence packet. The dedicated loop broadcasts it.
pub async fn send_beacon(
    socket: &tokio::net::UdpSocket,
    dest: SocketAddr,
    game_port: u16,
) -> std::io::Result<()> {
    let packet = beacon_packet(game_port);
    // A packet this process would ignore is not presence.
    if parse_beacon(&packet).is_none() {
        return Ok(());
    }
    socket.send_to(&packet, dest).await.map(|_| ())
}

/// Broadcast the game port until the task is aborted with the match.
pub async fn broadcast_loop(game_port: u16) {
    let socket = match tokio::net::UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).await {
        Ok(socket) => socket,
        Err(error) => {
            tracing::warn!("LAN beacon did not open: {error}");
            return;
        }
    };
    if let Err(error) = socket.set_broadcast(true) {
        tracing::warn!("LAN beacon could not broadcast: {error}");
        return;
    }
    let dest = SocketAddr::from((Ipv4Addr::BROADCAST, BEACON_PORT));
    tracing::info!(
        "LAN beacon: UDP {BEACON_PORT} every 2s for game port {game_port}. A beacon is not a join."
    );
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(2));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut warned = false;
    loop {
        interval.tick().await;
        if let Err(error) = send_beacon(&socket, dest, game_port).await {
            if !warned {
                tracing::warn!("LAN beacon send failed: {error}");
                warned = true;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_beacon_is_only_the_game_port() {
        assert_eq!(parse_beacon(b"FRAGR/1 6767\n"), Some(6767));
        assert_eq!(parse_beacon(b"FRAGR/1 1\n"), Some(1));
        assert_eq!(parse_beacon(b"FRAGR/1 65535\n"), Some(65535));
        assert_eq!(parse_beacon(&beacon_packet(6767)), Some(6767));
        for bad in [
            b"FRAGR/1 6767".as_slice(),
            b"FRAGR/1 6767\nextra",
            b"FRAGR/1 0\n",
            b"FRAGR/1 06767\n",
            b"fragr/1 6767\n",
            b"GET /status\n",
            b"FRAGR/1 65536\n",
            b"FRAGR/1\n",
        ] {
            assert_eq!(parse_beacon(bad), None, "{bad:?}");
        }
        assert!(!should_announce("127.0.0.1:6767".parse().unwrap()));
        assert!(!should_announce("[::1]:6767".parse().unwrap()));
        assert!(should_announce("0.0.0.0:6767".parse().unwrap()));
        assert!(should_announce("192.0.2.10:6767".parse().unwrap()));
    }

    #[tokio::test]
    async fn one_packet_names_the_game_port() {
        let recv = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let dest = recv.local_addr().unwrap();
        let send = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        send_beacon(&send, dest, 6767).await.unwrap();
        let mut buf = [0u8; 64];
        let (n, from) =
            tokio::time::timeout(std::time::Duration::from_secs(2), recv.recv_from(&mut buf))
                .await
                .expect("beacon")
                .unwrap();
        assert_eq!(parse_beacon(&buf[..n]), Some(6767));
        assert_eq!(from, send.local_addr().unwrap());
    }
}
