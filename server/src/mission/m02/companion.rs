//! Bounded M02 support. Latch follows the party and fires only at active threats.
use super::*;
use crate::combat::{aim_at, aim_point_for, line_of_sight, Ray};
use crate::protocol::{Action, CompanionPhase, LookAt};
use crate::sim::{BotIntent, Player};

mod formation;
#[cfg(test)]
mod tests;
const SUPPORT_RANGE: f32 = 12.0;
const PARTY_RANGE: f32 = 16.0;
const MAX_SUPPORT_SHOTS: u8 = 12;
const SUPPORT_COOLDOWN: u64 = 40;

fn distance(a: [f32; 3], b: [f32; 3]) -> f32 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

/// Match the finite hitscan body test before committing a limited support shot.
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
    pub(crate) fn m02_companion_intent(&mut self) -> Option<(Uuid, BotIntent)> {
        let run = self.mission.as_ref()?;
        let (support_shots, last_support_tick) = if let Some(progress) = run.m02.as_ref() {
            (progress.support_shots, progress.last_support_tick)
        } else if let Some(progress) = run.m03.as_ref() {
            (progress.support_shots, progress.last_support_tick)
        } else if let Some(progress) = run.m06.as_ref() {
            (progress.support_shots, progress.last_support_tick)
        } else if let Some(progress) = run.m07.as_ref() {
            (progress.support_shots, progress.last_support_tick)
        } else {
            let progress = run.m04.as_ref()?;
            (progress.support_shots, progress.last_support_tick)
        };
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
        let can_fire = leader_feet.is_some_and(|p| distance(feet, p) <= PARTY_RANGE)
            && support_shots < MAX_SUPPORT_SHOTS
            && last_support_tick
                .is_none_or(|last| self.tick.saturating_sub(last) >= SUPPORT_COOLDOWN);
        let mut civilians = Vec::new();
        self.append_civilian_contacts(&mut civilians);
        let mut tableau = Vec::new();
        self.append_m02_tableau_shots(&mut civilians, &mut tableau);
        let target = can_fire
            .then(|| {
                self.players
                    .iter()
                    .filter(|p| {
                        p.hp > 0
                            && p.respawn_timer.is_none()
                            && p.campaign.is_some_and(CampaignActor::is_enemy)
                            && !(run.m04.as_ref().is_some_and(|progress| progress.index <= 1)
                                && crate::combat::is_notary(p.campaign))
                            && !run.initial_map.m06_objectives().is_some_and(|prepared| {
                                [prepared.encounters[1], prepared.encounters[3]]
                                    .iter()
                                    .any(|index| self.encounters.enemy_in_group(p.id, *index))
                            })
                            && !run.initial_map.m07_objectives().is_some_and(|prepared| {
                                self.encounters
                                    .enemy_in_group(p.id, prepared.lesson_encounter)
                            })
                            && self.encounters.is_active_enemy(p.id)
                            && distance(feet, [p.x, p.y - PLAYER_FLOOR_Y, p.z]) <= SUPPORT_RANGE
                            && leader_feet.is_some_and(|leader| {
                                distance(leader, [p.x, p.y - PLAYER_FLOOR_Y, p.z]) <= PARTY_RANGE
                            })
                    })
                    .filter(|p| {
                        let origin = [feet[0], feet[1] + crate::movement::EYE_HEIGHT, feet[2]];
                        line_of_sight(
                            origin,
                            aim_point_for([p.x, p.y - PLAYER_FLOOR_Y, p.z], p.campaign, p.ducking),
                            &self.map.arena().solids,
                        ) && clear_support_ray(self, id, origin, p, &civilians, &tableau)
                    })
                    .min_by(|a, b| {
                        distance(feet, [a.x, a.y, a.z]).total_cmp(&distance(feet, [b.x, b.y, b.z]))
                    })
                    .map(|p| p.id)
            })
            .flatten();

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
            if let Some(progress) = self.mission.as_mut().and_then(|run| run.m02.as_mut()) {
                progress.support_shots += 1;
                progress.last_support_tick = Some(self.tick);
            }
            if let Some(progress) = self.mission.as_mut().and_then(|run| run.m03.as_mut()) {
                progress.support_shots += 1;
                progress.last_support_tick = Some(self.tick);
            }
            if let Some(progress) = self.mission.as_mut().and_then(|run| run.m04.as_mut()) {
                progress.support_shots += 1;
                progress.last_support_tick = Some(self.tick);
            }
            if let Some(progress) = self.mission.as_mut().and_then(|run| run.m06.as_mut()) {
                progress.support_shots += 1;
                progress.last_support_tick = Some(self.tick);
            }
            if let Some(progress) = self.mission.as_mut().and_then(|run| run.m07.as_mut()) {
                progress.support_shots += 1;
                progress.last_support_tick = Some(self.tick);
            }
            CompanionPhase::Firing
        } else {
            if let Some(leader) = leader_feet {
                let arena = self.current_arena();
                let bodies = self.contact_bodies();
                intent.goal = formation::goal(
                    &arena,
                    companion,
                    leader,
                    self.mission.as_ref().is_some_and(|run| run.m02.is_some()),
                    &bodies,
                );
                if intent.goal.is_none() {
                    intent.action = formation::short_yield(&arena, companion, leader, &bodies)
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
                        phase_started: self.tick,
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
