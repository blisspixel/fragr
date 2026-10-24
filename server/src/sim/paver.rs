//! Paver work pulses. The encounter controller owns the strip, its timing and
//! its interruption; this resolves actual damage on bodies standing inside.
use super::{GameState, PLAYER_FLOOR_Y};
use crate::encounters::enemy::paver::WORK_DAMAGE;
use crate::protocol::WeaponType;

impl GameState {
    pub(super) fn tick_paver_strips(&mut self) {
        for (owner, strip) in self.encounters.paver_pulses(self.tick) {
            let Some(attacker) = self.players.iter().position(|p| p.id == owner && p.hp > 0) else {
                continue;
            };
            let victims: Vec<usize> = (0..self.players.len())
                .filter(|&index| {
                    let body = &self.players[index];
                    index != attacker
                        && body.hp > 0
                        && body.respawn_timer.is_none()
                        && !body.detached
                        && !body.is_campaign_companion()
                        && crate::mission::actor_active(
                            self.mission.as_ref(),
                            body.id,
                            body.campaign,
                        )
                        && strip.contains([body.x, body.y - PLAYER_FLOOR_Y, body.z])
                        && self.damage_lands(attacker, index)
                })
                .collect();
            for victim in victims {
                let participant = self.players[victim].is_participant();
                let (hp, armor, _) = self.resolve_fighter_hit_for(
                    attacker,
                    victim,
                    WORK_DAMAGE,
                    None,
                    false,
                    Some(WeaponType::Fists),
                );
                if participant && hp + armor > 0 {
                    self.paver_strip_hits = self.paver_strip_hits.saturating_add(1);
                }
            }
        }
    }
}
