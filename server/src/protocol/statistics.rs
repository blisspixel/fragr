//! Versioned participant records. Ratios are derived from counts by presenters.
use super::{CampaignRules, CampaignRunState, MissionId, Role, WeaponType};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const RECORD_VERSION: u32 = 1;
pub const RECORD_TICKS_PER_SECOND: u32 = 20;
const MAX_EXACT_JSON_INTEGER: u64 = (1_u64 << 53) - 1;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeaponCounts {
    pub attacks: u64,
    pub damaging_attacks: u64,
    pub kills: u64,
    pub hp_damage: u64,
    pub armor_damage: u64,
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
    /// Indexed by WeaponType::index(), in WeaponType::ALL order.
    pub weapons: [WeaponCounts; 5],
}

impl CombatCounts {
    pub fn weapon(&self, weapon: WeaponType) -> &WeaponCounts {
        &self.weapons[weapon.index()]
    }

    pub fn attacks(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.attacks).sum()
    }

    pub fn kills(&self) -> u64 {
        self.weapons.iter().map(|weapon| weapon.kills).sum()
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        let mut counts = vec![
            self.alive_ticks,
            self.deaths,
            self.hp_lost,
            self.armor_lost,
            self.dry_triggers,
        ];
        for weapon in &self.weapons {
            counts.extend([
                weapon.attacks,
                weapon.damaging_attacks,
                weapon.kills,
                weapon.hp_damage,
                weapon.armor_damage,
            ]);
        }
        if counts.iter().any(|count| *count > MAX_EXACT_JSON_INTEGER) {
            return Err("record count is not an exact JSON integer");
        }
        for column in 0..5 {
            let sum: u64 = self
                .weapons
                .iter()
                .map(|weapon| {
                    [
                        weapon.attacks,
                        weapon.damaging_attacks,
                        weapon.kills,
                        weapon.hp_damage,
                        weapon.armor_damage,
                    ][column]
                })
                .sum();
            if sum > MAX_EXACT_JSON_INTEGER {
                return Err("record weapon total is not an exact JSON integer");
            }
        }
        if self.attacks() > self.alive_ticks
            || self.deaths > self.alive_ticks
            || self.dry_triggers > self.alive_ticks
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
            })
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
            && self.weapons.iter().zip(&other.weapons).all(|(a, b)| {
                a.attacks >= b.attacks
                    && a.damaging_attacks >= b.damaging_attacks
                    && a.kills >= b.kills
                    && a.hp_damage >= b.hp_damage
                    && a.armor_damage >= b.armor_damage
            })
    }
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
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
    pub total: CombatCounts,
    pub attempt: CombatCounts,
}

impl PlayerRecord {
    pub fn validate_for(
        &self,
        owner: Option<Uuid>,
        previous: Option<&Self>,
    ) -> Result<(), &'static str> {
        if self.version != RECORD_VERSION
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
                if *attempt == 0 || rules.revision != super::CAMPAIGN_RULES_REVISION {
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
            if self.session_id != old.session_id || self.player_id != old.player_id {
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
                            || self.scope != old.scope)))
            {
                return Err("record regressed or rewrote a terminal result");
            }
        }
        Ok(())
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
