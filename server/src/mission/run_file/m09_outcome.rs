//! Immutable berth facts. Transit completion belongs to a later M10 handoff.
use super::*;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum M09Outcome {
    Recorded {
        released_crew: Vec<String>,
        aboard_at_departure: Vec<String>,
    },
    HistoricalUnrecorded {},
}

impl M09Outcome {
    pub(crate) fn capture(
        crew: &[crate::protocol::M09CrewState],
        boarding: &crate::protocol::Region3,
    ) -> Self {
        Self::Recorded {
            released_crew: crew.iter().map(|c| c.id.clone()).collect(),
            aboard_at_departure: crew
                .iter()
                .filter(|c| boarding.contains(c.feet))
                .map(|c| c.id.clone())
                .collect(),
        }
    }

    pub(super) fn validate(&self, document: &RunDocument) -> Result<(), &'static str> {
        let Self::Recorded {
            released_crew,
            aboard_at_departure,
        } = self
        else {
            return Ok(());
        };
        let edda = document
            .m04_outcome
            .as_ref()
            .is_some_and(|o| !o.rescued_patients.is_empty());
        let splice = document
            .m05_outcome
            .as_ref()
            .is_some_and(|o| o.evacuated_workers.iter().any(|id| id == "splice"));
        let expected: Vec<_> = crate::protocol::M09_CREW_IDS
            .into_iter()
            .filter(|id| (*id != "edda" || edda) && (*id != "splice" || splice))
            .collect();
        if released_crew.iter().map(String::as_str).collect::<Vec<_>>() != expected {
            return Err("saved berth release does not match the actual eligible roster");
        }
        let mut next = 0;
        for id in aboard_at_departure {
            let Some(offset) = released_crew[next..]
                .iter()
                .position(|released| released == id)
            else {
                return Err("saved berth boarding is not an ordered subset of released crew");
            };
            next += offset + 1;
        }
        Ok(())
    }
}
