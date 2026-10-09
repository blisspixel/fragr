//! Exact authored geometry replacements, separate from document revisions.
use super::store::{stage_index, ContentHashes};
use super::{RunDocument, SavedStep};
use crate::protocol::MissionId;
use serde::Deserialize;

struct Upgrade {
    mission: MissionId,
    predecessor: [u8; 32],
    successor: [u8; 32],
    first_version: u64,
}

// A future canonical replacement must register its own reviewed exact pair.
// An expected hash supplied by a caller never establishes a new successor.
const UPGRADES: [Upgrade; 5] = [
    Upgrade {
        mission: MissionId::CustodianOfRecord,
        predecessor: digest(b"b9964704b9bf51e837118f25fbec9d93574d16634b1d281caf694181f44de666"),
        successor: digest(b"00ec523f6f9ced8cd426023247370d0f478f004570e82c9d756f52ff61829864"),
        first_version: 9,
    },
    Upgrade {
        mission: MissionId::PassengerManifest,
        predecessor: digest(b"4f45d0c5132dbc741537f83e541a97c8a4f8dd130ed0d74bde45f73eecff7381"),
        successor: digest(b"3197bbcf7a48ede2dea0a06a20ea62e8367c552cc39d671a96d625d860287c85"),
        first_version: 10,
    },
    Upgrade {
        mission: MissionId::CommonCarrier,
        predecessor: digest(b"d767c07691a88d810d945db952b7cda6c67ab968b2e1b6161a1f00790eeda49d"),
        successor: digest(b"dcc8e4c1039feec32ef956bba05b94271ad7350658358880df097cafc9407557"),
        first_version: 13,
    },
    Upgrade {
        mission: MissionId::TermsOfCooperation,
        predecessor: digest(b"8f84cca779909790d23c8af2fa59db38bb25c9b94f4422a969e79180a137c78d"),
        successor: digest(b"c30871c5e11f9792eb8353158b94e27335b4d14a7c65ee5ac28b1c0f99a91431"),
        first_version: 15,
    },
    Upgrade {
        mission: MissionId::PassengerManifest,
        predecessor: digest(b"01471a5ff4d5c3861018efcc87a547a3b86305c5ecba6e02745457f69b4f5397"),
        successor: digest(b"3197bbcf7a48ede2dea0a06a20ea62e8367c552cc39d671a96d625d860287c85"),
        first_version: 15,
    },
];

const fn digest(hex: &[u8; 64]) -> [u8; 32] {
    const fn nibble(byte: u8) -> u8 {
        match byte {
            b'0'..=b'9' => byte - b'0',
            b'a'..=b'f' => byte - b'a' + 10,
            _ => panic!("invalid registered geometry digest"),
        }
    }
    let mut bytes = [0; 32];
    let mut index = 0;
    while index < bytes.len() {
        bytes[index] = nibble(hex[index * 2]) * 16 + nibble(hex[index * 2 + 1]);
        index += 1;
    }
    bytes
}

// This projection selects the validation world only. The complete strict
// historical decoder still checks every field, step and supported stage.
#[derive(Deserialize)]
struct Identity {
    version: u64,
    content_sha256: [u8; 32],
    step: IdentityStep,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum IdentityStep {
    MissionEntry { mission: MissionId },
    PendingContinue { mission: MissionId },
    Failed { mission: MissionId },
    Abandoned { mission: MissionId },
    AwaitingMission { completed_mission: MissionId },
}

impl IdentityStep {
    fn mission(&self) -> MissionId {
        match self {
            Self::MissionEntry { mission }
            | Self::PendingContinue { mission }
            | Self::Failed { mission }
            | Self::Abandoned { mission } => *mission,
            Self::AwaitingMission { completed_mission } => *completed_mission,
        }
    }
}

fn registered(
    mission: MissionId,
    predecessor: [u8; 32],
    hashes: ContentHashes,
) -> Option<&'static Upgrade> {
    UPGRADES.iter().find(|upgrade| {
        upgrade.mission == mission
            && upgrade.predecessor == predecessor
            && upgrade.successor == hashes[stage_index(mission)]
    })
}

pub(super) fn validation_hashes(value: &serde_json::Value, hashes: ContentHashes) -> ContentHashes {
    let Ok(identity) = serde_json::from_value::<Identity>(value.clone()) else {
        return hashes;
    };
    let mission = identity.step.mission();
    let Some(upgrade) = registered(mission, identity.content_sha256, hashes) else {
        return hashes;
    };
    if identity.version < upgrade.first_version {
        return hashes;
    }
    let mut historical = hashes;
    historical[stage_index(mission)] = upgrade.predecessor;
    historical
}

/// Called only after the entire document passed its actual world's validation.
/// Completion and closed history retain the content that was actually played.
pub(super) fn normalize_entry(document: &mut RunDocument, hashes: ContentHashes) {
    if matches!(
        document.step,
        SavedStep::MissionEntry { .. } | SavedStep::PendingContinue { .. }
    ) {
        if let Some(upgrade) = registered(document.stage_mission(), document.content_sha256, hashes)
        {
            document.content_sha256 = upgrade.successor;
        }
    }
}

#[cfg(test)]
pub(super) fn pairs() -> impl Iterator<Item = (MissionId, [u8; 32], [u8; 32])> {
    UPGRADES
        .iter()
        .map(|upgrade| (upgrade.mission, upgrade.predecessor, upgrade.successor))
}

#[cfg(test)]
pub(super) fn first_version(mission: MissionId, predecessor: [u8; 32]) -> u64 {
    UPGRADES
        .iter()
        .find(|upgrade| upgrade.mission == mission && upgrade.predecessor == predecessor)
        .unwrap()
        .first_version
}
