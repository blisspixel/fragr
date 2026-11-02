//! The notice on the wire: a server keeping fun metrics says so in every
//! Welcome and in `/status`; one that is not says that too. A campaign
//! refuses the switch.
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_tungstenite::{connect_async, tungstenite::Message};

fn scratch() -> std::path::PathBuf {
    std::env::temp_dir().join(format!(
        "localexception-fun-wire-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ))
}

async fn status(address: std::net::SocketAddr) -> serde_json::Value {
    let mut tcp = tokio::net::TcpStream::connect(address).await.unwrap();
    tcp.write_all(b"GET /status HTTP/1.0\r\nHost: localhost\r\n\r\n")
        .await
        .unwrap();
    let mut text = String::new();
    tokio::time::timeout(
        std::time::Duration::from_secs(3),
        tcp.read_to_string(&mut text),
    )
    .await
    .unwrap()
    .unwrap();
    let body = text.split("\r\n\r\n").nth(1).unwrap();
    serde_json::from_str(body).unwrap()
}

async fn welcome(address: std::net::SocketAddr, role: &str) -> serde_json::Value {
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::json!({
                "type": "hello", "role": role, "name": "Notice",
                "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
                "geometry_version": crate::protocol::GEOMETRY_VERSION,
            })
            .to_string()
            .into(),
        ))
        .await
        .unwrap();
    let first = tokio::time::timeout(std::time::Duration::from_secs(3), socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let Message::Text(text) = first else {
        panic!("expected a text Welcome, got {first:?}");
    };
    serde_json::from_str(&text).unwrap()
}

async fn serve(fun_metrics: Option<std::path::PathBuf>) -> (std::net::SocketAddr, impl FnOnce()) {
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            fun_metrics,
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = ready_rx.await.unwrap();
    (address, move || {
        let _ = stop_tx.send(());
        drop(server);
    })
}

#[tokio::test]
async fn a_fun_metrics_server_announces_itself_before_anyone_fights() {
    let dir = scratch();
    let (address, stop) = serve(Some(dir.clone())).await;
    for role in ["human", "agent", "spectator"] {
        let welcome = welcome(address, role).await;
        assert_eq!(welcome["type"], "welcome");
        assert_eq!(welcome["fun_metrics"], true, "{role}: {welcome}");
    }
    let status = status(address).await;
    assert_eq!(status["fun_metrics"], true, "{status}");
    stop();
    assert!(dir.is_dir(), "the folder is made at start");
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn a_server_without_fun_metrics_says_so_plainly() {
    let (address, stop) = serve(None).await;
    let welcome = welcome(address, "human").await;
    assert_eq!(welcome["fun_metrics"], false, "{welcome}");
    let status = status(address).await;
    assert_eq!(status["fun_metrics"], false, "{status}");
    stop();
}

#[tokio::test]
async fn a_campaign_refuses_fun_metrics_before_it_binds() {
    let refused = crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(crate::maps::AuthoredSource::Mission(
                crate::protocol::MissionId::RecallNotice,
            )),
            fun_metrics: Some(scratch()),
            ..Default::default()
        },
        std::future::pending::<()>(),
        None,
    )
    .await
    .expect_err("a campaign keeps its own run file");
    assert!(refused
        .to_string()
        .contains("fun metrics are for arcade matches"));
}

/// Wait until the bot match has played some live ticks: warmup is two
/// seconds, so a tick past five seconds is live play.
async fn played(address: std::net::SocketAddr) {
    for _ in 0..200 {
        let status = status(address).await;
        if status["tick"].as_u64().unwrap_or(0) > 100 {
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    panic!("the bot match never got going");
}

fn bot_match(fun_metrics: std::path::PathBuf) -> crate::run::ServerOptions {
    crate::run::ServerOptions {
        bind: "127.0.0.1:0".into(),
        bots: 2,
        fun_metrics: Some(fun_metrics),
        ..Default::default()
    }
}

fn half_played(dir: &std::path::Path) {
    let (records, refused) = crate::fun_metrics::FunStore::read_all(dir).unwrap();
    assert!(refused.is_empty(), "{refused:?}");
    assert_eq!(records.len(), 1, "the stopped match is filed once");
    assert!(!records[0].finished, "and marked as not played out");
    assert!(records[0].tally.live_ticks > 0);
    assert!(records[0].tick_health.is_some());
}

#[tokio::test]
async fn a_stopped_server_files_the_half_played_match() {
    let dir = scratch();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    let server = tokio::spawn(crate::run::run_server(
        bot_match(dir.clone()),
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    played(ready_rx.await.unwrap()).await;
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
    half_played(&dir);
    let _ = std::fs::remove_dir_all(dir);
}

/// The binary's own stop: SIGTERM, as a service manager or `docker stop`
/// sends it, ends the loop through the same path. The handler is installed
/// before the signal is sent, so the test process is never at risk.
#[cfg(unix)]
#[tokio::test]
async fn sigterm_stops_the_server_and_files_the_half_played_match() {
    let dir = scratch();
    let stop = crate::run::stop_signal().unwrap();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        bot_match(dir.clone()),
        stop,
        Some(ready_tx),
    ));
    played(ready_rx.await.unwrap()).await;
    let sent = std::process::Command::new("kill")
        .args(["-TERM", &std::process::id().to_string()])
        .status()
        .unwrap();
    assert!(sent.success());
    tokio::time::timeout(std::time::Duration::from_secs(10), server)
        .await
        .expect("SIGTERM stops the loop")
        .unwrap()
        .unwrap();
    half_played(&dir);
    let _ = std::fs::remove_dir_all(dir);
}
