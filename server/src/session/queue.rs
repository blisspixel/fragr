//! The Duel line: watchers wait for a seat, the winner stays, and the
//! loser of a round passes the seat to the head of the line.
//!
//! A watcher asks with `queue`. Whenever a seat can be had (a free seat, or
//! a rule bot's seat under automatic fill) the head of the line is called
//! with a one-time token, and the next Hello carrying it is the only fighter
//! admitted until it arrives or the call lapses. When a round between two
//! people ends with a winner and somebody is waiting, the loser's socket is
//! closed with `duel_seat_passed` and the head of the line is called to that
//! seat. Rule bots never queue and a level round passes nobody.
use super::*;
use crate::protocol::{GameMode, HostReactionKind};
use std::time::{Duration, Instant};

/// How long a called watcher has to take the seat.
pub(crate) const SEAT_CALL_TIMEOUT: Duration = Duration::from_secs(10);
/// How long a called watcher's admission waits for the passed seat's socket
/// to let it go.
pub(crate) const SEAT_RELEASE_WAIT: Duration = Duration::from_secs(2);
/// The longest line the room shows; later arrivals are refused a place.
pub(crate) const QUEUE_LIMIT: usize = 16;

/// A seat held for one called watcher.
#[derive(Debug, Clone)]
pub struct SeatHold {
    token: String,
    deadline: Instant,
}

/// Shared between the tick owner, which calls, and admission, which admits.
pub type SeatHolds = Arc<std::sync::Mutex<Option<SeatHold>>>;

/// What admission does with a fighter Hello while seats may be held.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Admit {
    /// Nothing is held: the ordinary seat rules apply.
    Open,
    /// This Hello carries the held seat's token; the hold is spent.
    Holder,
    /// A seat is held for somebody else.
    Held,
}

/// Decide a fighter Hello against the current hold. A lapsed hold is gone.
pub fn admit(holds: &SeatHolds, token: Option<&str>, now: Instant) -> Admit {
    let mut guard = holds.lock().unwrap_or_else(|error| error.into_inner());
    let Some(hold) = guard.as_ref() else {
        return Admit::Open;
    };
    if now >= hold.deadline {
        *guard = None;
        return Admit::Open;
    }
    if token == Some(hold.token.as_str()) {
        *guard = None;
        return Admit::Holder;
    }
    Admit::Held
}

impl GameSession {
    /// The shared seat holds, for the listener's admission.
    pub(crate) fn seat_holds(&self) -> SeatHolds {
        Arc::clone(&self.seat_holds)
    }

    fn hold_active(&self) -> bool {
        let mut guard = self
            .seat_holds
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if guard
            .as_ref()
            .is_some_and(|hold| Instant::now() >= hold.deadline)
        {
            *guard = None;
        }
        guard.is_some()
    }

    /// A seat the line can be called to: one nobody holds, counted against
    /// a held call, so automatic fill leaves it for the caller.
    pub(super) fn held_seats(&self) -> usize {
        usize::from(self.hold_active())
    }

    /// A watcher joins the line or steps out of it. Only in a Duel, and only
    /// a watcher: a fighter already has a seat.
    pub(super) fn queue_request(&mut self, client_id: Uuid, wait: bool) {
        if self.state.config.rules.mode() != GameMode::Duel
            || !self.spectators.contains_key(&client_id)
        {
            return;
        }
        let queued = self.duel_queue.contains(&client_id);
        if wait && !queued && self.duel_queue.len() < QUEUE_LIMIT {
            self.duel_queue.push(client_id);
        } else if !wait && queued {
            self.duel_queue.retain(|id| *id != client_id);
        }
        self.sync_queue_names();
    }

    /// A watcher's socket left: it leaves the line too.
    pub(super) fn leave_queue(&mut self, client_id: Uuid) {
        if self.duel_queue.contains(&client_id) {
            self.duel_queue.retain(|id| *id != client_id);
            self.sync_queue_names();
        }
    }

    fn sync_queue_names(&mut self) {
        self.state.duel_queue = self
            .duel_queue
            .iter()
            .filter_map(|id| self.spectators.get(id).map(|seat| seat.name.clone()))
            .collect();
    }

    /// Sockets whose fighters lost and passed their seat, for the tick
    /// owner to close.
    pub fn take_seat_passes(&mut self) -> Vec<Uuid> {
        std::mem::take(&mut self.seat_passes)
    }

    /// A seat that can be had right now without moving a person.
    fn seat_open(&self) -> bool {
        let free = self
            .participant_slots
            .as_ref()
            .is_some_and(|slots| slots.available_permits() > 0);
        free || (self.auto_fill_target.is_some() && !self.bot_seats.is_empty())
    }

    /// Once a tick: call the line to an open seat, or at a decided round's
    /// end pass the loser's seat to it.
    pub(super) fn tick_duel_queue(&mut self) {
        if self.state.config.rules.mode() != GameMode::Duel {
            if !self.duel_queue.is_empty() {
                self.duel_queue.clear();
                self.sync_queue_names();
            }
            return;
        }
        if self.duel_queue.is_empty() || self.hold_active() {
            return;
        }
        if self.state.round_state == crate::sim::RoundState::Ended
            && self.benched_round != Some(self.state.round_number)
        {
            self.benched_round = Some(self.state.round_number);
            if let Some([winner, loser]) = self.state.duel_result {
                if let Some(client) = self.live_client.get(&loser).copied() {
                    let winner = self.state.name_of(winner);
                    if self.call_head(winner) {
                        tracing::info!(target: crate::logging::FEED_TARGET, "DUEL: winner stays, the loser passes the seat");
                        self.seat_passes.push(client);
                    }
                    return;
                }
            }
        }
        if self.seat_open() {
            self.call_head(None);
        }
    }

    /// Call the first watcher still here to the next seat. False when the
    /// line had nobody left to call.
    fn call_head(&mut self, winner: Option<String>) -> bool {
        while !self.duel_queue.is_empty() {
            let client_id = self.duel_queue.remove(0);
            let Some(name) = self
                .spectators
                .get(&client_id)
                .map(|seat| seat.name.clone())
            else {
                continue;
            };
            let token = Uuid::new_v4().simple().to_string();
            *self
                .seat_holds
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Some(SeatHold {
                token: token.clone(),
                deadline: Instant::now() + SEAT_CALL_TIMEOUT,
            });
            self.pending_unicasts.push((
                Recipient::Client(client_id),
                ServerMessage::SeatCall { seat: token },
            ));
            self.state
                .react(HostReactionKind::NextUp, Some(name), winner, None);
            self.sync_queue_names();
            return true;
        }
        self.sync_queue_names();
        false
    }
}

#[cfg(test)]
mod tests;
