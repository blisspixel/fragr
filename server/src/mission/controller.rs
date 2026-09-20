//! Validated mission observation and local control shared by wire agents.
use crate::movement::Solid;
use crate::navigation::{Navigation, NavigationGoal, Navigator};
use crate::protocol::{
    Action, CampaignRules, LookAt, MapPresentation, MissionGeometry, MissionPhase, MissionReady,
    MissionState, Snapshot,
};
use crate::sim::PLAYER_FLOOR_Y;
use uuid::Uuid;

#[derive(Debug, Clone, Default)]
pub struct MissionClient {
    geometry: Option<MissionGeometry>,
    points: [[f32; 3]; 2],
    pub state: Option<MissionState>,
    last_tick: Option<u64>,
    press_down: bool,
    rules: Option<CampaignRules>,
}

impl MissionClient {
    pub fn replace_map(
        &mut self,
        mission: Option<&MissionGeometry>,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let mut next = Self::default();
        if let Some(mission) = mission {
            mission.validate(half_extent, solids, presentation)?;
            let presentation = presentation.ok_or("mission requires presentation")?;
            next.points = [
                mission
                    .record
                    .point(presentation, solids)
                    .ok_or("missing record panel")?,
                mission
                    .departure
                    .point(presentation, solids)
                    .ok_or("missing lift panel")?,
            ];
            next.geometry = Some(mission.clone());
            if self
                .geometry
                .as_ref()
                .is_some_and(|old| old.id == mission.id)
            {
                next.rules = self.rules;
            }
        }
        *self = next;
        Ok(())
    }

    pub fn observe(&mut self, tick: u64, state: MissionState) -> Result<(), &'static str> {
        state.validate(tick)?;
        if self.geometry.as_ref().is_none_or(|map| map.id != state.id)
            || self.rules.is_some_and(|rules| rules != state.rules)
            || self.last_tick.is_some_and(|last| tick < last)
            || self
                .state
                .as_ref()
                .is_some_and(|last| state.attempt < last.attempt)
        {
            return Err("mission state does not match the current map or revision");
        }
        self.last_tick = Some(tick);
        self.rules = Some(state.rules);
        self.state = Some(state);
        Ok(())
    }

    /// Supplied wire controllers finish text immediately. MCP clients use an
    /// explicit tool; observation alone must never acknowledge on their behalf.
    pub fn readiness(&self, id: Option<Uuid>) -> Option<MissionReady> {
        let id = id?;
        let state = self.state.as_ref()?;
        (state.phase != MissionPhase::Departed
            && state
                .party
                .iter()
                .any(|member| member.id == id && !member.ready))
        .then_some(MissionReady {
            id: state.id,
            attempt: state.attempt,
        })
    }

    /// Public mission facts also gate optional decision work while a party waits.
    pub fn participating(&self, id: Uuid) -> bool {
        self.geometry.is_none()
            || self.state.as_ref().is_some_and(|state| {
                matches!(
                    state.phase,
                    MissionPhase::FindTransfer | MissionPhase::ReachLift
                ) && state
                    .party
                    .iter()
                    .any(|member| member.id == id && member.ready)
            })
    }

    /// Equipment and combat intent retain priority. With no target, walk to the
    /// mission approach, aim at the actual panel and use only a server prompt.
    pub fn steer(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
    ) -> Action {
        if !self.participating(id) {
            return Action::default();
        }
        let (Some(geometry), Some(state)) = (&self.geometry, &self.state) else {
            return navigator.steer_snapshot(world, id, snapshot, action);
        };
        if action.look_at.is_some() {
            self.press_down = false;
            return navigator.steer_snapshot(world, id, snapshot, action);
        }
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            self.press_down = false;
            return Action::default();
        };
        let (target, point) = match state.phase {
            MissionPhase::FindTransfer => (&geometry.record, self.points[0]),
            _ => (&geometry.departure, self.points[1]),
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let distance = (0..3)
            .map(|axis| (feet[axis] - target.approach[axis]).powi(2))
            .sum::<f32>()
            .sqrt();
        let mut wanted = Action {
            reload: action.reload,
            weapon_swap: action.weapon_swap,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Action::default()
        };
        if distance <= 0.45 {
            wanted.interact = !self.press_down && state.prompts.iter().any(|p| p.player_id == id);
            self.press_down = wanted.interact;
            navigator.clear();
            wanted
        } else {
            self.press_down = false;
            navigator.steer(
                world,
                feet,
                NavigationGoal {
                    feet: target.approach,
                    combat: false,
                },
                wanted,
                snapshot.tick,
                true,
            )
        }
    }
}
