use super::*;
use crate::protocol::{EpilogueMapGeometry, EPILOGUE_OBJECTIVE_IDS};

impl MissionClient {
    pub fn replace_map_with_epilogue(
        &mut self,
        geometry: Option<&EpilogueMapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(g) = geometry else {
            self.epilogue_map = None;
            self.epilogue_points = None;
            self.epilogue_pending = false;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m03_map.is_some()
            || self.m20_map.is_some()
            || self.m19_map.is_some()
        {
            return Err("Still Here cannot share another mission map");
        }
        g.validate(half, solids, presentation)?;
        if let Some(old) = &self.epilogue_map {
            let mut same = old.clone();
            same.later = g.later;
            if &same != g || old.later && !g.later {
                return Err("Still Here static map contract changed");
            }
        }
        let present = presentation.ok_or("Still Here presentation missing")?;
        self.epilogue_points = Some([
            g.latch
                .point(present, solids)
                .ok_or("Still Here ledger missing")?,
            g.departure
                .point(present, solids)
                .ok_or("Still Here bench missing")?,
        ]);
        self.epilogue_map = Some(g.clone());
        self.epilogue_pending = true;
        self.press_down = false;
        Ok(())
    }

    pub(super) fn validate_epilogue_target(
        &self,
        state: &MissionState,
    ) -> Result<(), &'static str> {
        let g = self
            .epilogue_map
            .as_ref()
            .ok_or("Still Here geometry missing")?;
        let f = state.epilogue.as_ref().ok_or("Still Here facts missing")?;
        let done = f.completed.len();
        let expected = match done {
            0 => Some(g.latch_objective()),
            1 => Some(g.arrival_objective()),
            n if n == EPILOGUE_OBJECTIVE_IDS.len() => Some(g.departure_objective()),
            _ => None,
        };
        if f.current != expected || f.later != g.later || f.blocking != g.blocking(&f.refuge) {
            return Err("Still Here facts disagree with the map");
        }
        if let Some(old) = self.state.as_ref().filter(|s| s.id == state.id) {
            let old_f = old
                .epilogue
                .as_ref()
                .ok_or("Still Here prior facts missing")?;
            if old.attempt == state.attempt
                && (done < old_f.completed.len()
                    || old_f.later && !f.later
                    || old_f.refuge != f.refuge
                    || old_f.turning_at.is_some() && old_f.turning_at != f.turning_at)
            {
                return Err("Still Here attempt moved backwards");
            }
        }
        Ok(())
    }

    /// Walk to Latch's table and stay; years later walk the court to the
    /// quay and ask. People in the way are bodies the navigator steps round.
    pub(super) fn steer_epilogue(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            return Action::default();
        };
        let Some(current) = self
            .state
            .as_ref()
            .and_then(|s| s.epilogue.as_ref())
            .and_then(|f| f.current.as_ref())
            .cloned()
        else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        // Nothing here is a target: whatever the fight layer wanted, no shot.
        let calm = Action {
            weapon_swap: action.weapon_swap,
            ..Action::default()
        };
        match current.action {
            MissionObjectiveAction::Arrival {
                feet: destination, ..
            } => {
                self.press_down = false;
                // While the world turns there is nowhere to walk to yet.
                if self.epilogue_map.as_ref().is_none_or(|g| !g.later) {
                    navigator.clear();
                    return calm;
                }
                navigator.steer(
                    world,
                    feet,
                    NavigationGoal {
                        feet: destination,
                        combat: false,
                    },
                    calm,
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let Some([latch, bench]) = self.epilogue_points else {
                    return Action::default();
                };
                let point = if current.id == EPILOGUE_OBJECTIVE_IDS[0] {
                    latch
                } else {
                    bench
                };
                self.steer_m02_use(navigator, world, id, snapshot, calm, feet, &target, point)
            }
            MissionObjectiveAction::Shoot { .. } => Action::default(),
        }
    }
}
