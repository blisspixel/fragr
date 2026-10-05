use super::*;
use crate::protocol::M04MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m04(
        &mut self,
        geometry: Option<&M04MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m04_map = None;
            self.m04_points = None;
            self.m04_pending = false;
            return Ok(());
        };
        if self.m07_map.is_some()
            || self.m09_map.is_some()
            || self.m10_map.is_some()
            || self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m06_map.is_some()
        {
            return Err("M04 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m04_map {
            let mut stable = old.clone();
            stable.clinic_open = g.clinic_open;
            if stable != *g {
                return Err("M04 static map contract changed");
            }
        }
        let p = presentation.ok_or("M04 presentation missing")?;
        self.m04_points = Some([
            g.clinic
                .control
                .point(p, solids)
                .ok_or("M04 clinic control missing")?,
            g.departure
                .point(p, solids)
                .ok_or("M04 departure missing")?,
        ]);
        self.m04_map = Some(g.clone());
        self.m04_pending = true;
        self.press_down = false;
        Ok(())
    }
    pub(super) fn validate_m04_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m04_map.as_ref().ok_or("M04 geometry missing")?;
        let f = state.m04.as_ref().ok_or("M04 facts missing")?;
        if self.state.as_ref().is_some_and(|old| {
            old.attempt == state.attempt
                && old.phase != MissionPhase::Briefing
                && state.phase == MissionPhase::Briefing
        }) {
            return Err("M04 attempt returned to briefing");
        }
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
            || f.clinic_open != g.clinic_open
            || f.patients.len() != g.patients.len()
        {
            return Err("M04 objective or clinic state disagrees with map");
        }
        for (patient, definition) in f.patients.iter().zip(&g.patients) {
            if patient.id != definition.id
                || (!f.patients_released
                    && (0..3).any(|i| (patient.feet[i] - definition.held[i]).abs() > 0.01))
                || route_progress(&definition.route, patient.feet).is_none()
            {
                return Err("M04 patient left its registered route");
            }
        }
        if let Some(old) = self
            .state
            .as_ref()
            .filter(|old| old.attempt == state.attempt)
            .and_then(|old| old.m04.as_ref())
        {
            if f.completed.len() < old.completed.len()
                || old.clinic_secured && !f.clinic_secured
                || old.clinic_open && !f.clinic_open
                || old.patients_released && !f.patients_released
                || f.photos_completed < old.photos_completed
                || f.carried_recall_cars != old.carried_recall_cars
            {
                return Err("M04 attempt facts moved backwards");
            }
            for ((previous, current), route) in
                old.patients.iter().zip(&f.patients).zip(&g.patients)
            {
                if route_progress(&route.route, current.feet).unwrap_or(0.0) + 0.05
                    < route_progress(&route.route, previous.feet).unwrap_or(0.0)
                {
                    return Err("M04 patient route moved backwards");
                }
            }
        } else if let Some(old) = self.state.as_ref().and_then(|old| old.m04.as_ref()) {
            if f.carried_recall_cars != old.carried_recall_cars {
                return Err("M04 carry changed on retry");
            }
        }
        Ok(())
    }
    pub(super) fn steer_m04(
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
        let Some(f) = self.state.as_ref().and_then(|s| s.m04.as_ref()) else {
            return Action::default();
        };
        let Some(g) = self.m04_map.clone() else {
            return Action::default();
        };
        let Some(points) = self.m04_points else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        if f.clinic_secured && !f.clinic_open {
            return self.steer_m02_use(
                navigator,
                world,
                id,
                snapshot,
                action,
                feet,
                &g.clinic.control,
                points[0],
            );
        }
        let goal = if f.clinic_open && !f.patients_released {
            MissionObjectiveAction::Arrival {
                region: g.clinic.release.clone(),
                feet: g.patients[0].held,
            }
        } else {
            let Some(current) = f.current.as_ref() else {
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
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => self.steer_m02_use(
                navigator, world, id, snapshot, action, feet, &target, points[1],
            ),
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
pub(super) fn route_progress(route: &[[f32; 3]], point: [f32; 3]) -> Option<f32> {
    let mut length = 0.0;
    let mut closest = None;
    let mut closest_distance = f32::INFINITY;
    for pair in route.windows(2) {
        let delta: [f32; 3] = std::array::from_fn(|i| pair[1][i] - pair[0][i]);
        let squared = delta.iter().map(|d| d * d).sum::<f32>();
        if squared <= 0.000001 {
            continue;
        }
        let t = ((0..3)
            .map(|i| (point[i] - pair[0][i]) * delta[i])
            .sum::<f32>()
            / squared)
            .clamp(0.0, 1.0);
        let distance = (0..3)
            .map(|i| (point[i] - pair[0][i] - t * delta[i]).powi(2))
            .sum::<f32>()
            .sqrt();
        if distance < closest_distance {
            closest_distance = distance;
            closest = Some(length + t * squared.sqrt());
        }
        length += squared.sqrt();
    }
    (closest_distance <= 0.05).then_some(closest).flatten()
}
