//! The podium between rounds: the ready-up that starts the next round as
//! soon as everyone seated has asked for it, and a Duel's running series
//! between the same two fighters.
use super::{GameState, RoundState};
use crate::protocol::{DuelRecord, GameMode, Podium, Role};
use std::cmp::Ordering;
use uuid::Uuid;

/// A Duel's two fighters, in id order, and the rounds each has taken from
/// the other since they first met.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct DuelSeries {
    pub(crate) ids: [Uuid; 2],
    pub(crate) wins: [u32; 2],
}

impl GameState {
    /// The fighters the ready-up waits for: seated people and agents. A rule
    /// bot is always ready, and a parked resume pawn cannot press anything.
    fn again_voters(&self) -> Vec<Uuid> {
        self.players
            .iter()
            .filter(|p| {
                p.contestant()
                    && !p.detached
                    && p.role != Role::Spectator
                    && !self.is_rule_bot(p.id)
            })
            .map(|p| p.id)
            .collect()
    }

    /// An ended arena round takes ready-ups. A Sabotage match keeps its own
    /// short break between rounds, and the campaign has no podium.
    fn podium_open(&self) -> bool {
        self.round_state == RoundState::Ended
            && self.sabotage.is_none()
            && !self.map.is_campaign()
            && !self.solo_broadcast.enabled
    }

    /// `Action::again` from a seated fighter while the podium shows.
    pub(super) fn note_again(&mut self, id: Uuid) {
        if self.podium_open() && self.again_voters().contains(&id) {
            self.again.insert(id);
        }
    }

    /// Everyone the ready-up waits for has pressed, somebody has, and the
    /// result has been up long enough to read.
    pub(super) fn again_ready(&self) -> bool {
        if !self.podium_open() || self.round_ticks < crate::rules::AGAIN_MIN_TICKS {
            return false;
        }
        let voters = self.again_voters();
        !voters.is_empty() && voters.iter().all(|id| self.again.contains(id))
    }

    /// The wire podium while a round has ended: the ready-up, and a Duel's
    /// series. Absent when nobody is waited for and there is no series.
    pub(super) fn podium(&self) -> Option<Podium> {
        if self.round_state != RoundState::Ended {
            return None;
        }
        let voters = if self.podium_open() {
            self.again_voters()
        } else {
            Vec::new()
        };
        let duel = self.duel_records();
        if voters.is_empty() && duel.is_none() {
            return None;
        }
        Some(Podium {
            again: self
                .again
                .iter()
                .copied()
                .filter(|id| voters.contains(id))
                .collect(),
            voters: u32::try_from(voters.len()).unwrap_or(u32::MAX),
            duel,
        })
    }

    fn duel_records(&self) -> Option<[DuelRecord; 2]> {
        let series = self.duel_series.as_ref()?;
        let record = |side: usize| {
            let id = series.ids[side];
            self.players
                .iter()
                .find(|p| p.id == id)
                .map(|p| DuelRecord {
                    id,
                    name: p.name.clone(),
                    wins: series.wins[side],
                })
        };
        Some([record(0)?, record(1)?])
    }

    /// At a Duel round's end, credit the winner against the same opponent,
    /// or open a new series when the pair has changed. `survivor` names the
    /// last fighter standing when lives decided it; otherwise frags do, and a
    /// level round counts for nobody.
    pub(super) fn settle_duel(&mut self, survivor: Option<&str>) {
        if self.config.rules.mode() != GameMode::Duel {
            return;
        }
        let mut pair: Vec<(Uuid, u32, bool)> = self
            .players
            .iter()
            .filter(|p| p.contestant())
            .map(|p| {
                (
                    p.id,
                    self.scores.get(&p.id).copied().unwrap_or(0),
                    survivor == Some(p.name.as_str()),
                )
            })
            .collect();
        if pair.len() != 2 {
            self.duel_series = None;
            return;
        }
        pair.sort_by_key(|(id, _, _)| *id);
        let ids = [pair[0].0, pair[1].0];
        let mut series = match self.duel_series.take() {
            Some(series) if series.ids == ids => series,
            _ => DuelSeries { ids, wins: [0, 0] },
        };
        let winner = if pair[0].2 {
            Some(0)
        } else if pair[1].2 {
            Some(1)
        } else {
            match pair[0].1.cmp(&pair[1].1) {
                Ordering::Greater => Some(0),
                Ordering::Less => Some(1),
                Ordering::Equal => None,
            }
        };
        if let Some(side) = winner {
            series.wins[side] = series.wins[side].saturating_add(1);
        }
        self.duel_series = Some(series);
    }

    /// The Host's opening for a rematch: who leads the series, or that it is
    /// level. None before the pair has finished a round together.
    pub(super) fn duel_open_line(&self) -> Option<String> {
        if self.config.rules.mode() != GameMode::Duel {
            return None;
        }
        let [a, b] = self.duel_records()?;
        Some(match a.wins.cmp(&b.wins) {
            Ordering::Greater => format!(
                "HOST: REMATCH. {} LEADS {} TO {}.",
                a.name.to_uppercase(),
                a.wins,
                b.wins
            ),
            Ordering::Less => format!(
                "HOST: REMATCH. {} LEADS {} TO {}.",
                b.name.to_uppercase(),
                b.wins,
                a.wins
            ),
            Ordering::Equal if a.wins == 0 => "HOST: REMATCH. NOTHING SETTLED.".to_string(),
            Ordering::Equal => format!("HOST: REMATCH. LEVEL AT {} EACH.", a.wins),
        })
    }
}

#[cfg(test)]
mod tests;
