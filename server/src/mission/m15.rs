//! Civic Pressure Valve: connected stadium bout progression, armed entrants and departure.
use super::*;
use crate::combat::{aim_point_for, line_of_sight};
use crate::movement::{Solid, EYE_HEIGHT};
use crate::protocol::{
    Action, CampaignActor, EquipmentPolicy, InteractionKind, InteractionPrompt, LookAt,
    M15ChallengeState, M15ObjectiveState, MissionMember, MissionObjectiveAction, MissionPhase,
    Role, WeaponType, M15_ENTRANTS, M15_OBJECTIVE_IDS,
};
use crate::sim::{BotIntent, Player, PLAYER_FLOOR_Y};
use std::collections::HashSet;
use uuid::Uuid;

#[derive(Default)]
pub(crate) struct M15Progress {
    pub(super) index: usize,
    pub(super) challenges: M15ChallengeState,
    pub(super) wave: u8,
    pub(super) broadcast_taken: bool,
    pub(super) tunnel_closed: bool,
    pub(super) gates_open: bool,
    pub(super) armed_entrants: Vec<u8>,
    pub(super) fallen_entrants: Vec<u8>,
    pub(super) blade_disqualified: bool,
    pub(super) blade_hits: u32,
    pub(super) entrant_ids: Vec<(u8, Uuid)>,
}

#[cfg(test)]
mod tests;

impl GameState {
    pub(crate) fn m15_encounter_available(&self, index: usize) -> bool {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m15.as_ref()) else {
            return true;
        };
        match index {
            0 => p.index >= 1,
            1 => p.index >= 2,
            2 => p.index >= 3,
            3 => p.index >= 3,
            4 => p.index >= 4,
            5 => p.broadcast_taken,
            _ => false,
        }
    }

    pub(crate) fn ensure_m15_entrants(&mut self) {
        if !self.mission.as_ref().is_some_and(|r| r.m15.is_some()) {
            return;
        }
        if self
            .players
            .iter()
            .any(|p| p.campaign.is_some_and(CampaignActor::is_entrant))
        {
            return;
        }
        let spawns: [(u8, [f32; 3]); 4] = [
            (4, [-16.0, 0.0, -29.4]),
            (12, [-12.0, 0.0, -29.4]),
            (44, [-8.0, 0.0, -29.4]),
            (71, [-4.0, 0.0, -29.4]),
        ];
        let mut ids = Vec::new();
        for (placard, feet) in spawns {
            let id = self.new_entity_id();
            let [x, floor, z] = feet;
            let mut player = Player::at_spawn(
                id,
                format!("Entrant {placard}"),
                Role::Agent,
                (x, z, 0.0, floor),
                EquipmentPolicy::Discovery,
            );
            player.weapon = WeaponType::Fists;
            player.campaign = Some(CampaignActor::Entrant {
                placard,
                armed: false,
            });
            self.players.push(player);
            ids.push((placard, id));
        }
        if let Some(p) = self.mission.as_mut().and_then(|r| r.m15.as_mut()) {
            p.entrant_ids = ids;
        }
    }

    pub(crate) fn m15_entrant_intents(&mut self) -> Vec<(Uuid, BotIntent)> {
        let run = match self.mission.as_ref() {
            Some(r) if r.m15.is_some() && r.phase == MissionPhase::InProgress => r,
            _ => return Vec::new(),
        };
        let p = match run.m15.as_ref() {
            Some(p) => p,
            None => return Vec::new(),
        };
        let mut intents = Vec::new();
        let solids = &self.map.arena().solids;
        for (_placard, id) in &p.entrant_ids {
            let entrant = match self.players.iter().find(|pl| pl.id == *id && pl.hp > 0) {
                Some(pl) => pl,
                None => continue,
            };
            let armed = match entrant.campaign {
                Some(CampaignActor::Entrant { armed, .. }) => armed,
                _ => false,
            };
            let feet = [entrant.x, entrant.y - PLAYER_FLOOR_Y, entrant.z];
            let mut intent = BotIntent::default();
            if armed {
                let origin = [feet[0], feet[1] + EYE_HEIGHT, feet[2]];
                let target = self
                    .players
                    .iter()
                    .filter(|enemy| {
                        enemy.hp > 0
                            && enemy.respawn_timer.is_none()
                            && enemy.campaign.is_some_and(CampaignActor::is_enemy)
                    })
                    .filter(|enemy| {
                        let enemy_feet = [enemy.x, enemy.y - PLAYER_FLOOR_Y, enemy.z];
                        let dx = enemy_feet[0] - feet[0];
                        let dy = enemy_feet[1] - feet[1];
                        let dz = enemy_feet[2] - feet[2];
                        let dist = (dx * dx + dy * dy + dz * dz).sqrt();
                        dist <= 18.0
                            && line_of_sight(
                                origin,
                                aim_point_for(enemy_feet, enemy.campaign, enemy.ducking),
                                solids,
                            )
                    })
                    .min_by(|a, b| {
                        let da = (a.x - feet[0]).powi(2) + (a.z - feet[2]).powi(2);
                        let db = (b.x - feet[0]).powi(2) + (b.z - feet[2]).powi(2);
                        da.total_cmp(&db)
                    });
                if let Some(target) = target {
                    intent.action = Action {
                        fire: true,
                        look_at: Some(LookAt {
                            player_id: Some(target.id),
                            ..LookAt::default()
                        }),
                        ..Action::default()
                    };
                }
            }
            intents.push((*id, intent));
        }
        intents
    }

    pub(crate) fn record_m15_damage(
        &mut self,
        shooter_id: Uuid,
        victim_id: Uuid,
        weapon: Option<WeaponType>,
        damage: i32,
        died: bool,
    ) {
        let run = match self.mission.as_mut() {
            Some(r) if r.m15.is_some() && r.phase == MissionPhase::InProgress => r,
            _ => return,
        };
        let p = match run.m15.as_mut() {
            Some(p) => p,
            None => return,
        };
        // Track entrant mortality
        if let Some(victim) = self.players.iter().find(|pl| pl.id == victim_id) {
            if let Some(CampaignActor::Entrant { placard, armed }) = victim.campaign {
                if died && !p.fallen_entrants.contains(&placard) {
                    p.fallen_entrants.push(placard);
                    if armed {
                        p.challenges.entrants_preserved = false;
                    }
                }
            }
        }
        // Track Blade wave challenge: encounter 1 (floor_lifts)
        if damage > 0 && self.encounters.enemy_in_group(victim_id, 1) {
            let shooter_is_participant = self
                .players
                .iter()
                .find(|pl| pl.id == shooter_id)
                .is_some_and(Player::is_participant);
            if shooter_is_participant {
                if weapon == Some(WeaponType::ArticleBlade) {
                    p.blade_hits += 1;
                } else {
                    p.blade_disqualified = true;
                }
            }
        }
    }

    pub(super) fn m15_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m15.as_ref()?;
        let g = run.initial_map.m15_geometry()?;
        let party: Vec<_> = self
            .players
            .iter()
            .filter(|pl| pl.is_participant())
            .map(|a| {
                let ready = run.ready.contains(&a.id);
                let alive = self.contact_eligible(a);
                MissionMember {
                    id: a.id,
                    name: a.name.clone(),
                    ready,
                    alive: a.hp > 0 && a.respawn_timer.is_none(),
                    aboard: ready && alive && g.boarding.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z]),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<_> = M15_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).to_owned())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < 6 {
            Some(g.objectives[p.index].clone())
        } else {
            Some(g.departure_objective())
        };
        let arena = self.current_arena();
        let mut prompts = Vec::new();
        if run.phase == MissionPhase::InProgress && !self.campaign_run_frozen() {
            if p.index == 0 {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.arming_crate, &self.map, &arena)
                        })
                        .map(|a| InteractionPrompt {
                            player_id: a.id,
                            kind: InteractionKind::ObjectiveUse,
                        }),
                );
            } else if p.index == 4 && self.encounters.is_complete(4) {
                prompts.extend(
                    self.players
                        .iter()
                        .filter(|a| {
                            self.contact_eligible(a)
                                && run.ready.contains(&a.id)
                                && can_use_in_arena(a, &g.booth_terminal, &self.map, &arena)
                        })
                        .map(|a| InteractionPrompt {
                            player_id: a.id,
                            kind: InteractionKind::ObjectiveUse,
                        }),
                );
            } else if p.index == 6 {
                let departure_ready =
                    !party.is_empty() && party.iter().all(|m| m.ready && m.alive && m.aboard);
                if departure_ready {
                    prompts.extend(
                        self.players
                            .iter()
                            .filter(|a| {
                                self.contact_eligible(a)
                                    && run.ready.contains(&a.id)
                                    && can_use_in_arena(a, &g.departure, &self.map, &arena)
                            })
                            .map(|a| InteractionPrompt {
                                player_id: a.id,
                                kind: InteractionKind::ObjectiveUse,
                            }),
                    );
                }
            }
        }
        Some(MissionState {
            id: MissionId::CivicPressureValve,
            run: run.solo.as_ref().map(|s| s.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            m02: None,
            m03: None,
            m04: None,
            m05: None,
            m06: None,
            m07: None,
            m08: None,
            m09: None,
            m10: None,
            m11: None,
            m12: None,
            m13: None,
            m14: None,
            m15: Some(M15ObjectiveState {
                completed,
                current,
                challenges: p.challenges.clone(),
                tunnel_closed: p.tunnel_closed,
                gates_open: p.gates_open,
                broadcast_taken: p.broadcast_taken,
                wave: p.wave,
                armed_entrants: p.armed_entrants.clone(),
                fallen_entrants: p.fallen_entrants.clone(),
            }),
        })
    }

    fn try_close_m15_tunnel(&mut self) {
        let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
        if p.tunnel_closed || p.index < 2 {
            return;
        }
        let any_behind = self
            .players
            .iter()
            .any(|pl| pl.is_participant() && self.contact_eligible(pl) && pl.z <= -12.4);
        if any_behind {
            return;
        }
        let gate_bounds = Solid {
            min_x: -4.0,
            bottom: 0.0,
            min_z: -12.4,
            max_x: 4.0,
            top: 2.2,
            max_z: -11.6,
        };
        let occupied = self.players.iter().any(|pl| {
            pl.hp > 0
                && pl.respawn_timer.is_none()
                && pl.x + crate::movement::RADIUS > gate_bounds.min_x
                && pl.x - crate::movement::RADIUS < gate_bounds.max_x
                && pl.z + crate::movement::RADIUS > gate_bounds.min_z
                && pl.z - crate::movement::RADIUS < gate_bounds.max_z
                && pl.y - PLAYER_FLOOR_Y < gate_bounds.top
                && pl.y - PLAYER_FLOOR_Y + crate::combat::body_height(pl.campaign, pl.ducking)
                    > gate_bounds.bottom
        });
        if occupied {
            return;
        }
        if let Some(world) = self.map.prepared_m15_world(1) {
            self.map = world;
            let run = self.mission.as_mut().unwrap();
            run.m15.as_mut().unwrap().tunnel_closed = true;
            run.changed_at = self.tick;
        }
    }

    fn try_open_m15_gates(&mut self) {
        let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
        if p.gates_open || p.index < 6 {
            return;
        }
        if let Some(world) = self.map.prepared_m15_world(2) {
            self.map = world;
            let run = self.mission.as_mut().unwrap();
            run.m15.as_mut().unwrap().gates_open = true;
            run.changed_at = self.tick;
        }
    }

    pub(super) fn advance_m15(&mut self) {
        let requests: HashSet<_> = self
            .players
            .iter_mut()
            .filter_map(|p| std::mem::take(&mut p.interaction_requested).then_some(p.id))
            .collect();
        if self.campaign_run_frozen()
            || !self
                .mission
                .as_ref()
                .is_some_and(|r| r.phase == MissionPhase::InProgress)
        {
            return;
        }
        let Some(g) = self.map.m15_geometry() else {
            return;
        };
        let old = self.m15_mission_state().unwrap().m15.unwrap();
        let index = self.mission.as_ref().unwrap().m15.as_ref().unwrap().index;

        let mut advanced = false;
        if index == 0 {
            let used_arming = self.players.iter().any(|pl| {
                requests.contains(&pl.id)
                    && pl.is_participant()
                    && self.contact_eligible(pl)
                    && can_use_in_arena(pl, &g.arming_crate, &self.map, self.map.arena())
            });
            if used_arming {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                p.challenges.pen_armed = true;
                p.armed_entrants = M15_ENTRANTS.to_vec();
                p.index = 1;
                for player in &mut self.players {
                    if let Some(CampaignActor::Entrant { placard, .. }) = player.campaign {
                        player.campaign = Some(CampaignActor::Entrant {
                            placard,
                            armed: true,
                        });
                        player.weapon = WeaponType::Tack;
                        player.inventory.grant_weapon(WeaponType::Tack);
                        player
                            .inventory
                            .grant_ammo(crate::protocol::AmmoPool::Bullets, 60);
                    }
                }
                advanced = true;
            }
        } else if index == 1 {
            let pen_gate_clear = self.encounters.is_complete(0);
            let arrived = match &g.objectives[1].action {
                MissionObjectiveAction::Arrival { region, .. } => self.players.iter().any(|a| {
                    a.is_participant()
                        && self.contact_eligible(a)
                        && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
                }),
                _ => false,
            };
            if pen_gate_clear && arrived {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                p.index = 2;
                p.wave = 1;
                advanced = true;
            }
        } else if index == 2 {
            let blade_wave_clear = self.encounters.is_complete(1);
            if blade_wave_clear {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                p.challenges.blade_wave_won = !p.blade_disqualified && p.blade_hits > 0;
                p.index = 3;
                p.wave = 2;
                advanced = true;
            }
        } else if index == 3 {
            let tunnel_wardens_clear = self.encounters.is_complete(2);
            let notaries_clear = self.encounters.is_complete(3);
            if tunnel_wardens_clear {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                if p.wave < 3 {
                    p.wave = 3;
                }
            }
            if tunnel_wardens_clear && notaries_clear {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                p.index = 4;
                p.wave = 4;
                advanced = true;
            }
        } else if index == 4 {
            let booth_wardens_clear = self.encounters.is_complete(4);
            let used_booth = booth_wardens_clear
                && self.players.iter().any(|pl| {
                    requests.contains(&pl.id)
                        && pl.is_participant()
                        && self.contact_eligible(pl)
                        && can_use_in_arena(pl, &g.booth_terminal, &self.map, self.map.arena())
                });
            if used_booth {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                p.broadcast_taken = true;
                p.index = 5;
                p.wave = 5;
                advanced = true;
            }
        } else if index == 5 {
            let bout_won = self.encounters.is_complete(5);
            if bout_won {
                let p = self.mission.as_mut().unwrap().m15.as_mut().unwrap();
                p.index = 6;
                advanced = true;
            }
        }

        self.try_close_m15_tunnel();
        self.try_open_m15_gates();

        let new = self.m15_mission_state().unwrap();
        if advanced || new.m15.as_ref() != Some(&old) {
            self.mission.as_mut().unwrap().changed_at = self.tick;
        }

        if advanced || index < 6 {
            return;
        }

        // Final departure check
        if !new.prompts.iter().any(|p| requests.contains(&p.player_id)) {
            return;
        }
        let exit = if new.run.is_some() {
            let Some(owner) = self
                .mission
                .as_ref()
                .and_then(|r| r.solo.as_ref())
                .and_then(recovery::SoloRun::owner)
            else {
                return;
            };
            let Some(player) = self.players.iter().find(|p| p.id == owner) else {
                return;
            };
            let Ok(entry) = run_file::SavedEntry::from_player(player) else {
                return;
            };
            Some(entry)
        } else {
            None
        };
        let run = self.mission.as_mut().unwrap();
        run.phase = MissionPhase::Departed;
        run.changed_at = self.tick;
        if let Some(solo) = &mut run.solo {
            if let Some(exit) = exit {
                solo.capture_exit(exit);
            }
            solo.state.status = crate::protocol::CampaignRunStatus::Complete;
        }
    }
}
