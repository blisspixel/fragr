//! Level 18's turn: the delivery is made, every Union machine in the district
//! stops, their heads come round together, and the same bodies move again for
//! the Inheritance. Latch does not turn with them. Server facts only; the
//! client presents the silence and the lines from `turn_started`.
use super::*;
use crate::protocol::{M18_HEADS_TURN_TICKS, M18_LATCH_LOOKS_TICKS, M18_TURN_TICKS};

/// Latch's two lines after the turn, at the caption's reading pace.
const M18_LATCH_QUIET_TICKS: u64 = 160;

/// The group working the square when the turn comes.
const SQUARE_GROUP: usize = 0;

impl GameState {
    fn m18_progress(&self) -> Option<&M18Progress> {
        self.mission
            .as_ref()
            .filter(|run| run.phase == MissionPhase::InProgress)?
            .m18
            .as_ref()
    }

    /// Ticks since the turn began, while a Level 18 attempt is in progress.
    fn m18_turn_age(&self) -> Option<u64> {
        let started = self.m18_progress()?.turn_started?;
        Some(self.tick.saturating_sub(started))
    }

    /// Once the heads have turned, every Union machine is the Inheritance's,
    /// including groups placed later in the level.
    pub(crate) fn m18_machines_absorbed(&self) -> bool {
        self.m18_progress().is_some_and(|p| p.heads_turned)
    }

    /// Before the turn ends the square's machines are at work, not on guard:
    /// walking among them does not raise them, and neither does a shot.
    pub(crate) fn m18_group_may_wake(&self, index: usize) -> bool {
        index != SQUARE_GROUP
            || self
                .mission
                .as_ref()
                .and_then(|run| run.m18.as_ref())
                .is_none_or(|p| p.turn_ended)
    }

    /// Before the delivery the square's machines and their supervisor are
    /// placed at work (`EnemyPhase::Working`) under the recovery's ceasefire:
    /// nobody's enemy, so shots do not land and nobody aims at them. The turn
    /// is the first thing that happens to them.
    pub(crate) fn m18_group_at_work(&self, index: usize) -> bool {
        index == SQUARE_GROUP
            && self
                .mission
                .as_ref()
                .and_then(|run| run.m18.as_ref())
                .is_some_and(|p| p.turn_started.is_none())
    }

    /// While the turn holds: `Some(None)` before the heads turn, then
    /// `Some(Some(point))`, the one point every machine faces at once.
    pub(crate) fn m18_turn_hold(&self) -> Option<Option<[f32; 3]>> {
        let age = self.m18_turn_age()?;
        if age >= M18_TURN_TICKS || self.campaign_run_frozen() {
            return None;
        }
        let toward = self.map.m18_geometry().map(|g| g.overlook_console.approach);
        Some(toward.filter(|_| age >= M18_HEADS_TURN_TICKS))
    }

    /// From the turn until its two spoken lines have had their time, Latch
    /// makes no tactical callouts.
    pub(crate) fn m18_latch_quiet(&self) -> bool {
        self.m18_turn_age()
            .is_some_and(|age| age < M18_TURN_TICKS + M18_LATCH_QUIET_TICKS)
    }

    /// Latch during the turn: still, and after the machines have turned,
    /// looking at the nearest of the party. `None` outside the turn.
    pub(crate) fn m18_latch_hold(&self, feet: [f32; 3]) -> Option<Option<f32>> {
        self.m18_turn_hold()?;
        let age = self.m18_turn_age()?;
        if age < M18_LATCH_LOOKS_TICKS {
            return Some(None);
        }
        let ready = self.mission.as_ref().map(|run| &run.ready)?;
        let nearest = self
            .players
            .iter()
            .filter(|p| p.is_participant() && p.hp > 0 && ready.contains(&p.id))
            .min_by(|a, b| {
                (a.x - feet[0])
                    .hypot(a.z - feet[2])
                    .total_cmp(&(b.x - feet[0]).hypot(b.z - feet[2]))
            })?;
        Some(Some((nearest.z - feet[2]).atan2(nearest.x - feet[0])))
    }

    pub(crate) fn ensure_m18_companion(&mut self) {
        if self
            .mission
            .as_ref()
            .is_some_and(|r| r.m18.is_some() && r.phase == MissionPhase::InProgress)
        {
            if let Some(start) = self.map.m18_objectives().map(|p| p.companion_start) {
                self.spawn_campaign_companion(start, false);
            }
        }
    }

    /// Apply the turn's two server changes once each, at their ticks.
    pub(super) fn advance_m18_turn(&mut self) {
        let Some(age) = self.m18_turn_age() else {
            return;
        };
        let Some(p) = self.m18_progress() else {
            return;
        };
        let (heads_turned, turn_ended) = (p.heads_turned, p.turn_ended);
        if age >= M18_HEADS_TURN_TICKS && !heads_turned {
            let mut encounters = std::mem::take(&mut self.encounters);
            let absorbed = encounters.absorb_union_machines(&mut self.players);
            self.encounters = encounters;
            if let Some(p) = self.mission.as_mut().and_then(|r| r.m18.as_mut()) {
                p.heads_turned = true;
            }
            tracing::info!(absorbed, "M18 turn: the machines' heads come round");
        }
        if age >= M18_TURN_TICKS && !turn_ended {
            let exits = self
                .map
                .m18_objectives()
                .map(|p| p.people_exits.clone())
                .unwrap_or_default();
            let alarm = self
                .players
                .iter()
                .filter(|p| p.is_participant() && p.hp > 0)
                .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
                .next();
            let tick = self.tick;
            let mut encounters = std::mem::take(&mut self.encounters);
            if let Some(alarm) = alarm {
                encounters.end_turn(self, SQUARE_GROUP, alarm, &exits, tick);
            }
            self.encounters = encounters;
            if let Some(p) = self.mission.as_mut().and_then(|r| r.m18.as_mut()) {
                p.turn_ended = true;
            }
            tracing::info!("M18 turn: the square moves again, together");
        }
    }
}
