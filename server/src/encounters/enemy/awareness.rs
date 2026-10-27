//! What a guard knows. Until its group wakes, a guard stands on post. The
//! authored entry region (or a struck peer) is the alarm: the group wakes as
//! the level was written, but each guard has heard an alarm, not seen anyone.
//! A guard that can see the spot the alarm came from turns toward it (half a
//! turn in about 0.6 s); one that cannot walks there around cover, as alarmed
//! guards always have. Neither attacks until it sees a participant through
//! the shared senses (a 120 degree cone, a level gaze, cover) and a 200 to
//! 400 ms reaction, so a participant who came in behind a guard or from a
//! gantry above it gets the first shots. After one second every alarmed guard
//! is in the fight regardless: the authored room always wakes.
//!
//! A sighting before the region was measured and not kept: even inside a six
//! metre band around the region it woke rooms early, broke authored beats
//! (a resupply beside sleeping guards, a pickup before an entry) and raised
//! the constrained M19 teaching survey from 4 deaths to 60.

use super::{turn, EnemyController, SIGHT_RANGE};
use crate::navigation::NavigationGoal;
use crate::protocol::{Action, CampaignActor, EnemyBarkKind, EnemyKind, EnemyPhase};
use crate::sim::{guard_reaction, guard_sees, BotIntent, GameState, Player};
use uuid::Uuid;

/// Turn per tick of a guard looking for an alarm it heard: half a turn in
/// about 0.6 s.
pub(super) const ALERT_TURN: f32 = 0.25;
/// Ticks an alarmed guard may go without a sighting before it joins the fight
/// anyway (1 s). The authored room always wakes.
pub(super) const ALERT_LIMIT: u64 = 20;
/// Facing within this of the alarm, an alarmed guard that cannot see it
/// walks toward it.
pub(super) const ALERT_WALK: f32 = 0.5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Awareness {
    /// On post: its group has not woken.
    Unaware,
    /// Heard the alarm at `since`. `seen` is a participant in its cone and
    /// the tick its reaction completes.
    Alerted {
        since: u64,
        seen: Option<(Uuid, u64)>,
    },
    /// In the fight.
    Aware,
}

/// Kinds outside the guard model: Office equipment on the Union network (the
/// Turret's sweep, the Jammer, the Notary and Assessor drones) and the
/// marksman keep their own notice rules, and Inheritance machines (the
/// Surveyor's lens, the Paver) work rather than guard. The model is for
/// guards on foot: personnel and the Sweepers.
fn own_cone(kind: EnemyKind) -> bool {
    matches!(
        kind,
        EnemyKind::Turret
            | EnemyKind::Jammer
            | EnemyKind::Notary
            | EnemyKind::Assessor
            | EnemyKind::RangedSweeper
            | EnemyKind::Surveyor
            | EnemyKind::Paver
    )
}

/// Guards on watch: everyone outside `own_cone` but the Crawler pack, an
/// ambush whose reveal (the scrabble and its caption) is the authored
/// warning; it wakes with its region, already in the fight.
fn on_watch(kind: EnemyKind) -> bool {
    !own_cone(kind) && kind != EnemyKind::Crawler
}

impl EnemyController {
    /// Place this guard on post: it needs an alarm and then a sighting.
    pub(in crate::encounters) fn on_post(mut self) -> Self {
        if on_watch(self.kind) {
            self.awareness = Awareness::Unaware;
        }
        self
    }

    pub(in crate::encounters) fn aware(&self) -> bool {
        self.awareness == Awareness::Aware
    }

    /// The tick an alarmed guard's reaction to a participant it keeps in
    /// sight completes, if it has one.
    #[cfg(test)]
    pub(in crate::encounters) fn reaction_due(&self) -> Option<u64> {
        match self.awareness {
            Awareness::Alerted {
                seen: Some((_, ready)),
                ..
            } => Some(ready),
            _ => None,
        }
    }

    /// The group's alarm sounded at `tick`. A guard leading the authored
    /// spine file is already walking its orders.
    pub(super) fn hear_alarm(&mut self, tick: u64) {
        if self.spine_march.is_some() {
            self.awareness = Awareness::Aware;
        } else if self.awareness == Awareness::Unaware {
            self.awareness = Awareness::Alerted {
                since: tick,
                seen: None,
            };
        }
    }

    /// Scripted orders and hits put a guard straight into the fight.
    pub(super) fn wake(&mut self) {
        self.awareness = Awareness::Aware;
    }

    /// One look along the cone. True on the tick the reaction to a
    /// participant it kept in sight completes: the guard is then in the fight.
    fn look(&mut self, state: &GameState, body: &Player, tick: u64) -> bool {
        let Awareness::Alerted { since, seen } = self.awareness else {
            return false;
        };
        let sighted = state
            .players
            .iter()
            .filter(|p| {
                p.campaign == Some(CampaignActor::Participant {})
                    && p.hp > 0
                    && crate::protocol::hostile(body.campaign, p.campaign)
                    && crate::mission::actor_active(state.mission.as_ref(), p.id, p.campaign)
                    && guard_sees(state, body, body.yaw, SIGHT_RANGE, p)
            })
            .min_by(|a, b| {
                (a.x - body.x)
                    .hypot(a.z - body.z)
                    .total_cmp(&(b.x - body.x).hypot(b.z - body.z))
            })
            .map(|p| p.id);
        let seen = match (sighted, seen) {
            (Some(id), Some((kept, ready))) if id == kept => {
                if tick >= ready {
                    self.awareness = Awareness::Aware;
                    self.pending_bark = Some(EnemyBarkKind::Sighting);
                    return true;
                }
                Some((kept, ready))
            }
            (Some(id), _) => Some((id, guard_reaction(self.id, id, tick))),
            (None, _) => None,
        };
        self.awareness = Awareness::Alerted { since, seen };
        false
    }

    /// An awake group's guard that has not yet seen anyone: it turns toward
    /// the alarm it heard, walks there if the spot is out of sight, and does
    /// not attack.
    /// `None` once it is in the fight.
    pub(super) fn unaware_intent(&mut self, state: &GameState, tick: u64) -> Option<BotIntent> {
        let body = state.players.iter().find(|p| p.id == self.id)?;
        if self.look(state, body, tick) {
            return None;
        }
        let (since, reacting) = match self.awareness {
            Awareness::Aware => return None,
            Awareness::Alerted { since, seen } => (since, seen.is_some()),
            // A group woken without an alarm reaching this guard: fight.
            Awareness::Unaware => {
                self.awareness = Awareness::Aware;
                return None;
            }
        };
        if tick >= since.saturating_add(ALERT_LIMIT) {
            self.awareness = Awareness::Aware;
            return None;
        }
        let toward = (self.last_known[2] - body.z).atan2(self.last_known[0] - body.x);
        let delta = turn(body.yaw, toward);
        let yaw = crate::movement::normalize_yaw(body.yaw + delta.clamp(-ALERT_TURN, ALERT_TURN));
        // A guard with the alarm in view stands and turns to look; one without
        // heads for it around cover as before. A guard reacting to a sighting
        // holds still until it reacts. None of them shoots what it has not
        // seen.
        let eye = [
            body.x,
            body.y - crate::sim::PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
            body.z,
        ];
        let alarm_in_view = crate::combat::line_of_sight(
            eye,
            [
                self.last_known[0],
                self.last_known[1] + crate::movement::EYE_HEIGHT,
                self.last_known[2],
            ],
            &state.current_arena().solids,
        );
        let investigating = !reacting
            && !alarm_in_view
            && super::gait(self.kind) > 0.0
            && !self.seated
            && tick <= self.search_until
            && (body.x - self.last_known[0]).hypot(body.z - self.last_known[2]) > 0.6;
        let walking = investigating && delta.abs() <= ALERT_WALK;
        let phase = if investigating {
            EnemyPhase::Moving
        } else {
            EnemyPhase::Idle
        };
        if self.phase != phase {
            self.enter(phase, tick, 0);
        }
        Some(BotIntent {
            action: Action {
                yaw: Some(yaw),
                pitch: Some(0.0),
                forward: walking,
                ..Default::default()
            },
            goal: investigating.then_some(NavigationGoal {
                feet: self.last_known,
                combat: false,
            }),
        })
    }

    /// A line this guard would say, once.
    pub(in crate::encounters) fn take_bark(&mut self) -> Option<EnemyBarkKind> {
        self.pending_bark.take()
    }
}
