use super::*;
use crate::maps::AuthoredMap;
use crate::net::GameCommand;
use crate::protocol::{Action, LookAt, Role, ServerMessage};
use crate::session::{GameSession, Recipient};
use serde_json::json;

fn arena() -> (GameState, Uuid, Uuid) {
    let map = AuthoredMap::read(
        serde_json::to_vec(&json!({
            "version": 1, "map_id": 1000, "name": "Record fixture", "half_extent": 12,
            "ground": "concrete", "equipment": "full_arsenal", "solids": [],
            "spawns": [{"id": "entry", "feet": [0, 0, -6], "yaw": 1.5707964}],
            "landmarks": [{"id": "exit", "feet": [0, 0, 10]}]
        }))
        .unwrap()
        .as_slice(),
    )
    .unwrap();
    let mut state = GameState::with_authored_map(map);
    state.seed(42);
    let a = Uuid::from_u128(1);
    let b = Uuid::from_u128(2);
    state.add_player(a, "Same label".into(), Role::Human);
    state.add_player(b, "Same label".into(), Role::Agent);
    for (i, player) in state.players.iter_mut().enumerate() {
        player.x = i as f32 * 3.0;
        player.z = 0.0;
        player.weapon = WeaponType::Rail;
    }
    (state, a, b)
}

fn fire(state: &mut GameState, id: Uuid, target: Uuid) {
    state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(target),
                x: None,
                y: None,
                z: None,
            }),
            ..Default::default()
        },
    );
}

#[test]
fn records_measure_effective_damage_and_count_only_the_first_death() {
    let (mut state, a, b) = arena();
    state.players[1].hp = 10;
    state.players[1].armor = 17;
    let c = Uuid::from_u128(3);
    state.add_player(c, "Second ray".into(), Role::Agent);
    state.players[2].x = 3.0;
    state.players[2].z = 3.0;
    state.players[2].weapon = WeaponType::Rail;
    fire(&mut state, a, b);
    fire(&mut state, c, b);
    state.tick(0.05);
    let first = state.player_record(a).unwrap();
    assert_eq!(
        first.total.weapon(WeaponType::Rail),
        &crate::protocol::WeaponCounts {
            attacks: 1,
            damaging_attacks: 1,
            kills: 1,
            hp_damage: 10,
            armor_damage: 17,
        }
    );
    let second = state.player_record(c).unwrap();
    assert_eq!(second.total.attacks(), 1);
    assert_eq!(second.total.weapon(WeaponType::Rail).damaging_attacks, 0);
    assert_eq!(second.total.kills(), 0);
    let victim = state.player_record(b).unwrap();
    assert_eq!(
        (
            victim.total.deaths,
            victim.total.hp_lost,
            victim.total.armor_lost
        ),
        (1, 10, 17)
    );
    assert_eq!(victim.total.alive_ticks, 1);
    state.tick(0.05);
    let next = state.player_record(b).unwrap();
    assert_eq!(
        next.total, victim.total,
        "dead waiting adds no living time or repeat death"
    );
    next.validate_for(Some(b), Some(&victim)).unwrap();
    assert_eq!(state.shot_results.len(), 0);
    state.remove_player(b);
    assert!(state.player_record(b).is_none());
    assert_eq!(state.player_record(a).unwrap().total.kills(), 1);
}

#[test]
fn both_committed_trade_shots_keep_their_credit() {
    let (mut state, a, b) = arena();
    state.players[0].hp = 10;
    state.players[1].hp = 10;
    fire(&mut state, a, b);
    fire(&mut state, b, a);
    state.tick(0.05);
    for id in [a, b] {
        let record = state.player_record(id).unwrap();
        assert_eq!(record.total.kills(), 1);
        assert_eq!(record.total.deaths, 1);
        assert_eq!(record.total.weapon(WeaponType::Rail).hp_damage, 10);
        record.validate_for(Some(id), None).unwrap();
    }
}

#[test]
fn misses_cooldown_and_administrative_removal_do_not_invent_hits_or_deaths() {
    let (mut state, a, b) = arena();
    state.set_action(
        a,
        Action {
            fire: true,
            yaw: Some(std::f32::consts::PI),
            ..Default::default()
        },
    );
    state.tick(0.05);
    state.tick(0.05);
    let record = state.player_record(a).unwrap();
    assert_eq!(record.total.attacks(), 1);
    assert_eq!(record.total.weapon(WeaponType::Rail).damaging_attacks, 0);
    assert_eq!(record.total.alive_ticks, 2);
    state.remove_player(b);
    assert_eq!(state.player_record(a).unwrap().total.kills(), 0);
    state.end_round("test terminal".into());
    let ended = state.player_record(a).unwrap();
    state.tick(0.05);
    let waiting = state.player_record(a).unwrap();
    assert_eq!(waiting.total, ended.total);
    assert_eq!(waiting.status, RecordStatus::Complete);
    waiting.validate_for(Some(a), Some(&ended)).unwrap();
    state.start_round();
    let next = state.player_record(a).unwrap();
    assert_eq!(next.round, ended.round + 1);
    assert_eq!(next.total, CombatCounts::default());
    next.validate_for(Some(a), Some(&ended)).unwrap();
}

#[test]
fn records_are_private_cadenced_and_terminal_delivery_is_immediate() {
    let mut session = GameSession::new();
    let id = Uuid::new_v4();
    session.apply_command(GameCommand::Connected {
        body: crate::protocol::BodyKind::Human,
        id,
        role: Role::Human,
        name: "Probe".into(),
        player_id: Some(id),
    });
    session.apply_command(GameCommand::Connected {
        body: crate::protocol::BodyKind::Human,
        id: Uuid::new_v4(),
        role: Role::Spectator,
        name: "Observer".into(),
        player_id: None,
    });
    session.take_unicasts();
    assert!(session.state.player_record(id).is_none());
    session.state.start_round();
    for tick in 1..=21 {
        let broadcast = session.tick_messages(0.05);
        assert!(!broadcast
            .iter()
            .any(|message| matches!(message, ServerMessage::Record(_))));
        let records: Vec<_> = session
            .take_unicasts()
            .into_iter()
            .filter_map(|(recipient, message)| {
                if let ServerMessage::Record(record) = message {
                    Some((recipient, record))
                } else {
                    None
                }
            })
            .collect();
        assert_eq!(records.len(), usize::from(tick == 1 || tick == 21));
        for (recipient, record) in records {
            assert_eq!(recipient, Recipient::Player(id));
            record.validate_for(Some(id), None).unwrap();
        }
    }
    session.state.end_round("test terminal".into());
    session.tick_messages(0.05);
    assert!(session.take_unicasts().iter().any(|(_, message)| matches!(message, ServerMessage::Record(record) if record.status == RecordStatus::Complete)));
}

#[test]
fn shared_client_record_fixture_and_invalid_observations() {
    let record: PlayerRecord =
        serde_json::from_str(include_str!("../../../client/golden/player_record.json")).unwrap();
    record.validate_for(Some(record.player_id), None).unwrap();
    assert_eq!(record.total.weapon(WeaponType::Rail).hp_damage, 100);
    assert_eq!(record.total.attacks(), 2);
    let wire = serde_json::to_string(&ServerMessage::Record(record.clone())).unwrap();
    let ServerMessage::Record(round_trip) = serde_json::from_str(&wire).unwrap() else {
        panic!("record shape")
    };
    assert_eq!(round_trip, record);
    for field in [
        "round",
        "tick",
        "map_id",
        "version",
        "ticks_per_second",
        "total",
        "attempt",
        "scope",
        "player_id",
        "session_id",
        "role",
        "status",
        "map_name",
    ] {
        let mut value = serde_json::to_value(&record).unwrap();
        value.as_object_mut().unwrap().remove(field);
        assert!(
            serde_json::from_value::<PlayerRecord>(value).is_err(),
            "missing {field}"
        );
    }
    assert!(record.validate_for(None, None).is_err());
    let mut bad = record.clone();
    bad.status = RecordStatus::Active;
    assert!(bad
        .validate_for(Some(bad.player_id), Some(&record))
        .is_err());
    bad = record.clone();
    bad.total.weapons[0].attacks = u64::MAX;
    assert!(bad.validate_for(Some(bad.player_id), None).is_err());
    bad = record.clone();
    bad.total.weapons[0].damaging_attacks = 1;
    assert!(bad.validate_for(Some(bad.player_id), None).is_err());
    bad = record.clone();
    bad.tick -= 1;
    assert!(bad
        .validate_for(Some(bad.player_id), Some(&record))
        .is_err());
    bad = record.clone();
    bad.session_id = Uuid::new_v4();
    assert!(bad
        .validate_for(Some(bad.player_id), Some(&record))
        .is_err());
}

#[test]
fn dry_triggers_are_latched_separately_from_accepted_attacks() {
    let (mut state, a, _) = arena();
    let player = &mut state.players[0];
    player.inventory =
        crate::inventory::Inventory::new(crate::protocol::EquipmentPolicy::Discovery);
    player.inventory.grant_weapon(WeaponType::Tack);
    player.weapon = WeaponType::Tack;
    for _ in 0..WeaponType::Tack.pickup_rounds() {
        assert!(player.inventory.try_fire(WeaponType::Tack));
    }
    state.set_action(
        a,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    for _ in 0..10 {
        state.tick(0.05);
    }
    let held = state.player_record(a).unwrap();
    assert_eq!(held.total.dry_triggers, 1);
    assert_eq!(held.total.attacks(), 0);
    state.set_action(a, Action::default());
    state.tick(0.05);
    state.set_action(
        a,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert_eq!(state.player_record(a).unwrap().total.dry_triggers, 2);
}

#[test]
fn completed_mission_records_cannot_rewrite_the_attempt_or_run_allowance() {
    use crate::protocol::{CampaignRules, CampaignRunState, CampaignRunStatus, MissionId};
    let mut record: PlayerRecord =
        serde_json::from_str(include_str!("../../../client/golden/player_record.json")).unwrap();
    let run = CampaignRunState {
        id: Uuid::from_u128(3),
        status: CampaignRunStatus::Complete,
        continues: 3,
    };
    record.scope = RecordScope::Mission {
        mission: MissionId::RecallNotice,
        attempt: 1,
        rules: CampaignRules::default(),
        run: Some(run),
    };
    record.validate_for(Some(record.player_id), None).unwrap();
    let mut rewritten = record.clone();
    if let RecordScope::Mission { attempt, run, .. } = &mut rewritten.scope {
        *attempt = 2;
        run.as_mut().unwrap().continues = 2;
    }
    rewritten.attempt = CombatCounts::default();
    rewritten
        .validate_for(Some(record.player_id), None)
        .unwrap();
    assert!(rewritten
        .validate_for(Some(record.player_id), Some(&record))
        .is_err());
    for (id, status, continues, attempt) in [
        (Uuid::nil(), CampaignRunStatus::Playing, 3, 1),
        (run.id, CampaignRunStatus::Playing, 4, 1),
        (run.id, CampaignRunStatus::Playing, 3, 2),
        (run.id, CampaignRunStatus::Continue, 0, 4),
        (run.id, CampaignRunStatus::Failed, 1, 3),
    ] {
        assert!(CampaignRunState {
            id,
            status,
            continues
        }
        .validate_attempt(attempt)
        .is_err());
    }
}

#[test]
fn protected_targets_and_friendlies_never_count_as_damaging_attacks() {
    let (mut state, a, b) = arena();
    state.spawn_shields.insert(b, 10);
    fire(&mut state, a, b);
    state.tick(0.05);
    assert_eq!(
        state
            .player_record(a)
            .unwrap()
            .total
            .weapon(WeaponType::Rail)
            .damaging_attacks,
        0
    );
    state.spawn_shields.clear();
    for player in &mut state.players {
        player.campaign = Some(crate::protocol::CampaignActor::Participant {});
    }
    state.players[0].fire_cooldown = 0;
    state.tick(0.05);
    let attacker = state.player_record(a).unwrap();
    assert_eq!(attacker.total.attacks(), 2);
    assert_eq!(attacker.total.weapon(WeaponType::Rail).damaging_attacks, 0);
    assert_eq!(state.player_record(b).unwrap().total.hp_lost, 0);
}

#[tokio::test]
async fn record_delivery_respects_advertised_client_capability() {
    use std::sync::Arc;
    use tokio::sync::{mpsc, Mutex};
    let (mut state, a, b) = arena();
    state.tick(0.05);
    let record = state.player_record(a).unwrap();
    let (legacy_tx, mut legacy_rx) = mpsc::channel(4);
    let (current_tx, mut current_rx) = mpsc::channel(4);
    let clients = Arc::new(Mutex::new(vec![
        crate::net::ClientSession::new(a, legacy_tx, crate::protocol::CONTINUES_GAMEPLAY_VERSION),
        crate::net::ClientSession::new(b, current_tx, crate::protocol::GAMEPLAY_VERSION),
    ]));
    crate::session::send_unicasts(
        &clients,
        &Default::default(),
        &[
            (Recipient::Client(a), ServerMessage::Record(record.clone())),
            (Recipient::Client(b), ServerMessage::Record(record)),
        ],
    )
    .await;
    assert!(
        legacy_rx.try_recv().is_err(),
        "older controllers must not see new message kinds"
    );
    assert!(matches!(
        current_rx.try_recv(),
        Ok(ServerMessage::Record(_))
    ));
}

#[test]
fn late_join_records_preserve_their_participation_window() {
    let mut state = GameState::new();
    state.start_round();
    for _ in 0..10 {
        state.tick(0.05);
    }
    let id = Uuid::new_v4();
    state.add_player(id, "Late arrival".into(), Role::Human);
    state.tick(0.05);
    let record = state.player_record(id).unwrap();
    assert_eq!(
        (
            record.round_started_at,
            record.entered_at,
            record.total.alive_ticks
        ),
        (0, 10, 1)
    );
    record.validate_for(Some(id), None).unwrap();
    state.end_round("done".into());
    let observer = Uuid::new_v4();
    state.add_player(observer, "Too late".into(), Role::Agent);
    assert!(
        state.player_record(observer).is_none(),
        "joining a finished round is not participation"
    );
}

#[test]
fn records_keep_five_legacy_weapon_slots_until_the_shiv_is_used() {
    use crate::protocol::CombatCounts;
    let mut counts = CombatCounts {
        alive_ticks: 10,
        ..Default::default()
    };
    counts.weapons[WeaponType::Rail.index()].attacks = 2;
    let legacy = serde_json::to_value(&counts).unwrap();
    assert_eq!(legacy["weapons"].as_array().unwrap().len(), 5);
    assert!(legacy.get("secrets").is_none(), "no secret, no field");
    assert_eq!(
        serde_json::from_value::<CombatCounts>(legacy.clone()).unwrap(),
        counts
    );
    counts.weapons[WeaponType::Shiv.index()].attacks = 3;
    counts.secrets = 1;
    counts.validate().unwrap();
    let current = serde_json::to_value(&counts).unwrap();
    assert_eq!(current["weapons"].as_array().unwrap().len(), 6);
    assert_eq!(current["secrets"], 1);
    assert_eq!(
        current["weapons"][4], legacy["weapons"][4],
        "Rail keeps its slot"
    );
    assert_eq!(
        serde_json::from_value::<CombatCounts>(current.clone()).unwrap(),
        counts
    );
    for length in [0, 4, 7] {
        let mut malformed = current.clone();
        let slots = malformed["weapons"].as_array_mut().unwrap();
        let slot = slots[0].clone();
        slots.resize(length, slot);
        assert!(
            serde_json::from_value::<CombatCounts>(malformed).is_err(),
            "{length}"
        );
    }
    let mut malformed = current.clone();
    malformed["weapons"][5]["unexpected"] = true.into();
    assert!(serde_json::from_value::<CombatCounts>(malformed).is_err());
    let mut busy = counts.clone();
    busy.secrets = 11;
    assert!(busy.validate().is_err(), "more secrets than active frames");
    let mut part = counts.clone();
    part.secrets = 2;
    assert!(!counts.contains(&part) && part.contains(&counts));
}

#[test]
fn shared_shiv_record_fixture_round_trips_its_sixth_slot_and_secret() {
    let text = include_str!("../../../client/golden/player_record_shiv.json");
    let record: PlayerRecord = serde_json::from_str(text).unwrap();
    record.validate_for(Some(record.player_id), None).unwrap();
    assert_eq!(record.total.weapon(WeaponType::Shiv).kills, 1);
    assert_eq!(record.total.weapon(WeaponType::Tack).attacks, 2);
    assert_eq!((record.total.secrets, record.attempt.secrets), (1, 1));
    let expected: serde_json::Value = serde_json::from_str(text).unwrap();
    assert_eq!(serde_json::to_value(&record).unwrap(), expected);
}
