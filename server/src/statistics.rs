//! Counters are updated at authoritative decisions, never reconstructed from snapshots.
use crate::protocol::{
    CombatCounts, MissionPhase, PlayerRecord, RecordScope, RecordStatus, WeaponType,
    RECORD_TICKS_PER_SECOND, RECORD_VERSION,
};
use crate::sim::{GameState, RoundState};
use uuid::Uuid;

mod head_to_head;
pub(crate) use head_to_head::HeadToHead;

#[cfg(test)]
mod tests;

/// A checkpoint keeps every counter column as it stands. The public record
/// shape (`CombatCounts`) withholds newer weapon columns from unversioned
/// readers; a checkpoint is read only by the build that wrote it, so it keeps
/// them all.
mod saved_counts {
    use crate::protocol::{CombatCounts, WeaponCounts, WeaponType};
    use serde::{Deserialize, Serialize};

    #[derive(Serialize, Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Saved {
        alive_ticks: u64,
        deaths: u64,
        hp_lost: u64,
        armor_lost: u64,
        dry_triggers: u64,
        secrets: u64,
        weapons: Vec<WeaponCounts>,
        grenades: WeaponCounts,
        mines: WeaponCounts,
        remote_mines: WeaponCounts,
    }

    pub fn serialize<S: serde::Serializer>(
        counts: &CombatCounts,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        Saved {
            alive_ticks: counts.alive_ticks,
            deaths: counts.deaths,
            hp_lost: counts.hp_lost,
            armor_lost: counts.armor_lost,
            dry_triggers: counts.dry_triggers,
            secrets: counts.secrets,
            weapons: counts.weapons.to_vec(),
            grenades: counts.grenades,
            mines: counts.mines,
            remote_mines: counts.remote_mines,
        }
        .serialize(serializer)
    }

    pub fn deserialize<'de, D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> Result<CombatCounts, D::Error> {
        let saved = Saved::deserialize(deserializer)?;
        let weapons: [WeaponCounts; WeaponType::ALL.len()] = saved
            .weapons
            .try_into()
            .map_err(|_| serde::de::Error::custom("one counter column per weapon"))?;
        Ok(CombatCounts {
            alive_ticks: saved.alive_ticks,
            deaths: saved.deaths,
            hp_lost: saved.hp_lost,
            armor_lost: saved.armor_lost,
            dry_triggers: saved.dry_triggers,
            secrets: saved.secrets,
            weapons,
            grenades: saved.grenades,
            mines: saved.mines,
            remote_mines: saved.remote_mines,
        })
    }
}

#[derive(Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct CombatLedger {
    entered_at: u64,
    #[serde(with = "saved_counts")]
    total: CombatCounts,
    #[serde(with = "saved_counts")]
    attempt: CombatCounts,
    /// Secret ids found this round and this attempt. A continue restores the
    /// secret's pickup, and finding it again is not a second secret.
    secrets_total: std::collections::BTreeSet<String>,
    secrets_attempt: std::collections::BTreeSet<String>,
}

impl CombatLedger {
    pub fn begin(&mut self, tick: u64) {
        *self = Self {
            entered_at: tick,
            ..Default::default()
        };
    }
    fn update(&mut self, mut f: impl FnMut(&mut CombatCounts)) {
        f(&mut self.total);
        f(&mut self.attempt);
    }

    pub fn reset_attempt(&mut self) {
        self.attempt = CombatCounts::default();
        self.secrets_attempt.clear();
    }

    /// A checkpoint retry resumes the attempt's counts where the checkpoint
    /// left them; the run totals keep everything, the failed stretch included.
    pub fn restore_attempt(&mut self, saved: &Self) {
        self.attempt = saved.attempt.clone();
        self.secrets_attempt.clone_from(&saved.secrets_attempt);
    }

    pub fn secret(&mut self, id: &str) {
        if self.secrets_total.insert(id.to_string()) {
            self.total.secrets += 1;
        }
        if self.secrets_attempt.insert(id.to_string()) {
            self.attempt.secrets += 1;
        }
    }

    pub fn alive_tick(&mut self) {
        self.update(|counts| counts.alive_ticks += 1);
    }

    pub fn dry_trigger(&mut self) {
        self.update(|counts| counts.dry_triggers += 1);
    }

    pub fn attack(&mut self, weapon: WeaponType) {
        self.update(|counts| counts.weapons[weapon.index()].attacks += 1);
    }

    /// Attacks with one weapon since the ledger began.
    pub fn attacks_with(&self, weapon: WeaponType) -> u64 {
        self.total.weapon(weapon).attacks
    }

    /// One call per attack, summed over every fighter its pellets struck.
    ///
    /// `connect` is a body found, including a shield or a teammate that lost
    /// nothing. `head` is a pellet in the head band on that body. Damage is a
    /// separate fact: a connect with no HP or armor removed is still a connect,
    /// and a head still counts when the shield held. A damaging hit is a
    /// connect even if the caller forgot the flag. A head implies a connect.
    pub fn hit(
        &mut self,
        weapon: WeaponType,
        hp: u64,
        armor: u64,
        kills: u64,
        connect: bool,
        head: bool,
    ) {
        let connected = connect || head || hp + armor > 0;
        self.update(|counts| {
            let weapon = &mut counts.weapons[weapon.index()];
            if connected {
                weapon.connects += 1;
            }
            if head {
                weapon.heads += 1;
            }
            if hp + armor == 0 {
                return;
            }
            weapon.damaging_attacks += 1;
            weapon.hp_damage += hp;
            weapon.armor_damage += armor;
            weapon.kills += kills;
        });
    }

    /// Deaths, gun shots, connects, head-band connects, and HP plus armor dealt.
    pub(crate) fn board(&self) -> (u64, u64, u64, u64, u64) {
        (
            self.total.deaths,
            self.total.shot_attacks(),
            self.total.connects(),
            self.total.heads(),
            self.total.damage_dealt(),
        )
    }

    pub fn hurt(&mut self, hp: u64, armor: u64, died: bool) {
        self.update(|counts| {
            counts.hp_lost += hp;
            counts.armor_lost += armor;
            counts.deaths += u64::from(died);
        });
    }

    pub fn grenade_attack(&mut self) {
        self.update(|counts| counts.grenades.attacks += 1);
    }

    pub fn grenade_hit(&mut self, hp: u64, armor: u64, kills: u64) {
        if hp + armor == 0 {
            return;
        }
        self.update(|counts| {
            counts.grenades.damaging_attacks += 1;
            counts.grenades.hp_damage += hp;
            counts.grenades.armor_damage += armor;
            counts.grenades.kills += kills;
        });
    }

    pub fn mine_attack(&mut self) {
        self.update(|counts| counts.mines.attacks += 1);
    }

    pub fn mine_hit(&mut self, hp: u64, armor: u64, kills: u64) {
        if hp + armor == 0 {
            return;
        }
        self.update(|counts| {
            counts.mines.damaging_attacks += 1;
            counts.mines.hp_damage += hp;
            counts.mines.armor_damage += armor;
            counts.mines.kills += kills;
        });
    }

    pub fn remote_mine_attack(&mut self) {
        self.update(|counts| counts.remote_mines.attacks += 1);
    }

    pub fn remote_mine_hit(&mut self, hp: u64, armor: u64, kills: u64) {
        if hp + armor == 0 {
            return;
        }
        self.update(|counts| {
            counts.remote_mines.damaging_attacks += 1;
            counts.remote_mines.hp_damage += hp;
            counts.remote_mines.armor_damage += armor;
            counts.remote_mines.kills += kills;
        });
    }
}

impl GameState {
    /// Private participant facts; spectators and authored enemies have no profile record.
    pub fn player_record(&self, id: Uuid) -> Option<PlayerRecord> {
        if self.round_number == 0 {
            return None;
        }
        let player = self.players.iter().find(|player| player.id == id)?;
        if !player.is_participant() {
            return None;
        }
        // The epilogue is a walk, not a result: no service record, no tally.
        if self.map.campaign_mission_id() == Some(crate::protocol::MissionId::StillHere) {
            return None;
        }
        if self.mission.is_none()
            && self.round_state == RoundState::Ended
            && player.statistics.total.alive_ticks == 0
        {
            return None;
        }
        let mut status = if self.round_state == RoundState::Ended {
            RecordStatus::Complete
        } else {
            RecordStatus::Active
        };
        let scope = if let Some(mission) = self.mission_state() {
            status = mission.run.map_or_else(
                || {
                    if mission.phase == MissionPhase::Departed {
                        RecordStatus::Complete
                    } else {
                        RecordStatus::Active
                    }
                },
                |run| run.status.into(),
            );
            RecordScope::Mission {
                mission: mission.id,
                attempt: mission.attempt,
                rules: mission.rules,
                run: mission.run,
            }
        } else if self.solo_broadcast.enabled
            || matches!(self.map, crate::maps::RuntimeMap::Authored(_))
        {
            if self.solo_broadcast.phase == crate::sim::EpisodePhase::Failed {
                status = RecordStatus::Failed;
            }
            RecordScope::Practice {
                round: self.round_number,
            }
        } else {
            RecordScope::Arena {
                round: self.round_number,
            }
        };
        Some(PlayerRecord {
            version: RECORD_VERSION,
            session_id: self.statistics_session,
            player_id: id,
            round: self.round_number,
            tick: self.tick,
            entered_at: player.statistics.entered_at,
            round_started_at: self.statistics_round_started,
            ticks_per_second: RECORD_TICKS_PER_SECOND,
            map_id: self.map.id(),
            map_name: self.map.name().to_string(),
            role: player.role,
            scope,
            status,
            mission_elapsed_ticks: self.mission_elapsed_ticks(),
            total: player.statistics.total.clone(),
            attempt: player.statistics.attempt.clone(),
        })
    }
}
