//! Objective credits for the hold-Tab board: who planted and defused the
//! Sabotage charge, who captured and returned flags, and who stood on a
//! Conquest point when it fell to their side. Credited at the same
//! authoritative decisions that raise the matching events; presentation reads
//! them from the snapshot and nothing scores from them.
use super::GameState;
use crate::protocol::ObjectiveTally;
use uuid::Uuid;

/// One kind of objective credit.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Credit {
    Plant,
    Defuse,
    Capture,
    Return,
}

impl GameState {
    /// Credit one objective act to a fighter, saturating.
    pub(crate) fn credit_objective(&mut self, id: Uuid, credit: Credit) {
        let tally = self.objective_tally.entry(id).or_default();
        let count = match credit {
            Credit::Plant => &mut tally.plants,
            Credit::Defuse => &mut tally.defuses,
            Credit::Capture => &mut tally.captures,
            Credit::Return => &mut tally.returns,
        };
        *count = count.saturating_add(1);
    }

    /// A fighter's credits for the snapshot, or none while every count is zero.
    pub(crate) fn objective_tally(&self, id: Uuid) -> Option<ObjectiveTally> {
        self.objective_tally
            .get(&id)
            .copied()
            .filter(|tally| !tally.is_empty())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn credits_count_per_fighter_and_stay_off_the_wire_while_zero() {
        let mut state = GameState::new();
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        assert_eq!(state.objective_tally(a), None);
        state.credit_objective(a, Credit::Plant);
        state.credit_objective(a, Credit::Plant);
        state.credit_objective(a, Credit::Defuse);
        state.credit_objective(b, Credit::Capture);
        state.credit_objective(b, Credit::Return);
        assert_eq!(
            state.objective_tally(a),
            Some(ObjectiveTally {
                plants: 2,
                defuses: 1,
                captures: 0,
                returns: 0
            })
        );
        let wire = serde_json::to_value(state.objective_tally(b).unwrap()).unwrap();
        assert_eq!(wire, serde_json::json!({"captures": 1, "returns": 1}));
        state.objective_tally.insert(a, ObjectiveTally::default());
        assert_eq!(state.objective_tally(a), None, "an empty tally is omitted");
        state.objective_tally.insert(
            a,
            ObjectiveTally {
                plants: u32::MAX,
                ..Default::default()
            },
        );
        state.credit_objective(a, Credit::Plant);
        assert_eq!(state.objective_tally(a).unwrap().plants, u32::MAX);
    }

    #[test]
    fn a_reader_refuses_unknown_tally_fields() {
        let refused: Result<ObjectiveTally, _> =
            serde_json::from_value(serde_json::json!({"plants": 1, "assists": 2}));
        assert!(refused.is_err());
        let read: ObjectiveTally = serde_json::from_value(serde_json::json!({})).unwrap();
        assert!(read.is_empty());
    }
}
