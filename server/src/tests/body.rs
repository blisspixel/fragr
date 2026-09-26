//! The chosen body is identity only: it rides the wire and the snapshot, and
//! nothing the simulation decides reads it.
use crate::maps::AuthoredSource;
use crate::net::GameCommand;
use crate::protocol::{
    Action, BodyKind, CampaignActor, ClientMessage, GameMode, LookAt, MissionId, MissionReady,
    PlayerState, Role, ServerMessage, Team, WeaponType,
};
use crate::rules::RuleSet;
use crate::session::GameSession;
use crate::sim::{GameState, MapKind, MatchConfig};
use uuid::Uuid;

#[test]
fn hello_welcome_and_snapshot_carry_an_allowlisted_body() {
    for role in ["human", "agent", "spectator"] {
        let mut hello = serde_json::json!({"type":"hello", "name":"Same", "role":role});
        let ClientMessage::Hello { body, .. } = serde_json::from_value(hello.clone()).unwrap()
        else {
            panic!("hello");
        };
        assert_eq!(body, None, "an omitted body stays unset on the wire");
        for (value, expected) in [
            (serde_json::Value::Null, None),
            (serde_json::json!("human"), Some(BodyKind::Human)),
            (serde_json::json!("synthetic"), Some(BodyKind::Synthetic)),
        ] {
            hello["body"] = value;
            let ClientMessage::Hello { body, .. } = serde_json::from_value(hello.clone()).unwrap()
            else {
                panic!("hello");
            };
            assert_eq!(body, expected);
        }
        for invalid in [
            serde_json::json!("Human"),
            serde_json::json!("robot"),
            serde_json::json!("res://body.png"),
            serde_json::json!(7),
            serde_json::json!({"kind":"synthetic"}),
        ] {
            hello["body"] = invalid;
            assert!(serde_json::from_value::<ClientMessage>(hello.clone()).is_err());
        }
    }
    // An older server's Welcome has no body, and a spectator's never does.
    let legacy: ServerMessage =
        serde_json::from_str(r#"{"type":"welcome","role":"human","player_id":null}"#).unwrap();
    assert!(matches!(legacy, ServerMessage::Welcome { body: None, .. }));
    let spectator = ServerMessage::Welcome {
        player_id: None,
        role: Role::Spectator,
        mode_name: "m".into(),
        playlist: "p".into(),
        resume: None,
        body: None,
    };
    assert!(serde_json::to_value(&spectator)
        .unwrap()
        .get("body")
        .is_none());

    let mut state = GameState::new();
    state.add_player_with_body(
        Uuid::from_u128(1),
        "Wire".into(),
        Role::Agent,
        BodyKind::Synthetic,
    );
    let mut pawn = serde_json::to_value(&state.snapshot().players[0]).unwrap();
    assert_eq!(pawn["body"], "synthetic");
    pawn.as_object_mut().unwrap().remove("body");
    assert_eq!(
        serde_json::from_value::<PlayerState>(pawn.clone())
            .unwrap()
            .body,
        None,
        "an older snapshot without a body still reads"
    );
    pawn["body"] = serde_json::json!("unknown");
    assert!(serde_json::from_value::<PlayerState>(pawn).is_err());
}

fn duel(body: BodyKind, role: Role) -> GameState {
    let mut state = GameState::new();
    state.seed(42);
    state.use_replay_ids();
    state.add_player_with_body(Uuid::from_u128(1), "Same".into(), role, body);
    state.add_player(Uuid::from_u128(2), "Target".into(), Role::Human);
    state.start_round();
    state.spawn_shields.clear();
    for (index, player) in state.players.iter_mut().enumerate() {
        player.x = -6.0;
        player.z = -3.0 + index as f32 * 5.0;
        player.yaw = 0.0;
    }
    state
}

#[test]
fn body_changes_no_seeded_combat_outcome_and_survives_respawn() {
    for role in [Role::Human, Role::Agent] {
        let mut states = [duel(BodyKind::Human, role), duel(BodyKind::Synthetic, role)];
        let mut hits = 0;
        for tick in 0..180 {
            for state in &mut states {
                state.set_action(
                    Uuid::from_u128(1),
                    Action {
                        fire: true,
                        forward: tick > 140,
                        look_at: Some(LookAt {
                            player_id: Some(Uuid::from_u128(2)),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                );
                state.tick(0.05);
            }
            hits += states[0]
                .shot_results
                .iter()
                .filter(|shot| shot.damage > 0)
                .count();
            let mut snapshots = states
                .iter()
                .map(|state| serde_json::to_value(state.snapshot()).unwrap())
                .collect::<Vec<_>>();
            for snapshot in &mut snapshots {
                for player in snapshot["players"].as_array_mut().unwrap() {
                    player.as_object_mut().unwrap().remove("body");
                }
            }
            assert_eq!(
                snapshots[0], snapshots[1],
                "body changed the simulation at tick {tick}"
            );
            for id in [Uuid::from_u128(1), Uuid::from_u128(2)] {
                assert_eq!(
                    serde_json::to_value(states[0].player_record(id)).unwrap(),
                    serde_json::to_value(states[1].player_record(id)).unwrap()
                );
            }
        }
        assert!(hits > 0, "the parity exercise must resolve damage");
        assert!(states[0].scores[&Uuid::from_u128(1)] > 0, "and a frag");
        let synthetic = &mut states[1];
        assert_eq!(synthetic.players[0].role, role);
        synthetic.players[0].hp = 0;
        synthetic.players[0].respawn_timer = Some(1);
        synthetic.tick(0.05);
        synthetic.tick(0.05);
        assert!(synthetic.players[0].hp > 0, "the fighter respawned");
        assert_eq!(
            synthetic.players[0].body,
            BodyKind::Synthetic,
            "respawn changed the body"
        );
    }
}

#[test]
fn rule_bots_alternate_bodies_and_authored_foes_have_none() {
    let mut session = GameSession::new();
    session.spawn_bots(4);
    let bodies = session
        .state
        .snapshot()
        .players
        .iter()
        .map(|player| player.body)
        .collect::<Vec<_>>();
    assert_eq!(
        bodies,
        [
            Some(BodyKind::Human),
            Some(BodyKind::Synthetic),
            Some(BodyKind::Human),
            Some(BodyKind::Synthetic)
        ]
    );
    // Renaming or recasting a bot's controller does not move its body.
    for player in &mut session.state.players {
        player.name = "Same".into();
        player.role = Role::Human;
    }
    assert_eq!(
        session
            .state
            .snapshot()
            .players
            .iter()
            .map(|player| player.body)
            .collect::<Vec<_>>(),
        bodies
    );

    // The arena boss keeps its own authored identity.
    let mut state = GameState::new();
    state.add_player(Uuid::from_u128(9), "Owner".into(), Role::Human);
    state.start_round();
    let boss = state.spawn_compliance_drone().expect("boss");
    let snapshot = state.snapshot();
    let boss_state = snapshot.players.iter().find(|p| p.id == boss).unwrap();
    assert_eq!(boss_state.body, None);

    // Union actors in a mission carry no participant body; the owner does.
    let map = AuthoredSource::Mission(MissionId::RecallNotice)
        .load()
        .unwrap();
    for role in [Role::Human, Role::Agent] {
        for body in BodyKind::ALL {
            let mut session = GameSession::with_authored_map(map.clone());
            session.state.enable_campaign_run().unwrap();
            let id = Uuid::from_u128(1);
            session.apply_command(GameCommand::Connected {
                id,
                player_id: Some(id),
                role,
                body,
                name: "Sweeper".into(),
            });
            let owner = &session.state.players[0];
            assert_eq!((owner.body, owner.role), (body, role));
            assert_eq!(owner.campaign, Some(CampaignActor::Participant {}));
            assert_eq!(owner.weapon, WeaponType::Fists);
            let mission = session.state.mission_state().unwrap();
            assert!(session.state.acknowledge_mission(
                id,
                MissionReady {
                    id: mission.id,
                    attempt: mission.attempt,
                }
            ));
            for player in session.state.snapshot().players {
                if player.id == id {
                    assert_eq!(player.body, Some(body));
                } else {
                    assert!(
                        player.campaign.is_some_and(CampaignActor::is_enemy),
                        "only Union actors share the owner's room"
                    );
                    assert_eq!(player.body, None, "a Union actor wore a participant body");
                }
            }
        }
    }
}

#[test]
fn team_sides_ignore_the_body() {
    let config = |rules: RuleSet| MatchConfig {
        frag_limit: Some(rules.default_frag_limit()),
        rules,
        ..MatchConfig::default()
    };
    let sides = |bodies: [BodyKind; 4]| {
        let mut state = GameState::with_map(MapKind::ArenaDuel, false);
        state.seed(11);
        state.apply_config(config(RuleSet::new(GameMode::Tdm, &[], false).unwrap()));
        for (index, body) in bodies.into_iter().enumerate() {
            state.add_player_with_body(
                Uuid::from_u128(index as u128 + 1),
                format!("F{index}"),
                Role::Human,
                body,
            );
        }
        state
            .snapshot()
            .players
            .iter()
            .map(|player| (player.team, player.body))
            .collect::<Vec<_>>()
    };
    let humans = sides([BodyKind::Human; 4]);
    let mixed = sides([
        BodyKind::Synthetic,
        BodyKind::Human,
        BodyKind::Human,
        BodyKind::Synthetic,
    ]);
    assert_eq!(
        humans.iter().map(|(team, _)| *team).collect::<Vec<_>>(),
        mixed.iter().map(|(team, _)| *team).collect::<Vec<_>>(),
        "the body picked a side"
    );
    assert!(mixed
        .iter()
        .all(|(team, body)| team.is_some() && body.is_some()));
    // Both sides field both bodies, so appearance never names an allegiance.
    for side in [Team::Union, Team::Coalition] {
        let bodies: std::collections::HashSet<_> = mixed
            .iter()
            .filter(|(team, _)| *team == Some(side))
            .map(|(_, body)| *body)
            .collect();
        assert_eq!(bodies.len(), 2, "{side:?} fielded one body");
    }
}
