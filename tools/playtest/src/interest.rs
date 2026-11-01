//! Pop-in at corners under interest filtering (gameplay 66, wave 22).
//!
//! In-process and seeded: rule bots fight a free-for-all on each map while
//! every bot is treated as a connected reader at a modelled round trip (its
//! `ping_ms`, which the server's lead reads). Each tick the survey asks what
//! that reader's client would draw and whether it should:
//!
//! - The client's clock runs one way behind the server, so at server tick
//!   `t` it is showing time `t - L`, `L` the one-way delay in ticks.
//! - Its own eye is predicted: where the server will put the reader once
//!   its inputs arrive, which is the reader's position at `t`.
//! - Other fighters are drawn from the interpolation buffer, `B` ticks
//!   behind the newest world it holds: the world of tick `t - 2L - B`.
//! - **Should be visible:** a line from that eye to any part of the target
//!   as drawn (chest, crown, either shoulder at the body radius, no margin).
//! - **Drawn:** the target's row in that reader's world of the drawn tick
//!   was seen whole.
//!
//! A *late reveal* is a pair turning visible while its drawn row was still
//! withheld: the body pops in. The rate is late reveals per reveal. Withheld
//! is the share of other-fighter rows a reader's worlds left out, the
//! protection a modified client loses.
//!
//! What it is not: real sockets or a real link (`--peek-probe` measures
//! those for the peek), and rule bots rather than people. Optional jitter
//! moves each world's arrival by up to `jitter` ticks, which the buffer must
//! absorb as on a real link.

use fragr_server::combat::{aim_point_for, line_of_sight, stance_eye};
use fragr_server::interest::{Interest, Sense};
use fragr_server::movement::Solid;
use fragr_server::protocol::{GameMode, ServerMessage};
use fragr_server::rules::RuleSet;
use fragr_server::session::GameSession;
use fragr_server::sim::{MapKind, MatchConfig, Player, PLAYER_FLOOR_Y};
use serde::Serialize;
use std::collections::{HashMap, HashSet, VecDeque};
use uuid::Uuid;

/// The round trips measured by default, milliseconds.
pub const RTTS_MS: [u32; 4] = [0, 50, 100, 150];
/// The interpolation buffer, ticks: the wave 21 adaptive buffer's widest
/// (100 ms), which is the latest a body is drawn.
pub const BUFFER_TICKS: u64 = 2;
/// Rule bots per match.
pub const BOTS: usize = 8;
/// A rule bot's default sight, metres (`sim::bot_skill`): past it a body is a
/// few pixels and the reveal is reported apart.
pub const FIGHT_RANGE: f32 = 64.0;
/// Fail `--assert` above this late-reveal rate at 100 ms or less.
pub const LATE_RATE_LIMIT: f64 = 0.01;

#[derive(Debug, Clone, Serialize)]
pub struct Row {
    pub map: String,
    pub rtt_ms: u32,
    pub jitter_ticks: u64,
    pub ticks: u64,
    /// Reader and target pairs that turned visible.
    pub reveals: u64,
    /// Of those, the ones drawn late: popped in.
    pub late_reveals: u64,
    pub late_rate: f64,
    /// The same, for bodies within [`FIGHT_RANGE`]: where a fight is.
    pub fight_reveals: u64,
    pub fight_late_reveals: u64,
    pub fight_late_rate: f64,
    /// The longest a late reveal stayed undrawn, ticks.
    pub late_max_ticks: u64,
    /// Visible observations whose row was withheld, of all visible ones.
    pub missed_share: f64,
    /// Other-fighter rows withheld from readers' worlds.
    pub withheld_share: f64,
    /// Rows sent whole while no line reached the body: what a modified
    /// client still learns through walls, the cost of the margins.
    pub sent_unseen_share: f64,
    pub heard_share: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Report {
    pub schema_version: u32,
    pub seed: u64,
    pub bots: usize,
    pub buffer_ticks: u64,
    pub rows: Vec<Row>,
}

#[derive(Clone, Copy)]
struct Body {
    feet: [f32; 3],
    ducking: bool,
    alive: bool,
}

fn body(player: &Player) -> Body {
    Body {
        feet: [player.x, player.y - PLAYER_FLOOR_Y, player.z],
        ducking: player.ducking,
        alive: player.hp > 0 && player.respawn_timer.is_none() && !player.eliminated,
    }
}

/// Whether any part of `target` is in line from `eye`.
fn any_part(eye: [f32; 3], target: Body, solids: &[Solid]) -> bool {
    let dx = target.feet[0] - eye[0];
    let dz = target.feet[2] - eye[2];
    let across = dx.hypot(dz).max(1e-3);
    let (sx, sz) = (-dz / across, dx / across);
    let radius = fragr_server::movement::RADIUS;
    let stand = stance_eye(None, target.ducking);
    let f = target.feet;
    let shoulder = f[1] + 1.4_f32.min(stand);
    [
        aim_point_for(f, None, target.ducking),
        [f[0], f[1] + stand + 0.2, f[2]],
        [f[0] + sx * radius, shoulder, f[2] + sz * radius],
        [f[0] - sx * radius, shoulder, f[2] - sz * radius],
    ]
    .into_iter()
    .any(|point| line_of_sight(eye, point, solids))
}

/// Ticks a body must have been alive and in place before a reveal counts.
const SETTLE: usize = 3;

/// Alive at every tick in `from..=to` with no step over 3 m between them.
fn steady(bodies: &VecDeque<HashMap<Uuid, Body>>, id: &Uuid, from: usize, to: usize) -> bool {
    let mut last: Option<[f32; 3]> = None;
    for tick in bodies.range(from..=to) {
        let Some(body) = tick.get(id).filter(|b| b.alive) else {
            return false;
        };
        if last.is_some_and(|at| (at[0] - body.feet[0]).hypot(at[2] - body.feet[2]) > 3.0) {
            return false;
        }
        last = Some(body.feet);
    }
    true
}

#[derive(Default)]
struct Tally {
    ticks: u64,
    reveals: u64,
    late: u64,
    near_reveals: u64,
    near_late: u64,
    late_max: u64,
    visible: u64,
    missed: u64,
    rows: u64,
    withheld: u64,
    heard: u64,
    sent_unseen: u64,
}

fn run_one(map: MapKind, rtt_ms: u32, jitter: u64, seconds: u32, seed: u64) -> Option<Row> {
    let mut session = GameSession::with_map(map, false);
    session.state.use_replay_ids();
    session.state.seed(seed);
    let rules = RuleSet::new(GameMode::Ffa, &[], false).ok()?;
    let ticks = u64::from(seconds) * 20;
    session.state.apply_config(MatchConfig {
        frag_limit: None,
        capture_limit: None,
        time_limit_ticks: Some(ticks as u32 + 400),
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        rules,
        ..MatchConfig::default()
    });
    session.spawn_bots(BOTS);
    let solids = map.solids();
    let one_way = (u64::from(rtt_ms) + 50) / 100;
    let delay = 2 * one_way + BUFFER_TICKS;
    let mut interest = Interest::default();
    // Per tick, newest last: bodies and each reader's drawn set.
    let mut bodies: VecDeque<HashMap<Uuid, Body>> = VecDeque::new();
    let mut drawn: VecDeque<HashMap<Uuid, HashSet<Uuid>>> = VecDeque::new();
    let mut was_visible: HashSet<(Uuid, Uuid)> = HashSet::new();
    // Pairs in a late reveal, with the tick it began.
    let mut popping: HashMap<(Uuid, Uuid), u64> = HashMap::new();
    let mut tally = Tally::default();
    let mut jitter_state = seed | 1;
    for tick in 0..ticks + delay + jitter {
        for player in &mut session.state.players {
            player.ping_ms = Some(rtt_ms as u16);
        }
        let messages = session.tick_messages(0.05);
        let Some(snapshot) = messages.iter().find_map(|m| match m {
            ServerMessage::Snapshot(s) => Some(s.clone()),
            _ => None,
        }) else {
            continue;
        };
        interest.observe(messages.iter());
        let readers: Vec<Uuid> = session.state.players.iter().map(|p| p.id).collect();
        let views = interest.views(&session.state, &snapshot, &readers);
        let mut sets = HashMap::new();
        for reader in &readers {
            let mut set: HashSet<Uuid> = snapshot.players.iter().map(|row| row.id).collect();
            if let Some(view) = views.get(reader) {
                for (index, sense) in view {
                    set.remove(&snapshot.players[*index].id);
                    tally.withheld += 1;
                    tally.heard += u64::from(matches!(sense, Sense::Heard(_)));
                }
            }
            tally.rows += snapshot.players.len().saturating_sub(1) as u64;
            sets.insert(*reader, set);
        }
        drawn.push_back(sets);
        bodies.push_back(
            session
                .state
                .players
                .iter()
                .map(|p| (p.id, body(p)))
                .collect(),
        );
        // A world may arrive up to `jitter` ticks late; the buffer then draws
        // an older one.
        jitter_state = jitter_state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        let late = if jitter == 0 {
            0
        } else {
            (jitter_state >> 33) % (jitter + 1)
        };
        let back = (delay + late) as usize;
        if bodies.len() <= back + SETTLE
            || session.state.round_state != fragr_server::sim::RoundState::Active
        {
            continue;
        }
        while bodies.len() > back + jitter as usize + SETTLE + 1 {
            bodies.pop_front();
            drawn.pop_front();
        }
        let index = bodies.len() - 1 - back;
        let now = &bodies[bodies.len() - 1];
        let then = &bodies[index];
        let shown = &drawn[index];
        tally.ticks += 1;
        for reader in &readers {
            let Some(me) = now.get(reader).filter(|b| b.alive) else {
                continue;
            };
            // A body that just spawned or was moved appears wherever it is:
            // that is a spawn, not a corner, for reader and target alike.
            if !steady(&bodies, reader, index - SETTLE, bodies.len() - 1) {
                continue;
            }
            let eye = [
                me.feet[0],
                me.feet[1] + stance_eye(None, me.ducking),
                me.feet[2],
            ];
            for (target, at) in then.iter().filter(|(id, b)| {
                *id != reader && b.alive && steady(&bodies, id, index - SETTLE, index)
            }) {
                let key = (*reader, *target);
                let visible = any_part(eye, *at, &solids);
                let sent = shown.get(reader).is_some_and(|set| set.contains(target));
                let near = (eye[0] - at.feet[0]).hypot(eye[2] - at.feet[2]) <= FIGHT_RANGE;
                if visible {
                    tally.visible += 1;
                    tally.missed += u64::from(!sent);
                    if !was_visible.contains(&key) {
                        tally.reveals += 1;
                        tally.near_reveals += u64::from(near);
                        if !sent {
                            tally.late += 1;
                            tally.near_late += u64::from(near);
                            popping.insert(key, tick);
                        }
                    }
                    was_visible.insert(key);
                } else {
                    was_visible.remove(&key);
                    tally.sent_unseen += u64::from(sent);
                }
                // A late reveal lasts until the row is drawn or the body is
                // out of sight again.
                if sent || !visible {
                    if let Some(began) = popping.remove(&key) {
                        tally.late_max = tally.late_max.max(tick - began);
                    }
                }
            }
        }
    }
    let share = |part: u64, whole: u64| {
        if whole == 0 {
            0.0
        } else {
            part as f64 / whole as f64
        }
    };
    let invisible = tally.rows.saturating_sub(tally.visible);
    Some(Row {
        map: map.name().to_string(),
        rtt_ms,
        jitter_ticks: jitter,
        ticks: tally.ticks,
        reveals: tally.reveals,
        late_reveals: tally.late,
        late_rate: share(tally.late, tally.reveals),
        fight_reveals: tally.near_reveals,
        fight_late_reveals: tally.near_late,
        fight_late_rate: share(tally.near_late, tally.near_reveals),
        late_max_ticks: tally.late_max,
        missed_share: share(tally.missed, tally.visible),
        withheld_share: share(tally.withheld, tally.rows),
        sent_unseen_share: share(tally.sent_unseen, invisible.max(1)),
        heard_share: share(tally.heard, tally.rows),
    })
}

/// Every map at every round trip, seeded.
pub fn run(maps: &[MapKind], rtts: &[u32], jitter: u64, seconds: u32, seed: u64) -> Report {
    let rows = maps
        .iter()
        .flat_map(|map| {
            rtts.iter()
                .filter_map(move |rtt| run_one(*map, *rtt, jitter, seconds, seed))
        })
        .collect();
    Report {
        schema_version: 1,
        seed,
        bots: BOTS,
        buffer_ticks: BUFFER_TICKS,
        rows,
    }
}

/// `--assert`: at each round trip of 100 ms or less, all maps together pop
/// in no more than [`LATE_RATE_LIMIT`] of their reveals within fight range.
/// A small map's few reveals make its own rate noisy, so the gate is the
/// pooled rate; every map's row stays in the table.
pub fn check(report: &Report) -> Vec<String> {
    let mut rtts: Vec<u32> = report.rows.iter().map(|row| row.rtt_ms).collect();
    rtts.sort_unstable();
    rtts.dedup();
    rtts.into_iter()
        .filter(|rtt| *rtt <= 100)
        .filter_map(|rtt| {
            let rows = report.rows.iter().filter(|row| row.rtt_ms == rtt);
            let (late, reveals) = rows.fold((0, 0), |(late, reveals), row| {
                (late + row.fight_late_reveals, reveals + row.fight_reveals)
            });
            let rate = if reveals == 0 { 0.0 } else { late as f64 / reveals as f64 };
            (rate > LATE_RATE_LIMIT).then(|| {
                format!(
                    "at {rtt} ms: {late} of {reveals} reveals within {FIGHT_RANGE} m late ({:.2} %)",
                    rate * 100.0
                )
            })
        })
        .collect()
}

pub fn table(report: &Report) -> String {
    let mut out = String::from(
        "map | rtt ms | jitter | reveals | late | late % | fight reveals | fight late | fight late % | late max ticks | missed % | withheld % | heard % | sent unseen %\n",
    );
    for row in &report.rows {
        out.push_str(&format!(
            "{} | {} | {} | {} | {} | {:.2} | {} | {} | {:.2} | {} | {:.3} | {:.1} | {:.1} | {:.1}\n",
            row.map,
            row.rtt_ms,
            row.jitter_ticks,
            row.reveals,
            row.late_reveals,
            row.late_rate * 100.0,
            row.fight_reveals,
            row.fight_late_reveals,
            row.fight_late_rate * 100.0,
            row.late_max_ticks,
            row.missed_share * 100.0,
            row.withheld_share * 100.0,
            row.heard_share * 100.0,
            row.sent_unseen_share * 100.0
        ));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_short_survey_measures_reveals_and_keeps_them_on_time() {
        let report = run(&[MapKind::ArenaDuel], &[50], 0, 20, 42);
        let row = &report.rows[0];
        assert!(row.ticks > 300, "{row:?}");
        assert!(row.reveals > 0, "bots meet: {row:?}");
        assert!(row.withheld_share > 0.0, "walls hide somebody: {row:?}");
        assert!(check(&report).is_empty(), "{}", table(&report));
        assert!(table(&report).contains("Larak Lot"));
    }
}
