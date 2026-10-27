//! Campaign chatter: short Union squad radio and Latch's callouts. The server
//! sends only the fact (kind, register, variant, speaker); the client owns the
//! words, the caption and the recording slot.

use serde::{Deserialize, Serialize};

/// Variants per bark kind, rotated so a player hears each in turn.
pub const BARK_VARIANTS: u8 = 3;

/// What a Union squad says over its radio.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnemyBarkKind {
    /// A guard on post saw a participant and its group woke.
    Sighting,
    /// A skirmisher leaves the line to go around while an anchor fires.
    Flanking,
    /// The group's Auditor went down.
    OfficerDown,
}

impl EnemyBarkKind {
    pub const ALL: [Self; 3] = [Self::Sighting, Self::Flanking, Self::OfficerDown];
}

/// Who is speaking on the Union side. Human personnel give short orders;
/// issued units recite the boilerplate the Office loaded.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BarkRegister {
    Personnel,
    Unit,
}

/// What Latch calls out to the party.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CompanionBarkKind {
    /// A raised gun behind a participant's shoulder.
    FlankWarning,
    /// A target worth taking first; `subject` names it.
    PriorityTarget,
    /// A participant has taken heavy damage.
    LowHealth,
}

impl CompanionBarkKind {
    pub const ALL: [Self; 3] = [Self::FlankWarning, Self::PriorityTarget, Self::LowHealth];
}
