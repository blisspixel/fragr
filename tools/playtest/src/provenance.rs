//! Bounded, accepted identity and same-snapshot kill evidence. Historical
//! name-keyed transient caches are deliberately not promoted into this owner.
use fragr_server::protocol::{Snapshot, WeaponType};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use uuid::Uuid;

const LIMIT: usize = 512;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(super) struct Provenance {
    #[serde(default)]
    names: BTreeMap<String, Option<Uuid>>,
    #[serde(default)]
    exhausted: bool,
    #[serde(default)]
    pub kills: BTreeMap<Uuid, Option<KillEvidence>>,
    #[serde(default)]
    engagements: BTreeMap<Uuid, u64>,
    #[serde(default)]
    timing_uncertain: bool,
    #[serde(default)]
    geometry_map: Option<u32>,
    #[serde(default)]
    positions: BTreeMap<Uuid, PositionReceipt>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PositionReceipt {
    last: (f32, f32),
    spawn: (f32, f32),
    off_field: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(super) struct KillEvidence {
    pub killer: Uuid,
    pub weapon: Option<WeaponType>,
    pub explosion: bool,
    pub distance: Option<f64>,
}

impl KillEvidence {
    pub fn label(&self) -> String {
        self.weapon
            .map(|weapon| weapon.name().to_owned())
            .unwrap_or_else(|| {
                if self.explosion {
                    "Explosion"
                } else {
                    "Unknown"
                }
                .to_owned()
            })
    }
}

impl Provenance {
    pub fn begin_snapshot(&mut self) {
        self.kills.clear();
    }

    pub fn observe_positions(&mut self, snapshot: &Snapshot) {
        if self.geometry_map != Some(snapshot.map_id) {
            self.positions.clear();
            self.geometry_map = Some(snapshot.map_id);
        }
        let present: std::collections::BTreeSet<_> =
            snapshot.players.iter().map(|player| player.id).collect();
        for (id, receipt) in &mut self.positions {
            if !present.contains(id) {
                receipt.off_field = true;
            }
        }
        for player in &snapshot.players {
            if !player.x.is_finite() || !player.z.is_finite() {
                self.positions.remove(&player.id);
                continue;
            }
            let position = (player.x, player.z);
            if let Some(receipt) = self.positions.get_mut(&player.id) {
                if receipt.off_field {
                    receipt.spawn = position;
                    let near = snapshot
                        .players
                        .iter()
                        .filter(|o| o.id != player.id && o.hp > 0)
                        .map(|o| ((o.x - player.x).hypot(o.z - player.z), o.x, o.z))
                        .fold((f32::MAX, 0.0, 0.0), |a, b| if b.0 < a.0 { b } else { a });
                    tracing::info!(x = player.x, z = player.z, near = near.0, nx = near.1, nz = near.2, "DIAG spawn");
                }
                receipt.last = position;
                receipt.off_field = false;
            } else if self.positions.len() < LIMIT {
                self.positions.insert(
                    player.id,
                    PositionReceipt {
                        last: position,
                        spawn: position,
                        off_field: false,
                    },
                );
            }
        }
    }

    pub fn position(&self, id: Option<Uuid>) -> Option<(f32, f32)> {
        self.positions.get(&id?).map(|receipt| receipt.last)
    }

    pub fn spawn(&self, id: Option<Uuid>) -> Option<(f32, f32)> {
        self.positions.get(&id?).map(|receipt| receipt.spawn)
    }

    pub fn observe(&mut self, id: Uuid, name: &str) {
        if name.chars().count() > 64 || name.is_empty() {
            self.exhausted = true;
            return;
        }
        if let Some(known) = self.names.get_mut(name) {
            if *known != Some(id) {
                *known = None;
            }
        } else if self.names.len() < LIMIT {
            self.names.insert(name.to_owned(), Some(id));
        } else {
            self.exhausted = true;
        }
    }

    pub fn unique(&self, name: &str) -> Option<Uuid> {
        (!self.exhausted)
            .then(|| self.names.get(name).copied().flatten())
            .flatten()
    }

    pub fn resolve(&self, supplied: Option<Uuid>, name: &str) -> Option<Uuid> {
        supplied.or_else(|| self.unique(name))
    }

    pub fn remember(&mut self, victim: Uuid, evidence: KillEvidence) {
        if let Some(existing) = self.kills.get_mut(&victim) {
            if existing.as_ref() != Some(&evidence) {
                *existing = None;
            }
        } else if self.kills.len() < LIMIT {
            self.kills.insert(victim, Some(evidence));
        }
    }

    pub fn take(&mut self, killer: Option<Uuid>, victim: Option<Uuid>) -> Option<KillEvidence> {
        let evidence = self.kills.remove(&victim?).flatten()?;
        evidence.filter_killer(killer)
    }

    pub fn hit(&mut self, victim: Uuid, tick: u64) {
        if self.timing_uncertain {
            return;
        }
        if self.engagements.len() < LIMIT || self.engagements.contains_key(&victim) {
            self.engagements.entry(victim).or_insert(tick);
        } else {
            // Once history is lost, later hits cannot safely become starts.
            // Keep this uncertainty for the rest of this observation.
            self.timing_uncertain = true;
            self.engagements.clear();
        }
    }

    pub fn finish_engagement(&mut self, victim: Option<Uuid>) -> Option<u64> {
        if self.timing_uncertain {
            return None;
        }
        self.engagements.remove(&victim?)
    }

    pub fn respawn(&mut self, name: &str) {
        if let Some(id) = self.unique(name) {
            self.engagements.remove(&id);
        } else {
            // Respawn has no ID. Omit optional samples rather than borrowing
            // a same-named participant's old engagement.
            self.engagements.clear();
            self.timing_uncertain = true;
        }
    }
}

impl KillEvidence {
    fn filter_killer(self, killer: Option<Uuid>) -> Option<Self> {
        (killer == Some(self.killer)).then_some(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lost_timing_history_never_restarts_at_a_later_hit() {
        let mut full = Provenance::default();
        for index in 0..LIMIT {
            full.hit(Uuid::from_u128(index as u128), 1);
        }
        let dropped = Uuid::from_u128(999);
        full.hit(dropped, 2);
        full.finish_engagement(Some(Uuid::from_u128(0)));
        full.hit(dropped, 30);
        assert_eq!(full.finish_engagement(Some(dropped)), None);

        let mut ambiguous = Provenance::default();
        let survivor = Uuid::from_u128(1);
        ambiguous.hit(survivor, 1);
        ambiguous.observe(Uuid::from_u128(2), "Same");
        ambiguous.observe(Uuid::from_u128(3), "Same");
        ambiguous.respawn("Same");
        ambiguous.hit(survivor, 30);
        assert_eq!(ambiguous.finish_engagement(Some(survivor)), None);
        let mut restored: Provenance =
            serde_json::from_str(&serde_json::to_string(&ambiguous).unwrap()).unwrap();
        restored.hit(survivor, 50);
        assert_eq!(restored.finish_engagement(Some(survivor)), None);
    }

    #[test]
    fn ambiguity_survives_omission_and_capacity_exhaustion_fails_closed() {
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        let mut provenance = Provenance::default();
        provenance.observe(a, "Same");
        provenance.observe(b, "Same");
        provenance.observe(a, "Same");
        assert_eq!(provenance.unique("Same"), None);
        for index in 0..LIMIT + 1 {
            provenance.observe(
                Uuid::from_u128(index as u128 + 10),
                &format!("Name {index}"),
            );
        }
        assert_eq!(provenance.names.len(), LIMIT);
        assert_eq!(provenance.unique("Name 0"), None);
        assert_eq!(provenance.resolve(Some(a), "Name 0"), Some(a));
    }

    #[test]
    fn contradictory_evidence_is_not_selected_by_insertion_order() {
        let owner = Uuid::from_u128(1);
        let target = Uuid::from_u128(2);
        let evidence = KillEvidence {
            killer: owner,
            weapon: Some(WeaponType::Rail),
            explosion: false,
            distance: None,
        };
        let mut provenance = Provenance::default();
        provenance.remember(target, evidence.clone());
        provenance.remember(
            target,
            KillEvidence {
                weapon: Some(WeaponType::Rocket),
                ..evidence
            },
        );
        assert!(provenance.take(Some(owner), Some(target)).is_none());
        assert!(provenance.kills.is_empty());
    }

    #[test]
    fn new_trusted_cache_round_trips_and_expires_at_the_next_snapshot() {
        let owner = Uuid::from_u128(1);
        let target = Uuid::from_u128(2);
        let mut provenance = Provenance::default();
        provenance.remember(
            target,
            KillEvidence {
                killer: owner,
                weapon: Some(WeaponType::Rocket),
                explosion: false,
                distance: None,
            },
        );
        let mut restored: Provenance =
            serde_json::from_str(&serde_json::to_string(&provenance).unwrap()).unwrap();
        assert_eq!(
            restored.take(Some(owner), Some(target)).unwrap().label(),
            "Rocket"
        );
        provenance.begin_snapshot();
        assert!(provenance.take(Some(owner), Some(target)).is_none());
    }
}
