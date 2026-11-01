//! One match's tally, read from the authoritative session from outside: the
//! state after each tick and the messages that tick broadcast. The observer
//! never steers anything. Fighter ids live only in its working memory, to
//! pair a spawn with its first contact or a hit with its frag, and are
//! dropped with it; the record it hands back holds none of them.
use super::record::{FunRecord, MatchTally, TickHealth, RECORD_SCHEMA};
use super::{sight, APPOINTMENT_TICKS, CONTEST_RADIUS, CONTEST_TICKS, SPAWN_DEATH_TICKS};
use crate::protocol::{
    FlagEventKind, GameEvent, GameMode, Mutator, Role, SabotageEventKind, SabotageReason,
    ServerMessage, Team, WeaponType,
};
use crate::session::GameSession;
use crate::sim::{BotSkill, GameState, PickupKind};
use std::collections::HashMap;
use uuid::Uuid;

/// The sole front of the round.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Leader {
    Fighter(Uuid),
    Side(Team),
}

/// The match's settings as the record names them.
#[derive(Debug, Clone, PartialEq)]
struct Setting {
    mode: GameMode,
    map_id: u32,
    mutators: Vec<Mutator>,
    friendly_fire: bool,
    bot_tier: BotSkill,
}

impl Setting {
    fn of(session: &GameSession) -> Self {
        let rules = &session.state.config.rules;
        Self {
            mode: rules.mode(),
            map_id: session.state.map.id(),
            mutators: rules.mutators().to_vec(),
            friendly_fire: rules.friendly_fire(),
            bot_tier: session.bot_skill(),
        }
    }
}

/// Folds one match. Feed it every tick with [`Observer::observe`], or with
/// [`Observer::begin_tick`] and then [`Observer::message`] for each message
/// when a caller reads the same messages itself.
#[derive(Debug)]
pub struct Observer {
    setting: Setting,
    live: bool,
    finished: bool,
    first_round_tick: Option<u64>,
    last_tick: u64,
    tally: MatchTally,
    fighters_peak: u32,
    bots_peak: u32,
    leader: Option<Leader>,
    spawned_at: HashMap<Uuid, u64>,
    /// Spawned and not yet in contact, with the spawn tick.
    awaiting: HashMap<Uuid, u64>,
    /// Spawned and not yet in a landed shot either way.
    unhit: HashMap<Uuid, u64>,
    /// The first tick somebody else hurt this fighter in this life.
    first_damage: HashMap<Uuid, u64>,
    /// Per pad: the tick it last returned in live play, whether that return
    /// still waits for its first claim, and whether it stood ready last tick.
    returned: Vec<Option<u64>>,
    waiting: Vec<bool>,
    was_available: Vec<bool>,
    /// Rockets each fighter had launched when last read.
    rocket_attacks: HashMap<Uuid, u64>,
    site_owners: Vec<Option<Team>>,
}

/// Weapon and armour pads: the power on a map.
pub fn power(kind: PickupKind) -> bool {
    match kind {
        PickupKind::Weapon(weapon) => weapon != WeaponType::Flechette,
        PickupKind::Armor | PickupKind::Plate => true,
        _ => false,
    }
}

fn ticks_u32(ticks: u64) -> u32 {
    u32::try_from(ticks).unwrap_or(u32::MAX)
}

fn centimetres(metres: f32) -> u32 {
    (f64::from(metres) * 100.0)
        .round()
        .clamp(0.0, f64::from(u32::MAX)) as u32
}

/// The sole leader by the scores: a fighter in free-for-all and Duel, a side
/// in team deathmatch and CTF. None when level, and always in the objective
/// modes, which are not led by frags.
fn sole_leader(state: &GameState, mode: GameMode) -> Option<Leader> {
    match mode {
        GameMode::Tdm => state.team_scores.leader().map(Leader::Side),
        GameMode::Ctf => state.capture_scores.leader().map(Leader::Side),
        GameMode::Ffa | GameMode::Duel => {
            let mut best: Option<(Uuid, u32)> = None;
            let mut level = false;
            for player in state.players.iter().filter(|p| !p.is_boss) {
                let score = state.scores.get(&player.id).copied().unwrap_or(0);
                match best {
                    Some((_, top)) if score < top => {}
                    Some((_, top)) if score == top => level = true,
                    _ => {
                        best = Some((player.id, score));
                        level = false;
                    }
                }
            }
            best.filter(|(_, top)| !level && *top > 0)
                .map(|(id, _)| Leader::Fighter(id))
        }
        GameMode::Sabotage | GameMode::Conquest => None,
    }
}

impl Observer {
    pub fn new(session: &GameSession) -> Self {
        let mut observer = Self {
            setting: Setting::of(session),
            live: false,
            finished: false,
            first_round_tick: None,
            last_tick: session.state.tick,
            tally: MatchTally::default(),
            fighters_peak: 0,
            bots_peak: 0,
            leader: None,
            spawned_at: HashMap::new(),
            awaiting: HashMap::new(),
            unhit: HashMap::new(),
            first_damage: HashMap::new(),
            returned: Vec::new(),
            waiting: Vec::new(),
            was_available: Vec::new(),
            rocket_attacks: session
                .state
                .players
                .iter()
                .map(|p| (p.id, p.statistics.attacks_with(WeaponType::Rocket)))
                .collect(),
            site_owners: Vec::new(),
        };
        observer.read_map(&session.state);
        observer
    }

    fn read_map(&mut self, state: &GameState) {
        self.returned = vec![None; state.pickups.len()];
        self.waiting = vec![false; state.pickups.len()];
        self.was_available = state.pickups.iter().map(|p| p.available).collect();
        self.site_owners = state
            .conquest
            .as_ref()
            .map(|c| c.points.iter().map(|p| p.owner).collect())
            .unwrap_or_default();
    }

    /// Whether the match is in live play right now.
    pub fn live(&self) -> bool {
        self.live
    }

    /// Whether the match reached its end: the round outside Sabotage, the
    /// deciding round in it.
    pub fn finished(&self) -> bool {
        self.finished
    }

    /// Whether any live play was seen.
    pub fn played(&self) -> bool {
        self.tally.live_ticks > 0
    }

    pub fn tally(&self) -> &MatchTally {
        &self.tally
    }

    /// One tick: the state after it and every message it broadcast.
    pub fn observe(&mut self, session: &GameSession, messages: &[ServerMessage]) {
        self.begin_tick(session);
        for message in messages {
            self.message(session, message);
        }
    }

    /// The state half of a tick: leads, sight contact, live time, pads,
    /// rockets launched and sites changing hands.
    pub fn begin_tick(&mut self, session: &GameSession) {
        let state = &session.state;
        let tick = state.tick;
        self.last_tick = tick;
        if self.first_round_tick.is_none() {
            let setting = Setting::of(session);
            if setting.map_id != self.setting.map_id {
                self.read_map(state);
            }
            self.setting = setting;
        }
        let fighters = state
            .players
            .iter()
            .filter(|p| p.is_participant() && p.role != Role::Spectator)
            .count();
        self.fighters_peak = self.fighters_peak.max(fighters as u32);
        self.bots_peak = self.bots_peak.max(session.bots.len() as u32);
        // A rocket leaves no hitscan trace, so the launcher is read from
        // each fighter's own count of launches.
        let mut rockets = 0;
        for player in &state.players {
            let now = player.statistics.attacks_with(WeaponType::Rocket);
            let before = self.rocket_attacks.insert(player.id, now).unwrap_or(0);
            rockets += now.saturating_sub(before);
        }
        if self.rocket_attacks.len() > state.players.len() {
            self.rocket_attacks
                .retain(|id, _| state.players.iter().any(|p| p.id == *id));
        }
        *self.tally.shots.get_mut(WeaponType::Rocket) += rockets;
        let mode = self.setting.mode;
        if self.live {
            if let Some(now) = sole_leader(state, mode) {
                if self.leader.is_some_and(|before| before != now) {
                    self.tally.lead_changes += 1;
                }
                self.leader = Some(now);
            }
            if !self.awaiting.is_empty() {
                let arena = state.current_arena();
                let met: Vec<Uuid> = self
                    .awaiting
                    .keys()
                    .copied()
                    .filter(|id| {
                        state
                            .players
                            .iter()
                            .find(|p| p.id == *id)
                            .is_some_and(|me| {
                                sight::alive(me)
                                    && state.players.iter().any(|other| {
                                        sight::in_contact(mode, &arena.solids, me, other)
                                    })
                            })
                    })
                    .collect();
                for id in met {
                    self.contact(id, tick);
                }
            }
            self.tally.live_ticks += 1;
        }
        for (index, pad) in state.pickups.iter().enumerate() {
            if index >= self.was_available.len() {
                break;
            }
            if self.live && pad.available && !self.was_available[index] && power(pad.kind) {
                self.tally.power_returns += 1;
                self.returned[index] = Some(tick);
                self.waiting[index] = true;
            }
            self.was_available[index] = pad.available;
        }
        if let Some(conquest) = &state.conquest {
            for (index, point) in conquest.points.iter().enumerate() {
                if index >= self.site_owners.len() {
                    self.site_owners.push(point.owner);
                    continue;
                }
                if self.site_owners[index] != point.owner {
                    if self.live && point.owner.is_some() {
                        self.tally.conquest.site_flips += 1;
                    }
                    self.site_owners[index] = point.owner;
                }
            }
        }
    }

    fn contact(&mut self, id: Uuid, tick: u64) {
        if let Some(at) = self.awaiting.remove(&id) {
            self.tally
                .respawn_to_contact_ticks
                .push(ticks_u32(tick.saturating_sub(at)));
        }
    }

    fn landed(&mut self, id: Uuid, tick: u64) {
        self.contact(id, tick);
        if let Some(at) = self.unhit.remove(&id) {
            self.tally
                .respawn_to_hit_ticks
                .push(ticks_u32(tick.saturating_sub(at)));
        }
    }

    fn spawn(&mut self, id: Uuid, tick: u64) {
        self.spawned_at.insert(id, tick);
        self.awaiting.insert(id, tick);
        self.unhit.insert(id, tick);
        self.first_damage.remove(&id);
        self.tally.spawns += 1;
    }

    fn round_started(&mut self, session: &GameSession) {
        if self.first_round_tick.is_none() {
            let setting = Setting::of(session);
            if setting.map_id != self.setting.map_id {
                self.read_map(&session.state);
            }
            self.setting = setting;
            self.first_round_tick = Some(session.state.tick);
        }
        self.tally.rounds += 1;
        let ids: Vec<Uuid> = session.state.players.iter().map(|p| p.id).collect();
        for id in ids {
            self.spawn(id, session.state.tick);
        }
    }

    /// One message the tick broadcast.
    pub fn message(&mut self, session: &GameSession, message: &ServerMessage) {
        match message {
            ServerMessage::Snapshot(snapshot) if self.live => {
                for shot in &snapshot.shot_results {
                    if let Some(trace) = &shot.trace {
                        *self.tally.shots.get_mut(trace.weapon) += 1;
                    }
                    if let Some(zone) = shot.zone {
                        self.tally.zone_hits.count(zone);
                        if shot.killed {
                            self.tally.kill_zones.count(zone);
                        }
                    }
                }
            }
            ServerMessage::Event(event) => self.event(session, event),
            _ => {}
        }
    }

    fn event(&mut self, session: &GameSession, event: &GameEvent) {
        let state = &session.state;
        let tick = state.tick;
        let rounds = self.setting.mode == GameMode::Sabotage;
        match event {
            // Sabotage plays rounds: live from each round's go to its end,
            // so the muster freeze is not live play.
            GameEvent::Sabotage { kind, .. } if rounds => match kind {
                SabotageEventKind::Live => self.live = true,
                SabotageEventKind::Planted if self.live => self.tally.sabotage.plants += 1,
                _ => {}
            },
            GameEvent::RoundStart { .. } => {
                self.round_started(session);
                if self.setting.mode != GameMode::Sabotage {
                    self.live = true;
                }
            }
            GameEvent::RoundEnd {
                sabotage,
                winning_team,
                ..
            } => {
                if rounds {
                    self.live = false;
                    if let Some(result) = sabotage {
                        let tally = &mut self.tally.sabotage;
                        tally.rounds += 1;
                        match winning_team {
                            Some(Team::Coalition) => tally.attack_wins += 1,
                            Some(Team::Union) => tally.defence_wins += 1,
                            None => tally.level_rounds += 1,
                        }
                        match result.reason {
                            SabotageReason::Elimination => tally.by_elimination += 1,
                            SabotageReason::Detonation => tally.by_detonation += 1,
                            SabotageReason::Defused => tally.by_defuse += 1,
                            SabotageReason::Time => tally.by_time += 1,
                        }
                        if result.match_over {
                            tally.matches_decided += 1;
                            self.finished = true;
                        }
                    }
                } else if self.live {
                    self.live = false;
                    self.finished = true;
                    if let Some(conquest) = &state.conquest {
                        let tally = &mut self.tally.conquest;
                        tally.matches_decided += 1;
                        match winning_team {
                            Some(Team::Union) => tally.union_wins += 1,
                            Some(Team::Coalition) => tally.coalition_wins += 1,
                            None => {}
                        }
                        for point in &conquest.points {
                            match point.owner {
                                Some(Team::Union) => tally.union_sites_at_end += 1,
                                Some(Team::Coalition) => tally.coalition_sites_at_end += 1,
                                None => {}
                            }
                        }
                        tally.union_tickets_left += conquest.tickets.union;
                        tally.coalition_tickets_left += conquest.tickets.coalition;
                    }
                }
            }
            GameEvent::Respawn { player } if self.live => {
                if let Some(id) = state
                    .players
                    .iter()
                    .find(|p| &p.name == player)
                    .map(|p| p.id)
                {
                    self.spawn(id, tick);
                }
            }
            GameEvent::Hit {
                shooter_id,
                target_id,
                target_hp_after,
                ..
            } if self.live && shooter_id == target_id => {
                // A fighter's own blast is not a hit on anybody else.
                if *target_hp_after <= 0 {
                    self.tally.self_deaths += 1;
                }
            }
            GameEvent::Hit {
                shooter_id,
                target_id,
                damage,
                ..
            } if self.live => {
                self.tally.hits += 1;
                self.landed(*shooter_id, tick);
                self.landed(*target_id, tick);
                if *damage > 0 {
                    self.first_damage.entry(*target_id).or_insert(tick);
                }
            }
            GameEvent::Frag {
                victim_id,
                killer_id,
                weapon,
                ..
            } if self.live => self.frag(state, *victim_id, *killer_id, *weapon),
            GameEvent::Pickup { pickup_id, .. } if self.live => self.pickup(state, pickup_id),
            GameEvent::Flag {
                kind: FlagEventKind::Captured,
                ..
            } if self.live => self.tally.captures += 1,
            _ => {}
        }
    }

    fn frag(
        &mut self,
        state: &GameState,
        victim_id: Option<Uuid>,
        killer_id: Option<Uuid>,
        weapon: Option<WeaponType>,
    ) {
        let tick = state.tick;
        self.tally.frags += 1;
        if let Some(weapon) = weapon {
            *self.tally.frag_weapons.get_mut(weapon) += 1;
        }
        let Some(victim_id) = victim_id else {
            return;
        };
        self.landed(victim_id, tick);
        let other = killer_id.filter(|killer| *killer != victim_id);
        let first_damage = self.first_damage.remove(&victim_id);
        if let (Some(_), Some(at)) = (other, first_damage) {
            self.tally
                .time_to_kill_ticks
                .push(ticks_u32(tick.saturating_sub(at)));
        }
        let find = |id: Uuid| state.players.iter().find(|p| p.id == id);
        let killer = other.and_then(find);
        let victim = find(victim_id);
        if let (Some(killer), Some(victim), Some(weapon)) = (killer, victim, weapon) {
            self.tally
                .kill_distance_cm
                .get_mut(weapon)
                .push(centimetres(
                    (killer.x - victim.x).hypot(killer.z - victim.z),
                ));
        }
        if self
            .spawned_at
            .get(&victim_id)
            .is_some_and(|at| tick.saturating_sub(*at) <= SPAWN_DEATH_TICKS)
        {
            self.tally.spawn_deaths += 1;
        }
        let places: Vec<(f32, f32)> = [Some(victim_id), killer_id]
            .into_iter()
            .flatten()
            .filter_map(|id| find(id).map(|p| (p.x, p.z)))
            .collect();
        let contested = state.pickups.iter().enumerate().any(|(index, pad)| {
            power(pad.kind)
                && self
                    .returned
                    .get(index)
                    .copied()
                    .flatten()
                    .is_some_and(|at| tick.saturating_sub(at) <= CONTEST_TICKS)
                && places
                    .iter()
                    .any(|(x, z)| (pad.x - x).hypot(pad.z - z) <= CONTEST_RADIUS)
        });
        if contested {
            self.tally.contested_frags += 1;
        }
    }

    fn pickup(&mut self, state: &GameState, pickup_id: &str) {
        let tick = state.tick;
        self.tally.pickups += 1;
        if pickup_id.starts_with(crate::sim::drops::DROPPED_GUN_PREFIX) {
            self.tally.drop_claims += 1;
        }
        let Some(index) = state.pickups.iter().position(|p| p.id == pickup_id) else {
            return;
        };
        match state.pickups[index].kind {
            PickupKind::Plate => self.tally.plate_claims += 1,
            PickupKind::Weapon(WeaponType::Rocket) => self.tally.rocket_claims += 1,
            _ => {}
        }
        let waiting = self.waiting.get(index).copied().unwrap_or(false);
        if let Some(at) = self
            .returned
            .get(index)
            .copied()
            .flatten()
            .filter(|_| waiting)
        {
            // The return tick stays for the contest window; the next claim
            // needs the next return.
            self.waiting[index] = false;
            let wait = tick.saturating_sub(at);
            self.tally.power_claims += 1;
            self.tally.power_wait_ticks += wait;
            if wait <= APPOINTMENT_TICKS {
                self.tally.appointments += 1;
            }
        }
    }

    /// The record for disk: the settings, the tally with every list sorted,
    /// and how the server kept time when something timed it.
    pub fn into_record(self, tick_health: Option<TickHealth>) -> FunRecord {
        let mut tally = self.tally;
        tally.settle();
        FunRecord {
            schema: RECORD_SCHEMA,
            map_id: self.setting.map_id,
            mode: self.setting.mode,
            mutators: self.setting.mutators,
            friendly_fire: self.setting.friendly_fire,
            bot_tier: self.setting.bot_tier,
            finished: self.finished,
            match_ticks: self
                .first_round_tick
                .map_or(0, |at| self.last_tick.saturating_sub(at)),
            fighters_peak: self.fighters_peak,
            bots_peak: self.bots_peak,
            tally,
            tick_health,
        }
    }
}
