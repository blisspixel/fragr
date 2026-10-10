use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, EnemyKind, EnemyPhase, Role};
use crate::session::GameSession;
use serde_json::json;

fn fixture(difficulty: CampaignDifficulty, kind: EnemyKind) -> (GameSession, Uuid) {
    fixture_facing(difficulty, kind, 0.0)
}

fn fixture_facing(
    difficulty: CampaignDifficulty,
    kind: EnemyKind,
    yaw: f32,
) -> (GameSession, Uuid) {
    let mut definition = super::tests::definition();
    definition["encounters"] = json!([{
        "id":"encounter", "regions":[{"min":[-1,0,-7],"max":[1,2,-4]}],
        "enemies":[{"id":"guard", "kind":kind, "feet":[2,0,-3], "yaw":yaw}]
    }]);
    let map = AuthoredMap::read(serde_json::to_vec(&definition).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(67);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    session.state.acknowledge_mission(
        id,
        MissionReady {
            id: crate::protocol::MissionId::RecallNotice,
            attempt: 1,
        },
    );
    (session, id)
}

fn phase(session: &GameSession) -> (EnemyPhase, u64, u64) {
    let guard = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap();
    match guard.campaign.unwrap() {
        CampaignActor::Union {
            phase,
            phase_started,
            phase_ends,
            ..
        } => (phase, phase_started, phase_ends),
        _ => panic!("expected Union guard"),
    }
}

#[test]
fn every_tier_keeps_real_tells_committed_aim_and_retaliation_windows() {
    for kind in [EnemyKind::Clerk, EnemyKind::Sweeper] {
        let mut timings = Vec::new();
        for difficulty in [
            CampaignDifficulty::Assisted,
            CampaignDifficulty::Standard,
            CampaignDifficulty::Severe,
        ] {
            for dodge in [false, true] {
                let (mut session, id) = fixture(difficulty, kind);
                for _ in 0..2 {
                    session.tick_messages(0.05);
                }
                let (current, start, end) = phase(&session);
                assert_eq!(current, EnemyPhase::Windup);
                assert!(end - start >= 10, "every tier preserves a readable tell");
                if dodge {
                    session.state.set_action(
                        id,
                        Action {
                            right: true,
                            yaw: Some(0.0),
                            ..Default::default()
                        },
                    );
                }
                while session.state.tick < end - 1 {
                    session.tick_messages(0.05);
                    assert!(session.state.shot_results.is_empty());
                    assert_eq!(session.state.players[0].hp, 100);
                }
                session.tick_messages(0.05);
                assert_eq!(phase(&session).0, EnemyPhase::Firing);
                assert_eq!(session.state.shot_results.len(), 1);
                let shot = &session.state.shot_results[0];
                if dodge {
                    assert!(shot.target_id.is_none());
                    assert_eq!(session.state.players[0].hp, 100);
                } else {
                    assert_eq!(shot.target_id, Some(id));
                    assert_eq!(shot.damage, if kind == EnemyKind::Clerk { 20 } else { 25 });
                }
                let mut shots = 1;
                for _ in 0..20 {
                    session.tick_messages(0.05);
                    shots += session.state.shot_results.len();
                    if phase(&session).0 == EnemyPhase::Recovery {
                        break;
                    }
                }
                let (current, recovery_start, recovery_end) = phase(&session);
                assert_eq!(current, EnemyPhase::Recovery);
                assert_eq!(shots, if kind == EnemyKind::Clerk { 1 } else { 3 });
                if dodge {
                    assert_eq!(session.state.players[0].hp, 100);
                } else {
                    timings.push((end - start, recovery_end - recovery_start));
                }
            }
        }
        assert!(timings
            .windows(2)
            .all(|pair| pair[0].0 > pair[1].0 && pair[0].1 > pair[1].1));
        assert_eq!(
            timings[1],
            if kind == EnemyKind::Clerk {
                (12, 20)
            } else {
                (14, 26)
            }
        );
    }
}

#[test]
fn difficulty_is_fixed_before_admission_and_retained_across_party_reset() {
    let mut arcade = GameState::new();
    assert!(arcade
        .set_campaign_difficulty(CampaignDifficulty::Severe)
        .is_err());
    let (mut session, id) = fixture(CampaignDifficulty::Severe, EnemyKind::Clerk);
    assert!(session
        .state
        .set_campaign_difficulty(CampaignDifficulty::Assisted)
        .is_err());
    session.tick_messages(0.05);
    session.state.players[0].hp = 0;
    session.tick_messages(0.05);
    let state = session.state.mission_state().unwrap();
    assert_eq!(state.attempt, 2);
    assert_eq!(state.rules, CampaignRules::new(CampaignDifficulty::Severe));
    session.state.remove_player(id);
    assert!(session
        .state
        .set_campaign_difficulty(CampaignDifficulty::Standard)
        .is_err());
}

#[test]
fn mission_rules_reject_unknown_revisions_missing_fields_and_midrun_changes() {
    let (session, _) = fixture(CampaignDifficulty::Assisted, EnemyKind::Clerk);
    let state = session.state.mission_state().unwrap();
    // Historical rules require save migration; live state uses the current revision.
    for revision in [0, 1, 2, 3, crate::protocol::CAMPAIGN_RULES_REVISION + 1] {
        let mut invalid = state.clone();
        invalid.rules.revision = revision;
        assert!(invalid.validate(0).is_err());
    }
    for bad in [
        json!({"difficulty":"nightmare","revision":1}),
        json!({"difficulty":"standard"}),
        json!({"difficulty":"standard","revision":1,"adaptive":true}),
    ] {
        assert!(serde_json::from_value::<CampaignRules>(bad).is_err());
    }
    let mut observer = MissionClient::default();
    let map = &session.state.map;
    observer
        .replace_map(
            map.mission(),
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    observer.observe(0, state.clone()).unwrap();
    observer
        .replace_map(
            map.mission(),
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut invalid = state;
    invalid.rules = CampaignRules::new(CampaignDifficulty::Severe);
    assert!(
        observer.observe(0, invalid).is_err(),
        "geometry refresh cannot change a run's rules"
    );
}

#[test]
fn heavy_and_turret_tells_precede_damage_by_the_documented_time_on_every_tier() {
    use crate::encounters::enemy::attack_timing;
    use crate::protocol::WeaponType;
    // Facing the visitor, so the turret's tracking settles on its first look.
    let facing = (-3.0f32).atan2(-2.0).rem_euclid(std::f32::consts::TAU);
    for (kind, weapon, burst) in [
        (EnemyKind::HeavySweeper, WeaponType::Flechette, 4),
        (EnemyKind::Turret, WeaponType::Rail, 1),
        (EnemyKind::RangedSweeper, WeaponType::Sniper, 1),
    ] {
        let mut timings = Vec::new();
        for difficulty in [
            CampaignDifficulty::Assisted,
            CampaignDifficulty::Standard,
            CampaignDifficulty::Severe,
        ] {
            let (windup, recovery) = attack_timing(kind, difficulty);
            assert!(windup >= 20, "a heavy tell stays at least one second");
            for dodge in [false, true] {
                let (mut session, id) = fixture_facing(difficulty, kind, facing);
                session.state.players[0].hp = 500;
                session.tick_messages(0.05);
                for _ in 0..8 {
                    if phase(&session).0 == EnemyPhase::Windup {
                        break;
                    }
                    session.tick_messages(0.05);
                    assert!(session.state.shot_results.is_empty());
                }
                let (current, start, end) = phase(&session);
                assert_eq!(current, EnemyPhase::Windup);
                assert_eq!(end - start, windup);
                if dodge {
                    session.state.set_action(
                        id,
                        Action {
                            right: true,
                            yaw: Some(0.0),
                            ..Default::default()
                        },
                    );
                }
                while session.state.tick < end - 1 {
                    session.tick_messages(0.05);
                    assert!(session.state.shot_results.is_empty());
                    assert_eq!(session.state.players[0].hp, 500);
                }
                session.tick_messages(0.05);
                assert_eq!(phase(&session).0, EnemyPhase::Firing);
                assert_eq!(session.state.shot_results.len(), 1);
                let shot = &session.state.shot_results[0];
                assert_eq!(shot.damage > 0, !dodge);
                if !dodge {
                    assert_eq!(shot.damage, weapon.damage());
                    assert_eq!(shot.target_id, Some(id));
                }
                let mut shots = 1;
                for _ in 0..20 {
                    if phase(&session).0 == EnemyPhase::Recovery {
                        break;
                    }
                    session.tick_messages(0.05);
                    shots += session.state.shot_results.len();
                }
                let (current, recovery_start, recovery_end) = phase(&session);
                assert_eq!(current, EnemyPhase::Recovery);
                assert_eq!(shots, burst);
                assert_eq!(recovery_end - recovery_start, recovery);
                if dodge {
                    assert_eq!(session.state.players[0].hp, 500);
                } else {
                    timings.push((windup, recovery));
                }
            }
        }
        assert!(timings
            .windows(2)
            .all(|pair| pair[0].0 > pair[1].0 && pair[0].1 > pair[1].1));
    }
}

#[test]
fn difficulty_supply_grant_scales_recovery_and_keeps_secrets_explosives_and_standard() {
    use crate::protocol::{CampaignSupply, WeaponType};

    let tiers = [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ];
    for difficulty in tiers {
        assert_eq!(
            difficulty.supply_grant(CampaignSupply::Ammunition, 10, true),
            10,
            "a secret stays authored"
        );
        assert_eq!(difficulty.supply_grant(CampaignSupply::Health, 0, false), 0);
        assert_eq!(
            difficulty.supply_grant(CampaignSupply::Armor, -4, false),
            -4
        );
        assert_eq!(
            difficulty.supply_grant(CampaignSupply::Explosive, 2, false),
            2
        );
        assert_eq!(
            difficulty.supply_grant(CampaignSupply::Ammunition, 3, false),
            match difficulty {
                CampaignDifficulty::Assisted => 5,
                CampaignDifficulty::Standard => 3,
                CampaignDifficulty::Severe => 2,
            }
        );
    }
    assert_eq!(
        CampaignDifficulty::Assisted.supply_grant(CampaignSupply::Ammunition, 10, false),
        15
    );
    assert_eq!(
        CampaignDifficulty::Standard.supply_grant(CampaignSupply::Ammunition, 10, false),
        10
    );
    assert_eq!(
        CampaignDifficulty::Severe.supply_grant(CampaignSupply::Ammunition, 10, false),
        6
    );
    assert_eq!(
        CampaignDifficulty::Assisted.supply_grant(CampaignSupply::Health, 10, false),
        15
    );
    assert_eq!(
        CampaignDifficulty::Severe.supply_grant(CampaignSupply::Health, 10, false),
        6
    );
    assert_eq!(
        CampaignDifficulty::Assisted.supply_grant(CampaignSupply::Armor, 25, false),
        38
    );
    assert_eq!(
        CampaignDifficulty::Severe.supply_grant(CampaignSupply::Armor, 25, false),
        16
    );
    assert_eq!(
        CampaignDifficulty::Severe.supply_grant(CampaignSupply::Ammunition, 1, false),
        1
    );
    assert_eq!(
        CampaignDifficulty::Assisted.supply_grant(CampaignSupply::Health, 1, false),
        2
    );
    assert_eq!(
        CampaignDifficulty::Severe.supply_grant(CampaignSupply::Health, 1, false),
        1
    );
    let tack = i32::from(WeaponType::Tack.pickup_rounds());
    assert_eq!(tack, 50);
    assert_eq!(
        CampaignDifficulty::Assisted.supply_grant(CampaignSupply::Ammunition, tack, false),
        75
    );
    assert_eq!(
        CampaignDifficulty::Standard.supply_grant(CampaignSupply::Ammunition, tack, false),
        50
    );
    assert_eq!(
        CampaignDifficulty::Severe.supply_grant(CampaignSupply::Ammunition, tack, false),
        33
    );
}

fn supply_state(difficulty: CampaignDifficulty) -> (GameState, Uuid) {
    let mut definition = super::tests::definition();
    definition["supplies"] = json!([
        {"id":"rounds","feet":[0,0,-6],"claim":"contested","grant":{"kind":"ammo","pool":"bullets","amount":10}},
        {"id":"secret_rounds","feet":[4,0,-6],"claim":"contested","secret":true,"grant":{"kind":"ammo","pool":"bullets","amount":10}},
        {"id":"charges","feet":[-4,0,-6],"claim":"contested","grant":{"kind":"grenade","amount":2}},
        {"id":"sidearm","feet":[0,0,-2],"claim":"personal","grant":{"kind":"weapon","weapon":"tack"}},
        {"id":"medkit","feet":[4,0,-2],"claim":"contested","grant":{"kind":"health","amount":10}},
        {"id":"plate","feet":[-6,0,-2],"claim":"contested","grant":{"kind":"armor","amount":25}}
    ]);
    let map = AuthoredMap::read(serde_json::to_vec(&definition).unwrap().as_slice()).unwrap();
    let mut state = GameState::with_authored_map(map);
    state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(91);
    state.add_player(id, "Visitor".into(), Role::Human);
    assert!(state.acknowledge_mission(
        id,
        MissionReady {
            id: crate::protocol::MissionId::RecallNotice,
            attempt: 1,
        },
    ));
    (state, id)
}

fn bullets(state: &GameState, id: Uuid) -> u16 {
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    player
        .inventory
        .state(id, player.weapon, state.tick)
        .unwrap()
        .ammo(crate::protocol::AmmoPool::Bullets)
}

fn claim(state: &mut GameState, id: Uuid, feet: [f32; 3]) -> crate::protocol::GameEvent {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = feet[0];
    player.z = feet[2];
    player.y = crate::sim::PLAYER_FLOOR_Y + feet[1];
    state.tick(0.05);
    state
        .take_events()
        .into_iter()
        .find(|event| {
            matches!(
                event,
                crate::protocol::GameEvent::Pickup { pickup_id, .. }
                    if pickup_id == "rounds"
                        || pickup_id == "secret_rounds"
                        || pickup_id == "charges"
                        || pickup_id == "sidearm"
                        || pickup_id == "medkit"
                        || pickup_id == "plate"
            )
        })
        .expect("pickup event")
}

#[test]
fn difficulty_campaign_claim_scales_ordinary_ammo_and_not_secrets() {
    use crate::protocol::GameEvent;

    for (difficulty, ammo, health, armor) in [
        (CampaignDifficulty::Assisted, 15, 15, 38),
        (CampaignDifficulty::Standard, 10, 10, 25),
        (CampaignDifficulty::Severe, 6, 6, 16),
    ] {
        let (mut state, id) = supply_state(difficulty);
        let before = bullets(&state, id);
        let event = claim(&mut state, id, [0.0, 0.0, -6.0]);
        assert_eq!(bullets(&state, id) - before, ammo);
        assert!(matches!(
            event,
            GameEvent::Pickup {
                amount: Some(gained),
                secret: false,
                ..
            } if gained == i32::from(ammo)
        ));

        let before = bullets(&state, id);
        let event = claim(&mut state, id, [4.0, 0.0, -6.0]);
        assert_eq!(
            bullets(&state, id) - before,
            10,
            "secret ammo stays authored"
        );
        assert!(matches!(
            event,
            GameEvent::Pickup {
                amount: Some(10),
                secret: true,
                ..
            }
        ));

        let event = claim(&mut state, id, [-4.0, 0.0, -6.0]);
        assert_eq!(
            state
                .players
                .iter()
                .find(|p| p.id == id)
                .unwrap()
                .inventory
                .grenades(),
            2
        );
        assert!(matches!(
            event,
            GameEvent::Pickup {
                amount: Some(2),
                ..
            }
        ));

        let before = bullets(&state, id);
        let rounds = state.campaign_supply_amount(
            crate::protocol::CampaignSupply::Ammunition,
            i32::from(crate::protocol::WeaponType::Tack.pickup_rounds()),
            false,
        );
        claim(&mut state, id, [0.0, 0.0, -2.0]);
        assert_eq!(i32::from(bullets(&state, id) - before), rounds);
        assert!(state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .inventory
            .owns(crate::protocol::WeaponType::Tack));

        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.hp = 50;
        let event = claim(&mut state, id, [4.0, 0.0, -2.0]);
        let hp = state.players.iter().find(|p| p.id == id).unwrap().hp;
        let gained = match event {
            GameEvent::Pickup {
                amount: Some(gained),
                ..
            } => gained,
            other => panic!("expected health pickup, got {other:?}"),
        };
        assert_eq!(gained, health);
        assert_eq!(hp, 50 + health);
        assert!(hp <= 100);

        let before = state.players.iter().find(|p| p.id == id).unwrap().armor;
        let event = claim(&mut state, id, [-6.0, 0.0, -2.0]);
        let armor_now = state.players.iter().find(|p| p.id == id).unwrap().armor;
        assert_eq!(armor_now - before, armor);
        assert!(matches!(
            event,
            GameEvent::Pickup { amount: Some(gained), .. } if gained == armor
        ));
    }

    let (mut state, id) = supply_state(CampaignDifficulty::Assisted);
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.hp = 95;
    let event = claim(&mut state, id, [4.0, 0.0, -2.0]);
    let hp = state.players.iter().find(|p| p.id == id).unwrap().hp;
    assert_eq!(hp, 100);
    assert!(matches!(
        event,
        GameEvent::Pickup {
            amount: Some(5),
            ..
        }
    ));
}

#[test]
fn difficulty_arcade_claim_keeps_the_authored_amount() {
    use crate::protocol::{GameEvent, Role};

    let mut state = GameState::new();
    assert!(state.campaign_difficulty().is_none());
    state.start_round();
    let id = Uuid::new_v4();
    state.add_player(id, "Rusher".into(), Role::Human);
    let (x, z, floor) = state
        .pickups
        .iter()
        .find(|pad| pad.id == "pad_health_n")
        .map(|pad| (pad.x, pad.z, pad.floor))
        .unwrap();
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.x = x;
    player.z = z;
    player.y = crate::sim::PLAYER_FLOOR_Y + floor;
    player.hp = 40;
    state.tick(0.05);
    let player = state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.hp, 80);
    assert!(state.take_events().into_iter().any(|event| matches!(
        event,
        GameEvent::Pickup {
            amount: Some(40),
            pickup_id,
            ..
        } if pickup_id == "pad_health_n"
    )));
}
