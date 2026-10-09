//! Sticking flight and deliberate detonation for independently counted charges.
//! Admission, owned stock and resolved blast application remain with GameState.
use super::{grenade, mine, GameState, PLAYER_FLOOR_Y};
use crate::movement::Arena;
use crate::protocol::{RemoteMinePhase, RemoteMineState};
use uuid::Uuid;

pub use crate::protocol::{
    REMOTE_MINE_ARMING_TICKS as ARMING_TICKS, REMOTE_MINE_TRIGGER_TICKS as TRIGGER_TICKS,
};
pub const LIVE_PER_OWNER: usize = 4;
pub const LIVE_GLOBAL: usize = 32;
pub const PLACE_COOLDOWN: u32 = mine::PLACE_COOLDOWN;
pub const BLAST_RADIUS: f32 = mine::BLAST_RADIUS;
pub const BLAST_DAMAGE: f32 = mine::BLAST_DAMAGE;
pub const FLIGHT_TICKS: u64 = mine::FLIGHT_TICKS;
const PLACE_SPEED: f32 = 8.0;
const PLACE_LIFT: f32 = 2.0;

/// One outcome from an ordinary authoritative device tick. A terminal outcome
/// is reported once; the owner removes the device and resolves a detonation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RemoteStep {
    Live,
    Expired,
    Detonate,
    Removed,
}

#[derive(Debug, Clone)]
pub struct RemoteMine {
    state: RemoteMineState,
    velocity: [f32; 3],
    last_tick: u64,
    removed: bool,
}

impl RemoteMine {
    /// Construct only after admission and finite-stock checks. The actual
    /// muzzle-sized sphere must be clear of the current world before launch.
    pub fn launch(
        id: u32,
        owner_id: Uuid,
        origin: [f32; 3],
        facing: [f32; 2],
        tick: u64,
        arena: &Arena,
    ) -> Result<Self, &'static str> {
        let [yaw, pitch] = facing;
        if !grenade::clear_sphere(origin, arena)
            || !yaw.is_finite()
            || !pitch.is_finite()
            || pitch.abs() > crate::combat::PITCH_LIMIT
        {
            return Err("invalid remote mine launch");
        }
        let state = RemoteMineState {
            id,
            owner_id,
            position: origin,
            normal: [0.0; 3],
            phase: RemoteMinePhase::Flying,
            phase_started: tick,
            phase_ends: tick,
        };
        state.validate(tick)?;
        let horizontal = pitch.cos() * PLACE_SPEED;
        Ok(Self {
            state,
            velocity: [
                yaw.cos() * horizontal,
                pitch.sin() * PLACE_SPEED + PLACE_LIFT,
                yaw.sin() * horizontal,
            ],
            last_tick: tick,
            removed: false,
        })
    }

    pub fn state(&self) -> &RemoteMineState {
        &self.state
    }

    /// An explicit fresh command commits an already armed charge. Requests
    /// during flight or arming are refused, with no later queued detonation.
    pub fn trigger(&mut self, tick: u64) -> Result<bool, &'static str> {
        self.state.validate(tick)?;
        if tick < self.last_tick {
            return Err("remote mine tick moved backwards");
        }
        if self.removed || self.state.phase != RemoteMinePhase::Armed {
            return Ok(false);
        }
        self.transition(RemoteMinePhase::Triggered, tick, TRIGGER_TICKS)?;
        Ok(true)
    }

    /// Advance at most one server tick. Bodies and gunfire do not supply a
    /// trigger to this device; only the explicit armed transition does.
    pub fn advance(
        &mut self,
        tick: u64,
        dt: f32,
        arena: &Arena,
    ) -> Result<RemoteStep, &'static str> {
        let mut next = self.clone();
        let outcome = next.advance_checked(tick, dt, arena)?;
        *self = next;
        Ok(outcome)
    }

    fn advance_checked(
        &mut self,
        tick: u64,
        dt: f32,
        arena: &Arena,
    ) -> Result<RemoteStep, &'static str> {
        self.state.validate(tick)?;
        if tick < self.last_tick || !dt.is_finite() || dt <= 0.0 {
            return Err("invalid remote mine tick");
        }
        if self.removed {
            return Ok(RemoteStep::Removed);
        }
        if tick == self.last_tick {
            return Ok(RemoteStep::Live);
        }
        self.last_tick = tick;
        match self.state.phase {
            RemoteMinePhase::Flying => {
                if tick.saturating_sub(self.state.phase_started) >= FLIGHT_TICKS {
                    self.removed = true;
                    return Ok(RemoteStep::Expired);
                }
                if let Some(normal) = mine::fly_device(
                    &mut self.state.position,
                    &mut self.velocity,
                    dt.min(crate::movement::DT_LIVE),
                    arena,
                ) {
                    self.state.normal = normal;
                    self.velocity = [0.0; 3];
                    self.transition(RemoteMinePhase::Arming, tick, ARMING_TICKS)?;
                }
            }
            RemoteMinePhase::Arming => {
                if tick >= self.state.phase_ends {
                    self.transition(RemoteMinePhase::Armed, tick, 0)?;
                }
            }
            RemoteMinePhase::Armed => {}
            RemoteMinePhase::Triggered => {
                if tick >= self.state.phase_ends {
                    self.removed = true;
                    return Ok(RemoteStep::Detonate);
                }
            }
        }
        self.state.validate(tick)?;
        Ok(RemoteStep::Live)
    }

    fn transition(
        &mut self,
        phase: RemoteMinePhase,
        tick: u64,
        duration: u64,
    ) -> Result<(), &'static str> {
        let mut next = self.state.clone();
        next.phase = phase;
        next.phase_started = tick;
        next.phase_ends = tick
            .checked_add(duration)
            .ok_or("remote mine tick overflow")?;
        next.validate(tick)?;
        self.state = next;
        Ok(())
    }
}

/// A fresh owner command affects every currently armed owned device, never
/// another owner's charge or one still in its launch/arming window.
pub fn trigger_owned(
    charges: &mut [RemoteMine],
    owner_id: Uuid,
    tick: u64,
) -> Result<usize, &'static str> {
    // Validate before changing any charge, so an invalid clock cannot partially
    // commit a multi-charge command.
    for charge in charges.iter().filter(|c| c.state.owner_id == owner_id) {
        charge.state.validate(tick)?;
        if tick < charge.last_tick {
            return Err("remote mine tick moved backwards");
        }
        if charge.state.phase == RemoteMinePhase::Armed && !charge.removed {
            let mut next = charge.state.clone();
            next.phase = RemoteMinePhase::Triggered;
            next.phase_started = tick;
            next.phase_ends = tick
                .checked_add(TRIGGER_TICKS)
                .ok_or("remote mine tick overflow")?;
            next.validate(tick)?;
        }
    }
    let mut count = 0;
    for charge in charges.iter_mut().filter(|c| c.state.owner_id == owner_id) {
        count += usize::from(charge.trigger(tick)?);
    }
    Ok(count)
}

impl GameState {
    pub(super) fn retire_dead_remote_owners(&mut self) {
        let players = &self.players;
        self.remote_mines.retain(|mine| {
            players.iter().any(|player| {
                player.id == mine.state.owner_id && player.hp > 0 && player.respawn_timer.is_none()
            })
        });
    }

    pub(crate) fn clear_remote_mines(&mut self) {
        self.remote_mines.clear();
        for player in &mut self.players {
            player.remote_place_requested = false;
            player.remote_trigger_requested = false;
            player.remote_cooldown = 0;
        }
    }

    pub(super) fn remote_mine_states(&self) -> Vec<RemoteMineState> {
        self.remote_mines
            .iter()
            .map(|mine| mine.state.clone())
            .collect()
    }

    /// Count exactly one admitted placement. Earlier explosive placements
    /// own this attack frame; every refusal preserves stock and counters.
    pub(super) fn place_remote_mines(&mut self, launched: &[Uuid]) -> Vec<Uuid> {
        if !self
            .players
            .iter()
            .any(|player| player.remote_place_requested)
        {
            return Vec::new();
        }
        let arena = self.current_arena().into_owned();
        let mut placed = Vec::new();
        for player in &mut self.players {
            let requested = std::mem::take(&mut player.remote_place_requested);
            if !requested
                || launched.contains(&player.id)
                || player.hp <= 0
                || player.detached
                || !player.is_participant()
                || player.remote_cooldown > 0
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
                || self.remote_mines.len() >= LIVE_GLOBAL
                || self
                    .remote_mines
                    .iter()
                    .filter(|mine| mine.state.owner_id == player.id)
                    .count()
                    >= LIVE_PER_OWNER
            {
                continue;
            }
            let Some(serial) = self.projectile_serial.checked_add(1) else {
                continue;
            };
            let origin = [
                player.x,
                player.y - PLAYER_FLOOR_Y
                    + crate::combat::stance_eye(player.campaign, player.ducking),
                player.z,
            ];
            let Ok(device) = RemoteMine::launch(
                serial,
                player.id,
                origin,
                [player.yaw, player.pitch],
                self.tick,
                &arena,
            ) else {
                continue;
            };
            if !player.inventory.try_place_remote_mine() {
                continue;
            }
            self.projectile_serial = serial;
            self.remote_mines.push(device);
            player.remote_cooldown = PLACE_COOLDOWN;
            player.statistics.remote_mine_attack();
            placed.push(player.id);
        }
        placed
    }

    /// Consume a fresh trigger, never retain it until a later charge arms.
    pub(super) fn trigger_remote_mines(&mut self) {
        for player in &mut self.players {
            let requested = std::mem::take(&mut player.remote_trigger_requested);
            if !requested
                || player.hp <= 0
                || player.detached
                || !player.is_participant()
                || !crate::mission::actor_active(self.mission.as_ref(), player.id, player.campaign)
            {
                continue;
            }
            if let Err(reason) = trigger_owned(&mut self.remote_mines, player.id, self.tick) {
                tracing::warn!(reason, "Remote Mine trigger refused invalid device state");
            }
        }
    }

    pub(super) fn tick_remote_mines(&mut self, dt: f32) {
        if self.remote_mines.is_empty() {
            return;
        }
        let arena = self.current_arena().into_owned();
        let tick = self.tick;
        let mut live = std::mem::take(&mut self.remote_mines);
        live.retain(|mine| self.remote_owner_alive(mine.state.owner_id));
        let mut survivors = Vec::with_capacity(live.len());
        for mut mine in live {
            // A preceding charge may kill an owner in the same tick. Their
            // remaining owned devices go dark rather than becoming grenades.
            if !self.remote_owner_alive(mine.state.owner_id) {
                continue;
            }
            match mine.advance(tick, dt, &arena) {
                Ok(RemoteStep::Live) => survivors.push(mine),
                Ok(RemoteStep::Detonate) => self.resolve_blast(
                    &grenade::Blast {
                        id: mine.state.id,
                        owner_id: mine.state.owner_id,
                        position: mine.state.position,
                        radius: BLAST_RADIUS,
                        peak: BLAST_DAMAGE,
                        source: grenade::BlastSource::RemoteMine,
                    },
                    &arena,
                ),
                Ok(RemoteStep::Expired | RemoteStep::Removed) => {}
                Err(reason) => {
                    tracing::warn!(reason, "Remote Mine removed after invalid device tick");
                }
            }
        }
        survivors.retain(|mine| self.remote_owner_alive(mine.state.owner_id));
        self.remote_mines = survivors;
    }

    fn remote_owner_alive(&self, owner: Uuid) -> bool {
        self.players
            .iter()
            .any(|player| player.id == owner && player.hp > 0 && player.respawn_timer.is_none())
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod live_tests;
