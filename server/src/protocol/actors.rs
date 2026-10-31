//! Fictional identity is independent of the connection's control role.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
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
    /// Heavy flying equipment with three finite, locked ballistic canisters.
    Assessor,
    /// Broad restoration machine that marks a bounded ground strip, prepares
    /// in the open, then works everything inside it. A hard hit during the
    /// preparation puts the strip out.
    Paver,
    /// Elevated off-white spotter. Its lens opens wide to observe one
    /// participant, then projects a tracking disc that nearby machines
    /// converge on. Lens closed, its shutter turns most traced damage.
    Surveyor,
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
    /// Level 18 before the turn: a Union machine or its supervisor at work
    /// under the recovery's ceasefire. Not an enemy to anyone until the turn.
    Working,
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

/// Who commands a hostile campaign body. Body kind, combat role, hostility and
/// imposed control are separate state: a chassis or skin never decides it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ControlDomain {
    /// The Union's own people and the bots still answering to it.
    #[default]
    Union,
    /// A former Union bot the Inheritance took at the wipe. It keeps its
    /// chassis and learned attacks; it no longer answers to anyone human.
    Absorbed,
    /// An Inheritance restoration machine.
    Restoration,
}

impl ControlDomain {
    /// Whether a body of this kind can be under this control. Human Union
    /// personnel are never absorbed; only restoration machines are restoration.
    pub fn admits(self, kind: EnemyKind) -> bool {
        match self {
            Self::Union => !kind.is_restoration_machine(),
            Self::Absorbed => kind.is_union_machine(),
            Self::Restoration => kind.is_restoration_machine(),
        }
    }
}

impl EnemyKind {
    /// The Inheritance's own restoration machines. They never answer to the
    /// Union and are never absorbed.
    pub fn is_restoration_machine(self) -> bool {
        matches!(self, Self::Paver | Self::Surveyor)
    }

    /// Union bots and equipment, as opposed to Union people and restoration
    /// machines. Only these can be absorbed.
    pub fn is_union_machine(self) -> bool {
        matches!(
            self,
            Self::Sweeper
                | Self::HeavySweeper
                | Self::Crawler
                | Self::Turret
                | Self::Jammer
                | Self::Notary
                | Self::RangedSweeper
                | Self::Assessor
        )
    }
}

/// Campaign identity. A hostile body's wire `side` follows its control:
/// `union` for the Union, `inheritance` (with `control`) for absorbed bots and
/// restoration machines.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(into = "ActorWire", try_from = "ActorWire")]
pub enum CampaignActor {
    Participant {},
    Companion {
        kind: CompanionKind,
        phase: CompanionPhase,
        phase_started: u64,
    },
    Hostile {
        kind: EnemyKind,
        phase: EnemyPhase,
        phase_started: u64,
        phase_ends: u64,
        /// Authored opening pose only while a dormant Clerk sits at a station.
        seated: bool,
        control: ControlDomain,
    },
    Entrant {
        placard: u8,
        armed: bool,
    },
}

/// The Inheritance's two control domains on the wire.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum InheritanceControl {
    Absorbed,
    Restoration,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "side", rename_all = "snake_case", deny_unknown_fields)]
enum ActorWire {
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
        #[serde(default, skip_serializing_if = "not_seated")]
        seated: bool,
    },
    Inheritance {
        control: InheritanceControl,
        kind: EnemyKind,
        phase: EnemyPhase,
        phase_started: u64,
        phase_ends: u64,
    },
    Entrant {
        placard: u8,
        armed: bool,
    },
}

fn not_seated(seated: &bool) -> bool {
    !seated
}

impl From<CampaignActor> for ActorWire {
    fn from(actor: CampaignActor) -> Self {
        match actor {
            CampaignActor::Participant {} => Self::Participant {},
            CampaignActor::Companion {
                kind,
                phase,
                phase_started,
            } => Self::Companion {
                kind,
                phase,
                phase_started,
            },
            CampaignActor::Hostile {
                kind,
                phase,
                phase_started,
                phase_ends,
                seated,
                control,
            } => match control {
                ControlDomain::Union => Self::Union {
                    kind,
                    phase,
                    phase_started,
                    phase_ends,
                    seated,
                },
                ControlDomain::Absorbed | ControlDomain::Restoration => Self::Inheritance {
                    control: if control == ControlDomain::Absorbed {
                        InheritanceControl::Absorbed
                    } else {
                        InheritanceControl::Restoration
                    },
                    kind,
                    phase,
                    phase_started,
                    phase_ends,
                },
            },
            CampaignActor::Entrant { placard, armed } => Self::Entrant { placard, armed },
        }
    }
}

impl TryFrom<ActorWire> for CampaignActor {
    type Error = &'static str;

    fn try_from(wire: ActorWire) -> Result<Self, Self::Error> {
        let (kind, phase, phase_started, phase_ends, seated, control) = match wire {
            ActorWire::Participant {} => return Ok(Self::Participant {}),
            ActorWire::Companion {
                kind,
                phase,
                phase_started,
            } => {
                return Ok(Self::Companion {
                    kind,
                    phase,
                    phase_started,
                })
            }
            ActorWire::Entrant { placard, armed } => return Ok(Self::Entrant { placard, armed }),
            ActorWire::Union {
                kind,
                phase,
                phase_started,
                phase_ends,
                seated,
            } => (
                kind,
                phase,
                phase_started,
                phase_ends,
                seated,
                ControlDomain::Union,
            ),
            ActorWire::Inheritance {
                control,
                kind,
                phase,
                phase_started,
                phase_ends,
            } => (
                kind,
                phase,
                phase_started,
                phase_ends,
                false,
                match control {
                    InheritanceControl::Absorbed => ControlDomain::Absorbed,
                    InheritanceControl::Restoration => ControlDomain::Restoration,
                },
            ),
        };
        if !control.admits(kind) {
            return Err("campaign actor kind does not match its control");
        }
        Ok(Self::Hostile {
            kind,
            phase,
            phase_started,
            phase_ends,
            seated,
            control,
        })
    }
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

/// One living Surveyor's projected mark: a disc of light on the ground that
/// tracks its observed participant at a bounded speed while sight holds.
/// Nearby walking machines converge on the disc's current centre.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SurveyorMarkState {
    /// The projecting Surveyor.
    pub id: uuid::Uuid,
    /// Grounded disc centre in world feet.
    pub center: [f32; 3],
    pub radius: f32,
    /// Tick the disc was cast and the tick it lapses unless broken first.
    pub since: u64,
    pub until: u64,
    /// The Surveyor currently sees its participant and the disc follows.
    pub tracking: bool,
}

/// Disc radius in metres. Stepping clear of it is the first counter.
pub const SURVEYOR_MARK_RADIUS: f32 = 3.0;

impl SurveyorMarkState {
    pub fn validate(&self, half: f32) -> Result<(), &'static str> {
        if self.id.is_nil()
            || !self.center.iter().all(|v| v.is_finite())
            || self.center[0].abs() > half
            || self.center[2].abs() > half
            || !(0.0..=512.0).contains(&self.center[1])
            || (self.radius - SURVEYOR_MARK_RADIUS).abs() > f32::EPSILON
            || self.until <= self.since
        {
            return Err("invalid Surveyor mark");
        }
        Ok(())
    }
}

impl CampaignActor {
    pub fn is_enemy(self) -> bool {
        matches!(self, Self::Hostile { .. })
    }

    /// A Union body at work under a ceasefire (Level 18 before the turn):
    /// nobody's enemy, nobody's target, until its phase changes.
    pub fn at_work(self) -> bool {
        matches!(
            self,
            Self::Hostile {
                phase: EnemyPhase::Working,
                ..
            }
        )
    }

    pub fn is_participant(self) -> bool {
        matches!(self, Self::Participant {})
    }

    pub fn is_companion(self) -> bool {
        matches!(self, Self::Companion { .. })
    }

    pub fn is_entrant(self) -> bool {
        matches!(self, Self::Entrant { .. })
    }
}

/// Identity, not callsign or control role, decides hostility. Missing identity
/// only enables the legacy free-for-all when both actors are legacy actors.
pub fn hostile(a: Option<CampaignActor>, b: Option<CampaignActor>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(a), Some(b)) => !a.at_work() && !b.at_work() && a.is_enemy() != b.is_enemy(),
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
    fn a_body_at_work_is_nobodys_enemy_until_its_phase_changes() {
        let working = CampaignActor::Hostile {
            kind: EnemyKind::Sweeper,
            phase: EnemyPhase::Working,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
            control: ControlDomain::Union,
        };
        let participant = Some(CampaignActor::Participant {});
        assert!(working.at_work());
        assert!(!hostile(Some(working), participant));
        assert!(!hostile(participant, Some(working)));
        let wire = serde_json::to_value(working).unwrap();
        assert_eq!(wire["phase"], "working");
        assert_eq!(
            serde_json::from_value::<CampaignActor>(wire).unwrap(),
            working
        );
        let turned = CampaignActor::Hostile {
            kind: EnemyKind::Sweeper,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
            control: ControlDomain::Union,
        };
        assert!(!turned.at_work() && hostile(Some(turned), participant));
    }

    #[test]
    fn allegiance_is_symmetric_and_missing_campaign_identity_fails_closed() {
        let union = CampaignActor::Hostile {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: false,
            control: Default::default(),
        };
        let companion = CampaignActor::Companion {
            kind: CompanionKind::Latch,
            phase: CompanionPhase::Releasing,
            phase_started: 42,
        };
        let entrant = CampaignActor::Entrant {
            placard: 4,
            armed: false,
        };
        let identities = [
            None,
            Some(CampaignActor::Participant {}),
            Some(union),
            Some(companion),
            Some(entrant),
        ];
        for (i, a) in identities.into_iter().enumerate() {
            for (j, b) in identities.into_iter().enumerate() {
                assert_eq!(
                    hostile(a, b),
                    i == 0 && j == 0
                        || (i == 2 && matches!(j, 1 | 3 | 4))
                        || (j == 2 && matches!(i, 1 | 3 | 4))
                );
            }
        }
        assert!(entrant.is_entrant());
        assert!(!entrant.is_enemy());
        assert!(!entrant.is_participant());
        assert_eq!(
            serde_json::to_value(entrant).unwrap(),
            serde_json::json!({"side":"entrant","placard":4,"armed":false})
        );
        assert!(serde_json::from_str::<CampaignActor>(
            r#"{"side":"entrant","placard":12,"armed":true}"#
        )
        .is_ok());
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
        let seated = CampaignActor::Hostile {
            kind: EnemyKind::Clerk,
            phase: EnemyPhase::Idle,
            phase_started: 0,
            phase_ends: 0,
            seated: true,
            control: Default::default(),
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

    #[test]
    fn inheritance_bodies_carry_their_control_domain_on_the_wire() {
        let body = |kind, control| CampaignActor::Hostile {
            kind,
            phase: EnemyPhase::Windup,
            phase_started: 4,
            phase_ends: 20,
            seated: false,
            control,
        };
        let paver = body(EnemyKind::Paver, ControlDomain::Restoration);
        assert_eq!(
            serde_json::to_value(paver).unwrap(),
            serde_json::json!({"side":"inheritance","control":"restoration","kind":"paver",
                "phase":"windup","phase_started":4,"phase_ends":20})
        );
        let absorbed = body(EnemyKind::HeavySweeper, ControlDomain::Absorbed);
        assert_eq!(
            serde_json::to_value(absorbed).unwrap(),
            serde_json::json!({"side":"inheritance","control":"absorbed","kind":"heavy_sweeper",
                "phase":"windup","phase_started":4,"phase_ends":20})
        );
        let sweeper = body(EnemyKind::Sweeper, ControlDomain::Union);
        assert_eq!(
            serde_json::to_value(sweeper).unwrap()["side"],
            serde_json::json!("union")
        );
        let surveyor = body(EnemyKind::Surveyor, ControlDomain::Restoration);
        assert_eq!(
            serde_json::to_value(surveyor).unwrap()["control"],
            serde_json::json!("restoration")
        );
        for actor in [paver, absorbed, sweeper, surveyor] {
            assert!(actor.is_enemy());
            assert!(hostile(Some(actor), Some(CampaignActor::Participant {})));
            let json = serde_json::to_string(&actor).unwrap();
            assert_eq!(serde_json::from_str::<CampaignActor>(&json).unwrap(), actor);
        }
        // Control and kind must agree: people are never absorbed, a Paver is
        // never the Union's, and only restoration machines are restoration.
        for raw in [
            r#"{"side":"union","kind":"paver","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"union","kind":"surveyor","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","control":"absorbed","kind":"surveyor","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","control":"absorbed","kind":"clerk","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","control":"absorbed","kind":"paver","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","control":"restoration","kind":"sweeper","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","control":"union","kind":"sweeper","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","kind":"sweeper","phase":"idle","phase_started":0,"phase_ends":0}"#,
            r#"{"side":"inheritance","control":"absorbed","kind":"sweeper","phase":"idle","phase_started":0,"phase_ends":0,"seated":true}"#,
        ] {
            assert!(serde_json::from_str::<CampaignActor>(raw).is_err(), "{raw}");
        }
        for kind in [
            EnemyKind::Clerk,
            EnemyKind::Auditor,
            EnemyKind::Enforcer,
            EnemyKind::Redactor,
        ] {
            assert!(ControlDomain::Union.admits(kind));
            assert!(!ControlDomain::Absorbed.admits(kind));
            assert!(!ControlDomain::Restoration.admits(kind));
        }
    }
}
