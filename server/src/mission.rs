//! Shared mission progression. The encounter lifecycle owns party reset timing.
use crate::maps::RuntimeMap;
use crate::protocol::{
    CampaignActor, CampaignDifficulty, CampaignRules, InteractionKind, InteractionPrompt,
    MissionId, MissionMember, MissionPhase, MissionReady, MissionState, ServerMessage, UseTarget,
    USE_DISTANCE,
};
use crate::sim::{GameState, Player, PLAYER_FLOOR_Y};
use std::collections::HashSet;
use uuid::Uuid;

mod controller;
mod m02;
mod m03;
mod m04;
mod m05;
mod m06;
mod recovery;
pub(crate) mod run_file;
pub use controller::MissionClient;
pub(crate) use m02::validate_m02_evacuation_route;
pub(crate) use m02::{LATCH_RELEASE_TICKS, LATCH_SECOND_FEET};

#[cfg(test)]
mod difficulty_tests;

#[cfg(test)]
mod readiness_tests;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod wire_tests;

pub(crate) struct MissionRun {
    m02: Option<m02::M02Progress>,
    m03: Option<m03::M03Progress>,
    m04: Option<m04::M04Progress>,
    m05: Option<m05::M05Progress>,
    m06: Option<m06::M06Progress>,
    solo: Option<recovery::SoloRun>,
    rules: CampaignRules,
    initial_map: RuntimeMap,
    attempt: u32,
    phase: MissionPhase,
    changed_at: u64,
    started: bool,
    ready: HashSet<Uuid>,
}

impl MissionRun {
    pub fn new(map: &RuntimeMap) -> Option<Self> {
        map.campaign_mission_id()?;
        Some(Self {
            m02: map.m02_objectives().map(|_| m02::M02Progress::default()),
            m03: map.m03_geometry().map(m03::M03Progress::new),
            m04: map.m04_geometry().map(m04::M04Progress::new),
            m05: map.m05_geometry().map(m05::M05Progress::new),
            m06: map.m06_geometry().map(|_| m06::M06Progress::default()),
            solo: None,
            rules: CampaignRules::default(),
            initial_map: map.clone(),
            attempt: 1,
            phase: MissionPhase::Briefing,
            changed_at: 0,
            started: false,
            ready: HashSet::new(),
        })
    }
}

/// One admission rule for movement, equipment, combat and encounter participation.
pub(crate) fn actor_active(
    run: Option<&MissionRun>,
    id: Uuid,
    actor: Option<CampaignActor>,
) -> bool {
    run.is_none_or(|run| {
        run.solo.as_ref().is_none_or(|solo| solo.playing())
            && run.phase != MissionPhase::Briefing
            && (actor != Some(CampaignActor::Participant {}) || run.ready.contains(&id))
    })
}

fn can_use(player: &Player, target: &UseTarget, map: &RuntimeMap) -> bool {
    can_use_in_arena(player, target, map, map.arena())
}
fn can_use_in_arena(
    player: &Player,
    target: &UseTarget,
    map: &RuntimeMap,
    arena: &crate::movement::Arena,
) -> bool {
    let Some(point) = map
        .presentation_ref()
        .and_then(|presentation| target.point(presentation, &arena.solids))
    else {
        return false;
    };
    let eye = [
        player.x,
        player.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
        player.z,
    ];
    let delta: [f32; 3] = std::array::from_fn(|axis| point[axis] - eye[axis]);
    let distance = delta.iter().map(|v| v * v).sum::<f32>().sqrt();
    let facing = [
        player.pitch.cos() * player.yaw.cos(),
        player.pitch.sin(),
        player.pitch.cos() * player.yaw.sin(),
    ];
    let dot = (0..3).map(|axis| delta[axis] * facing[axis]).sum::<f32>();
    // A forgiving physical use cone, narrower than a visible console at arm's reach.
    distance > 0.0
        && distance <= USE_DISTANCE
        && dot >= distance * 18.0_f32.to_radians().cos()
        && crate::combat::line_of_sight(eye, point, &arena.solids)
}

impl GameState {
    /// Host configuration is accepted only before any participant or tick exists.
    pub fn set_campaign_difficulty(
        &mut self,
        difficulty: CampaignDifficulty,
    ) -> Result<(), &'static str> {
        if self.tick != 0 || !self.players.is_empty() {
            return Err("campaign difficulty must be selected before the session starts");
        }
        let run = self
            .mission
            .as_mut()
            .ok_or("difficulty requires an authored mission")?;
        run.rules = CampaignRules::new(difficulty);
        Ok(())
    }

    pub fn campaign_rules(&self) -> CampaignRules {
        self.mission
            .as_ref()
            .map_or_else(CampaignRules::default, |run| run.rules)
    }

    pub fn acknowledge_mission(&mut self, player_id: Uuid, ready: MissionReady) -> bool {
        if ready.id == MissionId::PersonsUnknown {
            return self.acknowledge_m02(player_id, ready.attempt);
        }
        if self.map.campaign_mission_id() != Some(ready.id)
            || !self
                .players
                .iter()
                .any(|p| p.id == player_id && p.campaign == Some(CampaignActor::Participant {}))
        {
            return false;
        }
        let Some(run) = self
            .mission
            .as_mut()
            .filter(|run| run.attempt == ready.attempt && run.phase != MissionPhase::Departed)
        else {
            return false;
        };
        if !run.ready.insert(player_id) {
            return false;
        }
        if let Some(player) = self.players.iter_mut().find(|p| p.id == player_id) {
            player.clear_input();
            if let Some(solo) = run.solo.as_mut() {
                solo.capture_entry(player, *self.scores.get(&player_id).unwrap_or(&0));
            }
        }
        self.refresh_mission_readiness();
        true
    }

    pub(crate) fn refresh_mission_readiness(&mut self) {
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let party: HashSet<_> = self
            .players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Participant {}))
            .map(|p| p.id)
            .collect();
        run.ready.retain(|id| party.contains(id));
        if run.phase == MissionPhase::Briefing && !party.is_empty() && party.is_subset(&run.ready) {
            run.phase = if run.m02.is_some()
                || run.m03.is_some()
                || run.m04.is_some()
                || run.m05.is_some()
                || run.m06.is_some()
            {
                MissionPhase::InProgress
            } else {
                MissionPhase::FindTransfer
            };
            run.changed_at = self.tick;
            run.started = true;
            tracing::info!(members = party.len(), "Campaign party ready");
        }
        self.ensure_m03_companion();
        self.ensure_m04_companion();
        self.ensure_m05_companion();
        self.ensure_m06_companion();
    }

    pub(crate) fn note_mission_started(&mut self) {
        if let Some(run) = self.mission.as_mut() {
            run.started = true;
        }
    }

    pub(crate) fn reset_mission(&mut self) {
        let Some(run) = self.mission.as_mut().filter(|run| run.started) else {
            return;
        };
        self.map = run.initial_map.clone();
        self.players.retain(Player::is_participant);
        if let Some(m02) = run.m02.as_mut() {
            *m02 = m02::M02Progress::default();
        }
        run.m03 = run.initial_map.m03_geometry().map(m03::M03Progress::new);
        run.m04 = run.initial_map.m04_geometry().map(m04::M04Progress::new);
        run.m05 = run.initial_map.m05_geometry().map(m05::M05Progress::new);
        run.m06 = run
            .initial_map
            .m06_geometry()
            .map(|_| m06::M06Progress::default());
        run.phase = if run.ready.is_empty() {
            MissionPhase::Briefing
        } else {
            if run.m02.is_some()
                || run.m03.is_some()
                || run.m04.is_some()
                || run.m05.is_some()
                || run.m06.is_some()
            {
                MissionPhase::InProgress
            } else {
                MissionPhase::FindTransfer
            }
        };
        run.attempt = run.attempt.saturating_add(1);
        for player in &mut self.players {
            player.statistics.reset_attempt();
        }
        run.changed_at = self.tick;
        // An accepted solo retry is already a live attempt, even if the owner
        // dies again before the encounter controller gets its next tick.
        run.started = run.solo.is_some();
        for player in &mut self.players {
            player.interaction_requested = false;
        }
        tracing::info!(attempt = run.attempt, "Mission reset to intake");
        self.ensure_m03_companion();
        self.ensure_m04_companion();
        self.ensure_m05_companion();
        self.ensure_m06_companion();
    }

    pub fn mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        if run.m06.is_some() {
            return self.m06_mission_state();
        }
        if run.m05.is_some() {
            return self.m05_mission_state();
        }
        if run.m04.is_some() {
            return self.m04_mission_state();
        }
        if run.m03.is_some() {
            return self.m03_mission_state();
        }
        if run.m02.is_some() {
            return self.m02_mission_state();
        }
        let geometry = self.map.mission()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Participant {}))
            .map(|p| MissionMember {
                id: p.id,
                name: p.name.clone(),
                ready: run.ready.contains(&p.id),
                alive: p.hp > 0 && p.respawn_timer.is_none(),
                aboard: run.phase != MissionPhase::Briefing
                    && run.ready.contains(&p.id)
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && geometry.boarding.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z]),
            })
            .collect();
        let control = match run.phase {
            _ if self.campaign_run_frozen() => None,
            MissionPhase::FindTransfer => Some((&geometry.record, InteractionKind::TransferRecord)),
            MissionPhase::ReachLift if !party.is_empty() && party.iter().all(|p| p.aboard) => {
                Some((&geometry.departure, InteractionKind::LiftDeparture))
            }
            _ => None,
        };
        let prompts = control.map_or_else(Vec::new, |(target, kind)| {
            self.players
                .iter()
                .filter(|p| {
                    party
                        .iter()
                        .any(|member| member.id == p.id && member.alive && member.ready)
                })
                .filter(|p| can_use(p, target, &self.map))
                .map(|p| InteractionPrompt {
                    player_id: p.id,
                    kind,
                })
                .collect()
        });
        Some(MissionState {
            id: geometry.id,
            run: run.solo.as_ref().map(|solo| solo.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
        })
    }

    pub fn mission_message(&self) -> Option<ServerMessage> {
        self.mission_state().map(|state| ServerMessage::Mission {
            tick: self.tick,
            state,
        })
    }

    pub(crate) fn mission_departed(&self) -> bool {
        self.mission
            .as_ref()
            .is_some_and(|run| run.phase == MissionPhase::Departed)
    }

    pub(crate) fn advance_mission(&mut self) {
        if self.mission.as_ref().is_some_and(|r| r.m06.is_some()) {
            self.advance_m06();
            return;
        }
        if self.mission.as_ref().is_some_and(|r| r.m05.is_some()) {
            self.advance_m05();
            return;
        }
        if self.mission.as_ref().is_some_and(|run| run.m04.is_some()) {
            self.advance_m04();
            return;
        }
        if self.mission.as_ref().is_some_and(|run| run.m03.is_some()) {
            self.advance_m03();
            return;
        }
        if self.mission.as_ref().is_some_and(|run| run.m02.is_some()) {
            self.advance_m02();
            return;
        }
        // Consume even failed presses, including dead players and the wrong aim.
        let requests: Vec<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        if requests.is_empty() {
            return;
        }
        let Some(state) = self.mission_state() else {
            return;
        };
        if !state
            .prompts
            .iter()
            .any(|prompt| requests.contains(&prompt.player_id))
        {
            return;
        }
        let next = match state.phase {
            MissionPhase::FindTransfer => {
                let Some(opened) = self.map.opened_route() else {
                    return;
                };
                self.map = opened;
                MissionPhase::ReachLift
            }
            MissionPhase::ReachLift => MissionPhase::Departed,
            MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed => return,
        };
        let exit = if next == MissionPhase::Departed && state.run.is_some() {
            let Some(owner) = self
                .mission
                .as_ref()
                .and_then(|run| run.solo.as_ref())
                .and_then(recovery::SoloRun::owner)
            else {
                return;
            };
            let Some(player) = self.players.iter().find(|player| player.id == owner) else {
                return;
            };
            match run_file::SavedEntry::from_player(player) {
                Ok(exit) => Some(exit),
                Err(reason) => {
                    tracing::error!(reason, "Campaign exit equipment could not be saved");
                    return;
                }
            }
        } else {
            None
        };
        if let Some(run) = self.mission.as_mut() {
            run.phase = next;
            run.changed_at = self.tick;
            if next == MissionPhase::Departed {
                if let Some(solo) = run.solo.as_mut() {
                    if let Some(exit) = exit {
                        solo.capture_exit(exit);
                    }
                    solo.state.status = crate::protocol::CampaignRunStatus::Complete;
                }
            }
            tracing::info!(attempt = run.attempt, phase = ?next, "Mission progressed");
        }
    }
}
