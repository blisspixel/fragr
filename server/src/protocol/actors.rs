//! Fictional identity is independent of the connection's control role.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnemyKind {
    Clerk,
    Sweeper,
    /// Broad armored bot: slow gait, long suppressive burst, staggers only on
    /// a heavy hit.
    HeavySweeper,
    /// Low constrained chassis that commits to a short leaping attack.
    Crawler,
    /// Fixed equipment with a sweeping head, a spin-up tell and one strong shot.
    Turret,
    /// Exposed service chassis that launches a slow interference pulse.
    Jammer,
    /// Flying Office patrol equipment with a committed photographic flash.
    Notary,
    /// Human custody officer with a shield plate who channels a bounded
    /// repair into disabled Union bots.
    Auditor,
    /// Stationary marksman bot with an antenna mast: a scope glint, a held
    /// aim, then one precision shot.
    RangedSweeper,
    /// Committed human elite with issued powered armor and a locked charge.
    Enforcer,
    /// Ordinary human covert guard with a visible approach and locked close strike.
    Redactor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnemyPhase {
    Idle,
    Moving,
    Windup,
    Leaping,
    Firing,
    Recovery,
    Hit,
    Dead,
    /// An Auditor holding a repair channel on a disabled body.
    Channeling,
    /// An Enforcer's straight, committed ground charge.
    Charging,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CompanionKind {
    Latch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CompanionPhase {
    Releasing,
    Following,
    Firing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "side", rename_all = "snake_case", deny_unknown_fields)]
pub enum CampaignActor {
    Participant {},
    Companion {
        kind: CompanionKind,
        phase: CompanionPhase,
        phase_started: u64,
    },
    Union {
        kind: EnemyKind,
        phase: EnemyPhase,
        phase_started: u64,
        phase_ends: u64,
        /// Authored opening pose only while a dormant Clerk sits at a station.
        #[serde(default, skip_serializing_if = "not_seated")]
        seated: bool,
    },
}

fn not_seated(seated: &bool) -> bool {
    !seated
}

/// One living Auditor's repair budget and current channel. The channel's
/// window is the Auditor's own `channeling` phase.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuditorState {
    pub id: uuid::Uuid,
    /// Completed repairs it may still make, two at most.
    pub repairs_left: u8,
    /// The disabled body its channel reaches, only while channeling.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel_target: Option<uuid::Uuid>,
}

/// Completed repairs one Auditor may make. Never a third.
pub const AUDITOR_REPAIRS: u8 = 2;

impl CampaignActor {
    pub fn is_enemy(self) -> bool {
        matches!(self, Self::Union { .. })
    }

    pub fn is_participant(self) -> bool {
        matches!(self, Self::Participant {})
    }

    pub fn is_companion(self) -> bool {
        matches!(self, Self::Companion { .. })
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
    /// Worth aiming at: alive, on the other side of the campaign, and not a
    /// teammate. Friendly fire never makes a teammate a target.
    pub fn is_hostile_to(&self, other: &Self) -> bool {
        self.id != other.id
            && other.hp > 0
            && hostile(self.campaign, other.campaign)
            && (self.team.is_none() || self.team != other.team)
    }

    pub fn is_participant(&self) -> bool {
        self.campaign.is_none_or(CampaignActor::is_participant)
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
            seated: false,
        };
        let companion = CampaignActor::Companion {
            kind: CompanionKind::Latch,
            phase: CompanionPhase::Releasing,
            phase_started: 42,
        };
        let identities = [
            None,
            Some(CampaignActor::Participant {}),
            Some(union),
            Some(companion),
        ];
        for (i, a) in identities.into_iter().enumerate() {
            for (j, b) in identities.into_iter().enumerate() {
                assert_eq!(
                    hostile(a, b),
                    i == 0 && j == 0
                        || (i == 2 && matches!(j, 1 | 3))
                        || (j == 2 && matches!(i, 1 | 3))
                );
            }
        }
        assert!(companion.is_companion());
        assert!(!companion.is_participant());
        assert_eq!(
            serde_json::to_value(companion).unwrap(),
            serde_json::json!({"side":"companion","kind":"latch","phase":"releasing","phase_started":42})
        );
        assert!(serde_json::from_str::<CampaignActor>(
            r#"{"side":"companion","kind":"latch","phase":"firing","phase_started":43}"#
        )
        .is_ok());
        let json = serde_json::to_string(&union).unwrap();
        assert_eq!(serde_json::from_str::<CampaignActor>(&json).unwrap(), union);
        assert!(!json.contains("seated"));
        let seated = CampaignActor::Union {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: true,
        };
        let seated_json = serde_json::to_string(&seated).unwrap();
        assert!(seated_json.contains("\"seated\":true"));
        assert_eq!(
            serde_json::from_str::<CampaignActor>(&seated_json).unwrap(),
            seated
        );
        for raw in [
            r#"{"side":"union","kind":"unknown"}"#,
            r#"{"side":"participant","role":"human"}"#,
            r#"{"side":"union","kind":"clerk","phase":"idle","phase_started":-1,"phase_ends":0}"#,
            r#"{"side":"companion","kind":"latch","phase":"dead","phase_started":0}"#,
            r#"{"side":"companion","kind":"latch","phase":"following","phase_started":0,"phase_ends":1}"#,
        ] {
            assert!(serde_json::from_str::<CampaignActor>(raw).is_err());
        }
    }
}
