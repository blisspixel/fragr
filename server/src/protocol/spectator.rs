//! The booth: facts the server sends only to connections that watch and never
//! fight. A fighter learns pad clocks the way a regular does, by watching a
//! pad empty and counting, and never sees another fighter's spree or open
//! multikill chain as a number. A spectator's broadcast gets them all, so a
//! caster or a director can cut to the fight that is about to happen.
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Ticks between two booth fact messages: four a second, enough to count a
/// clock down smoothly between them.
pub const SPECTATOR_FACTS_EVERY_TICKS: u64 = 5;
/// Pads a booth message lists at most. Larak Lot has fewer than twenty.
pub const MAX_SPECTATOR_PADS: usize = 64;
/// Sprees and chains a booth message lists at most, longest first.
pub const MAX_SPECTATOR_RUNS: usize = 16;

/// One booth message. Never sent on a campaign map, and never to a
/// connection that holds a fighter.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SpectatorFacts {
    /// The tick these facts describe.
    pub tick: u64,
    /// Frags without dying that make a spree tier in this mode, so a reader
    /// can tell a run worth cutting to without knowing the rule sheet.
    pub spree_step: u32,
    /// Every pad that is down and will come back, soonest first. The Custody
    /// Plate is reported on its own in `plate`, never here.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub pads: Vec<PadClock>,
    /// The power item, when the map lays one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plate: Option<PlateFact>,
    /// Fighters on a run of two or more frags without dying, longest first.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sprees: Vec<SpreeFact>,
    /// Multikill chains still open: two or more frags, each inside the
    /// window of the last. Most frags first.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub chains: Vec<ChainFact>,
}

/// A down pad's live return clock.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PadClock {
    /// The pad's id in the snapshot's `pickups`.
    pub id: String,
    /// The snapshot's pickup kind: `weapon`, `health`, `armor`, ...
    pub kind: String,
    /// The gun on a weapon pad. Omitted for every other kind.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub weapon: String,
    /// A pad worth timing: a gun better than the Flechette or the sidearm,
    /// or armour.
    #[serde(default, skip_serializing_if = "is_false")]
    pub power: bool,
    /// Ticks until the pad is back.
    pub back_in: u32,
}

/// The Custody Plate: whether it waits on its pad, when it returns, and who
/// is wearing plated armour (armour above the ordinary cap, which only the
/// Plate grants and which drains back a point a second).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlateFact {
    /// The pad's id in the snapshot's `pickups`.
    pub id: String,
    pub up: bool,
    /// Ticks until the Plate is back. Omitted while it is up.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub back_in: Option<u32>,
    /// The living fighter with the most plated armour. Omitted when nobody
    /// is over the ordinary cap.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub holder: Option<Uuid>,
    /// That fighter's whole armour, plate included.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub armor: Option<i32>,
}

/// A run of frags without dying.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SpreeFact {
    pub id: Uuid,
    pub frags: u32,
}

/// An open multikill chain.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChainFact {
    pub id: Uuid,
    pub frags: u32,
    /// Ticks left for the next frag to extend the chain.
    pub open_for: u32,
}

fn is_false(value: &bool) -> bool {
    !value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn booth_facts_round_trip_and_omit_empty_lists() {
        let id = Uuid::from_u128(3);
        let facts = SpectatorFacts {
            tick: 40,
            spree_step: 5,
            pads: vec![PadClock {
                id: "larak_rail".into(),
                kind: "weapon".into(),
                weapon: "Rail".into(),
                power: true,
                back_in: 120,
            }],
            plate: Some(PlateFact {
                id: "larak_custody_plate".into(),
                up: false,
                back_in: Some(300),
                holder: Some(id),
                armor: Some(143),
            }),
            sprees: vec![SpreeFact { id, frags: 6 }],
            chains: vec![ChainFact {
                id,
                frags: 2,
                open_for: 30,
            }],
        };
        let message = super::super::ServerMessage::SpectatorFacts(facts.clone());
        let text = serde_json::to_string(&message).unwrap();
        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(value["type"], "spectator_facts");
        assert_eq!(value["pads"][0]["back_in"], 120);
        assert_eq!(value["plate"]["holder"], id.to_string());
        match serde_json::from_str(&text).unwrap() {
            super::super::ServerMessage::SpectatorFacts(back) => assert_eq!(back, facts),
            other => panic!("not booth facts: {other:?}"),
        }
        let quiet = SpectatorFacts {
            tick: 1,
            spree_step: 3,
            pads: Vec::new(),
            plate: None,
            sprees: Vec::new(),
            chains: Vec::new(),
        };
        let value =
            serde_json::to_value(super::super::ServerMessage::SpectatorFacts(quiet)).unwrap();
        for absent in ["pads", "plate", "sprees", "chains"] {
            assert!(
                value.get(absent).is_none(),
                "{absent} is omitted when empty"
            );
        }
        let unknown = r#"{"type":"spectator_facts","tick":1,"spree_step":3,"hp":[1]}"#;
        assert!(serde_json::from_str::<super::super::ServerMessage>(unknown).is_err());
    }
}
