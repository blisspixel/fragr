//! Fictional identity is independent of the connection's control role.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnemyKind {
    Clerk,
    Sweeper,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnemyPhase {
    Idle,
    Moving,
    Windup,
    Firing,
    Recovery,
    Hit,
    Dead,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "side", rename_all = "snake_case", deny_unknown_fields)]
pub enum CampaignActor {
    Participant {},
    Union {
        kind: EnemyKind,
        phase: EnemyPhase,
        phase_started: u64,
        phase_ends: u64,
    },
}

impl CampaignActor {
    pub fn is_enemy(self) -> bool {
        matches!(self, Self::Union { .. })
    }
}

/// Identity, not callsign or control role, decides hostility. Missing identity
/// only enables the legacy free-for-all when both actors are legacy actors.
pub fn hostile(a: Option<CampaignActor>, b: Option<CampaignActor>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(a), Some(b)) => a.is_enemy() != b.is_enemy(),
        _ => false,
    }
}

impl super::PlayerState {
    pub fn is_hostile_to(&self, other: &Self) -> bool {
        self.id != other.id && other.hp > 0 && hostile(self.campaign, other.campaign)
    }

    pub fn is_participant(&self) -> bool {
        !self.campaign.is_some_and(CampaignActor::is_enemy)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allegiance_is_symmetric_and_missing_campaign_identity_fails_closed() {
        let union = CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
        };
        let identities = [None, Some(CampaignActor::Participant {}), Some(union)];
        for (i, a) in identities.into_iter().enumerate() {
            for (j, b) in identities.into_iter().enumerate() {
                assert_eq!(hostile(a, b), i == 0 && j == 0 || i + j == 3);
            }
        }
        let json = serde_json::to_string(&union).unwrap();
        assert_eq!(serde_json::from_str::<CampaignActor>(&json).unwrap(), union);
        for raw in [
            r#"{"side":"union","kind":"unknown"}"#,
            r#"{"side":"participant","role":"human"}"#,
            r#"{"side":"union","kind":"clerk","phase":"idle","phase_started":-1,"phase_ends":0}"#,
        ] {
            assert!(serde_json::from_str::<CampaignActor>(raw).is_err());
        }
    }
}
