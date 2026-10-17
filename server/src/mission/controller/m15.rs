use super::*;
use crate::protocol::M15MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m15(
        &mut self,
        geometry: Option<&M15MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m15_map = None;
            self.m15_points = None;
            self.m15_pending = false;
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
        {
            return Err("M15 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m15_map {
            let mut same = old.clone();
            same.tunnel_closed = g.tunnel_closed;
            same.gates_open = g.gates_open;
            if &same != g {
                return Err("M15 static map contract changed");
            }
        }
        let present = presentation.ok_or("M15 presentation missing")?;
        self.m15_points = Some([
            g.arming_crate
                .point(present, solids)
                .ok_or("M15 arming crate missing")?,
            g.booth_terminal
                .point(present, solids)
                .ok_or("M15 booth terminal missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M15 departure missing")?,
        ]);
        self.m15_map = Some(g.clone());
        self.m15_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m15_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m15_map.as_ref().ok_or("M15 geometry missing")?;
        let f = state.m15.as_ref().ok_or("M15 facts missing")?;
        let done = f.completed.len();
        let expected = if done < 6 {
            Some(g.objectives[done].clone())
        } else if done == 6 {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected {
            return Err("M15 objective disagrees with map");
        }
        if f.tunnel_closed != g.tunnel_closed || f.gates_open != g.gates_open {
            return Err("M15 stage disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m15.as_ref().ok_or("M15 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.broadcast_taken && !f.broadcast_taken
                    || old_f.challenges.pen_armed && !f.challenges.pen_armed
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M15 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m15(
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
            .and_then(|s| s.m15.as_ref())
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
                let Some(points) = self.m15_points else {
                    return Action::default();
                };
                let point = match current.id.as_str() {
                    "pen_armed" => points[0],
                    "broadcast_secured" => points[1],
                    _ => points[2],
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            _ => Action::default(),
        }
    }
}
