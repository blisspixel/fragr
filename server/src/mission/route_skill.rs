//! Test-only skill shared by the scripted campaign route controllers.
//!
//! A Union attack commits its aim when the tell starts: the red optics swell,
//! the tell sounds, and the shot goes down that line. A player who reads the
//! tell and steps off the line is not hit. Route controllers that ignore tells
//! survive or die by the luck of the shot sequence, so their evidence moves
//! with the seed. Reading the tell the way the encounter teaches makes the
//! route a statement about the level instead of about a seed.
use crate::movement::{Arena, MoveInput, EYE_HEIGHT, STEP_UP};
use crate::navigation::Navigation;
use crate::protocol::{Action, CampaignActor, EnemyPhase, PlayerState, Region3, Snapshot};
use crate::sim::{GameState, PLAYER_FLOOR_Y};
use std::f32::consts::FRAC_PI_2;
use uuid::Uuid;

/// Distance off a committed line that clears a burst's spread at room range.
const LINE_CLEAR: f32 = 2.0;
/// A sidestep is chosen only toward ground that is open this far.
const SIDE_OPEN: f32 = 2.4;

/// A tell, burst, leap or charge: an attack whose line is already chosen.
fn committed(campaign: Option<CampaignActor>) -> bool {
    matches!(
        campaign,
        Some(CampaignActor::Hostile {
            phase: EnemyPhase::Windup
                | EnemyPhase::Firing
                | EnemyPhase::Leaping
                | EnemyPhase::Charging,
            ..
        })
    )
}

/// One committed attack being answered: who, the line it was aimed down and
/// the side chosen off that line.
#[derive(Clone, Copy, Debug)]
struct Dodge {
    guard: Uuid,
    from: [f32; 2],
    toward: [f32; 2],
    side: f32,
}

impl Dodge {
    /// Signed distance of `point` from the committed line, positive on the
    /// chosen side.
    fn offset(&self, point: [f32; 2]) -> f32 {
        let line = [self.toward[0] - self.from[0], self.toward[1] - self.from[1]];
        let length = line[0].hypot(line[1]).max(0.001);
        let normal = [-line[1] / length, line[0] / length];
        let along_side = normal[0] * self.side.cos() + normal[1] * self.side.sin();
        let delta = [point[0] - self.from[0], point[1] - self.from[1]];
        (delta[0] * normal[0] + delta[1] * normal[1]) * along_side.signum()
    }
}

/// Reads Union tells for one route controller. Each committed attack aimed
/// down a line at the controller is answered once, by stepping clear of that
/// line to one side and staying clear until the attack is spent.
#[derive(Default)]
pub(crate) struct TellReader {
    dodges: Vec<Dodge>,
    /// The way out of a marked blast area, while the body is still inside one.
    blast: Option<f32>,
    /// Regions a dodge must not carry the body into, such as an ungated exit
    /// a full-clear route has not earned yet.
    avoid: Vec<Region3>,
}

impl TellReader {
    pub(crate) fn avoid(&mut self, regions: Vec<Region3>) {
        self.avoid = regions;
    }

    /// Replace the movement keys with a sidestep while the body still stands
    /// on the line of a committed attack aimed at it. Aim, fire and equipment
    /// intent are kept. Off every line, or with no open side, the action is
    /// unchanged.
    pub(crate) fn evade(
        &mut self,
        state: &GameState,
        snapshot: &Snapshot,
        id: Uuid,
        action: Action,
    ) -> Action {
        let Some(me) = snapshot.players.iter().find(|p| p.id == id && p.hp > 0) else {
            self.dodges.clear();
            return action;
        };
        let arena = state.current_arena();
        let here = [me.x, me.z];
        // An attack spent, or a guard down, frees its line.
        self.dodges.retain(|dodge| {
            snapshot
                .players
                .iter()
                .any(|p| p.id == dodge.guard && p.hp > 0 && committed(p.campaign))
        });
        for guard in snapshot.players.iter().filter(|p| me.is_hostile_to(p)) {
            if !committed(guard.campaign)
                || self.dodges.iter().any(|dodge| dodge.guard == guard.id)
                || !sees(guard, me, &arena)
            {
                continue;
            }
            let bearing = (me.z - guard.z).atan2(me.x - guard.x);
            let velocity = state
                .players
                .iter()
                .find(|p| p.id == id)
                .map_or((0.0, 0.0), |p| (p.vx, p.vz));
            // Keep going the way the body already moves; reversing costs time.
            let mut sides = [bearing + FRAC_PI_2, bearing - FRAC_PI_2];
            let along = |yaw: f32| yaw.cos() * velocity.0 + yaw.sin() * velocity.1;
            if along(sides[1]) > along(sides[0]) {
                sides.swap(0, 1);
            }
            let side = sides
                .into_iter()
                .find(|yaw| open(&arena, &self.avoid, me, *yaw, SIDE_OPEN))
                .or_else(|| {
                    sides
                        .into_iter()
                        .find(|yaw| open(&arena, &self.avoid, me, *yaw, 1.0))
                });
            if let Some(side) = side {
                self.dodges.push(Dodge {
                    guard: guard.id,
                    from: [guard.x, guard.z],
                    toward: here,
                    side,
                });
            }
        }
        // A marked blast area comes first: walk out of it. Keep the way out
        // already chosen while it stays open, so two overlapping marks cannot
        // turn the body back and forth between them.
        let away = blast_exit(snapshot, me, &arena, &self.avoid).map(|fresh| {
            self.blast
                .filter(|kept| open(&arena, &self.avoid, me, *kept, 0.6))
                .unwrap_or(fresh)
        });
        self.blast = away;
        if let Some(away) = away {
            return steer(action, me, away);
        }
        // Answer the line the body is still closest to.
        let Some(dodge) = self
            .dodges
            .iter()
            .filter(|dodge| dodge.offset(here) < LINE_CLEAR)
            .min_by(|a, b| a.offset(here).total_cmp(&b.offset(here)))
            .copied()
        else {
            return action;
        };
        if !open(&arena, &self.avoid, me, dodge.side, 0.6) {
            return action;
        }
        steer(action, me, dodge.side)
    }
}

/// The world direction out of the Walker's announced stomp or marked shell
/// area the body stands in, if any.
fn blast_exit(
    snapshot: &Snapshot,
    me: &PlayerState,
    arena: &Arena,
    avoid: &[Region3],
) -> Option<f32> {
    use crate::protocol::{WalkerPhase, WALKER_SHELL_RADIUS, WALKER_STOMP_RADIUS};
    let mut areas = Vec::new();
    if let Some(walker) = snapshot.walker.as_ref() {
        if matches!(walker.phase, WalkerPhase::StompWarning | WalkerPhase::Stomp) {
            areas.push((walker.feet, WALKER_STOMP_RADIUS));
        }
        if matches!(
            walker.phase,
            WalkerPhase::ArtilleryWarning | WalkerPhase::Artillery
        ) || !walker.shells.is_empty()
        {
            areas.extend(
                walker
                    .artillery_targets
                    .iter()
                    .map(|target| (*target, WALKER_SHELL_RADIUS)),
            );
        }
    }
    // Every mark the body stands in pushes it out in proportion to how deep
    // it stands, so overlapping marks resolve to one way out.
    let mut push = [0.0_f32, 0.0_f32];
    let mut inside = false;
    // A Paver's marked strip: step off its nearer long edge.
    for strip in &snapshot.paver_strips {
        let along_dir = [strip.yaw.cos(), strip.yaw.sin()];
        let delta = [me.x - strip.origin[0], me.z - strip.origin[2]];
        let along = delta[0] * along_dir[0] + delta[1] * along_dir[1];
        let lateral = delta[0] * along_dir[1] - delta[1] * along_dir[0];
        let depth = strip.half_width + 0.6 - lateral.abs();
        if !(-0.6..=strip.length + 0.6).contains(&along) || depth <= 0.0 {
            continue;
        }
        inside = true;
        let side = if lateral >= 0.0 { 1.0 } else { -1.0 };
        push[0] += along_dir[1] * side * depth;
        push[1] -= along_dir[0] * side * depth;
    }
    for (centre, radius) in areas {
        let delta = [me.x - centre[0], me.z - centre[2]];
        let distance = delta[0].hypot(delta[1]);
        let depth = radius + 0.6 - distance;
        if depth <= 0.0 {
            continue;
        }
        inside = true;
        let unit = if distance > 0.01 {
            [delta[0] / distance, delta[1] / distance]
        } else {
            [1.0, 0.0]
        };
        push[0] += unit[0] * depth;
        push[1] += unit[1] * depth;
    }
    if !inside {
        return None;
    }
    let away = push[1].atan2(push[0]);
    [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]
        .into_iter()
        .map(|turn| away + turn)
        .find(|yaw| open(arena, avoid, me, *yaw, 1.0))
}

/// Movement keys closest to the world direction `yaw` in the facing the sim
/// uses this tick. Aim, fire and equipment intent are kept.
fn steer(mut action: Action, me: &PlayerState, yaw: f32) -> Action {
    {
        let facing = action.yaw.unwrap_or(me.yaw);
        let want = (yaw.cos(), yaw.sin());
        let keys = [
            (true, false, false, false),
            (false, true, false, false),
            (false, false, true, false),
            (false, false, false, true),
            (true, false, true, false),
            (true, false, false, true),
            (false, true, true, false),
            (false, true, false, true),
        ];
        let score = |k: &(bool, bool, bool, bool)| {
            let (dx, dz) = crate::movement::wish_dir(
                &MoveInput {
                    forward: k.0,
                    back: k.1,
                    left: k.2,
                    right: k.3,
                    yaw: facing,
                    ..Default::default()
                },
                facing,
            );
            dx * want.0 + dz * want.1
        };
        let best = keys
            .into_iter()
            .max_by(|a, b| score(a).total_cmp(&score(b)))
            .unwrap_or_default();
        (action.forward, action.back, action.left, action.right) = best;
    }
    action
}

/// Run one seeded route on every seed and report which held. A survey is
/// evidence for a route's seed independence; it fails if any seed fails.
pub(crate) fn survey(
    label: &str,
    seeds: impl IntoIterator<Item = u64>,
    route: impl Fn(u64) + std::panic::RefUnwindSafe,
) {
    let mut failed = Vec::new();
    let mut total = 0;
    // FRAGR_SURVEY_SEED narrows a survey to one seed while reading its log.
    let only: Option<u64> = std::env::var("FRAGR_SURVEY_SEED")
        .ok()
        .and_then(|seed| seed.parse().ok());
    for seed in seeds
        .into_iter()
        .filter(|seed| only.is_none_or(|only| only == *seed))
    {
        total += 1;
        if std::panic::catch_unwind(|| route(seed)).is_err() {
            failed.push(seed);
        }
    }
    eprintln!(
        "SURVEY {label}: {} of {total} seeds held, failed {failed:?}",
        total - failed.len()
    );
    assert!(failed.is_empty(), "{label} failed on seeds {failed:?}");
}

/// Ticks of steady fire at one target without a point of damage before the
/// controller stops trading with it.
const FUTILE_TICKS: u64 = 120;
/// How long a futile target is left alone before the controller tries again.
const FUTILE_REST: u64 = 600;

/// Targets a route controller has fired at without effect: a turret behind a
/// lip that sight lines clear but rounds do not. A player stops shooting the
/// rail and gets on with the objective; so does the controller, for a while.
#[derive(Default)]
pub(crate) struct FutileTargets {
    current: Option<(Uuid, i32, u64)>,
    resting: Vec<(Uuid, u64)>,
}

impl FutileTargets {
    pub(crate) fn skips(&self, target: Uuid, tick: u64) -> bool {
        self.resting
            .iter()
            .any(|(id, until)| *id == target && tick < *until)
    }

    pub(crate) fn observe(&mut self, snapshot: &Snapshot, action: &Action) {
        let tick = snapshot.tick;
        self.resting.retain(|(_, until)| tick < *until);
        // Held aim counts as well as held fire: a target the controller only
        // stares at, out of reach or out of sight, also holds up the route.
        let Some(target) = action
            .look_at
            .as_ref()
            .and_then(|look| look.player_id)
            .and_then(|id| snapshot.players.iter().find(|p| p.id == id))
        else {
            return;
        };
        let health = target.hp + target.armor;
        match self.current {
            Some((id, last, since)) if id == target.id => {
                if health < last {
                    self.current = Some((id, health, tick));
                } else if tick.saturating_sub(since) > FUTILE_TICKS {
                    self.resting.push((id, tick.saturating_add(FUTILE_REST)));
                    self.current = None;
                }
            }
            _ => self.current = Some((target.id, health, tick)),
        }
    }
}

/// A guard with a clear line from its eye to the body's chest.
fn sees(guard: &PlayerState, me: &PlayerState, arena: &Arena) -> bool {
    crate::combat::line_of_sight(
        [guard.x, guard.y - PLAYER_FLOOR_Y + EYE_HEIGHT, guard.z],
        [me.x, me.y - PLAYER_FLOOR_Y + EYE_HEIGHT * 0.75, me.z],
        &arena.solids,
    )
}

/// Walkable, level ground `length` metres from the body along `yaw`, outside
/// every region the controller must not enter yet.
fn open(arena: &Arena, avoid: &[Region3], me: &PlayerState, yaw: f32, length: f32) -> bool {
    let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
    let point = [
        feet[0] + yaw.cos() * length,
        feet[1],
        feet[2] + yaw.sin() * length,
    ];
    let floor = arena.support_height(point[0], point[2], feet[1] + STEP_UP);
    (floor - feet[1]).abs() <= STEP_UP
        && !avoid
            .iter()
            .any(|region| region.contains([point[0], floor, point[2]]))
        && Navigation::walkable_in(arena, feet, [point[0], floor, point[2]])
}
