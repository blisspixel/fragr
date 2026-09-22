//! A drop keeps the pawn. An explicit leave does not.

use std::time::Duration;

use fragr_server::protocol::{Role, ServerMessage};
use fragr_server::run::{run_server, ServerOptions};
use futures_util::{SinkExt, StreamExt};
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[tokio::test]
async fn a_drop_keeps_the_same_pawn_and_leave_removes_it() {
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
    let address = timeout(Duration::from_secs(2), ready_rx)
        .await
        .expect("ready")
        .expect("bound");
    let url = format!("ws://{address}");

    let (mut human, _) = connect_async(&url).await.unwrap();
    human
        .send(Message::Text(
            r#"{"type":"hello","role":"human","name":"Patch","geometry_version":2,"gameplay_version":8,"resume":""}"#
                .into(),
        ))
        .await
        .unwrap();
    let (player_id, token) = welcome(&mut human).await;
    let player_id = player_id.expect("fighter");
    let token = token.expect("resume token");

    let (mut spectator, _) = connect_async(&url).await.unwrap();
    spectator
        .send(Message::Text(
            r#"{"type":"hello","role":"spectator","name":"Eyes","geometry_version":2,"gameplay_version":8}"#
                .into(),
        ))
        .await
        .unwrap();
    let (spectator_id, spectator_token) = welcome(&mut spectator).await;
    assert!(spectator_id.is_none());
    assert!(spectator_token.is_none());

    human.close(None).await.unwrap();
    for _ in 0..8 {
        assert!(
            snapshot_has(&mut spectator, "Patch").await,
            "a drop removed the pawn"
        );
    }

    let (mut again, _) = connect_async(&url).await.unwrap();
    again
        .send(Message::Text(
            format!(
                r#"{{"type":"hello","role":"human","name":"Patch","geometry_version":2,"gameplay_version":8,"resume":"{token}"}}"#
            ),
        ))
        .await
        .unwrap();
    let (resumed_id, new_token) = welcome(&mut again).await;
    assert_eq!(resumed_id, Some(player_id));
    assert!(new_token.is_some());
    assert!(snapshot_has(&mut spectator, "Patch").await);

    again
        .send(Message::Text(r#"{"type":"leave"}"#.into()))
        .await
        .unwrap();
    again.close(None).await.unwrap();
    let mut gone = false;
    for _ in 0..20 {
        if !snapshot_has(&mut spectator, "Patch").await {
            gone = true;
            break;
        }
    }
    assert!(gone, "leave left the pawn in the match");

    let _ = shutdown_tx.send(());
    server.await.unwrap().unwrap();
}

async fn welcome(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> (Option<uuid::Uuid>, Option<String>) {
    let message = timeout(Duration::from_secs(2), socket.next())
        .await
        .expect("welcome")
        .unwrap()
        .unwrap();
    match serde_json::from_str(message.to_text().unwrap()).unwrap() {
        ServerMessage::Welcome {
            player_id,
            resume,
            role: Role::Human | Role::Spectator,
            ..
        } => (player_id, resume),
        other => panic!("unexpected {other:?}"),
    }
}

async fn snapshot_has(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    name: &str,
) -> bool {
    loop {
        let message = timeout(Duration::from_secs(2), socket.next())
            .await
            .expect("snapshot")
            .unwrap()
            .unwrap();
        if let ServerMessage::Snapshot(snapshot) =
            serde_json::from_str(message.to_text().unwrap()).unwrap()
        {
            return snapshot.players.iter().any(|player| player.name == name);
        }
    }
}
