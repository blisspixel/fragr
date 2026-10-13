//! Foundry gates shared by standalone fixtures and the connected mission.
//! The connected owner adds ordered progress, worker movement and party exit.
use crate::movement::{MoveState, DUCK_HEIGHT};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

mod connected;
#[cfg(test)]
mod connected_tests;
mod hazard;
mod lift;
mod relay;
mod workers;
pub(super) use connected::M13Progress;

#[cfg(test)]
mod tests;

pub(crate) use hazard::Cycle;
pub(crate) use lift::{deck_at, step_blocked, Body as LiftBody};

pub(crate) fn hazard_overlap(a: &crate::protocol::Region3, b: &crate::protocol::Region3) -> bool {
    hazard::regions_overlap(a, b)
}

pub(crate) fn workers_distance(feet: [f32; 3], approach: [f32; 3]) -> f32 {
    workers::distance(feet, approach)
}

#[derive(Debug, Clone)]
pub(crate) struct Gates {
    pub(crate) relay: usize,
    pub(crate) protected: Vec<usize>,
    pub(crate) hazard: crate::protocol::Region3,
    pub(crate) bypass: crate::protocol::Region3,
    pub(crate) cycle: Cycle,
    pub(crate) release: crate::protocol::UseTarget,
    pub(crate) quarters_group: usize,
    pub(crate) deck_index: usize,
    pub(crate) deck: crate::movement::Solid,
    pub(crate) inset_min: [f32; 2],
    pub(crate) inset_max: [f32; 2],
    pub(crate) lift_top: f32,
}

#[derive(Debug, Clone)]
pub(crate) struct Progress {
    pub(crate) relay_disabled: bool,
    pub(crate) workers: Option<[workers::Response; 3]>,
    pub(crate) hazard_hurt: u64,
    pub(crate) lift_top: f32,
    pub(crate) lift_phase: lift::Phase,
    pub(crate) returning: bool,
}

impl Progress {
    pub(crate) fn new(gates: &Gates) -> Self {
        Self {
            relay_disabled: false,
            workers: None,
            hazard_hurt: 0,
            lift_top: gates.deck.top,
            lift_phase: lift::Phase::Parked,
            returning: false,
        }
    }
}

impl GameState {
    pub(crate) fn foundry_arena(&self) -> Option<crate::movement::Arena> {
        let gates = self.map.m13_gates()?;
        let progress = self.foundry.as_ref()?;
        if (progress.lift_top - gates.deck.top).abs() <= 0.001 {
            return None;
        }
        let deck = lift::deck_at(gates.deck, progress.lift_top)?;
        let mut arena = self.map.arena().clone();
        arena.solids[gates.deck_index] = deck;
        Some(arena)
    }

    pub(crate) fn damage_foundry_relay(
        &mut self,
        shooter: Uuid,
        solid: usize,
        end: [f32; 3],
        normal: [f32; 3],
        damage: i32,
    ) {
        if damage <= 0 || self.campaign_run_frozen() {
            return;
        }
        if self
            .mission
            .as_ref()
            .and_then(|r| r.m13.as_ref())
            .is_some_and(|p| p.index != 4)
        {
            return;
        }
        let Some(gates) = self.map.m13_gates() else {
            return;
        };
        let relay = gates.relay;
        let protected = gates.protected.clone();
        let Some(host) = self.map.arena().solids.get(solid).copied() else {
            return;
        };
        let allowed = self.players.iter().any(|player| {
            player.id == shooter && player.is_participant() && self.contact_eligible(player)
        });
        if !allowed {
            return;
        }
        match relay::classify(solid, relay, &protected) {
            relay::Hit::Protected | relay::Hit::Other => {}
            relay::Hit::Relay if relay::on_face(end, normal, &host) => {
                if let Some(progress) = &mut self.foundry {
                    progress.relay_disabled = true;
                }
            }
            relay::Hit::Relay => {}
        }
    }

    pub(crate) fn tick_foundry_hazards(&mut self) {
        if self.campaign_run_frozen()
            || self
                .mission
                .as_ref()
                .is_some_and(|r| r.phase != crate::protocol::MissionPhase::InProgress)
        {
            return;
        }
        let Some(gates) = self.map.m13_gates().cloned() else {
            return;
        };
        let tick = self.tick;
        let hits: Vec<(usize, i32)> = self
            .players
            .iter()
            .enumerate()
            .filter_map(|(index, player)| {
                if !player.is_participant() || !self.contact_eligible(player) {
                    return None;
                }
                let height = if player.ducking {
                    DUCK_HEIGHT
                } else {
                    crate::combat::target_height(player.campaign)
                };
                let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
                let in_hazard = hazard::body_touches(feet, height, &gates.hazard)
                    && !hazard::body_touches(feet, height, &gates.bypass);
                let amount = hazard::damage(tick, gates.cycle, in_hazard);
                (amount > 0).then_some((index, amount))
            })
            .collect();
        for (index, amount) in hits {
            let (hp, armor) = self.environmental_self_damage(index, amount);
            if hp.saturating_add(armor) > 0 {
                if let Some(run) = self.mission.as_mut() {
                    run.changed_at = self.tick;
                }
            }
            if let Some(progress) = &mut self.foundry {
                progress.hazard_hurt = progress
                    .hazard_hurt
                    .saturating_add(hp.saturating_add(armor));
            }
        }
    }

    pub(crate) fn advance_foundry_lift(&mut self, dt: f32) {
        if self.campaign_run_frozen()
            || self
                .mission
                .as_ref()
                .is_some_and(|r| r.phase != crate::protocol::MissionPhase::InProgress)
        {
            return;
        }
        let Some(gates) = self.map.m13_gates().cloned() else {
            return;
        };
        let Some(progress) = self.foundry.as_ref() else {
            return;
        };
        let connected = self.map.m13_geometry();
        if connected.as_ref().is_some_and(|g| {
            progress.lift_phase != lift::Phase::Parked && !self.m13_party_supported(g)
        }) {
            let progress = self.foundry.as_mut().unwrap();
            progress.returning = true;
            progress.lift_phase = lift::Phase::Returning;
        }
        let progress = self.foundry.as_ref().unwrap();
        if !matches!(
            progress.lift_phase,
            lift::Phase::Moving | lift::Phase::Blocked | lift::Phase::Returning
        ) {
            return;
        }
        let returning = progress.returning;
        let step = if returning {
            lift::delta_y(gates.deck.top, progress.lift_top, dt).map(|d| -d)
        } else {
            lift::delta_y(progress.lift_top, gates.lift_top, dt)
        };
        let Some(delta) = step else {
            return;
        };
        if delta == 0.0 {
            if let Some(progress) = &mut self.foundry {
                progress.lift_phase = if returning {
                    lift::Phase::Parked
                } else {
                    lift::Phase::Arrived
                };
                progress.returning = false;
            }
            return;
        }
        let Some(old_deck) = lift::deck_at(gates.deck, progress.lift_top) else {
            return;
        };
        let Some(new_deck) = lift::deck_at(gates.deck, progress.lift_top + delta) else {
            return;
        };
        let bodies: Vec<(Uuid, lift::Body)> = self
            .players
            .iter()
            .filter(|player| self.contact_eligible(player))
            .map(|player| {
                let feet_y = player.y - PLAYER_FLOOR_Y;
                let height = if player.ducking {
                    DUCK_HEIGHT
                } else {
                    crate::combat::target_height(player.campaign)
                };
                let state = MoveState {
                    x: player.x,
                    y: feet_y,
                    z: player.z,
                    vx: 0.0,
                    vz: 0.0,
                    vy: player.vy,
                    yaw: player.yaw,
                };
                let supported = lift::supported(
                    state,
                    old_deck,
                    gates.inset_min,
                    gates.inset_max,
                    player.platform_jump_requested(),
                );
                (
                    player.id,
                    lift::Body {
                        x: player.x,
                        y: feet_y,
                        z: player.z,
                        height,
                        supported,
                    },
                )
            })
            .collect();
        let blocked = lift::step_blocked(
            old_deck,
            new_deck,
            &bodies.iter().map(|(_, body)| *body).collect::<Vec<_>>(),
            &self.map.arena().solids,
            gates.deck_index,
        );
        if blocked {
            if let Some(progress) = &mut self.foundry {
                progress.lift_phase = lift::Phase::Blocked;
            }
            if let Some(run) = self.mission.as_mut() {
                run.changed_at = self.tick;
            }
            return;
        }
        for (id, body) in &bodies {
            if !body.supported {
                continue;
            }
            if let Some(player) = self.players.iter_mut().find(|player| player.id == *id) {
                player.y += delta;
                player.vy = 0.0;
            }
        }
        if let Some(progress) = &mut self.foundry {
            progress.lift_top += delta;
            progress.lift_phase = if returning && progress.lift_top - gates.deck.top <= 0.001 {
                progress.returning = false;
                progress.lift_top = gates.deck.top;
                lift::Phase::Parked
            } else if returning {
                lift::Phase::Returning
            } else if gates.lift_top - progress.lift_top <= 0.001 {
                lift::Phase::Arrived
            } else {
                lift::Phase::Moving
            };
        }
        if let Some(run) = self.mission.as_mut() {
            run.changed_at = self.tick;
        }
    }

    pub(super) fn advance_foundry(&mut self) {
        let requests: Vec<Uuid> = self
            .players
            .iter_mut()
            .filter_map(|player| {
                std::mem::take(&mut player.interaction_requested).then_some(player.id)
            })
            .collect();
        let Some(gates) = self.map.m13_gates().cloned() else {
            return;
        };
        let frozen = self.campaign_run_frozen();
        let clear = self.encounters.is_complete(gates.quarters_group);
        let threats = self.encounters.is_awake(gates.quarters_group) && !clear;
        let already = self
            .foundry
            .as_ref()
            .is_some_and(|progress| progress.workers.is_some());
        let phase = self.foundry.as_ref().map(|progress| progress.lift_phase);
        let lift_top = self.foundry.as_ref().map(|progress| progress.lift_top);
        let mut released = None;
        let mut board = false;
        for id in requests {
            let Some(player) = self.players.iter().find(|player| player.id == id) else {
                continue;
            };
            let feet = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            let active = player.is_participant() && self.contact_eligible(player) && !frozen;
            if released.is_none()
                && super::can_use_in_arena(player, &gates.release, &self.map, &self.current_arena())
            {
                let distance = workers::distance(feet, gates.release.approach);
                if let Ok(responses) =
                    workers::try_release(active, clear, threats, already, distance)
                {
                    released = Some(responses);
                }
            }
            if active && phase == Some(lift::Phase::Parked) {
                if let Some(top) = lift_top.and_then(|top| lift::deck_at(gates.deck, top)) {
                    let state = MoveState {
                        x: player.x,
                        y: feet[1],
                        z: player.z,
                        vx: 0.0,
                        vz: 0.0,
                        vy: player.vy,
                        yaw: player.yaw,
                    };
                    if lift::supported(
                        state,
                        top,
                        gates.inset_min,
                        gates.inset_max,
                        player.platform_jump_requested(),
                    ) {
                        board = true;
                    }
                }
            }
        }
        if let Some(responses) = released {
            if let Some(progress) = &mut self.foundry {
                if progress.workers.is_none() {
                    progress.workers = Some(responses);
                    debug_assert!(!workers::gates_exit(responses));
                }
            }
        }
        if board {
            if let Some(progress) = &mut self.foundry {
                if progress.lift_phase == lift::Phase::Parked {
                    progress.lift_phase = lift::Phase::Moving;
                }
            }
        }
    }
}
