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

/// One count per ammunition type. There are no magazines: a shot spends one
/// unit straight from the count, the way Doom does it.
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AmmoPool {
    Bullets,
    Shells,
    Cells,
}

impl AmmoPool {
    pub const ALL: [Self; 3] = [Self::Bullets, Self::Shells, Self::Cells];

    /// Doom carries 200 bullets and 50 shells. Rail cells follow Doom's rocket
    /// cap rather than its plasma cap because one cell is one 80 damage shot.
    pub const fn capacity(self) -> u16 {
        match self {
            Self::Bullets => 200,
            Self::Shells => 50,
            Self::Cells => 50,
        }
    }

    pub const fn index(self) -> usize {
        match self {
            Self::Bullets => 0,
            Self::Shells => 1,
            Self::Cells => 2,
        }
    }
}

impl WeaponType {
    pub const ALL: [Self; 5] = [
        Self::Fists,
        Self::Tack,
        Self::Flechette,
        Self::Scatter,
        Self::Rail,
    ];
    pub const ARCADE: [Self; 3] = [Self::Flechette, Self::Rail, Self::Scatter];

    pub const fn index(self) -> usize {
        match self {
            Self::Fists => 0,
            Self::Tack => 1,
            Self::Flechette => 2,
            Self::Scatter => 3,
            Self::Rail => 4,
        }
    }

    /// The count one shot spends a single unit from. Fists need nothing.
    pub const fn ammo_pool(self) -> Option<AmmoPool> {
        match self {
            Self::Fists => None,
            Self::Tack | Self::Flechette => Some(AmmoPool::Bullets),
            Self::Scatter => Some(AmmoPool::Shells),
            Self::Rail => Some(AmmoPool::Cells),
        }
    }

    /// Units a weapon pickup adds, on discovery and again when already carried.
    pub const fn pickup_rounds(self) -> u16 {
        match self {
            Self::Fists => 0,
            Self::Tack => 50,
            Self::Flechette => 60,
            Self::Scatter => 12,
            Self::Rail => 10,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct AmmoCount {
    pub pool: AmmoPool,
    pub rounds: u16,
}

/// Private authoritative equipment. Never embed it in every player's snapshot.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LoadoutState {
    pub player_id: Uuid,
    pub tick: u64,
    pub selected: WeaponType,
    /// Carried weapons, Fists always included.
    pub weapons: Vec<WeaponType>,
    /// Exactly one count per ammunition type.
    pub ammo: Vec<AmmoCount>,
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
        validate_equipment(
            self.selected,
            &self.weapons,
            &self.ammo,
            &self.personal_claims,
        )
    }

    pub fn owns(&self, weapon: WeaponType) -> bool {
        self.weapons.contains(&weapon)
    }

    pub fn ammo(&self, pool: AmmoPool) -> u16 {
        self.ammo
            .iter()
            .find(|count| count.pool == pool)
            .map_or(0, |count| count.rounds)
    }

    /// Shots the weapon can fire now. None means it needs no ammunition.
    pub fn shots(&self, weapon: WeaponType) -> Option<u16> {
        weapon.ammo_pool().map(|pool| self.ammo(pool))
    }
}

/// Shared by the wire loadout and the saved run entry, so both refuse the same shapes.
pub(crate) fn validate_equipment(
    selected: WeaponType,
    weapons: &[WeaponType],
    ammo: &[AmmoCount],
    personal_claims: &[String],
) -> Result<(), &'static str> {
    if weapons.is_empty()
        || weapons.len() > WeaponType::ALL.len()
        || ammo.len() != AmmoPool::ALL.len()
        || personal_claims.len() > 128
    {
        return Err("invalid loadout size");
    }
    let mut owned = [false; 5];
    for weapon in weapons {
        if std::mem::replace(&mut owned[weapon.index()], true) {
            return Err("invalid owned weapon");
        }
    }
    if !owned[WeaponType::Fists.index()] || !owned[selected.index()] {
        return Err("selected or fallback weapon is unowned");
    }
    let mut pools = [false; 3];
    for count in ammo {
        if std::mem::replace(&mut pools[count.pool.index()], true)
            || count.rounds > count.pool.capacity()
        {
            return Err("invalid ammunition count");
        }
    }
    let mut claims = std::collections::HashSet::new();
    if personal_claims.iter().any(|id| {
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
