use super::*;
use crate::protocol::{M11MapGeometry, M11_OBJECTIVE_IDS};

impl MissionClient {
    pub fn replace_map_with_m11(
        &mut self,
        geometry: Option<&M11MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m11_map = None;
            self.m11_point = None;
            self.m11_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m07_map.is_some()
            || self.m09_map.is_some()
            || self.m10_map.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m05_map.is_some()
            || self.m06_map.is_some()
            || self.m08_map.is_some()
        {
            return Err("M11 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if self.m11_map.as_ref().is_some_and(|old| old != g) {
            return Err("M11 static map contract changed");
        }
        self.m11_point = g
            .departure
            .point(presentation.ok_or("M11 presentation missing")?, solids);
        self.m11_map = Some(g.clone());
        self.m11_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m11_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m11_map.as_ref().ok_or("M11 geometry missing")?;
        let f = state.m11.as_ref().ok_or("M11 facts missing")?;
        let i = f.completed.len();
        let expected = match i.cmp(&M11_OBJECTIVE_IDS.len()) {
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
            return Err("M11 objective disagrees with map");
        }
        if let Some(old) = self
            .state
            .as_ref()
            .filter(|s| s.id == state.id && s.attempt == state.attempt)
        {
            let old_f = old.m11.as_ref().ok_or("M11 prior facts missing")?;
            if f.completed.len() < old_f.completed.len()
                || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing
                || state.changed_at < old.changed_at
                || old_f.challenges.transfer_released && !f.challenges.transfer_released
                || old_f.challenges.records_read && !f.challenges.records_read
                || f.challenges.counter_boarder_blast_kills
                    < old_f.challenges.counter_boarder_blast_kills
                || old_f.challenges.counter_boarding_started.is_some()
                    && old_f.challenges.counter_boarding_started
                        != f.challenges.counter_boarding_started
                || old_f.challenges.bridge_taken_at.is_some()
                    && old_f.challenges.bridge_taken_at != f.challenges.bridge_taken_at
            {
                return Err("M11 attempt facts moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m11(
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
            .and_then(|s| s.m11.as_ref())
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
                let Some(point) = self.m11_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
