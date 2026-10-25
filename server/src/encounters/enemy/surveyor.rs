//! The Surveyor: an elevated spotter that never fires. Its lens sweeps, opens
//! wide on a noticed participant (the exposed observation tell), then
//! projects a disc of light that tracks that participant at a bounded speed
//! while sight holds. Nearby walking machines converge on the disc.
//!
//! Counters, all authoritative: break sight (the disc stops, then lapses),
//! move off the disc (it is slower than a walking participant), or hit the
//! Surveyor while its lens is open (any damaging hit staggers it and ends
//! the observation or the disc). A disc that ends by broken sight or a hit
//! before any machine reaches it is a broken mark.
use super::*;
use crate::protocol::SURVEYOR_MARK_RADIUS;

/// Elevated sight: the whole quay from a tower, but not the whole district.
pub(crate) const SURVEYOR_SIGHT_RANGE: f32 = 52.0;
const SWEEP_ARC: f32 = 1.1;
const SWEEP_RATE: f32 = 0.025;
const TRACK_RATE: f32 = 0.09;
/// Half-angle either side of the lens in which a participant is noticed.
pub(super) const NOTICE_CONE: f32 = 0.9;
/// Without sight of its participant for this long the disc lapses.
pub(crate) const MARK_SIGHT_GRACE: u64 = 30;
/// Machines within this distance of a live disc converge on it.
pub(crate) const CONVERGE_RADIUS: f32 = 36.0;
/// A converging machine presses in until it is this close to the disc
/// centre; reaching it counts as the machines arriving.
pub(crate) const ARRIVAL_RADIUS: f32 = SURVEYOR_MARK_RADIUS + 3.0;
/// Every actor phase window stays inside the shared presentation bound.
const PHASE_WINDOW: u64 = 100;
/// Hit stagger while the lens is open, before the shutter recovers.
pub(crate) const LENS_STAGGER_TICKS: u64 = 30;

/// How long a disc lasts once cast.
pub(crate) fn mark_ticks(difficulty: CampaignDifficulty) -> u64 {
    match difficulty {
        CampaignDifficulty::Assisted => 120,
        CampaignDifficulty::Standard => 160,
        CampaignDifficulty::Severe => 200,
    }
}

/// Disc tracking speed in metres per second, always under a walk.
pub(crate) fn disc_speed(difficulty: CampaignDifficulty) -> f32 {
    match difficulty {
        CampaignDifficulty::Assisted => 1.4,
        CampaignDifficulty::Standard => 2.0,
        CampaignDifficulty::Severe => 2.6,
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Mark {
    pub(crate) center: [f32; 3],
    pub(crate) target: Uuid,
    pub(crate) since: u64,
    pub(crate) until: u64,
    pub(crate) tracking: bool,
    pub(crate) unseen_since: Option<u64>,
    /// A converging machine has stood inside the disc.
    pub(crate) arrived: bool,
}

/// How a disc ended. Expiry is neither a success nor a broken mark.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MarkEnd {
    Expired,
    SightBroken,
    Struck,
}

impl EnemyController {
    pub(super) fn surveyor(
        &mut self,
        state: &GameState,
        target: Option<&crate::protocol::PlayerState>,
        eye: [f32; 3],
        timing: (u64, u64),
        tick: u64,
        may_attack: bool,
    ) -> BotIntent {
        let (windup, recovery) = timing;
        let difficulty = state.campaign_rules().difficulty;
        let mut action = Action::default();
        match self.phase {
            EnemyPhase::Hit | EnemyPhase::Recovery if tick < self.until => {
                action.yaw = Some(self.head);
                action.pitch = Some(0.0);
                return BotIntent { action, goal: None };
            }
            EnemyPhase::Windup => {
                let Some(target) = target else {
                    // Sight broke while the lens was opening: shutter closes.
                    self.target = None;
                    self.enter(EnemyPhase::Recovery, tick, recovery / 2);
                    return BotIntent::default();
                };
                let bearing = (target.z - eye[2]).atan2(target.x - eye[0]);
                self.face(&mut action, bearing, TRACK_RATE);
                if tick >= self.until {
                    let feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
                    self.marks_cast = self.marks_cast.saturating_add(1);
                    self.mark = Some(Mark {
                        center: grounded(state, feet, feet),
                        target: target.id,
                        since: tick,
                        until: tick.saturating_add(mark_ticks(difficulty)),
                        tracking: true,
                        unseen_since: None,
                        arrived: false,
                    });
                    // Readers bound every phase window to a hundred ticks;
                    // the disc's own lifetime is the mark fact.
                    self.enter(
                        EnemyPhase::Firing,
                        tick,
                        mark_ticks(difficulty).min(PHASE_WINDOW),
                    );
                    tracing::info!(surveyor = %self.id, participant = %target.id, "Surveyor mark cast");
                }
                return BotIntent { action, goal: None };
            }
            EnemyPhase::Firing => {
                let Some(mut mark) = self.mark else {
                    self.enter(EnemyPhase::Recovery, tick, recovery);
                    return BotIntent::default();
                };
                if tick >= mark.until {
                    self.end_mark(MarkEnd::Expired);
                    self.enter(EnemyPhase::Recovery, tick, recovery);
                    return BotIntent::default();
                }
                match target.filter(|t| t.id == mark.target) {
                    Some(target) => {
                        mark.tracking = true;
                        mark.unseen_since = None;
                        let feet = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
                        let dx = feet[0] - mark.center[0];
                        let dz = feet[2] - mark.center[2];
                        let distance = dx.hypot(dz);
                        let step = disc_speed(difficulty) * crate::movement::DT_LIVE;
                        let moved = if distance <= step {
                            [feet[0], mark.center[1], feet[2]]
                        } else {
                            [
                                mark.center[0] + dx / distance * step,
                                mark.center[1],
                                mark.center[2] + dz / distance * step,
                            ]
                        };
                        mark.center = grounded(state, moved, feet);
                        let bearing = (target.z - eye[2]).atan2(target.x - eye[0]);
                        self.face(&mut action, bearing, TRACK_RATE);
                    }
                    None => {
                        mark.tracking = false;
                        let since = *mark.unseen_since.get_or_insert(tick);
                        if tick.saturating_sub(since) >= MARK_SIGHT_GRACE {
                            self.mark = Some(mark);
                            self.end_mark(MarkEnd::SightBroken);
                            self.target = None;
                            self.enter(EnemyPhase::Recovery, tick, recovery);
                            return BotIntent::default();
                        }
                        action.yaw = Some(self.head);
                        action.pitch = Some(0.0);
                    }
                }
                self.mark = Some(mark);
                return BotIntent { action, goal: None };
            }
            _ => {}
        }
        // Idle: sweep the lens and open it on a noticed participant in reach.
        if let Some(target) =
            target.filter(|t| (t.x - eye[0]).hypot(t.z - eye[2]) <= SURVEYOR_SIGHT_RANGE)
        {
            let bearing = (target.z - eye[2]).atan2(target.x - eye[0]);
            let remaining = self.face(&mut action, bearing, TRACK_RATE);
            // The lens opens only with a free token: an open lens is a tell.
            if remaining.abs() <= 0.12 && may_attack {
                self.stagger_ready = true;
                self.enter(EnemyPhase::Windup, tick, windup);
            } else if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            return BotIntent { action, goal: None };
        }
        self.target = None;
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        let edge = self.home_yaw + self.sweep * SWEEP_ARC;
        if self.face(&mut action, edge, SWEEP_RATE).abs() <= SWEEP_RATE {
            self.sweep = -self.sweep;
        }
        BotIntent { action, goal: None }
    }

    /// The lens is open while observing and while projecting.
    pub(crate) fn lens_open(phase: EnemyPhase) -> bool {
        matches!(phase, EnemyPhase::Windup | EnemyPhase::Firing)
    }

    /// Close the disc, retaining whether it counted as broken.
    pub(super) fn end_mark(&mut self, how: MarkEnd) {
        if let Some(mark) = self.mark.take() {
            if !mark.arrived && how != MarkEnd::Expired {
                self.marks_broken = self.marks_broken.saturating_add(1);
            }
            tracing::info!(surveyor = %self.id, ?how, arrived = mark.arrived, "Surveyor mark ended");
        }
    }

    pub(in crate::encounters) fn mark(&self) -> Option<Mark> {
        self.mark.filter(|_| self.phase == EnemyPhase::Firing)
    }

    pub(in crate::encounters) fn note_mark_arrival(&mut self) {
        if let Some(mark) = self.mark.as_mut() {
            mark.arrived = true;
        }
    }

    /// Press toward a live disc until it lapses.
    pub(in crate::encounters) fn converge(&mut self, center: [f32; 3], until: u64, tick: u64) {
        self.converging = Some((center, until));
        self.alarm(center, tick);
    }

    pub(in crate::encounters) fn take_marks_broken(&mut self) -> u32 {
        std::mem::take(&mut self.marks_broken)
    }

    #[cfg(test)]
    pub(in crate::encounters) fn is_converging(&self) -> bool {
        self.converging.is_some()
    }

    /// The lone lesson is over once a first disc has been cast and has ended.
    pub(in crate::encounters) fn lesson_given(&self) -> bool {
        self.marks_cast > 0 && self.mark.is_none()
    }
}

/// The disc lies on the ground under the participant's level, never in the air.
fn grounded(state: &GameState, at: [f32; 3], feet: [f32; 3]) -> [f32; 3] {
    let floor = state
        .current_arena()
        .support_height(at[0], at[2], feet[1] + 0.05)
        .max(0.0);
    [at[0], floor, at[2]]
}

/// Mark radius for convergence arithmetic.
pub(crate) const MARK_RADIUS: f32 = SURVEYOR_MARK_RADIUS;
