use super::*;
use crate::protocol::{M05MapGeometry, M05TramPhase};
impl MissionClient {
    /// Reconstruct physical cover from the validated map and latest M05 pose.
    /// Other missions retain their existing immutable navigation geometry.
    pub fn live_visibility_solids(&self) -> Option<Vec<Solid>> {
        if self.m05_pending {
            return None;
        }
        let g = self.m05_map.as_ref()?;
        let f = self.state.as_ref()?.m05.as_ref()?;
        let mut solids = self.m05_solids.clone();
        let body = solids.get_mut(g.tram.solid)?;
        *body = g.tram.body(*body, f.tram.feet);
        Some(solids)
    }

    pub fn replace_map_with_m05(
        &mut self,
        geometry: Option<&M05MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m05_map = None;
            self.m05_solids.clear();
            self.m05_point = None;
            self.m05_pending = false;
            return Ok(());
        };
        if self.m07_map.is_some()
            || self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m04_map.is_some()
            || self.m06_map.is_some()
        {
            return Err("M05 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m05_map {
            let mut stable = old.clone();
            stable.freight_open = g.freight_open;
            if stable != *g {
                return Err("M05 static map contract changed");
            }
        }
        self.m05_point = g
            .departure
            .point(presentation.ok_or("M05 presentation missing")?, solids);
        self.m05_map = Some(g.clone());
        self.m05_solids = solids.to_vec();
        self.m05_pending = true;
        self.press_down = false;
        Ok(())
    }
    pub(super) fn validate_m05_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m05_map.as_ref().ok_or("M05 geometry missing")?;
        let f = state.m05.as_ref().ok_or("M05 facts missing")?;
        let index = f.completed.len();
        let expected = if index < 6 {
            Some(g.objectives[index].clone())
        } else if index == 6 {
            Some(crate::protocol::MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: g.departure.clone(),
                },
            })
        } else {
            None
        };
        if f.current != expected
            || f.freight_open != g.freight_open
            || f.captives.len() != g.rescue.captives.len()
            || !g.tram.valid_pose(&f.tram)
        {
            return Err("M05 facts disagree with map");
        }
        for (c, d) in f.captives.iter().zip(&g.rescue.captives) {
            if c.id != d.id
                || !f.group_released && c.feet != d.held
                || super::m04::route_progress(&d.route, c.feet).is_none()
            {
                return Err("M05 captive left registered route");
            }
        }
        if let Some(old) = self
            .state
            .as_ref()
            .filter(|s| s.attempt == state.attempt)
            .and_then(|s| s.m05.as_ref())
        {
            let maximum_travel = g.tram.speed
                * (f.tram.tick.saturating_sub(old.tram.tick) as f32)
                * crate::movement::DT_LIVE
                + 0.001;
            if f.completed.len() < old.completed.len()
                || old.freight_open && !f.freight_open
                || old.workshop_secured && !f.workshop_secured
                || old.group_released && !f.group_released
                || f.tram.tick < old.tram.tick
                || (f.tram.feet[2] - old.tram.feet[2]) * (g.tram.end[2] - g.tram.start[2]) < -0.001
                || (old.tram.phase == M05TramPhase::Arrived
                    && f.tram.phase != M05TramPhase::Arrived)
                || (f.tram.feet[2] - old.tram.feet[2]).abs() > maximum_travel
                || matches!(
                    old.tram.phase,
                    M05TramPhase::Moving | M05TramPhase::Blocked | M05TramPhase::Arrived
                ) && matches!(f.tram.phase, M05TramPhase::Parked | M05TramPhase::Boarding)
            {
                return Err("M05 attempt facts moved backwards");
            }
            for ((old, c), d) in old.captives.iter().zip(&f.captives).zip(&g.rescue.captives) {
                if super::m04::route_progress(&d.route, c.feet).unwrap_or(0.0) + 0.05
                    < super::m04::route_progress(&d.route, old.feet).unwrap_or(0.0)
                {
                    return Err("M05 captive moved backwards");
                }
            }
        }
        if self.state.as_ref().is_some_and(|old| {
            old.attempt == state.attempt
                && old.phase != MissionPhase::Briefing
                && state.phase == MissionPhase::Briefing
        }) {
            return Err("M05 attempt returned to briefing");
        }
        if let Some(old) = self.state.as_ref().and_then(|s| s.m05.as_ref()) {
            if f.carried_recall_cars != old.carried_recall_cars
                || f.carried_patients != old.carried_patients
                || f.carried_photos != old.carried_photos
            {
                return Err("M05 carry changed");
            }
        }
        Ok(())
    }
    pub(super) fn steer_m05(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        if action.look_at.is_some() {
            self.press_down = false;
            let Some(solids) = self.live_visibility_solids() else {
                return Action::default();
            };
            return navigator
                .route_snapshot_with_visibility(world, id, snapshot, action, true, &solids);
        }
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let Some(f) = self.state.as_ref().and_then(|s| s.m05.as_ref()) else {
            return Action::default();
        };
        let Some(g) = self.m05_map.clone() else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let goal = if f.workshop_secured && !f.group_released {
            MissionObjectiveAction::Arrival {
                region: g.rescue.release.clone(),
                feet: g.rescue.captives[0].held,
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
                        throw_grenade: action.throw_grenade,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let Some(point) = self.m05_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
