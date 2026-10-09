use super::*;
use crate::protocol::{M12MapGeometry, M12_OBJECTIVE_IDS};
impl MissionClient {
    pub fn replace_map_with_m12(
        &mut self,
        geometry: Option<&M12MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m12_map = None;
            self.m12_points = None;
            self.m12_pending = false;
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
        {
            return Err("M12 cannot share other mission geometry");
        }
        g.validate(half, solids, presentation)?;
        if self.m12_map.as_ref().is_some_and(|old| {
            let mut old = old.clone();
            old.shelter_open = g.shelter_open;
            old != *g
        }) {
            return Err("M12 static geometry changed");
        }
        let present = presentation.ok_or("M12 presentation missing")?;
        self.m12_points = Some([
            g.commitment
                .point(present, solids)
                .ok_or("M12 commitment missing")?,
            g.departure
                .point(present, solids)
                .ok_or("M12 departure missing")?,
        ]);
        self.m12_map = Some(g.clone());
        self.m12_pending = true;
        self.press_down = false;
        Ok(())
    }
    pub(super) fn validate_m12_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m12_map.as_ref().ok_or("M12 geometry missing")?;
        let f = state.m12.as_ref().ok_or("M12 facts missing")?;
        let n = f.completed.len();
        let expected = if n < M12_OBJECTIVE_IDS.len() {
            Some(g.objectives[n].clone())
        } else if n == 6 {
            Some(crate::protocol::MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            })
        } else {
            None
        };
        if f.current != expected || f.challenges.shelter_opened != g.shelter_open {
            return Err("M12 facts disagree with current map");
        }
        if let Some(old) = self
            .state
            .as_ref()
            .filter(|old| old.id == state.id && old.attempt == state.attempt)
            .and_then(|s| s.m12.as_ref())
        {
            let a = &old.challenges;
            let b = &f.challenges;
            if n < old.completed.len()
                || a.shelter_opened && !b.shelter_opened
                || a.workers_released && !b.workers_released
                || (0..2).any(|i| b.pump_health[i] > a.pump_health[i])
                || b.assessor_wreck_union_kills < a.assessor_wreck_union_kills
                || a.first_pump_damage_at.is_some()
                    && a.first_pump_damage_at != b.first_pump_damage_at
                || a.shelter_route_secured_at.is_some()
                    && a.shelter_route_secured_at != b.shelter_route_secured_at
                || !old.aid_vehicle_ids.is_empty() && old.aid_vehicle_ids != f.aid_vehicle_ids
            {
                return Err("M12 attempt facts moved backwards");
            }
        }
        Ok(())
    }
    pub(super) fn steer_m12(
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
            .and_then(|s| s.m12.as_ref())
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
                let Some(points) = self.m12_points else {
                    return Action::default();
                };
                let point = points[usize::from(current.id == "party_departed")];
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            _ => Action::default(),
        }
    }
}
