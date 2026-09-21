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

    pub fn hit(&mut self, weapon: WeaponType, hp: u64, armor: u64, killed: bool) {
        if hp + armor == 0 {
            return;
        }
        self.update(|counts| {
            let weapon = &mut counts.weapons[weapon.index()];
            weapon.damaging_attacks += 1;
            weapon.hp_damage += hp;
            weapon.armor_damage += armor;
            weapon.kills += u64::from(killed);
        });
    }

    pub fn hurt(&mut self, hp: u64, armor: u64, died: bool) {
        self.update(|counts| {
            counts.hp_lost += hp;
            counts.armor_lost += armor;
            counts.deaths += u64::from(died);
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
        if player.is_campaign_enemy() || player.is_boss {
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
            total: player.statistics.total.clone(),
            attempt: player.statistics.attempt.clone(),
        })
    }
}
