//! Bounded ordered delivery with one replaceable pending world. Resolved
//! combat and discrete state changes remain in their original FIFO positions.

use crate::protocol::{PlayerState, ServerMessage, Snapshot};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc::error::TryRecvError;
use tokio::sync::Notify;

struct State {
    queue: VecDeque<ServerMessage>,
    pending_world: Option<usize>,
    capacity: usize,
    senders: usize,
    closed: bool,
}

struct Shared {
    state: Mutex<State>,
    ready: Notify,
}

pub struct WsTx(Arc<Shared>);
pub struct WsRx(Arc<Shared>);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Queued {
    Added,
    ReplacedWorld,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QueueError {
    Full,
    Closed,
}

pub fn channel(capacity: usize) -> (WsTx, WsRx) {
    assert!(capacity > 0, "outbound capacity must be positive");
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            queue: VecDeque::with_capacity(capacity),
            pending_world: None,
            capacity,
            senders: 1,
            closed: false,
        }),
        ready: Notify::new(),
    });
    (WsTx(Arc::clone(&shared)), WsRx(shared))
}

impl Clone for WsTx {
    fn clone(&self) -> Self {
        self.0
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .senders += 1;
        Self(Arc::clone(&self.0))
    }
}

impl Drop for WsTx {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        state.senders -= 1;
        if state.senders == 0 {
            self.0.ready.notify_one();
        }
    }
}

impl WsTx {
    pub fn try_send(&self, message: ServerMessage) -> Result<Queued, QueueError> {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.closed {
            return Err(QueueError::Closed);
        }
        let replace = match (&message, state.pending_world) {
            (ServerMessage::Snapshot(new), Some(index)) => match &state.queue[index] {
                ServerMessage::Snapshot(old) => can_replace(old, new),
                _ => unreachable!("pending world must index a snapshot"),
            },
            _ => false,
        };
        if !replace && state.queue.len() == state.capacity {
            return Err(QueueError::Full);
        }
        if replace {
            let index = state.pending_world.take().expect("replacement has a world");
            state.queue.remove(index);
        }
        if matches!(message, ServerMessage::Snapshot(_)) {
            // A predecessor that cannot be replaced becomes a reliable fact
            // carrier. Moving the latest world to the tail preserves geometry,
            // events and acknowledgements that arrived in between.
            state.pending_world = Some(state.queue.len());
        } else if matches!(
            message,
            ServerMessage::MapInfo { .. } | ServerMessage::Mission { .. }
        ) {
            // Never compare or replace a world across a geometry/mission
            // boundary, even when both worlds reuse the same map id.
            state.pending_world = None;
        }
        state.queue.push_back(message);
        drop(state);
        self.0.ready.notify_one();
        Ok(if replace {
            Queued::ReplacedWorld
        } else {
            Queued::Added
        })
    }

    pub fn depth(&self) -> usize {
        self.0
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .queue
            .len()
    }
}

impl WsRx {
    pub fn try_recv(&mut self) -> Result<ServerMessage, TryRecvError> {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(message) = state.queue.pop_front() {
            state.pending_world = state.pending_world.and_then(|index| index.checked_sub(1));
            Ok(message)
        } else if state.senders == 0 {
            Err(TryRecvError::Disconnected)
        } else {
            Err(TryRecvError::Empty)
        }
    }

    pub async fn recv(&mut self) -> Option<ServerMessage> {
        loop {
            // There is only one consumer. A send after try_recv stores a Notify
            // permit, so neither this wait nor cancelling it can lose a wakeup.
            match self.try_recv() {
                Ok(message) => return Some(message),
                Err(TryRecvError::Disconnected) => return None,
                Err(TryRecvError::Empty) => self.0.ready.notified().await,
            }
        }
    }
}

impl Drop for WsRx {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().unwrap_or_else(|e| e.into_inner());
        state.closed = true;
        state.queue.clear();
        state.pending_world = None;
    }
}

/// Deliberately enumerate the entire snapshot: adding a field requires deciding
/// whether it is replaceable motion or an exact fact. No serialization on the
/// enqueue path. Transient combat is retained even if a later shot looks equal.
fn can_replace(old: &Snapshot, new: &Snapshot) -> bool {
    let Snapshot {
        vehicles,
        tick,
        players,
        round_state,
        round_time_left: _,
        frag_limit,
        shot_results,
        projectiles,
        grenades,
        mines,
        remote_mines,
        auditors,
        explosions,
        mode_name,
        playlist,
        pressure,
        host_line,
        mvp,
        mvp_frags,
        pickups,
        map_id,
        map_name,
        episode_id,
        episode_title,
        episode_objective,
        episode_progress,
        episode_phase,
        jammer_dish,
        team_scores,
        flags,
        capture_scores,
        capture_limit,
        sabotage,
        conquest,
    } = old;
    vehicles.len() == new.vehicles.len()
        && vehicles
            .iter()
            .zip(&new.vehicles)
            .all(|(a, b)| same_vehicle_facts(a, b))
        && *tick < new.tick
        && shot_results.is_empty()
        && explosions.is_empty()
        && players.len() == new.players.len()
        && players
            .iter()
            .zip(&new.players)
            .all(|(a, b)| same_player_facts(a, b))
        && round_state == &new.round_state
        && frag_limit == &new.frag_limit
        && projectiles == &new.projectiles
        && grenades == &new.grenades
        && mines == &new.mines
        && remote_mines == &new.remote_mines
        && auditors == &new.auditors
        && mode_name == &new.mode_name
        && playlist == &new.playlist
        && pressure == &new.pressure
        && host_line == &new.host_line
        && mvp == &new.mvp
        && mvp_frags == &new.mvp_frags
        && pickups.len() == new.pickups.len()
        && pickups.iter().zip(&new.pickups).all(|(a, b)| {
            // A countdown is superseded; availability and all supply facts are exact.
            let mut prior = a.clone();
            prior.respawn_in = b.respawn_in;
            prior == *b
        })
        && map_id == &new.map_id
        && map_name == &new.map_name
        && episode_id == &new.episode_id
        && episode_title == &new.episode_title
        && episode_objective == &new.episode_objective
        && episode_progress == &new.episode_progress
        && episode_phase == &new.episode_phase
        && jammer_dish == &new.jammer_dish
        && team_scores == &new.team_scores
        && flags == &new.flags
        && capture_scores == &new.capture_scores
        && capture_limit == &new.capture_limit
        && same_sabotage_facts(sabotage.as_ref(), new.sabotage.as_ref())
        && conquest == &new.conquest
}

fn same_vehicle_facts(
    old: &crate::protocol::VehicleState,
    new: &crate::protocol::VehicleState,
) -> bool {
    let crate::protocol::VehicleState {
        id,
        kind,
        position: _,
        yaw: _,
        speed: _,
        vy: _,
        hp,
        driver,
        gunner,
        gun_heat: _,
        burning_ticks,
        control_ready_tick,
    } = old;
    id == &new.id
        && kind == &new.kind
        && hp == &new.hp
        && driver == &new.driver
        && gunner == &new.gunner
        && (*burning_ticks > 0) == (new.burning_ticks > 0)
        && control_ready_tick == &new.control_ready_tick
}

fn same_player_facts(old: &PlayerState, new: &PlayerState) -> bool {
    let PlayerState {
        collidable,
        campaign,
        id,
        name,
        x: _,
        y: _,
        z: _,
        yaw: _,
        pitch: _,
        hp,
        armor,
        just_fired,
        behavior,
        score,
        deaths,
        attacks,
        connects,
        heads,
        damage,
        weapon,
        team,
        lives,
        golden,
        ducking,
        body,
    } = old;
    !just_fired
        && collidable == &new.collidable
        && campaign == &new.campaign
        && id == &new.id
        && name == &new.name
        && hp == &new.hp
        && armor == &new.armor
        && behavior == &new.behavior
        && score == &new.score
        && deaths == &new.deaths
        && attacks == &new.attacks
        && connects == &new.connects
        && heads == &new.heads
        && damage == &new.damage
        && weapon == &new.weapon
        && team == &new.team
        && lives == &new.lives
        && golden == &new.golden
        && ducking == &new.ducking
        && body == &new.body
}

fn same_sabotage_facts(
    old: Option<&crate::protocol::SabotageState>,
    new: Option<&crate::protocol::SabotageState>,
) -> bool {
    match (old, new) {
        (None, None) => true,
        (Some(old), Some(new)) => {
            let mut prior = old.clone();
            prior.clock_ticks = new.clock_ticks;
            if let (Some(a), Some(b)) = (&mut prior.charge, &new.charge) {
                a.position = b.position;
            }
            if let (Some(a), Some(b)) = (&mut prior.progress, &new.progress) {
                a.ticks = b.ticks;
            }
            prior == *new
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests;
