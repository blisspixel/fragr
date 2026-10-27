//! What a guard knows. Until its group wakes, a guard stands on post. A shot
//! that strikes one of them is gunfire in the room and puts the whole group in
//! the fight at once, as it always did. The authored entry region is a quiet
//! alarm: the group wakes and is dispatched exactly as the level was written,
//! walking to the alarm when it sees nobody, but each guard has heard an
//! alarm, not seen anyone. Its eyes go to the alarm, turning half a turn in
//! about 0.6 s whatever way its feet take around cover, and it starts an
//! attack only after it sees a
//! participant through the shared senses (a 120 degree cone, a level gaze,
//! cover). A guard already looking where the alarm came from was expecting
//! someone and raises at once, as before; one still turning is startled and
//! takes the 200 to 400 ms reaction. A participant who came in behind a guard
//! or from a gantry above it gets the first shots. After one second every
//! alarmed guard is in the fight regardless.
//!
//! Five variants were measured and not kept. A sighting before the region,
//! even inside a six metre band around it, woke rooms early, broke authored
//! beats (a resupply beside sleeping guards, a pickup before an entry) and
//! raised the constrained M19 teaching survey from 4 deaths to 60. Holding
//! alarmed guards at their posts instead of dispatching them left Level 1's
//! sorting room shooting the participant from the side while they fought the
//! dispatch desk, and raised M01 deaths again. Letting the walking body's
//! facing be the cone turned guards away from the participant whenever their
//! route bent; and giving even a guard that faced the alarm the startled
//! reaction pushed the Level 1 intake Clerk's committed aim into the line a
//! participant walks to reach it (its tell began 4 ticks later, aimed where
//! they then stood), so its one shot landed where it had always missed. And
//! letting a struck peer's alarm only draw the others' eyes sent Level 1's
//! sorting Sweepers walking toward the struck desk past the participant for a
//! second, so they joined the fight from the participant's side.

use super::{turn, EnemyController, SIGHT_RANGE};
use crate::navigation::NavigationGoal;
use crate::protocol::{Action, CampaignActor, EnemyBarkKind, EnemyKind, EnemyPhase};
use crate::sim::{guard_reaction, guard_sees, BotIntent, GameState, Player, PLAYER_FLOOR_Y};
use uuid::Uuid;

/// Turn per tick of a guard's eyes toward an alarm it heard: half a turn in
/// about 0.6 s.
pub(super) const ALERT_TURN: f32 = 0.25;
/// Ticks an alarmed guard may go without a sighting before it joins the fight
/// anyway (1 s). The authored room always wakes.
pub(super) const ALERT_LIMIT: u64 = 20;

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum Awareness {
    /// On post: its group has not woken.
    Unaware,
    /// Heard the alarm at `since`. `gaze` is where its eyes point, once it
    /// has looked up; `seen` is a participant in its cone and the tick its
    /// reaction completes.
    Alerted {
        since: u64,
        gaze: Option<f32>,
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

    /// The group's alarm sounded at `tick`. A guard leading the authored
    /// spine file is already walking its orders.
    pub(super) fn hear_alarm(&mut self, tick: u64) {
        if self.spine_march.is_some() {
            self.awareness = Awareness::Aware;
        } else if self.awareness == Awareness::Unaware {
            self.awareness = Awareness::Alerted {
                since: tick,
                gaze: None,
                seen: None,
            };
        }
    }

    /// Scripted orders and hits put a guard straight into the fight.
    pub(in crate::encounters) fn wake(&mut self) {
        self.awareness = Awareness::Aware;
    }

    /// One look along the cone of `gaze`. True on the tick the reaction to a
    /// participant it kept in sight completes: the guard is then in the fight.
    /// A guard already looking where the alarm came from (`ready`) was
    /// expecting someone and raises at once; one still turning is startled
    /// and takes the 200 to 400 ms reaction.
    fn look(
        &mut self,
        state: &GameState,
        body: &Player,
        gaze: f32,
        ready: bool,
        tick: u64,
    ) -> bool {
        let Awareness::Alerted { since, seen, .. } = self.awareness else {
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
                    && guard_sees(state, body, gaze, SIGHT_RANGE, p)
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
            (Some(_), _) if ready => {
                self.awareness = Awareness::Aware;
                self.pending_bark = Some(EnemyBarkKind::Sighting);
                return true;
            }
            (Some(id), _) => Some((id, guard_reaction(body, id, tick))),
            (None, _) => None,
        };
        self.awareness = Awareness::Alerted {
            since,
            gaze: Some(gaze),
            seen,
        };
        false
    }

    /// An awake group's guard that has not yet seen anyone: its eyes turn
    /// toward the alarm it heard, its feet go there as a dispatched guard's
    /// always have, and it does not attack. `None` once it is in the fight.
    pub(super) fn unaware_intent(&mut self, state: &GameState, tick: u64) -> Option<BotIntent> {
        let body = state.players.iter().find(|p| p.id == self.id)?;
        let (since, gaze) = match self.awareness {
            Awareness::Aware => return None,
            Awareness::Alerted { since, gaze, .. } => (since, gaze.unwrap_or(body.yaw)),
            // A group woken without an alarm reaching this guard: fight.
            Awareness::Unaware => {
                self.awareness = Awareness::Aware;
                return None;
            }
        };
        let toward = (self.last_known[2] - body.z).atan2(self.last_known[0] - body.x);
        let gaze = crate::movement::normalize_yaw(
            gaze + turn(gaze, toward).clamp(-ALERT_TURN, ALERT_TURN),
        );
        let facing_alarm = turn(gaze, toward).abs() <= ALERT_TURN;
        if self.look(state, body, gaze, facing_alarm, tick) {
            return None;
        }
        if tick >= since.saturating_add(ALERT_LIMIT) {
            self.awareness = Awareness::Aware;
            return None;
        }
        let reacting = matches!(self.awareness, Awareness::Alerted { seen: Some(_), .. });
        let feet = [body.x, body.y - PLAYER_FLOOR_Y, body.z];
        // A guard reacting to a sighting stands, as a guard that sees its
        // quarry always has; otherwise it walks to the alarm like any
        // dispatched guard that sees nobody.
        let walking = !reacting
            && super::gait(self.kind) > 0.0
            && !self.seated
            && tick <= self.search_until
            && (feet[0] - self.last_known[0]).hypot(feet[2] - self.last_known[2]) > 0.6;
        let phase = if walking {
            EnemyPhase::Moving
        } else {
            EnemyPhase::Idle
        };
        if self.phase != phase {
            self.enter(phase, tick, 0);
        }
        Some(if walking {
            BotIntent {
                action: Action {
                    forward: true,
                    yaw: Some(toward),
                    ..Default::default()
                },
                goal: Some(NavigationGoal {
                    feet: self.last_known,
                    combat: false,
                }),
            }
        } else {
            BotIntent {
                action: Action {
                    yaw: Some(gaze),
                    pitch: Some(0.0),
                    ..Default::default()
                },
                goal: None,
            }
        })
    }

    /// A line this guard would say, once.
    pub(in crate::encounters) fn take_bark(&mut self) -> Option<EnemyBarkKind> {
        self.pending_bark.take()
    }
}
