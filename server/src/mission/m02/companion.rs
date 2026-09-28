//! Bounded M02 support. Latch follows the party and fires only at active threats.
use super::*;
use crate::combat::{aim_at, line_of_sight, target_height, Ray};
use crate::navigation::NavigationGoal;
use crate::protocol::{Action, CompanionPhase, LookAt};
use crate::sim::{BotIntent, Player, PLAYER_RADIUS};

const FORMATION_TOLERANCE: f32 = 0.65;
const SUPPORT_RANGE: f32 = 12.0;
const PARTY_RANGE: f32 = 16.0;
const MAX_SUPPORT_SHOTS: u8 = 12;
const SUPPORT_COOLDOWN: u64 = 40;

fn distance(a: [f32; 3], b: [f32; 3]) -> f32 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

/// Match the finite hitscan body test before committing a limited support shot.
fn clear_support_ray(state: &GameState, origin: [f32; 3], target: &Player) -> bool {
    let target_feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
    let centre = [
        target.x,
        target_feet[1] + target_height(target.campaign) * 0.5,
        target.z,
    ];
    let Some((yaw, pitch)) = aim_at(origin, centre) else {
        return false;
    };
    let ray = Ray::dispersed(origin, yaw, pitch, 0.0, [0.0, 0.0]);
    let Some(hostile) = ray.fighter_with_height(
        target_feet,
        PLAYER_RADIUS,
        target_height(target.campaign),
        SUPPORT_RANGE,
    ) else {
        return false;
    };
    !state.players.iter().any(|participant| {
        participant.campaign == Some(CampaignActor::Participant {})
            && participant.hp > 0
            && participant.respawn_timer.is_none()
            && crate::mission::actor_active(
                state.mission.as_ref(),
                participant.id,
                participant.campaign,
            )
            && !state
                .spawn_shields
                .get(&participant.id)
                .is_some_and(|ticks| *ticks > 0)
            && ray
                .fighter_with_height(
                    [participant.x, participant.y - PLAYER_FLOOR_Y, participant.z],
                    PLAYER_RADIUS,
                    target_height(participant.campaign),
                    hostile.distance,
                )
                .is_some_and(|hit| hit.distance < hostile.distance)
    })
}

impl GameState {
    pub(crate) fn m02_companion_intent(&mut self) -> Option<(Uuid, BotIntent)> {
        let run = self.mission.as_ref()?;
        let progress = run.m02.as_ref()?;
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
            && progress.support_shots < MAX_SUPPORT_SHOTS
            && progress
                .last_support_tick
                .is_none_or(|last| self.tick.saturating_sub(last) >= SUPPORT_COOLDOWN);
        let target = can_fire
            .then(|| {
                self.players
                    .iter()
                    .filter(|p| {
                        p.hp > 0
                            && p.respawn_timer.is_none()
                            && p.campaign.is_some_and(CampaignActor::is_enemy)
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
                            [
                                p.x,
                                p.y - PLAYER_FLOOR_Y + target_height(p.campaign) * 0.5,
                                p.z,
                            ],
                            &self.map.arena().solids,
                        ) && clear_support_ray(self, origin, p)
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
            CompanionPhase::Firing
        } else {
            // The return route crosses the ward opening near the west side of
            // the processing floor. A west-forward slot carries Latch through
            // that opening while leaving the participant's aim lane clear.
            let formation = leader_feet
                .map(|leader| [(leader[0] - 2.4).max(-13.0), leader[1], leader[2] + 1.2]);
            if let Some(leader) = formation.filter(|p| distance(feet, *p) > FORMATION_TOLERANCE) {
                intent.goal = Some(NavigationGoal {
                    feet: leader,
                    combat: false,
                });
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
