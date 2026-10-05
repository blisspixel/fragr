use crate::maps::{AuthoredSource, EnemyPlacement};
use crate::protocol::{
    Action, CampaignActor, EnemyKind, EquipmentPolicy, GameEvent, GameMode, MissionId,
    MissionReady, Role, ShotImpact, ShotResult, Team, WeaponType,
};
use crate::rules::RuleSet;
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

const GUNS: [WeaponType; 6] = [
    WeaponType::Tack,
    WeaponType::Flechette,
    WeaponType::Scatter,
    WeaponType::Rail,
    WeaponType::Sniper,
    WeaponType::Repeater,
];

fn place(state: &mut GameState, id: Uuid, feet: [f32; 3]) {
    let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [player.x, player.y, player.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    player.vy = 0.0;
    player.yaw = 0.0;
    player.pitch = 0.0;
    player.clear_input();
}

fn hp(state: &GameState, id: Uuid) -> i32 {
    state.players.iter().find(|p| p.id == id).unwrap().hp
}

fn lane(roles: [Role; 3]) -> (GameState, Uuid, Uuid, Uuid) {
    let mut state = GameState::new();
    state.seed(42);
    state.start_round();
    let ids = [
        Uuid::from_u128(101),
        Uuid::from_u128(102),
        Uuid::from_u128(103),
    ];
    for (index, (&id, role)) in ids.iter().zip(roles).enumerate() {
        state.add_player(id, format!("lane_{index}"), role);
        place(&mut state, id, [-1.0 + index as f32 * 1.2, 0.0, 0.0]);
    }
    state.spawn_shields.clear();
    (state, ids[0], ids[1], ids[2])
}

fn fire(state: &mut GameState, shooter: Uuid, weapon: WeaponType) -> Vec<ShotResult> {
    fire_at(state, shooter, weapon, 0.0, 0.0)
}

fn fire_at(
    state: &mut GameState,
    shooter: Uuid,
    weapon: WeaponType,
    yaw: f32,
    pitch: f32,
) -> Vec<ShotResult> {
    let player = state.players.iter_mut().find(|p| p.id == shooter).unwrap();
    player.inventory = crate::inventory::Inventory::new(EquipmentPolicy::Discovery);
    player.inventory.grant_weapon(weapon);
    player.weapon = weapon;
    player.fire_cooldown = 0;
    let companion = player.is_campaign_companion();
    let action = Action {
        fire: true,
        yaw: Some(yaw),
        pitch: Some(pitch),
        ..Default::default()
    };
    if companion {
        state.set_companion_action(shooter, action);
    } else {
        state.set_action(shooter, action);
    }
    // Zero dt holds diagnostic feet fixed, but advances real ticks, trigger
    // ownership and Repeater spin-up through the ordinary combat owner.
    for _ in 0..24 {
        state.tick(0.0);
        let shots: Vec<_> = state
            .shot_results
            .iter()
            .filter(|shot| shot.shooter_id == shooter)
            .cloned()
            .collect();
        if !shots.is_empty() {
            return shots;
        }
    }
    panic!("ordinary {weapon:?} fire produced no resolved shot");
}

fn assert_nearest(shots: &[ShotResult], near: Uuid, far: Uuid) {
    assert!(!shots.is_empty());
    for shot in shots {
        assert_eq!(
            shot.target_id,
            Some(near),
            "nearest living body must stop the ray"
        );
        assert_ne!(shot.target_id, Some(far));
        let trace = shot.trace.as_ref().unwrap();
        assert!(matches!(trace.impact, ShotImpact::Fighter { .. }));
        assert!(trace.end[0] < 0.3, "trace passed beyond the near body");
        for pellet in &trace.pellets {
            assert!(matches!(pellet.impact, ShotImpact::Fighter { .. }));
            assert!(pellet.end[0] < 0.3, "Scatter pellet penetrated the blocker");
        }
    }
}

#[test]
fn every_gun_stops_on_mixed_role_teammates_independent_of_friendly_fire() {
    for roles in [
        [Role::Human, Role::Agent, Role::Human],
        [Role::Agent, Role::Human, Role::Agent],
    ] {
        for friendly_fire in [false, true] {
            for weapon in GUNS {
                let (mut state, shooter, near, far) = lane(roles);
                state.config.rules = RuleSet::new(GameMode::Tdm, &[], friendly_fire).unwrap();
                for p in &mut state.players {
                    p.team = Some(if p.id == far {
                        Team::Coalition
                    } else {
                        Team::Union
                    });
                }
                state.players.swap(1, 2);
                let shots = fire(&mut state, shooter, weapon);
                assert_nearest(&shots, near, far);
                assert_eq!(hp(&state, far), 100);
                assert_eq!(hp(&state, near) < 100, friendly_fire);
                assert!(shots.iter().all(|shot| (shot.damage > 0) == friendly_fire));
            }
        }
    }
}

#[test]
fn shielded_living_body_stops_every_gun_without_damage_or_hit_events() {
    for weapon in GUNS {
        let (mut state, shooter, near, far) = lane([Role::Agent, Role::Human, Role::Agent]);
        state.spawn_shields.insert(near, 40);
        state.players.swap(1, 2);
        let shots = fire(&mut state, shooter, weapon);
        assert_nearest(&shots, near, far);
        assert_eq!(hp(&state, near), 100);
        assert_eq!(hp(&state, far), 100);
        assert!(shots.iter().all(|shot| shot.damage == 0 && !shot.killed));
        assert!(!state
            .events
            .iter()
            .any(|event| matches!(event, GameEvent::Hit { .. })));
    }
}

#[test]
fn actual_zero_spread_weapon_includes_its_exact_range_endpoint() {
    let (mut state, shooter, near, far) = lane([Role::Human, Role::Agent, Role::Human]);
    state.remove_player(far);
    place(&mut state, shooter, [0.0, 0.0, 0.0]);
    place(
        &mut state,
        near,
        [
            WeaponType::Shiv.range_units() + crate::movement::RADIUS,
            0.0,
            0.0,
        ],
    );
    let shots = fire(&mut state, shooter, WeaponType::Shiv);
    assert_eq!(shots.len(), 1);
    assert_eq!(shots[0].target_id, Some(near));
    assert!(shots[0].damage > 0);
    let trace = shots[0].trace.as_ref().unwrap();
    assert_eq!(trace.end[0], WeaponType::Shiv.range_units());
    assert!(matches!(trace.impact, ShotImpact::Fighter { .. }));
    assert!(hp(&state, near) > 0);

    place(&mut state, near, [2.71, 0.0, 0.0]);
    let outside = fire(&mut state, shooter, WeaponType::Shiv);
    assert_eq!(outside[0].target_id, None);
    assert_eq!(outside[0].damage, 0);
    assert!(matches!(
        outside[0].trace.as_ref().unwrap().impact,
        ShotImpact::Range
    ));
}

fn companion_lane(companion_shoots: bool) -> (GameState, Uuid, Uuid, Uuid) {
    let mut state = GameState::new();
    state.start_round();
    state.seed(42);
    let participant = Uuid::from_u128(201);
    state.add_player(participant, "participant".into(), Role::Human);
    state.players[0].campaign = Some(CampaignActor::Participant {});
    let companion = state
        .spawn_campaign_companion([0.2, 0.0, 0.0], false)
        .unwrap();
    let enemy = state.spawn_campaign_enemy(&EnemyPlacement {
        id: "target_clerk".into(),
        kind: EnemyKind::Clerk,
        feet: [1.4, 0.0, 0.0],
        yaw: 0.0,
        seated: false,
        hover: None,
    });
    let (shooter, near) = if companion_shoots {
        (companion, participant)
    } else {
        (participant, companion)
    };
    place(&mut state, shooter, [-1.0, 0.0, 0.0]);
    place(&mut state, near, [0.2, 0.0, 0.0]);
    state.spawn_shields.clear();
    (state, shooter, near, enemy)
}

#[test]
fn companion_and_participant_are_opaque_without_friendly_damage() {
    for companion_shoots in [false, true] {
        for weapon in GUNS {
            let (mut state, shooter, near, far) = companion_lane(companion_shoots);
            let before = [hp(&state, near), hp(&state, far)];
            let shots = fire(&mut state, shooter, weapon);
            assert_nearest(&shots, near, far);
            assert_eq!([hp(&state, near), hp(&state, far)], before);
            assert!(shots.iter().all(|shot| shot.damage == 0 && !shot.killed));
        }
    }
}

#[test]
fn union_fire_stops_at_immune_companion_in_front_of_participant() {
    for weapon in GUNS {
        let (mut state, participant, companion, enemy) = companion_lane(false);
        place(&mut state, enemy, [-1.0, 0.0, 0.0]);
        place(&mut state, participant, [1.4, 0.0, 0.0]);
        let before = [hp(&state, companion), hp(&state, participant)];
        let shots = fire(&mut state, enemy, weapon);
        assert_nearest(&shots, companion, participant);
        assert_eq!([hp(&state, companion), hp(&state, participant)], before);
        assert!(shots.iter().all(|shot| shot.damage == 0 && !shot.killed));
    }
}

#[test]
fn real_jammer_pulse_stops_at_companion_or_shielded_body() {
    for protected in ["companion", "shield"] {
        let (mut state, participant, companion, _) = companion_lane(false);
        state.players.retain(|p| !p.is_campaign_enemy());
        let jammer = state.spawn_campaign_enemy(&EnemyPlacement {
            id: "pulse_source".into(),
            kind: EnemyKind::Jammer,
            feet: [-1.0, 0.0, 0.0],
            yaw: 0.0,
            seated: false,
            hover: None,
        });
        place(&mut state, participant, [1.4, 0.0, 0.0]);
        let near = if protected == "shield" {
            state.remove_player(companion);
            let near = Uuid::from_u128(401);
            state.add_player(near, "shielded".into(), Role::Agent);
            place(&mut state, near, [0.2, 0.0, 0.0]);
            state.spawn_shields.insert(near, 40);
            near
        } else {
            companion
        };
        let before = [hp(&state, near), hp(&state, participant)];
        state.set_action(
            jammer,
            Action {
                fire: true,
                yaw: Some(0.0),
                pitch: Some(0.0),
                ..Default::default()
            },
        );
        state.tick(0.05);
        assert_eq!(
            state.snapshot().projectiles.len(),
            1,
            "ordinary Jammer fire launches one pulse"
        );
        state.set_action(jammer, Action::default());
        for _ in 0..20 {
            state.tick(0.05);
            if state.snapshot().projectiles.is_empty() {
                break;
            }
        }
        assert!(
            state.snapshot().projectiles.is_empty(),
            "pulse must stop before reaching the farther participant"
        );
        assert_eq!([hp(&state, near), hp(&state, participant)], before);
        assert!(!state
            .events
            .iter()
            .any(|event| matches!(event, GameEvent::Hit { .. })));
    }
}

#[test]
fn dead_absent_respawning_detached_and_eliminated_bodies_do_not_occlude() {
    for excluded in ["dead", "absent", "respawning", "detached", "eliminated"] {
        let (mut state, shooter, near, far) = lane([Role::Human, Role::Agent, Role::Human]);
        match excluded {
            "absent" => state.remove_player(near),
            _ => {
                let p = state.players.iter_mut().find(|p| p.id == near).unwrap();
                match excluded {
                    "dead" => p.hp = 0,
                    "respawning" => p.respawn_timer = Some(100),
                    "detached" => p.detached = true,
                    "eliminated" => p.eliminated = true,
                    _ => unreachable!(),
                }
            }
        }
        let shots = fire(&mut state, shooter, WeaponType::Rail);
        assert!(shots.iter().all(|shot| shot.target_id == Some(far)));
        assert!(hp(&state, far) < 100, "excluded={excluded}");
    }
}

#[test]
fn actual_patient_stops_ray_without_invented_target_or_health_facts() {
    for weapon in GUNS {
        let (mut state, shooter, far, patient) = patient_lane();
        let feet = [patient.from.x, patient.from.y, patient.from.z];
        let before = hp(&state, far);
        let shots = fire(&mut state, shooter, weapon);
        for shot in shots {
            assert!(!shot.hit);
            assert_eq!(shot.target_id, None);
            assert_eq!(shot.target_hp_after, None);
            assert_eq!(shot.damage, 0);
            let trace = shot.trace.unwrap();
            assert!(matches!(trace.impact, ShotImpact::Fighter { .. }));
            assert!((trace.end[0] - feet[0]).abs() <= crate::movement::RADIUS + 0.01);
            assert!(trace
                .pellets
                .iter()
                .all(|p| matches!(p.impact, ShotImpact::Fighter { .. })));
        }
        assert_eq!(hp(&state, far), before);
        let mut after = Vec::new();
        state.append_civilian_contacts(&mut after);
        assert_eq!(
            after
                .iter()
                .find(|body| body.key == patient.key)
                .unwrap()
                .from,
            patient.from
        );
    }
}

fn patient_lane() -> (GameState, Uuid, Uuid, crate::movement::contact::ContactBody) {
    let map = AuthoredSource::Mission(MissionId::NoticeToVacate)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    let shooter = Uuid::from_u128(301);
    let far = Uuid::from_u128(302);
    for id in [shooter, far] {
        state.add_player(id, "patient_lane".into(), Role::Human);
        assert!(state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::NoticeToVacate,
                attempt: 1
            }
        ));
    }
    state.tick(0.0);
    let mut civilians = Vec::new();
    state.append_civilian_contacts(&mut civilians);
    let patient = civilians
        .into_iter()
        .find(|body| body.key == "m04/edda_team_a")
        .unwrap();
    let feet = [patient.from.x, patient.from.y, patient.from.z];
    place(&mut state, shooter, [feet[0] - 1.2, feet[1], feet[2]]);
    place(&mut state, far, [feet[0] + 1.2, feet[1], feet[2]]);
    state.spawn_shields.clear();
    (state, shooter, far, patient)
}

#[test]
fn actual_patient_stops_traveling_point_without_damage_facts() {
    let (mut state, shooter, far, patient) = patient_lane();
    assert!(state.launch_traveling_shot(shooter));
    for _ in 0..25 {
        state.tick(0.05);
        if state.snapshot().projectiles.is_empty() {
            break;
        }
    }
    assert!(state.snapshot().projectiles.is_empty());
    assert_eq!(hp(&state, far), 100);
    assert!(state.shot_results.is_empty());
    assert!(!state
        .events
        .iter()
        .any(|event| matches!(event, GameEvent::Hit { .. })));
    let mut after = Vec::new();
    state.append_civilian_contacts(&mut after);
    assert_eq!(
        after
            .iter()
            .find(|body| body.key == patient.key)
            .unwrap()
            .from,
        patient.from
    );
}

#[test]
fn traveling_point_hits_a_front_fighter_before_the_neutral_stop() {
    let (mut state, shooter, rear, patient) = patient_lane();
    let feet = [patient.from.x, patient.from.y, patient.from.z];
    place(&mut state, shooter, [feet[0], feet[1], feet[2] - 3.0]);
    place(&mut state, rear, [feet[0], feet[1], feet[2] + 1.2]);
    let near = state.spawn_campaign_enemy(&EnemyPlacement {
        id: "front_clerk".into(),
        kind: EnemyKind::Clerk,
        feet: [feet[0], feet[1], feet[2] - 1.2],
        yaw: 0.0,
        seated: false,
        hover: None,
    });
    let before = hp(&state, near);
    state
        .players
        .iter_mut()
        .find(|p| p.id == shooter)
        .unwrap()
        .yaw = std::f32::consts::FRAC_PI_2;
    state.spawn_shields.clear();
    assert!(state.launch_traveling_shot(shooter));
    for _ in 0..25 {
        state.tick(0.05);
        if state.snapshot().projectiles.is_empty() {
            break;
        }
    }
    assert!(state.snapshot().projectiles.is_empty());
    assert_eq!(hp(&state, near), before - 12);
    assert_eq!(hp(&state, rear), 100);
    assert_eq!(
        state
            .events
            .iter()
            .filter(|e| matches!(e, GameEvent::Hit { target_id, .. } if *target_id == near))
            .count(),
        1
    );
}

#[test]
fn traveling_point_uses_same_nearest_team_and_ineligible_body_rules() {
    for friendly_fire in [false, true] {
        let (mut state, shooter, near, far) = lane([Role::Agent, Role::Human, Role::Agent]);
        state.config.rules = RuleSet::new(GameMode::Tdm, &[], friendly_fire).unwrap();
        for p in &mut state.players {
            p.team = Some(if p.id == far {
                Team::Coalition
            } else {
                Team::Union
            });
        }
        assert!(state.launch_traveling_shot(shooter));
        for _ in 0..20 {
            state.tick(0.05);
            if state.snapshot().projectiles.is_empty() {
                break;
            }
        }
        assert!(state.snapshot().projectiles.is_empty());
        assert_eq!(hp(&state, far), 100);
        assert_eq!(hp(&state, near), if friendly_fire { 88 } else { 100 });
    }
    for excluded in ["dead", "respawning", "detached", "eliminated"] {
        let (mut state, shooter, near, far) = lane([Role::Human, Role::Agent, Role::Human]);
        let p = state.players.iter_mut().find(|p| p.id == near).unwrap();
        match excluded {
            "dead" => p.hp = 0,
            "respawning" => p.respawn_timer = Some(100),
            "detached" => p.detached = true,
            "eliminated" => p.eliminated = true,
            _ => unreachable!(),
        }
        assert!(state.launch_traveling_shot(shooter));
        for _ in 0..25 {
            state.tick(0.05);
            if state.snapshot().projectiles.is_empty() {
                break;
            }
        }
        assert!(state.snapshot().projectiles.is_empty());
        assert_eq!(hp(&state, far), 88, "excluded={excluded}");
    }
}

#[test]
fn real_mission_briefing_bodies_are_inactive_until_shared_readiness() {
    let map = AuthoredSource::Mission(MissionId::NoticeToVacate)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    let ids = [Uuid::from_u128(501), Uuid::from_u128(502)];
    for (id, role) in ids.into_iter().zip([Role::Human, Role::Agent]) {
        state.add_player(id, "readiness_body".into(), role);
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.inventory.grant_weapon(WeaponType::Rail);
        p.weapon = WeaponType::Rail;
    }
    assert!(state
        .players
        .iter()
        .filter(|p| ids.contains(&p.id))
        .all(|p| !state.contact_eligible(p)));
    assert!(state.contact_bodies().is_empty());
    state.set_action(
        ids[0],
        Action {
            fire: true,
            ..Default::default()
        },
    );
    assert!(!state.launch_traveling_shot(ids[0]));
    state.tick(0.0);
    assert!(state.shot_results.is_empty());
    for id in ids {
        assert!(state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::NoticeToVacate,
                attempt: 1
            }
        ));
    }
    state.tick(0.0);
    for id in ids {
        assert!(state.contact_eligible(state.players.iter().find(|p| p.id == id).unwrap()));
        assert!(state
            .contact_bodies()
            .iter()
            .any(|body| body.key == id.to_string()));
    }
}

fn ward_lane() -> (GameState, Uuid, Uuid) {
    let map = AuthoredSource::Mission(MissionId::PersonsUnknown)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    let ids = [Uuid::from_u128(601), Uuid::from_u128(602)];
    for id in ids {
        state.add_player(id, "ward witness".into(), Role::Human);
        assert!(state.acknowledge_mission(
            id,
            MissionReady {
                id: MissionId::PersonsUnknown,
                attempt: 1
            }
        ));
    }
    state.tick(0.0);
    state.spawn_shields.clear();
    (state, ids[0], ids[1])
}

#[test]
fn actual_second_tableau_parts_stop_guns_and_pulse_without_health_facts() {
    for weapon in GUNS {
        let (mut state, shooter, rear) = ward_lane();
        place(&mut state, shooter, [8.5, 0.0, -17.12]);
        place(&mut state, rear, [8.5, 0.0, -14.3]);
        let (yaw, pitch) = crate::combat::aim_at([8.5, 1.6, -17.12], [8.56, 1.2, -16.12]).unwrap();
        let shots = fire_at(&mut state, shooter, weapon, yaw, pitch);
        assert_eq!(hp(&state, rear), 100);
        for shot in shots {
            assert!(!shot.hit && shot.target_id.is_none() && shot.target_hp_after.is_none());
            assert_eq!(shot.damage, 0);
            let trace = shot.trace.unwrap();
            assert!(
                matches!(trace.impact, ShotImpact::Fighter { .. }),
                "weapon={weapon:?}"
            );
            assert!(trace
                .pellets
                .iter()
                .all(|p| matches!(p.impact, ShotImpact::Fighter { .. })));
        }
    }
    let (mut state, shooter, rear) = ward_lane();
    place(&mut state, shooter, [8.5, 0.0, -17.12]);
    place(&mut state, rear, [8.5, 0.0, -14.3]);
    let (yaw, pitch) = crate::combat::aim_at([8.5, 1.6, -17.12], [8.56, 1.2, -16.12]).unwrap();
    let p = state.players.iter_mut().find(|p| p.id == shooter).unwrap();
    p.yaw = yaw;
    p.pitch = pitch;
    assert!(state.launch_traveling_shot(shooter));
    for _ in 0..5 {
        state.tick(0.05);
        if state.snapshot().projectiles.is_empty() {
            break;
        }
    }
    assert!(state.snapshot().projectiles.is_empty());
    assert_eq!(hp(&state, rear), 100);
    assert!(!state
        .events
        .iter()
        .any(|e| matches!(e, GameEvent::Hit { .. })));
}

#[test]
fn real_spawn_switches_restrained_body_once_and_releasing_pawn_stops_shots() {
    let (mut state, shooter, rear) = ward_lane();
    let mut cylinders = Vec::new();
    let mut boxes = Vec::new();
    state.append_m02_tableau_shots(&mut cylinders, &mut boxes);
    assert_eq!(cylinders.len(), 1);
    assert_eq!(cylinders[0].key, "m02/restrained_latch");
    place(&mut state, shooter, [6.0, 0.0, -10.0]);
    let before = fire(&mut state, shooter, WeaponType::Rail);
    assert!(!before[0].hit && before[0].target_id.is_none());
    assert!(matches!(
        before[0].trace.as_ref().unwrap().impact,
        ShotImpact::Fighter { .. }
    ));
    let latch = state.spawn_m02_companion().unwrap();
    assert!(state.spawn_m02_companion().is_none());
    cylinders.clear();
    boxes.clear();
    state.append_m02_tableau_shots(&mut cylinders, &mut boxes);
    assert!(cylinders.is_empty());
    assert_eq!(boxes.len(), 12);
    assert!(state.contact_eligible(state.players.iter().find(|p| p.id == latch).unwrap()));
    place(&mut state, shooter, [5.5, 0.0, -14.8]);
    place(&mut state, rear, [8.5, 0.0, -14.8]);
    let shot = fire(&mut state, shooter, WeaponType::Rail);
    assert_eq!(shot[0].target_id, Some(latch));
    assert_ne!(shot[0].target_id, Some(rear));
    assert!(matches!(
        shot[0].trace.as_ref().unwrap().impact,
        ShotImpact::Fighter { .. }
    ));
    assert!(shot[0].trace.as_ref().unwrap().end[0] < 7.55);
    assert_eq!(hp(&state, latch), 100);
    assert_eq!(hp(&state, rear), 100);
    assert_eq!(shot[0].damage, 0);
    state.mission = None;
    cylinders.clear();
    boxes.clear();
    state.append_m02_tableau_shots(&mut cylinders, &mut boxes);
    assert!(cylinders.is_empty() && boxes.is_empty());
}
