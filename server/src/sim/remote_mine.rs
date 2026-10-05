//! Sticking flight and deliberate detonation for independently counted charges.
//! Admission, owned stock and resolved blast application remain with GameState.
use super::{grenade, mine};
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

#[cfg(test)]
mod tests;
