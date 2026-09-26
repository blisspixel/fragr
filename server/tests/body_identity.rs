//! The chosen body travels in Hello, comes back on Welcome, reaches every
//! watcher in the snapshot, and survives a resume that asks for another.

use std::time::Duration;

use fragr_server::protocol::{BodyKind, Role, ServerMessage, BODY_GAMEPLAY_VERSION};
use fragr_server::run::{run_server, ServerOptions};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};
use uuid::Uuid;

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

async fn next_message(socket: &mut Socket) -> Option<ServerMessage> {
    timeout(Duration::from_secs(3), async {
        loop {
            match socket.next().await {
                Some(Ok(Message::Text(text))) => return serde_json::from_str(&text).ok(),
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => return None,
                Some(Ok(_)) => {}
            }
        }
    })
    .await
    .expect("server reply deadline")
}

async fn hello(url: &str, value: serde_json::Value) -> Socket {
    let (mut socket, _) = connect_async(url).await.unwrap();
    socket.send(Message::Text(value.to_string())).await.unwrap();
    socket
}

/// The body a snapshot shows for `id`, waiting for the pawn to appear.
async fn snapshot_body(socket: &mut Socket, id: Uuid) -> Option<BodyKind> {
    for _ in 0..60 {
        match next_message(socket).await {
            Some(ServerMessage::Snapshot(snapshot)) => {
                if let Some(player) = snapshot.players.iter().find(|player| player.id == id) {
                    return player.body;
                }
            }
            Some(_) => {}
            None => panic!("watcher closed"),
        }
    }
    panic!("pawn never appeared in a snapshot");
}

#[tokio::test]
async fn body_is_accepted_shown_to_watchers_and_kept_across_resume() {
    tokio::task::spawn_blocking(fragr_server::session::GameSession::new)
        .await
        .expect("navigation");
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel();
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        run_server(
            ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                ..ServerOptions::default()
            },
            async move {
                let _ = shutdown_rx.await;
            },
            Some(ready_tx),
        )
        .await
        .map_err(|error| error.to_string())
    });
    let address = timeout(Duration::from_secs(5), ready_rx)
        .await
        .expect("ready")
        .expect("bound");
    let url = format!("ws://{address}");

    let mut watcher = hello(
        &url,
        json!({"type":"hello","role":"spectator","name":"Eyes","geometry_version":2,
            "gameplay_version":BODY_GAMEPLAY_VERSION,"body":"synthetic"}),
    )
    .await;
    match next_message(&mut watcher).await {
        Some(ServerMessage::Welcome {
            player_id: None,
            body: None,
            ..
        }) => {}
        other => panic!("a spectator took a body: {other:?}"),
    }

    // Every participant role takes either body, and an omitted body is human.
    let mut kept = Vec::new();
    for role in [Role::Human, Role::Agent] {
        for requested in [None, Some(BodyKind::Human), Some(BodyKind::Synthetic)] {
            let mut message = json!({"type":"hello","role":role,"name":"Same label",
                "geometry_version":2,"gameplay_version":BODY_GAMEPLAY_VERSION,"resume":""});
            if let Some(body) = requested {
                message["body"] = json!(body);
            }
            let mut socket = hello(&url, message).await;
            let Some(ServerMessage::Welcome {
                player_id: Some(id),
                role: accepted_role,
                body: Some(body),
                resume: Some(token),
                ..
            }) = next_message(&mut socket).await
            else {
                panic!("participant welcome without an accepted body");
            };
            assert_eq!(accepted_role, role, "body changed the control role");
            assert_eq!(body, requested.unwrap_or_default());
            assert_eq!(snapshot_body(&mut watcher, id).await, Some(body));
            kept.push((socket, id, role, body, token));
        }
    }

    // A body outside the allowlist never reaches admission.
    for invalid in [json!("robot"), json!("res://body.png"), json!(7)] {
        let mut socket = hello(
            &url,
            json!({"type":"hello","role":"human","name":"Bad","geometry_version":2,
                "gameplay_version":BODY_GAMEPLAY_VERSION,"body":invalid}),
        )
        .await;
        assert!(
            !matches!(
                next_message(&mut socket).await,
                Some(ServerMessage::Welcome { .. })
            ),
            "an unknown body was admitted"
        );
    }

    // A drop and resume that asks for the other body keeps the pawn's own.
    let (mut socket, id, role, body, token) = kept.pop().unwrap();
    assert_eq!(body, BodyKind::Synthetic);
    socket.close(None).await.unwrap();
    let mut again = hello(
        &url,
        json!({"type":"hello","role":role,"name":"Same label","geometry_version":2,
            "gameplay_version":BODY_GAMEPLAY_VERSION,"resume":token,"body":"human"}),
    )
    .await;
    match next_message(&mut again).await {
        Some(ServerMessage::Welcome {
            player_id: Some(resumed),
            body: Some(resumed_body),
            ..
        }) => {
            assert_eq!(resumed, id);
            assert_eq!(resumed_body, BodyKind::Synthetic, "resume rewrote the body");
        }
        other => panic!("resume failed: {other:?}"),
    }
    assert_eq!(
        snapshot_body(&mut watcher, id).await,
        Some(BodyKind::Synthetic)
    );

    let _ = shutdown_tx.send(());
    server.await.unwrap().unwrap();
}
