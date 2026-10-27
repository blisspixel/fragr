//! Observer-only per-action market facts. They split the attempt-wide public
//! challenge flags into the steps that actually lost health inside a working
//! strip, how the body came to stand there and what the controller had
//! recognized at that decision. Authoritative strips, positions and health
//! are read after the action is chosen and never return to the controller.
use super::Status;
use crate::campaign::market_guard::Guard;
use fragr_server::protocol::{AmmoPool, LoadoutState, PaverStripState};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use uuid::Uuid;

#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq)]
pub struct Facts {
    /// Rounds in the pools of owned ranged weapons at public market entry.
    /// Pools already include loaded magazines.
    pub entry_ranged_rounds: u32,
    pub decision_steps: u32,
    /// Steps whose market guard kept the shared escape or withheld ingress.
    pub escape_preserved_steps: u32,
    pub ingress_withheld_steps: u32,
    /// Health plus armor lost to published shots, by shooter name. Shot
    /// damage is the resolved value and can include overkill on a death.
    pub shot_loss: BTreeMap<String, i32>,
    /// Health plus armor lost on steps that ended inside a working strip and
    /// were not covered by shots. This is a work-pulse inference, not a
    /// server hit count.
    pub strip_loss: i32,
    /// Remaining loss with no shot and no working strip under the feet.
    pub unattributed_loss: i32,
    pub contacts: Vec<Contact>,
    pub strip_hits: Vec<StripHit>,
    pub death: Option<Death>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Arrival {
    /// The body stepped from outside onto an existing strip.
    MovedIn,
    /// A new strip was published under a body that was already standing there.
    PlacedOnBody,
    /// The first market step already found the body inside.
    AlreadyInside,
}

/// One continuous stay on one owner's strip geometry.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Contact {
    pub tick: u64,
    pub owner: String,
    pub working: bool,
    pub arrival: Arrival,
    /// The strip was in the delayed, visibility-limited observation used for
    /// this decision.
    pub recognized: bool,
    pub airborne: bool,
    pub guard: Option<Guard>,
    pub moving: bool,
    /// Other owners publishing a strip at the same step.
    pub other_strips: u8,
    pub left_tick: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StripHit {
    pub tick: u64,
    /// Every working strip under the feet after this step. Two owners mean
    /// overlapping floor rectangles, not just simultaneous strips.
    pub owners: Vec<String>,
    pub loss: i32,
    /// Shot loss resolved in the same step.
    pub shot_loss: i32,
    pub recognized: Vec<bool>,
    /// The step that first put the body inside the first owner's rectangle.
    pub inside_since: Option<u64>,
    pub arrival: Option<Arrival>,
    pub guard: Option<Guard>,
    pub airborne: bool,
    pub moving: bool,
    /// A published attack tell was in the controller's observation.
    pub telling: bool,
    pub other_strips: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Death {
    pub tick: u64,
    /// `strip`, `shot:<shooter>` or `unattributed`, for the fatal step only.
    pub cause: String,
    pub hp_before: i32,
    pub armor_before: i32,
    pub ranged_rounds: u32,
}

/// The controller's own state at one market decision, and what it chose.
pub(crate) struct Decision<'a> {
    pub tick: u64,
    pub feet: [f32; 3],
    pub hp: i32,
    pub armor: i32,
    pub airborne: bool,
    pub moving: bool,
    pub telling: bool,
    pub guard: Option<Guard>,
    /// Owners in the delayed visible observation.
    pub recognized: Vec<Uuid>,
    pub strips: &'a [PaverStripState],
    pub names: &'a BTreeMap<Uuid, String>,
}

/// What the step actually did, read after the simulation advanced.
pub(crate) struct Outcome<'a> {
    pub strips: &'a [PaverStripState],
    pub status: Option<Status>,
    pub shots: Vec<(String, i32)>,
}

#[derive(Default)]
pub(super) struct Tracker {
    inside: BTreeMap<Uuid, (usize, [f32; 3])>,
}

pub(crate) fn ranged_rounds(loadout: &LoadoutState) -> u32 {
    [
        AmmoPool::Bullets,
        AmmoPool::Shells,
        AmmoPool::Cells,
        AmmoPool::Rockets,
    ]
    .into_iter()
    .filter(|pool| {
        loadout
            .weapons
            .iter()
            .any(|weapon| weapon.ammo_pool() == Some(*pool))
    })
    .map(|pool| u32::from(loadout.ammo(pool)))
    .sum()
}

fn name(names: &BTreeMap<Uuid, String>, owner: Uuid) -> String {
    names
        .get(&owner)
        .cloned()
        .unwrap_or_else(|| owner.to_string())
}

impl Tracker {
    pub(super) fn reset(&mut self) {
        self.inside.clear();
    }

    /// End every open stay at `tick`: a terminal receipt, or the start of the
    /// continuation, closes market contacts instead of leaving them open.
    pub(super) fn close(&mut self, facts: &mut Facts, tick: u64) {
        for (_, (index, _)) in std::mem::take(&mut self.inside) {
            facts.contacts[index].left_tick.get_or_insert(tick);
        }
    }

    pub(super) fn step(
        &mut self,
        facts: &mut Facts,
        decision: &Decision<'_>,
        outcome: Outcome<'_>,
    ) {
        facts.decision_steps += 1;
        match decision.guard {
            Some(Guard::EscapePreserved) => facts.escape_preserved_steps += 1,
            Some(Guard::IngressWithheld) => facts.ingress_withheld_steps += 1,
            _ => {}
        }
        let Some(after) = outcome.status else {
            return;
        };
        let owners: Vec<Uuid> = {
            let mut owners: Vec<Uuid> = outcome.strips.iter().map(|s| s.owner_id).collect();
            owners.sort();
            owners.dedup();
            owners
        };
        // Contacts follow the geometry after this step.
        let first_step = facts.decision_steps == 1;
        for strip in outcome.strips {
            if !strip.contains(after.feet) {
                continue;
            }
            if self
                .inside
                .get(&strip.owner_id)
                .is_some_and(|(_, origin)| *origin == strip.origin)
            {
                facts.contacts[self.inside[&strip.owner_id].0].working |= strip.working;
                continue;
            }
            let before = decision
                .strips
                .iter()
                .find(|old| old.owner_id == strip.owner_id && old.origin == strip.origin);
            let arrival = match before {
                _ if first_step => Arrival::AlreadyInside,
                Some(old) if !old.contains(decision.feet) => Arrival::MovedIn,
                Some(_) => Arrival::AlreadyInside,
                None if strip.contains(decision.feet) => Arrival::PlacedOnBody,
                None => Arrival::MovedIn,
            };
            // The same owner marking a new strip under a body still on its
            // old one ends that earlier stay here.
            if let Some((index, _)) = self.inside.remove(&strip.owner_id) {
                facts.contacts[index].left_tick = Some(decision.tick);
            }
            facts.contacts.push(Contact {
                tick: decision.tick,
                owner: name(decision.names, strip.owner_id),
                working: strip.working,
                arrival,
                recognized: decision.recognized.contains(&strip.owner_id),
                airborne: decision.airborne,
                guard: decision.guard,
                moving: decision.moving,
                other_strips: owners.len().saturating_sub(1).min(u8::MAX as usize) as u8,
                left_tick: None,
            });
            self.inside
                .insert(strip.owner_id, (facts.contacts.len() - 1, strip.origin));
        }
        let left: Vec<Uuid> = self
            .inside
            .iter()
            .filter(|(owner, (_, origin))| {
                !outcome.strips.iter().any(|strip| {
                    strip.owner_id == **owner
                        && strip.origin == *origin
                        && strip.contains(after.feet)
                })
            })
            .map(|(owner, _)| *owner)
            .collect();
        for owner in left {
            let (index, _) = self.inside.remove(&owner).expect("tracked contact");
            facts.contacts[index].left_tick = Some(decision.tick);
        }

        let loss = (decision.hp + decision.armor - after.hp - after.armor).max(0);
        let shot: i32 = outcome.shots.iter().map(|(_, damage)| *damage).sum();
        for (source, damage) in &outcome.shots {
            *facts.shot_loss.entry(source.clone()).or_default() += damage;
        }
        let residual = (loss - shot).max(0);
        // A work pulse resolves against the strip current during the step:
        // before retirement or after a new work phase began.
        let mut working: Vec<&PaverStripState> = decision
            .strips
            .iter()
            .chain(outcome.strips)
            .filter(|strip| strip.working && strip.contains(after.feet))
            .collect();
        working.sort_by_key(|strip| strip.owner_id);
        working.dedup_by_key(|strip| strip.owner_id);
        if residual > 0 {
            if working.is_empty() {
                facts.unattributed_loss += residual;
            } else {
                facts.strip_loss += residual;
                let first = self.inside.get(&working[0].owner_id).map(|(i, _)| *i);
                facts.strip_hits.push(StripHit {
                    tick: decision.tick,
                    owners: working
                        .iter()
                        .map(|s| name(decision.names, s.owner_id))
                        .collect(),
                    loss: residual,
                    shot_loss: shot,
                    recognized: working
                        .iter()
                        .map(|s| decision.recognized.contains(&s.owner_id))
                        .collect(),
                    inside_since: first.map(|i| facts.contacts[i].tick),
                    arrival: first.map(|i| facts.contacts[i].arrival),
                    guard: decision.guard,
                    airborne: decision.airborne,
                    moving: decision.moving,
                    telling: decision.telling,
                    other_strips: owners.len().saturating_sub(1).min(u8::MAX as usize) as u8,
                });
            }
        }
        if after.hp <= 0 && facts.death.is_none() {
            let cause = if residual > 0 && !working.is_empty() {
                "strip".to_owned()
            } else if let Some((source, _)) = outcome.shots.last() {
                format!("shot:{source}")
            } else {
                "unattributed".to_owned()
            };
            facts.death = Some(Death {
                tick: decision.tick,
                cause,
                hp_before: decision.hp,
                armor_before: decision.armor,
                ranged_rounds: ranged_rounds(&after.loadout),
            });
        }
    }
}

#[cfg(test)]
mod tests;
