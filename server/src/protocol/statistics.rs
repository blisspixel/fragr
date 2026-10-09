//! Versioned participant records. Ratios are derived from counts by presenters.
use super::{CampaignRules, CampaignRunState, MissionId, Role, WeaponType};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const RECORD_VERSION: u32 = 3;
pub const EIGHT_COLUMN_RECORD_VERSION: u32 = 2;
pub const LEGACY_RECORD_VERSION: u32 = 1;
mod record_wire;
pub const RECORD_TICKS_PER_SECOND: u32 = 20;
const MAX_EXACT_JSON_INTEGER: u64 = (1_u64 << 53) - 1;

/// One accepted shot, and what that shot did.
///
/// `attacks` counts the shot. `connects` counts a shot whose pellets found a
/// body, including a shield or a teammate that lost nothing. `heads` counts a
/// connect with at least one pellet in the head band. That is geometry: a
/// shielded head still counts, and a fist has no band test. `damaging_attacks`
/// counts a shot that removed HP or armor. One shot is one of each, however
/// many bodies the pellets struck.
///
/// `connects` and `heads` are omitted while zero. A column that dealt damage
/// and omits both predates this count. A presenter must not read that omission
/// as a measured zero.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeaponCounts {
    pub attacks: u64,
    pub damaging_attacks: u64,
    pub kills: u64,
    pub hp_damage: u64,
    pub armor_damage: u64,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub connects: u64,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub heads: u64,
}

/// `scale * numerator / denominator`, rounded half away from zero.
/// A zero denominator is no observation, not a zero rate.
///
/// The product is formed in 128 bits. A legal count times the scale can exceed
/// 2^64 while the rounded quotient still fits in 64 bits; that quotient is the
/// rate. A quotient that does not fit is no rate.
///
/// The published percent is this value at `scale` 1000, shown with one decimal
/// (`500` is 50.0%). Damage per shot and kills per death use `scale` 10
/// (`250` is 25.0). The arithmetic stays on integers. A floating percent is
/// not a second copy of the count.
pub fn ratio_scaled(numerator: u64, denominator: u64, scale: u64) -> Option<u64> {
    if denominator == 0 || scale == 0 {
        return None;
    }
    let product = u128::from(numerator) * u128::from(scale);
    let den = u128::from(denominator);
    let quotient = product / den;
    let remainder = product % den;
    // `remainder * 2 >= denominator` without overflowing when the denominator is huge.
    let round_up = remainder >= den - remainder;
    let rounded = if round_up {
        quotient.checked_add(1)?
    } else {
        quotient
    };
    u64::try_from(rounded).ok()
}

/// Tenths of `count` per minute. Records tick at 20 Hz, so a minute is 1200
/// ticks and one decimal is scale `12000` (`600` is 60.0). Zero ticks is no rate.
pub fn per_minute_tenths(count: u64, alive_ticks: u64) -> Option<u64> {
    ratio_scaled(count, alive_ticks, 1_200 * 10)
}

/// Wilson score interval at z = 1.96, in thousandths of the unit, rounded half
/// away from zero. This is the interval, not the rate. Zero trials, or more
/// hits than trials, is no interval.
///
/// `1.96` is the conventional two-decimal form of the two-sided 95% normal
/// quantile. Every count this record accepts fits in the f64 mantissa, so the
/// casts of hits and trials are exact. The products inside the formula are not.
pub fn wilson_thousandths(hits: u64, trials: u64) -> Option<(u64, u64)> {
    if trials == 0 || hits > trials {
        return None;
    }
    let z = 1.96_f64;
    let n = trials as f64;
    let p = hits as f64 / n;
    let z2 = z * z;
    let denom = 1.0 + z2 / n;
    let centre = p + z2 / (2.0 * n);
    let margin = z * ((p * (1.0 - p) / n) + (z2 / (4.0 * n * n))).sqrt();
    let low = ((centre - margin) / denom).clamp(0.0, 1.0);
    let high = ((centre + margin) / denom).clamp(0.0, 1.0);
    Some((unit_thousandths(low), unit_thousandths(high)))
}

fn unit_thousandths(unit: f64) -> u64 {
    if unit <= 0.0 {
        return 0;
    }
    if unit >= 1.0 {
        return 1000;
    }
    let scaled = unit * 1000.0;
    let base = scaled.floor();
    let fraction = scaled - base;
    let rounded = if fraction * 2.0 >= 1.0 {
        base + 1.0
    } else {
        base
    };
    rounded.clamp(0.0, 1000.0) as u64
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CombatCounts {
    /// Ticks alive and admitted to an active simulation frame, including death's frame.
    pub alive_ticks: u64,
    pub deaths: u64,
    pub hp_lost: u64,
    pub armor_lost: u64,
    pub dry_triggers: u64,
    /// Distinct authored secrets found. Omitted while zero, so arena records
    /// and records from before secrets keep their exact shape.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub secrets: u64,
    /// Indexed by WeaponType::index(), in WeaponType::ALL order.
    #[serde(with = "weapon_counts")]
    pub weapons: [WeaponCounts; WeaponType::ALL.len()],
    /// Counted explosives have their own column; gun indices stay stable.
    #[serde(default, skip_serializing_if = "empty_grenades")]
    pub grenades: WeaponCounts,
    /// Placed proximity mines have their own column beside the grenades.
    #[serde(default, skip_serializing_if = "empty_grenades")]
    pub mines: WeaponCounts,
    /// Deliberately triggered charges are distinct from body-trip mines.
    #[serde(default, skip_serializing_if = "empty_grenades")]
    pub remote_mines: WeaponCounts,
}

fn empty_grenades(counts: &WeaponCounts) -> bool {
    *counts == WeaponCounts::default()
}

fn is_zero(value: &u64) -> bool {
    *value == 0
}

/// Five original slots, then the Shiv's sixth and the Sniper's seventh only once
/// they have been used, so retained history keeps its shape and no index ever
/// changes meaning.
mod weapon_counts {
    use super::{WeaponCounts, WeaponType};
    use serde::de::{Error, IgnoredAny, SeqAccess, Visitor};
    use serde::Serialize;

    const LEGACY: usize = 5;
    const SLOTS: usize = WeaponType::ALL.len();

    pub fn serialize<S: serde::Serializer>(
        counts: &[WeaponCounts; SLOTS],
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        if counts[WeaponType::Repeater.index()] != WeaponCounts::default()
            || counts[WeaponType::Arc.index()] != WeaponCounts::default()
        {
            return Err(serde::ser::Error::custom(
                "new weapon counters require a versioned participant record",
            ));
        }
        // The shortest prefix that still holds every non-zero column.
        let used = counts
            .iter()
            .rposition(|c| *c != WeaponCounts::default())
            .map_or(LEGACY, |last| (last + 1).max(LEGACY));
        counts[..used].serialize(serializer)
    }

    pub fn deserialize<'de, D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> Result<[WeaponCounts; SLOTS], D::Error> {
        struct Counts;
        impl<'de> Visitor<'de> for Counts {
            type Value = [WeaponCounts; SLOTS];
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("five, six or seven weapon counters")
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut counts = [WeaponCounts::default(); SLOTS];
                // Standalone retained counts keep their original unversioned
                // seven-column ceiling. Record revision 2 uses record_wire.
                for (index, count) in counts.iter_mut().take(7).enumerate() {
                    match seq.next_element()? {
                        Some(value) => *count = value,
                        None if index >= LEGACY => return Ok(counts),
                        None => return Err(A::Error::invalid_length(index, &self)),
                    }
                }
                if seq.next_element::<IgnoredAny>()?.is_some() {
                    return Err(A::Error::invalid_length(8, &self));
                }
                Ok(counts)
            }
        }
        deserializer.deserialize_seq(Counts)
    }
}

impl CombatCounts {
    pub fn weapon(&self, weapon: WeaponType) -> &WeaponCounts {
        &self.weapons[weapon.index()]
    }

    pub fn attacks(&self) -> u64 {
        self.weapons
            .iter()
            .map(|weapon| weapon.attacks)
            .sum::<u64>()
            + self.grenades.attacks
            + self.mines.attacks
            + self.remote_mines.attacks
    }

    /// Gun and fist shots. Grenades and mines stay off this denominator.
    pub fn shot_attacks(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.attacks).sum()
    }

    pub fn connects(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.connects).sum()
    }

    pub fn heads(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.heads).sum()
    }

    /// HP and armor actually removed, guns and explosives, overkill excluded.
    pub fn damage_dealt(&self) -> u64 {
        let column = |counts: &WeaponCounts| counts.hp_damage.saturating_add(counts.armor_damage);
        self.weapons
            .iter()
            .map(column)
            .fold(0_u64, u64::saturating_add)
            .saturating_add(column(&self.grenades))
            .saturating_add(column(&self.mines))
    }

    pub fn kills(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.kills).sum::<u64>()
            + self.grenades.kills
            + self.mines.kills
            + self.remote_mines.kills
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        let mut counts = vec![
            self.alive_ticks,
            self.deaths,
            self.hp_lost,
            self.armor_lost,
            self.dry_triggers,
            self.secrets,
        ];
        for weapon in self
            .weapons
            .iter()
            .chain([&self.grenades, &self.mines, &self.remote_mines])
        {
            counts.extend(weapon_fields(weapon));
        }
        if counts.iter().any(|count| *count > MAX_EXACT_JSON_INTEGER) {
            return Err("record count is not an exact JSON integer");
        }
        for column in 0..7 {
            let sum: u64 = self
                .weapons
                .iter()
                .chain([&self.grenades, &self.mines, &self.remote_mines])
                .map(|weapon| weapon_fields(weapon)[column])
                .sum();
            if sum > MAX_EXACT_JSON_INTEGER {
                return Err("record weapon total is not an exact JSON integer");
            }
        }
        if self.attacks() > self.alive_ticks
            || self.deaths > self.alive_ticks
            || self.dry_triggers > self.alive_ticks
            || self.secrets > self.alive_ticks
        {
            return Err("record contains more actions than active frames");
        }
        // One scatter blast can kill every fighter its pellets reach, so its
        // kills are bounded by pellets rather than by damaging attacks.
        if self
            .weapons
            .iter()
            .zip(super::WeaponType::ALL)
            .any(|(counts, weapon)| {
                counts.kills
                    > counts
                        .damaging_attacks
                        .saturating_mul(weapon.pellets() as u64)
                    || counts.damaging_attacks > counts.attacks
                    || !geometry_holds(counts, weapon != super::WeaponType::Fists)
            })
            || !explosive_holds(&self.grenades)
            || !explosive_holds(&self.mines)
            || !explosive_holds(&self.remote_mines)
        {
            return Err("inconsistent attack counts");
        }
        Ok(())
    }

    pub fn contains(&self, other: &Self) -> bool {
        self.alive_ticks >= other.alive_ticks
            && self.deaths >= other.deaths
            && self.hp_lost >= other.hp_lost
            && self.armor_lost >= other.armor_lost
            && self.dry_triggers >= other.dry_triggers
            && self.secrets >= other.secrets
            && counts_cover(&self.grenades, &other.grenades)
            && counts_cover(&self.mines, &other.mines)
            && counts_cover(&self.remote_mines, &other.remote_mines)
            && self
                .weapons
                .iter()
                .zip(&other.weapons)
                .all(|(outer, inner)| counts_cover(outer, inner))
    }
}

fn weapon_fields(weapon: &WeaponCounts) -> [u64; 7] {
    [
        weapon.attacks,
        weapon.damaging_attacks,
        weapon.kills,
        weapon.hp_damage,
        weapon.armor_damage,
        weapon.connects,
        weapon.heads,
    ]
}

fn counts_cover(outer: &WeaponCounts, inner: &WeaponCounts) -> bool {
    outer.attacks >= inner.attacks
        && outer.damaging_attacks >= inner.damaging_attacks
        && outer.kills >= inner.kills
        && outer.hp_damage >= inner.hp_damage
        && outer.armor_damage >= inner.armor_damage
        && outer.connects >= inner.connects
        && outer.heads >= inner.heads
}

/// Heads are a subset of connects, and connects are a subset of shots.
/// Damage implies a connect only once the column records connects. An older
/// column that dealt damage and omitted the key stays valid.
/// A fist has no head-band test, so a fist head is not a count we made.
fn geometry_holds(counts: &WeaponCounts, band: bool) -> bool {
    if counts.heads > counts.connects || counts.connects > counts.attacks {
        return false;
    }
    if !band && counts.heads > 0 {
        return false;
    }
    if (counts.connects > 0 || counts.heads > 0) && counts.damaging_attacks > counts.connects {
        return false;
    }
    true
}

fn explosive_holds(counts: &WeaponCounts) -> bool {
    counts.damaging_attacks <= counts.attacks
        && counts.kills <= counts.damaging_attacks.saturating_mul(256)
        && counts.connects == 0
        && counts.heads == 0
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum RecordScope {
    Arena {
        round: u32,
    },
    Mission {
        mission: MissionId,
        attempt: u32,
        rules: CampaignRules,
        run: Option<CampaignRunState>,
    },
    Practice {
        round: u32,
    },
}

impl RecordScope {
    pub fn attempt(&self) -> u32 {
        match self {
            Self::Mission { attempt, .. } => *attempt,
            _ => 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordStatus {
    Active,
    Continue,
    Complete,
    Failed,
    Abandoned,
}

impl RecordStatus {
    pub fn terminal(self) -> bool {
        matches!(self, Self::Complete | Self::Failed | Self::Abandoned)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(try_from = "record_wire::Wire")]
pub struct PlayerRecord {
    pub version: u32,
    pub session_id: Uuid,
    pub player_id: Uuid,
    /// Session-local round, stable throughout all mission attempts.
    pub round: u32,
    pub tick: u64,
    pub entered_at: u64,
    pub round_started_at: u64,
    pub ticks_per_second: u32,
    pub map_id: u32,
    pub map_name: String,
    pub role: Role,
    pub scope: RecordScope,
    pub status: RecordStatus,
    /// Successful mission attempt: readiness to authoritative departure.
    /// Absent on historical records and every noncompleted mission/arena.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "mission_elapsed"
    )]
    pub mission_elapsed_ticks: Option<u64>,
    pub total: CombatCounts,
    pub attempt: CombatCounts,
}

fn mission_elapsed<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<u64>, D::Error> {
    // Missing historical fields use Default; a present null is not a duration.
    u64::deserialize(deserializer).map(Some)
}

impl PlayerRecord {
    pub fn validate_for(
        &self,
        owner: Option<Uuid>,
        previous: Option<&Self>,
    ) -> Result<(), &'static str> {
        if !matches!(
            self.version,
            LEGACY_RECORD_VERSION | EIGHT_COLUMN_RECORD_VERSION | RECORD_VERSION
        ) || (self.version < RECORD_VERSION
            && (self.total.weapon(WeaponType::Arc) != &WeaponCounts::default()
                || self.attempt.weapon(WeaponType::Arc) != &WeaponCounts::default()))
            || (self.version == LEGACY_RECORD_VERSION
                && (self.total.weapon(WeaponType::Repeater) != &WeaponCounts::default()
                    || self.attempt.weapon(WeaponType::Repeater) != &WeaponCounts::default()))
            || self.ticks_per_second != RECORD_TICKS_PER_SECOND
            || owner != Some(self.player_id)
            || self.role == Role::Spectator
            || self.round == 0
            || self.tick > MAX_EXACT_JSON_INTEGER
            || self.entered_at > self.tick
            || self.round_started_at > self.entered_at
            || self.map_id == 0
            || self.map_name.is_empty()
            || self.map_name.chars().count() > 128
        {
            return Err("invalid participant record identity or version");
        }
        self.total.validate()?;
        self.attempt.validate()?;
        if self.mission_elapsed_ticks.is_some_and(|elapsed| {
            self.status != RecordStatus::Complete
                || !matches!(self.scope, RecordScope::Mission { .. })
                || elapsed > self.tick - self.round_started_at
        }) {
            return Err("invalid mission completion elapsed time");
        }
        if self.total.alive_ticks > self.tick - self.entered_at {
            return Err("record active time exceeds participation window");
        }
        if !self.total.contains(&self.attempt) {
            return Err("attempt exceeds total effort");
        }
        match &self.scope {
            RecordScope::Arena { round } | RecordScope::Practice { round }
                if *round != self.round || self.attempt != self.total =>
            {
                return Err("inconsistent round record");
            }
            RecordScope::Mission {
                attempt,
                rules,
                run,
                ..
            } => {
                if *attempt == 0 || !(1..=super::CAMPAIGN_RULES_REVISION).contains(&rules.revision)
                {
                    return Err("unsupported mission record");
                }
                if let Some(run) = run {
                    run.validate_attempt(*attempt)?;
                    if self.status != run.status.into() {
                        return Err("inconsistent solo record");
                    }
                }
            }
            _ => {}
        }
        if let Some(old) = previous {
            if self.session_id != old.session_id
                || self.player_id != old.player_id
                || self.version != old.version
            {
                return Err("record identity changed within a connection");
            }
            if self.tick < old.tick || self.round < old.round {
                return Err("record moved backwards");
            }
            if self.round == old.round
                && (self.map_id != old.map_id
                    || self.entered_at != old.entered_at
                    || self.round_started_at != old.round_started_at
                    || self.map_name != old.map_name
                    || self.role != old.role
                    || !self.scope.follows(&old.scope)
                    || !self.total.contains(&old.total)
                    || self.scope.attempt() < old.scope.attempt()
                    || (self.scope.attempt() == old.scope.attempt()
                        && !self.attempt.contains(&old.attempt))
                    || (old.status.terminal()
                        && (self.status != old.status
                            || self.total != old.total
                            || self.attempt != old.attempt
                            || self.mission_elapsed_ticks != old.mission_elapsed_ticks
                            || self.scope != old.scope)))
            {
                return Err("record regressed or rewrote a terminal result");
            }
        }
        Ok(())
    }

    /// Select an exact historical shape only when no unsupported facts exist.
    pub fn record_for_version(&self, version: u32) -> Result<Self, &'static str> {
        if !matches!(
            version,
            LEGACY_RECORD_VERSION | EIGHT_COLUMN_RECORD_VERSION | RECORD_VERSION
        ) {
            return Err("unsupported participant record version");
        }
        if version < RECORD_VERSION
            && (self.total.weapon(WeaponType::Arc) != &WeaponCounts::default()
                || self.attempt.weapon(WeaponType::Arc) != &WeaponCounts::default())
        {
            return Err("Arc counts cannot be delivered to an older reader");
        }
        if version == LEGACY_RECORD_VERSION {
            if self.total.remote_mines != WeaponCounts::default()
                || self.attempt.remote_mines != WeaponCounts::default()
            {
                return Err("Remote Mine counts cannot be delivered to a historical reader");
            }
            if self.total.weapon(WeaponType::Repeater) != &WeaponCounts::default()
                || self.attempt.weapon(WeaponType::Repeater) != &WeaponCounts::default()
            {
                return Err("Repeater counts cannot be delivered to a historical reader");
            }
        }
        let mut record = self.clone();
        record.version = version;
        Ok(record)
    }

    pub fn legacy_record(&self) -> Result<Self, &'static str> {
        self.record_for_version(LEGACY_RECORD_VERSION)
    }
}

impl Serialize for PlayerRecord {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let record = self
            .record_for_version(self.version)
            .map_err(serde::ser::Error::custom)?;
        record_wire::Wire::from(record).serialize(serializer)
    }
}

impl RecordScope {
    fn follows(&self, old: &Self) -> bool {
        match (self, old) {
            (Self::Arena { round: a }, Self::Arena { round: b })
            | (Self::Practice { round: a }, Self::Practice { round: b }) => a == b,
            (
                Self::Mission {
                    mission,
                    rules,
                    run,
                    ..
                },
                Self::Mission {
                    mission: old_mission,
                    rules: old_rules,
                    run: old_run,
                    ..
                },
            ) => {
                mission == old_mission
                    && rules == old_rules
                    && match (run, old_run) {
                        (None, None) => true,
                        (Some(run), Some(old)) => {
                            run.id == old.id && run.continues <= old.continues
                        }
                        _ => false,
                    }
            }
            _ => false,
        }
    }
}

impl From<super::CampaignRunStatus> for RecordStatus {
    fn from(status: super::CampaignRunStatus) -> Self {
        match status {
            super::CampaignRunStatus::Playing => Self::Active,
            super::CampaignRunStatus::Continue => Self::Continue,
            super::CampaignRunStatus::Complete => Self::Complete,
            super::CampaignRunStatus::Failed => Self::Failed,
            super::CampaignRunStatus::Abandoned => Self::Abandoned,
        }
    }
}
