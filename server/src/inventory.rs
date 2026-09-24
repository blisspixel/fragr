//! Equipment rules independent of controller, transport and rendering.
use crate::protocol::{AmmoCount, AmmoPool, EquipmentPolicy, LoadoutState, WeaponType};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use uuid::Uuid;

mod controller;
#[cfg(test)]
mod tests;
pub use controller::{
    control_action, control_action_with_objective, control_action_with_target_filter,
};

/// Mission-entry equipment without participant identity or tick.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SavedEquipment {
    pub selected: WeaponType,
    pub weapons: Vec<WeaponType>,
    pub ammo: Vec<AmmoCount>,
    pub personal_claims: Vec<String>,
}

impl SavedEquipment {
    pub fn validate(&self) -> Result<(), &'static str> {
        crate::protocol::validate_equipment(
            self.selected,
            &self.weapons,
            &self.ammo,
            &self.personal_claims,
        )
    }
}

#[derive(Debug, Clone)]
pub struct Inventory {
    policy: EquipmentPolicy,
    owned: [bool; 5],
    ammo: [u16; 3],
    claims: BTreeSet<String>,
    revision: u64,
    dry_fire_count: u64,
    dry_latched: bool,
}

impl Inventory {
    pub(crate) fn saved_equipment(&self, selected: WeaponType) -> Option<SavedEquipment> {
        let state = self.state(Uuid::nil(), selected, 0)?;
        let saved = SavedEquipment {
            selected,
            weapons: state.weapons,
            ammo: state.ammo,
            personal_claims: state.personal_claims,
        };
        saved.validate().ok()?;
        Some(saved)
    }

    pub(crate) fn restore_saved_equipment(
        &mut self,
        saved: &SavedEquipment,
    ) -> Result<(), &'static str> {
        if self.policy != EquipmentPolicy::Discovery {
            return Err("saved equipment requires discovery policy");
        }
        saved.validate()?;
        self.owned = [false; 5];
        for weapon in &saved.weapons {
            self.owned[weapon.index()] = true;
        }
        self.ammo = [0; 3];
        for count in &saved.ammo {
            self.ammo[count.pool.index()] = count.rounds;
        }
        self.claims = saved.personal_claims.iter().cloned().collect();
        self.dry_latched = false;
        self.revision += 1;
        Ok(())
    }

    pub fn new(policy: EquipmentPolicy) -> Self {
        let mut owned = [false; 5];
        owned[WeaponType::Fists.index()] = true;
        Self {
            policy,
            owned,
            ammo: [0; 3],
            claims: BTreeSet::new(),
            revision: 0,
            dry_fire_count: 0,
            dry_latched: false,
        }
    }

    pub fn policy(&self) -> EquipmentPolicy {
        self.policy
    }
    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub(crate) fn dry_fire_count(&self) -> u64 {
        self.dry_fire_count
    }

    /// Restore durable entry equipment without rolling back observer counters
    /// or carrying a held trigger across attempts.
    pub(crate) fn restore_entry(&mut self, entry: &Self) {
        self.policy = entry.policy;
        self.owned = entry.owned;
        self.ammo = entry.ammo;
        self.claims.clone_from(&entry.claims);
        self.dry_latched = false;
        self.revision += 1;
    }

    pub fn owns(&self, weapon: WeaponType) -> bool {
        match self.policy {
            EquipmentPolicy::FullArsenal => WeaponType::ARCADE.contains(&weapon),
            EquipmentPolicy::Discovery => self.owned[weapon.index()],
        }
    }

    pub fn claimed(&self, id: &str) -> bool {
        self.claims.contains(id)
    }

    pub fn record_claim(&mut self, id: String) {
        if self.claims.insert(id) {
            self.revision += 1;
        }
    }

    /// A new selection or a death releases a latched dry trigger.
    pub fn release_trigger(&mut self) {
        self.dry_latched = false;
    }

    pub fn select(&mut self, current: WeaponType, requested: WeaponType) -> bool {
        if !self.owns(requested) {
            return false;
        }
        if current != requested {
            self.release_trigger();
        }
        true
    }

    pub fn grant_weapon(&mut self, weapon: WeaponType) -> bool {
        if self.policy == EquipmentPolicy::FullArsenal {
            return self.owns(weapon);
        }
        let Some(pool) = weapon.ammo_pool() else {
            return false;
        };
        let acquired = !self.owned[weapon.index()];
        if acquired {
            self.owned[weapon.index()] = true;
            self.revision += 1;
        }
        self.grant_ammo(pool, weapon.pickup_rounds()) > 0 || acquired
    }

    pub fn needs_ammo(&self, pool: AmmoPool) -> bool {
        self.policy == EquipmentPolicy::Discovery && self.ammo[pool.index()] < pool.capacity()
    }

    pub fn grant_ammo(&mut self, pool: AmmoPool, amount: u16) -> u16 {
        if self.policy != EquipmentPolicy::Discovery {
            return 0;
        }
        let count = &mut self.ammo[pool.index()];
        let next = count.saturating_add(amount).min(pool.capacity());
        if next == *count {
            return 0;
        }
        let gained = next - *count;
        *count = next;
        self.revision += 1;
        gained
    }

    pub fn tick(&mut self, fire_held: bool) {
        if !fire_held {
            self.dry_latched = false;
        }
    }

    /// Called only after alive/cooldown admission, before RNG or ray resolution.
    /// One shot, including one Scatter blast of several pellets, spends one unit.
    pub fn try_fire(&mut self, selected: WeaponType) -> bool {
        if !self.owns(selected) {
            return false;
        }
        if self.policy == EquipmentPolicy::FullArsenal {
            return true;
        }
        let Some(pool) = selected.ammo_pool() else {
            return true;
        };
        let count = &mut self.ammo[pool.index()];
        if *count > 0 {
            *count -= 1;
            self.revision += 1;
            self.dry_latched = false;
            return true;
        }
        if !self.dry_latched {
            self.dry_latched = true;
            self.dry_fire_count = self.dry_fire_count.saturating_add(1);
            self.revision += 1;
        }
        false
    }

    pub fn state(&self, player_id: Uuid, selected: WeaponType, tick: u64) -> Option<LoadoutState> {
        if self.policy != EquipmentPolicy::Discovery {
            return None;
        }
        Some(LoadoutState {
            player_id,
            tick,
            selected,
            weapons: WeaponType::ALL
                .into_iter()
                .filter(|&weapon| self.owns(weapon))
                .collect(),
            ammo: AmmoPool::ALL
                .into_iter()
                .map(|pool| AmmoCount {
                    pool,
                    rounds: self.ammo[pool.index()],
                })
                .collect(),
            personal_claims: self.claims.iter().cloned().collect(),
            dry_fire_count: self.dry_fire_count,
        })
    }
}
