//! Counters are updated at authoritative decisions, never reconstructed from snapshots.
use crate::protocol::{
    CombatCounts, MissionPhase, PlayerRecord, RecordScope, RecordStatus, WeaponType,
    RECORD_TICKS_PER_SECOND, RECORD_VERSION,
};
use crate::sim::{GameState, RoundState};
use uuid::Uuid;

#[cfg(test)]
mod tests;

#[derive(Default)]
pub(crate) struct CombatLedger {
    entered_at: u64,
    total: CombatCounts,
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
