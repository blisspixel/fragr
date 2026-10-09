//! Startup checks for the public match line.
//!
//! The process does not report ready until loopback `GET /status` returns a
//! schema 2 arena or mission line small enough for the client. Other
//! addresses on this computer are probed afterwards. A success here does not
//! prove that another computer can connect.

use serde::Deserialize;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

/// Bytes the Godot check reads. A larger plain status is a startup failure.
pub const CLIENT_STATUS_BODY_LIMIT: usize = 4096;

const PROBE_ATTEMPTS: u32 = 20;
const CONNECT_TIMEOUT: Duration = Duration::from_millis(500);
const READ_TIMEOUT: Duration = Duration::from_secs(2);

/// One IPv4 adapter, already reduced to the fields the join filter needs.
#[derive(Debug, Clone, PartialEq, Eq)]
struct JoinAdapter {
    name: String,
    ip: Ipv4Addr,
}

/// Addresses another computer might use, plus adapters that were set aside.
#[derive(Debug, Clone, PartialEq, Eq)]
struct JoinOffer {
    offered: Vec<SocketAddr>,
    skipped: Vec<String>,
}

/// Fields the startup probe requires. Extra status fields are ignored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusFacts {
    pub schema_version: u32,
    pub kind: String,
    pub map: String,
}

#[derive(Debug)]
enum ProbeError {
    /// Connection refused, a timeout, or a busy snapshot. Try again.
    Retry(String),
    /// The host answered something that is not a match line.
    Fatal(String),
}

impl ProbeError {
    fn message(&self) -> &str {
        match self {
            Self::Retry(message) | Self::Fatal(message) => message,
        }
    }
}

#[derive(Debug, Deserialize)]
struct ProbeJson {
    schema_version: u32,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    map: String,
    #[serde(default)]
    busy: bool,
}

/// Where this process should probe itself. A wildcard bind uses loopback.
pub fn loopback_probe_addr(bound: SocketAddr) -> SocketAddr {
    match bound.ip() {
        IpAddr::V4(ip) if !ip.is_unspecified() => bound,
        IpAddr::V4(_) => SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), bound.port()),
        IpAddr::V6(ip) if !ip.is_unspecified() => bound,
        IpAddr::V6(_) => SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), bound.port()),
    }
}

/// Require a schema 2 match line. A bad body fails immediately. A refused or
/// busy probe is retried, then reported as a startup failure.
pub async fn require_status(addr: SocketAddr) -> Result<StatusFacts, String> {
    require_status_attempts(addr, PROBE_ATTEMPTS).await
}

async fn require_status_attempts(addr: SocketAddr, attempts: u32) -> Result<StatusFacts, String> {
    let mut last = String::from("no attempt");
    let attempts = attempts.max(1);
    for attempt in 0..attempts {
        match fetch_status(addr).await {
            Ok(facts) => return Ok(facts),
            Err(ProbeError::Fatal(error)) => return Err(format!("{addr}: {error}")),
            Err(ProbeError::Retry(error)) => last = error,
        }
        if attempt + 1 < attempts {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    }
    Err(format!("{addr} did not answer: {last}"))
}

/// What this process will actually hold. Bots are fighters inside the
/// process. People and watchers use the connection caps. A full house is
/// not a measured 64-fighter match.
pub(crate) fn population_note(bots: usize, connections: usize, per_address: usize) -> String {
    format!(
        "Room: {bots} rule bots stay in the fight and do not use a connection. This process accepts {connections} connections, {per_address} from one address, and spectators count. About 24 people fit, with connections left for watching. A full house uses every connection and has no spare. One address past {per_address} needs another address. Eight to sixteen fighters fill the shorter floors. Sector 9 and the longer floors still have open ground at that count. Stocking one bot per connection is not a measured match."
    )
}

/// List join addresses and probe them. Failures are warnings. This never
/// claims that another computer can connect.
pub async fn log_join_checks(bound: SocketAddr) {
    if bound.ip().is_loopback() {
        tracing::info!(
            "Listening on loopback only ({bound}). Other computers cannot join this process."
        );
        return;
    }
    let adapters = match read_adapters() {
        Ok(adapters) => adapters,
        Err(error) => {
            tracing::warn!(
                "Join addresses could not be listed: {error}. A check from this computer does not prove another computer can connect."
            );
            return;
        }
    };
    let offer = join_candidates(&adapters, bound);
    if !offer.skipped.is_empty() {
        tracing::info!("Not offered for join: {}.", offer.skipped.join(", "));
    }
    if offer.offered.is_empty() {
        tracing::warn!(
            "No join address was found besides loopback. Another computer cannot use this process until a network address is up. A check from this computer does not prove another computer can connect."
        );
        return;
    }
    for addr in offer.offered {
        match fetch_status(addr).await {
            Ok(_) => tracing::info!("{}", join_success_line(addr)),
            Err(error) => tracing::warn!("{}", join_failure_line(addr, error.message())),
        }
    }
}

fn join_success_line(addr: SocketAddr) -> String {
    format!(
        "Join check from this computer: {addr} answered. {} A check from this computer does not prove another computer can connect.",
        join_hint(addr)
    )
}

fn join_failure_line(addr: SocketAddr, error: &str) -> String {
    format!(
        "Join check from this computer: {addr} did not answer ({error}). Another computer using that address will see the same failure. A check from this computer does not prove another computer can connect."
    )
}

fn join_hint(addr: SocketAddr) -> &'static str {
    let IpAddr::V4(ip) = addr.ip() else {
        return "Another computer uses this address only when a path to it is open.";
    };
    if is_lan(ip) {
        "Another computer on the same network uses this address and port."
    } else if is_shared_overlay(ip) {
        "This address is a private overlay. Use it only when the other computer is on that overlay."
    } else {
        "Another computer uses this address only when a path to it is open."
    }
}

fn is_lan(ip: Ipv4Addr) -> bool {
    let [first, second, _, _] = ip.octets();
    first == 10 || (first == 172 && (16..32).contains(&second)) || (first == 192 && second == 168)
}

/// RFC 6598 carrier-grade space, including the Tailscale range.
fn is_shared_overlay(ip: Ipv4Addr) -> bool {
    let [first, second, _, _] = ip.octets();
    first == 100 && (64..128).contains(&second)
}

fn is_virtual_adapter(name: &str) -> bool {
    let name = name.to_ascii_lowercase();
    const MARKERS: &[&str] = &[
        "vmware",
        "vethernet",
        "wsl",
        "hyper-v",
        "hyperv",
        "bluetooth",
        "virtualbox",
        "vbox",
        "docker",
        "loopback",
        "teredo",
        "isatap",
    ];
    MARKERS.iter().any(|marker| name.contains(marker))
}

fn join_candidates(adapters: &[JoinAdapter], bind: SocketAddr) -> JoinOffer {
    let port = bind.port();
    if let IpAddr::V4(ip) = bind.ip() {
        if ip.is_loopback() {
            return JoinOffer {
                offered: Vec::new(),
                skipped: Vec::new(),
            };
        }
        if !ip.is_unspecified() {
            return JoinOffer {
                offered: vec![SocketAddr::from((ip, port))],
                skipped: Vec::new(),
            };
        }
    }
    if bind.ip().is_loopback() {
        return JoinOffer {
            offered: Vec::new(),
            skipped: Vec::new(),
        };
    }
    let mut offered = Vec::new();
    let mut skipped = Vec::new();
    for adapter in adapters {
        if adapter.ip.is_unspecified() || adapter.ip.is_loopback() {
            continue;
        }
        if adapter.ip.is_link_local() {
            skipped.push(format!("{} ({}, link-local)", adapter.name, adapter.ip));
            continue;
        }
        if is_virtual_adapter(&adapter.name) {
            skipped.push(format!("{} ({})", adapter.name, adapter.ip));
            continue;
        }
        let addr = SocketAddr::from((adapter.ip, port));
        if !offered.contains(&addr) {
            offered.push(addr);
        }
    }
    JoinOffer { offered, skipped }
}

fn read_adapters() -> Result<Vec<JoinAdapter>, String> {
    let interfaces = if_addrs::get_if_addrs().map_err(|error| error.to_string())?;
    let mut adapters = Vec::new();
    for iface in interfaces {
        if matches!(
            iface.oper_status,
            if_addrs::IfOperStatus::Down
                | if_addrs::IfOperStatus::NotPresent
                | if_addrs::IfOperStatus::LowerLayerDown
        ) {
            continue;
        }
        let if_addrs::IfAddr::V4(addr) = iface.addr else {
            continue;
        };
        adapters.push(JoinAdapter {
            name: iface.name,
            ip: addr.ip,
        });
    }
    Ok(adapters)
}

async fn fetch_status(addr: SocketAddr) -> Result<StatusFacts, ProbeError> {
    let mut stream = match tokio::time::timeout(CONNECT_TIMEOUT, TcpStream::connect(addr)).await {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => {
            return Err(ProbeError::Retry(format!(
                "{addr} refused the connection: {error}"
            )))
        }
        Err(_) => return Err(ProbeError::Retry(format!("{addr} timed out"))),
    };
    let request = format!(
        "GET /status HTTP/1.0\r\nHost: {}\r\nConnection: close\r\n\r\n",
        host_header(addr)
    );
    if tokio::time::timeout(CONNECT_TIMEOUT, stream.write_all(request.as_bytes()))
        .await
        .map_err(|_| ProbeError::Retry(format!("{addr} timed out")))?
        .is_err()
    {
        return Err(ProbeError::Retry(format!(
            "{addr} did not take the request"
        )));
    }
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    let deadline = tokio::time::Instant::now() + READ_TIMEOUT;
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            return Err(ProbeError::Retry(format!("{addr} timed out")));
        }
        match tokio::time::timeout(remaining, stream.read(&mut tmp)).await {
            Ok(Ok(0)) => break,
            Ok(Ok(n)) => {
                if buf.len().saturating_add(n) > CLIENT_STATUS_BODY_LIMIT.saturating_add(512) {
                    return Err(ProbeError::Fatal(format!(
                        "{addr} answered, but the reply was larger than {CLIENT_STATUS_BODY_LIMIT} bytes"
                    )));
                }
                buf.extend_from_slice(&tmp[..n]);
            }
            Ok(Err(error)) => {
                return Err(ProbeError::Retry(format!(
                    "{addr} dropped the reply: {error}"
                )))
            }
            Err(_) => return Err(ProbeError::Retry(format!("{addr} timed out"))),
        }
    }
    parse_status_reply(&buf)
}

fn host_header(addr: SocketAddr) -> String {
    match addr.ip() {
        IpAddr::V6(ip) => format!("[{ip}]:{}", addr.port()),
        IpAddr::V4(ip) => format!("{ip}:{}", addr.port()),
    }
}

fn parse_status_reply(bytes: &[u8]) -> Result<StatusFacts, ProbeError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| ProbeError::Fatal("the reply was not text".to_string()))?;
    let (head, body) = text
        .split_once("\r\n\r\n")
        .ok_or_else(|| ProbeError::Fatal("the reply had no header".to_string()))?;
    let status_line = head.lines().next().unwrap_or("");
    let mut parts = status_line.split_whitespace();
    let version = parts.next().unwrap_or("");
    let code = parts.next().unwrap_or("");
    if !version.starts_with("HTTP/1.") {
        return Err(ProbeError::Fatal(format!(
            "the reply was not HTTP: {status_line}"
        )));
    }
    if code == "503" {
        return Err(ProbeError::Retry("the host was busy".to_string()));
    }
    if code != "200" {
        return Err(ProbeError::Fatal(format!("the host answered HTTP {code}")));
    }
    if body.len() > CLIENT_STATUS_BODY_LIMIT {
        return Err(ProbeError::Fatal(format!(
            "the reply was {} bytes, and the client reads at most {CLIENT_STATUS_BODY_LIMIT}",
            body.len()
        )));
    }
    let parsed: ProbeJson = serde_json::from_str(body)
        .map_err(|_| ProbeError::Fatal("the reply was not a match line".to_string()))?;
    if parsed.busy {
        return Err(ProbeError::Retry("the host was busy".to_string()));
    }
    let facts = StatusFacts {
        schema_version: parsed.schema_version,
        kind: parsed.kind,
        map: parsed.map,
    };
    facts_are_a_match(&facts)?;
    Ok(facts)
}

fn facts_are_a_match(facts: &StatusFacts) -> Result<(), ProbeError> {
    if facts.schema_version != 2 {
        return Err(ProbeError::Fatal(format!(
            "schema {} is not a match line",
            facts.schema_version
        )));
    }
    if facts.kind != "arena" && facts.kind != "campaign" {
        return Err(ProbeError::Fatal(
            "the host did not say whether this is an arena or a mission".to_string(),
        ));
    }
    if facts.map.is_empty() {
        return Err(ProbeError::Fatal(
            "the host did not name the map".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::TcpListener;

    fn adapter(name: &str, ip: Ipv4Addr) -> JoinAdapter {
        JoinAdapter {
            name: name.to_string(),
            ip,
        }
    }

    #[test]
    fn population_note_names_the_caps_and_refuses_a_bot_per_connection() {
        let note = population_note(8, 64, 32);
        assert!(note.contains("8 rule bots"), "{note}");
        assert!(note.contains("64 connections"), "{note}");
        assert!(note.contains("32 from one address"), "{note}");
        assert!(note.contains("About 24 people"), "{note}");
        assert!(note.contains("not a measured match"), "{note}");
        let full = population_note(64, 64, 32);
        assert!(full.contains("64 rule bots"), "{full}");
        assert!(full.contains("not a measured match"), "{full}");
    }

    #[test]
    fn virtual_adapters_are_not_join_addresses() {
        let adapters = vec![
            adapter("Wi-Fi", Ipv4Addr::new(192, 168, 44, 46)),
            adapter("Tailscale", Ipv4Addr::new(100, 83, 110, 16)),
            adapter(
                "VMware Network Adapter VMnet8",
                Ipv4Addr::new(192, 168, 19, 1),
            ),
            adapter("vEthernet (WSL)", Ipv4Addr::new(172, 17, 208, 1)),
            adapter("Loopback Pseudo-Interface 1", Ipv4Addr::LOCALHOST),
            adapter("Ethernet", Ipv4Addr::new(169, 254, 1, 8)),
            adapter("Wi-Fi", Ipv4Addr::new(192, 168, 44, 46)),
        ];
        let offer = join_candidates(&adapters, "0.0.0.0:6767".parse().unwrap());
        assert_eq!(
            offer.offered,
            vec![
                "192.168.44.46:6767".parse().unwrap(),
                "100.83.110.16:6767".parse().unwrap(),
            ]
        );
        assert!(offer.skipped.iter().any(|line| line.contains("VMware")));
        assert!(offer.skipped.iter().any(|line| line.contains("WSL")));
        assert!(offer.skipped.iter().any(|line| line.contains("link-local")));
        assert!(!offer.skipped.iter().any(|line| line.contains("127.0.0.1")));
    }

    #[test]
    fn loopback_and_specific_binds_do_not_invent_addresses() {
        let adapters = vec![
            adapter("Wi-Fi", Ipv4Addr::new(192, 168, 44, 46)),
            adapter("Tailscale", Ipv4Addr::new(100, 83, 110, 16)),
        ];
        assert!(
            join_candidates(&adapters, "127.0.0.1:6767".parse().unwrap())
                .offered
                .is_empty()
        );
        assert_eq!(
            join_candidates(&adapters, "192.168.44.46:6767".parse().unwrap()).offered,
            vec!["192.168.44.46:6767".parse().unwrap()]
        );
        assert!(join_candidates(&adapters, "[::1]:6767".parse().unwrap())
            .offered
            .is_empty());
    }

    #[test]
    fn loopback_probe_follows_the_bind() {
        assert_eq!(
            loopback_probe_addr("0.0.0.0:6767".parse().unwrap()),
            "127.0.0.1:6767".parse().unwrap()
        );
        assert_eq!(
            loopback_probe_addr("192.168.44.46:6767".parse().unwrap()),
            "192.168.44.46:6767".parse().unwrap()
        );
        assert_eq!(
            loopback_probe_addr("[::]:6767".parse().unwrap()),
            "[::1]:6767".parse().unwrap()
        );
    }

    #[test]
    fn status_replies_keep_a_real_match_line() {
        let body = r#"{"schema_version":2,"kind":"campaign","map":"Recall Notice"}"#;
        let raw = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        );
        let facts = parse_status_reply(raw.as_bytes()).expect("campaign line");
        assert_eq!(facts.kind, "campaign");
        assert_eq!(facts.map, "Recall Notice");

        let schema_one = parse_status_reply(b"HTTP/1.1 200 OK\r\n\r\n{\"schema_version\":1}")
            .expect_err("schema 1");
        assert!(
            matches!(schema_one, ProbeError::Fatal(ref message) if message.contains("schema 1")),
            "{schema_one:?}"
        );
        let busy = parse_status_reply(
            b"HTTP/1.1 503 Service Unavailable\r\n\r\n{\"schema_version\":2,\"busy\":true}",
        )
        .expect_err("busy");
        assert!(matches!(busy, ProbeError::Retry(_)), "{busy:?}");
        let empty = parse_status_reply(b"HTTP/1.1 200 OK\r\n\r\n{}").expect_err("empty object");
        assert!(matches!(empty, ProbeError::Fatal(_)), "{empty:?}");
        let unnamed = parse_status_reply(
            b"HTTP/1.1 200 OK\r\n\r\n{\"schema_version\":2,\"kind\":\"arena\",\"map\":\"\"}",
        )
        .expect_err("unnamed map");
        assert!(
            matches!(unnamed, ProbeError::Fatal(ref message) if message.contains("map")),
            "{unnamed:?}"
        );

        let mut huge = b"HTTP/1.1 200 OK\r\n\r\n".to_vec();
        huge.extend(std::iter::repeat_n(b'x', CLIENT_STATUS_BODY_LIMIT + 1));
        let oversized = parse_status_reply(&huge).expect_err("oversized");
        assert!(
            matches!(oversized, ProbeError::Fatal(ref message) if message.contains("4096")),
            "{oversized:?}"
        );
        assert!(matches!(
            parse_status_reply(b"not http").unwrap_err(),
            ProbeError::Fatal(_)
        ));
        assert!(matches!(
            parse_status_reply(b"NOPE\r\n\r\n{}").unwrap_err(),
            ProbeError::Fatal(ref message) if message.contains("not HTTP")
        ));
        assert!(matches!(
            parse_status_reply(b"HTTP/1.1 404 No\r\n\r\n{}").unwrap_err(),
            ProbeError::Fatal(ref message) if message.contains("404")
        ));
        assert!(matches!(
            parse_status_reply(
                b"HTTP/1.1 200 OK\r\n\r\n{\"schema_version\":2,\"kind\":\"arena\",\"map\":\"Arena Duel\",\"busy\":true}"
            )
            .unwrap_err(),
            ProbeError::Retry(_)
        ));
        assert!(matches!(
            parse_status_reply(
                b"HTTP/1.1 200 OK\r\n\r\n{\"schema_version\":2,\"kind\":\"lobby\",\"map\":\"Arena Duel\"}"
            )
            .unwrap_err(),
            ProbeError::Fatal(ref message) if message.contains("arena")
        ));
    }

    #[test]
    fn join_lines_name_the_address_and_do_not_claim_the_other_computer() {
        let lan = join_success_line("192.168.44.46:6767".parse().unwrap());
        assert!(lan.contains("192.168.44.46:6767"));
        assert!(lan.contains("same network"));
        assert!(lan.contains("does not prove"));
        let overlay = join_success_line("100.83.110.16:6767".parse().unwrap());
        assert!(overlay.contains("private overlay"));
        assert!(overlay.contains("does not prove"));
        let public_addr = join_success_line("203.0.113.8:6767".parse().unwrap());
        assert!(public_addr.contains("path to it is open"));
        let failed = join_failure_line("192.168.44.46:6767".parse().unwrap(), "timed out");
        assert!(failed.contains("did not answer"));
        assert!(failed.contains("timed out"));
        assert!(failed.contains("does not prove"));
    }

    #[test]
    fn this_computer_can_list_adapters() {
        read_adapters().expect("interface list");
    }

    #[tokio::test]
    async fn loopback_bind_does_not_probe_other_addresses() {
        let started = std::time::Instant::now();
        log_join_checks("127.0.0.1:1".parse().unwrap()).await;
        assert!(started.elapsed() < Duration::from_millis(200));
    }

    #[tokio::test]
    async fn schema_one_is_not_retried() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let serve = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut buf = [0u8; 256];
            let _ = tokio::time::timeout(Duration::from_secs(1), socket.read(&mut buf)).await;
            let body = r#"{"schema_version":1}"#;
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = socket.write_all(response.as_bytes()).await;
        });
        let started = std::time::Instant::now();
        let error = require_status(addr).await.expect_err("schema 1");
        assert!(
            started.elapsed() < Duration::from_millis(800),
            "schema 1 must fail without the retry budget"
        );
        assert!(error.contains("schema 1"), "{error}");
        serve.abort();
    }

    #[tokio::test]
    async fn a_busy_reply_is_retried_then_reported() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let serve = tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    break;
                };
                let mut buf = [0u8; 256];
                let _ = tokio::time::timeout(Duration::from_secs(1), socket.read(&mut buf)).await;
                let body = r#"{"schema_version":2,"busy":true}"#;
                let response = format!(
                    "HTTP/1.1 503 Service Unavailable\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                let _ = socket.write_all(response.as_bytes()).await;
            }
        });
        let error = require_status_attempts(addr, 2).await.expect_err("busy");
        assert!(
            error.contains("busy") || error.contains("did not answer"),
            "{error}"
        );
        serve.abort();
    }

    #[tokio::test]
    async fn require_status_reads_a_live_match_line() {
        let (tx, _commands) = crate::net::game_channel();
        let mut server = crate::net::NetServer::bind("127.0.0.1:0", tx)
            .await
            .unwrap();
        server.share_status(std::sync::Arc::new(tokio::sync::RwLock::new(
            crate::protocol::LiveStatus {
                schema_version: 2,
                kind: "arena".into(),
                map: "Arena Duel".into(),
                ..crate::protocol::LiveStatus::default()
            },
        )));
        let addr = server.local_addr().unwrap();
        let accept = tokio::spawn(server.accept_loop());
        let facts = require_status(addr).await.expect("live status");
        assert_eq!(facts.schema_version, 2);
        assert_eq!(facts.kind, "arena");
        assert_eq!(facts.map, "Arena Duel");
        accept.abort();
    }
}
