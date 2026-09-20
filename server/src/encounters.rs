//! Authored encounter lifecycle. Bodies, weapons and collision belong to sim.
use crate::protocol::{CampaignActor, EnemyPhase};
use crate::sim::{BotIntent, GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

mod enemy;
use enemy::EnemyController;

#[derive(Default)]
enum Group {
    #[default]
    Dormant,
    Active(Vec<Uuid>),
    Complete,
}

#[derive(Default)]
pub(crate) struct Encounters {
    groups: Vec<Group>,
    enemies: Vec<EnemyController>,
    waiting_for_party: bool,
}

impl Encounters {
    /// Called once per simulation tick, and on participant departure. Crossing
    /// a trigger repeatedly never respawns an active or completed encounter.
    pub fn update(&mut self, state: &mut GameState) {
        if !state.map.has_encounters() {
            return;
        }
        let map = state.map.clone();
        let definitions = map.encounters();
        self.groups.resize_with(definitions.len(), Group::default);
        let living: Vec<[f32; 3]> = state
            .players
            .iter()
            .filter(|p| p.campaign == Some(CampaignActor::Participant {}) && p.hp > 0)
            .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
            .collect();
        if living.is_empty() {
            if !self.waiting_for_party {
                state.players.retain(|p| !p.is_campaign_enemy());
                self.enemies.clear();
                self.groups
                    .iter_mut()
                    .for_each(|group| *group = Group::Dormant);
                state.pickups = state.map.pickups();
                self.waiting_for_party = true;
                tracing::info!("Campaign encounters reset; waiting for a living participant");
            }
            return;
        }
        self.waiting_for_party = false;
        for (index, definition) in definitions.iter().enumerate() {
            if let Group::Active(ids) = &self.groups[index] {
                if ids
                    .iter()
                    .all(|id| !state.players.iter().any(|p| p.id == *id && p.hp > 0))
                {
                    self.groups[index] = Group::Complete;
                    tracing::info!(encounter = %definition.id, "Campaign encounter cleared");
                }
            }
            let ready = matches!(self.groups[index], Group::Dormant)
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
                let mut ids = Vec::with_capacity(definition.enemies.len());
                for placement in &definition.enemies {
                    let id = state.spawn_campaign_enemy(placement);
                    ids.push(id);
                    self.enemies
                        .push(EnemyController::new(id, placement.kind, feet, state.tick));
                }
                tracing::info!(encounter = %definition.id, enemies = ids.len(), "Campaign encounter activated");
                self.groups[index] = Group::Active(ids);
            }
        }
        state.players.retain(|player| !matches!(player.campaign,
            Some(CampaignActor::Union { phase: EnemyPhase::Dead, phase_ends, .. }) if state.tick >= phase_ends));
        self.enemies
            .retain(|enemy| state.players.iter().any(|p| p.id == enemy.id));
    }

    pub fn intents(&mut self, state: &mut GameState) -> Vec<(Uuid, BotIntent)> {
        let snapshot = state.snapshot();
        let mut actions = Vec::with_capacity(self.enemies.len());
        for enemy in &mut self.enemies {
            let intent = enemy.intent(state, &snapshot);
            if let Some(player) = state.players.iter_mut().find(|p| p.id == enemy.id) {
                player.campaign = Some(enemy.identity());
            }
            actions.push((enemy.id, intent));
        }
        actions
    }

    pub fn hit(&mut self, id: Uuid, tick: u64, died: bool) -> Option<CampaignActor> {
        let enemy = self.enemies.iter_mut().find(|enemy| enemy.id == id)?;
        enemy.hit(tick, died);
        Some(enemy.identity())
    }
}

impl GameState {
    pub(crate) fn update_encounters(&mut self) {
        if self.map.has_encounters() {
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
