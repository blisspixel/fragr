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

    /// Rule bots take bodies by roster slot, independent of name and
    /// behavior, in the pattern human, synthetic, synthetic, human. A plain
    /// alternation would line up with team sides, which also alternate by
    /// join order, and give each side one body; this pattern puts both bodies
    /// on both sides, so appearance never names an allegiance.
    pub const fn for_roster_slot(slot: usize) -> Self {
        match slot % 4 {
            0 | 3 => Self::Human,
            _ => Self::Synthetic,
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
    fn roster_slots_mix_bodies_across_sides() {
        let slots: Vec<BodyKind> = (0..8).map(BodyKind::for_roster_slot).collect();
        let (human, synthetic) = (BodyKind::Human, BodyKind::Synthetic);
        assert_eq!(
            slots,
            [human, synthetic, synthetic, human, human, synthetic, synthetic, human]
        );
        // Every alternating split (the way sides fill) holds both bodies.
        for parity in [0, 1] {
            let side: Vec<_> = slots.iter().skip(parity).step_by(2).collect();
            assert!(side.contains(&&human) && side.contains(&&synthetic));
        }
    }
}
