//! Latch in a fight. Latch carries a Tack with a real twelve-round magazine,
//! fires at active threats on a steady cadence, and covers the participant
//! when they reload: faster fire at whoever has a gun raised at them. Out of
//! a shot, Latch takes a covering position beside the participant with a line
//! on the threat and out of the participant's line of fire, and steps out of
//! the participant's path in corridors and doorways.
use super::*;
use crate::combat::{aim_at, aim_point_for, line_of_sight, Ray};
use crate::protocol::{Action, AmmoPool, CompanionPhase, LookAt, WeaponType};
use crate::sim::{BotIntent, Player};

mod formation;
#[cfg(test)]
mod tests;
const SUPPORT_RANGE: f32 = 16.0;
const PARTY_RANGE: f32 = 16.0;
/// Latch's Tack magazine and reload, the same as anyone's.
const MAGAZINE: u8 = match WeaponType::Tack.magazine_size() {
    Some(rounds) => rounds as u8,
    None => 12,
};
const RELOAD_TICKS: u64 = match WeaponType::Tack.reload_ticks() {
    Some(ticks) => ticks as u64,
    None => 16,
};
/// Ticks between covering shots while the participant reloads: just over the
/// Tack's own cycle, so it reads as a deliberate string of shots.
const COVER_CADENCE: u64 = 6;

/// Latch fights beside the participant, not instead of them: while the
/// participant holds fire, Latch keeps a measured pace.
const WAITING_CADENCE: u64 = 44;
/// A participant who fired this recently is in the fight.
const ENGAGED_TICKS: u64 = 60;

/// Ticks between support shots while the participant fights. Latch helps
/// more on Assisted and leaves more of the fight to the participant on
/// Severe.
fn support_cadence(difficulty: crate::protocol::CampaignDifficulty) -> u64 {
    match difficulty {
        crate::protocol::CampaignDifficulty::Assisted => 12,
        crate::protocol::CampaignDifficulty::Standard => 16,
        crate::protocol::CampaignDifficulty::Severe => 22,
    }
}

/// Latch's own weapon state for one attempt.
#[derive(Debug, Default)]
pub(in crate::mission) struct Support {
    /// Rounds fired from the current magazine.
    spent: u8,
    /// A reload in progress finishes on this tick.
    reload_until: Option<u64>,
    last_shot: Option<u64>,
    /// The participant's latest shot Latch saw.
    leader_fired: Option<u64>,
    /// Shots this attempt, and how many of them covered a reload.
    pub(in crate::mission) shots: u32,
    pub(in crate::mission) covering_shots: u32,
}

impl Support {
    #[cfg(test)]
    pub(in crate::mission) fn rounds(&self) -> u8 {
        MAGAZINE - self.spent
    }

    #[cfg(test)]
    pub(in crate::mission) fn reloading(&self) -> bool {
        self.reload_until.is_some()
    }

    /// Forget the last shot, as if the cadence had already passed.
    #[cfg(test)]
    pub(in crate::mission) fn rest(&mut self) {
        self.last_shot = None;
    }

    /// Fire the magazine dry without starting its reload.
    #[cfg(test)]
    pub(in crate::mission) fn empty(&mut self) {
        self.spent = MAGAZINE;
    }

    /// Finish a reload that is due. Returns true when one just finished.
    fn settle(&mut self, tick: u64) -> bool {
        if self.reload_until.is_some_and(|until| tick >= until) {
            self.reload_until = None;
            self.spent = 0;
            return true;
        }
        false
    }

    fn ready(&self, tick: u64, cadence: u64) -> bool {
        self.reload_until.is_none()
            && self.spent < MAGAZINE
            && self
                .last_shot
                .is_none_or(|last| tick.saturating_sub(last) >= cadence)
    }

    fn reload(&mut self, tick: u64) {
        if self.reload_until.is_none() && self.spent > 0 {
            self.reload_until = Some(tick.saturating_add(RELOAD_TICKS));
        }
    }
}

fn distance(a: [f32; 3], b: [f32; 3]) -> f32 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

/// Match the finite hitscan body test before committing a support shot.
fn clear_support_ray(
    state: &GameState,
    companion: Uuid,
    origin: [f32; 3],
    target: &Player,
    civilians: &[crate::movement::contact::ContactBody],
    tableau: &[crate::movement::Solid],
) -> bool {
    let target_feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
    let centre = aim_point_for(target_feet, target.campaign, target.ducking);
    let Some((yaw, pitch)) = aim_at(origin, centre) else {
        return false;
    };
    let ray = Ray::dispersed(origin, yaw, pitch, 0.0, [0.0, 0.0]);
    let Some(hostile) =
        ray.actor_stance(target_feet, target.campaign, target.ducking, SUPPORT_RANGE)
    else {
        return false;
    };
    !state.players.iter().any(|participant| {
        participant.id != companion
            && participant.id != target.id
            && state.contact_eligible(participant)
            && ray
                .actor_stance(
                    [participant.x, participant.y - PLAYER_FLOOR_Y, participant.z],
                    participant.campaign,
                    participant.ducking,
                    hostile.distance,
                )
                .is_some_and(|hit| hit.distance < hostile.distance)
    }) && !tableau.iter().any(|body| {
        ray.solid(body, hostile.distance)
            .is_some_and(|hit| hit.distance < hostile.distance)
    }) && !civilians.iter().any(|body| {
        ray.fighter_with_height(
            [body.from.x, body.from.y, body.from.z],
            body.radius,
            body.height,
            hostile.distance,
        )
        .is_some_and(|hit| hit.distance < hostile.distance)
    })
}

impl GameState {
    /// Enemies Latch may engage: awake, in reach of the party, and not part
    /// of a lesson the participant has to meet alone.
    fn companion_may_engage(&self, run: &MissionRun, enemy: &Player, leader: [f32; 3]) -> bool {
        enemy.hp > 0
            && enemy.respawn_timer.is_none()
            && enemy.campaign.is_some_and(CampaignActor::is_enemy)
            && !(run.m04.as_ref().is_some_and(|progress| progress.index <= 1)
                && crate::combat::is_notary(enemy.campaign))
            && !run.initial_map.m06_objectives().is_some_and(|prepared| {
                [prepared.encounters[1], prepared.encounters[3]]
                    .iter()
                    .any(|index| self.encounters.enemy_in_group(enemy.id, *index))
            })
            && !run.initial_map.m07_objectives().is_some_and(|prepared| {
                self.encounters
                    .enemy_in_group(enemy.id, prepared.lesson_encounter)
            })
            && self.encounters.is_active_enemy(enemy.id)
            && distance(leader, [enemy.x, enemy.y - PLAYER_FLOOR_Y, enemy.z]) <= PARTY_RANGE
    }

    pub(crate) fn m02_companion_intent(&mut self) -> Option<(Uuid, BotIntent)> {
        let run = self.mission.as_ref()?;
        if run.m02.is_none()
            && run.m03.is_none()
            && run.m04.is_none()
            && run.m06.is_none()
            && run.m07.is_none()
        {
            return None;
        }
        if run.phase != MissionPhase::InProgress || self.campaign_run_frozen() {
            return None;
        }
        let companion = self.players.iter().find(|p| p.is_campaign_companion())?;
        let CampaignActor::Companion { phase, .. } = companion.campaign? else {
            return None;
        };
        if phase == CompanionPhase::Releasing {
            return None;
        }
        let id = companion.id;
        let tick = self.tick;
        let reloaded = self
            .mission
            .as_mut()
            .is_some_and(|run| run.companion.settle(tick));
        if reloaded {
            // Latch's own scavenged rounds, never the participant's supply.
            if let Some(body) = self.players.iter_mut().find(|p| p.id == id) {
                body.inventory
                    .grant_ammo(AmmoPool::Bullets, u16::from(MAGAZINE));
            }
        }
        let run = self.mission.as_ref()?;
        let companion = self.players.iter().find(|p| p.id == id)?;
        let feet = [companion.x, companion.y - PLAYER_FLOOR_Y, companion.z];
        let leader = self
            .players
            .iter()
            .filter(|p| {
                p.campaign == Some(CampaignActor::Participant {})
                    && p.hp > 0
                    && p.respawn_timer.is_none()
                    && run.ready.contains(&p.id)
            })
            .min_by(|a, b| {
                let da = distance(feet, [a.x, a.y - PLAYER_FLOOR_Y, a.z]);
                let db = distance(feet, [b.x, b.y - PLAYER_FLOOR_Y, b.z]);
                da.total_cmp(&db)
            });
        let leader_feet = leader.map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z]);
        let leader_id = leader.map(|p| p.id);
        let covering = leader.is_some_and(|p| p.inventory.reloading());
        let together = leader_feet.is_some_and(|p| distance(feet, p) <= PARTY_RANGE);
        let leader_fired = if leader.is_some_and(|p| p.just_fired) {
            Some(tick)
        } else {
            run.companion.leader_fired
        };
        let engaged = leader_fired.is_some_and(|fired| tick.saturating_sub(fired) <= ENGAGED_TICKS);
        let cadence = if covering {
            COVER_CADENCE
        } else if engaged {
            support_cadence(run.rules.difficulty)
        } else {
            WAITING_CADENCE
        };
        let can_fire = together && run.companion.ready(tick, cadence);
        let mut civilians = Vec::new();
        self.append_civilian_contacts(&mut civilians);
        let mut tableau = Vec::new();
        self.append_m02_tableau_shots(&mut civilians, &mut tableau);
        let eye = [feet[0], feet[1] + crate::movement::EYE_HEIGHT, feet[2]];
        let engageable: Vec<&Player> = leader_feet
            .map(|leader| {
                self.players
                    .iter()
                    .filter(|p| self.companion_may_engage(run, p, leader))
                    .collect()
            })
            .unwrap_or_default();
        // A raised gun at the participant comes first, then whoever is
        // nearest the participant while they reload, then the nearest to
        // Latch.
        let aimed_at_leader = |p: &Player| {
            leader_id.is_some_and(|leader| self.encounters.committed_target(p.id) == Some(leader))
        };
        let priority = |p: &Player| {
            let from = if covering {
                leader_feet.unwrap_or(feet)
            } else {
                feet
            };
            (
                !aimed_at_leader(p),
                distance(from, [p.x, p.y - PLAYER_FLOOR_Y, p.z]),
            )
        };
        let target = can_fire
            .then(|| {
                engageable
                    .iter()
                    .filter(|p| {
                        distance(feet, [p.x, p.y - PLAYER_FLOOR_Y, p.z]) <= SUPPORT_RANGE
                            && line_of_sight(
                                eye,
                                aim_point_for(
                                    [p.x, p.y - PLAYER_FLOOR_Y, p.z],
                                    p.campaign,
                                    p.ducking,
                                ),
                                &self.map.arena().solids,
                            )
                            && clear_support_ray(self, id, eye, p, &civilians, &tableau)
                    })
                    .min_by(|a, b| {
                        let (pa, da) = priority(a);
                        let (pb, db) = priority(b);
                        pa.cmp(&pb).then(da.total_cmp(&db))
                    })
                    .map(|p| p.id)
            })
            .flatten();
        // The threat Latch positions against: the nearest engageable enemy
        // the participant can see.
        let threat = leader_feet.and_then(|leader| {
            let leader_eye = [
                leader[0],
                leader[1] + crate::movement::EYE_HEIGHT,
                leader[2],
            ];
            engageable
                .iter()
                .filter(|p| {
                    line_of_sight(
                        leader_eye,
                        aim_point_for([p.x, p.y - PLAYER_FLOOR_Y, p.z], p.campaign, p.ducking),
                        &self.map.arena().solids,
                    )
                })
                .min_by(|a, b| {
                    distance(leader, [a.x, a.y - PLAYER_FLOOR_Y, a.z])
                        .total_cmp(&distance(leader, [b.x, b.y - PLAYER_FLOOR_Y, b.z]))
                })
                .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
        });
        let quiet = engageable.is_empty();
        let leader_state = leader.map(|p| formation::Leader {
            feet: [p.x, p.y - PLAYER_FLOOR_Y, p.z],
            yaw: p.yaw,
            velocity: [p.vx, p.vz],
        });

        if let Some(run) = self.mission.as_mut() {
            run.companion.leader_fired = leader_fired;
        }
        let mut intent = BotIntent::default();
        let next_phase = if let Some(target_id) = target {
            intent.action = Action {
                fire: true,
                look_at: Some(LookAt {
                    player_id: Some(target_id),
                    ..LookAt::default()
                }),
                ..Action::default()
            };
            let aimed = self
                .players
                .iter()
                .find(|p| p.id == target_id)
                .is_some_and(aimed_at_leader);
            if let Some(run) = self.mission.as_mut() {
                let support = &mut run.companion;
                support.spent += 1;
                support.shots += 1;
                support.covering_shots += u32::from(covering || aimed);
                support.last_shot = Some(tick);
                if support.spent >= MAGAZINE {
                    support.reload(tick);
                }
            }
            CompanionPhase::Firing
        } else {
            // Top up in a quiet moment, never while the participant is
            // counting on cover.
            if let Some(run) = self.mission.as_mut() {
                if run.companion.spent >= MAGAZINE || (quiet && !covering) {
                    run.companion.reload(tick);
                }
            }
            if let Some(leader) = leader_state {
                let arena = self.current_arena();
                let bodies = self.contact_bodies();
                let solids = &self.map.arena().solids;
                intent.goal = formation::goal(
                    &arena,
                    companion_body(self, id)?,
                    &leader,
                    self.mission.as_ref().is_some_and(|run| run.m02.is_some()),
                    &bodies,
                    threat.map(|threat| formation::Threat {
                        feet: threat,
                        solids,
                    }),
                );
                if intent.goal.is_none() {
                    intent.action = formation::short_yield(
                        &arena,
                        companion_body(self, id)?,
                        leader.feet,
                        &bodies,
                    )
                    .unwrap_or_default();
                }
            }
            CompanionPhase::Following
        };
        if let Some(player) = self.players.iter_mut().find(|p| p.id == id) {
            if let Some(CampaignActor::Companion {
                kind,
                phase,
                phase_started,
            }) = player.campaign
            {
                if phase != next_phase {
                    player.campaign = Some(CampaignActor::Companion {
                        kind,
                        phase: next_phase,
                        phase_started: tick,
                    });
                } else {
                    player.campaign = Some(CampaignActor::Companion {
                        kind,
                        phase,
                        phase_started,
                    });
                }
            }
        }
        Some((id, intent))
    }
}

fn companion_body(state: &GameState, id: Uuid) -> Option<&Player> {
    state.players.iter().find(|p| p.id == id)
}
