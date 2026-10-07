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
    pub personal_claims: Vec<String>,
}

impl SavedEquipment {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.proximity_mines > crate::protocol::MINE_CARRY_CAP {
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

#[derive(Debug, Clone)]
pub struct Inventory {
    policy: EquipmentPolicy,
    /// A weapon-only mutator: this is the one weapon, with unlimited ammunition.
    only: Option<WeaponType>,
    owned: [bool; WeaponType::ALL.len()],
    ammo: [u16; 3],
    grenades: u16,
    mines: u16,
    claims: BTreeSet<String>,
    revision: u64,
    dry_fire_count: u64,
    dry_latched: bool,
    /// None keeps the single ammunition count. Some is a human magazine per gun.
    magazines: Option<[u16; WeaponType::ALL.len()]>,
    reload_weapon: Option<WeaponType>,
    reload_ready_at: Option<u64>,
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
        self.dry_latched = false;
        self.reload_weapon = None;
        self.reload_ready_at = None;
        if self.magazines.is_some() {
            let loaded = self.allocate_loaded();
            self.magazines = Some(loaded);
        }
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
            claims: BTreeSet::new(),
            revision: 0,
            dry_fire_count: 0,
            dry_latched: false,
            magazines: None,
            reload_weapon: None,
            reload_ready_at: None,
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
        self.claims.clone_from(&entry.claims);
        self.magazines = entry.magazines;
        self.reload_weapon = None;
        self.reload_ready_at = None;
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

    pub fn armed(&self) -> bool {
        self.magazines.is_some()
    }

    pub fn reloading(&self) -> bool {
        self.reload_weapon.is_some()
    }

    /// Give a human magazines. An arcade human also receives the finite spawn
    /// kit. A weapon-only mutator fills its one magazine and keeps no bag.
    /// A second call leaves the current magazines alone.
    pub fn arm_magazines(&mut self) {
        if self.magazines.is_some() {
            return;
        }
        if self.finite_arcade() {
            self.seed_arcade_spawn();
        }
        let loaded = self.allocate_loaded();
        self.magazines = Some(loaded);
        self.revision = self.revision.saturating_add(1);
    }

    /// Owned and able to fire now. An armed magazine must have a round and
    /// must not be the gun currently reloading. An unarmed arsenal keeps the
    /// single count.
    pub fn usable(&self, weapon: WeaponType) -> bool {
        if !self.owns(weapon) {
            return false;
        }
        if let Some(magazines) = self.magazines {
            if self.reload_weapon == Some(weapon) {
                return false;
            }
            return weapon
                .magazine_size()
                .is_none_or(|_| magazines[weapon.index()] > 0);
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
            if !self.owns(weapon) {
                return false;
            }
            // Unarmed pawns and a weapon-only mutator keep an open gun.
            // An armed arcade human restocks the finite bag from the weapon pad.
            if !self.finite_arcade() || self.magazines.is_none() {
                return true;
            }
            let Some(pool) = weapon.ammo_pool() else {
                return true;
            };
            return self.grant_carried(pool, weapon.pickup_rounds()) > 0;
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
        let gained = self.grant_ammo(pool, weapon.pickup_rounds()) > 0;
        if acquired {
            self.load_new_magazine(weapon);
        }
        gained || acquired
    }

    pub fn needs_ammo(&self, pool: AmmoPool) -> bool {
        self.policy == EquipmentPolicy::Discovery && self.ammo[pool.index()] < pool.capacity()
    }

    pub fn grant_ammo(&mut self, pool: AmmoPool, amount: u16) -> u16 {
        if self.policy != EquipmentPolicy::Discovery {
            return 0;
        }
        self.grant_carried(pool, amount)
    }

    fn grant_carried(&mut self, pool: AmmoPool, amount: u16) -> u16 {
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

    /// Called only after alive/cooldown admission, before RNG or ray resolution.
    /// One shot, including one Scatter blast of several pellets, spends one unit.
    /// An armed magazine spends that unit from the gun and from the carried total.
    pub fn try_fire(&mut self, selected: WeaponType) -> bool {
        if !self.owns(selected) {
            return false;
        }
        if self.magazines.is_some() {
            return self.try_fire_magazine(selected);
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
        self.note_dry_fire();
        false
    }

    pub fn request_reload(&mut self, weapon: WeaponType, tick: u64) -> bool {
        if self.magazines.is_none() || self.reload_weapon.is_some() || !self.owns(weapon) {
            return false;
        }
        let Some(size) = weapon.magazine_size() else {
            return false;
        };
        let Some(ticks) = weapon.reload_ticks() else {
            return false;
        };
        let loaded = self
            .magazines
            .map(|magazines| magazines[weapon.index()])
            .unwrap_or(0);
        if loaded >= size {
            return false;
        }
        if self.policy == EquipmentPolicy::Discovery || self.finite_arcade() {
            let Some(pool) = weapon.ammo_pool() else {
                return false;
            };
            if self.reserve(pool) == 0 {
                return false;
            }
        }
        self.reload_weapon = Some(weapon);
        self.reload_ready_at = Some(tick.saturating_add(u64::from(ticks)));
        self.revision = self.revision.saturating_add(1);
        true
    }

    pub fn cancel_reload(&mut self) {
        if self.reload_weapon.is_none() && self.reload_ready_at.is_none() {
            return;
        }
        self.reload_weapon = None;
        self.reload_ready_at = None;
        self.revision = self.revision.saturating_add(1);
    }

    pub fn finish_reload(&mut self, tick: u64) {
        let Some(ready) = self.reload_ready_at else {
            return;
        };
        if tick < ready {
            return;
        }
        let Some(weapon) = self.reload_weapon.take() else {
            self.reload_ready_at = None;
            return;
        };
        self.reload_ready_at = None;
        let Some(size) = weapon.magazine_size() else {
            self.revision = self.revision.saturating_add(1);
            return;
        };
        let loaded = self
            .magazines
            .map(|magazines| magazines[weapon.index()])
            .unwrap_or(0);
        let space = size.saturating_sub(loaded);
        let take = if self.policy == EquipmentPolicy::Discovery || self.finite_arcade() {
            weapon
                .ammo_pool()
                .map(|pool| space.min(self.reserve(pool)))
                .unwrap_or(0)
        } else {
            space
        };
        if let Some(magazines) = self.magazines.as_mut() {
            magazines[weapon.index()] = magazines[weapon.index()].saturating_add(take);
        }
        self.revision = self.revision.saturating_add(1);
    }

    /// Arcade respawn. An armed human gets the spawn kit again. A weapon-only
    /// mutator refills its one magazine and still has no bag.
    pub fn refill_if_armed(&mut self) {
        if self.magazines.is_none() || self.policy != EquipmentPolicy::FullArsenal {
            return;
        }
        self.reload_weapon = None;
        self.reload_ready_at = None;
        if self.finite_arcade() {
            self.seed_arcade_spawn();
        }
        let loaded = self.allocate_loaded();
        self.magazines = Some(loaded);
        self.revision = self.revision.saturating_add(1);
    }

    pub fn state(&self, player_id: Uuid, selected: WeaponType, tick: u64) -> Option<LoadoutState> {
        let loaded = self.magazine_counts();
        if self.policy != EquipmentPolicy::Discovery {
            if loaded.is_empty() {
                return None;
            }
            let weapons: Vec<WeaponType> = WeaponType::ALL
                .into_iter()
                .filter(|&weapon| self.owns(weapon) && weapon.magazine_size().is_some())
                .collect();
            let selected = if weapons.contains(&selected) {
                selected
            } else {
                weapons.first().copied()?
            };
            return Some(LoadoutState {
                player_id,
                tick,
                selected,
                weapons,
                ammo: AmmoPool::ALL
                    .into_iter()
                    .map(|pool| AmmoCount {
                        pool,
                        rounds: if self.finite_arcade() {
                            self.ammo[pool.index()]
                        } else {
                            0
                        },
                    })
                    .collect(),
                personal_claims: self.claims.iter().cloned().collect(),
                grenades: self.grenades,
                proximity_mines: self.mines,
                dry_fire_count: self.dry_fire_count,
                loaded,
            });
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
            dry_fire_count: self.dry_fire_count,
            loaded,
        })
    }

    fn try_fire_magazine(&mut self, selected: WeaponType) -> bool {
        if self.reload_weapon == Some(selected) {
            return false;
        }
        if selected.magazine_size().is_none() {
            return true;
        }
        let loaded = self
            .magazines
            .map(|magazines| magazines[selected.index()])
            .unwrap_or(0);
        if loaded == 0 {
            self.note_dry_fire();
            return false;
        }
        if let Some(magazines) = self.magazines.as_mut() {
            magazines[selected.index()] = magazines[selected.index()].saturating_sub(1);
        }
        if self.policy == EquipmentPolicy::Discovery || self.finite_arcade() {
            if let Some(pool) = selected.ammo_pool() {
                self.ammo[pool.index()] = self.ammo[pool.index()].saturating_sub(1);
            }
        }
        self.revision = self.revision.saturating_add(1);
        self.dry_latched = false;
        true
    }

    fn note_dry_fire(&mut self) {
        if self.dry_latched {
            return;
        }
        self.dry_latched = true;
        self.dry_fire_count = self.dry_fire_count.saturating_add(1);
        self.revision = self.revision.saturating_add(1);
    }

    fn finite_arcade(&self) -> bool {
        self.policy == EquipmentPolicy::FullArsenal && self.only.is_none()
    }

    fn seed_arcade_spawn(&mut self) {
        for pool in AmmoPool::ALL {
            self.ammo[pool.index()] = pool.arcade_spawn();
        }
    }

    fn allocate_loaded(&self) -> [u16; WeaponType::ALL.len()] {
        let mut loaded = [0; WeaponType::ALL.len()];
        if self.policy == EquipmentPolicy::FullArsenal && !self.finite_arcade() {
            for weapon in WeaponType::ALL {
                if self.owns(weapon) {
                    loaded[weapon.index()] = weapon.magazine_size().unwrap_or(0);
                }
            }
            return loaded;
        }
        let mut remaining = self.ammo;
        for weapon in WeaponType::ALL {
            if !self.owns(weapon) {
                continue;
            }
            let Some(pool) = weapon.ammo_pool() else {
                continue;
            };
            let Some(size) = weapon.magazine_size() else {
                continue;
            };
            let take = size.min(remaining[pool.index()]);
            loaded[weapon.index()] = take;
            remaining[pool.index()] -= take;
        }
        loaded
    }

    fn load_new_magazine(&mut self, weapon: WeaponType) {
        if self.magazines.is_none() {
            return;
        }
        let Some(size) = weapon.magazine_size() else {
            return;
        };
        let rounds = if self.policy == EquipmentPolicy::FullArsenal && !self.finite_arcade() {
            size
        } else {
            let Some(pool) = weapon.ammo_pool() else {
                return;
            };
            size.min(self.reserve(pool))
        };
        if let Some(magazines) = self.magazines.as_mut() {
            magazines[weapon.index()] = rounds;
        }
    }

    fn reserve(&self, pool: AmmoPool) -> u16 {
        self.ammo[pool.index()].saturating_sub(self.loaded_in_pool(pool))
    }

    fn loaded_in_pool(&self, pool: AmmoPool) -> u16 {
        let Some(magazines) = self.magazines else {
            return 0;
        };
        WeaponType::ALL
            .into_iter()
            .filter(|weapon| weapon.ammo_pool() == Some(pool) && self.owns(*weapon))
            .map(|weapon| magazines[weapon.index()])
            .fold(0u16, u16::saturating_add)
    }

    fn magazine_counts(&self) -> Vec<crate::protocol::MagazineCount> {
        let Some(magazines) = self.magazines else {
            return Vec::new();
        };
        WeaponType::ALL
            .into_iter()
            .filter(|weapon| self.owns(*weapon) && weapon.magazine_size().is_some())
            .map(|weapon| crate::protocol::MagazineCount {
                weapon,
                rounds: magazines[weapon.index()],
                ready_at: (self.reload_weapon == Some(weapon))
                    .then_some(self.reload_ready_at)
                    .flatten(),
            })
            .collect()
    }
}
