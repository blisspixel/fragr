//! Authored encounter lifecycle. Bodies, weapons and collision belong to sim.
use crate::protocol::{CampaignActor, EnemyPhase};
use crate::sim::{BotIntent, GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

mod enemy;
use enemy::EnemyController;

#[derive(Default)]
enum Group {
    #[default]
    Unplaced,
    Dormant(Vec<Uuid>),
    Active {
        ids: Vec<Uuid>,
        dispatched: bool,
    },
    Complete,
}

#[derive(Default)]
pub(crate) struct Encounters {
    groups: Vec<Group>,
    enemies: Vec<(usize, EnemyController)>,
    waiting_for_party: bool,
}

impl Encounters {
    /// Called once per simulation tick, and on participant departure. Crossing
    /// a trigger repeatedly never respawns an active or completed encounter.
    pub fn update(&mut self, state: &mut GameState) {
        if !state.map.is_campaign() {
            return;
        }
        let map = state.map.clone();
        let definitions = map.encounters();
        self.groups.resize_with(definitions.len(), Group::default);
        let living: Vec<[f32; 3]> = state
            .players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Participant {}) && p.hp > 0)
            .filter(|p| crate::mission::actor_active(state.mission.as_ref(), p.id, p.campaign))
            .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
            .collect();
        if living.is_empty() {
            if !self.waiting_for_party {
                state.reset_mission();
                state.players.retain(|p| !p.is_campaign_enemy());
                self.enemies.clear();
                self.groups
                    .iter_mut()
                    .for_each(|group| *group = Group::Unplaced);
                state.pickups = state.map.pickups();
                self.waiting_for_party = true;
                tracing::info!("Campaign encounters reset; waiting for a living participant");
            }
            return;
        }
        self.waiting_for_party = false;
        state.note_mission_started();
        for (index, definition) in definitions.iter().enumerate() {
            if matches!(self.groups[index], Group::Unplaced) {
                let mut ids = Vec::with_capacity(definition.enemies.len());
                for placement in &definition.enemies {
                    let id = state.spawn_campaign_enemy(placement);
                    ids.push(id);
                    self.enemies.push((
                        index,
                        EnemyController::new(id, placement.kind, placement.feet, state.tick),
                    ));
                }
                self.groups[index] = Group::Dormant(ids);
            }
            if let Group::Active { ids, .. } = &self.groups[index] {
                if ids
                    .iter()
                    .all(|id| !state.players.iter().any(|p| p.id == *id && p.hp > 0))
                {
                    self.groups[index] = Group::Complete;
                    tracing::info!(encounter = %definition.id, "Campaign encounter cleared");
                }
            }
            let ready = matches!(
                self.groups[index],
                Group::Active {
                    dispatched: false,
                    ..
                }
            ) || matches!(self.groups[index], Group::Dormant(_))
                && definition.after.as_ref().is_none_or(|id| {
                    definitions
                        .iter()
                        .position(|e| e.id == *id)
                        .is_some_and(|at| matches!(self.groups[at], Group::Complete))
                });
            let entered = living.iter().find(|&&feet| {
                definition
                    .regions
                    .iter()
                    .any(|region| region.contains(feet))
            });
            if let Some(&feet) = entered.filter(|_| ready) {
                self.activate(index, feet, state.tick, true);
                tracing::info!(encounter = %definition.id, "Campaign encounter activated");
            }
        }
        state.players.retain(|player| !matches!(player.campaign,
            Some(CampaignActor::Union { phase: EnemyPhase::Dead, phase_ends, .. }) if state.tick >= phase_ends));
        self.enemies
            .retain(|(_, enemy)| state.players.iter().any(|p| p.id == enemy.id));
    }

    fn activate(&mut self, group: usize, alarm: [f32; 3], tick: u64, dispatch: bool) {
        match &mut self.groups[group] {
            Group::Dormant(ids) => {
                self.groups[group] = Group::Active {
                    ids: std::mem::take(ids),
                    dispatched: dispatch,
                }
            }
            Group::Active { dispatched, .. } if dispatch && !*dispatched => *dispatched = true,
            _ => return,
        }
        for (_, enemy) in self.enemies.iter_mut().filter(|(index, _)| *index == group) {
            enemy.alarm(alarm, tick);
        }
    }

    pub fn intents(&mut self, state: &mut GameState) -> Vec<(Uuid, BotIntent)> {
        let snapshot = state.snapshot();
        let mut actions = Vec::with_capacity(self.enemies.len());
        for (group, enemy) in &mut self.enemies {
            if !matches!(self.groups[*group], Group::Active { .. }) {
                continue;
            }
            let intent = enemy.intent(state, &snapshot);
            if let Some(player) = state.players.iter_mut().find(|p| p.id == enemy.id) {
                player.campaign = Some(enemy.identity());
            }
            actions.push((enemy.id, intent));
        }
        actions
    }

    pub fn hit(
        &mut self,
        id: Uuid,
        feet: [f32; 3],
        tick: u64,
        died: bool,
    ) -> Option<CampaignActor> {
        let index = self.enemies.iter().position(|(_, enemy)| enemy.id == id)?;
        let group = self.enemies[index].0;
        // A struck sentry alerts its own group without learning an unseen
        // attacker's position. Peers investigate the struck guard's location;
        // a later entry alarm can dispatch them once to that known threshold.
        self.activate(group, feet, tick, false);
        let enemy = &mut self.enemies[index].1;
        enemy.hit(tick, died);
        Some(enemy.identity())
    }
}

impl GameState {
    pub(crate) fn update_encounters(&mut self) {
        if self.map.is_campaign() {
            let mut encounters = std::mem::take(&mut self.encounters);
            encounters.update(self);
            self.encounters = encounters;
        }
    }

    pub(crate) fn enemy_intents(&mut self) -> Vec<(Uuid, BotIntent)> {
        if !self.map.has_encounters() {
            return Vec::new();
        }
        let mut encounters = std::mem::take(&mut self.encounters);
        let intents = encounters.intents(self);
        self.encounters = encounters;
        intents
    }
}
