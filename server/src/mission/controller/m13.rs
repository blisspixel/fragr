use super::*;
use crate::protocol::{M13LiftPhase, M13MapGeometry, M13_OBJECTIVE_IDS};

fn worker_progress(from: [f32; 3], to: [f32; 3], feet: [f32; 3]) -> Option<f32> {
    if from == to {
        return ((0..3).all(|i| (feet[i] - from[i]).abs() <= 0.05)).then_some(0.0);
    }
    super::m04::route_progress(&[from, to], feet)
}

impl MissionClient {
    pub fn replace_map_with_m13(
        &mut self,
        geometry: Option<&M13MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m13_map = None;
            self.m13_solids.clear();
            self.m13_points = None;
            self.m13_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
            || self.m06_map.is_some()
            || self.m07_map.is_some()
            || self.m08_map.is_some()
            || self.m09_map.is_some()
            || self.m10_map.is_some()
            || self.m11_map.is_some()
            || self.m12_map.is_some()
        {
            return Err("M13 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if self.m13_map.as_ref().is_some_and(|old| old != g) {
            return Err("M13 static geometry changed");
        }
        let present = presentation.ok_or("M13 presentation missing")?;
        self.m13_points = Some([
            g.release
                .point(present, solids)
                .ok_or("M13 release missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M13 departure missing")?,
        ]);
        self.m13_map = Some(g.clone());
        self.m13_solids = solids.to_vec();
        self.m13_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m13_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m13_map.as_ref().ok_or("M13 geometry missing")?;
        let f = state.m13.as_ref().ok_or("M13 facts missing")?;
        let count = f.completed.len();
        let expected = if count < M13_OBJECTIVE_IDS.len() {
            Some(g.objectives[count].clone())
        } else if count == M13_OBJECTIVE_IDS.len() {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected
            || f.hazard_phase != g.cycle.phase(f.lift.tick)
            || f.lift.top < g.parked_top - 0.001
            || f.lift.top > g.lift_top + 0.001
            || (f.lift.phase == M13LiftPhase::Parked && (f.lift.top - g.parked_top).abs() > 0.001)
            || (f.lift.phase == M13LiftPhase::Arrived && (f.lift.top - g.lift_top).abs() > 0.001)
        {
            return Err("M13 facts disagree with current map");
        }
        for (index, feet) in f.worker_feet.iter().enumerate() {
            let route = [g.workers[index], g.worker_destinations[index]];
            if worker_progress(route[0], route[1], *feet).is_none()
                || f.challenges.workers.is_none() && *feet != g.workers[index]
                || f.challenges.workers_arrived[index]
                    && (0..3).any(|axis| (feet[axis] - route[1][axis]).abs() > 0.05)
            {
                return Err("M13 worker left its registered route");
            }
        }
        if let Some(previous) = self
            .state
            .as_ref()
            .filter(|s| s.id == state.id && s.attempt == state.attempt)
        {
            let old = previous.m13.as_ref().ok_or("previous M13 facts missing")?;
            let maximum = f.lift.tick.saturating_sub(old.lift.tick) as f32
                * crate::movement::DT_LIVE
                * crate::protocol::M13_LIFT_SPEED
                + 0.001;
            if count < old.completed.len()
                || old.relay_disabled && !f.relay_disabled
                || old.overseer_surrendered && !f.overseer_surrendered
                || old.challenges.workers.is_some()
                    && old.challenges.workers != f.challenges.workers
                || old.challenges.hazard_hurt > f.challenges.hazard_hurt
                || old.challenges.supports_cleared && !f.challenges.supports_cleared
                || f.lift.tick < old.lift.tick
                || (f.lift.top - old.lift.top).abs() > maximum
                || previous.phase == MissionPhase::Departed
                    && (f.lift.top != old.lift.top
                        || f.lift.phase != old.lift.phase
                        || f.lift.returning != old.lift.returning)
                || previous.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing
            {
                return Err("M13 attempt facts moved backwards or exceeded lift speed");
            }
            for index in 0..3 {
                let route = [g.workers[index], g.worker_destinations[index]];
                if old.challenges.workers_arrived[index] && !f.challenges.workers_arrived[index]
                    || worker_progress(route[0], route[1], f.worker_feet[index]).unwrap_or(0.0)
                        + 0.05
                        < worker_progress(route[0], route[1], old.worker_feet[index]).unwrap_or(0.0)
                {
                    return Err("M13 worker outcome or movement went backwards");
                }
            }
        }
        Ok(())
    }

    pub(super) fn m13_visibility_solids(&self) -> Option<Vec<Solid>> {
        if self.m13_pending {
            return None;
        }
        let g = self.m13_map.as_ref()?;
        let f = self.state.as_ref()?.m13.as_ref()?;
        let mut solids = self.m13_solids.clone();
        let deck = solids.get_mut(g.deck)?;
        deck.bottom += f.lift.top - deck.top;
        deck.top = f.lift.top;
        Some(solids)
    }

    pub(super) fn steer_m13(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        let Some(f) = self.state.as_ref().and_then(|s| s.m13.as_ref()) else {
            return Action::default();
        };
        // The deck carries the actor. Routing toward its final height would
        // walk off the platform while its actual world is still rising.
        if f.lift.phase != M13LiftPhase::Parked {
            self.press_down = false;
            navigator.clear();
            return Action::default();
        }
        if action.look_at.is_some() {
            self.press_down = false;
            let Some(solids) = self.m13_visibility_solids() else {
                return Action::default();
            };
            return navigator
                .route_snapshot_with_visibility(world, id, snapshot, action, true, &solids);
        }
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let Some(g) = self.m13_map.clone() else {
            return Action::default();
        };
        let Some(points) = self.m13_points else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let goal = if f.completed.len() == M13_OBJECTIVE_IDS.len() {
            MissionObjectiveAction::Use {
                target: g.departure.clone(),
            }
        } else if f.overseer_surrendered && f.challenges.workers.is_none() {
            MissionObjectiveAction::Use {
                target: g.release.clone(),
            }
        } else {
            let Some(current) = &f.current else {
                return Action::default();
            };
            current.action.clone()
        };
        match goal {
            MissionObjectiveAction::Arrival {
                feet: destination, ..
            } => {
                self.press_down = false;
                navigator.steer(
                    world,
                    feet,
                    NavigationGoal {
                        feet: destination,
                        combat: false,
                    },
                    Action {
                        weapon_swap: action.weapon_swap,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let point = points[usize::from(target == g.departure)];
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { approach, aim, .. } => {
                self.press_down = false;
                let near = (0..3)
                    .map(|axis| (feet[axis] - approach[axis]).powi(2))
                    .sum::<f32>()
                    <= 0.45_f32.powi(2);
                let wanted = Action {
                    weapon_swap: action.weapon_swap,
                    fire: near && !action.reload,
                    reload: action.reload,
                    look_at: Some(LookAt {
                        x: Some(aim[0]),
                        y: Some(aim[1]),
                        z: Some(aim[2]),
                        player_id: None,
                    }),
                    ..Action::default()
                };
                if near {
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
        }
    }
}
