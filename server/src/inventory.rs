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
    pub grenades: u16,
    pub proximity_mines: u16,
    /// Independent deliberate charges. Absent means zero in current saves;
    /// historical documents use their exact pre-remote decoder instead.
    #[serde(default, skip_serializing_if = "remote_count_empty")]
    pub remote_mines: u16,
    pub personal_claims: Vec<String>,
}

impl SavedEquipment {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.proximity_mines > crate::protocol::MINE_CARRY_CAP
            || self.remote_mines > crate::protocol::REMOTE_MINE_CARRY_CAP
        {
            return Err("invalid saved proximity mine count");
        }
        crate::protocol::validate_equipment(
            self.selected,
            &self.weapons,
            &self.ammo,
            self.grenades,
            &self.personal_claims,
        )
    }
}

fn remote_count_empty(count: &u16) -> bool {
    *count == 0
}

#[derive(Debug, Clone)]
pub struct Inventory {
    policy: EquipmentPolicy,
    /// A weapon-only mutator: this is the one weapon, with unlimited ammunition.
    only: Option<WeaponType>,
    owned: [bool; WeaponType::ALL.len()],
    ammo: [u16; 3],
    grenades: u16,
    mines: u16,
    remote_mines: u16,
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
            grenades: state.grenades,
            proximity_mines: state.proximity_mines,
            remote_mines: state.remote_mines,
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
        self.owned = [false; WeaponType::ALL.len()];
        for weapon in &saved.weapons {
            self.owned[weapon.index()] = true;
        }
        self.ammo = [0; 3];
        for count in &saved.ammo {
            self.ammo[count.pool.index()] = count.rounds;
        }
        self.claims = saved.personal_claims.iter().cloned().collect();
        self.grenades = saved.grenades;
        self.mines = saved.proximity_mines;
        self.remote_mines = saved.remote_mines;
        self.dry_latched = false;
        self.revision += 1;
        Ok(())
    }

    pub fn new(policy: EquipmentPolicy) -> Self {
        let mut owned = [false; WeaponType::ALL.len()];
        owned[WeaponType::Fists.index()] = true;
        Self {
            policy,
            only: None,
            owned,
            ammo: [0; 3],
            grenades: 0,
            mines: 0,
            remote_mines: 0,
            claims: BTreeSet::new(),
            revision: 0,
            dry_fire_count: 0,
            dry_latched: false,
        }
    }

    /// A weapon-only arsenal: one weapon, unlimited ammunition, nothing to
    /// pick up. It is an arena arsenal, so it sends no private loadout.
    pub fn restricted(weapon: WeaponType) -> Self {
        Self {
            only: Some(weapon),
            ..Self::new(EquipmentPolicy::FullArsenal)
        }
    }

    pub fn only(&self) -> Option<WeaponType> {
        self.only
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
        self.grenades = entry.grenades;
        self.mines = entry.mines;
        self.remote_mines = entry.remote_mines;
        self.claims.clone_from(&entry.claims);
        self.dry_latched = false;
        self.revision += 1;
    }

    pub fn owns(&self, weapon: WeaponType) -> bool {
        if let Some(only) = self.only {
            return weapon == only;
        }
        match self.policy {
            EquipmentPolicy::FullArsenal => WeaponType::ARCADE.contains(&weapon),
            EquipmentPolicy::Discovery => self.owned[weapon.index()],
        }
    }

    /// Owned and able to fire now: unlimited arsenals always, discovery
    /// weapons while their ammunition lasts.
    pub fn usable(&self, weapon: WeaponType) -> bool {
        if !self.owns(weapon) {
            return false;
        }
        if self.policy == EquipmentPolicy::FullArsenal {
            return true;
        }
        weapon
            .ammo_pool()
            .is_none_or(|pool| self.ammo[pool.index()] > 0)
    }

    pub fn claimed(&self, id: &str) -> bool {
        self.claims.contains(id)
    }

    /// Forget personal claims, so a carried arsenal can take a spawn pad again.
    pub fn clear_claims(&mut self) {
        if !self.claims.is_empty() {
            self.claims.clear();
            self.revision += 1;
        }
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
            // Pool-less melee is ownership alone. Fists are always carried.
            if weapon == WeaponType::Fists || self.owned[weapon.index()] {
                return false;
            }
            self.owned[weapon.index()] = true;
            self.revision += 1;
            return true;
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

    pub fn grenades(&self) -> u16 {
        self.grenades
    }

    pub fn grant_grenades(&mut self, amount: u16) -> u16 {
        if self.only.is_some() {
            return 0;
        }
        let next = self.grenades.saturating_add(amount).min(6);
        let gained = next - self.grenades;
        if gained > 0 {
            self.grenades = next;
            self.revision += 1;
        }
        gained
    }

    pub fn try_throw(&mut self) -> bool {
        if self.grenades == 0 || self.only.is_some() {
            return false;
        }
        self.grenades -= 1;
        self.revision += 1;
        true
    }

    pub fn mines(&self) -> u16 {
        self.mines
    }

    pub fn grant_mines(&mut self, amount: u16) -> u16 {
        if self.only.is_some() {
            return 0;
        }
        let next = self
            .mines
            .saturating_add(amount)
            .min(crate::protocol::MINE_CARRY_CAP);
        let gained = next - self.mines;
        if gained > 0 {
            self.mines = next;
            self.revision += 1;
        }
        gained
    }

    pub fn try_place_mine(&mut self) -> bool {
        if self.mines == 0 || self.only.is_some() {
            return false;
        }
        self.mines -= 1;
        self.revision += 1;
        true
    }

    pub fn remote_mines(&self) -> u16 {
        self.remote_mines
    }

    pub fn grant_remote_mines(&mut self, amount: u16) -> u16 {
        if self.only.is_some() {
            return 0;
        }
        let next = self
            .remote_mines
            .saturating_add(amount)
            .min(crate::protocol::REMOTE_MINE_CARRY_CAP);
        let gained = next - self.remote_mines;
        if gained > 0 {
            self.remote_mines = next;
            self.revision += 1;
        }
        gained
    }

    pub fn try_place_remote_mine(&mut self) -> bool {
        if self.remote_mines == 0 || self.only.is_some() {
            return false;
        }
        self.remote_mines -= 1;
        self.revision += 1;
        true
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
            grenades: self.grenades,
            proximity_mines: self.mines,
            remote_mines: self.remote_mines,
            dry_fire_count: self.dry_fire_count,
        })
    }
}
