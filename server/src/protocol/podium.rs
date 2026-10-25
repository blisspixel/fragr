//! Between rounds on the wire: the podium's ready-up for an instant rematch,
//! and a Duel's running series between the same two fighters.
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// The podium while a round has ended. The next round starts on its own
/// clock; once every person and agent holding a seat has pressed for another
/// (`Action::again`), it starts as soon as the result has shown for
/// `rules::AGAIN_MIN_TICKS`. Rule bots are always ready and never counted.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Podium {
    /// Fighters who have asked for the next round, in id order.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub again: Vec<Uuid>,
    /// Seated people and agents the room waits for. Zero when only rule bots
    /// fight, which leaves the next round to its own clock.
    pub voters: u32,
    /// A Duel's series so far, present once the same two fighters have
    /// finished a round together.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duel: Option<[DuelRecord; 2]>,
}

/// One side of a Duel series: who, and how many rounds they have taken from
/// this opponent since the pair first met. Ordered by id.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DuelRecord {
    pub id: Uuid,
    pub name: String,
    pub wins: u32,
}
