//! Surface swimming reuses ordinary collision. Mirrored by WaterMovement.
use super::{Arena, MoveInput, MoveState};
use crate::protocol::WaterRegion;

pub const SWIM_DRAFT: f32 = 0.9;
pub const SWIM_SPEED: f32 = 3.2;

/// The same buoyant floor must survive later actor-contact projection.
pub(crate) fn append_support(arena: &mut Arena, regions: &[WaterRegion]) {
    for region in regions {
        let top = region.level - SWIM_DRAFT;
        let bottom = region.level - region.depth;
        if top > bottom {
            arena.solids.push(super::Solid {
                min_x: region.min[0],
                max_x: region.max[0],
                min_z: region.min[1],
                max_z: region.max[1],
                bottom,
                top,
            });
        }
    }
}

pub fn live_step(
    mut state: MoveState,
    input: &MoveInput,
    speed: f32,
    dt: f32,
    arena: &Arena,
    height: f32,
    regions: &[WaterRegion],
) -> MoveState {
    if regions.is_empty() {
        return super::live_step_with_height(state, input, speed, dt, arena, height);
    }
    let water = regions
        .iter()
        .find(|water| water.contains(state.x, state.z));
    let swimming = water.is_some_and(|water| {
        state.y < water.level - 0.25
            && arena.support_height(state.x, state.z, state.y + super::STEP_UP)
                < water.level - SWIM_DRAFT
    });
    let travel = if swimming {
        speed.min(SWIM_SPEED)
    } else {
        speed
    };
    // Buoyancy must also be a support surface for the ordinary step-up rule.
    // A post-step height clamp alone leaves a swimmer permanently airborne at a shore.
    let mut supported = arena.clone();
    append_support(&mut supported, regions);
    if let Some(water) = water {
        let surface_feet = water.level - SWIM_DRAFT;
        if state.y < surface_feet
            && !arena.blocked_body_at(state.x, state.z, surface_feet, surface_feet)
        {
            state.y = surface_feet;
            state.vy = state.vy.max(0.0);
        }
    }
    let mut moved = super::live_step_with_height(state, input, travel, dt, &supported, height);
    if let Some(water) = regions
        .iter()
        .find(|water| water.contains(moved.x, moved.z))
    {
        let surface_feet = water.level - SWIM_DRAFT;
        let floor = arena.support_height(moved.x, moved.z, moved.y + super::STEP_UP);
        if floor < surface_feet
            && moved.y < surface_feet
            && !arena.blocked_body_at(moved.x, moved.z, surface_feet, surface_feet)
        {
            moved.y = surface_feet;
            moved.vy = 0.0;
        }
    }
    moved
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::{Solid, BODY_HEIGHT, DT_LIVE};

    #[test]
    fn shared_swim_vectors_match_native_contract() {
        let document: serde_json::Value =
            serde_json::from_str(include_str!("../../../client/golden/water_vectors.json"))
                .unwrap();
        assert_eq!(document["version"], 1);
        for case in document["vectors"].as_array().unwrap() {
            let mut state: MoveState = serde_json::from_value(case["initial"].clone()).unwrap();
            let expected: MoveState = serde_json::from_value(case["expected"].clone()).unwrap();
            let input: MoveInput = serde_json::from_value(case["input"].clone()).unwrap();
            let arena: Arena = serde_json::from_value(case["arena"].clone()).unwrap();
            let water: Vec<WaterRegion> =
                serde_json::from_value(case["water_regions"].clone()).unwrap();
            for _ in 0..case["steps"].as_u64().unwrap() {
                state = live_step(
                    state,
                    &input,
                    case["speed"].as_f64().unwrap() as f32,
                    case["dt"].as_f64().unwrap() as f32,
                    &arena,
                    case["body_height"].as_f64().unwrap() as f32,
                    &water,
                );
            }
            for (a, b) in [
                state.x, state.y, state.z, state.vx, state.vy, state.vz, state.yaw,
            ]
            .into_iter()
            .zip([
                expected.x,
                expected.y,
                expected.z,
                expected.vx,
                expected.vy,
                expected.vz,
                expected.yaw,
            ]) {
                assert!(
                    (a - b).abs() < 0.001,
                    "{} native{a} fixture{b}",
                    case["name"]
                );
            }
        }
    }

    #[test]
    fn swimmer_floats_above_real_seabed_and_reaches_a_shore_step() {
        let arena = Arena {
            half: 20.0,
            solids: vec![Solid::from_center_top(5.0, 0.0, 1.0, 5.0, 1.8)],
        };
        let water = [WaterRegion {
            min: [-20.0, -20.0],
            max: [20.0, 20.0],
            level: 2.2,
            depth: 2.2,
        }];
        let mut state = MoveState {
            x: 0.0,
            y: 0.0,
            z: 0.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        let input = MoveInput {
            forward: true,
            ..Default::default()
        };
        for _ in 0..25 {
            state = live_step(state, &input, 5.0, DT_LIVE, &arena, BODY_HEIGHT, &water);
        }
        assert!(state.x > 3.5 && state.y >= 1.8, "{state:?}");
    }

    #[test]
    fn empty_water_contract_matches_existing_step_exactly() {
        let arena = Arena {
            half: 20.0,
            solids: Vec::new(),
        };
        let state = MoveState {
            x: 0.0,
            y: 0.0,
            z: 0.0,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        let input = MoveInput {
            forward: true,
            jump: true,
            ..Default::default()
        };
        assert_eq!(
            live_step(state, &input, 5.0, DT_LIVE, &arena, BODY_HEIGHT, &[]),
            super::super::live_step_with_height(state, &input, 5.0, DT_LIVE, &arena, BODY_HEIGHT)
        );
    }
}
