//! Bounded, opt-in diagnostic trace for one campaign participant.
use crate::plan::Plan;
use fragr_server::protocol::{
    Action, CampaignRunStatus, GameEvent, LoadoutState, MissionGeometry, MissionPhase,
    MissionState, Snapshot, WeaponType,
};
use serde::Serialize;
use std::collections::VecDeque;
use std::path::Path;
use uuid::Uuid;

const MAX_POINTS: usize = 2048;
const SAMPLE_TICKS: u64 = 20;

#[derive(Debug, Serialize)]
struct Point {
    tick: u64,
    attempt: u32,
    phase: MissionPhase,
    status: Option<CampaignRunStatus>,
    kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    position: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    objective_distance: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    hp: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    armor: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    weapon: Option<WeaponType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    magazine: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    target: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    goal_xz: Option<[f32; 2]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    navigating: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    stance: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    forward: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    raw_hit_damage: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pickup: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    claims: Option<usize>,
}

impl Point {
    fn marker(tick: u64, state: &MissionState, kind: &'static str) -> Self {
        Self {
            tick,
            attempt: state.attempt,
            phase: state.phase,
            status: state.run.map(|run| run.status),
            kind,
            position: None,
            objective_distance: None,
            hp: None,
            armor: None,
            weapon: None,
            magazine: None,
            target: None,
            goal_xz: None,
            navigating: None,
            stance: None,
            forward: None,
            raw_hit_damage: None,
            pickup: None,
            claims: None,
        }
    }
}

#[derive(Debug, Default)]
pub struct Timeline {
    points: VecDeque<Point>,
    dropped: u64,
    sampled_tick: Option<(u32, u64)>,
}

impl Timeline {
    fn push(&mut self, point: Point) {
        if self.points.len() == MAX_POINTS {
            self.points.pop_front();
            self.dropped += 1;
        }
        self.points.push_back(point);
    }

    pub fn mission(&mut self, tick: u64, state: &MissionState) {
        let changed = self.points.back().is_none_or(|last| {
            last.attempt != state.attempt
                || last.phase != state.phase
                || last.status != state.run.map(|run| run.status)
        });
        if changed {
            self.push(Point::marker(tick, state, "mission"));
        }
    }

    pub fn event(&mut self, tick: u64, state: &MissionState, id: Uuid, event: &GameEvent) {
        match event {
            GameEvent::Hit {
                target_id, damage, ..
            } if *target_id == id => {
                let mut point = Point::marker(tick, state, "damage");
                point.raw_hit_damage = Some(*damage);
                self.push(point);
            }
            GameEvent::Pickup {
                player_id,
                pickup_id,
                ..
            } if *player_id == id => {
                let mut point = Point::marker(tick, state, "pickup");
                point.pickup = Some(pickup_id.clone());
                self.push(point);
            }
            _ => {}
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn sample(
        &mut self,
        id: Uuid,
        snapshot: &Snapshot,
        state: &MissionState,
        geometry: Option<&MissionGeometry>,
        loadout: Option<&LoadoutState>,
        plan: &Plan,
        intent: &Action,
        action: &Action,
    ) {
        if self.sampled_tick.is_some_and(|(attempt, tick)| {
            attempt == state.attempt && snapshot.tick.saturating_sub(tick) < SAMPLE_TICKS
        }) {
            return;
        }
        let Some(me) = snapshot.players.iter().find(|player| player.id == id) else {
            return;
        };
        self.sampled_tick = Some((state.attempt, snapshot.tick));
        let goal = state
            .m02
            .as_ref()
            .and_then(|m02| m02.current.as_ref())
            .map(|step| match &step.action {
                fragr_server::protocol::MissionObjectiveAction::Arrival { feet, .. } => *feet,
                fragr_server::protocol::MissionObjectiveAction::Use { target } => target.approach,
            })
            .or_else(|| {
                geometry.map(|map| match state.phase {
                    MissionPhase::FindTransfer
                    | MissionPhase::Briefing
                    | MissionPhase::InProgress => map.record.approach,
                    MissionPhase::ReachLift | MissionPhase::Departed => map.departure.approach,
                })
            });
        let objective_distance = goal.map(|goal| {
            ((me.x - goal[0]).powi(2)
                + (me.y - fragr_server::sim::PLAYER_FLOOR_Y - goal[1]).powi(2)
                + (me.z - goal[2]).powi(2))
            .sqrt()
        });
        let selected = loadout.map(|equipment| equipment.selected);
        self.push(Point {
            tick: snapshot.tick,
            attempt: state.attempt,
            phase: state.phase,
            status: state.run.map(|run| run.status),
            kind: "sample",
            position: Some([me.x, me.y, me.z]),
            objective_distance,
            hp: Some(me.hp),
            armor: Some(me.armor),
            weapon: selected,
            magazine: selected.and_then(|weapon| loadout?.weapon(weapon)?.magazine),
            target: intent.look_at.as_ref().and_then(|look| look.player_id),
            goal_xz: intent
                .look_at
                .as_ref()
                .and_then(|look| Some([look.x?, look.z?])),
            navigating: Some(action.yaw.is_some() && action.look_at.is_none()),
            stance: Some(plan.stance.name()),
            forward: Some(action.forward),
            raw_hit_damage: None,
            pickup: None,
            claims: loadout.map(|equipment| equipment.personal_claims.len()),
        });
    }

    pub fn write(&self, path: &Path, id: Option<Uuid>) -> Result<(), crate::Error> {
        let parent = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty());
        if let Some(parent) = parent {
            std::fs::create_dir_all(parent)?;
        }
        let text = serde_json::to_vec_pretty(&serde_json::json!({
            "version": 1,
            "player_id": id,
            "dropped": self.dropped,
            "points": self.points,
        }))
        .map_err(|error| crate::Error::Malformed(error.to_string()))?;
        std::fs::write(path, text)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::telemetry::fixtures::{player, snapshot};
    use fragr_server::protocol::{CampaignDifficulty, CampaignRules, MissionId};

    fn state(attempt: u32) -> MissionState {
        MissionState {
            id: MissionId::RecallNotice,
            run: None,
            rules: CampaignRules::new(CampaignDifficulty::Standard),
            attempt,
            phase: MissionPhase::FindTransfer,
            changed_at: 0,
            party: vec![],
            prompts: vec![],
            m02: None,
        }
    }

    #[test]
    fn bounds_trace_and_retains_attempt_boundary() {
        let mut trace = Timeline::default();
        for tick in 0..=MAX_POINTS as u64 {
            trace.push(Point::marker(tick, &state(1), "damage"));
        }
        assert_eq!(trace.points.len(), MAX_POINTS);
        assert_eq!(trace.dropped, 1);
        trace.mission(9999, &state(2));
        let last = trace.points.back().unwrap();
        assert_eq!(last.attempt, 2);
        assert_eq!(last.kind, "mission");
    }

    #[test]
    fn only_own_damage_and_pickups_enter_trace() {
        let own = Uuid::new_v4();
        let other = Uuid::new_v4();
        let mut trace = Timeline::default();
        let hit = GameEvent::Hit {
            shooter: "Guard".into(),
            shooter_id: other,
            target: "Fighter".into(),
            target_id: other,
            damage: 8,
            target_hp_after: 92,
        };
        trace.event(12, &state(1), own, &hit);
        assert!(trace.points.is_empty());
        if let GameEvent::Hit { target_id, .. } = &hit {
            let mut own_hit = hit.clone();
            if let GameEvent::Hit { target_id: id, .. } = &mut own_hit {
                *id = own;
            }
            assert_eq!(*target_id, other);
            trace.event(13, &state(1), own, &own_hit);
        }
        assert_eq!(trace.points.len(), 1);
        assert_eq!(trace.points[0].raw_hit_damage, Some(8));
        let pickup = GameEvent::Pickup {
            player: "Fighter".into(),
            player_id: other,
            kind: "health".into(),
            weapon: String::new(),
            amount: Some(25),
            pickup_id: "medkit".into(),
        };
        trace.event(14, &state(1), own, &pickup);
        assert_eq!(trace.points.len(), 1);
        let GameEvent::Pickup { player_id, .. } = &pickup else {
            unreachable!()
        };
        let mut own_pickup = pickup.clone();
        if let GameEvent::Pickup { player_id: id, .. } = &mut own_pickup {
            *id = own;
        }
        assert_eq!(*player_id, other);
        trace.event(15, &state(1), own, &own_pickup);
        assert_eq!(trace.points.len(), 2);
        assert_eq!(trace.points[1].pickup.as_deref(), Some("medkit"));
    }

    #[test]
    fn samples_one_participant_once_per_second_and_restarts_on_retry() {
        let own = Uuid::from_u128(1);
        let other = Uuid::from_u128(2);
        let players = vec![
            player("Fighter", own, 2.0, 3.0, 75, "tack"),
            player("Other", other, 9.0, 9.0, 8, "flechette"),
        ];
        let mut trace = Timeline::default();
        for tick in [1, 19, 21, 22] {
            trace.sample(
                own,
                &snapshot(tick, players.clone(), vec![]),
                &state(1),
                None,
                None,
                &Plan::default(),
                &Action::default(),
                &Action::default(),
            );
        }
        assert_eq!(trace.points.len(), 2);
        assert_eq!(trace.points[0].position, Some([2.0, 1.0, 3.0]));
        assert_eq!(trace.points[1].tick, 21);
        trace.sample(
            own,
            &snapshot(22, players, vec![]),
            &state(2),
            None,
            None,
            &Plan::default(),
            &Action::default(),
            &Action::default(),
        );
        assert_eq!(trace.points.len(), 3);
        assert_eq!(trace.points[2].attempt, 2);
    }
}
