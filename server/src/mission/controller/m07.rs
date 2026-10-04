use super::*;
use crate::protocol::{M07MapGeometry, M07_OBJECTIVE_IDS};

impl MissionClient {
    pub fn replace_map_with_m07(
        &mut self,
        geometry: Option<&M07MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m07_map = None;
            self.m07_point = None;
            self.m07_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
            || self.m06_map.is_some()
            || self.m08_map.is_some()
        {
            return Err("M07 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if self.m07_map.as_ref().is_some_and(|old| old != g) {
            return Err("M07 static map contract changed");
        }
        self.m07_point = g
            .departure
            .point(presentation.ok_or("M07 presentation missing")?, solids);
        self.m07_map = Some(g.clone());
        self.m07_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m07_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m07_map.as_ref().ok_or("M07 geometry missing")?;
        let f = state.m07.as_ref().ok_or("M07 facts missing")?;
        let i = f.completed.len();
        let expected = match i.cmp(&M07_OBJECTIVE_IDS.len()) {
            std::cmp::Ordering::Less => Some(g.objectives[i].clone()),
            std::cmp::Ordering::Equal => Some(crate::protocol::MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            }),
            std::cmp::Ordering::Greater => None,
        };
        if f.current != expected {
            return Err("M07 objective disagrees with map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m07.as_ref().ok_or("M07 prior facts missing")?;
            if old_f.carried_recall_cars != f.carried_recall_cars
                || old_f.carried_patients != f.carried_patients
                || old_f.carried_photos != f.carried_photos
                || old_f.carried_released_workers != f.carried_released_workers
                || old_f.carried_evacuated_workers != f.carried_evacuated_workers
                || old_f.carried_prisoner_route_marked != f.carried_prisoner_route_marked
            {
                return Err("M07 carry changed");
            }
            if old.attempt == state.attempt
                && (f.completed.len() < old_f.completed.len()
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M07 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m07(
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
            .and_then(|s| s.m07.as_ref())
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
                let Some(point) = self.m07_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
