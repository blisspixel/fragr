//! The participant's chosen body: a human or a conscious embodied agent in a
//! synthetic body. Both share one personal story. The body is presentation
//! identity only. It never selects a control role, side, faction, hit volume,
//! speed, health or access, and it does not establish moral status.

use serde::{Deserialize, Serialize};

/// Allowlisted body kinds. The wire never carries a resource path or model
/// name, so an unknown string fails Hello parsing before admission.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BodyKind {
    /// The default for every role when a hello omits the body.
    #[default]
    Human,
    /// A conscious embodied agent in a repaired synthetic body.
    Synthetic,
}

impl BodyKind {
    pub const ALL: [Self; 2] = [Self::Human, Self::Synthetic];

    pub const fn id(self) -> &'static str {
        match self {
            Self::Human => "human",
            Self::Synthetic => "synthetic",
        }
    }

    /// Rule bots alternate by roster slot, independent of name and behavior,
    /// so a four-bot room always shows both bodies.
    pub const fn for_roster_slot(slot: usize) -> Self {
        if slot.is_multiple_of(2) {
            Self::Human
        } else {
            Self::Synthetic
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_round_trip_and_unknown_values_fail() {
        for body in BodyKind::ALL {
            let json = serde_json::to_string(&body).unwrap();
            assert_eq!(json, format!("\"{}\"", body.id()));
            assert_eq!(serde_json::from_str::<BodyKind>(&json).unwrap(), body);
        }
        for invalid in [
            "\"Human\"",
            "\"robot\"",
            "\"res://body.png\"",
            "7",
            "true",
            "{\"kind\":\"synthetic\"}",
        ] {
            assert!(
                serde_json::from_str::<BodyKind>(invalid).is_err(),
                "{invalid}"
            );
        }
        assert_eq!(BodyKind::default(), BodyKind::Human);
    }

    #[test]
    fn roster_slots_alternate_bodies() {
        let slots: Vec<BodyKind> = (0..4).map(BodyKind::for_roster_slot).collect();
        assert_eq!(
            slots,
            [
                BodyKind::Human,
                BodyKind::Synthetic,
                BodyKind::Human,
                BodyKind::Synthetic
            ]
        );
    }
}
