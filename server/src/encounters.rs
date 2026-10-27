//! Authored encounter lifecycle. Bodies, weapons and collision belong to sim.
use crate::protocol::{CampaignActor, EnemyKind, EnemyPhase, GameEvent};
use crate::sim::{BotIntent, GameState, Player, PLAYER_FLOOR_Y};
use uuid::Uuid;

mod barks;
pub(crate) mod enemy;
pub(crate) use enemy::body as enemy_body;
use enemy::EnemyController;

/// Share of top speed for a body. Participants and arcade fighters keep 1.0.
pub(crate) fn gait(identity: Option<CampaignActor>) -> f32 {
    match identity {
        Some(CampaignActor::Hostile {
            kind: crate::protocol::EnemyKind::Crawler,
            phase: EnemyPhase::Leaping,
            ..
        }) => 1.15,
        Some(CampaignActor::Hostile {
            kind: EnemyKind::Enforcer,
            phase: EnemyPhase::Charging,
            ..
        }) => 1.6,
        Some(CampaignActor::Hostile { kind, .. }) => enemy::gait(kind),
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
    /// Ranged attack pacing per participant, kept for its stagger clock.
    tokens: enemy::AttackTokens,
    /// Union squad radio and Latch's callouts, on one spaced channel.
    barks: barks::Barks,
    /// Auditors that fell since the last intents, with their group.
    officers_down: Vec<(usize, Uuid)>,
}

impl Encounters {
    pub(crate) fn registered_in_group(&self, id: Uuid, group: usize) -> bool {
        self.enemies
            .iter()
            .any(|(g, enemy)| *g == group && enemy.id == id)
    }
    pub(crate) fn is_complete(&self, index: usize) -> bool {
        matches!(self.groups.get(index), Some(Group::Complete))
    }

    /// A group the party has woken: its fight has begun or is finished.
    pub(crate) fn is_awake(&self, index: usize) -> bool {
        matches!(
            self.groups.get(index),
            Some(Group::Active { .. } | Group::Complete)
        )
    }

    /// A body the reprieve sent away: it no longer works the refuge line.
    pub(crate) fn stood_down(&self, id: Uuid) -> bool {
        self.enemies
            .iter()
            .any(|(_, enemy)| enemy.id == id && enemy.stood_down().is_some())
    }

    pub(crate) fn is_active_enemy(&self, id: Uuid) -> bool {
        self.enemies.iter().any(|(group, enemy)| {
            enemy.id == id && matches!(self.groups.get(*group), Some(Group::Active { .. }))
        })
    }

    /// The participant an enemy's committed ranged tell or burst is aimed at.
    pub(crate) fn committed_target(&self, id: Uuid) -> Option<Uuid> {
        self.enemies
            .iter()
            .find(|(_, enemy)| enemy.id == id)
            .and_then(|(_, enemy)| enemy.holds_token())
    }

    pub(crate) fn enemy_in_group(&self, id: Uuid, index: usize) -> bool {
        self.enemies
            .iter()
            .any(|(group, enemy)| *group == index && enemy.id == id)
    }

    fn reset(&mut self, state: &mut GameState) {
        state.clear_traveling_shots();
        state.players.retain(Player::is_participant);
        self.barks.reset();
        self.officers_down.clear();
        self.enemies.clear();
        self.groups
            .iter_mut()
            .for_each(|group| *group = Group::Unplaced);
        state.pickups = state.map.pickups();
        state.reset_vehicles();
        state.walker = state
            .map
            .walker_geometry()
            .as_ref()
            .map(crate::sim::walker::Walker::new);
        // Standalone foundry maps have no MissionRun to reset their moving
        // deck or resolved gate facts when the last participant dies or leaves.
        state.foundry = state
            .map
            .m13_gates()
            .map(crate::mission::m13::Progress::new);
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
        state.ensure_m08_companion();
        state.ensure_m07_companion();
        state.ensure_m09_companion();
        state.ensure_m10_companion();
        state.note_mission_started();
        for (index, definition) in definitions.iter().enumerate() {
            // M04 introduces each airborne threat in order. Do not expose a
            // future group that can be shot awake before its lesson.
            if (map.m04_objectives().is_some()
                || map.m05_objectives().is_some()
                || map.m06_objectives().is_some()
                || map.m07_objectives().is_some()
                || map.m08_objectives().is_some()
                || map.m09_objectives().is_some()
                || map.m10_objectives().is_some()
                || map.m11_objectives().is_some()
                || map.m12_objectives().is_some()
                || map.m13_geometry().is_some()
                || map.m14_geometry().is_some()
                || map.m15_geometry().is_some()
                || map.m16_geometry().is_some()
                || map.m17_geometry().is_some()
                || map.m18_geometry().is_some()
                || map.m20_objectives().is_some()
                || map.has_authored_vehicles())
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
            if map.m09_objectives().is_some()
                && !state.m09_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m14_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m15_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m16_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m17_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m18_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m19_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if !state.m20_encounter_available(index)
                && matches!(self.groups[index], Group::Unplaced)
            {
                continue;
            }
            if matches!(self.groups[index], Group::Unplaced) {
                let mut ids = Vec::with_capacity(definition.enemies.len());
                for (member, placement) in definition.enemies.iter().enumerate() {
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
                        .on_post()
                        .with_hover(placement.hover.clone())
                        .with_control(placement.control)
                        .with_spine_march(
                            map.m11_objectives()
                                .filter(|_| index == 0)
                                .map(|p| p.spine_patrol.clone()),
                            member,
                        ),
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
            // The authored region stays the alarm. Each guard then needs its
            // own sighting before it attacks (`enemy/awareness.rs`).
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
        self.retire_stood_down(state);
        for (_, enemy) in &mut self.enemies {
            enemy.advance_hover(state);
        }
        // A pulse keeps its combat owner until impact, even after the ordinary
        // corpse presentation ends. Never turn a slow launched attack harmless
        // merely because its emitter died.
        let emitters: Vec<Uuid> = state
            .players
            .iter()
            .filter(|player| {
                state.has_traveling_shot(player.id) || state.has_assessor_canister(player.id)
            })
            .map(|player| player.id)
            .collect();
        state.players.retain(|player| {
            !matches!(player.campaign,
            Some(CampaignActor::Hostile { phase: EnemyPhase::Dead, phase_ends, .. })
                if state.tick >= phase_ends && !emitters.contains(&player.id))
        });
        self.enemies
            .retain(|(_, enemy)| state.players.iter().any(|p| p.id == enemy.id));
    }

    /// What each awake group's guards know of their squad this tick: an
    /// anchor in a tell or burst and the first living heavy in authored order.
    fn squads(&self, state: &GameState) -> Vec<(usize, enemy::squad::Squad)> {
        let feet_of = |id: Uuid| {
            state
                .players
                .iter()
                .find(|p| p.id == id && p.hp > 0)
                .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
        };
        let mut squads: Vec<(usize, enemy::squad::Squad)> = Vec::new();
        for (group, enemy) in &self.enemies {
            if !matches!(self.groups.get(*group), Some(Group::Active { .. })) {
                continue;
            }
            let Some(feet) = feet_of(enemy.id) else {
                continue;
            };
            let at = match squads.iter().position(|(g, _)| g == group) {
                Some(at) => at,
                None => {
                    squads.push((*group, Default::default()));
                    squads.len() - 1
                }
            };
            let squad = &mut squads[at].1;
            if enemy::squad::role(enemy.kind()) == enemy::squad::SquadRole::Anchor
                && squad.anchor.is_none()
            {
                if let Some(target) = enemy.holds_token() {
                    squad.anchor = Some((target, feet));
                }
            }
            if matches!(enemy.kind(), EnemyKind::HeavySweeper | EnemyKind::Enforcer)
                && squad.heavy.is_none()
            {
                squad.heavy = Some(feet);
            }
        }
        squads
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
            if !dispatch {
                enemy.end_spine_march();
            }
            enemy.alarm(alarm, tick);
            // A shot that struck one of them is gunfire in the room: everyone
            // is in the fight at once, as before guards needed a sighting.
            // Only the silent entry alarm leaves them looking.
            if !dispatch {
                enemy.wake();
            }
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

    /// Live Surveyor discs, for the snapshot.
    pub(crate) fn surveyor_marks(&self) -> Vec<crate::protocol::SurveyorMarkState> {
        self.enemies
            .iter()
            .filter_map(|(_, enemy)| {
                enemy.mark().map(|mark| crate::protocol::SurveyorMarkState {
                    id: enemy.id,
                    center: mark.center,
                    radius: enemy::surveyor::MARK_RADIUS,
                    since: mark.since,
                    until: mark.until,
                    tracking: mark.tracking,
                })
            })
            .collect()
    }

    /// Whether a placed guard is in the fight rather than on post or alarmed.
    #[cfg(test)]
    pub(crate) fn aware(&self, id: Uuid) -> bool {
        self.enemies
            .iter()
            .any(|(_, enemy)| enemy.id == id && enemy.aware())
    }

    #[cfg(test)]
    pub(crate) fn converging(&self, id: Uuid) -> bool {
        self.enemies
            .iter()
            .any(|(_, enemy)| enemy.id == id && enemy.is_converging())
    }

    /// Whether a group's Surveyors have finished teaching alone: each has
    /// cast a disc that has since ended, or is down.
    pub(crate) fn surveyor_lesson_over(&self, state: &GameState, group: usize) -> bool {
        match self.groups.get(group) {
            Some(Group::Complete) => return true,
            Some(Group::Active { .. }) => {}
            _ => return false,
        }
        self.enemies
            .iter()
            .filter(|(index, enemy)| *index == group && enemy.kind() == EnemyKind::Surveyor)
            .all(|(_, enemy)| {
                enemy.lesson_given() || !state.players.iter().any(|p| p.id == enemy.id && p.hp > 0)
            })
    }

    /// Discs broken since the last call: ended by broken sight or a hit
    /// before any converging machine stood inside them.
    pub(crate) fn drain_marks_broken(&mut self) -> u32 {
        self.enemies
            .iter_mut()
            .map(|(_, enemy)| enemy.take_marks_broken())
            .sum()
    }

    /// Convergence: every walking Inheritance machine of an active group near
    /// a live disc is alarmed to its current centre. A machine still
    /// answering to the Union never reads a restoration mark. A machine inside
    /// the disc records the arrival, after which ending the disc no longer
    /// breaks the mark.
    fn advance_marks(&mut self, state: &GameState) {
        let tick = state.tick.saturating_add(1);
        let marks: Vec<(usize, enemy::surveyor::Mark)> = self
            .enemies
            .iter()
            .enumerate()
            .filter_map(|(index, (_, enemy))| enemy.mark().map(|mark| (index, mark)))
            .collect();
        for (owner, mark) in marks {
            let mut arrived = mark.arrived;
            for index in 0..self.enemies.len() {
                let (group, ref machine) = self.enemies[index];
                if index == owner
                    || machine.control() == crate::protocol::ControlDomain::Union
                    || enemy::gait(machine.kind()) <= 0.0
                    || machine.stood_down().is_some()
                    || !matches!(self.groups.get(group), Some(Group::Active { .. }))
                {
                    continue;
                }
                let Some(body) = state
                    .players
                    .iter()
                    .find(|p| p.id == machine.id && p.hp > 0)
                else {
                    continue;
                };
                let feet = [body.x, body.y - PLAYER_FLOOR_Y, body.z];
                let distance = (feet[0] - mark.center[0]).hypot(feet[2] - mark.center[2]);
                if distance > enemy::surveyor::CONVERGE_RADIUS {
                    continue;
                }
                if distance <= enemy::surveyor::ARRIVAL_RADIUS
                    && (feet[1] - mark.center[1]).abs() <= 2.0
                {
                    arrived = true;
                } else if (tick - mark.since).is_multiple_of(10) {
                    self.enemies[index]
                        .1
                        .converge(mark.center, mark.until, tick);
                }
            }
            if arrived && !mark.arrived {
                self.enemies[owner].1.note_mark_arrival();
                tracing::info!(surveyor = %self.enemies[owner].1.id, "Surveyor mark reached by a machine");
            }
        }
    }

    /// Send a group's walking machines to points on the refuge line, spread
    /// deterministically by member so they arrive along the barricade.
    pub(crate) fn march_group(&mut self, group: usize, points: &[[f32; 3]], tick: u64) {
        if points.is_empty() {
            return;
        }
        for (member, (_, enemy)) in self
            .enemies
            .iter_mut()
            .filter(|(index, enemy)| {
                *index == group && enemy::gait(enemy.kind()) > 0.0 && enemy.stood_down().is_none()
            })
            .enumerate()
        {
            enemy.march(points[(group * 3 + member) % points.len()], tick);
        }
    }

    /// Re-issue the march to idle machines that stopped short of the line.
    pub(crate) fn march_idle(&mut self, state: &GameState, groups: &[usize], tick: u64) {
        for (group, enemy) in &mut self.enemies {
            if !groups.contains(group)
                || enemy::gait(enemy.kind()) <= 0.0
                || enemy.stood_down().is_some()
                || enemy.phase() != EnemyPhase::Idle
                || !matches!(self.groups.get(*group), Some(Group::Active { .. }))
            {
                continue;
            }
            let point = enemy.marching_to();
            if state.players.iter().any(|p| {
                p.id == enemy.id && p.hp > 0 && (p.x - point[0]).hypot(p.z - point[2]) > 1.5
            }) {
                enemy.march(point, tick);
            }
        }
    }

    /// The reprieve: every Union body stops attacking and walks to the
    /// nearer exit. Hovering bodies hold still until they are retired.
    pub(crate) fn stand_down(&mut self, state: &mut GameState, exits: &[[f32; 3]], tick: u64) {
        for (_, enemy) in &mut self.enemies {
            let Some(body) = state.players.iter().find(|p| p.id == enemy.id) else {
                continue;
            };
            let exit = exits
                .iter()
                .copied()
                .min_by(|a, b| {
                    (a[0] - body.x)
                        .hypot(a[2] - body.z)
                        .total_cmp(&(b[0] - body.x).hypot(b[2] - body.z))
                })
                .unwrap_or([body.x, body.y - PLAYER_FLOOR_Y, body.z]);
            enemy.stand_down(exit, tick);
        }
        self.sync_identities(&mut state.players);
    }

    /// One group's machines stand down toward `exit` as they appear. The
    /// reprieve's work front uses it: it never fights and walks on.
    pub(crate) fn stand_down_group(
        &mut self,
        state: &mut GameState,
        group: usize,
        exit: [f32; 3],
        tick: u64,
    ) {
        for (_, enemy) in self
            .enemies
            .iter_mut()
            .filter(|(index, enemy)| *index == group && enemy.stood_down().is_none())
        {
            enemy.stand_down(exit, tick);
        }
        self.sync_identities(&mut state.players);
    }

    /// Stood-down machines leave the district: a walker at its exit, a
    /// hovering body after a short hold, anything after a bounded wait.
    fn retire_stood_down(&mut self, state: &mut GameState) {
        let tick = state.tick;
        let leaving: Vec<Uuid> = self
            .enemies
            .iter()
            .filter_map(|(_, enemy)| {
                let (since, exit) = enemy.stood_down()?;
                let body = state.players.iter().find(|p| p.id == enemy.id)?;
                let elapsed = tick.saturating_sub(since);
                let walker = enemy::gait(enemy.kind()) > 0.0;
                let arrived = (body.x - exit[0]).hypot(body.z - exit[2]) <= 2.0;
                (body.hp > 0
                    && (walker && arrived || !walker && elapsed >= 100 || elapsed >= 1_600))
                    .then_some(enemy.id)
            })
            .collect();
        if leaving.is_empty() {
            return;
        }
        state.players.retain(|p| !leaving.contains(&p.id));
        self.enemies
            .retain(|(_, enemy)| !leaving.contains(&enemy.id));
    }

    /// Living Auditors' repair budgets and current channels, for the snapshot.
    pub(crate) fn auditor_states(&self) -> Vec<crate::protocol::AuditorState> {
        self.enemies
            .iter()
            .filter(|(_, enemy)| {
                enemy.kind() == EnemyKind::Auditor && enemy.phase() != EnemyPhase::Dead
            })
            .map(|(_, enemy)| crate::protocol::AuditorState {
                id: enemy.id,
                repairs_left: enemy.repairs_left(),
                channel_target: enemy.channel_target(),
            })
            .collect()
    }

    /// Marked Paver strips for the snapshot, while prepared or worked.
    pub(crate) fn paver_strips(&self) -> Vec<crate::protocol::PaverStripState> {
        self.enemies
            .iter()
            .filter_map(|(_, enemy)| {
                let strip = enemy.paver_strip()?;
                Some(crate::protocol::PaverStripState {
                    owner_id: enemy.id,
                    origin: strip.origin,
                    yaw: strip.yaw,
                    length: strip.length,
                    half_width: strip.half_width,
                    working: enemy.phase() == EnemyPhase::Firing,
                    phase_started: enemy.phase_started(),
                    phase_ends: enemy.phase_ends(),
                })
            })
            .collect()
    }

    /// Strips whose work pulse lands on this tick, with their owner.
    pub(crate) fn paver_pulses(&self, tick: u64) -> Vec<(Uuid, enemy::paver::Strip)> {
        self.enemies
            .iter()
            .filter_map(|(_, enemy)| enemy.paver_pulse(tick).map(|strip| (enemy.id, strip)))
            .collect()
    }

    /// Every preparation put out by damage since the encounters were placed.
    pub(crate) fn paver_interruptions(&self) -> u32 {
        self.enemies
            .iter()
            .map(|(_, enemy)| enemy.paver_interruptions())
            .sum()
    }

    /// Auditor repair channels, before this tick's intents: snap, complete or
    /// start a channel, then hold every reached disabled body until it ends.
    fn advance_repairs(&mut self, state: &mut GameState) {
        if !self
            .enemies
            .iter()
            .any(|(_, enemy)| enemy.kind() == EnemyKind::Auditor)
        {
            return;
        }
        let tick = state.tick.saturating_add(1);
        let duration = enemy::channel_ticks(state.campaign_rules().difficulty);
        let arena = state.current_arena().into_owned();
        for index in 0..self.enemies.len() {
            let (group, ref auditor) = self.enemies[index];
            if auditor.kind() != EnemyKind::Auditor
                || !matches!(self.groups.get(group), Some(Group::Active { .. }))
            {
                continue;
            }
            let Some(me) = state
                .players
                .iter()
                .find(|p| p.id == auditor.id && p.hp > 0)
            else {
                continue;
            };
            let eye = [
                me.x,
                me.y - PLAYER_FLOOR_Y + crate::combat::stance_eye(me.campaign, me.ducking),
                me.z,
            ];
            let reaches = |body: &Player| {
                let point = [body.x, body.y - PLAYER_FLOOR_Y + 0.4, body.z];
                body.hp <= 0
                    && (point[0] - eye[0]).hypot(point[2] - eye[2]) <= enemy::REPAIR_RANGE
                    && crate::combat::line_of_sight(eye, point, &arena.solids)
            };
            if auditor.phase() == EnemyPhase::Channeling {
                let body = auditor
                    .channel_target()
                    .and_then(|id| state.players.iter().find(|p| p.id == id))
                    .filter(|body| reaches(body));
                let Some(body) = body else {
                    self.enemies[index].1.snap_channel(tick);
                    continue;
                };
                if tick < auditor.phase_ends() {
                    continue;
                }
                // A living body standing on the disabled one blocks the repair.
                let occupied = state.players.iter().any(|p| {
                    p.id != body.id
                        && p.hp > 0
                        && (p.x - body.x).hypot(p.z - body.z) < crate::movement::RADIUS * 2.0
                        && (p.y - body.y).abs() < crate::movement::BODY_HEIGHT
                });
                let body_id = body.id;
                let Some(reached) = self
                    .enemies
                    .iter()
                    .position(|(_, enemy)| enemy.id == body_id)
                else {
                    self.enemies[index].1.snap_channel(tick);
                    continue;
                };
                if occupied {
                    self.enemies[index].1.snap_channel(tick);
                    continue;
                }
                let hp = enemy::body(self.enemies[reached].1.kind()).0 / 2;
                self.enemies[reached].1.repaired(tick, hp);
                self.enemies[index].1.complete_channel(tick);
                if let Some(player) = state.players.iter_mut().find(|p| p.id == body_id) {
                    player.hp = hp;
                    player.vy = 0.0;
                    player.respawn_timer = None;
                    player.clear_input();
                    player.inventory.release_trigger();
                }
                tracing::info!(auditor = %self.enemies[index].1.id, body = %body_id, "Auditor repair completed");
                continue;
            }
            if !auditor.can_channel(tick) {
                continue;
            }
            let taken: Vec<Uuid> = self
                .enemies
                .iter()
                .filter_map(|(_, enemy)| enemy.channel_target())
                .collect();
            let candidate = self
                .enemies
                .iter()
                .filter(|(other, enemy)| {
                    *other == group
                        && enemy.phase() == EnemyPhase::Dead
                        && enemy::repairable(enemy.kind())
                        && !taken.contains(&enemy.id)
                        // A held body never outlasts its disabled presentation
                        // bound: the whole channel must finish inside it.
                        && tick + duration < enemy.phase_started() + enemy::DISABLED_HOLD_LIMIT
                })
                .filter_map(|(_, enemy)| state.players.iter().find(|p| p.id == enemy.id))
                .filter(|body| reaches(body))
                .min_by(|a, b| {
                    (a.x - eye[0])
                        .hypot(a.z - eye[2])
                        .total_cmp(&(b.x - eye[0]).hypot(b.z - eye[2]))
                })
                .map(|body| body.id);
            if let Some(body) = candidate {
                self.enemies[index].1.start_channel(body, tick, duration);
                tracing::info!(auditor = %self.enemies[index].1.id, %body, "Auditor repair channel started");
            }
        }
        let holds: Vec<(Uuid, u64)> = self
            .enemies
            .iter()
            .filter_map(|(_, enemy)| {
                enemy
                    .channel_target()
                    .map(|body| (body, enemy.phase_ends().saturating_add(1)))
            })
            .collect();
        for (_, enemy) in &mut self.enemies {
            let held = holds
                .iter()
                .filter(|(body, _)| *body == enemy.id)
                .map(|(_, until)| *until)
                .max();
            enemy.hold_disabled(held);
        }
    }

    pub fn intents(&mut self, state: &mut GameState) -> Vec<(Uuid, BotIntent)> {
        self.advance_repairs(state);
        self.advance_marks(state);
        let snapshot = state.snapshot();
        let mut actions = Vec::with_capacity(self.enemies.len());
        let squads = self.squads(state);
        for (group, enemy) in &mut self.enemies {
            let squad = squads
                .iter()
                .find(|(g, _)| g == group)
                .map(|(_, squad)| *squad)
                .unwrap_or_default();
            enemy.set_squad(squad);
        }
        // What changed this tick, for chatter once every guard has moved.
        let mut said: Vec<(usize, Uuid, crate::protocol::EnemyBarkKind)> = Vec::new();
        let mut raised: Vec<(Uuid, EnemyKind, Uuid)> = Vec::new();
        let mut channels: Vec<Uuid> = Vec::new();
        // Ranged tokens per participant: attacks already committed hold theirs.
        let tokens = &mut self.tokens;
        tokens.begin_tick();
        for (group, enemy) in &self.enemies {
            if matches!(self.groups[*group], Group::Active { .. }) {
                if let Some(target) = enemy.holds_token() {
                    tokens.take(target, enemy.phase_started());
                }
            }
        }
        for (group, enemy) in &mut self.enemies {
            let Group::Active { ids, .. } = &self.groups[*group] else {
                continue;
            };
            enemy.last_standing = ids
                .iter()
                .filter(|id| {
                    snapshot
                        .players
                        .iter()
                        .any(|player| player.id == **id && player.hp > 0)
                })
                .count()
                == 1;
            let held = enemy.holds_token();
            let was = (enemy.phase(), enemy.phase_started());
            let intent = enemy.paced_intent(state, &snapshot, tokens);
            tokens.settle(held, enemy.holds_token(), state.tick);
            if let Some(kind) = enemy.take_bark() {
                said.push((*group, enemy.id, kind));
            }
            if (enemy.phase(), enemy.phase_started()) != was {
                if let (EnemyPhase::Windup, Some(target)) = (enemy.phase(), enemy.holds_token()) {
                    raised.push((enemy.id, enemy.kind(), target));
                }
            }
            if let Some(player) = state.players.iter_mut().find(|p| p.id == enemy.id) {
                player.campaign = Some(enemy.identity());
            }
            actions.push((enemy.id, intent));
        }
        for (group, enemy) in &self.enemies {
            if enemy.kind() == EnemyKind::Auditor
                && enemy.phase() == EnemyPhase::Channeling
                && enemy.phase_started() == state.tick.saturating_add(1)
                && matches!(self.groups.get(*group), Some(Group::Active { .. }))
            {
                channels.push(enemy.id);
            }
        }
        for (group, id) in std::mem::take(&mut self.officers_down) {
            said.push((group, id, crate::protocol::EnemyBarkKind::OfficerDown));
        }
        self.chatter(state, &said, &raised, &channels);
        actions
    }

    /// Offer this tick's chatter to the spaced channel: the squad's own lines
    /// first, then Latch's callouts.
    fn chatter(
        &mut self,
        state: &mut GameState,
        said: &[(usize, Uuid, crate::protocol::EnemyBarkKind)],
        raised: &[(Uuid, EnemyKind, Uuid)],
        channels: &[Uuid],
    ) {
        use crate::protocol::CompanionBarkKind;
        for &(group, id, bark) in said {
            // A guard that cannot speak passes the line to one of its group
            // that can.
            if let Some((speaker, speaker_kind, control)) = self.speaker(state, group, id) {
                if self
                    .barks
                    .enemy(state, bark, speaker, speaker_kind, control)
                {
                    break;
                }
            }
        }
        if !channels.is_empty() {
            self.barks.companion(
                state,
                CompanionBarkKind::PriorityTarget,
                Some(EnemyKind::Auditor),
            );
        }
        for &(id, kind, target) in raised {
            if kind == EnemyKind::Turret {
                self.barks.companion(
                    state,
                    CompanionBarkKind::PriorityTarget,
                    Some(EnemyKind::Turret),
                );
            }
            let from = state
                .players
                .iter()
                .find(|p| p.id == id)
                .map(|p| [p.x, p.y, p.z]);
            let flanked = from.is_some_and(|from| {
                state
                    .players
                    .iter()
                    .find(|p| p.id == target)
                    .is_some_and(|participant| barks::behind(participant, from))
            });
            if flanked {
                self.barks
                    .companion(state, CompanionBarkKind::FlankWarning, None);
            }
        }
        self.barks.watch_health(state);
    }

    /// The living body that voices a line for `id`: itself when it speaks,
    /// otherwise the nearest speaking member of its group.
    fn speaker(
        &self,
        state: &GameState,
        group: usize,
        id: Uuid,
    ) -> Option<(Uuid, EnemyKind, crate::protocol::ControlDomain)> {
        let origin = state.players.iter().find(|p| p.id == id)?;
        self.enemies
            .iter()
            .filter(|(g, enemy)| {
                *g == group && barks::register(enemy.kind(), enemy.control()).is_some()
            })
            .filter_map(|(_, enemy)| {
                state
                    .players
                    .iter()
                    .find(|p| p.id == enemy.id && p.hp > 0)
                    .map(|p| (enemy, (p.x - origin.x).hypot(p.z - origin.z)))
            })
            .min_by(|a, b| {
                (a.0.id != id)
                    .cmp(&(b.0.id != id))
                    .then(a.1.total_cmp(&b.1))
            })
            .map(|(enemy, _)| (enemy.id, enemy.kind(), enemy.control()))
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
        if died && enemy.kind() == EnemyKind::Auditor {
            self.officers_down.push((group, id));
        }
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
    pub(crate) fn assessor_target(&self, id: Uuid) -> Option<[f32; 3]> {
        self.enemies
            .iter()
            .find(|(_, enemy)| enemy.id == id)
            .and_then(|(_, enemy)| enemy.canister_target())
    }
    pub(crate) fn spend_assessor_canister(&mut self, id: Uuid) -> bool {
        self.enemies
            .iter_mut()
            .find(|(_, enemy)| enemy.id == id)
            .is_some_and(|(_, enemy)| enemy.spend_canister())
    }
    pub(crate) fn claim_enforcer_contact(&mut self, id: Uuid) -> bool {
        self.enemies
            .iter_mut()
            .find(|(_, enemy)| enemy.id == id)
            .is_some_and(|(_, enemy)| enemy.claim_enforcer_contact())
    }
    pub(crate) fn enforcer_fell(&self, id: Uuid, feet: [f32; 3]) -> bool {
        self.enemies
            .iter()
            .find(|(_, enemy)| enemy.id == id)
            .is_some_and(|(_, enemy)| enemy.enforcer_fell(feet))
    }
}

impl GameState {
    /// The reprieve's stand-down over the current encounter roster.
    pub(crate) fn stand_down_encounters(&mut self, exits: &[[f32; 3]]) {
        let mut encounters = std::mem::take(&mut self.encounters);
        let tick = self.tick;
        encounters.stand_down(self, exits, tick);
        self.encounters = encounters;
    }

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
            // Shared blast damage and mission receipts must see the registered
            // controllers. Resolving while `encounters` is taken loses both
            // same-tick death phases and the M12 squad membership evidence.
            let wrecks: Vec<Uuid> = self
                .encounters
                .enemies
                .iter_mut()
                .filter_map(|(_, enemy)| enemy.take_wreck().then_some(enemy.id))
                .collect();
            for owner in wrecks {
                self.resolve_assessor_wreck(owner);
            }
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
