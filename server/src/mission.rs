//! Shared mission progression. The encounter lifecycle owns party reset timing.
use crate::maps::RuntimeMap;
use crate::protocol::{
    CampaignActor, InteractionKind, InteractionPrompt, MissionMember, MissionPhase, MissionState,
    ServerMessage, UseTarget, USE_DISTANCE,
};
use crate::sim::{GameState, Player, PLAYER_FLOOR_Y};

mod controller;
pub use controller::MissionClient;

#[cfg(test)]
mod tests;
#[cfg(test)]
mod wire_tests;

pub(crate) struct MissionRun {
    initial_map: RuntimeMap,
    attempt: u32,
    phase: MissionPhase,
    changed_at: u64,
    started: bool,
}

impl MissionRun {
    pub fn new(map: &RuntimeMap) -> Option<Self> {
        map.mission()?;
        Some(Self {
            initial_map: map.clone(),
            attempt: 1,
            phase: MissionPhase::FindTransfer,
            changed_at: 0,
            started: false,
        })
    }
}

fn can_use(player: &Player, target: &UseTarget, map: &RuntimeMap) -> bool {
    let Some(point) = map
        .presentation_ref()
        .and_then(|presentation| target.point(presentation, &map.arena().solids))
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
        && crate::combat::line_of_sight(eye, point, &map.arena().solids)
}

impl GameState {
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
        run.phase = MissionPhase::FindTransfer;
        run.attempt = run.attempt.saturating_add(1);
        run.changed_at = self.tick;
        run.started = false;
        for player in &mut self.players {
            player.interaction_requested = false;
        }
        tracing::info!(attempt = run.attempt, "Mission reset to intake");
    }

    pub fn mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let geometry = self.map.mission()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Participant {}))
            .map(|p| MissionMember {
                id: p.id,
                name: p.name.clone(),
                alive: p.hp > 0 && p.respawn_timer.is_none(),
                aboard: p.hp > 0
                    && p.respawn_timer.is_none()
                    && geometry.boarding.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z]),
            })
            .collect();
        let control = match run.phase {
            MissionPhase::FindTransfer => Some((&geometry.record, InteractionKind::TransferRecord)),
            MissionPhase::ReachLift if !party.is_empty() && party.iter().all(|p| p.aboard) => {
                Some((&geometry.departure, InteractionKind::LiftDeparture))
            }
            _ => None,
        };
        let prompts = control.map_or_else(Vec::new, |(target, kind)| {
            self.players
                .iter()
                .filter(|p| party.iter().any(|member| member.id == p.id && member.alive))
                .filter(|p| can_use(p, target, &self.map))
                .map(|p| InteractionPrompt {
                    player_id: p.id,
                    kind,
                })
                .collect()
        });
        Some(MissionState {
            id: geometry.id,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
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
            MissionPhase::Departed => return,
        };
        if let Some(run) = self.mission.as_mut() {
            run.phase = next;
            run.changed_at = self.tick;
            tracing::info!(attempt = run.attempt, phase = ?next, "Mission progressed");
        }
    }
}
