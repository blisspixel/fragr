use super::*;
use crate::protocol::M17MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m17(
        &mut self,
        geometry: Option<&M17MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m17_map = None;
            self.m17_points = None;
            self.m17_pending = false;
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
            || self.m13_map.is_some()
            || self.m14_map.is_some()
            || self.m15_map.is_some()
            || self.m16_map.is_some()
        {
            return Err("M17 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m17_map {
            let mut same = old.clone();
            same.core_unsealed = g.core_unsealed;
            same.voss_captured = g.voss_captured;
            if &same != g {
                return Err("M17 static map contract changed");
            }
        }
        let present = presentation.ok_or("M17 presentation missing")?;
        self.m17_points = Some([
            g.kessel_desk
                .point(present, solids)
                .ok_or("M17 kessel desk missing")?,
            g.core_override
                .point(present, solids)
                .ok_or("M17 core override missing")?,
            g.voss_rostrum
                .point(present, solids)
                .ok_or("M17 voss rostrum missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M17 departure missing")?,
        ]);
        self.m17_map = Some(g.clone());
        self.m17_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m17_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m17_map.as_ref().ok_or("M17 geometry missing")?;
        let f = state.m17.as_ref().ok_or("M17 facts missing")?;
        let done = f.completed.len();
        let expected = if done < 6 {
            Some(g.objectives[done].clone())
        } else if done == 6 {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected {
            return Err("M17 objective disagrees with map");
        }
        if f.core_unsealed != g.core_unsealed || f.voss_captured != g.voss_captured {
            return Err("M17 stage disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m17.as_ref().ok_or("M17 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.challenges.approach_breached && !f.challenges.approach_breached
                    || old_f.challenges.kessel_secured && !f.challenges.kessel_secured
                    || old_f.challenges.core_defeated && !f.challenges.core_defeated
                    || old_f.challenges.voss_captured && !f.challenges.voss_captured
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M17 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m17(
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
        let Some(current) = self
            .state
            .as_ref()
            .and_then(|s| s.m17.as_ref())
            .and_then(|f| f.current.as_ref())
        else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        match current.action.clone() {
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
                        throw_grenade: action.throw_grenade,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let Some(points) = self.m17_points else {
                    return Action::default();
                };
                let point = match current.id.as_str() {
                    "kessel_secured" => points[0],
                    "core_unsealed" => points[1],
                    "voss_captured" => points[2],
                    _ => points[3],
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            _ => Action::default(),
        }
    }
}
