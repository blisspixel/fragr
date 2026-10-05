//! Separately counted deliberate charges. No weapon or proximity-mine identity
//! changes meaning when the owner earns this gadget.
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const REMOTE_MINE_CARRY_CAP: u16 = 6;
pub const REMOTE_MINE_ARMING_TICKS: u64 = 40;
pub const REMOTE_MINE_TRIGGER_TICKS: u64 = 4;
const MAX_EXACT_JSON_INTEGER: u64 = (1_u64 << 53) - 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RemoteMinePhase {
    Flying,
    Arming,
    Armed,
    Triggered,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RemoteMineState {
    pub id: u32,
    pub owner_id: Uuid,
    pub position: [f32; 3],
    /// Unit surface normal after contact; exactly zero during flight.
    pub normal: [f32; 3],
    pub phase: RemoteMinePhase,
    pub phase_started: u64,
    pub phase_ends: u64,
}

impl RemoteMineState {
    /// Bound a complete snapshot collection, including shared projectile ids
    /// already used by the current proximity-mine collection.
    pub fn validate_set(
        remotes: &[Self],
        mines: &[super::MineState],
        tick: u64,
    ) -> Result<(), &'static str> {
        if remotes.len() > 32 {
            return Err("too many live Remote Mines");
        }
        let mut ids: std::collections::BTreeSet<u32> = mines.iter().map(|mine| mine.id).collect();
        let mut owners = std::collections::BTreeMap::<Uuid, usize>::new();
        for remote in remotes {
            remote.validate(tick)?;
            if !ids.insert(remote.id) {
                return Err("Remote Mine id aliases a placed device");
            }
            let count = owners.entry(remote.owner_id).or_default();
            *count += 1;
            if *count > 4 {
                return Err("too many owned Remote Mines");
            }
        }
        Ok(())
    }

    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        let finite = self
            .position
            .iter()
            .chain(&self.normal)
            .all(|value| value.is_finite() && value.abs() <= 1024.0);
        let length = self
            .normal
            .iter()
            .map(|value| value * value)
            .sum::<f32>()
            .sqrt();
        let normal_ok = match self.phase {
            RemoteMinePhase::Flying => length == 0.0,
            _ => (length - 1.0).abs() <= 0.001,
        };
        let duration = match self.phase {
            RemoteMinePhase::Flying | RemoteMinePhase::Armed => 0,
            RemoteMinePhase::Arming => REMOTE_MINE_ARMING_TICKS,
            RemoteMinePhase::Triggered => REMOTE_MINE_TRIGGER_TICKS,
        };
        if self.id == 0
            || !finite
            || !normal_ok
            || self.phase_started > tick
            || tick > MAX_EXACT_JSON_INTEGER
            || self.phase_ends > MAX_EXACT_JSON_INTEGER
            || self.phase_started.checked_add(duration) != Some(self.phase_ends)
        {
            return Err("invalid remote mine state");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state(phase: RemoteMinePhase) -> RemoteMineState {
        let duration = match phase {
            RemoteMinePhase::Arming => REMOTE_MINE_ARMING_TICKS,
            RemoteMinePhase::Triggered => REMOTE_MINE_TRIGGER_TICKS,
            _ => 0,
        };
        RemoteMineState {
            id: 1,
            owner_id: Uuid::from_u128(1),
            position: [1.0, 0.5, 2.0],
            normal: if phase == RemoteMinePhase::Flying {
                [0.0; 3]
            } else {
                [0.0, 1.0, 0.0]
            },
            phase,
            phase_started: 60,
            phase_ends: 60 + duration,
        }
    }

    #[test]
    fn remote_collection_refuses_aliases_owner_overflow_and_global_overflow() {
        let mut remotes = Vec::new();
        for id in 1..=32 {
            let mut remote = state(RemoteMinePhase::Armed);
            remote.id = id;
            remote.owner_id = Uuid::from_u128(u128::from((id - 1) / 4 + 1));
            remotes.push(remote);
        }
        RemoteMineState::validate_set(&remotes, &[], 60).unwrap();
        let mut over = remotes.clone();
        over.push(state(RemoteMinePhase::Armed));
        assert!(RemoteMineState::validate_set(&over, &[], 60).is_err());
        let mut over = remotes[..5].to_vec();
        over[4].owner_id = over[0].owner_id;
        assert!(RemoteMineState::validate_set(&over, &[], 60).is_err());
        let mut alias = remotes[..2].to_vec();
        alias[1].id = alias[0].id;
        assert!(RemoteMineState::validate_set(&alias, &[], 60).is_err());
        let proximity = super::super::MineState {
            id: 1,
            owner_id: Uuid::from_u128(55),
            position: [0.0, 0.12, 0.0],
            normal: [0.0, 1.0, 0.0],
            phase: super::super::MinePhase::Armed,
            phase_started: 50,
            phase_ends: 50,
        };
        assert!(RemoteMineState::validate_set(&remotes, &[proximity], 60).is_err());
    }

    #[test]
    fn remote_mine_state_has_strict_distinct_phases_and_windows() {
        for phase in [
            RemoteMinePhase::Flying,
            RemoteMinePhase::Arming,
            RemoteMinePhase::Armed,
            RemoteMinePhase::Triggered,
        ] {
            let state = state(phase);
            state.validate(60).unwrap();
            let value = serde_json::to_value(&state).unwrap();
            assert_eq!(
                serde_json::from_value::<RemoteMineState>(value.clone()).unwrap(),
                state
            );
            for (field, bad) in [
                ("phase", serde_json::json!("tripped")),
                ("phase", serde_json::json!("detonated")),
                ("position", serde_json::json!([0, 0])),
                ("normal", serde_json::json!([0, 1, 0, 0])),
                ("id", serde_json::json!(-1)),
                ("unknown", serde_json::json!(true)),
            ] {
                let mut bad_state = value.clone();
                bad_state[field] = bad;
                assert!(serde_json::from_value::<RemoteMineState>(bad_state).is_err());
            }
            for field in [
                "id",
                "owner_id",
                "position",
                "normal",
                "phase",
                "phase_started",
                "phase_ends",
            ] {
                let mut bad_state = value.clone();
                bad_state.as_object_mut().unwrap().remove(field);
                assert!(serde_json::from_value::<RemoteMineState>(bad_state).is_err());
            }
            let mut invalid = state.clone();
            invalid.phase_ends += 1;
            assert!(invalid.validate(60).is_err());
            assert!(state.validate(59).is_err());
        }
    }

    #[test]
    fn remote_mine_state_rejects_nonfinite_normals_bounds_and_overflow() {
        let good = state(RemoteMinePhase::Armed);
        for position in [
            [f32::NAN, 0.0, 0.0],
            [0.0, f32::INFINITY, 0.0],
            [1024.1, 0.0, 0.0],
        ] {
            let mut bad = good.clone();
            bad.position = position;
            assert!(bad.validate(60).is_err());
        }
        for normal in [[0.0; 3], [0.0, 2.0, 0.0], [0.0, f32::NAN, 0.0]] {
            let mut bad = good.clone();
            bad.normal = normal;
            assert!(bad.validate(60).is_err());
        }
        let mut bad = state(RemoteMinePhase::Flying);
        bad.normal = [0.0, 1.0, 0.0];
        assert!(bad.validate(60).is_err());
        bad = state(RemoteMinePhase::Arming);
        bad.phase_started = u64::MAX - 1;
        bad.phase_ends = u64::MAX;
        assert!(bad.validate(u64::MAX).is_err());
        bad = good;
        bad.id = 0;
        assert!(bad.validate(60).is_err());
    }

    #[test]
    fn remote_mine_wire_matches_shared_client_boundary_vectors() {
        let cases: Vec<serde_json::Value> = serde_json::from_str(include_str!(
            "../../../client/golden/remote_mine_vectors.json"
        ))
        .unwrap();
        assert_eq!(cases.len(), 18);
        for case in cases {
            let tick = case["tick"].as_u64().unwrap();
            let accepted = serde_json::from_value::<RemoteMineState>(case["state"].clone())
                .is_ok_and(|state| state.validate(tick).is_ok());
            assert_eq!(
                accepted,
                case["valid"].as_bool().unwrap(),
                "{}",
                case["name"]
            );
        }
    }
}
