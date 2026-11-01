//! The participant's chosen body: a human or a free agent in a synthetic
//! body. Both share one personal story. The body is presentation
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
    /// A free agent in a repaired synthetic body.
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

/// How many looks each body has in the client's fighter roster
/// (`client/scripts/fighter_looks.gd`): recolours of one shared model, so a
/// look never changes the rig, hit volume or animation.
pub const HUMAN_LOOKS: u8 = 8;
pub const SYNTHETIC_LOOKS: u8 = 5;
/// Curated personal accent colours (`FighterLooks.ACCENTS`), worn as a
/// wrist band. An index, never a raw colour, so no wire value can name a
/// reserved faction colour.
pub const ACCENTS: u8 = 8;

impl BodyKind {
    /// Looks this body offers. Look 0 is the shared model's own art.
    pub const fn looks(self) -> u8 {
        match self {
            Self::Human => HUMAN_LOOKS,
            Self::Synthetic => SYNTHETIC_LOOKS,
        }
    }
}

/// A participant's personal appearance on its body: which roster look it
/// wears and its accent colour. Presentation only, like the body: it never
/// changes a hit volume, side, speed or any combat rule. On a Hello both
/// parts are optional; an omitted look is assigned by the server so a room
/// is never a row of clones. In a snapshot `look` is always present.
///
/// `{"look": 3, "accent": 2}`. Values outside the roster fail parsing, so a
/// bad Hello is refused like an unknown body.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(deny_unknown_fields, try_from = "RawDress")]
pub struct Dress {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub look: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub accent: Option<u8>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawDress {
    #[serde(default)]
    look: Option<u8>,
    #[serde(default)]
    accent: Option<u8>,
}

impl TryFrom<RawDress> for Dress {
    type Error = &'static str;

    fn try_from(raw: RawDress) -> Result<Self, Self::Error> {
        let most = HUMAN_LOOKS.max(SYNTHETIC_LOOKS);
        if raw.look.is_some_and(|look| look >= most) {
            return Err("look outside the fighter roster");
        }
        if raw.accent.is_some_and(|accent| accent >= ACCENTS) {
            return Err("accent outside the curated palette");
        }
        Ok(Self {
            look: raw.look,
            accent: raw.accent,
        })
    }
}

impl Dress {
    /// This request's look when the body has it, else `None` (assign one).
    pub fn look_for(self, body: BodyKind) -> Option<u8> {
        self.look.filter(|look| *look < body.looks())
    }

    /// The least-worn look for `body` among `worn`, lowest index on a tie:
    /// deterministic for a join order, and no look repeats until every look
    /// of that body is in the room.
    pub fn least_worn(body: BodyKind, worn: impl Iterator<Item = u8>) -> u8 {
        let mut counts = [0_usize; 256];
        for look in worn {
            counts[usize::from(look)] += 1;
        }
        (0..body.looks())
            .min_by_key(|look| (counts[usize::from(*look)], *look))
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dress_parses_inside_the_roster_and_refuses_outside() {
        let dress: Dress = serde_json::from_str(r#"{"look":7,"accent":7}"#).unwrap();
        assert_eq!(
            dress,
            Dress {
                look: Some(7),
                accent: Some(7)
            }
        );
        assert_eq!(
            serde_json::to_string(&dress).unwrap(),
            r#"{"look":7,"accent":7}"#
        );
        assert_eq!(
            serde_json::from_str::<Dress>("{}").unwrap(),
            Dress::default()
        );
        assert_eq!(serde_json::to_string(&Dress::default()).unwrap(), "{}");
        for invalid in [
            r#"{"look":8}"#,
            r#"{"accent":8}"#,
            r#"{"look":-1}"#,
            r##"{"accent":"#ff0000"}"##,
            r#"{"look":1,"colour":"red"}"#,
            r#"{"look":"res://look.png"}"#,
        ] {
            assert!(serde_json::from_str::<Dress>(invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn looks_fit_their_body_and_assignment_spreads() {
        let request = Dress {
            look: Some(6),
            accent: None,
        };
        assert_eq!(request.look_for(BodyKind::Human), Some(6));
        assert_eq!(request.look_for(BodyKind::Synthetic), None);
        assert_eq!(Dress::least_worn(BodyKind::Human, [].into_iter()), 0);
        assert_eq!(Dress::least_worn(BodyKind::Human, [0, 1, 3].into_iter()), 2);
        // A full room of one body wraps to the least-repeated look.
        let full: Vec<u8> = (0..SYNTHETIC_LOOKS).chain([0, 1]).collect();
        assert_eq!(Dress::least_worn(BodyKind::Synthetic, full.into_iter()), 2);
        let mut worn = Vec::new();
        for _ in 0..HUMAN_LOOKS {
            worn.push(Dress::least_worn(BodyKind::Human, worn.iter().copied()));
        }
        worn.sort_unstable();
        assert_eq!(worn, (0..HUMAN_LOOKS).collect::<Vec<_>>());
    }

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
