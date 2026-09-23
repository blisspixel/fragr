use super::*;
use crate::enclosed_fixture::{balcony, room};
use crate::movement::{Arena, BODY_HEIGHT};
use crate::navigation::{Navigation, NavigationGoal, Navigator};

fn player_at(state: &mut GameState, feet: [f32; 3]) -> Uuid {
    let id = Uuid::from_u128(state.players.len() as u128 + 1);
    state.add_player(id, format!("Probe {}", state.players.len()), Role::Human);
    let player = state.players.last_mut().unwrap();
    player.x = feet[0];
    player.y = feet[1] + PLAYER_FLOOR_Y;
    player.z = feet[2];
    player.weapon = WeaponType::Rail;
    id
}

fn feet(state: &GameState) -> [f32; 3] {
    let player = &state.players[0];
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

fn frame(state: &mut GameState, arena: &Arena) {
    state.tick += 1;
    state.shot_results.clear();
    state.tick_active(0.05, arena);
    state.take_events();
}

#[derive(serde::Serialize)]
struct CaptureFrame {
    feet: [f32; 3],
    yaw: f32,
    pitch: f32,
    shots: Vec<ShotResult>,
    phase: &'static str,
}

fn capture(state: &GameState, phase: &'static str) -> CaptureFrame {
    CaptureFrame {
        feet: feet(state),
        yaw: state.players[0].yaw,
        pitch: state.players[0].pitch,
        shots: state.shot_results.clone(),
        phase,
    }
}

#[test]
fn active_players_walk_both_levels_without_jumping_or_crossing_the_slab() {
    walk_capture();
}

fn walk_capture() -> Vec<CaptureFrame> {
    let arena = room();
    let world = Navigation::new(arena.clone()).unwrap();
    let mut frames = Vec::new();
    for (from, to, phase) in [
        ([-2.0, 0.0, 0.0], [9.0, 0.0, 0.0], "underpass"),
        ([4.0, 0.0, 0.0], [4.0, 3.0, 0.0], "stairs_up"),
        ([4.0, 3.0, 0.0], [4.0, 0.0, 0.0], "upper_exit"),
    ] {
        let mut state = GameState::new();
        state.pickups.clear();
        let id = player_at(&mut state, from);
        let mut navigator = Navigator::default();
        let mut arrived = false;
        for _ in 0..1600 {
            let here = feet(&state);
            if (here[0] - to[0]).hypot(here[2] - to[2]) < 0.3 && (here[1] - to[1]).abs() < 0.1 {
                arrived = true;
                break;
            }
            let action = navigator.steer(
                &world,
                here,
                NavigationGoal {
                    feet: to,
                    combat: false,
                },
                Action {
                    forward: true,
                    ..Action::default()
                },
                state.tick,
                true,
            );
            assert!(!action.jump);
            state.set_action(id, action);
            frame(&mut state, &arena);
            frames.push(capture(&state, phase));
            let [x, y, z] = feet(&state);
            assert!(
                arena.solids.iter().all(|solid| {
                    !solid.covers(x, z)
                        || y >= solid.top - 0.0001
                        || y + BODY_HEIGHT <= solid.bottom + 0.0001
                }),
                "player intersected a volume at {:?}",
                feet(&state)
            );
        }
        assert!(arrived, "{from:?} -> {to:?} stopped at {:?}", feet(&state));
    }
    frames
}

#[test]
fn queued_jump_hits_the_underside_and_lands_on_the_same_floor() {
    let arena = balcony();
    let mut state = GameState::new();
    state.pickups.clear();
    let id = player_at(&mut state, [4.0, 0.0, 0.0]);
    state.set_action(
        id,
        Action {
            jump: true,
            ..Action::default()
        },
    );
    state.set_action(id, Action::default());
    let mut peak = 0.0_f32;
    for _ in 0..30 {
        frame(&mut state, &arena);
        let y = feet(&state)[1];
        peak = peak.max(y);
        assert!(y + BODY_HEIGHT <= 2.4 + 0.0001);
    }
    assert!((peak - (2.4 - BODY_HEIGHT)).abs() < 0.0001);
    assert!(feet(&state)[1].abs() < 0.0001);
    assert_eq!(state.players[0].vy, 0.0);
}

#[test]
fn active_shots_hit_below_the_balcony_but_not_through_its_deck() {
    let arena = balcony();
    for (target_feet, hits) in [([6.0, 0.0, 0.0], true), ([4.0, 3.0, 0.0], false)] {
        let mut state = GameState::new();
        state.pickups.clear();
        let shooter = player_at(&mut state, [2.0, 0.0, 0.0]);
        let target = player_at(&mut state, target_feet);
        state.set_action(
            shooter,
            Action {
                fire: true,
                look_at: Some(crate::protocol::LookAt {
                    player_id: Some(target),
                    ..Default::default()
                }),
                ..Action::default()
            },
        );
        frame(&mut state, &arena);
        assert_eq!(state.shot_results.len(), 1);
        let shot = &state.shot_results[0];
        assert_eq!(shot.hit, hits);
        assert_eq!(shot.target_id, hits.then_some(target));
        assert_eq!(state.players[1].hp < PLAYER_MAX_HP, hits);
        let trace = shot.trace.as_ref().unwrap();
        if !hits {
            assert!((trace.end[1] - 2.4).abs() < 0.0001);
            assert_eq!(
                trace.impact,
                ShotImpact::Solid {
                    normal: [0.0, -1.0, 0.0]
                }
            );
        }
    }
}

/// A reproducible active-frame recording for rendered inspection. It exercises
/// the same core as live play, without claiming a complete network campaign.
#[test]
#[ignore]
fn export_enclosed_capture() {
    let arena = room();
    let mut frames = walk_capture();
    let mut state = GameState::new();
    state.pickups.clear();
    let id = player_at(&mut state, [4.0, 0.0, 0.0]);
    state.set_action(
        id,
        Action {
            jump: true,
            yaw: Some(0.0),
            ..Default::default()
        },
    );
    for i in 0..30 {
        frame(&mut state, &arena);
        frames.push(capture(&state, "head_contact"));
        if i == 0 {
            state.set_action(id, Action::default());
        }
    }
    state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(crate::protocol::LookAt {
                x: Some(5.0),
                y: Some(5.0),
                z: Some(0.0),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    frame(&mut state, &arena);
    assert_eq!(state.shot_results.len(), 1);
    assert!((state.shot_results[0].trace.as_ref().unwrap().end[1] - 2.4).abs() < 0.0001);
    frames.push(capture(&state, "underside_shot"));
    let data = serde_json::json!({
        "schema_version": 1,
        "kind": "active_frame_fixture",
        "dt": 0.05,
        "map": ServerMessage::MapInfo {
            presentation: None,
            mission: None,
            m02_objectives: None,
            map_id: 1,
            map_name: "Enclosed geometry fixture".into(),
            half_extent: arena.half,
            geometry_version: crate::protocol::GEOMETRY_VERSION,
            solids: arena.solids,
        },
        "frames": frames,
    });
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap();
    let path = root.join(".agents/qa/enclosed-session.json");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, serde_json::to_vec(&data).unwrap()).unwrap();
}
