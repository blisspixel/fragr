//! Between rounds on a rotating server: which maps the rotation may visit,
//! and the three-map vote the podium counts down into the next round.
//!
//! A host switches maps off and on (`--map-off`, the desk's `rotation`);
//! no map is removed. The rotation and the vote only reach maps that are
//! switched on and can host the live mode. The vote offers the next three in
//! roster order after the live map, with the live map last when fewer are
//! left, so the night still walks the roster when nobody votes. Seated
//! people and agents vote; rule bots vote only when nobody else is seated,
//! and spectators never do. The leader loads when the podium closes: most
//! votes, ties to the earlier option, and no votes at all to the first.
use super::{playlist::slot_playable, GameState, MapKind, RoundState};
use crate::protocol::{GameMode, MapBallot, MapVote, MapVoteOption};
use std::collections::BTreeMap;
use uuid::Uuid;

/// The most maps a vote offers.
pub const MAP_VOTE_OPTIONS: usize = 3;
/// The podium stays up at least this long while a vote is open, so a room
/// can read its stories and choose: twelve seconds. A room that has all
/// pressed for another still skips the rest (`rules::AGAIN_MIN_TICKS`).
pub const MAP_VOTE_TICKS: u32 = 20 * 12;
/// A rule bot's ballot lands this long after the vote opens, and each
/// further bot a little later, so a watched room sees the tally move.
const BOT_BALLOT_FIRST_TICK: u32 = 20 * 2;
const BOT_BALLOT_STEP_TICKS: u32 = 12;

/// Which roster maps a host has switched on. Every map starts on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rotation {
    on: [bool; MapKind::ALL.len()],
}

impl Default for Rotation {
    fn default() -> Self {
        Self {
            on: [true; MapKind::ALL.len()],
        }
    }
}

impl Rotation {
    /// Every map on except `off`. Refuses a list that switches every map off.
    pub fn without(off: &[MapKind]) -> Result<Self, String> {
        let mut rotation = Self::default();
        for map in off {
            rotation.on[map.index()] = false;
        }
        if rotation.on.iter().all(|on| !on) {
            return Err("--map-off cannot switch off every map".into());
        }
        Ok(rotation)
    }

    pub fn is_on(&self, map: MapKind) -> bool {
        self.on[map.index()]
    }

    /// Switch one map. The last map on stays on.
    pub fn set(&mut self, map: MapKind, on: bool) -> Result<(), &'static str> {
        if !on && self.is_on(map) && self.on.iter().filter(|on| **on).count() == 1 {
            return Err("That is the last map in the rotation. Switch another on first.");
        }
        self.on[map.index()] = on;
        Ok(())
    }

    /// The maps the rotation may visit after `live` for `mode`, in roster
    /// order, with `live` itself last when it qualifies.
    pub fn after(&self, live: MapKind, mode: GameMode) -> Vec<MapKind> {
        let count = MapKind::ALL.len();
        (1..=count)
            .map(|step| MapKind::ALL[(live.index() + step) % count])
            .filter(|map| self.is_on(*map) && slot_playable(*map, mode).is_ok())
            .collect()
    }
}

/// An open vote: the offered maps in order and each voter's choice.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MapVoteState {
    pub(crate) options: Vec<MapKind>,
    pub(crate) ballots: BTreeMap<Uuid, MapKind>,
}

impl GameState {
    /// A rotating arena between rounds, with no night list or desk choice
    /// waiting. Sabotage and the campaign never open a podium.
    fn vote_applies(&self) -> bool {
        self.map_rotate
            && !self.playlist
            && self.queued_show.is_none()
            && self.round_state == RoundState::Ended
            && self.sabotage.is_none()
            && !self.map.is_campaign()
            && !self.solo_broadcast.enabled
            && matches!(self.map, crate::maps::RuntimeMap::BuiltIn(_))
    }

    /// Called as a round ends. Opens a vote when the rotation has more than
    /// one map to choose from for this mode.
    pub(super) fn open_map_vote(&mut self) {
        self.map_vote = None;
        if !self.vote_applies() {
            return;
        }
        let crate::maps::RuntimeMap::BuiltIn(live) = self.map else {
            return;
        };
        let mut options = self.rotation.after(live, self.config.rules.mode());
        options.truncate(MAP_VOTE_OPTIONS);
        if options.len() < 2 {
            return;
        }
        self.map_vote = Some(MapVoteState {
            options,
            ballots: BTreeMap::new(),
        });
    }

    /// How long the podium stays up while a vote is open.
    pub(super) fn vote_window(&self) -> u32 {
        self.config.end_delay_ticks.max(MAP_VOTE_TICKS)
    }

    /// Rule bots vote only in a room with nobody else seated.
    fn bots_vote(&self) -> bool {
        self.again_voters().is_empty()
    }

    /// `Action::vote` from a seated person or agent while the vote is open.
    pub(super) fn note_vote(&mut self, id: Uuid, map_id: u32) {
        if !self.again_voters().contains(&id) {
            return;
        }
        let Some(vote) = self.map_vote.as_mut() else {
            return;
        };
        if let Some(map) = vote.options.iter().copied().find(|map| map.id() == map_id) {
            vote.ballots.insert(id, map);
        }
    }

    /// Each Ended tick: in a room of rule bots only, each named bot casts
    /// one ballot on its own beat, from its callsign and the round.
    pub(super) fn tick_map_vote(&mut self) {
        if self.map_vote.is_none() || !self.bots_vote() {
            return;
        }
        let bots: Vec<(Uuid, String)> = self
            .bots
            .iter()
            .filter(|bot| self.is_named_rule_bot(bot.player_id))
            .filter_map(|bot| {
                self.players
                    .iter()
                    .find(|p| p.id == bot.player_id && p.contestant())
                    .map(|p| (p.id, p.name.clone()))
            })
            .collect();
        let round = self.round_number;
        let now = self.round_ticks;
        let Some(vote) = self.map_vote.as_mut() else {
            return;
        };
        for (order, (id, name)) in bots.into_iter().enumerate() {
            let beat = BOT_BALLOT_FIRST_TICK
                .saturating_add(BOT_BALLOT_STEP_TICKS.saturating_mul(order as u32));
            if now != beat || vote.ballots.contains_key(&id) {
                continue;
            }
            let pick = bot_preference(&name, round) % vote.options.len();
            vote.ballots.insert(id, vote.options[pick]);
        }
    }

    /// Votes for each option from the voters that count now: seated people
    /// and agents, or rule bots when nobody else is seated.
    fn vote_tally(&self, vote: &MapVoteState) -> Vec<u32> {
        let electorate: Vec<Uuid> = if self.bots_vote() {
            self.bots.iter().map(|bot| bot.player_id).collect()
        } else {
            self.again_voters()
        };
        let mut tally = vec![0_u32; vote.options.len()];
        for (id, map) in &vote.ballots {
            if !electorate.contains(id) {
                continue;
            }
            if let Some(index) = vote.options.iter().position(|option| option == map) {
                tally[index] = tally[index].saturating_add(1);
            }
        }
        tally
    }

    /// Most votes; a tie goes to the earlier option, so no votes at all
    /// picks the first.
    fn vote_leader(&self, vote: &MapVoteState) -> MapKind {
        let tally = self.vote_tally(vote);
        let mut best = 0;
        for (index, votes) in tally.iter().enumerate() {
            if *votes > tally[best] {
                best = index;
            }
        }
        vote.options[best]
    }

    /// The map the next round loads on a rotating server: the vote's leader,
    /// or the next map switched on that can host the mode. None stays.
    pub(super) fn next_rotation_map(&mut self) -> Option<MapKind> {
        let vote = self.map_vote.take();
        let crate::maps::RuntimeMap::BuiltIn(live) = self.map else {
            return None;
        };
        if let Some(vote) = vote {
            return Some(self.vote_leader(&vote));
        }
        self.rotation
            .after(live, self.config.rules.mode())
            .first()
            .copied()
    }

    /// The wire vote while the podium shows.
    pub(super) fn wire_map_vote(&self) -> Option<MapVote> {
        let vote = self.map_vote.as_ref()?;
        let tally = self.vote_tally(vote);
        let bots_vote = self.bots_vote();
        let electorate: Vec<Uuid> = if bots_vote {
            self.bots.iter().map(|bot| bot.player_id).collect()
        } else {
            self.again_voters()
        };
        Some(MapVote {
            options: vote
                .options
                .iter()
                .zip(&tally)
                .map(|(map, votes)| MapVoteOption {
                    map_id: map.id(),
                    map_name: map.name().to_string(),
                    votes: *votes,
                })
                .collect(),
            ballots: vote
                .ballots
                .iter()
                .filter(|(id, _)| electorate.contains(id))
                .map(|(id, map)| MapBallot {
                    id: *id,
                    map_id: map.id(),
                })
                .collect(),
            leader: self.vote_leader(vote).id(),
            closes_in: self.vote_window().saturating_sub(self.round_ticks),
            bots_vote,
        })
    }

    /// Switch one roster map on or off for the rotation, from the desk.
    pub(crate) fn set_rotation(&mut self, map: MapKind, on: bool) -> Result<String, &'static str> {
        if !self.map_rotate {
            return Err("No rotation is running. Start the server with --map-rotate.");
        }
        self.rotation.set(map, on)?;
        let mode = self.config.rules.mode();
        let fit = slot_playable(map, mode).is_ok();
        Ok(match (on, fit) {
            (true, true) => format!("{} is in the rotation.", map.name()),
            (true, false) => format!(
                "{} is on, but it cannot host {}; the rotation skips it for now.",
                map.name(),
                mode.name()
            ),
            (false, _) => format!(
                "{} is out of the rotation. A live round on it finishes first.",
                map.name()
            ),
        })
    }

    /// The desk's rotation table: every roster map, on or off, and whether
    /// it can host the live mode.
    pub(crate) fn desk_rotation(&self) -> String {
        if !self.map_rotate {
            return "No rotation is running. This show repeats.".into();
        }
        let mode = self.config.rules.mode();
        let mut lines = vec![format!("Rotation for {}:", mode.name())];
        for map in MapKind::ALL {
            let state = if !self.rotation.is_on(map) {
                "off"
            } else if slot_playable(map, mode).is_err() {
                "on, cannot host this mode"
            } else {
                "on"
            };
            lines.push(format!("{} {}: {state}", map.id(), map.name()));
        }
        lines.push("Use rotation on <map> or rotation off <map>.".into());
        lines.join("\n")
    }
}

/// A rule bot's lean for one round: stable for a callsign and a round, so a
/// replay votes the same way and different rounds lean differently.
fn bot_preference(name: &str, round: u32) -> usize {
    let base = crate::protocol::rule_bot_callsign_base(name.trim()).to_lowercase();
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in base.bytes().chain(round.to_le_bytes()) {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x0100_0000_01b3);
    }
    (hash % 1024) as usize
}

#[cfg(test)]
mod tests;
