use super::*;
use crate::protocol::M06MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m06(
        &mut self,
        geometry: Option<&M06MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m06_map = None;
            self.m06_point = None;
            self.m06_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
        {
            return Err("M06 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if self.m06_map.as_ref().is_some_and(|old| old != g) {
            return Err("M06 static map contract changed");
        }
        self.m06_point = g
            .departure
            .point(presentation.ok_or("M06 presentation missing")?, solids);
        self.m06_map = Some(g.clone());
        self.m06_pending = true;
        self.press_down = false;
        Ok(())
    }
    pub(super) fn validate_m06_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m06_map.as_ref().ok_or("M06 geometry missing")?;
        let f = state.m06.as_ref().ok_or("M06 facts missing")?;
        let i = f.completed.len();
        let expected = if i < 6 {
            Some(g.objectives[i].clone())
        } else if i == 6 {
            Some(crate::protocol::MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            })
        } else {
            None
        };
        if f.current != expected {
            return Err("M06 objective disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m06.as_ref().ok_or("M06 prior facts missing")?;
            if old_f.carried_recall_cars != f.carried_recall_cars
                || old_f.carried_patients != f.carried_patients
                || old_f.carried_photos != f.carried_photos
                || old_f.carried_released_workers != f.carried_released_workers
                || old_f.carried_evacuated_workers != f.carried_evacuated_workers
            {
                return Err("M06 carry changed");
            }
            if old.attempt == state.attempt
                && (f.completed.len() < old_f.completed.len()
                    || old_f.prisoner_route_marked && !f.prisoner_route_marked
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M06 attempt moved backwards");
            }
        }
        Ok(())
    }
    pub(super) fn steer_m06(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        if action.look_at.is_some() {
            self.press_down = false;
            return navigator.steer_snapshot(world, id, snapshot, action);
        }
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let Some(current) = self
            .state
            .as_ref()
            .and_then(|s| s.m06.as_ref())
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
                let Some(point) = self.m06_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
