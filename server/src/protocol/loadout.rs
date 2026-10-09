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

/// One count per ammunition type. That count is everything carried, including
/// rounds sitting in a human's magazines. A shot still spends one unit.
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AmmoPool {
    Bullets,
    Shells,
    Cells,
    Rockets,
}

impl AmmoPool {
    pub const ALL: [Self; 4] = [Self::Bullets, Self::Shells, Self::Cells, Self::Rockets];

    /// Doom carries 200 bullets and 50 shells. One cell is one 80 damage rail
    /// shot; the cap of 100 (raised from 50 on 2026-09-25) lets a Railgun
    /// player bank ten pickups without the count reading like a plasma pool.
    pub const fn capacity(self) -> u16 {
        match self {
            Self::Bullets => 200,
            Self::Shells => 50,
            Self::Cells => 100,
            Self::Rockets => 20,
        }
    }

    /// Spawn kit for an armed arcade human, including the loaded magazine.
    /// Bullets 80 is one Flechette magazine plus 60. Shells 24 is one Scatter
    /// tube plus 18. Cells 16 is one Rail magazine plus 12. Death restores
    /// this kit. A weapon pad adds `pickup_rounds` on top, up to `capacity`.
    pub const fn arcade_spawn(self) -> u16 {
        match self {
            Self::Bullets => 80,
            Self::Shells => 24,
            Self::Cells => 16,
            Self::Rockets => 0,
        }
    }

    pub const fn index(self) -> usize {
        match self {
            Self::Bullets => 0,
            Self::Shells => 1,
            Self::Cells => 2,
            Self::Rockets => 3,
        }
    }
}

impl WeaponType {
    /// Wire and record order. Later guns are appended so earlier record slots
    /// keep their meaning.
    pub const ALL: [Self; 10] = [
        Self::Fists,
        Self::Tack,
        Self::Flechette,
        Self::Scatter,
        Self::Rail,
        Self::Shiv,
        Self::Sniper,
        Self::Repeater,
        Self::Arc,
        Self::Rocket,
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
            Self::Sniper => 6,
            Self::Repeater => 7,
            Self::Arc => 8,
            Self::Rocket => 9,
        }
    }

    /// The count one shot spends a single unit from. Melee needs nothing.
    pub const fn ammo_pool(self) -> Option<AmmoPool> {
        match self {
            Self::Fists | Self::Shiv => None,
            Self::Tack | Self::Flechette | Self::Repeater => Some(AmmoPool::Bullets),
            Self::Scatter => Some(AmmoPool::Shells),
            Self::Rail | Self::Sniper | Self::Arc => Some(AmmoPool::Cells),
            Self::Rocket => Some(AmmoPool::Rockets),
        }
    }

    /// Rounds a human magazine holds. Melee has none. Absent on an unarmed pawn.
    pub const fn magazine_size(self) -> Option<u16> {
        match self {
            Self::Fists | Self::Shiv => None,
            Self::Tack => Some(12),
            Self::Flechette => Some(20),
            Self::Repeater => Some(30),
            Self::Scatter => Some(6),
            Self::Rail => Some(4),
            Self::Sniper => Some(5),
            Self::Arc => Some(12),
            Self::Rocket => Some(1),
        }
    }

    /// Ticks to fill one magazine at 20 Hz. One press fills the whole tube.
    pub const fn reload_ticks(self) -> Option<u32> {
        match self {
            Self::Fists | Self::Shiv => None,
            Self::Tack => Some(16),
            Self::Flechette | Self::Repeater | Self::Arc => Some(22),
            Self::Scatter => Some(14),
            Self::Rail | Self::Sniper => Some(28),
            Self::Rocket => Some(16),
        }
    }

    /// Units a weapon pickup adds, on discovery and again when already carried.
    pub const fn pickup_rounds(self) -> u16 {
        match self {
            Self::Fists | Self::Shiv => 0,
            Self::Tack => 50,
            Self::Flechette => 60,
            Self::Scatter => 12,
            Self::Rail => 10,
            // Eight slow shots: the rack teaches the verb without banking a
            // second Railgun pool.
            Self::Sniper => 8,
            Self::Repeater => 60,
            Self::Arc => 40,
            Self::Rocket => 4,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct AmmoCount {
    pub pool: AmmoPool,
    pub rounds: u16,
}

/// Rounds in one human magazine. Omitted from the loadout entirely when the
/// pawn has no magazines, so an older reader never has to understand it.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct MagazineCount {
    pub weapon: WeaponType,
    pub rounds: u16,
    /// Tick the current reload of this gun finishes. Absent while it is not
    /// reloading.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ready_at: Option<u64>,
}

/// Private authoritative equipment. Never embed it in every player's snapshot.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LoadoutState {
    pub player_id: Uuid,
    pub tick: u64,
    pub selected: WeaponType,
    /// Carried weapons. Discovery always includes Fists. An arcade human
    /// magazine loadout lists only the guns that have magazines.
    pub weapons: Vec<WeaponType>,
    /// Exactly one count per ammunition type. The count is the total carried,
    /// including rounds in `loaded`. An armed arcade human sends the finite
    /// spawn kit. A weapon-only mutator still sends zeros: that one gun has
    /// no bag to run out of.
    pub ammo: Vec<AmmoCount>,
    pub grenades: u16,
    /// Carried proximity mines. Omitted while zero so earlier readers keep
    /// every mission without them.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub proximity_mines: u16,
    /// Deliberate charges, independent of grenades and proximity mines.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub remote_mines: u16,
    pub personal_claims: Vec<String>,
    pub dry_fire_count: u64,
    /// Per-gun magazines for an armed human. Empty and omitted otherwise.
    /// The retired loadout keys `reserves` and `reload` stay refused.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub loaded: Vec<MagazineCount>,
}

fn is_zero(count: &u16) -> bool {
    *count == 0
}

/// Proximity mines carried at once, independent of the six grenades.
pub const MINE_CARRY_CAP: u16 = 4;

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
        if self.proximity_mines > MINE_CARRY_CAP || self.remote_mines > super::REMOTE_MINE_CARRY_CAP
        {
            return Err("invalid proximity mine count");
        }
        if self.arcade_magazines() {
            self.validate_arcade_magazines()?;
        } else {
            validate_equipment(
                self.selected,
                &self.weapons,
                &self.ammo,
                self.grenades,
                &self.personal_claims,
            )?;
            self.validate_loaded_against_pools()?;
        }
        Ok(())
    }

    fn arcade_magazines(&self) -> bool {
        !self.loaded.is_empty() && !self.weapons.contains(&WeaponType::Fists)
    }

    fn validate_arcade_magazines(&self) -> Result<(), &'static str> {
        if self.grenades > 6
            || self.weapons.is_empty()
            || self.weapons.len() > WeaponType::ALL.len()
            || self.ammo.len() != AmmoPool::ALL.len()
            || self.personal_claims.len() > 128
        {
            return Err("invalid loadout size");
        }
        let mut owned = [false; WeaponType::ALL.len()];
        for weapon in &self.weapons {
            if weapon.magazine_size().is_none()
                || std::mem::replace(&mut owned[weapon.index()], true)
            {
                return Err("invalid owned weapon");
            }
        }
        if !owned[self.selected.index()] {
            return Err("selected or fallback weapon is unowned");
        }
        let mut seen = [false; AmmoPool::ALL.len()];
        let mut amounts = [0u16; AmmoPool::ALL.len()];
        for count in &self.ammo {
            if std::mem::replace(&mut seen[count.pool.index()], true)
                || count.rounds > count.pool.capacity()
            {
                return Err("invalid ammunition count");
            }
            amounts[count.pool.index()] = count.rounds;
        }
        if seen.iter().any(|present| !present) {
            return Err("invalid ammunition count");
        }
        validate_claims(&self.personal_claims)?;
        self.validate_loaded_entries(true)?;
        // All zeros is a weapon-only magazine: the gun refills without a bag.
        // A finite bag has to hold every round sitting in its magazines.
        if amounts.iter().any(|rounds| *rounds != 0) {
            let mut used = [0u16; AmmoPool::ALL.len()];
            for magazine in &self.loaded {
                let Some(pool) = magazine.weapon.ammo_pool() else {
                    return Err("invalid magazine");
                };
                used[pool.index()] = used[pool.index()].saturating_add(magazine.rounds);
            }
            if used
                .iter()
                .zip(amounts)
                .any(|(loaded, carried)| *loaded > carried)
            {
                return Err("invalid magazine");
            }
        }
        Ok(())
    }

    fn validate_loaded_against_pools(&self) -> Result<(), &'static str> {
        if self.loaded.is_empty() {
            return Ok(());
        }
        self.validate_loaded_entries(false)?;
        let mut used = [0u16; AmmoPool::ALL.len()];
        for magazine in &self.loaded {
            let Some(pool) = magazine.weapon.ammo_pool() else {
                return Err("invalid magazine");
            };
            used[pool.index()] = used[pool.index()].saturating_add(magazine.rounds);
        }
        for count in &self.ammo {
            if used[count.pool.index()] > count.rounds {
                return Err("invalid magazine");
            }
        }
        Ok(())
    }

    fn validate_loaded_entries(&self, exact: bool) -> Result<(), &'static str> {
        let mut seen = [false; WeaponType::ALL.len()];
        let mut reloading = false;
        for magazine in &self.loaded {
            let Some(size) = magazine.weapon.magazine_size() else {
                return Err("invalid magazine");
            };
            if magazine.rounds > size
                || !self.weapons.contains(&magazine.weapon)
                || std::mem::replace(&mut seen[magazine.weapon.index()], true)
            {
                return Err("invalid magazine");
            }
            if magazine.ready_at.is_some() {
                if reloading {
                    return Err("invalid magazine");
                }
                reloading = true;
            }
        }
        if exact && self.weapons.iter().any(|weapon| !seen[weapon.index()]) {
            return Err("invalid magazine");
        }
        Ok(())
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

    /// Shots the weapon can fire now. A magazine, when this loadout has one,
    /// replaces the pool. None means the weapon needs no ammunition.
    pub fn shots(&self, weapon: WeaponType) -> Option<u16> {
        if let Some(magazine) = self
            .loaded
            .iter()
            .find(|magazine| magazine.weapon == weapon)
        {
            return Some(magazine.rounds);
        }
        weapon.ammo_pool().map(|pool| self.ammo(pool))
    }
}

/// Shared by the wire loadout and the saved run entry, so both refuse the same shapes.
pub(crate) fn validate_equipment(
    selected: WeaponType,
    weapons: &[WeaponType],
    ammo: &[AmmoCount],
    grenades: u16,
    personal_claims: &[String],
) -> Result<(), &'static str> {
    if grenades > 6
        || weapons.is_empty()
        || weapons.len() > WeaponType::ALL.len()
        || ammo.len() != AmmoPool::ALL.len()
        || personal_claims.len() > 128
    {
        return Err("invalid loadout size");
    }
    let mut owned = [false; WeaponType::ALL.len()];
    for weapon in weapons {
        if std::mem::replace(&mut owned[weapon.index()], true) {
            return Err("invalid owned weapon");
        }
    }
    if !owned[WeaponType::Fists.index()] || !owned[selected.index()] {
        return Err("selected or fallback weapon is unowned");
    }
    let mut pools = [false; AmmoPool::ALL.len()];
    for count in ammo {
        if std::mem::replace(&mut pools[count.pool.index()], true)
            || count.rounds > count.pool.capacity()
        {
            return Err("invalid ammunition count");
        }
    }
    validate_claims(personal_claims)
}

fn validate_claims(personal_claims: &[String]) -> Result<(), &'static str> {
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
