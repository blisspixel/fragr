//! Authored encounter lifecycle. Bodies, weapons and collision belong to sim.
use crate::protocol::{CampaignActor, EnemyKind, EnemyPhase, GameEvent};
use crate::sim::{BotIntent, GameState, Player, PLAYER_FLOOR_Y};
use uuid::Uuid;

pub(crate) mod enemy;
pub(crate) use enemy::body as enemy_body;
use enemy::EnemyController;

/// Share of top speed for a body. Participants and arcade fighters keep 1.0.
pub(crate) fn gait(identity: Option<CampaignActor>) -> f32 {
    match identity {
        Some(CampaignActor::Union {
            kind: crate::protocol::EnemyKind::Crawler,
            phase: EnemyPhase::Leaping,
            ..
        }) => 1.15,
        Some(CampaignActor::Union { kind, .. }) => enemy::gait(kind),
        _ => 1.0,
    }
}

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
    pub(crate) fn is_complete(&self, index: usize) -> bool {
        matches!(self.groups.get(index), Some(Group::Complete))
    }

    pub(crate) fn is_active_enemy(&self, id: Uuid) -> bool {
        self.enemies.iter().any(|(group, enemy)| {
            enemy.id == id && matches!(self.groups.get(*group), Some(Group::Active { .. }))
        })
    }

    pub(crate) fn enemy_in_group(&self, id: Uuid, index: usize) -> bool {
        self.enemies
            .iter()
            .any(|(group, enemy)| *group == index && enemy.id == id)
    }

    fn reset(&mut self, state: &mut GameState) {
        state.clear_traveling_shots();
        state.players.retain(Player::is_participant);
        self.enemies.clear();
        self.groups
            .iter_mut()
            .for_each(|group| *group = Group::Unplaced);
        state.pickups = state.map.pickups();
        self.waiting_for_party = true;
    }
    /// Called once per simulation tick, and on participant departure. Crossing
    /// a trigger repeatedly never respawns an active or completed encounter.
    pub fn update(&mut self, state: &mut GameState) {
        if !state.map.is_campaign() {
            return;
        }
        state.update_campaign_run();
        if state.campaign_run_frozen() {
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
                self.reset(state);
                tracing::info!("Campaign encounters reset; waiting for a living participant");
            }
            return;
        }
        self.waiting_for_party = false;
        state.ensure_m03_companion();
        state.ensure_m04_companion();
        state.ensure_m05_companion();
        state.ensure_m06_companion();
        state.note_mission_started();
        for (index, definition) in definitions.iter().enumerate() {
            // M04 introduces each airborne threat in order. Do not expose a
            // future group that can be shot awake before its lesson.
            if (map.m04_objectives().is_some()
                || map.m05_objectives().is_some()
                || map.m06_objectives().is_some())
                && definition.after.as_ref().is_some_and(|id| {
                    definitions
                        .iter()
                        .position(|e| e.id == *id)
                        .is_none_or(|previous| !matches!(self.groups[previous], Group::Complete))
                })
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if matches!(self.groups[index], Group::Unplaced) {
                let mut ids = Vec::with_capacity(definition.enemies.len());
                for placement in &definition.enemies {
                    let id = state.spawn_campaign_enemy(placement);
                    ids.push(id);
                    self.enemies.push((
                        index,
                        EnemyController::new(
                            id,
                            placement.kind,
                            placement.feet,
                            placement.yaw,
                            state.tick,
                            placement.seated,
                        )
                        .with_hover(placement.hover.clone()),
                    ));
                }
                self.groups[index] = Group::Dormant(ids);
            }
            // A distant shot can wake and kill a later group before its
            // predecessor clears. Keep it active until the authored chain
            // clears so downstream encounters and mission facts stay gated.
            let predecessor_complete = definition.after.as_ref().is_none_or(|id| {
                definitions
                    .iter()
                    .position(|encounter| encounter.id == *id)
                    .is_some_and(|at| matches!(self.groups[at], Group::Complete))
            });
            if let Group::Active { ids, .. } = &self.groups[index] {
                if predecessor_complete
                    && ids
                        .iter()
                        .all(|id| !state.players.iter().any(|p| p.id == *id && p.hp > 0))
                {
                    self.groups[index] = Group::Complete;
                    tracing::info!(encounter = %definition.id, "Campaign encounter cleared");
                }
            }
            let active_undispatched_alive = match &self.groups[index] {
                Group::Active {
                    ids,
                    dispatched: false,
                } => ids.iter().any(|id| {
                    state
                        .players
                        .iter()
                        .any(|player| player.id == *id && player.hp > 0)
                }),
                _ => false,
            };
            let ready = active_undispatched_alive
                || matches!(self.groups[index], Group::Dormant(_)) && predecessor_complete;
            let entered = living.iter().find(|&&feet| {
                definition
                    .regions
                    .iter()
                    .any(|region| region.contains(feet))
            });
            if let Some(&feet) = entered.filter(|_| ready) {
                self.activate(index, feet, state.tick, true);
                if let Some(crawler) = definition
                    .enemies
                    .iter()
                    .find(|enemy| enemy.kind == EnemyKind::Crawler)
                {
                    state.events.push(GameEvent::CrawlerScrabble {
                        position: crawler.feet,
                    });
                }
                tracing::info!(encounter = %definition.id, "Campaign encounter activated");
            }
        }
        self.sync_identities(&mut state.players);
        for (_, enemy) in &mut self.enemies {
            enemy.advance_hover(state);
        }
        // A pulse keeps its combat owner until impact, even after the ordinary
        // corpse presentation ends. Never turn a slow launched attack harmless
        // merely because its emitter died.
        let emitters: Vec<Uuid> = state
            .players
            .iter()
            .filter(|player| state.has_traveling_shot(player.id))
            .map(|player| player.id)
            .collect();
        state.players.retain(|player| {
            !matches!(player.campaign,
            Some(CampaignActor::Union { phase: EnemyPhase::Dead, phase_ends, .. })
                if state.tick >= phase_ends && !emitters.contains(&player.id))
        });
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

    /// An alarm can happen after intents have run for this tick. Publish the
    /// changed posture before the next snapshot, including peers of a hit guard.
    pub(crate) fn sync_identities(&self, players: &mut [Player]) {
        for (_, enemy) in &self.enemies {
            if let Some(player) = players.iter_mut().find(|player| player.id == enemy.id) {
                player.campaign = Some(enemy.identity());
            }
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

    pub(crate) fn claim_crawler_contact(&mut self, id: Uuid) -> bool {
        self.enemies
            .iter_mut()
            .find(|(_, enemy)| enemy.id == id)
            .is_some_and(|(_, enemy)| enemy.claim_crawler_contact())
    }
    pub(crate) fn claim_notary_photo_target(&mut self, id: Uuid) -> Option<Uuid> {
        self.enemies
            .iter_mut()
            .find(|(_, enemy)| enemy.id == id)
            .and_then(|(_, enemy)| enemy.claim_notary_photo_target())
    }
}

impl GameState {
    pub(crate) fn reset_campaign_encounters(&mut self) {
        let mut encounters = std::mem::take(&mut self.encounters);
        encounters.reset(self);
        self.encounters = encounters;
    }
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
