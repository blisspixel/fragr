//! The world half of a campaign checkpoint: the bodies, devices, vehicles and
//! map facts a restored attempt resumes with. Mission facts, encounter marks,
//! scheduling and the safety rule live in `mission/checkpoint.rs`.
//!
//! A checkpoint is restored on a later tick than it was taken, and the tick
//! never rewinds. Every absolute tick a restored value holds moves forward by
//! the time between the two, so a clock that was running resumes where it was.
use super::{blade, drops, mine, walker, ArenaPickup, GameState, Player};
use crate::protocol::{CampaignActor, WalkerPhase};

#[derive(Clone, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorldSave {
    /// Deterministic surveys must not reuse an ally's saved identity when
    /// encounters place new guards after reopening the checkpoint.
    #[serde(skip_serializing_if = "Option::is_none")]
    replay_id_counter: Option<u128>,
    #[serde(skip, default = "crate::maps::RuntimeMap::placeholder")]
    map: crate::maps::RuntimeMap,
    pickups: Vec<ArenaPickup>,
    vehicles: Vec<crate::vehicles::Jeep>,
    walker: Option<walker::Walker>,
    foundry: Option<crate::mission::m13::Progress>,
    article_blade: Option<blade::ArticleBladePlinth>,
    dropped_guns: Vec<drops::DroppedGun>,
    mines: Vec<mine::Mine>,
    /// Latch, entrants and story figures: every campaign body that is neither
    /// a participant nor a hostile. Hostiles are placed again by the encounter
    /// lifecycle from the restored group marks.
    allies: Vec<Player>,
}

/// An ally body: a campaign actor that is neither a participant nor hostile.
pub(crate) fn is_ally(player: &Player) -> bool {
    player
        .campaign
        .is_some_and(|actor| !actor.is_participant() && !actor.is_enemy())
}

impl GameState {
    /// Nothing is in flight that could still land: no hostile pulse, canister,
    /// grenade, rocket or thrown remote mine, and the Walker, if any, is not
    /// fighting.
    pub(crate) fn checkpoint_world_quiet(&self) -> bool {
        self.traveling_shots.is_empty()
            && self.assessor_canisters.is_empty()
            && self.grenades.is_empty()
            && self.rockets.is_empty()
            && self.remote_mines.is_empty()
            && self.walker.as_ref().is_none_or(|walker| {
                matches!(
                    walker.state.phase,
                    WalkerPhase::Dormant | WalkerPhase::Disabled
                )
            })
    }

    pub(crate) fn save_checkpoint_world(&self) -> WorldSave {
        WorldSave {
            replay_id_counter: self.replay_id_counter,
            map: self.map.clone(),
            pickups: self.pickups.clone(),
            vehicles: self.vehicles.clone(),
            walker: self.walker.clone(),
            foundry: self.foundry.clone(),
            article_blade: self.article_blade.clone(),
            dropped_guns: self.dropped_guns.clone(),
            mines: self.mines.clone(),
            allies: self
                .players
                .iter()
                .filter(|p| is_ally(p))
                .cloned()
                .collect(),
        }
    }

    /// Put the saved world back `shift` ticks after it was taken. Hostile
    /// bodies and everything in flight are removed; participants stay and are
    /// restored by the caller.
    pub(crate) fn restore_checkpoint_world(&mut self, save: &WorldSave, shift: u64) {
        if let (Some(current), Some(saved)) =
            (self.replay_id_counter.as_mut(), save.replay_id_counter)
        {
            *current = (*current).max(saved);
        }
        self.clear_grenades();
        self.clear_remote_mines();
        self.traveling_shots.clear();
        self.assessor_canisters.clear();
        self.shot_results.clear();
        self.explosion_results.clear();
        self.spawn_shields.clear();
        self.map = save.map.clone();
        self.pickups = save.pickups.clone();
        self.vehicles = save.vehicles.clone();
        for jeep in &mut self.vehicles {
            jeep.gun_ready = jeep.gun_ready.saturating_add(shift);
        }
        self.walker = save.walker.clone();
        if let Some(walker) = self.walker.as_mut() {
            walker.state.phase_started = walker.state.phase_started.saturating_add(shift);
            walker.state.phase_ends = walker.state.phase_ends.saturating_add(shift);
        }
        self.foundry = save.foundry.clone();
        self.article_blade = save.article_blade.clone();
        if let Some(blade) = self.article_blade.as_mut() {
            blade.shift_ticks(shift);
        }
        self.dropped_guns = save.dropped_guns.clone();
        for gun in &mut self.dropped_guns {
            gun.expires_at = gun.expires_at.saturating_add(shift);
        }
        self.mines = save.mines.clone();
        for mine in &mut self.mines {
            mine.shift_ticks(shift);
        }
        self.players.retain(Player::is_participant);
        for ally in &save.allies {
            let mut ally = ally.clone();
            if let Some(CampaignActor::Companion { phase_started, .. }) = ally.campaign.as_mut() {
                *phase_started = phase_started.saturating_add(shift);
            }
            ally.last_speak_tick = ally.last_speak_tick.map(|t| t.saturating_add(shift));
            ally.clear_input();
            ally.just_fired = false;
            ally.reset_movement_baseline();
            self.players.push(ally);
        }
    }
}

impl WorldSave {
    /// The world a checkpoint read from a run file stands in, rebuilt from
    /// the mission content by its recorded steps.
    pub(crate) fn rebuild_map(&mut self, map: crate::maps::RuntimeMap) {
        self.map = map;
    }

    /// Bounds a decoded world must keep before it touches the simulation.
    pub(crate) fn validate(&self) -> Result<(), &'static str> {
        const MAX_BODIES: usize = 64;
        // Keep an entire u64's allocation headroom in the u128 counter, even
        // when the decoded file was edited rather than written by a survey.
        if self
            .replay_id_counter
            .is_some_and(|counter| counter > u128::from(u64::MAX))
        {
            return Err("saved checkpoint replay identity counter is out of bounds");
        }
        if self.allies.len() > MAX_BODIES
            || self.pickups.len() > 1_024
            || self.mines.len() > 256
            || self.dropped_guns.len() > 256
            || self.vehicles.len() > 32
        {
            return Err("saved checkpoint world holds too many things");
        }
        if !self.allies.iter().all(|ally| {
            is_ally(ally)
                && [ally.x, ally.y, ally.z, ally.yaw, ally.pitch]
                    .iter()
                    .all(|v| v.is_finite())
        }) {
            return Err("saved checkpoint ally is out of bounds");
        }
        Ok(())
    }
}

#[cfg(test)]
impl WorldSave {
    /// Each saved pad and whether it was available.
    pub(crate) fn pads(&self) -> Vec<(String, bool)> {
        self.pickups
            .iter()
            .map(|pad| (pad.id.clone(), pad.available))
            .collect()
    }
}
