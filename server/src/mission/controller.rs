//! Validated mission observation and local control shared by wire agents.
use crate::movement::Solid;
use crate::navigation::{Navigation, NavigationGoal, Navigator};
use crate::protocol::{
    Action, CampaignRules, LookAt, MapPresentation, MissionGeometry, MissionId,
    MissionObjectiveAction, MissionPhase, MissionReady, MissionState, Snapshot, UseTarget,
};
use crate::sim::PLAYER_FLOOR_Y;
use uuid::Uuid;

#[derive(Debug, Clone, Default)]
pub struct MissionClient {
    geometry: Option<MissionGeometry>,
    points: [[f32; 3]; 2],
    m02_map: Option<(u32, u8, f32, Vec<Solid>, MapPresentation)>,
    m02_point: Option<[f32; 3]>,
    pub state: Option<MissionState>,
    last_tick: Option<u64>,
    press_down: bool,
    rules: Option<CampaignRules>,
    run: Option<crate::protocol::CampaignRunState>,
    observed: bool,
}

impl MissionClient {
    pub fn replace_map_with_id(
        &mut self,
        map_id: u32,
        m02_objectives: Option<u8>,
        mission: Option<&MissionGeometry>,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        if let Some(count) = m02_objectives {
            if !(1..=8).contains(&count) || mission.is_some() || presentation.is_none() {
                return Err("invalid M02 map marker or presentation");
            }
        }
        let old = self.clone();
        self.replace_map(mission, half_extent, solids, presentation)?;
        if let Some(count) = m02_objectives {
            let presentation = presentation.ok_or("M02 requires map presentation")?;
            self.m02_map = Some((
                map_id,
                count,
                half_extent,
                solids.to_vec(),
                presentation.clone(),
            ));
            if old
                .m02_map
                .as_ref()
                .is_some_and(|(old_id, old_count, ..)| *old_id == map_id && *old_count == count)
            {
                self.state = old.state;
                self.last_tick = old.last_tick;
                self.rules = old.rules;
                self.run = old.run;
                self.observed = old.observed;
            }
        }
        Ok(())
    }

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
                next.run = self.run;
                next.observed = self.observed;
                next.last_tick = self.last_tick;
            }
        }
        *self = next;
        Ok(())
    }

    pub fn observe(&mut self, tick: u64, state: MissionState) -> Result<(), &'static str> {
        state.validate(tick)?;
        let m02_point = if state.id == MissionId::PersonsUnknown {
            Some(self.validate_m02_target(&state)?)
        } else {
            None
        };
        let map_matches = if state.id == MissionId::PersonsUnknown {
            self.m02_map.as_ref().is_some_and(|(_, count, ..)| {
                state.m02.as_ref().is_some_and(|m02| m02.total == *count)
            })
        } else {
            self.geometry.as_ref().is_some_and(|map| map.id == state.id)
        };
        if !map_matches
            || self.rules.is_some_and(|rules| rules != state.rules)
            || (self.observed
                && match (self.run, state.run) {
                    (None, None) => false,
                    (Some(old), Some(new)) => old.id != new.id || new.continues > old.continues,
                    _ => true,
                })
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
        self.run = state.run;
        self.observed = true;
        self.m02_point = m02_point.flatten();
        self.state = Some(state);
        Ok(())
    }

    fn validate_m02_target(&self, state: &MissionState) -> Result<Option<[f32; 3]>, &'static str> {
        let (_, _, half, solids, presentation) =
            self.m02_map.as_ref().ok_or("M02 map is missing")?;
        let current = state.m02.as_ref().and_then(|m02| m02.current.as_ref());
        match current.map(|objective| &objective.action) {
            Some(MissionObjectiveAction::Arrival { region, feet }) => {
                if !region.valid(*half) || !region.contains(*feet) {
                    return Err("M02 arrival lies outside the map");
                }
                Ok(None)
            }
            Some(MissionObjectiveAction::Use { target }) => {
                let panel = presentation
                    .decorations
                    .get(target.decoration)
                    .ok_or("M02 target references an unknown panel")?;
                if !matches!(
                    panel.kind,
                    crate::protocol::MapDecorationKind::Terminal
                        | crate::protocol::MapDecorationKind::LiftControl
                ) || target.approach[0].abs() > *half
                    || target.approach[2].abs() > *half
                {
                    return Err("M02 target has an invalid panel or approach");
                }
                let point = target
                    .point(presentation, solids)
                    .ok_or("M02 target has no use point")?;
                let eye = [
                    target.approach[0],
                    target.approach[1] + crate::movement::EYE_HEIGHT,
                    target.approach[2],
                ];
                let distance = (0..3)
                    .map(|axis| (eye[axis] - point[axis]).powi(2))
                    .sum::<f32>()
                    .sqrt();
                if distance > crate::protocol::USE_DISTANCE
                    || !crate::combat::line_of_sight(eye, point, solids)
                {
                    return Err("M02 target cannot be reached from its approach");
                }
                Ok(Some(point))
            }
            None => Ok(None),
        }
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
        (self.geometry.is_none() && self.m02_map.is_none())
            || self.state.as_ref().is_some_and(|state| {
                state
                    .run
                    .is_none_or(|run| run.status == crate::protocol::CampaignRunStatus::Playing)
                    && matches!(
                        state.phase,
                        MissionPhase::FindTransfer
                            | MissionPhase::ReachLift
                            | MissionPhase::InProgress
                    )
                    && state
                        .party
                        .iter()
                        .any(|member| member.id == id && member.ready)
            })
    }

    pub fn continuation(&self, id: Option<Uuid>) -> Option<crate::protocol::MissionContinue> {
        let id = id?;
        let state = self.state.as_ref()?;
        let run = state.run?;
        (run.status == crate::protocol::CampaignRunStatus::Continue
            && state
                .party
                .iter()
                .any(|member| member.id == id && !member.alive))
        .then_some(crate::protocol::MissionContinue {
            id: state.id,
            run_id: run.id,
            attempt: state.attempt,
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
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::PersonsUnknown)
        {
            return self.steer_m02(navigator, world, id, snapshot, action);
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

    fn steer_m02(
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
        let Some(me) = snapshot
            .players
            .iter()
            .find(|player| player.id == id && player.hp > 0)
        else {
            self.press_down = false;
            return Action::default();
        };
        let Some(state) = self.state.as_ref() else {
            return Action::default();
        };
        let Some(objective) = state.m02.as_ref().and_then(|m02| m02.current.as_ref()) else {
            return Action::default();
        };
        let objective_action = objective.action.clone();
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        match objective_action {
            MissionObjectiveAction::Arrival { feet: goal, .. } => {
                self.press_down = false;
                navigator.steer(
                    world,
                    feet,
                    NavigationGoal {
                        feet: goal,
                        combat: false,
                    },
                    action,
                    snapshot.tick,
                    true,
                )
            }
            MissionObjectiveAction::Use { target } => {
                let Some(point) = self.m02_point else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn steer_m02_use(
        &mut self,
        navigator: &mut Navigator,
        world: &Navigation,
        id: Uuid,
        snapshot: &Snapshot,
        action: Action,
        feet: [f32; 3],
        target: &UseTarget,
        point: [f32; 3],
    ) -> Action {
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
            wanted.interact = !self.press_down
                && self
                    .state
                    .as_ref()
                    .is_some_and(|state| state.prompts.iter().any(|prompt| prompt.player_id == id));
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
