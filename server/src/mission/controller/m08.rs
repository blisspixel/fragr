use super::*;
use crate::protocol::{M08MapGeometry, M08_MACHINE_STEP, M08_OBJECTIVE_IDS};

impl MissionClient {
    pub fn replace_map_with_m08(
        &mut self,
        geometry: Option<&M08MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m08_map = None;
            self.m08_point = None;
            self.m08_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
            || self.m06_map.is_some()
            || self.m07_map.is_some()
        {
            return Err("M08 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m08_map {
            // Only the two stage flags may move: forward with the world, and
            // back to the sealed stage on a retry. The facts must then agree.
            let mut same = old.clone();
            same.seal_open = g.seal_open;
            same.machine_fallen = g.machine_fallen;
            if &same != g {
                return Err("M08 static map contract changed");
            }
        }
        self.m08_point = g
            .departure
            .point(presentation.ok_or("M08 presentation missing")?, solids);
        self.m08_map = Some(g.clone());
        self.m08_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m08_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m08_map.as_ref().ok_or("M08 geometry missing")?;
        let f = state.m08.as_ref().ok_or("M08 facts missing")?;
        let done = f.completed.len();
        let expected = if done <= M08_OBJECTIVE_IDS.len() {
            g.step(done, &f.node_hp)
        } else {
            None
        };
        if f.current != expected {
            return Err("M08 objective disagrees with map");
        }
        if f.seal_open != g.seal_open || f.machine_fallen != g.machine_fallen {
            return Err("M08 stage disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m08.as_ref().ok_or("M08 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.custody_released && !f.custody_released
                    || old_f.recovered_mind_secured && !f.recovered_mind_secured
                    || old_f.node_hp.iter().zip(&f.node_hp).any(|(a, b)| b > a)
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M08 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m08(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        if action.look_at.is_some() {
            self.press_down = false;
            return navigator.route_snapshot_with_visibility(
                world,
                id,
                snapshot,
                action,
                true,
                &world.planning_arena().solids,
            );
        }
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let Some(facts) = self.state.as_ref().and_then(|s| s.m08.as_ref()) else {
            return Action::default();
        };
        let Some(current) = facts.current.clone() else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let distance = |goal: [f32; 3]| {
            (0..3)
                .map(|i| (feet[i] - goal[i]).powi(2))
                .sum::<f32>()
                .sqrt()
        };
        match current.action {
            MissionObjectiveAction::Arrival {
                feet: destination,
                region,
            } => {
                self.press_down = false;
                // The mine lesson: once inside the one-entrance alcove with no
                // live mine of its own, throw one at the mouth and hold.
                let lesson = facts.completed.len() == 2
                    && region.contains(feet)
                    && !snapshot.mines.iter().any(|mine| mine.owner_id == id);
                if lesson {
                    self.press_down = !self.press_down;
                    navigator.clear();
                    return Action {
                        weapon_swap: action.weapon_swap,
                        // Alternate presses so each one is a fresh rising edge.
                        place_mine: self.press_down,
                        look_at: Some(LookAt {
                            x: Some(-11.0),
                            y: Some(feet[1] + 0.2),
                            z: Some(18.0),
                            player_id: None,
                        }),
                        ..Action::default()
                    };
                }
                navigator.steer(
                    world,
                    feet,
                    NavigationGoal {
                        feet: destination,
                        combat: false,
                    },
                    Action {
                        weapon_swap: action.weapon_swap,
                        throw_grenade: action.throw_grenade,
                        place_mine: action.place_mine,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Shoot { approach, aim, .. } => {
                self.press_down = false;
                let close = distance(approach) <= 0.45;
                let wanted = Action {
                    weapon_swap: action.weapon_swap,
                    fire: close && facts.completed.len() == M08_MACHINE_STEP,
                    look_at: Some(LookAt {
                        x: Some(aim[0]),
                        y: Some(aim[1]),
                        z: Some(aim[2]),
                        player_id: None,
                    }),
                    ..Action::default()
                };
                if close {
                    navigator.clear();
                    wanted
                } else {
                    navigator.steer(
                        world,
                        feet,
                        NavigationGoal {
                            feet: approach,
                            combat: false,
                        },
                        wanted,
                        snapshot.tick,
                        true,
                    )
                }
            }
            MissionObjectiveAction::Use { target } => {
                let Some(point) = self.m08_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
        }
    }
}
