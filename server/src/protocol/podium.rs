//! Between rounds on the wire: the podium's ready-up for an instant rematch,
//! a Duel's running series between the same two fighters, each fighter's
//! nemesis and rivals this session, and the vote for the next map.
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
    /// Each seated fighter's nemesis and rivals this session. Omitted when
    /// nobody has met anybody.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub story: Vec<PodiumStory>,
    /// The next map, chosen by the room, on a rotating server with more
    /// than one map that can host the mode.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vote: Option<MapVote>,
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

/// Who a podium row belongs to, said plainly so a rule bot never passes for
/// a person and an agent is named as one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FighterKind {
    Human,
    Agent,
    Bot,
}

/// One fighter's book against one rival this session: frags each way since
/// this server started. Not the desktop host's long book.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PodiumRival {
    pub name: String,
    pub kind: FighterKind,
    /// This fighter's frags on the rival.
    pub won: u32,
    /// The rival's frags on this fighter.
    pub lost: u32,
}

/// One seated fighter's story for the podium: the rival it owes most this
/// session, and its closest books, most meetings first. Ordered by id.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PodiumStory {
    pub id: Uuid,
    pub name: String,
    pub kind: FighterKind,
    /// The rival present with the widest lead over this fighter this
    /// session. Omitted when nobody present is ahead of it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nemesis: Option<String>,
    /// At most three rivals present, most meetings first, then by name.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub rivals: Vec<PodiumRival>,
}

/// The map vote between rounds on a rotating server: three maps that can
/// host this mode and are switched on, in rotation order. The next round
/// loads the leader when the podium closes. Ties go to the earlier option,
/// and no votes at all to the first.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapVote {
    pub options: Vec<MapVoteOption>,
    /// Every ballot cast, in voter id order. A voter may change its vote.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub ballots: Vec<MapBallot>,
    /// The map the next round loads if the vote closed now.
    pub leader: u32,
    /// Ticks until the podium closes on its own clock.
    pub closes_in: u32,
    /// Rule bots vote only while no person or agent holds a seat; with
    /// anybody seated they abstain and the room decides.
    pub bots_vote: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapVoteOption {
    pub map_id: u32,
    pub map_name: String,
    pub votes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapBallot {
    pub id: Uuid,
    pub map_id: u32,
}
