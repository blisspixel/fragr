use super::*;
use tokio::time::{timeout, Duration};
use tokio_tungstenite::connect_async;

#[tokio::test]
async fn raised_geometry_rejects_legacy_roles_before_welcome_or_join() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind_with_geometry("127.0.0.1:0", tx, 2)
        .await
        .unwrap();
    let address = server.local_addr().unwrap();
    let clients = server.clients.clone();
    let accept = tokio::spawn(server.accept_loop());
    for role in ["human", "agent", "spectator"] {
        for version in [None, Some(0), Some(1)] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            let mut hello = serde_json::json!({"type":"hello", "role":role, "name":"Legacy"});
            if let Some(version) = version {
                hello["geometry_version"] = version.into();
            }
            socket.send(Message::Text(hello.to_string())).await.unwrap();
            let reply = timeout(Duration::from_secs(2), socket.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            let rejection: ServerMessage = serde_json::from_str(reply.to_text().unwrap()).unwrap();
            assert!(
                matches!(rejection, ServerMessage::Error { code, .. } if code == "unsupported_geometry")
            );
            assert!(matches!(
                timeout(Duration::from_secs(2), socket.next())
                    .await
                    .unwrap(),
                Some(Ok(Message::Close(_)))
            ));
            assert!(
                commands.try_recv().is_err(),
                "rejected client reached the game session"
            );
            assert!(clients.lock().await.is_empty());
        }
    }
    // A future client declaring support for all earlier formats can still join.
    for version in [2, 3] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket
            .send(Message::Text(
                serde_json::json!({
                    "type":"hello", "role":"human", "name":"Current", "geometry_version":version,
                })
                .to_string(),
            ))
            .await
            .unwrap();
        let reply = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert!(matches!(
            serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
            ServerMessage::Welcome {
                player_id: Some(_),
                ..
            }
        ));
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Connected { .. })
        ));
        socket.close(None).await.unwrap();
        assert!(matches!(
            timeout(Duration::from_secs(2), commands.recv())
                .await
                .unwrap(),
            Some(GameCommand::Disconnected { .. })
        ));
    }
    accept.abort();
}

#[tokio::test]
async fn server_rejects_unsupported_geometry_configuration() {
    for version in [0, crate::protocol::GEOMETRY_VERSION + 1] {
        let (tx, _) = mpsc::unbounded_channel();
        let result = NetServer::bind_with_geometry("127.0.0.1:0", tx, version).await;
        assert!(matches!(result, Err(error) if error.kind() == std::io::ErrorKind::InvalidInput));
    }
}

#[tokio::test]
async fn mission_admission_bounds_participants_and_keeps_spectators_separate() {
    let (tx, mut commands) = mpsc::unbounded_channel();
    let server = NetServer::bind_with_requirements("127.0.0.1:0", tx, 2, 4)
        .await
        .unwrap();
    let address = server.local_addr().unwrap();
    let accept = tokio::spawn(server.accept_loop());
    let mut joined = Vec::new();
    for (role, version, expected) in [
        ("human", 3, "unsupported_gameplay"),
        ("human", 4, "welcome"),
        ("agent", 4, "welcome"),
        ("human", 4, "welcome"),
        ("agent", 4, "welcome"),
        ("human", 4, "party_full"),
        ("agent", 4, "party_full"),
        ("spectator", 4, "welcome"),
    ] {
        let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
        socket.send(Message::Text(serde_json::json!({
            "type":"hello","role":role,"name":"Visitor","geometry_version":2,"gameplay_version":version
        }).to_string())).await.unwrap();
        let reply = timeout(Duration::from_secs(2), socket.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        let reply: ServerMessage = serde_json::from_str(reply.to_text().unwrap()).unwrap();
        if expected == "welcome" {
            assert!(matches!(reply, ServerMessage::Welcome { .. }));
            assert!(matches!(
                timeout(Duration::from_secs(2), commands.recv())
                    .await
                    .unwrap(),
                Some(GameCommand::Connected { .. })
            ));
            joined.push(socket);
        } else {
            assert!(matches!(reply, ServerMessage::Error { code, .. } if code == expected));
            assert!(commands.try_recv().is_err());
        }
    }
    assert_eq!(joined.len(), 5);
    let mut departed = joined.remove(0);
    departed.close(None).await.unwrap();
    assert!(matches!(
        timeout(Duration::from_secs(2), commands.recv())
            .await
            .unwrap(),
        Some(GameCommand::Disconnected { .. })
    ));
    let (mut replacement, _) = connect_async(format!("ws://{address}")).await.unwrap();
    replacement.send(Message::Text(serde_json::json!({"type":"hello","role":"agent","name":"Replacement","geometry_version":2,"gameplay_version":4}).to_string())).await.unwrap();
    let reply = timeout(Duration::from_secs(2), replacement.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(matches!(
        serde_json::from_str::<ServerMessage>(reply.to_text().unwrap()).unwrap(),
        ServerMessage::Welcome {
            player_id: Some(_),
            ..
        }
    ));
    for mut socket in joined {
        socket.close(None).await.unwrap();
    }
    replacement.close(None).await.unwrap();
    accept.abort();
}
