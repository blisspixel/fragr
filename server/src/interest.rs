//! Per-recipient interest: a fighter's socket carries only what that fighter
//! could perceive (fair play, gameplay 66).
//!
//! The tick still builds and encodes one world. Before fan-out, each fighter
//! connected to a shared arcade room gets its own view of that world: every
//! other fighter it could see stays whole, one it could only hear becomes a
//! `heard` row at a rough place, and one it could neither see nor hear becomes
//! a `hidden` row. Both keep the scoreboard and identity fields and nothing
//! else a modified client could aim with (`PlayerState.sense`). Spectators,
//! the booth and campaign missions keep the whole world.
//!
//! **Seen** is decided generously, so nobody is late around a corner. A
//! world sent at tick `d` is drawn while the reader's own predicted body
//! stands where the server will have it a round trip plus the buffer after
//! `d`, so every pair is traced each tick:
//!
//! - From the reader's eye standing (rising from a crouch is a peek), from
//!   that eye after its lead ([`lead_ticks`]: four ticks plus the measured
//!   round trip) on its velocity or its measured motion (a vehicle seat,
//!   stairs) and one step higher, and from a step either way across the line
//!   (a reader that turns or starts from rest).
//! - To the target's chest, crown and shoulders, and its shoulders widened by
//!   [`PEEK_MARGIN`], now; and its chest and widened shoulders
//!   [`TARGET_LEAD_TICKS`] ahead, so a body about to clear a corner is
//!   already on the reader's socket.
//! - Through the shot solids only (`combat::SightGrid`, exactly
//!   `combat::line_of_sight`), with no view cone: a reader can turn faster
//!   than a tick.
//! - A sighting is kept for [`SEEN_GRACE`] after the last clear line, so a
//!   body that steps back behind cover does not blink.
//!
//! `fragr-playtest --interest-survey` measures how often a body still turns
//! visible before its row is drawn (docs/BENCHMARK.md).
//!
//! **Always seen:** the reader itself, team-mates in a team mode, campaign
//! actors and the arena boss, anybody seated in a vehicle (the hull is in
//! every world and loud), objective carriers (a carried flag or charge
//! already gives the carrier's feet), and the fighter that killed the reader
//! while the reader is down, so the death recap has its killer. A reader that
//! is down in a team mode sees what its living team-mates see: the team seat
//! rides their eyes (`game_manager.gd`).
//!
//! **Heard** reuses the bots' ears (`sim::bot_senses::hunt`): running feet
//! within `FOOTSTEP_REACH` and gunfire within `GUNFIRE_WALLED`. The row's
//! place is off by up to `EAR_ERROR` of the distance, on a slowly turning
//! bearing, so footsteps play near the right place and the place drifts
//! smoothly instead of jumping.
//!
//! What a world still carries for everyone: shot results (gunfire is
//! audible and a tracer is visible), projectiles, explosions, vehicles,
//! pickups and events. Those are known, coarse leaks.

use crate::net::Broadcast;
use crate::protocol::{GameEvent, PlayerSense, PlayerState, ServerMessage, Snapshot};
use crate::sim::bot_senses::hunt::{EAR_ERROR, FOOTSTEP_REACH, FOOTSTEP_SPEED, GUNFIRE_WALLED};
use crate::sim::{GameState, Player, RoundState};
use std::collections::HashMap;
use std::sync::Arc;
use uuid::Uuid;

/// Ticks a sighting is kept after the last clear line: 0.5 s.
pub const SEEN_GRACE: u64 = 10;
/// Ticks a sound is kept after it stops: 0.5 s.
pub const HEARD_GRACE: u64 = 10;
/// How far past the body's radius a shoulder probe reaches, metres. A
/// sighting from a peek's first frame needs the line to a shoulder, not to
/// the chest.
pub const PEEK_MARGIN: f32 = 0.6;
/// Every reader's own lead, ticks: the 60 to 100 ms interpolation buffer
/// and two ticks of slack for the world in flight.
pub const LEAD_BASE_TICKS: f32 = 4.0;
/// The longest lead a slow link earns, ticks (500 ms).
pub const LEAD_MAX_TICKS: f32 = 10.0;
/// The furthest the reader's eye is tested across the line, metres: a full
/// speed step over a long lead.
pub const EYE_REACH: f32 = 2.0;
/// How far ahead a target is tested, ticks.
pub const TARGET_LEAD_TICKS: f32 = 3.0;
/// The heard bearing turns once in this many ticks (8 s).
const HEARD_TURN_TICKS: f32 = 160.0;
const TICK_SECONDS: f32 = 0.05;
/// A shoulder probe sits this far above the feet.
const SHOULDER: f32 = 1.4;
/// A head probe sits this far above the eye.
const CROWN: f32 = 0.2;

/// What a reader perceives of one row.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Sense {
    Seen,
    /// Where it sounds: the row's `x`, `y`, `z`.
    Heard([f32; 3]),
    Hidden,
}

/// The rows a reader does not see whole, by roster index. Empty when the
/// reader sees everybody, so it shares the tick's broadcast.
pub type View = Vec<(usize, Sense)>;

/// Counters for the measurements (`bench`, `fragr-playtest --interest`).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct InterestCounts {
    /// Reader and target pairs decided this tick.
    pub pairs: u64,
    /// Lines of sight traced.
    pub rays: u64,
    /// Rows sent heard or hidden.
    pub withheld: u64,
}

/// Memory across ticks: sightings, sounds and killers.
#[derive(Debug, Default)]
pub struct Interest {
    sighted: HashMap<(Uuid, Uuid), u64>,
    heard: HashMap<(Uuid, Uuid), u64>,
    /// The fighter that killed each reader, until the reader is back up.
    killers: HashMap<Uuid, Uuid>,
    counts: InterestCounts,
    /// The solids lines are traced through, filed by floor cell; rebuilt
    /// when the solids change.
    grid: Option<crate::combat::SightGrid>,
    /// Each fighter's feet last tick, and how far they moved since.
    feet: HashMap<Uuid, (u64, [f32; 3])>,
    moved: HashMap<Uuid, [f32; 3]>,
}

/// The ids every view leaves whole whatever the walls say: objective
/// carriers. Read from the world being sent, so the rule follows the wire.
fn carriers(snapshot: &Snapshot) -> Vec<Uuid> {
    let mut ids: Vec<Uuid> = snapshot
        .flags
        .iter()
        .flatten()
        .filter_map(|flag| flag.carrier)
        .collect();
    ids.extend(
        snapshot
            .sabotage
            .as_ref()
            .and_then(|sabotage| sabotage.charge.as_ref())
            .and_then(|charge| charge.carrier),
    );
    ids
}

fn down(state: &GameState, player: &Player) -> bool {
    !state.contact_eligible(player)
}

fn feet(player: &Player) -> [f32; 3] {
    [player.x, player.y - crate::sim::PLAYER_FLOOR_Y, player.z]
}

fn eye(player: &Player) -> [f32; 3] {
    let mut at = feet(player);
    at[1] += crate::combat::stance_eye(player.campaign, player.ducking);
    at
}

/// `point` carried `ticks` ahead on `player`'s motion: its velocity, or the
/// distance its feet moved last tick when that is faster (a seat in a
/// vehicle moves the body with no walking velocity), and the height they
/// climbed (stairs and ramps move the eye without any `vy`).
fn ahead(point: [f32; 3], player: &Player, ticks: f32, moved: [f32; 3]) -> [f32; 3] {
    let seconds = ticks * TICK_SECONDS;
    let walked = [player.vx * TICK_SECONDS, player.vz * TICK_SECONDS];
    let step = if moved[0].hypot(moved[2]) > walked[0].hypot(walked[1]) {
        [moved[0], moved[2]]
    } else {
        walked
    };
    // A jump's rise is a peek too; a fall is clamped so the probe stays
    // above the floor it will land on.
    let rise = (player.vy * seconds + moved[1] * ticks).clamp(-1.5, 1.5);
    [
        point[0] + step[0] * ticks,
        (point[1] + rise).max(point[1].min(0.2)),
        point[2] + step[1] * ticks,
    ]
}
fn mix(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

fn salt(id: Uuid) -> u64 {
    let value = id.as_u128();
    value as u64 ^ (value >> 64) as u64
}

/// The reader's lead in ticks from its measured round trip. A world sent at
/// tick `d` reaches the reader half a round trip later and is drawn a buffer
/// after that, while the reader's own body is predicted half a round trip
/// ahead of the server: its eye then stands where the server will have it
/// a whole round trip plus the buffer after `d`.
pub fn lead_ticks(ping_ms: Option<u16>) -> f32 {
    let round_trip = f32::from(ping_ms.unwrap_or(0)) / 1000.0 / TICK_SECONDS;
    (LEAD_BASE_TICKS + round_trip).min(LEAD_MAX_TICKS)
}

/// Whether any probe line from the reader to the target is clear.
fn clear_line(
    reader: &Player,
    target: &Player,
    lead: f32,
    moved: [[f32; 3]; 2],
    grid: &crate::combat::SightGrid,
    rays: &mut u64,
) -> bool {
    // The reader's eye stands up: rising from a crouch is a peek too.
    let mut eye_now = eye(reader);
    eye_now[1] =
        eye_now[1].max(feet(reader)[1] + crate::combat::stance_eye(reader.campaign, false));
    let feet_now = feet(target);
    let feet_lead = ahead(feet_now, target, TARGET_LEAD_TICKS, moved[1]);
    let dx = feet_now[0] - eye_now[0];
    let dz = feet_now[2] - eye_now[2];
    let across = dx.hypot(dz);
    // Perpendicular to the line, in the floor plane.
    let (side_x, side_z) = if across > 1e-3 {
        (-dz / across, dx / across)
    } else {
        (1.0, 0.0)
    };
    // Where the reader's client may have put its eye by the time this world
    // is drawn: along its velocity, or a step either way across the line if
    // it turns or starts from rest.
    let step = (crate::movement::TOP_SPEED * lead * TICK_SECONDS).min(EYE_REACH);
    let across_by =
        |point: [f32; 3], by: f32| [point[0] + side_x * by, point[1], point[2] + side_z * by];
    // A moving reader may take a step up before this world is drawn: its
    // lead eye stands one step higher.
    let mut eye_lead = ahead(eye_now, reader, lead, moved[0]);
    if reader.vx.hypot(reader.vz) > 1.0 {
        eye_lead[1] += crate::movement::STEP_UP;
    }
    let eyes = [
        eye_now,
        eye_lead,
        across_by(eye_now, step),
        across_by(eye_now, -step),
    ];
    let stand = crate::combat::stance_eye(target.campaign, target.ducking);
    let reach = crate::movement::RADIUS + PEEK_MARGIN;
    let points = |body: [f32; 3], whole: bool| {
        let chest = crate::combat::aim_point_for(body, target.campaign, target.ducking);
        let shoulder = [body[0], body[1] + SHOULDER.min(stand), body[2]];
        let mut points = vec![
            chest,
            across_by(shoulder, reach),
            across_by(shoulder, -reach),
        ];
        if whole {
            // The body's own crown and shoulders: a thin post can hide the
            // widened line and not these.
            points.push([body[0], body[1] + stand + CROWN, body[2]]);
            points.push(across_by(shoulder, crate::movement::RADIUS));
            points.push(across_by(shoulder, -crate::movement::RADIUS));
        }
        points
    };
    let mut targets = points(feet_now, true);
    targets.extend(points(feet_lead, false));
    for eye in eyes {
        for point in &targets {
            *rays += 1;
            if grid.line_of_sight(eye, *point) {
                return true;
            }
        }
    }
    false
}

fn audible(reader: &Player, target: &Player) -> bool {
    let distance = (target.x - reader.x).hypot(target.z - reader.z);
    let running = target.vy == 0.0 && target.vx.hypot(target.vz) >= FOOTSTEP_SPEED;
    (running && distance <= FOOTSTEP_REACH) || (target.just_fired && distance <= GUNFIRE_WALLED)
}

/// Where a heard target sounds to this reader: off by up to `EAR_ERROR` of
/// the distance on a bearing that turns slowly, so it drifts, never jumps.
fn heard_at(reader: &Player, target: &Player, tick: u64) -> [f32; 3] {
    let distance = (target.x - reader.x).hypot(target.z - reader.z);
    let phase = (mix(salt(reader.id) ^ salt(target.id).rotate_left(17)) & 0xffff) as f32 / 65536.0
        * std::f32::consts::TAU;
    let bearing =
        phase + (tick as f32 % HEARD_TURN_TICKS) / HEARD_TURN_TICKS * std::f32::consts::TAU;
    let off = distance * EAR_ERROR;
    [
        target.x + bearing.cos() * off,
        target.y,
        target.z + bearing.sin() * off,
    ]
}

impl Interest {
    fn moved_of(&self, id: Uuid) -> [f32; 3] {
        self.moved.get(&id).copied().unwrap_or([0.0; 3])
    }

    /// Measure how far every fighter's feet moved since the tick before. A
    /// step past 1.5 m is a placement (a spawn), not motion.
    fn measure_motion(&mut self, state: &GameState) {
        self.moved.clear();
        for player in &state.players {
            let now = feet(player);
            if let Some((tick, last)) = self.feet.get(&player.id) {
                let step = [now[0] - last[0], now[1] - last[1], now[2] - last[2]];
                if state.tick == tick + 1 && step.iter().all(|v| v.abs() <= 1.5) {
                    self.moved.insert(player.id, step);
                }
            }
            self.feet.insert(player.id, (state.tick, now));
        }
        self.feet.retain(|_, (tick, _)| *tick == state.tick);
    }

    pub fn counts(&self) -> InterestCounts {
        self.counts
    }

    /// Forget everything: a new round or a new map.
    pub fn clear(&mut self) {
        self.sighted.clear();
        self.heard.clear();
        self.killers.clear();
    }

    /// Note the tick's frags, so a reader that is down keeps its killer.
    pub fn observe<'m>(&mut self, messages: impl IntoIterator<Item = &'m ServerMessage>) {
        for message in messages {
            if let ServerMessage::Event(GameEvent::Frag {
                killer_id: Some(killer),
                victim_id: Some(victim),
                ..
            }) = message
            {
                if killer != victim {
                    self.killers.insert(*victim, *killer);
                }
            }
        }
    }

    /// One perceiver's sense of one living or dead target, updating memory.
    fn perceive(
        &mut self,
        state: &GameState,
        reader: &Player,
        target: &Player,
        lead: f32,
        grid: &crate::combat::SightGrid,
    ) -> Sense {
        let tick = state.tick;
        let key = (reader.id, target.id);
        self.counts.pairs += 1;
        // A body that is down is only ever shown to a reader that just saw
        // it, so the reader watches it fall.
        if !down(state, target)
            && clear_line(
                reader,
                target,
                lead,
                [self.moved_of(reader.id), self.moved_of(target.id)],
                grid,
                &mut self.counts.rays,
            )
        {
            self.sighted.insert(key, tick);
        }
        if self
            .sighted
            .get(&key)
            .is_some_and(|seen| tick.saturating_sub(*seen) <= SEEN_GRACE)
        {
            return Sense::Seen;
        }
        if !down(state, target) && audible(reader, target) {
            self.heard.insert(key, tick);
        }
        if !down(state, target)
            && self
                .heard
                .get(&key)
                .is_some_and(|heard| tick.saturating_sub(*heard) <= HEARD_GRACE)
        {
            return Sense::Heard(heard_at(reader, target, tick));
        }
        Sense::Hidden
    }

    /// Each reader's view of `snapshot`, the world this tick sends. `readers`
    /// are the fighters whose sockets the world goes to. A reader absent from
    /// the result, or with an empty view, sees the whole world.
    pub fn views(
        &mut self,
        state: &GameState,
        snapshot: &Snapshot,
        readers: &[Uuid],
    ) -> HashMap<Uuid, View> {
        let arena = state.current_arena();
        self.views_in(state, snapshot, readers, &arena.solids)
    }

    /// [`Self::views`] through `solids` rather than the live arena's.
    pub fn views_in(
        &mut self,
        state: &GameState,
        snapshot: &Snapshot,
        readers: &[Uuid],
        solids: &[crate::movement::Solid],
    ) -> HashMap<Uuid, View> {
        self.counts = InterestCounts::default();
        let mut views = HashMap::new();
        if readers.is_empty() || state.map.is_campaign() || state.round_state != RoundState::Active
        {
            if state.round_state != RoundState::Active {
                self.clear();
            }
            return views;
        }
        let tick = state.tick;
        self.sighted
            .retain(|_, seen| tick.saturating_sub(*seen) <= SEEN_GRACE);
        self.heard
            .retain(|_, heard| tick.saturating_sub(*heard) <= HEARD_GRACE);
        self.measure_motion(state);
        let key = crate::combat::SightGrid::key_of(solids);
        let grid = match self.grid.take() {
            Some(grid) if grid.key() == key => grid,
            _ => crate::combat::SightGrid::new(solids),
        };
        let teams = state.config.rules.teams();
        let carriers = carriers(snapshot);
        let by_id: HashMap<Uuid, &Player> = state.players.iter().map(|p| (p.id, p)).collect();
        // Bodies back up forget who killed them.
        self.killers
            .retain(|victim, _| by_id.get(victim).is_some_and(|p| down(state, p)));
        let always = |reader: &Player, target: &Player| {
            target.id == reader.id
                || !target.is_participant()
                || (teams && reader.team.is_some() && reader.team == target.team)
                || state.vehicle_seat(target.id).is_some()
                || carriers.contains(&target.id)
        };
        // Who perceives for each reader: itself while up; while down in a
        // team mode, its living team-mates.
        let mut cache: HashMap<Uuid, Vec<Sense>> = HashMap::new();
        for reader_id in readers {
            let Some(reader) = by_id.get(reader_id).copied() else {
                continue;
            };
            let eyes: Vec<&Player> = if teams && down(state, reader) && reader.team.is_some() {
                state
                    .players
                    .iter()
                    .filter(|mate| {
                        mate.id != reader.id
                            && mate.team == reader.team
                            && mate.is_participant()
                            && !down(state, mate)
                    })
                    .collect()
            } else {
                vec![reader]
            };
            let killer = self.killers.get(&reader.id).copied();
            let mut view = View::new();
            let mut senses: Vec<Vec<Sense>> = Vec::with_capacity(eyes.len());
            for perceiver in &eyes {
                if let std::collections::hash_map::Entry::Vacant(slot) = cache.entry(perceiver.id) {
                    let lead = lead_ticks(perceiver.ping_ms);
                    let mut row_senses = Vec::with_capacity(snapshot.players.len());
                    for row in &snapshot.players {
                        let sense = match by_id.get(&row.id) {
                            Some(target) if !always(perceiver, target) => {
                                self.perceive(state, perceiver, target, lead, &grid)
                            }
                            _ => Sense::Seen,
                        };
                        row_senses.push(sense);
                    }
                    slot.insert(row_senses);
                }
                senses.push(cache[&perceiver.id].clone());
            }
            for (index, row) in snapshot.players.iter().enumerate() {
                let Some(target) = by_id.get(&row.id).copied() else {
                    continue;
                };
                if always(reader, target) || killer == Some(row.id) {
                    continue;
                }
                // The best any perceiver has: seen over heard over hidden.
                let mut best = Sense::Hidden;
                for perceived in &senses {
                    match perceived[index] {
                        Sense::Seen => {
                            best = Sense::Seen;
                            break;
                        }
                        heard @ Sense::Heard(_) if best == Sense::Hidden => best = heard,
                        _ => {}
                    }
                }
                if best != Sense::Seen {
                    view.push((index, best));
                }
            }
            self.counts.withheld += view.len() as u64;
            views.insert(reader.id, view);
        }
        self.grid = Some(grid);
        views
    }
}

/// The row a reader receives for a fighter it does not see whole.
pub fn redact(row: &PlayerState, sense: Sense) -> PlayerState {
    let (position, sense) = match sense {
        Sense::Seen => return row.clone(),
        Sense::Heard(at) => (at, PlayerSense::Heard),
        Sense::Hidden => ([0.0; 3], PlayerSense::Hidden),
    };
    PlayerState {
        collidable: false,
        campaign: row.campaign,
        id: row.id,
        name: row.name.clone(),
        x: position[0],
        y: position[1],
        z: position[2],
        yaw: 0.0,
        pitch: 0.0,
        hp: 0,
        armor: 0,
        just_fired: false,
        behavior: None,
        score: row.score,
        deaths: row.deaths,
        attacks: row.attacks,
        connects: row.connects,
        heads: row.heads,
        damage: row.damage,
        weapon: crate::protocol::WeaponType::Fists.name().to_string(),
        team: row.team,
        lives: row.lives,
        golden: row.golden,
        ducking: false,
        airborne: false,
        body: row.body,
        dress: row.dress,
        ping: row.ping,
        sense: Some(sense),
    }
}

/// A view as a key: each withheld row, its sense and where it sounds.
type ViewKey = Vec<(usize, u8, [u32; 3])>;

/// The tick's world as each reader's view, keyed by reader. Readers with
/// the same view share one broadcast; a reader that sees everybody is left
/// out and receives the tick's own broadcast, delta and all.
pub fn encode_views(
    world: &Arc<Broadcast>,
    views: &HashMap<Uuid, View>,
) -> serde_json::Result<HashMap<Uuid, Arc<Broadcast>>> {
    let mut out = HashMap::new();
    let ServerMessage::Snapshot(snapshot) = world.message() else {
        return Ok(out);
    };
    if views.values().all(Vec::is_empty) {
        return Ok(out);
    }
    let text = world.text();
    let Some(spans) = crate::protocol::delta::roster_spans(text) else {
        return Ok(out);
    };
    if spans.entries.len() != snapshot.players.len() {
        return Ok(out);
    }
    let mut hidden: Vec<Option<String>> = vec![None; snapshot.players.len()];
    let mut shared: HashMap<ViewKey, Arc<Broadcast>> = HashMap::new();
    for (reader, view) in views {
        if view.is_empty() {
            continue;
        }
        let key: ViewKey = view
            .iter()
            .map(|(index, sense)| match sense {
                Sense::Heard(at) => (*index, 1, at.map(f32::to_bits)),
                _ => (*index, 0, [0; 3]),
            })
            .collect();
        if let Some(broadcast) = shared.get(&key) {
            out.insert(*reader, Arc::clone(broadcast));
            continue;
        }
        let mut cut = String::with_capacity(text.len());
        cut.push_str(&text[..spans.start]);
        cut.push('[');
        let mut withheld = view.iter().peekable();
        for (index, (from, to)) in spans.entries.iter().enumerate() {
            if index > 0 {
                cut.push(',');
            }
            match withheld.next_if(|(at, _)| *at == index) {
                None => cut.push_str(&text[*from..*to]),
                Some((_, Sense::Hidden)) => {
                    if hidden[index].is_none() {
                        hidden[index] = Some(serde_json::to_string(&redact(
                            &snapshot.players[index],
                            Sense::Hidden,
                        ))?);
                    }
                    cut.push_str(hidden[index].as_deref().unwrap_or_default());
                }
                Some((_, sense)) => {
                    cut.push_str(&serde_json::to_string(&redact(
                        &snapshot.players[index],
                        *sense,
                    ))?);
                }
            }
        }
        cut.push(']');
        cut.push_str(&text[spans.end..]);
        let broadcast = Broadcast::view(world, cut);
        shared.insert(key, Arc::clone(&broadcast));
        out.insert(*reader, broadcast);
    }
    Ok(out)
}

#[cfg(test)]
mod tests;
