use super::WeaponType;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EquipmentPolicy {
    #[default]
    FullArsenal,
    Discovery,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SupplyClaim {
    #[default]
    Contested,
    Personal,
}

pub(super) fn is_contested(claim: &SupplyClaim) -> bool {
    *claim == SupplyClaim::Contested
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AmmoPool {
    Tacks,
    Darts,
    Cores,
}

impl AmmoPool {
    pub const ALL: [Self; 3] = [Self::Tacks, Self::Darts, Self::Cores];

    pub const fn capacity(self) -> u16 {
        match self {
            Self::Tacks => 220,
            Self::Darts => 120,
            Self::Cores => 100,
        }
    }

    pub const fn index(self) -> usize {
        match self {
            Self::Tacks => 0,
            Self::Darts => 1,
            Self::Cores => 2,
        }
    }
}

impl WeaponType {
    pub const ALL: [Self; 6] = [
        Self::Fists,
        Self::Tack,
        Self::Flechette,
        Self::Scatter,
        Self::Rail,
        Self::Shiv,
    ];
    pub const ARCADE: [Self; 3] = [Self::Flechette, Self::Rail, Self::Scatter];

    pub const fn index(self) -> usize {
        match self {
            Self::Fists => 0,
            Self::Tack => 1,
            Self::Flechette => 2,
            Self::Scatter => 3,
            Self::Rail => 4,
            Self::Shiv => 5,
        }
    }

    pub const fn magazine_size(self) -> u16 {
        match self {
            Self::Fists | Self::Shiv => 0,
            Self::Tack => 12,
            Self::Flechette => 30,
            Self::Scatter => 6,
            Self::Rail => 4,
        }
    }

    pub const fn ammo_pool(self) -> Option<AmmoPool> {
        match self {
            Self::Fists | Self::Shiv => None,
            Self::Tack => Some(AmmoPool::Tacks),
            Self::Flechette | Self::Scatter => Some(AmmoPool::Darts),
            Self::Rail => Some(AmmoPool::Cores),
        }
    }

    /// Pool rounds needed to load one shot. Scatter uses four darts per shell.
    pub const fn ammo_cost(self) -> u16 {
        match self {
            Self::Fists | Self::Shiv => 0,
            Self::Scatter => 4,
            _ => 1,
        }
    }

    pub const fn reload_ticks(self) -> u64 {
        match self {
            Self::Fists | Self::Shiv => 0,
            Self::Tack => 18,
            Self::Flechette => 22,
            Self::Scatter => 26,
            Self::Rail => 28,
        }
    }

    pub const fn initial_reserve(self) -> u16 {
        let magazines = if matches!(self, Self::Rail) { 2 } else { 3 };
        self.magazine_size() * self.ammo_cost() * magazines
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct WeaponAmmo {
    pub weapon: WeaponType,
    /// None means ammunition is not applicable, never an unowned weapon.
    pub magazine: Option<u16>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct AmmoReserve {
    pub pool: AmmoPool,
    pub rounds: u16,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct ReloadState {
    pub weapon: WeaponType,
    pub complete_at: u64,
}

/// Private authoritative equipment. Never embed it in every player's snapshot.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct LoadoutState {
    pub player_id: Uuid,
    pub tick: u64,
    pub selected: WeaponType,
    pub weapons: Vec<WeaponAmmo>,
    pub reserves: Vec<AmmoReserve>,
    pub reload: Option<ReloadState>,
    pub personal_claims: Vec<String>,
    pub dry_fire_count: u64,
}

impl LoadoutState {
    pub fn validate_for(
        &self,
        player_id: Option<Uuid>,
        previous: Option<&Self>,
    ) -> Result<(), &'static str> {
        self.validate()?;
        if Some(self.player_id) != player_id {
            return Err("loadout belongs to another participant");
        }
        if previous.is_some_and(|old| old.tick > self.tick) {
            return Err("loadout tick moved backwards");
        }
        Ok(())
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        if self.weapons.is_empty()
            || self.weapons.len() > WeaponType::ALL.len()
            || self.reserves.len() != AmmoPool::ALL.len()
            || self.personal_claims.len() > 128
        {
            return Err("invalid loadout size");
        }
        let mut weapons = [false; WeaponType::ALL.len()];
        for held in &self.weapons {
            if std::mem::replace(&mut weapons[held.weapon.index()], true)
                || match held.magazine {
                    None => held.weapon.ammo_pool().is_some(),
                    Some(rounds) => {
                        held.weapon.ammo_pool().is_none() || rounds > held.weapon.magazine_size()
                    }
                }
            {
                return Err("invalid owned weapon or magazine");
            }
        }
        if !weapons[WeaponType::Fists.index()] || !weapons[self.selected.index()] {
            return Err("selected or fallback weapon is unowned");
        }
        let mut pools = [false; 3];
        for reserve in &self.reserves {
            if std::mem::replace(&mut pools[reserve.pool.index()], true)
                || reserve.rounds > reserve.pool.capacity()
            {
                return Err("invalid ammunition reserve");
            }
        }
        if self.reload.as_ref().is_some_and(|reload| {
            reload.weapon != self.selected
                || reload.weapon.ammo_pool().is_none()
                || reload.complete_at <= self.tick
                || reload.complete_at - self.tick > reload.weapon.reload_ticks()
                || self.weapon(reload.weapon).and_then(|held| held.magazine)
                    == Some(reload.weapon.magazine_size())
                || reload
                    .weapon
                    .ammo_pool()
                    .is_some_and(|pool| self.reserve(pool) < reload.weapon.ammo_cost())
        }) {
            return Err("invalid reload state");
        }
        let mut claims = std::collections::HashSet::new();
        if self.personal_claims.iter().any(|id| {
            id.is_empty()
                || id.len() > 64
                || !id
                    .bytes()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
                || !claims.insert(id)
        }) {
            return Err("invalid personal supply claims");
        }
        Ok(())
    }

    pub fn weapon(&self, weapon: WeaponType) -> Option<&WeaponAmmo> {
        self.weapons.iter().find(|held| held.weapon == weapon)
    }

    pub fn reserve(&self, pool: AmmoPool) -> u16 {
        self.reserves
            .iter()
            .find(|reserve| reserve.pool == pool)
            .map_or(0, |reserve| reserve.rounds)
    }
}
