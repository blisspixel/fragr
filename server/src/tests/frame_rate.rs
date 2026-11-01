//! Frame-rate independence of the authoritative step (#525).
//!
//! A client sends one Action per rendered frame, so a 30 fps and a 240 fps
//! player deliver one to twelve Actions inside each 50 ms tick. The server
//! steps movement once per tick from the newest Action plus its press
//! latches, so the same held keys must give the same body at every rate:
//! the Quake 3 lesson that a frame-rate-dependent jump becomes a competitive
//! setting. The GDScript mirror's half is `client/scripts/test_frame_rate_golden.gd`.

use crate::movement::DT_LIVE;
use crate::protocol::{Action, Role};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

/// The frame rates the 1.0 bar names.
const RATES: [u32; 4] = [30, 60, 144, 240];
const TICKS: usize = 48;

/// What a player holds during each tick: a run, a turning strafe, a jump, a
/// dodge, a crouch walk and a release.
fn held(tick: usize) -> Action {
    let mut action = Action {
        yaw: Some(0.15 * tick as f32 % std::f32::consts::TAU),
        pitch: Some(0.0),
        ..Action::default()
    };
    match tick {
        0..=7 => action.forward = true,
        8..=15 => {
            action.forward = true;
            action.right = true;
            action.jump = tick == 10;
        }
        16..=21 => {
            action.left = true;
            action.dodge = tick == 17;
        }
        22..=31 => {
            action.back = true;
            action.duck = true;
        }
        32..=37 => {
            action.forward = true;
            action.jump = tick == 33;
        }
        _ => {}
    }
    action
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Body {
    at: [f32; 3],
    velocity: [f32; 3],
    ducking: bool,
}

/// Drive one human at `fps`, one Action per frame, frames offset from the
/// tick grid by a fixed phase. Returns the body after every tick and the
/// most and fewest Actions any tick received.
fn run(fps: u32) -> (Vec<Body>, usize, usize) {
    let mut state = GameState::new();
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.start_round();
    state.pickups.clear();
    let id = Uuid::from_u128(0xF5);
    state.add_player(id, "Runner".into(), Role::Human);
    state.spawn_shields.clear();
    {
        let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
        [p.x, p.y, p.z] = [0.0, PLAYER_FLOOR_Y, 0.0];
        p.vy = 0.0;
    }
    let frame = 1.0 / f64::from(fps);
    let mut next_frame = 0.37 * frame;
    let mut seq = 0u32;
    let mut bodies = Vec::new();
    let (mut most, mut fewest) = (0usize, usize::MAX);
    for tick in 0..TICKS {
        let cutoff = (tick + 1) as f64 * f64::from(DT_LIVE);
        let mut sent = 0usize;
        while next_frame <= cutoff {
            seq += 1;
            state.set_action(
                id,
                Action {
                    seq: Some(seq),
                    ..held(tick)
                },
            );
            sent += 1;
            next_frame += frame;
        }
        most = most.max(sent);
        fewest = fewest.min(sent);
        state.tick(DT_LIVE);
        let p = state.players.iter().find(|p| p.id == id).unwrap();
        bodies.push(Body {
            at: [p.x, p.y - PLAYER_FLOOR_Y, p.z],
            velocity: [p.vx, p.vy, p.vz],
            ducking: p.ducking,
        });
    }
    (bodies, most, fewest)
}

#[test]
fn the_same_keys_move_the_same_body_at_30_60_144_and_240_fps() {
    let (reference, _, _) = run(60);
    // The script did move: a run, a jump that left the floor, a dodge burst
    // and a crouch.
    let peak = reference.iter().map(|b| b.at[1]).fold(0.0f32, f32::max);
    let fastest = reference
        .iter()
        .map(|b| b.velocity[0].hypot(b.velocity[2]))
        .fold(0.0f32, f32::max);
    assert!(peak > 1.0, "jumped {peak}");
    assert!(
        fastest > crate::movement::TOP_SPEED + 1.0,
        "dodged {fastest}"
    );
    assert!(reference.iter().any(|b| b.ducking));
    for fps in RATES {
        let (bodies, most, fewest) = run(fps);
        assert!(fewest >= 1, "{fps} fps left a tick without an Action");
        let expected_most = (f64::from(fps) * f64::from(DT_LIVE)).ceil() as usize;
        assert!(most <= expected_most, "{fps} fps: {most} Actions in a tick");
        for (tick, (body, want)) in bodies.iter().zip(&reference).enumerate() {
            assert_eq!(body, want, "{fps} fps diverges from 60 fps at tick {tick}");
        }
    }
}
