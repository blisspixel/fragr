//! Declared imperfect-aim matrix on the committed mission, with real enemy
//! decisions, finite ammunition and ordinary human reload input.
use super::*;
use crate::protocol::{CampaignDifficulty, CampaignRunStatus, MissionContinue, MissionPhase};

fn ordinary_route(run: &mut Walkthrough, bypass: bool) {
    run.walk([0., 0., -26.]);
    assert_eq!(run.session.state.players[0].weapon, WeaponType::Tack);
    assert!(run.first_threat.is_none());
    if bypass {
        for point in [
            [-8., 0., -18.],
            [-17., 0., -18.],
            [-17., 0., -14.],
            [-17., 3., 8.],
        ] {
            run.walk(point);
        }
    } else {
        run.walk([0., 0., -10.]);
        for _ in 0..600 {
            if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
                break;
            }
            run.step([0., 0., -10.]);
        }
        for point in [[6., 0., -9.], [8., 0., -8.], [8., 3., 9.]] {
            run.walk(point);
        }
    }
    for _ in 0..600 {
        if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
            break;
        }
        let p = &run.session.state.players[0];
        run.step([p.x, p.y - PLAYER_FLOOR_Y, p.z]);
    }
    assert_eq!(run.intake.intersection(&run.defeated).count(), 3);
    assert_eq!(run.session.state.players[0].weapon, WeaponType::Flechette);
    for point in [[-19., 3., 9.], [-15.5, 3., 17.5], [-19., 3., 23.]] {
        run.walk(point);
    }
    if bypass {
        for point in [
            [-21., 3., 27.],
            [-16., 3., 26.],
            [-18., 3., 31.],
            [-18., 3., 38.],
        ] {
            run.walk(point);
        }
    } else {
        for point in [
            [-25., 3., 18.],
            [-25.5, 3., 23.],
            [-32., 3., 17.],
            [-41.5, 3., 17.],
            [-41.5, 3., 14.5],
            [-37., 3., 27.],
            [-37., 3., 31.],
            [-28., 3., 32.],
            [-41.5, 3., 40.],
        ] {
            run.walk(point);
        }
    }
    for point in [
        [-22., 3., 41.],
        [-11., 3., 36.],
        [-3., 3., 42.],
        [-10.5, 3., 42.],
        [-3., 3., 29.],
        [-3., 3., 20.],
    ] {
        run.walk(point);
    }
    run.use_control(true);
    run.walk([7., 3., 23.]);
    run.use_control(false);
}

#[test]
fn m01_all_tiers_both_ordinary_routes_depart_with_periodic_resolved_misses() {
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        for role in [Role::Human, Role::Agent] {
            for bypass in [false, true] {
                let mut run =
                    Walkthrough::with_rules(role, true, difficulty, role == Role::Human, 4);
                ordinary_route(&mut run, bypass);
                run.assert_optional_caches_unclaimed();
                assert_eq!(
                    run.intentional_misses,
                    run.shots / 4,
                    "miss rate must use actual resolved attacks"
                );
                assert!(run.intentional_misses >= 20);
                let state = run.session.state.mission_state().unwrap();
                assert_eq!(state.phase, MissionPhase::Departed);
                assert_eq!(state.rules.difficulty, difficulty);
                assert_eq!(state.run.unwrap().status, CampaignRunStatus::Complete);
                let record = run.session.state.player_record(run.id).unwrap();
                assert_eq!(record.total.deaths, 0);
                assert_eq!(record.total.secrets, 0);
                let player = &run.session.state.players[0];
                let gear = player
                    .inventory
                    .state(run.id, player.weapon, run.session.state.tick)
                    .unwrap();
                assert!(
                    gear.ammo(AmmoPool::Bullets) > 0,
                    "no secret or unlimited reserve may be required"
                );
                assert_eq!(!gear.loaded.is_empty(), role == Role::Human);
                if role == Role::Human {
                    assert!(run.reload_presses > 0);
                }
                for name in [
                    "stacks_clerk",
                    "archive_clerk",
                    "stacks_sweeper",
                    "archive_sweeper",
                ] {
                    let guard = run.session.state.players.iter().find(|p| p.name == name);
                    if bypass {
                        assert!(
                            guard.is_some_and(|p| p.hp > 0),
                            "bypass must leave {name} alive"
                        );
                    } else {
                        assert!(
                            guard.is_none_or(|p| p.hp <= 0),
                            "public route must fight {name}"
                        );
                    }
                }
                if bypass {
                    for stock in ["stacks_bullets", "stacks_armor", "stacks_medkit"] {
                        assert!(
                            run.session
                                .state
                                .pickups
                                .iter()
                                .find(|p| p.id == stock)
                                .unwrap()
                                .available
                        );
                    }
                }
                assert!(run.defeated.len() >= if bypass { 16 } else { 19 });
                eprintln!("M01 miss matrix: tier={difficulty:?} role={role:?} bypass={bypass} ticks={} attacks={} deliberate_misses={} defeats={} enemy_attacks={} reload_presses={} hp={} armor={} hp_lost={} armor_lost={} bullets={} deaths={}",run.session.state.tick,run.shots,run.intentional_misses,run.defeated.len(),run.enemy_shots,run.reload_presses,player.hp,player.armor,record.total.hp_lost,record.total.armor_lost,gear.ammo(AmmoPool::Bullets),record.total.deaths);
            }
        }
    }
}

/// Use ordinary forward input into the taught Clerk's room, then stay exposed.
/// The participant spends a real round overhead and lets the guard kill them.
fn enemy_death(run: &mut Walkthrough) {
    run.walk([0., 0., -26.]);
    let before = run
        .session
        .state
        .player_record(run.id)
        .unwrap()
        .total
        .deaths;
    let mut spent = false;
    let mut killed = false;
    for _ in 0..1800 {
        let p = run
            .session
            .state
            .players
            .iter()
            .find(|p| p.id == run.id)
            .unwrap();
        if p.hp <= 0 {
            break;
        }
        let approach = p.z < -21.;
        run.session.state.set_action(
            run.id,
            Action {
                forward: approach,
                look_at: Some(if approach {
                    LookAt {
                        x: Some(0.),
                        y: Some(1.6),
                        z: Some(-21.),
                        player_id: None,
                    }
                } else {
                    LookAt {
                        x: Some(p.x),
                        y: Some(12.),
                        z: Some(p.z),
                        player_id: None,
                    }
                }),
                fire: !approach && !spent,
                ..Default::default()
            },
        );
        run.session.tick_messages(0.05);
        for shot in &run.session.state.shot_results {
            if shot.shooter_id == run.id {
                assert!(!shot.hit && shot.damage == 0);
                spent = true;
            } else if shot.target_id == Some(run.id) && shot.killed {
                killed = true;
            }
        }
    }
    assert!(spent, "death attempt must really spend found ammunition");
    assert!(killed, "guard must own the resolved killing shot");
    assert_eq!(
        run.session
            .state
            .player_record(run.id)
            .unwrap()
            .total
            .deaths,
        before + 1
    );
}

#[test]
fn m01_all_tiers_real_enemy_deaths_restore_entry_then_exhaust_three_continues() {
    for difficulty in [
        CampaignDifficulty::Assisted,
        CampaignDifficulty::Standard,
        CampaignDifficulty::Severe,
    ] {
        let mut run = Walkthrough::with_rules(Role::Human, true, difficulty, true, 0);
        let entry_map = run.session.state.map.clone();
        let p = &run.session.state.players[0];
        let entry_body = (p.x, p.y - PLAYER_FLOOR_Y, p.z, p.hp, p.armor);
        let entry_facing = (p.yaw, p.pitch);
        let entry_gear = p
            .inventory
            .state(run.id, p.weapon, run.session.state.tick)
            .unwrap();
        for spent in 0..=3 {
            let before = run.session.state.mission_state().unwrap();
            let request = MissionContinue {
                id: before.id,
                run_id: before.run.unwrap().id,
                attempt: before.attempt,
            };
            enemy_death(&mut run);
            let dead = run.session.state.mission_state().unwrap();
            assert_eq!(dead.rules.difficulty, difficulty);
            assert_eq!(dead.run.as_ref().unwrap().continues, 3 - spent);
            assert_eq!(
                dead.run.unwrap().status,
                if spent == 3 {
                    CampaignRunStatus::Failed
                } else {
                    CampaignRunStatus::Continue
                }
            );
            let tick = run.session.state.tick;
            let revision = run.session.state.players[0].inventory.revision();
            assert_eq!(
                run.session.state.continue_mission(run.id, request),
                spent < 3
            );
            assert!(
                !run.session.state.continue_mission(run.id, request),
                "duplicate or exhausted request cannot spend"
            );
            assert_eq!(run.session.state.tick, tick);
            if spent < 3 {
                let p = &run.session.state.players[0];
                assert_eq!((p.x, p.y - PLAYER_FLOOR_Y, p.z, p.hp, p.armor), entry_body);
                assert_eq!(p.weapon, WeaponType::Fists);
                assert_eq!((p.yaw, p.pitch), entry_facing);
                assert!(!p.inventory.owns(WeaponType::Tack));
                assert!(p.inventory.revision() > revision);
                assert!(p.inventory.armed());
                let gear = p
                    .inventory
                    .state(run.id, p.weapon, run.session.state.tick)
                    .unwrap();
                assert_eq!(gear.weapons, entry_gear.weapons);
                assert_eq!(gear.ammo, entry_gear.ammo);
                assert_eq!(gear.loaded, entry_gear.loaded);
                assert_eq!(gear.personal_claims, entry_gear.personal_claims);
                assert_eq!(run.session.state.map, entry_map);
                assert!(run.session.state.pickups.iter().all(|p| p.available));
                let restored = run.session.state.mission_state().unwrap();
                assert_eq!(restored.phase, MissionPhase::FindTransfer);
                assert_eq!(restored.attempt, u32::from(spent) + 2);
                assert_eq!(restored.run.unwrap().continues, 2 - spent);
                run.navigator.clear();
            }
        }
        run.session.state.set_action(run.id, Action::default());
        for _ in 0..100 {
            run.session.tick_messages(0.05);
        }
        assert!(run.session.state.players[0].hp <= 0);
        assert_eq!(
            run.session
                .state
                .player_record(run.id)
                .unwrap()
                .total
                .deaths,
            4
        );
        assert_eq!(
            run.session
                .state
                .mission_state()
                .unwrap()
                .run
                .unwrap()
                .status,
            CampaignRunStatus::Failed
        );
        eprintln!("M01 real recovery: tier={difficulty:?} enemy_deaths=4 continues_spent=3 duplicate_rejected=true entry_restored=true exhausted=true ticks={}",run.session.state.tick);
    }
}
