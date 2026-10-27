//! The Duel line: watchers wait for a seat, the winner stays, and the
//! loser of a round between two people passes the seat to the head of the
//! line.
//!
//! A watcher asks with `queue`. Whenever a seat can be had (a free seat, or
//! a rule bot's seat under automatic fill) the head of the line is called
//! with a one-time token, and the next Hello carrying it is the only fighter
//! admitted until it arrives or the call lapses. When a round between two
//! people ends with a winner and somebody is waiting, the loser's socket is
//! closed with `duel_seat_passed` and the head of the line is called to that
//! seat. Only a round between two `human` fighters passes a seat: an agent
//! (MCP or the brain) has no line to return to, and a person who lost to a
//! rule bot stays to try again. Rule bots never queue and a level round
//! passes nobody. Each queued watcher is told its own place
//! (`queue_place`), because names on the shared line can repeat.
use super::*;
use crate::protocol::{GameMode, HostReactionKind};
use std::time::{Duration, Instant};

/// How long a called watcher has to take the seat.
pub(crate) const SEAT_CALL_TIMEOUT: Duration = Duration::from_secs(10);
/// How long a called watcher's admission waits for the passed seat's socket
/// to let it go: the passing socket's writer may take its whole send
/// timeout (2 s) to stop, and the seat is released only after it has.
pub(crate) const SEAT_RELEASE_WAIT: Duration = Duration::from_millis(2_500);
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
    /// This Hello carries the held seat's token. The hold stays until
    /// [`release`] spends it, once the holder actually has the seat.
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
        return Admit::Holder;
    }
    Admit::Held
}

/// Hold the next seat for `token` until `deadline`.
pub(crate) fn place_hold(holds: &SeatHolds, token: String, deadline: Instant) {
    *holds.lock().unwrap_or_else(|error| error.into_inner()) = Some(SeatHold { token, deadline });
}

/// Spend the hold for `token`, once its holder has the seat (or gave up).
pub fn release(holds: &SeatHolds, token: &str) {
    let mut guard = holds.lock().unwrap_or_else(|error| error.into_inner());
    if guard.as_ref().is_some_and(|hold| hold.token == token) {
        *guard = None;
    }
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
        if wait && !queued && self.duel_queue.len() >= QUEUE_LIMIT {
            self.pending_unicasts.push((
                Recipient::Client(client_id),
                ServerMessage::Error {
                    code: "queue_full".into(),
                    message: "The line for this duel is full. Keep watching and try again.".into(),
                },
            ));
            return;
        }
        if wait && !queued {
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

    /// Publish the line by name to the room, and tell each watcher whose
    /// place changed where they stand (0: not in line).
    fn sync_queue_names(&mut self) {
        self.duel_queue
            .retain(|id| self.spectators.contains_key(id));
        self.state.duel_queue = self
            .duel_queue
            .iter()
            .filter_map(|id| self.spectators.get(id).map(|seat| seat.name.clone()))
            .collect();
        let of = u32::try_from(self.duel_queue.len()).unwrap_or(u32::MAX);
        let mut places: HashMap<Uuid, u32> = HashMap::new();
        for (index, id) in self.duel_queue.iter().enumerate() {
            places.insert(*id, u32::try_from(index + 1).unwrap_or(u32::MAX));
        }
        let mut told: Vec<(Uuid, u32)> = Vec::new();
        for (id, place) in &places {
            if self.queue_places.get(id) != Some(place) || self.queue_size != of {
                told.push((*id, *place));
            }
        }
        for id in self.queue_places.keys() {
            if !places.contains_key(id) && self.spectators.contains_key(id) {
                told.push((*id, 0));
            }
        }
        told.sort();
        for (id, place) in told {
            self.pending_unicasts.push((
                Recipient::Client(id),
                ServerMessage::QueuePlace { place, of },
            ));
        }
        self.queue_places = places;
        self.queue_size = of;
    }

    /// A decided round passes a seat only between two people: both fighters
    /// joined as `human` and both sockets are live. An agent has no line to
    /// return to, and losing to a rule bot is a rematch, not a hand-over.
    fn passes_seat(&self, winner: Uuid, loser: Uuid) -> Option<Uuid> {
        let human = |id: Uuid| {
            self.state
                .players
                .iter()
                .any(|player| player.id == id && player.role == Role::Human)
                && self.live_client.contains_key(&id)
                && !self.bots.iter().any(|bot| bot.player_id == id)
        };
        (human(winner) && human(loser))
            .then(|| self.live_client.get(&loser).copied())
            .flatten()
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
                if let Some(client) = self.passes_seat(winner, loser) {
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
            place_hold(
                &self.seat_holds,
                token.clone(),
                Instant::now() + SEAT_CALL_TIMEOUT,
            );
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
