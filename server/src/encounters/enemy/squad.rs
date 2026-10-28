//! Squad roles on top of the attack tokens. Anchors (the Heavy Sweeper and
//! the Turret) hold a lane; while one of them is firing at a participant,
//! skirmishers (the Sweeper and the Redactor) leave the anchor's
//! line and go around to a side that still sees the participant; the Auditor
//! keeps a heavy between itself and the participant. A guard that flanks
//! still asks for a token before it raises its gun.

use super::{turn, EnemyController};
use crate::navigation::NavigationGoal;
use crate::protocol::{
    Action, CampaignDifficulty, EnemyBarkKind, EnemyKind, EnemyPhase, PlayerState,
};
use crate::sim::{BotIntent, GameState, PLAYER_FLOOR_Y};
use uuid::Uuid;

/// A skirmisher already this far around the participant from the anchor's
/// line is in its crossfire and attacks as usual.
pub(super) const FLANK_ANGLE: f32 = 0.8;
/// The flank point swings this far around the participant from the anchor's
/// bearing.
pub(super) const FLANK_SWING: f32 = 1.2;
/// Bound on one flanking walk (2.5 s).
pub(super) const FLANK_TICKS: u64 = 50;
/// Close enough to the flank point.
pub(super) const FLANK_ARRIVAL: f32 = 1.5;
/// After a flank, a skirmisher fights from where it is for this long.
pub(super) const FLANK_REST: u64 = 80;
/// Flank distance from the participant, in metres.
pub(super) const FLANK_RANGE: (f32, f32) = (6.0, 14.0);
/// The Auditor's place behind its heavy, in metres.
pub(super) const BACKLINE_DISTANCE: f32 = 3.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SquadRole {
    /// Pins a lane: the Heavy Sweeper and the Turret.
    Anchor,
    /// Goes around while an anchor fires: Sweeper, Redactor.
    Skirmisher,
    /// Holds behind a heavy: the Auditor.
    Backline,
    /// Everyone else fights as before. The Crawler is a leaper, not a gun:
    /// a flank point lies six metres or more out, past its four metre leap,
    /// so a pack keeps closing and leaping while an anchor fires.
    Line,
}

pub(crate) fn role(kind: EnemyKind) -> SquadRole {
    match kind {
        EnemyKind::HeavySweeper | EnemyKind::Turret => SquadRole::Anchor,
        EnemyKind::Sweeper | EnemyKind::Redactor => SquadRole::Skirmisher,
        EnemyKind::Auditor => SquadRole::Backline,
        _ => SquadRole::Line,
    }
}

/// What a guard knows of its own group this tick, set by the encounter.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub(crate) struct Squad {
    /// An anchor of this group in a tell or a burst: its target and feet.
    pub anchor: Option<(Uuid, [f32; 3])>,
    /// The first living heavy of this group, in authored order (Heavy Sweeper or Enforcer).
    pub heavy: Option<[f32; 3]>,
}

fn bearing(from: [f32; 3], to: [f32; 3]) -> f32 {
    (to[2] - from[2]).atan2(to[0] - from[0])
}

/// Walk to a squad position. The navigator walks straight while the point
/// is in sight and routes around cover only when it is not (`combat`), so
/// a flank in the open is a lateral arc rather than a grid path.
fn walk(point: [f32; 3], feet: [f32; 3]) -> BotIntent {
    BotIntent {
        action: Action {
            forward: true,
            yaw: Some(bearing(feet, point)),
            ..Default::default()
        },
        goal: Some(NavigationGoal {
            feet: point,
            combat: true,
        }),
    }
}

impl EnemyController {
    pub(in crate::encounters) fn set_squad(&mut self, squad: Squad) {
        self.squad = squad;
    }

    /// A skirmisher's lateral walk around the participant while an anchor of
    /// its group fires at them. `None` leaves the guard to its usual fight.
    pub(super) fn flank(
        &mut self,
        state: &GameState,
        target: &PlayerState,
        feet: [f32; 3],
        tick: u64,
    ) -> Option<BotIntent> {
        if role(self.kind) != SquadRole::Skirmisher
            || self.seated
            || state.campaign_rules().difficulty == CampaignDifficulty::Assisted
            || !matches!(
                self.phase,
                EnemyPhase::Idle | EnemyPhase::Moving | EnemyPhase::Recovery
            )
        {
            self.flank = None;
            return None;
        }
        if let Some((point, until)) = self.flank {
            if tick > until || (feet[0] - point[0]).hypot(feet[2] - point[2]) <= FLANK_ARRIVAL {
                self.flank = None;
                self.flank_rest = tick.saturating_add(FLANK_REST);
                return None;
            }
            self.keep_walking(tick);
            return Some(walk(point, feet));
        }
        let (anchor_target, anchor) = self.squad.anchor?;
        if anchor_target != target.id || tick < self.flank_rest {
            return None;
        }
        let quarry = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
        let lane = bearing(quarry, anchor);
        let offset = turn(lane, bearing(quarry, feet));
        if offset.abs() >= FLANK_ANGLE {
            return None;
        }
        let side = if offset >= 0.0 { 1.0 } else { -1.0 };
        let reach = (feet[0] - quarry[0])
            .hypot(feet[2] - quarry[2])
            .clamp(FLANK_RANGE.0, FLANK_RANGE.1);
        let point = [
            (side, reach),
            (-side, reach),
            (side, FLANK_RANGE.0),
            (-side, FLANK_RANGE.0),
        ]
        .into_iter()
        .find_map(|(sign, radius)| flank_point(state, quarry, lane + sign * FLANK_SWING, radius))?;
        self.flank = Some((point, tick.saturating_add(FLANK_TICKS)));
        self.pending_bark = Some(EnemyBarkKind::Flanking);
        self.keep_walking(tick);
        Some(walk(point, feet))
    }

    /// Walking a flank: a guard still recovering from its own burst keeps
    /// that window (the opening lasts as long) and walks during it.
    fn keep_walking(&mut self, tick: u64) {
        if !matches!(self.phase, EnemyPhase::Moving | EnemyPhase::Recovery) {
            self.enter(EnemyPhase::Moving, tick, 0);
        }
    }

    /// The Auditor's walk to its place behind a heavy when it cannot attack
    /// from where it stands. `None` when it has no heavy or is already there.
    pub(super) fn hold_behind(
        &mut self,
        target: &PlayerState,
        feet: [f32; 3],
        tick: u64,
    ) -> Option<BotIntent> {
        if role(self.kind) != SquadRole::Backline {
            return None;
        }
        let heavy = self.squad.heavy?;
        let quarry = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
        let away = bearing(quarry, heavy);
        let spot = [
            heavy[0] + away.cos() * BACKLINE_DISTANCE,
            heavy[1],
            heavy[2] + away.sin() * BACKLINE_DISTANCE,
        ];
        if (feet[0] - spot[0]).hypot(feet[2] - spot[2]) <= FLANK_ARRIVAL {
            return None;
        }
        if self.phase != EnemyPhase::Moving {
            self.enter(EnemyPhase::Moving, tick, 0);
        }
        Some(walk(spot, feet))
    }
}

/// A standing point `radius` from `quarry` along `bearing`, on the
/// participant's floor and in their sight.
fn flank_point(state: &GameState, quarry: [f32; 3], bearing: f32, radius: f32) -> Option<[f32; 3]> {
    let point = [
        quarry[0] + bearing.cos() * radius,
        quarry[1],
        quarry[2] + bearing.sin() * radius,
    ];
    let arena = state.current_arena();
    let floor = arena.support_height(point[0], point[2], quarry[1] + 0.5);
    let (x, z) = arena.clamp(point[0], point[2]);
    if (floor - quarry[1]).abs() > 0.5
        || (x - point[0]).abs() > 0.01
        || (z - point[2]).abs() > 0.01
        || !arena.fits_height(point[0], point[2], floor, crate::movement::BODY_HEIGHT)
    {
        return None;
    }
    let eye = crate::movement::EYE_HEIGHT;
    crate::combat::line_of_sight(
        [point[0], floor + eye, point[2]],
        [quarry[0], quarry[1] + eye, quarry[2]],
        &arena.solids,
    )
    .then_some([point[0], floor, point[2]])
}
