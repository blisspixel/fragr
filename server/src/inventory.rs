//! Equipment rules independent of controller, transport and rendering.
use crate::protocol::{
    AmmoPool, AmmoReserve, EquipmentPolicy, LoadoutState, ReloadState, WeaponAmmo, WeaponType,
};
use std::collections::BTreeSet;
use uuid::Uuid;

mod controller;
#[cfg(test)]
mod tests;
pub use controller::control_action;

#[derive(Debug, Clone)]
pub struct Inventory {
    policy: EquipmentPolicy,
    magazines: [Option<u16>; 5],
    reserves: [u16; 3],
    reload: Option<ReloadState>,
    claims: BTreeSet<String>,
    revision: u64,
    dry_fire_count: u64,
    dry_latched: bool,
}

impl Inventory {
    pub fn new(policy: EquipmentPolicy) -> Self {
        Self {
            policy,
            magazines: [None; 5],
            reserves: [0; 3],
            reload: None,
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

    pub fn owns(&self, weapon: WeaponType) -> bool {
        match self.policy {
            EquipmentPolicy::FullArsenal => WeaponType::ARCADE.contains(&weapon),
            EquipmentPolicy::Discovery => {
                weapon == WeaponType::Fists || self.magazines[weapon.index()].is_some()
            }
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

    pub fn cancel_reload(&mut self) {
        if self.reload.take().is_some() {
            self.revision += 1;
        }
        self.dry_latched = false;
    }

    pub fn select(&mut self, current: WeaponType, requested: WeaponType) -> bool {
        if !self.owns(requested) {
            return false;
        }
        if current != requested {
            self.cancel_reload();
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
        let acquired = self.magazines[weapon.index()].is_none();
        if acquired {
            self.magazines[weapon.index()] = Some(weapon.magazine_size());
            self.revision += 1;
        }
        self.grant_ammo(pool, weapon.initial_reserve()) > 0 || acquired
    }

    pub fn needs_ammo(&self, pool: AmmoPool) -> bool {
        self.policy == EquipmentPolicy::Discovery && self.reserves[pool.index()] < pool.capacity()
    }

    pub fn grant_ammo(&mut self, pool: AmmoPool, amount: u16) -> u16 {
        if self.policy != EquipmentPolicy::Discovery {
            return 0;
        }
        let reserve = &mut self.reserves[pool.index()];
        let next = reserve.saturating_add(amount).min(pool.capacity());
        if next == *reserve {
            return 0;
        }
        let gained = next - *reserve;
        *reserve = next;
        self.revision += 1;
        gained
    }

    pub fn begin_reload(&mut self, selected: WeaponType, tick: u64) -> bool {
        if self.policy != EquipmentPolicy::Discovery || self.reload.is_some() {
            return false;
        }
        let Some(pool) = selected.ammo_pool() else {
            return false;
        };
        let Some(rounds) = self.magazines[selected.index()] else {
            return false;
        };
        if rounds == selected.magazine_size() || self.reserves[pool.index()] < selected.ammo_cost()
        {
            return false;
        }
        self.reload = Some(ReloadState {
            weapon: selected,
            complete_at: tick.saturating_add(selected.reload_ticks()),
        });
        self.revision += 1;
        self.dry_latched = false;
        true
    }

    pub fn tick(&mut self, tick: u64, fire_held: bool) {
        if !fire_held {
            self.dry_latched = false;
        }
        if !self
            .reload
            .as_ref()
            .is_some_and(|reload| reload.complete_at <= tick)
        {
            return;
        }
        if let Some(reload) = self.reload.take() {
            let weapon = reload.weapon;
            if let (Some(pool), Some(rounds)) =
                (weapon.ammo_pool(), self.magazines[weapon.index()].as_mut())
            {
                let reserve = &mut self.reserves[pool.index()];
                let loaded = (weapon.magazine_size() - *rounds).min(*reserve / weapon.ammo_cost());
                *rounds += loaded;
                *reserve -= loaded * weapon.ammo_cost();
            }
            self.revision += 1;
        }
    }

    /// Called only after alive/cooldown admission, before RNG or ray resolution.
    pub fn try_fire(&mut self, selected: WeaponType) -> bool {
        if !self.owns(selected) || self.reload.is_some() {
            return false;
        }
        if self.policy == EquipmentPolicy::FullArsenal || selected == WeaponType::Fists {
            return true;
        }
        if let Some(rounds) = self.magazines[selected.index()]
            .as_mut()
            .filter(|rounds| **rounds > 0)
        {
            *rounds -= 1;
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
                .map(|weapon| WeaponAmmo {
                    weapon,
                    magazine: self.magazines[weapon.index()],
                })
                .collect(),
            reserves: AmmoPool::ALL
                .into_iter()
                .map(|pool| AmmoReserve {
                    pool,
                    rounds: self.reserves[pool.index()],
                })
                .collect(),
            reload: self.reload.clone(),
            personal_claims: self.claims.iter().cloned().collect(),
            dry_fire_count: self.dry_fire_count,
        })
    }
}
