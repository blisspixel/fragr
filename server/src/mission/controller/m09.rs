use super::*;
use crate::protocol::M09MapGeometry;

impl MissionClient {
    pub fn replace_map_with_m09(
        &mut self,
        geometry: Option<&M09MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.m09_map = None;
            self.m09_points = None;
            self.m09_pending = false;
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
        {
            return Err("M09 cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.m09_map {
            let mut static_old = old.clone();
            static_old.hatch_open = g.hatch_open;
            if static_old != *g {
                return Err("M09 static map changed");
            }
        }
        let presentation = presentation.ok_or("M09 presentation missing")?;
        let crew = g
            .crew_release
            .point(presentation, solids)
            .ok_or("M09 release panel missing")?;
        let departure = g
            .departure
            .point(presentation, solids)
            .ok_or("M09 departure panel missing")?;
        self.m09_points = Some([crew, departure]);
        self.m09_map = Some(g.clone());
        self.m09_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_m09_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let g = self.m09_map.as_ref().ok_or("M09 geometry missing")?;
        let f = state.m09.as_ref().ok_or("M09 facts missing")?;
        if f.current != g.step(f.completed.len()) || f.hatch_open != g.hatch_open {
            return Err("M09 step disagrees with current world");
        }
        for crew in &f.crew {
            let definition = g
                .crew
                .iter()
                .find(|c| c.id == crew.id)
                .ok_or("M09 unregistered crew")?;
            let route = &definition.route;
            if !f.crew_released && crew.feet != route[0]
                || crew.aboard != (f.crew_released && g.boarding.contains(crew.feet))
            {
                return Err("M09 crew state disagrees with berth");
            }
            // Stair height comes from actual supported motion, not linear Y.
            // Horizontal positions stay on a registered segment; contacts wait.
            if !route.windows(2).enumerate().any(|(index, p)| {
                let dx = p[1][0] - p[0][0];
                let dz = p[1][2] - p[0][2];
                let length = dx * dx + dz * dz;
                let fraction = if length > 0.000001 {
                    ((crew.feet[0] - p[0][0]) * dx + (crew.feet[2] - p[0][2]) * dz) / length
                } else {
                    0.0
                };
                let fraction = fraction.clamp(0.0, 1.0);
                (crew.feet == route[0]
                    || usize::from(definition.held_until[index + 1]) <= f.completed.len())
                    && (crew.feet[0] - p[0][0] - dx * fraction)
                        .hypot(crew.feet[2] - p[0][2] - dz * fraction)
                        <= 0.01
                    && crew.feet[1] >= p[0][1].min(p[1][1]) - 0.01
                    && crew.feet[1] <= p[0][1].max(p[1][1]) + 0.01
            }) {
                return Err("M09 crew left registered route");
            }
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let before = old.m09.as_ref().ok_or("M09 prior facts missing")?;
            if before.carried_archive != f.carried_archive
                || before
                    .crew
                    .iter()
                    .map(|c| &c.id)
                    .ne(f.crew.iter().map(|c| &c.id))
            {
                return Err("M09 carry or crew presence changed");
            }
            if old.attempt == state.attempt
                && (f.completed.len() < before.completed.len()
                    || f.charge_falls < before.charge_falls
                    || old.phase != MissionPhase::Briefing && state.phase == MissionPhase::Briefing)
            {
                return Err("M09 attempt moved backwards");
            }
        }
        Ok(())
    }

    pub(super) fn steer_m09(
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
            .and_then(|s| s.m09.as_ref())
            .and_then(|f| f.current.as_ref())
            .cloned()
        else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        match current.action {
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
                        place_mine: action.place_mine,
                        ..Action::default()
                    },
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let Some(points) = self.m09_points else {
                    return Action::default();
                };
                let point = points[usize::from(current.id == "party_departed")];
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
