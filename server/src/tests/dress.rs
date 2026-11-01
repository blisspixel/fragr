//! A participant's look and accent (`Dress`): presentation only. Rule bots,
//! agents and humans who leave the look to the server get the least-worn
//! look of their body, a Hello may ask for one, the snapshot carries it, and
//! a campaign run binds it like the body.
use crate::maps::AuthoredSource;
use crate::net::GameCommand;
use crate::protocol::{
    BodyKind, ClientMessage, Dress, MissionId, PlayerState, Role, HUMAN_LOOKS, SYNTHETIC_LOOKS,
};
use crate::session::GameSession;
use crate::sim::GameState;
use uuid::Uuid;

fn looks(session: &GameSession, body: BodyKind) -> Vec<u8> {
    session
        .state
        .snapshot()
        .players
        .iter()
        .filter(|player| player.body == Some(body))
        .map(|player| player.dress.and_then(|dress| dress.look).expect("look"))
        .collect()
}

#[test]
fn rule_bots_never_fill_a_room_with_clones() {
    let mut session = GameSession::new();
    session.spawn_bots(16);
    for (body, count) in [
        (BodyKind::Human, HUMAN_LOOKS),
        (BodyKind::Synthetic, SYNTHETIC_LOOKS),
    ] {
        let worn = looks(&session, body);
        assert_eq!(worn.len(), 8, "{body:?}");
        // No look repeats until every look of that body is in the room.
        let mut counts = vec![0; usize::from(count)];
        for look in &worn {
            counts[usize::from(*look)] += 1;
        }
        let (least, most) = (counts.iter().min(), counts.iter().max());
        assert!(
            most.unwrap() - least.unwrap() <= 1,
            "{body:?} looks spread evenly: {counts:?}"
        );
        assert!(worn.iter().all(|look| *look < count));
    }
    // Deterministic: a second room filled the same way dresses the same.
    let mut again = GameSession::new();
    again.spawn_bots(16);
    for body in BodyKind::ALL {
        assert_eq!(looks(&session, body), looks(&again, body));
    }
    // Bots carry no personal accent; their tape is their callsign colour.
    assert!(session
        .state
        .snapshot()
        .players
        .iter()
        .all(|player| player.dress.and_then(|dress| dress.accent).is_none()));
}

#[test]
fn hello_dress_parses_inside_the_roster_and_refuses_outside() {
    let hello = serde_json::json!({"type":"hello", "name":"Look", "role":"human",
        "body":"synthetic", "dress":{"look":4, "accent":7}});
    let ClientMessage::Hello { dress, .. } = serde_json::from_value(hello).unwrap() else {
        panic!("hello");
    };
    assert_eq!(
        dress,
        Some(Dress {
            look: Some(4),
            accent: Some(7)
        })
    );
    for invalid in [
        serde_json::json!({"look": 8}),
        serde_json::json!({"accent": 8}),
        serde_json::json!({"look": "res://look.png"}),
        serde_json::json!({"look": 1, "colour": "#ff0000"}),
        serde_json::json!("look_human_1"),
    ] {
        let hello =
            serde_json::json!({"type":"hello", "name":"Look", "role":"human", "dress": invalid});
        assert!(
            serde_json::from_value::<ClientMessage>(hello).is_err(),
            "{invalid}"
        );
    }
    let without = serde_json::json!({"type":"hello", "name":"Look", "role":"agent"});
    assert!(matches!(
        serde_json::from_value::<ClientMessage>(without).unwrap(),
        ClientMessage::Hello { dress: None, .. }
    ));
}

#[test]
fn a_requested_dress_rides_the_snapshot_and_a_bad_look_keeps_the_assigned_one() {
    let mut session = GameSession::new();
    let (human, agent, spectator) = (Uuid::from_u128(1), Uuid::from_u128(2), Uuid::from_u128(3));
    for (id, role, body) in [
        (human, Role::Human, BodyKind::Human),
        (agent, Role::Agent, BodyKind::Synthetic),
    ] {
        session.apply_command(GameCommand::Connected {
            id,
            role,
            name: format!("{role:?}"),
            player_id: Some(id),
            body,
        });
    }
    session.apply_command(GameCommand::Connected {
        id: spectator,
        role: Role::Spectator,
        name: "Watcher".into(),
        player_id: None,
        body: BodyKind::Human,
    });
    session.apply_command(GameCommand::Dress {
        player_id: human,
        dress: Dress {
            look: Some(7),
            accent: Some(2),
        },
    });
    // Look 6 is a human look the synthetic body does not have.
    session.apply_command(GameCommand::Dress {
        player_id: agent,
        dress: Dress {
            look: Some(6),
            accent: Some(5),
        },
    });
    session.apply_command(GameCommand::Dress {
        player_id: Uuid::from_u128(99),
        dress: Dress::default(),
    });
    let snapshot = session.state.snapshot();
    let dress_of = |id: Uuid| snapshot.players.iter().find(|p| p.id == id).unwrap().dress;
    assert_eq!(
        dress_of(human),
        Some(Dress {
            look: Some(7),
            accent: Some(2)
        })
    );
    let agent_dress = dress_of(agent).unwrap();
    assert_eq!(agent_dress.accent, Some(5));
    assert!(
        agent_dress.look.unwrap() < SYNTHETIC_LOOKS,
        "kept its assigned look"
    );
    assert!(snapshot.players.iter().all(|p| p.id != spectator));
    // On the wire: `dress` beside `body`, and a strict reader refuses junk.
    let mut pawn =
        serde_json::to_value(snapshot.players.iter().find(|p| p.id == human).unwrap()).unwrap();
    assert_eq!(pawn["dress"], serde_json::json!({"look": 7, "accent": 2}));
    pawn["dress"] = serde_json::json!({"look": 200});
    assert!(serde_json::from_value::<PlayerState>(pawn).is_err());
}

#[test]
fn a_dress_changes_no_seeded_combat_outcome() {
    let run = |dress: Dress| {
        let mut state = GameState::new();
        state.seed(7);
        state.use_replay_ids();
        for id in 1..=4 {
            state.add_player_with_body(
                Uuid::from_u128(id),
                format!("P{id}"),
                Role::Agent,
                BodyKind::Human,
            );
        }
        state.dress_player(Uuid::from_u128(1), dress);
        state.start_round();
        for _ in 0..200 {
            state.tick(0.05);
        }
        state
            .snapshot()
            .players
            .iter()
            .map(|p| (p.id, p.hp, p.score, p.x.to_bits(), p.z.to_bits()))
            .collect::<Vec<_>>()
    };
    assert_eq!(
        run(Dress::default()),
        run(Dress {
            look: Some(5),
            accent: Some(1)
        })
    );
}

#[test]
fn a_campaign_run_binds_its_first_dress_and_keeps_it() {
    let map = AuthoredSource::Mission(MissionId::RecallNotice)
        .load()
        .unwrap();
    let mut session = GameSession::with_authored_map(map.clone());
    session.state.enable_campaign_run().unwrap();
    let owner = Uuid::from_u128(1);
    session.apply_command(GameCommand::Connected {
        id: owner,
        role: Role::Human,
        name: "Runner".into(),
        player_id: Some(owner),
        body: BodyKind::Human,
    });
    let chosen = Dress {
        look: Some(3),
        accent: Some(6),
    };
    session.apply_command(GameCommand::Dress {
        player_id: owner,
        dress: chosen,
    });
    // A later request inside the same run changes nothing.
    session.apply_command(GameCommand::Dress {
        player_id: owner,
        dress: Dress {
            look: Some(1),
            accent: None,
        },
    });
    assert_eq!(session.state.players[0].dress, chosen);
    let document = session
        .state
        .campaign_run_document()
        .unwrap()
        .expect("run document");
    assert_eq!(document.dress, Some(chosen));
    let saved = serde_json::to_value(&document).unwrap();
    assert_eq!(saved["dress"], serde_json::json!({"look": 3, "accent": 6}));

    // The saved run dresses its owner on the next session, whatever the
    // next Hello asks for.
    let mut next = GameState::with_authored_map(map);
    next.load_campaign_run(&document).unwrap();
    let returning = Uuid::from_u128(2);
    next.add_player_with_body(returning, "Runner".into(), Role::Human, BodyKind::Human);
    next.dress_player(
        returning,
        Dress {
            look: Some(0),
            accent: Some(0),
        },
    );
    let player = next.players.iter().find(|p| p.id == returning).unwrap();
    assert_eq!(player.dress, chosen);
}
