//! Objective callouts (#432 Milestone 5, the multiplayer part): a named rule
//! bot tells its own side, in text, when a CTF or Sabotage objective turns.
//! It has the enemy flag, it sees the fighter carrying its side's flag, it
//! planted the charge, it is defusing. Lines come from the callsign's register
//! (`roster::callouts`) and go out as `speak` events addressed to the side.
//!
//! They stay rare and out of the Host's way. A side hears at most one call
//! every `CALLOUT_GAP_TICKS`; a call waits `CALLOUT_AFTER_HOST_TICKS` after
//! any Host call, so the corner caption and the feed line never land
//! together; the speaker's own speak cooldown still applies; and a call that
//! cannot be said while it is still true is dropped. A carrier is called only
//! by a bot that sees it through the shared senses, once per carry.

use super::{GameState, RoundState, SpeakOutcome};
use crate::protocol::{ProgressKind, SabotagePhase, Team};
use crate::roster::{ObjectiveCall, Reach};
use uuid::Uuid;

/// One side hears at most one callout this often: fifteen seconds.
pub(crate) const CALLOUT_GAP_TICKS: u64 = 20 * 15;
/// A callout waits this long after any Host call.
pub(crate) const CALLOUT_AFTER_HOST_TICKS: u64 = 20 * 2;
/// A callout not said inside this window is old news and dropped.
pub(crate) const CALLOUT_STALE_TICKS: u64 = 20 * 4;

#[derive(Debug, Clone, Copy, PartialEq)]
struct Pending {
    speaker: Uuid,
    team: Team,
    call: ObjectiveCall,
    at: u64,
}

/// Per-round callout memory, kept beside the Host's.
#[derive(Debug, Clone, Default)]
pub(super) struct CalloutBook {
    pending: Vec<Pending>,
    /// When each side last heard a call.
    last: [Option<u64>; 2],
    /// The carrier of each side's flag already called on this carry.
    carrier_called: [Option<Uuid>; 2],
}

/// Where `feet` sits on the line from the stand a flag was taken from
/// (`from`) to the stand its carrier scores at (`to`): thirds.
fn reach(feet: [f32; 3], from: [f32; 3], to: [f32; 3]) -> Reach {
    let axis = [to[0] - from[0], to[2] - from[2]];
    let length = axis[0] * axis[0] + axis[1] * axis[1];
    if length <= f32::EPSILON {
        return Reach::Mid;
    }
    let along = ((feet[0] - from[0]) * axis[0] + (feet[2] - from[2]) * axis[1]) / length;
    if along < 1.0 / 3.0 {
        Reach::OurStand
    } else if along > 2.0 / 3.0 {
        Reach::TheirStand
    } else {
        Reach::Mid
    }
}

impl GameState {
    /// A named rule bot's objective moment, said to its side when the
    /// spacing allows. Anyone else's moment is the Host's business.
    pub(super) fn queue_callout(&mut self, speaker: Uuid, call: ObjectiveCall) {
        if self.round_state != RoundState::Active || !self.is_named_rule_bot(speaker) {
            return;
        }
        let Some(team) = self
            .players
            .iter()
            .find(|player| player.id == speaker)
            .and_then(|player| player.team)
        else {
            return;
        };
        let book = &mut self.reactions.callouts;
        if book
            .pending
            .iter()
            .any(|item| item.team == team && item.call == call)
        {
            return;
        }
        book.pending.push(Pending {
            speaker,
            team,
            call,
            at: self.tick,
        });
    }

    /// Whether a waiting call is still true: the speaker still carries the
    /// flag, the carrier still runs, the charge is still down, the defuse
    /// still goes on.
    fn callout_holds(&self, item: &Pending) -> bool {
        let standing = self
            .players
            .iter()
            .any(|player| player.id == item.speaker && player.standing() && !player.detached);
        if !standing {
            return false;
        }
        match item.call {
            ObjectiveCall::HaveFlag => self.flags.as_ref().is_some_and(|flags| {
                flags[item.team.other().index()].carrier == Some(item.speaker)
            }),
            ObjectiveCall::EnemyCarrier(_) => self
                .flags
                .as_ref()
                .is_some_and(|flags| flags[item.team.index()].carrier.is_some()),
            ObjectiveCall::Planted(_) => self
                .sabotage
                .as_ref()
                .is_some_and(|sab| sab.phase == SabotagePhase::Planted),
            ObjectiveCall::Defusing(_) => self.sabotage.as_ref().is_some_and(|sab| {
                sab.hold.as_ref().is_some_and(|hold| {
                    hold.kind == ProgressKind::Defuse && hold.player == item.speaker
                })
            }),
        }
    }

    /// A rule bot that sees the fighter carrying its side's flag calls where
    /// it is, once per carry. Only what its senses hold this tick counts.
    fn spot_carriers(&mut self) {
        let Some(flags) = self.flags.as_ref() else {
            return;
        };
        let mut calls = Vec::new();
        for team in Team::ALL {
            let flag = &flags[team.index()];
            let Some(carrier) = flag.carrier else {
                self.reactions.callouts.carrier_called[team.index()] = None;
                continue;
            };
            if self.reactions.callouts.carrier_called[team.index()] == Some(carrier) {
                continue;
            }
            let scores_at = flags[team.other().index()].stand;
            let spotter = self.bots.iter().find_map(|controller| {
                let bot = self.players.iter().find(|player| {
                    player.id == controller.player_id
                        && player.team == Some(team)
                        && player.standing()
                })?;
                let (seen, feet) = bot.bot_senses.sees_now(self.tick)?;
                (seen == carrier).then_some((bot.id, feet))
            });
            if let Some((spotter, feet)) = spotter {
                calls.push((team, carrier, spotter, reach(feet, flag.stand, scores_at)));
            }
        }
        for (team, carrier, spotter, reach) in calls {
            self.reactions.callouts.carrier_called[team.index()] = Some(carrier);
            self.queue_callout(spotter, ObjectiveCall::EnemyCarrier(reach));
        }
    }

    /// Spot carriers, then say what the spacing allows. Called once a tick
    /// after the objective modes have moved.
    pub(super) fn tick_callouts(&mut self) {
        if self.round_state != RoundState::Active {
            self.reactions.callouts.pending.clear();
            return;
        }
        self.spot_carriers();
        if self.reactions.callouts.pending.is_empty() {
            return;
        }
        let tick = self.tick;
        let pending = std::mem::take(&mut self.reactions.callouts.pending);
        let mut waiting = Vec::new();
        for item in pending {
            if tick.saturating_sub(item.at) > CALLOUT_STALE_TICKS || !self.callout_holds(&item) {
                continue;
            }
            let host_quiet = self
                .reactions
                .last_tick
                .is_none_or(|last| tick >= last + CALLOUT_AFTER_HOST_TICKS);
            let side_quiet = self.reactions.callouts.last[item.team.index()]
                .is_none_or(|last| tick >= last + CALLOUT_GAP_TICKS);
            if !host_quiet || !side_quiet {
                waiting.push(item);
                continue;
            }
            let Some(line) = self
                .players
                .iter()
                .find(|player| player.id == item.speaker)
                .and_then(|player| crate::roster::objective_line(&player.name, item.call))
            else {
                continue;
            };
            match self.try_speak_to_side(item.speaker, &line, item.team) {
                SpeakOutcome::Sent => {
                    self.reactions.callouts.last[item.team.index()] = Some(tick);
                }
                SpeakOutcome::RateLimited => waiting.push(item),
                SpeakOutcome::Rejected => {}
            }
        }
        self.reactions.callouts.pending.extend(waiting);
    }
}

#[cfg(test)]
mod tests;
