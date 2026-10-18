use super::*;
use crate::protocol::M16MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m16(
        &mut self,
        geometry: Option<&M16MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m16_map = None;
            self.m16_points = None;
            self.m16_pending = false;
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
        {
            return Err("M16 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m16_map {
            let mut same = old.clone();
            same.checkpoint_lifted = g.checkpoint_lifted;
            same.doors_open = g.doors_open;
            if &same != g {
                return Err("M16 static map contract changed");
            }
        }
        let present = presentation.ok_or("M16 presentation missing")?;
        self.m16_points = Some([
            g.bus_release
                .point(present, solids)
                .ok_or("M16 bus release missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M16 departure missing")?,
        ]);
        self.m16_map = Some(g.clone());
        self.m16_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m16_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m16_map.as_ref().ok_or("M16 geometry missing")?;
        let f = state.m16.as_ref().ok_or("M16 facts missing")?;
        let done = f.completed.len();
        let expected = if done < 6 {
            Some(g.objectives[done].clone())
        } else if done == 6 {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected {
            return Err("M16 objective disagrees with map");
        }
        if f.checkpoint_lifted != g.checkpoint_lifted || f.doors_open != g.doors_open {
            return Err("M16 stage disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m16.as_ref().ok_or("M16 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.challenges.ride_started && !f.challenges.ride_started
                    || old_f.challenges.green_wave_triggered && !f.challenges.green_wave_triggered
                    || old_f.challenges.bus_freed && !f.challenges.bus_freed
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M16 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m16(
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
            .and_then(|s| s.m16.as_ref())
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
                let Some(points) = self.m16_points else {
                    return Action::default();
                };
                let point = match current.id.as_str() {
                    "bus_freed" => points[0],
                    _ => points[1],
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            _ => Action::default(),
        }
    }
}
