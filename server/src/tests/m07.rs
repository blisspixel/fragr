//! Declared Goods: strict authoring, ordered fights, the window lesson, rim
//! sightlines, departure and retained earlier outcomes.
use crate::maps::{AuthoredMap, AuthoredSource, RuntimeMap};
use crate::protocol::{
    Action, EnemyKind, MissionId, MissionObjectiveAction, MissionPhase, MissionReady, Role,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::DeclaredGoods)
            .load()
            .expect("bundled M07 route proof")
    })
    .clone()
}

fn advance(s: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        s.tick_messages(0.05);
    }
}

fn fixture() -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    let id = Uuid::from_u128(7007);
    s.state.add_player(id, "Visitor".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::DeclaredGoods,
            attempt: 1
        }
    ));
    advance(&mut s, 1);
    (s, id)
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = feet[0];
    p.y = feet[1] + PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.vy = 0.0;
    p.clear_input();
}

fn arrival(s: &GameSession, index: usize) -> [f32; 3] {
    let g = s.state.map.m07_geometry().unwrap();
    let MissionObjectiveAction::Arrival { feet, .. } = g.objectives[index].action else {
        panic!("arrival");
    };
    feet
}

fn clear(s: &mut GameSession, id: Uuid, index: usize) {
    let group = s.state.map.encounters()[index].clone();
    place(s, id, arrival(s, index));
    advance(s, 1);
    for e in &group.enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == e.id)
            .expect("eligible current group spawned");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    advance(s, 2);
    assert!(s.state.encounters.is_complete(index));
}

#[test]
fn bundled_declared_goods_validates_its_shape() {
    let map = RuntimeMap::Authored(map());
    assert_eq!(map.id(), 1007);
    assert_eq!(map.campaign_mission_id(), Some(MissionId::DeclaredGoods));
    let g = map.m07_geometry().unwrap();
    assert_eq!(g.objectives.len(), 5);
    let groups = map.encounters();
    assert_eq!(groups.len(), 5);
    let kinds =
        |i: usize, kind: EnemyKind| groups[i].enemies.iter().filter(|e| e.kind == kind).count();
    assert_eq!(groups.iter().map(|g| g.enemies.len()).sum::<usize>(), 25);
    assert_eq!(kinds(1, EnemyKind::Notary), 2);
    assert_eq!(kinds(2, EnemyKind::Turret), 1);
    assert_eq!(kinds(2, EnemyKind::Clerk), 4);
    assert_eq!(kinds(3, EnemyKind::RangedSweeper), 1);
    assert_eq!(kinds(4, EnemyKind::RangedSweeper), 5);
    assert!(map.requires_sniper_contract());
}

#[test]
fn m07_pickup_ambush_keeps_the_patrol_clearable_with_real_rifle_inputs() {
    let (mut session, id) = fixture();
    let mut navigator = crate::navigation::Navigator::default();
    let runtime = session.state.map.clone();
    for goal in [
        [-61.0, 0.0, -63.0],
        [-58.0, 0.0, -62.0],
        [-52.0, 0.0, -62.0],
    ] {
        let mut reached = false;
        for _ in 0..200 {
            let player = session.state.players.iter().find(|p| p.id == id).unwrap();
            if (player.x - goal[0]).hypot(player.z - goal[2]) < 0.5 {
                reached = true;
                break;
            }
            let action = navigator.route_snapshot_with_visibility(
                runtime.navigation(),
                id,
                &session.state.snapshot(),
                Action {
                    forward: true,
                    look_at: Some(crate::protocol::LookAt {
                        x: Some(goal[0]),
                        y: Some(goal[1] + crate::movement::EYE_HEIGHT),
                        z: Some(goal[2]),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                true,
                &runtime.arena().solids,
            );
            session.state.set_action(id, action);
            advance(&mut session, 1);
        }
        assert!(reached, "ordinary pickup route must reach {goal:?}");
    }
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(
        player.weapon,
        crate::protocol::WeaponType::Scatter,
        "found Shotgun selects normally"
    );
    let required = ["patrol_clerk_a", "patrol_clerk_b", "patrol_clerk_c"];
    let mut defeated = std::collections::HashSet::new();
    for tick in 0..500 {
        let player = session.state.players.iter().find(|p| p.id == id).unwrap();
        let eye = [
            player.x,
            player.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
            player.z,
        ];
        let target = session
            .state
            .players
            .iter()
            .filter(|p| required.contains(&p.name.as_str()) && p.hp > 0)
            .filter(|p| {
                crate::combat::line_of_sight(
                    eye,
                    [
                        p.x,
                        p.y - PLAYER_FLOOR_Y + crate::combat::aim_height(p.campaign),
                        p.z,
                    ],
                    &runtime.arena().solids,
                )
            })
            .min_by(|a, b| {
                ((a.x - eye[0]).hypot(a.z - eye[2]))
                    .total_cmp(&((b.x - eye[0]).hypot(b.z - eye[2])))
            })
            .map(|p| p.id);
        if defeated.len() == required.len() {
            assert!(
                player.hp > 0,
                "the real participant survives the opening patrol"
            );
            return;
        }
        assert!(player.hp > 0, "patrol must be clearable before a wipe");
        session.state.set_action(
            id,
            Action {
                weapon_swap: Some(crate::protocol::WeaponType::Flechette),
                left: tick % 40 < 20,
                right: tick % 40 >= 20,
                fire: target.is_some(),
                look_at: target.map(|target| crate::protocol::LookAt {
                    player_id: Some(target),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        for message in session.tick_messages(0.05) {
            if let crate::protocol::ServerMessage::Snapshot(snapshot) = message {
                for shot in snapshot.shot_results.iter().filter(|shot| shot.killed) {
                    if let Some(name) = shot.target.as_ref() {
                        if required.contains(&name.as_str()) {
                            defeated.insert(name.clone());
                        }
                    }
                }
            }
        }
    }
    let bodies: Vec<_> = session
        .state
        .players
        .iter()
        .map(|p| (&p.name, p.hp, p.x, p.z, p.weapon))
        .collect();
    panic!("the authored Clerks could not be cleared in the 25 second street window: {bodies:?}");
}

/// Marksmen on the rim that can see a participant standing at `feet`, using
/// the server's chest-or-eye rule, sight range and notice cone.
fn rim_watchers(arena: &crate::movement::Arena, marksmen: &[[f32; 3]], feet: [f32; 3]) -> usize {
    marksmen
        .iter()
        .filter(|m| {
            let eye = [m[0], m[1] + crate::movement::EYE_HEIGHT, m[2]];
            let dx = feet[0] - m[0];
            let dz = feet[2] - m[2];
            let bearing = dz.atan2(dx);
            let facing = -std::f32::consts::FRAC_PI_2;
            let mut turn = (bearing - facing).rem_euclid(std::f32::consts::TAU);
            if turn > std::f32::consts::PI {
                turn -= std::f32::consts::TAU;
            }
            dx.hypot(dz) <= 90.0
                && turn.abs() <= 1.0
                && [crate::combat::aim_height(None), crate::movement::EYE_HEIGHT]
                    .iter()
                    .any(|h| {
                        crate::combat::line_of_sight(
                            eye,
                            [feet[0], feet[1] + h, feet[2]],
                            &arena.solids,
                        )
                    })
        })
        .count()
}

fn rim_marksmen(map: &RuntimeMap) -> Vec<[f32; 3]> {
    map.encounters()[4]
        .enemies
        .iter()
        .filter(|e| e.kind == EnemyKind::RangedSweeper)
        .map(|e| e.feet)
        .collect()
}

#[test]
fn m07_future_groups_wait_and_objectives_need_a_clear_then_actual_arrival() {
    let (mut s, id) = fixture();
    let initial: Vec<String> = s
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.name.clone())
        .collect();
    assert_eq!(initial.len(), 5, "only the curfew patrol is placed");
    assert!(initial.iter().all(|name| name.starts_with("patrol_")));
    // Arriving before the patrol falls does not advance the ring.
    let ring = arrival(&s, 0);
    place(&mut s, id, ring);
    advance(&mut s, 2);
    let state = s.state.mission_state().unwrap();
    assert!(state.m07.as_ref().unwrap().completed.is_empty());
    for index in 0..5 {
        clear(&mut s, id, index);
        let completed = s.state.mission_state().unwrap().m07.unwrap().completed;
        assert_eq!(completed.len(), index + 1, "objective {index} reached");
        assert_eq!(completed[index], crate::protocol::M07_OBJECTIVE_IDS[index]);
    }
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::InProgress);
    let f = state.m07.unwrap();
    assert!(matches!(
        f.current.unwrap().action,
        MissionObjectiveAction::Use { .. }
    ));
    // A retry restores the whole entry: groups, objectives and the companion.
    s.state.reset_mission();
    s.state.reset_campaign_encounters();
    advance(&mut s, 1);
    assert!(s
        .state
        .mission_state()
        .unwrap()
        .m07
        .unwrap()
        .completed
        .is_empty());
}

#[test]
fn m07_window_lesson_shows_a_head_over_the_sill_beyond_rail_reach() {
    let authored = map();
    let runtime = RuntimeMap::Authored(authored.clone());
    let solids = &runtime.arena().solids;
    let lesson = runtime.encounters()[3].enemies[0].feet;
    let eye = [
        lesson[0],
        lesson[1] + crate::movement::EYE_HEIGHT,
        lesson[2],
    ];
    let step = authored.landmark("window_stance").unwrap();
    let head = [step[0], step[1] + crate::movement::EYE_HEIGHT, step[2]];
    let centre = [step[0], step[1] + crate::combat::aim_height(None), step[2]];
    assert!(
        crate::combat::line_of_sight(eye, head, solids),
        "a raised head is seen"
    );
    assert!(
        !crate::combat::line_of_sight(eye, centre, solids),
        "the sill covers the body"
    );
    let off = [step[0], 3.5, step[2] - 1.4];
    for height in [crate::combat::aim_height(None), crate::movement::EYE_HEIGHT] {
        assert!(
            !crate::combat::line_of_sight(eye, [off[0], off[1] + height, off[2]], solids),
            "dropping off the step hides the participant"
        );
    }
    // The participant can see the marksman's body from the step.
    let body = [
        lesson[0],
        lesson[1] + crate::combat::aim_height(None),
        lesson[2],
    ];
    assert!(crate::combat::line_of_sight(head, body, solids));
    let distance = (0..3)
        .map(|i| (head[i] - body[i]).powi(2))
        .sum::<f32>()
        .sqrt();
    assert!(
        distance > crate::protocol::WeaponType::Rail.range_units()
            && distance < crate::protocol::WeaponType::Sniper.range_units(),
        "the lesson is beyond the Railgun and inside the Sniper: {distance}"
    );
}

#[test]
fn m07_cover_rows_shield_the_ordinary_route_stops() {
    let map = RuntimeMap::Authored(map());
    let marksmen = rim_marksmen(&map);
    assert_eq!(marksmen.len(), 5);
    // Stops behind each row of cover see no marksman at all.
    for stop in [
        [-20.0, 4.0, 11.0],
        [6.0, 4.0, 11.0],
        [32.0, 4.0, 11.0],
        [-15.0, 4.0, 23.0],
        [10.0, 4.0, 21.0],
        [-12.0, 4.0, 29.0],
        [12.0, 4.0, 29.0],
        [-26.0, 4.0, 35.0],
        [0.0, 4.0, 35.0],
        [23.0, 4.0, 35.0],
        [-14.0, 4.0, 40.0],
        [22.0, 4.0, 40.0],
        [-18.0, 4.0, 45.0],
        [10.0, 4.0, 45.0],
    ] {
        assert_eq!(
            rim_watchers(map.arena(), &marksmen, stop),
            0,
            "cover stop {stop:?} must hide the whole rim"
        );
    }
    // Under the rim the marksmen cannot see straight down.
    assert!(rim_watchers(map.arena(), &marksmen, [0.0, 4.0, 56.0]) <= 2);
    // The overlook and the open cut entry stay exposed: a real choice.
    assert!(rim_watchers(map.arena(), &marksmen, [-6.0, 7.3, -4.0]) >= 3);
}

#[test]
fn m07_sniper_peeks_clear_cover_across_the_tour_arrival_band() {
    let runtime = RuntimeMap::Authored(map());
    let solids = &runtime.arena().solids;
    let exposed = |feet: [f32; 3], target: [f32; 3]| {
        let eye = [feet[0], feet[1] + crate::movement::EYE_HEIGHT, feet[2]];
        [0.5, 0.85, 0.2].into_iter().any(|fraction| {
            crate::combat::line_of_sight(
                eye,
                [
                    target[0],
                    target[1] + crate::combat::FIGHTER_HEIGHT * fraction,
                    target[2],
                ],
                solids,
            )
        })
    };
    assert!(
        !exposed([-1.631_547_1, 4.0, 10.915_329], [-14.0, 9.0, 59.5]),
        "actual accepted edge feet remain behind the first shield"
    );
    for (peek, target) in [
        ([-3.25, 4.0, 11.0], [-14.0, 9.0, 59.5]),
        ([15.25, 4.0, 11.0], [32.0, 9.0, 59.5]),
    ] {
        // The capture accepts a horizontal distance below 0.5 m. Check a
        // containing square, including its corners, for a conservative margin.
        for dx in [-0.5, 0.0, 0.5] {
            for dz in [-0.5, 0.0, 0.5] {
                let feet = [peek[0] + dx, peek[1], peek[2] + dz];
                assert!(
                    runtime.navigation().walkable([6.0, 4.0, 11.0], feet),
                    "peek {feet:?} remains an ordinary supported walk"
                );
                assert!(
                    exposed(feet, target),
                    "peek {feet:?} must expose {target:?}"
                );
            }
        }
    }
}

#[test]
fn m07_departure_needs_the_cut_clear_a_ready_living_party_and_a_fresh_use() {
    let (mut s, id) = fixture();
    for i in 0..4 {
        clear(&mut s, id, i);
    }
    let g = s.state.map.m07_geometry().unwrap();
    place(&mut s, id, g.departure.approach);
    advance(&mut s, 1);
    assert!(
        s.state.mission_state().unwrap().prompts.is_empty(),
        "the uncleared cut blocks the depot"
    );
    clear(&mut s, id, 4);
    let point = g
        .departure
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    let aim = crate::protocol::LookAt {
        x: Some(point[0]),
        y: Some(point[1]),
        z: Some(point[2]),
        player_id: None,
    };
    place(&mut s, id, g.departure.approach);
    s.state.set_action(
        id,
        Action {
            look_at: Some(aim.clone()),
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    let peer = Uuid::from_u128(7070);
    s.state.add_player(peer, "Peer".into(), Role::Human);
    advance(&mut s, 1);
    assert!(
        s.state.mission_state().unwrap().prompts.is_empty(),
        "an unready peer blocks departure"
    );
    s.state.remove_player(peer);
    advance(&mut s, 1);
    assert_eq!(s.state.mission_state().unwrap().prompts.len(), 1);
    s.state.set_action(
        id,
        Action {
            look_at: Some(aim),
            interact: true,
            ..Action::default()
        },
    );
    advance(&mut s, 1);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    assert_eq!(
        state.m07.unwrap().completed.last().unwrap(),
        "party_departed"
    );
}

#[test]
fn m07_companion_leaves_the_lesson_marksman_to_the_participant() {
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, id, i);
    }
    let window = arrival(&s, 3);
    place(&mut s, id, window);
    advance(&mut s, 2);
    let companion = s
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .map(|p| p.id)
        .expect("Latch follows into the post");
    let marksman = s
        .state
        .players
        .iter()
        .find(|p| p.name == "lesson_marksman")
        .unwrap()
        .id;
    place(&mut s, companion, [-4.5, 4.0, -1.1]);
    for _ in 0..80 {
        advance(&mut s, 1);
        assert!(
            !s.state
                .shot_results
                .iter()
                .any(|shot| shot.shooter_id == companion && shot.target_id == Some(marksman)),
            "support fire never takes the lesson"
        );
    }
}

/// Grid search over standing one metre cells across the cut, from the entry to
/// the rim top, never stepping onto a cell more than `limit` marksmen watch.
fn watched_route(runtime: &RuntimeMap, limit: usize) -> Option<Vec<[f32; 3]>> {
    let marksmen = rim_marksmen(runtime);
    let nav = runtime.navigation();
    let cell = |x: i32, z: i32| {
        nav.floor_below([x as f32, 12.0, z as f32])
            .map(|y| [x as f32, y, z as f32])
    };
    let start = (-2i32, 6i32);
    let goal = (40i32, 60i32);
    let mut previous = std::collections::HashMap::from([(start, start)]);
    let mut queue = std::collections::VecDeque::from([start]);
    while let Some(at) = queue.pop_front() {
        if at == goal {
            break;
        }
        let here = cell(at.0, at.1)?;
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let next = (at.0 + dx, at.1 + dz);
            if previous.contains_key(&next)
                || !(-40..=70).contains(&next.0)
                || !(0..=66).contains(&next.1)
            {
                continue;
            }
            let Some(there) = cell(next.0, next.1) else {
                continue;
            };
            if there[1] < 3.9
                || !nav.walkable(here, there)
                || rim_watchers(runtime.arena(), &marksmen, there) > limit
            {
                continue;
            }
            previous.insert(next, at);
            queue.push_back(next);
        }
    }
    let mut at = goal;
    let mut path = vec![cell(goal.0, goal.1)?];
    while at != start {
        at = *previous.get(&at)?;
        path.push(cell(at.0, at.1)?);
    }
    path.reverse();
    Some(path)
}

#[test]
fn m07_cut_has_an_ordinary_route_no_more_than_two_marksmen_watch() {
    let runtime = RuntimeMap::Authored(map());
    let route =
        watched_route(&runtime, 2).expect("a walk across the cut watched by at most two marksmen");
    assert!(
        route.len() < 160,
        "the watched route stays a direct crossing: {} cells",
        route.len()
    );
    let marksmen = rim_marksmen(&runtime);
    assert!(route
        .iter()
        .all(|feet| rim_watchers(runtime.arena(), &marksmen, *feet) <= 2));
    assert!(
        watched_route(&runtime, 1).is_none(),
        "the crossing is never free: some stretch is watched"
    );
}

/// The rendered tour walks only where ordinary movement can: every waypoint
/// stands on a floor at its stated height and every consecutive pair is a
/// straight walk the shared movement accepts.
#[test]
fn m07_tour_waypoints_are_ordinary_walks() {
    let runtime = RuntimeMap::Authored(map());
    let nav = runtime.navigation();
    let manifest: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../../client/qa/m07_declared_goods.json"))
            .unwrap();
    let point = |v: &serde_json::Value| -> [f32; 3] {
        let a = v.as_array().unwrap();
        [
            a[0].as_f64().unwrap() as f32,
            a[1].as_f64().unwrap() as f32,
            a[2].as_f64().unwrap() as f32,
        ]
    };
    let mut at = [-66.0f32, 0.0, -62.5];
    for state in manifest["states"].as_array().unwrap() {
        let name = state["name"].as_str().unwrap();
        let mut chains: Vec<(&str, Vec<[f32; 3]>, bool)> = Vec::new();
        if let Some(walk) = state["walk_to"].as_array() {
            chains.push(("walk", walk.iter().map(point).collect(), true));
        }
        for key in ["approach_route", "search_route"] {
            if let Some(route) = state["combat"][key].as_array() {
                chains.push((key, route.iter().map(point).collect(), true));
            }
        }
        for (label, chain, from_here) in chains {
            let mut from = if from_here { at } else { chain[0] };
            for p in &chain {
                let floor = nav.floor_below([p[0], p[1] + 0.6, p[2]]);
                let standing = floor.is_some_and(|y| (y - p[1]).abs() < 0.03);
                let walk = nav.walkable(from, *p);
                assert!(
                    standing && walk,
                    "{name} {label}: {from:?} -> {p:?} standing {standing} ({floor:?}) walkable {walk}"
                );
                from = *p;
            }
            if label == "walk" || label == "approach_route" {
                at = from;
            }
        }
        if let Some(route) = state["combat"]["search_route"].as_array() {
            at = point(route.last().unwrap());
        }
    }
}

#[test]
fn m07_seeded_rack_sniper_takes_the_lesson_from_the_step_and_the_arrival_counts() {
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, id, i);
    }
    place(&mut s, id, [-0.5, 0.0, -2.3]);
    advance(&mut s, 2);
    let me = s.state.players.iter().find(|p| p.id == id).unwrap();
    assert!(
        me.inventory.owns(crate::protocol::WeaponType::Sniper),
        "the rack grants the Sniper Rifle through the normal supply path"
    );
    place(&mut s, id, [-6.0, 4.0, -1.1]);
    advance(&mut s, 1);
    let marksman = s
        .state
        .players
        .iter()
        .find(|p| p.name == "lesson_marksman")
        .expect("the lesson is placed once the post clears")
        .id;
    let windup = (0..80).any(|_| {
        advance(&mut s, 1);
        matches!(
            s.state
                .players
                .iter()
                .find(|p| p.id == marksman)
                .and_then(|p| p.campaign),
            Some(crate::protocol::CampaignActor::Union {
                phase: crate::protocol::EnemyPhase::Windup,
                ..
            })
        )
    });
    assert!(windup, "a head over the sill draws the glint");
    let me = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    me.weapon = crate::protocol::WeaponType::Sniper;
    me.fire_cooldown = 0;
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                player_id: Some(marksman),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    advance(&mut s, 1);
    s.state.set_action(id, Action::default());
    let shot = s
        .state
        .shot_results
        .iter()
        .find(|shot| shot.shooter_id == id)
        .expect("the participant fired");
    assert_eq!(
        (shot.target_id, shot.damage),
        (Some(marksman), 70),
        "one scoped-range Sniper hit answers the glint"
    );
    advance(&mut s, 3);
    let state = s.state.mission_state().unwrap();
    assert_eq!(
        state.m07.unwrap().completed,
        [
            "ring_cleared",
            "plaza_cleared",
            "post_cleared",
            "window_cleared"
        ]
    );
    assert_eq!(s.state.players.iter().find(|p| p.id == id).unwrap().hp, 100);
}

#[test]
fn m07_controller_binds_the_town_and_refuses_forged_or_mixed_facts() {
    let (mut s, id) = fixture();
    let map = s.state.map.clone();
    let g = map.m07_geometry().unwrap().clone();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m07(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    assert!(
        client
            .replace_map_with_m06(
                map.m06_geometry().as_ref(),
                map.half_extent(),
                &map.arena().solids,
                map.presentation_ref()
            )
            .is_ok(),
        "no M06 envelope on the town map clears nothing"
    );
    let mut moved = g.clone();
    moved.companion_start[0] += 1.0;
    assert!(
        client
            .replace_map_with_m07(
                Some(&moved),
                map.half_extent(),
                &map.arena().solids,
                map.presentation_ref()
            )
            .is_err(),
        "the static town contract cannot change under the client"
    );
    let mut navigator = crate::navigation::Navigator::default();
    let refused = client.steer(
        &mut navigator,
        map.navigation(),
        id,
        &s.state.snapshot(),
        Action {
            forward: true,
            fire: true,
            ..Action::default()
        },
    );
    assert!(
        !refused.forward && !refused.fire,
        "no steering before fresh facts"
    );
    let state = s.state.mission_state().unwrap();
    client.observe(s.state.tick, state.clone()).unwrap();
    let steered = client.steer(
        &mut navigator,
        map.navigation(),
        id,
        &s.state.snapshot(),
        Action::default(),
    );
    assert!(
        steered.forward || steered.turn_left || steered.turn_right || steered.yaw.is_some(),
        "fresh facts steer toward the ring arrival: {steered:?}"
    );
    let mut forged = state.clone();
    forged.m07.as_mut().unwrap().carried_prisoner_route_marked ^= true;
    assert!(
        client.observe(s.state.tick + 1, forged).is_err(),
        "carried outcomes are immutable"
    );
    let mut skipped = state.clone();
    skipped.m07.as_mut().unwrap().current = Some(g.objectives[1].clone());
    assert!(
        client.observe(s.state.tick + 1, skipped).is_err(),
        "the objective must match the map order"
    );
    clear(&mut s, id, 0);
    let next = s.state.mission_state().unwrap();
    client.observe(s.state.tick, next).unwrap();
    client
        .replace_map_with_m07(
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
}

#[tokio::test]
async fn m07_refuses_pre_town_readers_and_sends_geometry_before_snapshots() {
    use futures_util::{SinkExt, StreamExt};
    use std::time::Duration;
    use tokio_tungstenite::{connect_async, tungstenite::Message};

    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 0,
            authored: Some(AuthoredSource::Mission(MissionId::DeclaredGoods)),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    for version in [
        crate::protocol::M06_GAMEPLAY_VERSION,
        crate::protocol::SNIPER_GAMEPLAY_VERSION,
        crate::protocol::M08_GAMEPLAY_VERSION,
        crate::protocol::M07_GAMEPLAY_VERSION,
        crate::protocol::ASSESSOR_GAMEPLAY_VERSION,
    ] {
        for role in ["human", "agent", "spectator"] {
            let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
            socket
                .send(Message::Text(
                    serde_json::json!({
                        "type":"hello", "role":role, "name":"TownProbe",
                        "gameplay_version":version,
                        "geometry_version":crate::protocol::GEOMETRY_VERSION
                    })
                    .to_string(),
                ))
                .await
                .unwrap();
            tokio::time::timeout(Duration::from_secs(5), async {
                let mut saw_map = false;
                let mut saw_welcome = false;
                loop {
                    let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                        continue;
                    };
                    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                    if version < crate::protocol::ASSESSOR_GAMEPLAY_VERSION {
                        assert_eq!(value["type"], "error", "pre-town reader admitted");
                        assert_eq!(value["code"], "unsupported_gameplay");
                        assert!(value["message"].as_str().unwrap().contains(&format!(
                            "version {}",
                            crate::protocol::ASSESSOR_GAMEPLAY_VERSION
                        )));
                        break;
                    }
                    match value["type"].as_str().unwrap() {
                        "welcome" => saw_welcome = true,
                        "map_info" => {
                            assert_eq!(value["map_id"], 1007);
                            assert!(value["m07"].is_object(), "the town envelope rides MapInfo");
                            saw_map = true;
                        }
                        "snapshot" => {
                            assert!(saw_map && saw_welcome, "snapshot overtook geometry");
                            break;
                        }
                        "error" => panic!("current reader rejected: {value}"),
                        _ => {}
                    }
                }
            })
            .await
            .expect("bounded town admission");
            let _ = socket.close(None).await;
        }
    }
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();
}

#[test]
fn m07_entering_the_cut_passes_a_window_arrival_won_from_elsewhere() {
    let (mut s, id) = fixture();
    for i in 0..3 {
        clear(&mut s, id, i);
    }
    // Trigger the lesson on the step, then take it from the floor below.
    place(&mut s, id, [-6.0, 4.0, -1.1]);
    advance(&mut s, 1);
    place(&mut s, id, [-1.5, 0.0, -3.0]);
    let lesson = s.state.map.encounters()[3].clone();
    for e in &lesson.enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == e.id)
            .expect("lesson spawned");
        p.hp = 0;
        s.state
            .encounters
            .hit(p.id, [p.x, p.y - PLAYER_FLOOR_Y, p.z], s.state.tick, true);
    }
    advance(&mut s, 4);
    let completed = |s: &GameSession| {
        s.state
            .mission_state()
            .unwrap()
            .m07
            .unwrap()
            .completed
            .len()
    };
    assert!(s.state.encounters.is_complete(3));
    assert_eq!(
        completed(&s),
        3,
        "the window arrival waits while the cut sleeps"
    );
    place(&mut s, id, [6.0, 4.0, 10.5]);
    advance(&mut s, 3);
    assert!(s.state.encounters.is_awake(4));
    assert_eq!(
        completed(&s),
        4,
        "walking into the cut passes the window arrival"
    );
}
