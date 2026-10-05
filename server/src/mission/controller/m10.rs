use super::*;
use crate::protocol::{M10MapGeometry, M10_OBJECTIVE_IDS};

impl MissionClient {
    pub fn replace_map_with_m10(
        &mut self,
        geometry: Option<&M10MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m10_map = None;
            self.m10_point = None;
            self.m10_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m07_map.is_some()
            || self.m09_map.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
            || self.m06_map.is_some()
            || self.m08_map.is_some()
        {
            return Err("M10 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if self.m10_map.as_ref().is_some_and(|old| old != g) {
            return Err("M10 static map contract changed");
        }
        self.m10_point = g
            .departure
            .point(presentation.ok_or("M10 presentation missing")?, solids);
        self.m10_map = Some(g.clone());
        self.m10_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m10_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m10_map.as_ref().ok_or("M10 geometry missing")?;
        let f = state.m10.as_ref().ok_or("M10 facts missing")?;
        let i = f.completed.len();
        let expected = match i.cmp(&M10_OBJECTIVE_IDS.len()) {
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
            return Err("M10 objective disagrees with map");
        }
        let expected: Vec<_> = g
            .passengers
            .iter()
            .filter(|p| f.transit.arrived(&p.id))
            .cloned()
            .collect();
        if f.pilot != g.pilot || f.passengers != expected {
            return Err("M10 current crew do not match the authored ship");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old.m10.as_ref().ok_or("M10 prior facts missing")?;
            if old_f.transit != f.transit
                || old_f.carried_archive != f.carried_archive
                || old_f.pilot != f.pilot
                || old_f.passengers != f.passengers
            {
                return Err("M10 carried history or current crew changed");
            }
            if old.attempt == state.attempt
                && (f.completed.len() < old_f.completed.len()
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M10 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m10(
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
            .and_then(|s| s.m10.as_ref())
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
                let Some(point) = self.m10_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
