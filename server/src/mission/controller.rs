//! Validated mission observation and local control shared by wire agents.
use crate::movement::Solid;
use crate::navigation::{Navigation, NavigationGoal, Navigator};
use crate::protocol::{
    Action, CampaignRules, LookAt, MapPresentation, MissionGeometry, MissionId,
    MissionObjectiveAction, MissionPhase, MissionReady, MissionState, Snapshot, UseTarget,
};
use crate::sim::PLAYER_FLOOR_Y;
use uuid::Uuid;
mod m04;
mod m05;
mod m06;
mod m07;
mod m08;
mod m09;

#[derive(Debug, Clone, Default)]
pub struct MissionClient {
    geometry: Option<MissionGeometry>,
    points: [[f32; 3]; 2],
    m02_map: Option<M02Map>,
    m02_point: Option<[f32; 3]>,
    m03_map: Option<crate::protocol::M03MapGeometry>,
    m04_map: Option<crate::protocol::M04MapGeometry>,
    m04_points: Option<[[f32; 3]; 2]>,
    m04_pending: bool,
    m05_map: Option<crate::protocol::M05MapGeometry>,
    m05_solids: Vec<Solid>,
    m05_point: Option<[f32; 3]>,
    m05_pending: bool,
    m06_map: Option<crate::protocol::M06MapGeometry>,
    m06_point: Option<[f32; 3]>,
    m06_pending: bool,
    m08_map: Option<crate::protocol::M08MapGeometry>,
    m08_point: Option<[f32; 3]>,
    m08_pending: bool,
    m07_map: Option<crate::protocol::M07MapGeometry>,
    m07_point: Option<[f32; 3]>,
    m07_pending: bool,
    m09_map: Option<crate::protocol::M09MapGeometry>,
    m09_points: Option<[[f32; 3]; 2]>,
    m09_pending: bool,
    m03_departure: Option<[f32; 3]>,
    pub state: Option<MissionState>,
    last_tick: Option<u64>,
    press_down: bool,
    rules: Option<CampaignRules>,
    run: Option<crate::protocol::CampaignRunState>,
    observed: bool,
}

#[derive(Debug, Clone)]
struct M02Map {
    id: u32,
    total: u8,
    side_ward: bool,
    half: f32,
    solids: Vec<Solid>,
    presentation: MapPresentation,
}

impl MissionClient {
    fn validate_m03_target(&self, state: &MissionState) -> Result<(), &'static str> {
        let geometry = self.m03_map.as_ref().ok_or("M03 map is missing")?;
        let facts = state.m03.as_ref().ok_or("M03 facts are missing")?;
        if (facts.mast_hp == 0) != geometry.mast_shutdown || facts.cars.len() != geometry.cars.len()
        {
            return Err("M03 facts do not match current world");
        }
        for (car, definition) in facts.cars.iter().zip(&geometry.cars) {
            if car.id != definition.id
                || (!car.released
                    && car
                        .captives
                        .iter()
                        .zip(definition.held)
                        .any(|(feet, held)| (0..3).any(|i| (feet[i] - held[i]).abs() > 0.01)))
            {
                return Err("M03 captive facts do not match authored car");
            }
            for (feet, (held, safe)) in car
                .captives
                .iter()
                .zip(definition.held.iter().zip(definition.safe))
            {
                let delta: [f32; 3] = std::array::from_fn(|i| safe[i] - held[i]);
                let length = delta.iter().map(|value| value * value).sum::<f32>();
                let fraction = if length > 0.0001 {
                    ((0..3).map(|i| (feet[i] - held[i]) * delta[i]).sum::<f32>() / length)
                        .clamp(0.0, 1.0)
                } else {
                    0.0
                };
                if (0..3)
                    .map(|i| (feet[i] - held[i] - delta[i] * fraction).powi(2))
                    .sum::<f32>()
                    > 0.0025
                {
                    return Err("M03 captive left authored evacuation segment");
                }
            }
        }
        let expected = if facts.mast_hp > 0 {
            Some(MissionObjectiveAction::Shoot {
                solid: geometry.mast.solid,
                approach: geometry.mast.approach,
                aim: geometry.mast.aim,
            })
        } else if state.phase != MissionPhase::Departed {
            Some(MissionObjectiveAction::Use {
                target: geometry.departure.clone(),
            })
        } else {
            None
        };
        if facts.current.as_ref().map(|goal| &goal.action) != expected.as_ref() {
            return Err("M03 objective drifted from authored target");
        }
        if let Some(old) = self
            .state
            .as_ref()
            .filter(|old| old.attempt == state.attempt)
            .and_then(|old| old.m03.as_ref())
        {
            if facts.mast_hp > old.mast_hp
                || (old.mast_secured && !facts.mast_secured)
                || (old.train_secured && !facts.train_secured)
                || old
                    .cars
                    .iter()
                    .zip(&facts.cars)
                    .any(|(old, new)| old.released && !new.released)
            {
                return Err("M03 facts rewound within attempt");
            }
        }
        Ok(())
    }

    fn steer_m03(
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
        let Some(facts) = self.state.as_ref().and_then(|state| state.m03.as_ref()) else {
            return Action::default();
        };
        if self
            .m03_map
            .as_ref()
            .is_none_or(|map| map.mast_shutdown != (facts.mast_hp == 0))
        {
            navigator.clear();
            return Action::default();
        }
        let Some(goal) = facts.current.as_ref().map(|goal| goal.action.clone()) else {
            return Action::default();
        };
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        match goal {
            MissionObjectiveAction::Shoot { approach, aim, .. } => {
                let distance = (0..3)
                    .map(|i| (feet[i] - approach[i]).powi(2))
                    .sum::<f32>()
                    .sqrt();
                let wanted = Action {
                    weapon_swap: action.weapon_swap,
                    fire: facts.mast_secured && distance <= 0.45,
                    look_at: Some(LookAt {
                        x: Some(aim[0]),
                        y: Some(aim[1]),
                        z: Some(aim[2]),
                        player_id: None,
                    }),
                    ..Action::default()
                };
                self.press_down = false;
                if distance <= 0.45 {
                    navigator.clear();
                    wanted
                } else {
                    navigator.steer(
                        world,
                        feet,
                        NavigationGoal {
                            feet: approach,
                            combat: false,
                        },
                        wanted,
                        snapshot.tick,
                        true,
                    )
                }
            }
            MissionObjectiveAction::Use { target } => {
                let Some(point) = self.m03_departure else {
                    return Action::default();
                };
                self.steer_m02_use(navigator, world, id, snapshot, action, feet, &target, point)
            }
            MissionObjectiveAction::Arrival { .. } => Action::default(),
        }
    }
    pub fn replace_map_with_m03(
        &mut self,
        geometry: Option<&crate::protocol::M03MapGeometry>,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let Some(geometry) = geometry else {
            self.m03_map = None;
            self.m03_departure = None;
            return Ok(());
        };
        if self.geometry.is_some()
            || self.m02_map.is_some()
            || self.m06_map.is_some()
            || self.m07_map.is_some()
            || self.m09_map.is_some()
        {
            return Err("M03 cannot share another mission map");
        }
        geometry.validate(half, solids, presentation)?;
        if let Some(old) = &self.m03_map {
            let mut stable = old.clone();
            stable.mast_shutdown = geometry.mast_shutdown;
            if stable != *geometry {
                return Err("M03 static contract changed");
            }
        }
        self.m03_departure = geometry
            .departure
            .point(presentation.ok_or("M03 presentation is missing")?, solids);
        self.m03_map = Some(geometry.clone());
        self.press_down = false;
        Ok(())
    }
    // One validated handoff receives the corresponding MapInfo wire fields.
    #[allow(clippy::too_many_arguments)]
    pub fn replace_map_with_id(
        &mut self,
        map_id: u32,
        m02_objectives: Option<u8>,
        m02_side_ward: bool,
        mission: Option<&MissionGeometry>,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        if m02_side_ward && m02_objectives.is_none() {
            return Err("side ward marker requires M02 objectives");
        }
        if self
            .m02_map
            .as_ref()
            .is_some_and(|old| old.id == map_id && old.side_ward != m02_side_ward)
        {
            return Err("M02 side ward marker changed for the same map");
        }
        if let Some(count) = m02_objectives {
            if self.m07_map.is_some() || self.m09_map.is_some() {
                return Err("M02 cannot share an M07 mission map");
            }
            if !(1..=8).contains(&count) || mission.is_some() || presentation.is_none() {
                return Err("invalid M02 map marker or presentation");
            }
        }
        let old = self.clone();
        self.replace_map(mission, half_extent, solids, presentation)?;
        if old.m03_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1003
        {
            self.m03_map = old.m03_map.clone();
            self.m03_departure = old.m03_departure;
            self.state = old.state.clone();
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
        }
        if old.m04_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1004
        {
            self.m04_map = old.m04_map.clone();
            self.m04_points = old.m04_points;
            self.state = old.state.clone();
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
            self.m04_pending = true;
        }
        if old.m05_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1005
        {
            self.m05_map = old.m05_map.clone();
            self.m05_point = old.m05_point;
            self.state = old.state.clone();
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
            self.m05_pending = true;
        }
        if old.m06_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1006
        {
            self.m06_map = old.m06_map.clone();
            self.m06_point = old.m06_point;
            self.state = old.state.clone();
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
            self.m06_pending = true;
        }
        if old.m08_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1008
        {
            self.m08_map = old.m08_map.clone();
            self.m08_point = old.m08_point;
            self.state = old.state.clone();
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
            self.m08_pending = true;
        }
        if old.m07_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1007
        {
            self.m07_map = old.m07_map.clone();
            self.m07_point = old.m07_point;
            self.state = old.state.clone();
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
            self.m07_pending = true;
        }
        if let Some(count) = m02_objectives {
            let presentation = presentation.ok_or("M02 requires map presentation")?;
            self.m02_map = Some(M02Map {
                id: map_id,
                total: count,
                side_ward: m02_side_ward,
                half: half_extent,
                solids: solids.to_vec(),
                presentation: presentation.clone(),
            });
            if old.m02_map.as_ref().is_some_and(|old| {
                old.id == map_id && old.total == count && old.side_ward == m02_side_ward
            }) {
                self.state = old.state.clone();
                self.last_tick = old.last_tick;
                self.rules = old.rules;
                self.run = old.run;
                self.observed = old.observed;
            }
        }
        if old.m09_map.is_some() && mission.is_none() && m02_objectives.is_none() && map_id == 1009
        {
            self.m09_map = old.m09_map.clone();
            self.m09_points = old.m09_points;
            self.state = old.state;
            self.last_tick = old.last_tick;
            self.rules = old.rules;
            self.run = old.run;
            self.observed = old.observed;
            self.m09_pending = true;
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
        let map_matches = if state.id == MissionId::PassengerManifest {
            self.validate_m09_target(&state)?;
            true
        } else if state.id == MissionId::CustodianOfRecord {
            self.validate_m08_target(&state)?;
            true
        } else if state.id == MissionId::DeclaredGoods {
            self.validate_m07_target(&state)?;
            true
        } else if state.id == MissionId::PortOfEntry {
            self.validate_m06_target(&state)?;
            true
        } else if state.id == MissionId::NoForwardingAddress {
            self.validate_m05_target(&state)?;
            true
        } else if state.id == MissionId::NoticeToVacate {
            self.validate_m04_target(&state)?;
            true
        } else if state.id == MissionId::ScheduledService {
            self.validate_m03_target(&state)?;
            true
        } else if state.id == MissionId::PersonsUnknown {
            self.m02_map.as_ref().is_some_and(|map| {
                state.m02.as_ref().is_some_and(|m02| {
                    m02.total == map.total && m02.evacuation.is_some() == map.side_ward
                })
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
        self.m04_pending = false;
        self.m05_pending = false;
        self.m06_pending = false;
        self.m08_pending = false;
        self.m07_pending = false;
        self.m09_pending = false;
        self.m02_point = m02_point.flatten();
        self.state = Some(state);
        Ok(())
    }

    fn validate_m02_target(&self, state: &MissionState) -> Result<Option<[f32; 3]>, &'static str> {
        let map = self.m02_map.as_ref().ok_or("M02 map is missing")?;
        let half = map.half;
        let solids = &map.solids;
        let presentation = &map.presentation;
        if state
            .m02
            .as_ref()
            .and_then(|m02| m02.evacuation.as_ref())
            .is_some_and(|evacuation| {
                evacuation
                    .captives
                    .iter()
                    .any(|feet| feet[0].abs() > half || feet[2].abs() > half)
            })
        {
            return Err("M02 captive feet lie outside the map");
        }
        let current = state.m02.as_ref().and_then(|m02| m02.current.as_ref());
        match current.map(|objective| &objective.action) {
            Some(MissionObjectiveAction::Arrival { region, feet }) => {
                if !region.valid(half) || !region.contains(*feet) {
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
                ) || target.approach[0].abs() > half
                    || target.approach[2].abs() > half
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
            Some(MissionObjectiveAction::Shoot { .. }) => {
                Err("M02 cannot contain a shoot objective")
            }
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
        (self.geometry.is_none()
            && self.m02_map.is_none()
            && self.m03_map.is_none()
            && self.m04_map.is_none()
            && self.m05_map.is_none()
            && self.m06_map.is_none()
            && self.m07_map.is_none()
            && self.m08_map.is_none()
            && self.m09_map.is_none())
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
        let wanted = self.steer_route(navigator, world, id, snapshot, action);
        let mut bodies = Navigator::snapshot_bodies(snapshot);
        if let Some(state) = self
            .state
            .as_ref()
            .filter(|state| state.phase == MissionPhase::InProgress)
        {
            let mut append = |key: String, feet: [f32; 3]| {
                bodies.push(crate::sim::contact::civilian(key, feet));
            };
            if let Some(f) = state.m02.as_ref().and_then(|m| m.evacuation.as_ref()) {
                for (i, feet) in f.captives.iter().copied().enumerate() {
                    append(format!("m02/captive/{i}"), feet);
                }
            }
            if let Some(f) = &state.m03 {
                for car in &f.cars {
                    for (i, feet) in car.captives.iter().copied().enumerate() {
                        append(format!("m03/{}/{i}", car.id), feet);
                    }
                }
            }
            if let Some(f) = &state.m04 {
                for patient in &f.patients {
                    append(format!("m04/{}", patient.id), patient.feet);
                }
            }
            if let Some(f) = &state.m05 {
                for captive in &f.captives {
                    append(format!("m05/{}", captive.id), captive.feet);
                }
            }
            if let Some(f) = &state.m09 {
                for crew in &f.crew {
                    append(format!("m09/{}", crew.id), crew.feet);
                }
            }
        }
        let solids = self.live_visibility_solids();
        let arena = crate::movement::Arena {
            half: world.planning_arena().half,
            solids: solids.unwrap_or_else(|| world.planning_arena().solids.clone()),
        };
        navigator.avoid_bodies(&arena, id, &bodies, wanted, snapshot.tick)
    }

    fn steer_route(
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
        if self.m04_pending
            || self.m05_pending
            || self.m06_pending
            || self.m07_pending
            || self.m08_pending
            || self.m09_pending
        {
            navigator.clear();
            return Action::default();
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::PassengerManifest)
        {
            return self.steer_m09(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::CustodianOfRecord)
        {
            return self.steer_m08(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::PortOfEntry)
        {
            return self.steer_m06(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::DeclaredGoods)
        {
            return self.steer_m07(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::NoForwardingAddress)
        {
            return self.steer_m05(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::NoticeToVacate)
        {
            return self.steer_m04(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::ScheduledService)
        {
            return self.steer_m03(navigator, world, id, snapshot, action);
        }
        if self
            .state
            .as_ref()
            .is_some_and(|state| state.id == MissionId::PersonsUnknown)
        {
            return self.steer_m02(navigator, world, id, snapshot, action);
        }
        let (Some(geometry), Some(state)) = (&self.geometry, &self.state) else {
            return navigator.route_snapshot_with_visibility(
                world,
                id,
                snapshot,
                action,
                true,
                &world.planning_arena().solids,
            );
        };
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
            return navigator.route_snapshot_with_visibility(
                world,
                id,
                snapshot,
                action,
                true,
                &world.planning_arena().solids,
            );
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
            MissionObjectiveAction::Shoot { .. } => Action::default(),
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
