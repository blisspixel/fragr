//! Local Exception: the Surveyor lesson over the sluices, the waterworks
//! crew's crossing, the pier hold against converging pressure and the
//! reprieve. The level's one door, the refuge gate, opens when Latch walks
//! back across the pier.
use super::*;
use crate::maps::m20_authored::{Prepared, CROSSING_GROUP, FOLLOW_GROUP, SLUICE_GROUP};
use crate::movement::MoveState;
use crate::protocol::{
    CampaignDifficulty, EnemyKind, InteractionKind, InteractionPrompt, M20ChallengeState,
    M20CrewPhase, M20CrewState, M20ObjectiveState, M20Refuge, MissionMember,
    MissionObjectiveAction, MissionPhase, M20_CREW, M20_OBJECTIVE_IDS, M20_REFUGE_BASE,
    M20_REFUGE_INTEGRITY,
};
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;

#[cfg(test)]
mod route_tests;
#[cfg(test)]
mod tests;

/// Crew and Latch walk deliberately; neither is a race.
const CREW_SPEED: f32 = 1.5;
const LATCH_SPEED: f32 = 1.8;
/// Crew leave the pump hall one after another.
const CREW_STAGGER: u64 = 24;
/// The gate opens when Latch reaches it, or after this many ticks regardless.
pub(crate) const GATE_TIMEOUT: u64 = 600;
/// No pressure group appears with a participant this close to its ingress.
const INGRESS_CLEARANCE: f32 = 20.0;
/// A group in sight of a participant waits at most this long, then walks in.
const INGRESS_SIGHT_DEFERRAL: u64 = 300;
/// Re-issue a stalled march this often.
const MARCH_REFRESH: u64 = 40;

/// Simultaneous walking machines the pressure may field. A deferred group waits.
pub(crate) fn population_cap(difficulty: CampaignDifficulty) -> usize {
    match difficulty {
        CampaignDifficulty::Assisted => 4,
        CampaignDifficulty::Standard => 6,
        CampaignDifficulty::Severe => 8,
    }
}

/// Ticks between barricade wear by machines standing on the line.
pub(crate) fn wear_interval(difficulty: CampaignDifficulty) -> u64 {
    match difficulty {
        CampaignDifficulty::Assisted => 30,
        CampaignDifficulty::Standard => 20,
        CampaignDifficulty::Severe => 16,
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct CrewProgress {
    pub(crate) phase: M20CrewPhase,
    pub(crate) feet: [f32; 3],
    pub(crate) next: usize,
    pub(crate) depart_at: u64,
    pub(crate) stalled: u32,
}

pub(crate) struct M20Progress {
    pub(super) index: usize,
    pub(super) challenges: M20ChallengeState,
    pub(super) crew: Vec<CrewProgress>,
    pub(super) pier_reached_at: Option<u64>,
    pub(super) refuge_integrity: u16,
    pub(super) display_lit: bool,
    pub(super) reprieve_at: Option<u64>,
    pub(super) latch: Option<([f32; 3], usize)>,
    pub(super) latch_arrived: bool,
    pub(super) gate_open: bool,
    /// The sluice Surveyor has taught alone: its first disc ended, or it fell.
    pub(super) lesson_over: bool,
    marched: Vec<bool>,
    released: Vec<bool>,
}

impl M20Progress {
    pub(crate) fn new(prepared: &Prepared) -> Self {
        Self {
            index: 0,
            challenges: M20ChallengeState {
                refuge_held: true,
                ..M20ChallengeState::default()
            },
            crew: prepared
                .crew
                .iter()
                .map(|member| CrewProgress {
                    phase: M20CrewPhase::Working,
                    feet: member.start,
                    next: 0,
                    depart_at: 0,
                    stalled: 0,
                })
                .collect(),
            pier_reached_at: None,
            refuge_integrity: M20_REFUGE_INTEGRITY,
            display_lit: false,
            reprieve_at: None,
            latch: None,
            latch_arrived: false,
            gate_open: false,
            lesson_over: false,
            marched: vec![false; prepared.pressure.len()],
            released: vec![false; prepared.crates.len()],
        }
    }

    /// The hold clock: (start, turn, reprieve) ticks, once the quay is reached.
    fn clock(&self, prepared: &Prepared) -> Option<(u64, u64, u64)> {
        self.pier_reached_at.map(|at| prepared.geometry.clock(at))
    }
}

/// The refuge's own four hundred, plus every authored rescue the run carried
/// into this level. Flavor for the harbour display and the faces on the
/// pier; never a gate on survival or on the epilogue.
fn refuge_for(solo: Option<&recovery::SoloRun>) -> M20Refuge {
    let Some(solo) = solo else {
        return M20Refuge::alone();
    };
    let mut freed: u32 = 0;
    let count = |items: usize| u32::try_from(items).unwrap_or(u32::MAX);
    freed = freed.saturating_add(count(solo.carried_recall_cars.len()).saturating_mul(2));
    freed = freed.saturating_add(count(solo.carried_patients.len()));
    freed = freed.saturating_add(count(solo.carried_released_workers.len()));
    if solo.carried_prisoner_route_marked {
        freed = freed.saturating_add(6);
    }
    let mut orrin = false;
    if let Some(crate::protocol::M08Outcome {
        custody_released,
        recovered_mind_secured,
        ..
    }) = &solo.carried_archive
    {
        if *custody_released {
            freed = freed.saturating_add(5);
        }
        orrin = *recovered_mind_secured;
        if orrin {
            freed = freed.saturating_add(1);
        }
    }
    if let Some(run_file::M09Outcome { released_crew, .. }) = &solo.carried_berth {
        freed = freed.saturating_add(count(released_crew.len()));
    }
    let sorrel = solo
        .carried_tender
        .as_ref()
        .is_some_and(|tender| tender.transfer_released);
    if sorrel {
        freed = freed.saturating_add(1);
    }
    if solo
        .carried_habitat
        .as_ref()
        .is_some_and(|habitat| habitat.workers_released)
    {
        freed = freed.saturating_add(6);
    }
    if let Some(foundry) = &solo.carried_foundry {
        freed = freed.saturating_add(count(
            foundry.workers_arrived.iter().filter(|a| **a).count(),
        ));
    }
    if let Some(stadium) = &solo.carried_stadium {
        freed = freed.saturating_add(count(stadium.armed_entrants.len()));
    }
    if solo
        .carried_avenue
        .as_ref()
        .is_some_and(|avenue| avenue.bus_freed)
    {
        freed = freed.saturating_add(12);
    }
    M20Refuge {
        persons: M20_REFUGE_BASE + freed.min(crate::protocol::M20_MAX_FREED),
        edda: !solo.carried_patients.is_empty(),
        splice: solo
            .carried_released_workers
            .iter()
            .any(|id| id == "splice"),
        orrin,
        sorrel,
    }
}

/// One walking step along a fixed route. A walker that has waited this long
/// behind a living blocker slides around it instead of waiting forever.
const STALL_SLIDE: u32 = 40;

fn step_toward(
    state: &GameState,
    key: &str,
    feet: [f32; 3],
    to: [f32; 3],
    speed: f32,
    stalled: u32,
) -> [f32; 3] {
    let dx = to[0] - feet[0];
    let dz = to[2] - feet[2];
    let distance = dx.hypot(dz);
    if distance <= 0.04 {
        return [to[0], feet[1], to[2]];
    }
    let direction = [dx / distance, dz / distance];
    let from = MoveState {
        x: feet[0],
        y: feet[1],
        z: feet[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let speed = (distance / 0.05).min(speed);
    let arena = state.current_arena();
    let proposed = crate::movement::integrate(
        MoveState {
            vx: direction[0] * speed,
            vz: direction[1] * speed,
            ..from
        },
        false,
        0.05,
        &arena,
    );
    let mut contacts = state.contact_bodies();
    contacts.retain(|body| body.key != key);
    let moved = if stalled >= STALL_SLIDE {
        crate::sim::contact::move_body(
            key,
            from,
            proposed,
            crate::movement::BODY_HEIGHT,
            0.05,
            &arena,
            &contacts,
        )
    } else {
        crate::mission::contact::move_on_route(
            key, from, proposed, direction, 0.05, &arena, &contacts,
        )
    };
    [moved.x, moved.y, moved.z]
}

impl GameState {
    fn m20_prepared(&self) -> Option<&Prepared> {
        self.mission.as_ref()?.initial_map.m20_objectives()
    }

    /// The two lessons are ordinary ordered groups. Every later group is
    /// pressure: eligible on its hidden schedule inside the hold, deferred
    /// while the population is full or a participant stands at its ingress.
    pub(crate) fn m20_encounter_available(&self, index: usize) -> bool {
        let Some(run) = self.mission.as_ref() else {
            return true;
        };
        let Some(p) = run.m20.as_ref() else {
            return true;
        };
        if index == SLUICE_GROUP || index == CROSSING_GROUP {
            return true;
        }
        // The Surveyor teaches alone first. One machine joins once its first
        // disc ends, or once it is down, while the sluice is still the lesson.
        if index == FOLLOW_GROUP {
            return p.lesson_over && p.index == 0;
        }
        let Some(prepared) = run.initial_map.m20_objectives() else {
            return false;
        };
        // The work front appears only after the reprieve, already standing
        // down: it walks past the refuge and on to the next district.
        if index == prepared.passing.0 {
            return p.reprieve_at.is_some();
        }
        let Some(slot) = prepared.pressure.iter().find(|s| s.group == index) else {
            return false;
        };
        let Some((start, _, reprieve)) = p.clock(prepared) else {
            return false;
        };
        let due = start.saturating_add(slot.at);
        if p.reprieve_at.is_some() || self.tick < due || self.tick >= reprieve {
            return false;
        }
        let Some(definition) = self.map.encounters().get(index) else {
            return false;
        };
        // The cap counts walking machines only. Spotters on their towers and
        // hovering units over the water hold their posts, so counting them
        // would let one living Surveyor starve an easy tier of pressure.
        let walking = |kind: EnemyKind| crate::encounters::enemy::gait(kind) > 0.0;
        let living = self
            .players
            .iter()
            .filter(|player| player.hp > 0)
            .filter(|player| {
                matches!(player.campaign, Some(crate::protocol::CampaignActor::Hostile { kind, .. }) if walking(kind))
            })
            .count();
        let arriving = definition
            .enemies
            .iter()
            .filter(|enemy| walking(enemy.kind))
            .count();
        if living + arriving > population_cap(run.rules.difficulty) {
            return false;
        }
        let arena = self.current_arena();
        let sight_bound = self.tick >= due.saturating_add(INGRESS_SIGHT_DEFERRAL);
        !self
            .players
            .iter()
            .filter(|player| player.is_participant() && player.hp > 0)
            .any(|player| {
                let eye = [
                    player.x,
                    player.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                    player.z,
                ];
                definition.enemies.iter().any(|enemy| {
                    let feet = enemy.hover.as_ref().map_or(enemy.feet, |h| h.approach);
                    (player.x - feet[0]).hypot(player.z - feet[2]) < INGRESS_CLEARANCE
                        || !sight_bound
                            && enemy.hover.is_none()
                            && crate::combat::line_of_sight(
                                eye,
                                [feet[0], feet[1] + 1.0, feet[2]],
                                &arena.solids,
                            )
                })
            })
    }

    pub fn m20_mission_state(&self) -> Option<MissionState> {
        let run = self.mission.as_ref()?;
        let p = run.m20.as_ref()?;
        let g = self.map.m20_geometry()?;
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
                    aboard: ready
                        && alive
                        && run.phase != MissionPhase::Briefing
                        && g.boarding.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z]),
                }
            })
            .collect();
        let departed = run.phase == MissionPhase::Departed;
        let mut completed: Vec<_> = M20_OBJECTIVE_IDS
            .iter()
            .take(p.index)
            .map(|id| (*id).to_owned())
            .collect();
        if departed {
            completed.push("party_departed".into());
        }
        let current = if departed {
            None
        } else if p.index < M20_OBJECTIVE_IDS.len() {
            Some(g.objectives[p.index].clone())
        } else {
            Some(g.departure_objective())
        };
        let mut prompts = Vec::new();
        if run.phase == MissionPhase::InProgress
            && !self.campaign_run_frozen()
            && p.index == M20_OBJECTIVE_IDS.len()
            && p.gate_open
            && !party.is_empty()
            && party.iter().all(|m| m.ready && m.alive && m.aboard)
        {
            let arena = self.current_arena();
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
        let challenges = p.challenges.clone();
        Some(MissionState {
            id: MissionId::LocalException,
            run: run.solo.as_ref().map(|s| s.state),
            rules: run.rules,
            attempt: run.attempt,
            phase: run.phase,
            changed_at: run.changed_at,
            party,
            prompts,
            epilogue: None,
            m20: Some(M20ObjectiveState {
                completed,
                current,
                brief_completed: challenges.brief_completed(run.rules.difficulty),
                challenges,
                crew: p
                    .crew
                    .iter()
                    .map(|member| M20CrewState {
                        phase: member.phase,
                        feet: member.feet,
                    })
                    .collect(),
                pier_reached_at: p.pier_reached_at,
                refuge_integrity: p.refuge_integrity,
                display_lit: p.display_lit,
                reprieve_at: p.reprieve_at,
                latch: p.latch.map(|(feet, _)| feet),
                gate_open: p.gate_open,
                refuge: refuge_for(run.solo.as_ref()),
            }),
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
            m15: None,
            m16: None,
            m17: None,
            m18: None,
            m19: None,
        })
    }

    /// Civilian contact bodies: crew while working or crossing, and Latch.
    pub(super) fn append_m20_contacts(
        &self,
        bodies: &mut Vec<crate::movement::contact::ContactBody>,
    ) {
        let Some(p) = self.mission.as_ref().and_then(|r| r.m20.as_ref()) else {
            return;
        };
        for (i, member) in p.crew.iter().enumerate() {
            if member.phase != M20CrewPhase::Arrived {
                bodies.push(crate::sim::contact::civilian(
                    format!("m20/crew/{i}"),
                    member.feet,
                ));
            }
        }
        if let Some((feet, _)) = p.latch {
            bodies.push(crate::sim::contact::civilian("m20/latch".into(), feet));
        }
    }

    fn m20_in_region(&self, region: &crate::protocol::Region3) -> bool {
        self.players.iter().any(|a| {
            a.is_participant()
                && self.contact_eligible(a)
                && self
                    .mission
                    .as_ref()
                    .is_some_and(|run| run.ready.contains(&a.id))
                && region.contains([a.x, a.y - PLAYER_FLOOR_Y, a.z])
        })
    }

    fn move_m20_walkers(&mut self, prepared: &Prepared) {
        let tick = self.tick;
        for i in 0..M20_CREW {
            let Some(member) = self
                .mission
                .as_ref()
                .and_then(|r| r.m20.as_ref())
                .map(|p| p.crew[i])
            else {
                return;
            };
            if member.phase != M20CrewPhase::Crossing || tick < member.depart_at {
                continue;
            }
            let route = &prepared.crew[i].route;
            let to = route[member.next];
            let feet = step_toward(
                self,
                &format!("m20/crew/{i}"),
                member.feet,
                to,
                CREW_SPEED,
                member.stalled,
            );
            let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
            let entry = &mut p.crew[i];
            entry.stalled = if feet == member.feet {
                entry.stalled.saturating_add(1)
            } else {
                0
            };
            entry.feet = feet;
            if (feet[0] - to[0]).hypot(feet[2] - to[2]) <= 0.05 {
                if member.next + 1 >= route.len() {
                    entry.phase = M20CrewPhase::Arrived;
                    tracing::info!(crew = i, "Waterworks crew member through the wicket");
                } else {
                    entry.next += 1;
                }
            }
        }
        let crossed = self
            .mission
            .as_ref()
            .and_then(|r| r.m20.as_ref())
            .is_some_and(|p| p.crew.iter().all(|c| c.phase == M20CrewPhase::Arrived));
        if crossed {
            self.mission
                .as_mut()
                .unwrap()
                .m20
                .as_mut()
                .unwrap()
                .challenges
                .crew_crossed = true;
        }
        let Some((feet, next)) = self
            .mission
            .as_ref()
            .and_then(|r| r.m20.as_ref())
            .and_then(|p| p.latch.filter(|_| !p.latch_arrived))
        else {
            return;
        };
        let to = prepared.latch_route[next];
        let moved = step_toward(self, "m20/latch", feet, to, LATCH_SPEED, 0);
        let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
        let arrived_here = (moved[0] - to[0]).hypot(moved[2] - to[2]) <= 0.05;
        if arrived_here && next + 1 >= prepared.latch_route.len() {
            p.latch = Some((moved, next));
            p.latch_arrived = true;
            tracing::info!("Latch walked back across the pier");
        } else {
            p.latch = Some((moved, if arrived_here { next + 1 } else { next }));
        }
    }

    /// Supplies in a crate stay out of reach until the people bring it up.
    fn hold_m20_crates(&mut self, prepared: &Prepared, hold_start: Option<u64>) {
        let tick = self.tick;
        let Some(p) = self.mission.as_mut().and_then(|r| r.m20.as_mut()) else {
            return;
        };
        for (index, c) in prepared.crates.iter().enumerate() {
            let due = hold_start.is_some_and(|start| tick >= start.saturating_add(c.release));
            if due && !p.released[index] {
                p.released[index] = true;
                for pad in self
                    .pickups
                    .iter_mut()
                    .filter(|pad| c.supplies.contains(&pad.id))
                {
                    pad.available = true;
                }
                tracing::info!(crate_index = index, "Resupply crate brought up to the pier");
            } else if !p.released[index] {
                for pad in self
                    .pickups
                    .iter_mut()
                    .filter(|pad| c.supplies.contains(&pad.id))
                {
                    pad.available = false;
                }
            }
        }
    }

    /// Machines standing on the refuge line wear the barricade down.
    fn wear_m20_barricade(&mut self, prepared: &Prepared) {
        let difficulty = self.campaign_rules().difficulty;
        if !self.tick.is_multiple_of(wear_interval(difficulty)) {
            return;
        }
        let line = &prepared.geometry.refuge_line;
        let wear: u32 = self
            .players
            .iter()
            .filter(|p| p.hp > 0 && !self.encounters.stood_down(p.id))
            .filter_map(|p| match p.campaign {
                Some(crate::protocol::CampaignActor::Hostile { kind, .. })
                    if crate::encounters::enemy::gait(kind) > 0.0
                        && line.contains([p.x, p.y - PLAYER_FLOOR_Y, p.z]) =>
                {
                    Some(if kind == EnemyKind::HeavySweeper {
                        2
                    } else {
                        1
                    })
                }
                _ => None,
            })
            .sum();
        if wear == 0 {
            return;
        }
        let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
        let before = p.refuge_integrity;
        p.refuge_integrity = before.saturating_sub(u16::try_from(wear).unwrap_or(u16::MAX));
        if before > 0 && p.refuge_integrity == 0 {
            p.challenges.refuge_held = false;
            tracing::info!("The refuge barricade fell; the people pulled back from the line");
        }
    }

    fn march_m20_pressure(&mut self, prepared: &Prepared) {
        let tick = self.tick;
        let woke: Vec<usize> = {
            let Some(p) = self.mission.as_ref().and_then(|r| r.m20.as_ref()) else {
                return;
            };
            prepared
                .pressure
                .iter()
                .enumerate()
                .filter(|(slot, s)| !p.marched[*slot] && self.encounters.is_awake(s.group))
                .map(|(slot, _)| slot)
                .collect()
        };
        for slot in woke {
            let group = prepared.pressure[slot].group;
            self.encounters
                .march_group(group, &prepared.refuge_marks, tick);
            self.mission.as_mut().unwrap().m20.as_mut().unwrap().marched[slot] = true;
            tracing::info!(group = %self.map.encounters()[group].id, "Pressure reached the district");
        }
        if tick.is_multiple_of(MARCH_REFRESH) {
            let groups: Vec<usize> = prepared.pressure.iter().map(|s| s.group).collect();
            let mut encounters = std::mem::take(&mut self.encounters);
            encounters.march_idle(self, &groups, tick);
            self.encounters = encounters;
        }
    }

    pub(super) fn advance_m20(&mut self) {
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
        let Some(prepared) = self.m20_prepared().cloned() else {
            return;
        };
        let old = self.m20_mission_state().and_then(|s| s.m20);
        let broken = self.encounters.drain_marks_broken();
        if broken > 0 {
            let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
            p.challenges.mark_broken = true;
        }
        if self.encounters.surveyor_lesson_over(self, SLUICE_GROUP) {
            let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
            if !p.lesson_over {
                p.lesson_over = true;
                tracing::info!("The Surveyor has taught alone; a machine follows it");
            }
        }
        self.move_m20_walkers(&prepared);
        let (index, clock) = {
            let p = self.mission.as_ref().unwrap().m20.as_ref().unwrap();
            (p.index, p.clock(&prepared))
        };
        let g = &prepared.geometry;
        let region = |i: usize| match &g.objectives[i].action {
            MissionObjectiveAction::Arrival { region, .. } => Some(region.clone()),
            _ => None,
        };
        let tick = self.tick;
        match index {
            0 => {
                if self.encounters.is_complete(SLUICE_GROUP)
                    && region(0).is_some_and(|r| self.m20_in_region(&r))
                {
                    self.mission.as_mut().unwrap().m20.as_mut().unwrap().index = 1;
                }
            }
            1 => {
                if self.encounters.is_complete(CROSSING_GROUP)
                    && region(1).is_some_and(|r| self.m20_in_region(&r))
                {
                    let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
                    p.index = 2;
                    for (i, member) in p.crew.iter_mut().enumerate() {
                        member.phase = M20CrewPhase::Crossing;
                        member.depart_at = tick + CREW_STAGGER * i as u64;
                    }
                    tracing::info!("Crossing clear; the waterworks crew go on their own");
                }
            }
            2 => {
                if region(2).is_some_and(|r| self.m20_in_region(&r)) {
                    let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
                    p.pier_reached_at = Some(tick);
                    p.index = 3;
                    tracing::info!("The pier: thirty seconds of the people you are here for");
                }
            }
            3 => {
                if clock.is_some_and(|(_, turn, _)| tick >= turn) {
                    let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
                    p.display_lit = true;
                    p.index = 4;
                    tracing::info!("Harbour display lit: six minutes");
                }
            }
            4 => {
                if clock.is_some_and(|(_, _, reprieve)| tick >= reprieve) {
                    {
                        let p = self.mission.as_mut().unwrap().m20.as_mut().unwrap();
                        p.reprieve_at = Some(tick);
                        p.index = 5;
                        p.latch = Some((prepared.latch_route[0], 1));
                    }
                    self.clear_hostile_projectiles();
                    self.stand_down_encounters(&prepared.reprieve_exits);
                    tracing::info!("Reprieve: the machines reach the refuge line and stop");
                }
            }
            _ => {
                let p = self.mission.as_ref().unwrap().m20.as_ref().unwrap();
                let timed_out = p
                    .reprieve_at
                    .is_some_and(|at| tick >= at.saturating_add(GATE_TIMEOUT));
                if !p.gate_open && (p.latch_arrived || timed_out) {
                    if let Some(world) = self.map.prepared_m20_world(1) {
                        self.map = world;
                        self.mission
                            .as_mut()
                            .unwrap()
                            .m20
                            .as_mut()
                            .unwrap()
                            .gate_open = true;
                        tracing::info!("The refuge gate opens");
                    }
                }
            }
        }
        let (index, clock, reprieve) = {
            let p = self.mission.as_ref().unwrap().m20.as_ref().unwrap();
            (p.index, p.clock(&prepared), p.reprieve_at.is_some())
        };
        self.hold_m20_crates(&prepared, clock.map(|(start, _, _)| start));
        if reprieve {
            let (group, exit) = prepared.passing;
            let mut encounters = std::mem::take(&mut self.encounters);
            encounters.stand_down_group(self, group, exit, tick);
            self.encounters = encounters;
        }
        if index >= 3 && !reprieve && clock.is_some_and(|(start, _, _)| tick >= start) {
            self.march_m20_pressure(&prepared);
            self.wear_m20_barricade(&prepared);
        }

        let new = self.m20_mission_state().unwrap();
        if new.m20 != old {
            self.mission.as_mut().unwrap().changed_at = self.tick;
        }
        if index < M20_OBJECTIVE_IDS.len()
            || !new.prompts.iter().any(|p| requests.contains(&p.player_id))
        {
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
        tracing::info!("Local Exception complete: the campaign's refuge crossing holds");
    }
}
