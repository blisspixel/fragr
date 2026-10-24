//! Coalition jetpack: short thrust bursts on the held jump input, a visible
//! fuel count that refills only on support, and an authored height ceiling.
//! Mirrored by `client/scripts/jet_movement.gd` with shared golden vectors.
use super::{grounded, water, Arena, MoveInput, MoveState};
use crate::protocol::WaterRegion;

/// Three seconds of thrust at the 20 Hz live step.
pub const FUEL_MAX: u16 = 60;
/// Fuel returned per supported tick: an empty pack refills in one second of
/// standing or walking, never in the air.
pub const REFILL_PER_TICK: u16 = 3;
/// Upward acceleration while thrusting. Gravity still applies, so the net
/// climb is `THRUST - GRAVITY`: a lift, not a launch.
pub const THRUST: f32 = 34.0;
/// Fastest climb thrust can sustain. A jump already rising faster keeps its
/// own speed; thrust never slows it.
pub const MAX_RISE: f32 = 4.5;
/// Feet never rise above the ceiling while thrusting, and a climb that
/// reaches it stops there. A map authors it below its perimeter walls.
pub const DEFAULT_CEILING: f32 = 9.0;

/// The pack's state carried between steps.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Pack {
    pub fuel: u16,
}

/// One live step with the pack worn. Returns the moved body, the fuel left and
/// whether this step burned thrust. Thrust needs the held jump input, a body
/// already off its support at the start of the step, fuel and feet below the
/// ceiling. A grounded jump input is the ordinary jump: the pack then lifts on
/// the next step while the input stays held.
#[allow(clippy::too_many_arguments)]
pub fn live_step(
    state: MoveState,
    input: &MoveInput,
    speed: f32,
    dt: f32,
    arena: &Arena,
    height: f32,
    regions: &[WaterRegion],
    pack: Pack,
    ceiling: f32,
) -> (MoveState, Pack, bool) {
    let fuel = pack.fuel.min(FUEL_MAX);
    let support = arena.support_height(state.x, state.z, state.y);
    let airborne = !grounded(state.y, support, state.vy);
    let thrusting = input.jump && airborne && fuel > 0 && state.y < ceiling;
    let mut start = state;
    if thrusting {
        // Integration subtracts this step's gravity afterwards, so the cap is
        // stated after gravity: the step ends rising no faster than MAX_RISE.
        let boosted = (state.vy + THRUST * dt).min(MAX_RISE + super::GRAVITY * dt);
        start.vy = state.vy.max(boosted);
    }
    let mut moved = water::live_step(start, input, speed, dt, arena, height, regions);
    if moved.y > ceiling && moved.y > state.y {
        moved.y = ceiling.max(state.y);
        moved.vy = moved.vy.min(0.0);
    }
    let fuel = if thrusting {
        fuel - 1
    } else if grounded(
        moved.y,
        arena.support_height(moved.x, moved.z, moved.y),
        moved.vy,
    ) {
        (fuel + REFILL_PER_TICK).min(FUEL_MAX)
    } else {
        fuel
    };
    (moved, Pack { fuel }, thrusting)
}

/// A short authored hop climbs until the feet clear the landing by this much,
/// then crosses at that height.
pub const HOP_CLEARANCE: f32 = 0.6;
/// The hop releases thrust and travel this close to the landing.
pub const HOP_ARRIVE: f32 = 0.35;
/// Ticks a hop may take before a controller abandons it for the walking route.
pub const HOP_TICKS: u32 = 100;

/// Deterministic controller input for one authored hop from a supported
/// launch to a landing: rise first, cross at clearance height, then drop
/// onto the landing. Movement and collision stay the ordinary live step.
pub fn hop_input(state: MoveState, landing: [f32; 3]) -> MoveInput {
    let dx = landing[0] - state.x;
    let dz = landing[2] - state.z;
    let over = dx.hypot(dz) <= HOP_ARRIVE;
    let clear = state.y >= landing[1] + HOP_CLEARANCE;
    MoveInput {
        forward: clear && !over,
        jump: !over && state.y < landing[1] + HOP_CLEARANCE + 0.3,
        yaw: super::normalize_yaw(dz.atan2(dx)),
        ..MoveInput::default()
    }
}

/// Fly one hop with the actual live step and a full pack. Returns the ticks
/// taken when the body ends supported on the landing's floor within reach.
pub fn simulate_hop(
    arena: &Arena,
    launch: [f32; 3],
    landing: [f32; 3],
    ceiling: f32,
) -> Option<u32> {
    let mut state = MoveState {
        x: launch[0],
        z: launch[2],
        y: launch[1],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let mut pack = Pack { fuel: FUEL_MAX };
    for tick in 1..=HOP_TICKS {
        let input = hop_input(state, landing);
        let (moved, next, _) = live_step(
            state,
            &input,
            super::TOP_SPEED,
            super::DT_LIVE,
            arena,
            super::BODY_HEIGHT,
            &[],
            pack,
            ceiling,
        );
        state = moved;
        pack = next;
        let support = arena.support_height(state.x, state.z, state.y);
        if grounded(state.y, support, state.vy)
            && (state.y - landing[1]).abs() <= 0.05
            && (state.x - landing[0]).hypot(state.z - landing[2]) <= 0.6
        {
            return Some(tick);
        }
    }
    None
}

/// Shared vectors for the GDScript mirror.
pub const GOLDEN_PATH: &str = "client/golden/jetpack_vectors.json";

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct GoldenStep {
    pub state: MoveState,
    pub fuel: u16,
    pub thrusting: bool,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct GoldenCase {
    pub name: String,
    pub arena: Arena,
    pub start: MoveState,
    pub fuel: u16,
    pub ceiling: f32,
    pub speed: f32,
    pub inputs: Vec<MoveInput>,
    pub expected: Vec<GoldenStep>,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct GoldenFile {
    pub version: u32,
    pub dt: f32,
    pub fuel_max: u16,
    pub refill_per_tick: u16,
    pub thrust: f32,
    pub max_rise: f32,
    pub cases: Vec<GoldenCase>,
}

fn case(
    name: &str,
    arena: &Arena,
    start: MoveState,
    fuel: u16,
    ceiling: f32,
    inputs: Vec<MoveInput>,
) -> GoldenCase {
    let mut state = start;
    let mut pack = Pack { fuel };
    let mut expected = Vec::with_capacity(inputs.len());
    for input in &inputs {
        let (moved, next, thrusting) = live_step(
            state,
            input,
            super::TOP_SPEED,
            super::DT_LIVE,
            arena,
            super::BODY_HEIGHT,
            &[],
            pack,
            ceiling,
        );
        state = moved;
        pack = next;
        expected.push(GoldenStep {
            state,
            fuel: pack.fuel,
            thrusting,
        });
    }
    GoldenCase {
        name: name.into(),
        arena: arena.clone(),
        start,
        fuel,
        ceiling,
        speed: super::TOP_SPEED,
        inputs,
        expected,
    }
}

/// Lift from the floor, the burn to empty and refill, forward flight onto a
/// gallery, a head strike under a slab and the authored ceiling.
pub fn golden_cases() -> GoldenFile {
    use super::Solid;
    let at = |x: f32, y: f32| MoveState {
        x,
        z: 0.0,
        y,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let held = |jump: bool, forward: bool| MoveInput {
        forward,
        jump,
        ..MoveInput::default()
    };
    let flat = Arena {
        half: 30.0,
        solids: Vec::new(),
    };
    let gallery = Arena {
        half: 30.0,
        solids: vec![Solid::from_center_top(14.0, 0.0, 9.0, 4.0, 4.5)],
    };
    let slab = Arena {
        half: 30.0,
        solids: vec![Solid::from_center_volume(0.0, 0.0, 3.0, 3.0, 4.0, 4.4)],
    };
    let mut burn = vec![held(true, false); 70];
    burn.extend(vec![held(false, false); 40]);
    let mut tap = vec![held(true, false)];
    tap.extend(vec![held(false, false); 20]);
    let mut flight = vec![held(true, true); 22];
    flight.extend(vec![held(false, true); 24]);
    GoldenFile {
        version: 1,
        dt: super::DT_LIVE,
        fuel_max: FUEL_MAX,
        refill_per_tick: REFILL_PER_TICK,
        thrust: THRUST,
        max_rise: MAX_RISE,
        cases: vec![
            case(
                "tap_is_an_ordinary_jump",
                &flat,
                at(0.0, 0.0),
                FUEL_MAX,
                DEFAULT_CEILING,
                tap,
            ),
            case(
                "burn_to_empty_then_refill",
                &flat,
                at(0.0, 0.0),
                FUEL_MAX,
                DEFAULT_CEILING,
                burn,
            ),
            case(
                "flight_onto_gallery",
                &gallery,
                at(0.0, 0.0),
                FUEL_MAX,
                DEFAULT_CEILING,
                flight,
            ),
            case(
                "head_strike_under_slab",
                &slab,
                at(0.0, 0.0),
                FUEL_MAX,
                DEFAULT_CEILING,
                vec![held(true, false); 30],
            ),
            case(
                "authored_ceiling",
                &flat,
                at(0.0, 0.0),
                FUEL_MAX,
                3.0,
                vec![held(true, false); 40],
            ),
            case(
                "empty_pack_cannot_lift",
                &flat,
                at(0.0, 0.0),
                0,
                DEFAULT_CEILING,
                vec![held(true, false); 12],
            ),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::{Solid, BODY_HEIGHT, DT_LIVE, GRAVITY, JUMP_SPEED, TOP_SPEED};

    fn still(y: f32) -> MoveState {
        MoveState {
            x: 0.0,
            z: 0.0,
            y,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        }
    }

    fn step(state: MoveState, jump: bool, fuel: u16, arena: &Arena) -> (MoveState, Pack, bool) {
        live_step(
            state,
            &MoveInput {
                jump,
                ..MoveInput::default()
            },
            TOP_SPEED,
            DT_LIVE,
            arena,
            BODY_HEIGHT,
            &[],
            Pack { fuel },
            DEFAULT_CEILING,
        )
    }

    #[test]
    fn grounded_jump_is_unchanged_and_thrust_starts_only_in_the_air() {
        let arena = Arena {
            half: 20.0,
            solids: Vec::new(),
        };
        let (first, pack, thrust) = step(still(0.0), true, FUEL_MAX, &arena);
        let plain = crate::movement::live_step(
            still(0.0),
            &MoveInput {
                jump: true,
                ..MoveInput::default()
            },
            TOP_SPEED,
            DT_LIVE,
            &arena,
        );
        assert_eq!(first, plain, "the ground jump is the ordinary jump");
        assert!(!thrust);
        assert_eq!(pack.fuel, FUEL_MAX);
        assert_eq!(first.vy, JUMP_SPEED, "takeoff keeps the full jump speed");
        // Still rising faster than the cap: thrust burns but never slows it.
        let (second, pack, thrust) = step(first, true, pack.fuel, &arena);
        assert!(thrust && pack.fuel == FUEL_MAX - 1);
        assert!(second.vy >= first.vy - GRAVITY * DT_LIVE - 1e-5);
        // Once the jump slows, sustained thrust climbs at MAX_RISE.
        let mut state = second;
        let mut fuel = pack.fuel;
        for _ in 0..20 {
            let (next, pack, thrust) = step(state, true, fuel, &arena);
            assert!(thrust);
            state = next;
            fuel = pack.fuel;
        }
        assert!((state.vy - MAX_RISE).abs() < 1e-4, "{}", state.vy);
        assert_eq!(fuel, FUEL_MAX - 21);
    }

    #[test]
    fn fuel_runs_out_in_three_seconds_and_refills_only_on_support() {
        let arena = Arena {
            half: 20.0,
            solids: Vec::new(),
        };
        let mut state = still(0.0);
        let mut fuel = FUEL_MAX;
        let mut burned = 0;
        let mut ticks = 0;
        while fuel > 0 {
            let (next, pack, thrust) = step(state, true, fuel, &arena);
            burned += u32::from(thrust);
            state = next;
            fuel = pack.fuel;
            ticks += 1;
            assert!(ticks <= 120, "sixty burning steps, with ceiling pauses");
        }
        assert_eq!(burned, u32::from(FUEL_MAX));
        // Falling with an empty pack: held jump gives no thrust and the air
        // never refills it.
        assert!(state.y > 0.0);
        let mut landed = None;
        for tick in 0..200 {
            let (next, pack, thrust) = step(state, landed.is_none(), fuel, &arena);
            if landed.is_none() {
                assert!(!thrust, "an empty pack cannot thrust");
                if next.y > 0.0 {
                    assert_eq!(pack.fuel, 0, "no refill aloft");
                } else {
                    landed = Some(tick);
                }
            }
            state = next;
            fuel = pack.fuel;
            if fuel == FUEL_MAX {
                // Twenty supported ticks at three a tick fill sixty.
                assert_eq!(tick - landed.unwrap(), 19);
                break;
            }
        }
        assert!(landed.is_some());
        assert_eq!(fuel, FUEL_MAX);
    }

    #[test]
    fn the_ceiling_and_a_slab_overhead_stop_the_climb() {
        let flat = Arena {
            half: 20.0,
            solids: Vec::new(),
        };
        let mut state = still(0.0);
        let mut fuel = FUEL_MAX;
        for _ in 0..60 {
            let (next, pack, _) = live_step(
                state,
                &MoveInput {
                    jump: true,
                    ..MoveInput::default()
                },
                TOP_SPEED,
                DT_LIVE,
                &flat,
                BODY_HEIGHT,
                &[],
                Pack { fuel },
                3.0,
            );
            assert!(next.y <= 3.0 + 1e-5, "{}", next.y);
            state = next;
            fuel = pack.fuel;
        }
        assert!(state.y > 2.5);
        let slab = Arena {
            half: 20.0,
            solids: vec![Solid::from_center_volume(0.0, 0.0, 2.0, 2.0, 4.0, 4.5)],
        };
        let mut state = still(0.0);
        let mut fuel = FUEL_MAX;
        for _ in 0..40 {
            let (next, pack, _) = step(state, true, fuel, &slab);
            assert!(next.y + BODY_HEIGHT <= 4.0 + 1e-4);
            state = next;
            fuel = pack.fuel;
        }
    }

    #[test]
    fn shared_vectors_match_the_committed_golden_file() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join(GOLDEN_PATH);
        let generated = serde_json::to_string_pretty(&golden_cases()).unwrap() + "\n";
        if std::env::var_os("FRAGR_UPDATE_JETPACK_VECTORS").is_some() {
            std::fs::write(&path, &generated).unwrap();
        }
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            generated,
            "regenerate with FRAGR_UPDATE_JETPACK_VECTORS=1"
        );
        let file = golden_cases();
        let flight = &file.cases[2];
        assert!(
            flight.expected.iter().any(|step| step.state.y == 4.5),
            "the flight case lands on the gallery"
        );
    }
}
