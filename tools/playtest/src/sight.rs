//! Shared survey readings: who could see whom, how a fighter walks, and how
//! a list of seconds or metres spreads. The survey reads the authoritative
//! state from outside the bots and never steers them.
use fragr_server::movement::Solid;
use fragr_server::protocol::GameMode;
use fragr_server::session::GameSession;
use fragr_server::sim::Player;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Half the 120 degree view cone every rule bot looks through.
const CONE: f32 = std::f32::consts::FRAC_PI_3;
/// The default rung's eyes, metres: contact is read at what a regular sees.
pub const SIGHT: f32 = 64.0;
/// A dither window, ticks: four seconds.
const WINDOW: u32 = 80;
/// The window is read in steps this long, ticks: half a second.
const STEP: u32 = 10;
/// A step that moves less than this, metres, has no heading.
const STEP_MOVING: f32 = 0.5;
/// A window walks at least this far to count as moving, metres.
const MOVING: f32 = 4.0;
/// A heading this far from the last step's is a reversal.
const REVERSAL: f32 = 2.0 * std::f32::consts::FRAC_PI_3;
/// Reversals in one window that make it a dither: there and back and there
/// again, the walk of a bot that cannot settle on a goal. One U-turn, to a
/// sound behind or a pad that came up, is a decision, not a dither.
const DITHER_REVERSALS: u32 = 2;

/// Median and quartiles of a list.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Spread {
    pub count: u64,
    pub median: f64,
    pub p25: f64,
    pub p75: f64,
}

pub fn spread(values: &[f64]) -> Spread {
    if values.is_empty() {
        return Spread::default();
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(f64::total_cmp);
    let at = |share: f64| {
        let index = ((sorted.len() - 1) as f64 * share).round() as usize;
        sorted[index]
    };
    Spread {
        count: sorted.len() as u64,
        median: at(0.5),
        p25: at(0.25),
        p75: at(0.75),
    }
}

fn alive(player: &Player) -> bool {
    player.hp > 0
        && player.respawn_timer.is_none()
        && player.role != fragr_server::protocol::Role::Spectator
}

fn feet(player: &Player) -> [f32; 3] {
    [
        player.x,
        player.y - fragr_server::sim::PLAYER_FLOOR_Y,
        player.z,
    ]
}

/// Whether `a` and `b` fight each other in `mode`.
pub fn hostile(mode: GameMode, a: &Player, b: &Player) -> bool {
    a.id != b.id
        && !a.is_boss
        && !b.is_boss
        && match mode {
            GameMode::Ffa | GameMode::Duel => true,
            _ => a.team.is_some() && a.team != b.team,
        }
}

/// Whether `from` has `to` inside its 120 degree cone, within `range`,
/// with clear sight from its eye to the other's chest.
pub fn sees(solids: &[Solid], from: &Player, to: &Player, range: f32) -> bool {
    let dx = to.x - from.x;
    let dz = to.z - from.z;
    if dx.hypot(dz) > range {
        return false;
    }
    let bearing = dz.atan2(dx);
    let turn = (bearing - from.yaw + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU)
        - std::f32::consts::PI;
    if turn.abs() > CONE {
        return false;
    }
    let mut eye = feet(from);
    eye[1] += fragr_server::combat::stance_eye(from.campaign, from.ducking);
    let chest = fragr_server::combat::aim_point_for(feet(to), to.campaign, to.ducking);
    fragr_server::combat::line_of_sight(eye, chest, solids)
}

/// Whether `player` can see any living opponent right now.
pub fn sees_anyone(session: &GameSession, solids: &[Solid], player: &Player, range: f32) -> bool {
    let mode = session.state.config.rules.mode();
    session.state.players.iter().any(|other| {
        alive(other) && hostile(mode, player, other) && sees(solids, player, other, range)
    })
}

#[derive(Debug, Clone, Copy)]
struct Window {
    /// Where the current step began.
    step_start: [f32; 3],
    last: [f32; 3],
    /// The last moving step's heading.
    heading: Option<[f32; 2]>,
    walked: f32,
    reversals: u32,
    ticks: u32,
    fighting: bool,
}

impl Window {
    fn at(here: [f32; 3]) -> Self {
        Self {
            step_start: here,
            last: here,
            heading: None,
            walked: 0.0,
            reversals: 0,
            ticks: 0,
            fighting: false,
        }
    }
}

/// Four second windows of every living fighter's walk, read in half second
/// steps. A window with nobody in view that walks four metres or more and
/// turns back on itself twice is a dither: the bot could not decide.
#[derive(Debug, Default)]
pub struct DitherTracker {
    windows: HashMap<Uuid, Window>,
    pub moving: u64,
    pub dithers: u64,
}

impl DitherTracker {
    /// One tick of every living fighter.
    pub fn observe(&mut self, session: &GameSession, solids: &[Solid]) {
        let living: Vec<Uuid> = session
            .state
            .players
            .iter()
            .filter(|p| alive(p) && !p.is_boss)
            .map(|p| p.id)
            .collect();
        for id in &living {
            self.observe_one(session, solids, *id);
        }
        self.windows.retain(|id, _| living.contains(id));
    }

    /// One tick of one fighter. A dead fighter's window closes unread.
    pub fn observe_one(&mut self, session: &GameSession, solids: &[Solid], id: Uuid) {
        let Some(player) = session
            .state
            .players
            .iter()
            .find(|p| p.id == id && alive(p))
        else {
            self.windows.remove(&id);
            return;
        };
        let here = feet(player);
        let window = self.windows.entry(id).or_insert(Window::at(here));
        let step = (here[0] - window.last[0]).hypot(here[2] - window.last[2]);
        if step > 2.0 {
            // A respawn or a teleport: a new walk.
            *window = Window::at(here);
            return;
        }
        window.walked += step;
        window.last = here;
        window.ticks += 1;
        if !window.fighting && window.ticks.is_multiple_of(4) {
            window.fighting = sees_anyone(session, solids, player, SIGHT);
        }
        if window.ticks.is_multiple_of(STEP) {
            let moved = [
                here[0] - window.step_start[0],
                here[2] - window.step_start[2],
            ];
            let length = moved[0].hypot(moved[1]);
            if length >= STEP_MOVING {
                let heading = [moved[0] / length, moved[1] / length];
                if let Some(last) = window.heading {
                    let dot = (last[0] * heading[0] + last[1] * heading[1]).clamp(-1.0, 1.0);
                    if dot.acos() > REVERSAL {
                        window.reversals += 1;
                    }
                }
                window.heading = Some(heading);
            }
            window.step_start = here;
        }
        if window.ticks >= WINDOW {
            if !window.fighting && window.walked >= MOVING {
                self.moving += 1;
                if window.reversals >= DITHER_REVERSALS {
                    self.dithers += 1;
                }
            }
            *window = Window::at(here);
        }
    }

    pub fn share(&self) -> f64 {
        if self.moving == 0 {
            0.0
        } else {
            self.dithers as f64 / self.moving as f64
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spread_reads_median_and_quartiles() {
        let s = spread(&[5.0, 1.0, 3.0, 2.0, 4.0]);
        assert_eq!((s.count, s.median, s.p25, s.p75), (5, 3.0, 2.0, 4.0));
        assert_eq!(spread(&[]), Spread::default());
    }
}
