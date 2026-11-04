//! Per-recipient interest: a fighter's socket carries only what that fighter
//! could perceive (fair play, gameplay 66 for the roster, 67 for shots, throws and pickups).
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
//! - From the reader's eye, and standing if it crouches (rising is a peek), from
//!   that eye after its lead ([`lead_ticks`]: five ticks plus the measured
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
//! `localexception-playtest --interest-survey` measures how often a body still turns
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
//! **The rest of the world follows the same senses** (gameplay 67). A shot
//! result from a fighter the reader sees stays whole; from one it only
//! hears it keeps its hit facts and gun but says it was heard, its trace
//! cut to the place the shooter sounds (no line, no pellets); from one it
//! neither sees nor hears it is not sent. A rocket, grenade or mine in
//! flight from a fighter the reader does not see is sent only while a line
//! from the reader's eye reaches it (kept [`SEEN_GRACE`] after). A pickup
//! event for a fighter the reader does not see is not sent, except the
//! Custody Plate, which the whole venue answers. The reader's own shots,
//! the shots that strike it, everything about team-mates, the kill feed,
//! the board, explosions, stuck mines, vehicles, pads, flags and the
//! charge stay in every world.

use crate::net::Broadcast;
use crate::protocol::{
    GameEvent, PlayerSense, PlayerState, ServerMessage, ShotImpact, ShotResult, ShotTrace, Snapshot,
};
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
/// and three ticks of slack for a world held up on a jittery link.
pub const LEAD_BASE_TICKS: f32 = 5.0;
/// The longest lead a slow link earns, ticks (500 ms).
pub const LEAD_MAX_TICKS: f32 = 10.0;
/// The furthest the reader's eye is tested across the line, metres: a full
/// speed step over a long lead.
pub const EYE_REACH: f32 = 2.0;
/// How far ahead a target is tested, ticks.
pub const TARGET_LEAD_TICKS: f32 = 3.0;
/// Threads that trace lines of sight, at most.
const TRACE_THREADS: usize = 8;
/// Below this many questions a thread is not worth starting.
const TRACES_PER_THREAD: usize = 128;
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

/// A thing in flight a reader may be denied: which list holds it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Thing {
    Rocket,
    Grenade,
    Mine,
    RemoteMine,
}

impl Thing {
    /// The snapshot key of its list.
    pub fn key(self) -> &'static str {
        match self {
            Self::Rocket => "rockets",
            Self::Grenade => "grenades",
            Self::Mine => "mines",
            Self::RemoteMine => "remote_mines",
        }
    }
}

/// What a reader's world leaves out of the tick's world. Empty when the
/// reader sees everybody, so it shares the tick's broadcast.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct View {
    /// Roster rows not seen whole, by index, in roster order.
    pub rows: Vec<(usize, Sense)>,
    /// Shot results from a fighter the reader does not see, by index in
    /// order: `Heard` is sent cut to where it sounds, `Hidden` not at all.
    pub shots: Vec<(usize, Sense)>,
    /// Things in flight the reader cannot see from a fighter it does not
    /// see, by list and index in order: not sent.
    pub things: Vec<(Thing, usize)>,
}

impl View {
    /// Event-specific hearing does not reveal a hidden body or its equipment.
    /// Downed team readers hear from the same living seats whose eyes they ride.
    pub fn handling_event(
        &self,
        state: &GameState,
        snapshot: &Snapshot,
        reader_id: Uuid,
        message: &ServerMessage,
    ) -> Option<ServerMessage> {
        let ServerMessage::Event(GameEvent::WeaponHandling {
            player_id,
            tick,
            kind,
            position,
        }) = message
        else {
            return None;
        };
        let reader = state.players.iter().find(|p| p.id == reader_id)?;
        let target = state.players.iter().find(|p| p.id == *player_id)?;
        let ears = eyes_of(state, reader, state.config.rules.teams());
        let ear = ears
            .into_iter()
            .filter_map(|ear| {
                let at = feet(ear);
                let distance = (at[0] - position[0])
                    .hypot(at[1] - position[1])
                    .hypot(at[2] - position[2]);
                (distance <= crate::protocol::HANDLING_REACH).then_some((ear, distance))
            })
            .min_by(|a, b| a.1.total_cmp(&b.1))?
            .0;
        let position = if self.withholds(snapshot, *player_id) {
            let mut at = heard_at(ear, target, *tick);
            at[1] -= crate::sim::PLAYER_FLOOR_Y;
            at
        } else {
            *position
        };
        Some(ServerMessage::Event(GameEvent::WeaponHandling {
            player_id: *player_id,
            tick: *tick,
            kind: *kind,
            position,
        }))
    }

    pub fn is_empty(&self) -> bool {
        self.rows.is_empty() && self.shots.is_empty() && self.things.is_empty()
    }

    /// Whether this view withholds the fighter `id` of `snapshot`.
    pub fn withholds(&self, snapshot: &Snapshot, id: Uuid) -> bool {
        self.rows
            .iter()
            .any(|(index, _)| snapshot.players.get(*index).is_some_and(|row| row.id == id))
    }

    /// Whether `message`, one of the tick's events, stays out of this
    /// reader's socket: a pickup by a fighter it does not see, except the
    /// Custody Plate the venue answers for everyone.
    pub fn mutes(&self, snapshot: &Snapshot, message: &ServerMessage) -> bool {
        match message {
            ServerMessage::Event(GameEvent::Pickup {
                player_id, kind, ..
            }) => kind != "plate" && self.withholds(snapshot, *player_id),
            _ => false,
        }
    }
}

/// Counters for the measurements (`bench`, `localexception-playtest --interest`).
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
    /// Things in flight each reader last had a line to, by list and id.
    things_seen: HashMap<(Uuid, Thing, u32), u64>,
}

/// A thing in flight from the world being sent: list, index, id, owner,
/// where it is and where it is headed per tick.
struct Flying {
    thing: Thing,
    index: usize,
    id: u32,
    owner: Uuid,
    at: [f32; 3],
    step: [f32; 3],
}

/// The world's things in flight, in list order. A stuck mine is not in
/// flight: it no longer says where its owner stands.
fn flying(snapshot: &Snapshot) -> Vec<Flying> {
    let mut out = Vec::new();
    for (index, rocket) in snapshot.rockets.iter().enumerate() {
        out.push(Flying {
            thing: Thing::Rocket,
            index,
            id: rocket.id,
            owner: rocket.owner_id,
            at: rocket.position,
            step: rocket.velocity.map(|v| v * TICK_SECONDS),
        });
    }
    for (index, grenade) in snapshot.grenades.iter().enumerate() {
        out.push(Flying {
            thing: Thing::Grenade,
            index,
            id: grenade.id,
            owner: grenade.owner_id,
            at: grenade.position,
            step: [0.0; 3],
        });
    }
    for (index, mine) in snapshot.mines.iter().enumerate() {
        if mine.phase == crate::protocol::MinePhase::Flying {
            out.push(Flying {
                thing: Thing::Mine,
                index,
                id: mine.id,
                owner: mine.owner_id,
                at: mine.position,
                step: [0.0; 3],
            });
        }
    }
    for (index, mine) in snapshot.remote_mines.iter().enumerate() {
        if mine.phase == crate::protocol::RemoteMinePhase::Flying {
            out.push(Flying {
                thing: Thing::RemoteMine,
                index,
                id: mine.id,
                owner: mine.owner_id,
                at: mine.position,
                step: [0.0; 3],
            });
        }
    }
    out
}

/// Whether a line from `perceiver`'s eye, now or after its lead, reaches a
/// thing in flight where it is or [`TARGET_LEAD_TICKS`] ahead.
fn sees_thing(
    perceiver: &Player,
    thing: &Flying,
    moved: [f32; 3],
    grid: &crate::combat::SightGrid,
    rays: &mut u64,
) -> bool {
    let mut eye_now = eye(perceiver);
    eye_now[1] =
        eye_now[1].max(feet(perceiver)[1] + crate::combat::stance_eye(perceiver.campaign, false));
    let eye_lead = ahead(eye_now, perceiver, lead_ticks(perceiver.ping_ms), moved);
    let later = [
        thing.at[0] + thing.step[0] * TARGET_LEAD_TICKS,
        thing.at[1] + thing.step[1] * TARGET_LEAD_TICKS,
        thing.at[2] + thing.step[2] * TARGET_LEAD_TICKS,
    ];
    for eye in [eye_now, eye_lead] {
        for point in [thing.at, later] {
            *rays += 1;
            if grid.line_of_sight(eye, point) {
                return true;
            }
        }
    }
    false
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

/// Who perceives for a reader: itself while up; while it is down in a team
/// mode, its living team-mates, whose eyes the team seat rides.
fn eyes_of<'a>(state: &'a GameState, reader: &'a Player, teams: bool) -> Vec<&'a Player> {
    if teams && down(state, reader) && reader.team.is_some() {
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
    }
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
    // The reader's eye where it is, and standing: rising from a crouch is a
    // peek too, and a crouch under a low roof sees what standing cannot.
    let crouched = eye(reader);
    let mut eye_now = crouched;
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
    let across_by =
        |point: [f32; 3], by: f32| [point[0] + side_x * by, point[1], point[2] + side_z * by];
    // Where the reader's client may have put its eye by the time this world
    // is drawn: along its motion and one step higher (a stair taken), or a
    // step either way across the line (a turn, or a start from rest).
    let mut eye_lead = ahead(eye_now, reader, lead, moved[0]);
    if reader.vx.hypot(reader.vz) > 1.0 {
        eye_lead[1] += crate::movement::STEP_UP;
    }
    let step = (crate::movement::TOP_SPEED * lead * TICK_SECONDS).min(EYE_REACH);
    let stand = crate::combat::stance_eye(target.campaign, target.ducking);
    let reach = crate::movement::RADIUS + PEEK_MARGIN;
    let chest =
        |body: [f32; 3]| crate::combat::aim_point_for(body, target.campaign, target.ducking);
    let shoulder = |body: [f32; 3]| [body[0], body[1] + SHOULDER.min(stand), body[2]];
    let crown = [feet_now[0], feet_now[1] + stand + CROWN, feet_now[2]];
    let (now, ahead_of) = (shoulder(feet_now), shoulder(feet_lead));
    // The body as it stands, its own shoulders as well as widened ones: a
    // thin post can hide one line and not the other.
    let whole = [
        chest(feet_now),
        crown,
        across_by(now, crate::movement::RADIUS),
        across_by(now, -crate::movement::RADIUS),
        across_by(now, reach),
        across_by(now, -reach),
        chest(feet_lead),
        across_by(ahead_of, reach),
        across_by(ahead_of, -reach),
    ];
    // The eyes across the line look for the body itself, not its margins.
    let core = [chest(feet_now), crown, chest(feet_lead)];
    let low = (crouched != eye_now).then_some(crouched);
    let lines = [Some(eye_now), Some(eye_lead), low]
        .into_iter()
        .flatten()
        .flat_map(|eye| whole.iter().map(move |point| (eye, *point)))
        .chain([step, -step].into_iter().flat_map(|by| {
            let eye = across_by(eye_now, by);
            core.iter().map(move |point| (eye, *point))
        }));
    for (eye, point) in lines {
        *rays += 1;
        if grid.line_of_sight(eye, point) {
            return true;
        }
    }
    false
}

/// One line-of-sight question: may `reader` see `target` this tick.
struct Trace<'a> {
    reader: &'a Player,
    target: &'a Player,
    lead: f32,
    moved: [[f32; 3]; 2],
}

/// Every question answered, across the machine's cores when there are many:
/// the answers are pure functions of the world, so the order is free and
/// the result is the same as one thread's.
fn trace_all(traces: &[Trace<'_>], grid: &crate::combat::SightGrid) -> (Vec<bool>, u64) {
    let run = |chunk: &[Trace<'_>]| {
        let mut rays = 0;
        let answers = chunk
            .iter()
            .map(|t| clear_line(t.reader, t.target, t.lead, t.moved, grid, &mut rays))
            .collect::<Vec<bool>>();
        (answers, rays)
    };
    let threads = std::thread::available_parallelism()
        .map_or(1, usize::from)
        .min(TRACE_THREADS);
    if threads <= 1 || traces.len() < TRACES_PER_THREAD * 2 {
        return run(traces);
    }
    let size = traces.len().div_ceil(threads).max(TRACES_PER_THREAD);
    std::thread::scope(|scope| {
        let handles: Vec<_> = traces
            .chunks(size)
            .map(|chunk| scope.spawn(move || run(chunk)))
            .collect();
        let mut answers = Vec::with_capacity(traces.len());
        let mut rays = 0;
        for handle in handles {
            // A tracing thread only reads; if one ever panicked, its pairs
            // count as clear, which shows more rather than less.
            let (part, counted) = handle.join().unwrap_or_else(|_| (vec![true; size], 0));
            answers.extend(part);
            rays += counted;
        }
        answers.truncate(traces.len());
        (answers, rays)
    })
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

    /// The shots and things in flight `reader` is denied, given the rows its
    /// view already withholds: a shot or a throw says where its fighter is.
    #[allow(clippy::too_many_arguments)]
    fn cut_the_rest(
        &mut self,
        state: &GameState,
        snapshot: &Snapshot,
        reader: &Player,
        eyes: &[&Player],
        things: &[Flying],
        grid: &crate::combat::SightGrid,
        view: &mut View,
    ) {
        let sense_of = |id: Uuid| {
            view.rows.iter().find_map(|(index, sense)| {
                (snapshot.players.get(*index).map(|row| row.id) == Some(id)).then_some(*sense)
            })
        };
        let mut shots = Vec::new();
        for (index, shot) in snapshot.shot_results.iter().enumerate() {
            // The reader's own shots and the ones that strike it stay whole.
            if shot.target_id == Some(reader.id) {
                continue;
            }
            if let Some(sense) = sense_of(shot.shooter_id) {
                shots.push((index, sense));
            }
        }
        let mut denied = Vec::new();
        let mut rays = 0;
        for thing in things {
            if sense_of(thing.owner).is_none() {
                continue;
            }
            let key = (reader.id, thing.thing, thing.id);
            let seen = eyes.iter().any(|perceiver| {
                sees_thing(
                    perceiver,
                    thing,
                    self.moved_of(perceiver.id),
                    grid,
                    &mut rays,
                )
            });
            if seen {
                self.things_seen.insert(key, state.tick);
            } else if !self.things_seen.contains_key(&key) {
                denied.push((thing.thing, thing.index));
            }
        }
        denied.sort_unstable();
        self.counts.rays += rays;
        view.shots = shots;
        view.things = denied;
    }

    pub fn counts(&self) -> InterestCounts {
        self.counts
    }

    /// Forget everything: a new round or a new map.
    pub fn clear(&mut self) {
        self.sighted.clear();
        self.heard.clear();
        self.killers.clear();
        self.things_seen.clear();
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
        clear: bool,
    ) -> Sense {
        let tick = state.tick;
        let key = (reader.id, target.id);
        self.counts.pairs += 1;
        if clear {
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
        self.things_seen
            .retain(|_, seen| tick.saturating_sub(*seen) <= SEEN_GRACE);
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
        // Every line this tick needs, traced at once. A body that is down is
        // never traced: only a reader that just saw it keeps it, and watches
        // it fall.
        let mut perceivers: Vec<&Player> = Vec::new();
        for reader in readers.iter().filter_map(|id| by_id.get(id).copied()) {
            for eye in eyes_of(state, reader, teams) {
                if !perceivers.iter().any(|known| known.id == eye.id) {
                    perceivers.push(eye);
                }
            }
        }
        let mut traces = Vec::new();
        for perceiver in &perceivers {
            let lead = lead_ticks(perceiver.ping_ms);
            for row in &snapshot.players {
                if let Some(target) = by_id.get(&row.id).copied() {
                    if !always(perceiver, target) && !down(state, target) {
                        traces.push(Trace {
                            reader: perceiver,
                            target,
                            lead,
                            moved: [self.moved_of(perceiver.id), self.moved_of(target.id)],
                        });
                    }
                }
            }
        }
        let (answers, rays) = trace_all(&traces, &grid);
        self.counts.rays += rays;
        let clear: std::collections::HashSet<(Uuid, Uuid)> = traces
            .iter()
            .zip(answers)
            .filter(|(_, clear)| *clear)
            .map(|(trace, _)| (trace.reader.id, trace.target.id))
            .collect();
        let mut cache: HashMap<Uuid, Vec<Sense>> = HashMap::new();
        let things = flying(snapshot);
        for reader_id in readers {
            let Some(reader) = by_id.get(reader_id).copied() else {
                continue;
            };
            let eyes = eyes_of(state, reader, teams);
            let killer = self.killers.get(&reader.id).copied();
            let mut view = View::default();
            let mut senses: Vec<Vec<Sense>> = Vec::with_capacity(eyes.len());
            for perceiver in &eyes {
                if let std::collections::hash_map::Entry::Vacant(slot) = cache.entry(perceiver.id) {
                    let mut row_senses = Vec::with_capacity(snapshot.players.len());
                    for row in &snapshot.players {
                        let sense = match by_id.get(&row.id) {
                            Some(target) if !always(perceiver, target) => self.perceive(
                                state,
                                perceiver,
                                target,
                                clear.contains(&(perceiver.id, target.id)),
                            ),
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
                    view.rows.push((index, best));
                }
            }
            if !view.rows.is_empty() {
                self.cut_the_rest(state, snapshot, reader, &eyes, &things, &grid, &mut view);
            }
            self.counts.withheld += view.rows.len() as u64;
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
        // Objective credits are scoreboard facts, like frags: they say nothing
        // about where the fighter is.
        objective: row.objective,
        sense: Some(sense),
    }
}

/// The shot result a reader receives from a fighter it only hears: the hit
/// facts and the gun, its trace cut to the place the shooter sounds, with no
/// line, no impact and no pellets to trace back to the muzzle.
pub fn coarsen(shot: &ShotResult, at: [f32; 3]) -> ShotResult {
    let mut cut = shot.clone();
    cut.sense = Some(PlayerSense::Heard);
    cut.trace = shot.trace.as_ref().map(|trace| ShotTrace {
        vehicle_id: trace.vehicle_id,
        weapon: trace.weapon,
        origin: at,
        end: at,
        impact: ShotImpact::Range,
        pellets: Vec::new(),
    });
    cut
}

/// A sense as a key: heard with where it sounds, or hidden.
fn sense_key(index: usize, sense: &Sense) -> (usize, u8, [u32; 3]) {
    match sense {
        Sense::Heard(at) => (index, 1, at.map(f32::to_bits)),
        _ => (index, 0, [0; 3]),
    }
}

/// A view as a key: each withheld row and shot, its sense and where it
/// sounds, and each thing left out.
type ViewKey = (
    Vec<(usize, u8, [u32; 3])>,
    Vec<(usize, u8, [u32; 3])>,
    Vec<(Thing, usize)>,
);

/// The lists a view cuts, in the order [`encode_views`] reads their spans.
const LISTS: [&str; 6] = [
    "players",
    "shot_results",
    "rockets",
    "grenades",
    "mines",
    "remote_mines",
];
const THINGS: [Thing; 4] = [
    Thing::Rocket,
    Thing::Grenade,
    Thing::Mine,
    Thing::RemoteMine,
];

/// A list's text with some entries replaced or left out: `entry` answers
/// `None` to keep an entry's own text, `Some(None)` to leave it out and
/// `Some(Some(text))` to send that instead.
fn relist(
    text: &str,
    spans: &crate::protocol::delta::RosterSpans,
    mut entry: impl FnMut(usize) -> serde_json::Result<Option<Option<String>>>,
) -> serde_json::Result<String> {
    let mut out = String::with_capacity(spans.end - spans.start);
    out.push('[');
    let mut first = true;
    for (index, (from, to)) in spans.entries.iter().enumerate() {
        let swapped = entry(index)?;
        if matches!(swapped, Some(None)) {
            continue;
        }
        if !first {
            out.push(',');
        }
        first = false;
        match swapped {
            Some(Some(text)) => out.push_str(&text),
            _ => out.push_str(&text[*from..*to]),
        }
    }
    out.push(']');
    Ok(out)
}

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
    if views.values().all(View::is_empty) {
        return Ok(out);
    }
    let text = world.text();
    let Some(spans) = crate::protocol::delta::list_spans(text, &LISTS) else {
        return Ok(out);
    };
    let lengths = [
        snapshot.players.len(),
        snapshot.shot_results.len(),
        snapshot.rockets.len(),
        snapshot.grenades.len(),
        snapshot.mines.len(),
        snapshot.remote_mines.len(),
    ];
    // Every list's text must line up with the world it was encoded from; the
    // roster is never empty in a world worth cutting.
    let lined_up = spans.iter().zip(lengths).all(|(span, length)| {
        span.as_ref()
            .map_or(length == 0, |span| span.entries.len() == length)
    });
    let Some(roster) = spans[0].as_ref().filter(|_| lined_up) else {
        return Ok(out);
    };
    let mut hidden: Vec<Option<String>> = vec![None; snapshot.players.len()];
    let mut shared: HashMap<ViewKey, Arc<Broadcast>> = HashMap::new();
    for (reader, view) in views {
        if view.is_empty() {
            continue;
        }
        let key: ViewKey = (
            view.rows
                .iter()
                .map(|(i, sense)| sense_key(*i, sense))
                .collect(),
            view.shots
                .iter()
                .map(|(i, sense)| sense_key(*i, sense))
                .collect(),
            view.things.clone(),
        );
        if let Some(broadcast) = shared.get(&key) {
            out.insert(*reader, Arc::clone(broadcast));
            continue;
        }
        // Each cut list as (start, end, new text), in text order.
        let mut edits: Vec<(usize, usize, String)> = Vec::new();
        if !view.rows.is_empty() {
            let list = relist(text, roster, |index| {
                let Some((_, sense)) = view.rows.iter().find(|(at, _)| *at == index) else {
                    return Ok(None);
                };
                let row = &snapshot.players[index];
                Ok(Some(Some(match sense {
                    Sense::Hidden => {
                        if hidden[index].is_none() {
                            hidden[index] =
                                Some(serde_json::to_string(&redact(row, Sense::Hidden))?);
                        }
                        hidden[index].clone().unwrap_or_default()
                    }
                    _ => serde_json::to_string(&redact(row, *sense))?,
                })))
            })?;
            edits.push((roster.start, roster.end, list));
        }
        if let (false, Some(span)) = (view.shots.is_empty(), spans[1].as_ref()) {
            let list = relist(text, span, |index| {
                Ok(match view.shots.iter().find(|(at, _)| *at == index) {
                    None => None,
                    Some((_, Sense::Heard(at))) => Some(Some(serde_json::to_string(&coarsen(
                        &snapshot.shot_results[index],
                        *at,
                    ))?)),
                    Some(_) => Some(None),
                })
            })?;
            edits.push((span.start, span.end, list));
        }
        for (thing, span) in THINGS.iter().zip(&spans[2..]) {
            let Some(span) = span else { continue };
            if !view.things.iter().any(|(kind, _)| kind == thing) {
                continue;
            }
            let list = relist(text, span, |index| {
                Ok(view.things.contains(&(*thing, index)).then_some(None))
            })?;
            edits.push((span.start, span.end, list));
        }
        edits.sort_unstable_by_key(|(start, _, _)| *start);
        let mut cut = String::with_capacity(text.len());
        let mut at = 0;
        for (start, end, list) in &edits {
            cut.push_str(&text[at..*start]);
            cut.push_str(list);
            at = *end;
        }
        cut.push_str(&text[at..]);
        let broadcast = Broadcast::view(world, cut);
        shared.insert(key, Arc::clone(&broadcast));
        out.insert(*reader, broadcast);
    }
    Ok(out)
}

#[cfg(test)]
mod tests;
