use super::*;
use crate::protocol::M18MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m18(
        &mut self,
        geometry: Option<&M18MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m18_map = None;
            self.m18_points = None;
            self.m18_pending = false;
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
            || self.m17_map.is_some()
        {
            return Err("M18 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m18_map {
            let mut same = old.clone();
            same.roadblock_active = g.roadblock_active;
            same.concourse_evac_completed = g.concourse_evac_completed;
            if &same != g {
                return Err("M18 static map contract changed");
            }
        }
        let present = presentation.ok_or("M18 presentation missing")?;
        self.m18_points = Some([
            g.depot_station
                .point(present, solids)
                .ok_or("M18 depot station missing")?,
            g.overlook_console
                .point(present, solids)
                .ok_or("M18 overlook console missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M18 departure missing")?,
        ]);
        self.m18_map = Some(g.clone());
        self.m18_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m18_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m18_map.as_ref().ok_or("M18 geometry missing")?;
        let f = state.m18.as_ref().ok_or("M18 facts missing")?;
        let done = f.completed.len();
        let expected = if done < 6 {
            Some(g.objectives[done].clone())
        } else if done == 6 {
            Some(g.departure_objective())
        } else {
            None
        };
        if f.current != expected {
            return Err("M18 objective disagrees with map");
        }
        if f.roadblock_active != g.roadblock_active
            || f.concourse_secured != g.concourse_evac_completed
        {
            return Err("M18 stage disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m18.as_ref().ok_or("M18 prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.challenges.aid_delivered && !f.challenges.aid_delivered
                    || old_f.challenges.square_defended && !f.challenges.square_defended
                    || old_f.challenges.collector_neutralized
                        && !f.challenges.collector_neutralized
                    || old_f.challenges.overlook_witnessed && !f.challenges.overlook_witnessed
                    || old_f.challenges.concourse_secured && !f.challenges.concourse_secured
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M18 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m18(
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
            .and_then(|s| s.m18.as_ref())
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
                let Some(points) = self.m18_points else {
                    return Action::default();
                };
                let point = match current.id.as_str() {
                    "aid_checkin" => points[0],
                    "overlook_recon" => points[1],
                    _ => points[2],
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            _ => Action::default(),
        }
    }
}
