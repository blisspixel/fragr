//! Sabotage on the wire: the static site layout in `MapInfo`, the round state
//! in each snapshot, the facts as events and the round result. The server owns
//! every transition (`crate::sim::sabotage`); readers validate and present
//! these shapes and never decide an outcome.
use super::{Team, TeamScores};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// How long a match runs.
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, clap::ValueEnum,
)]
#[serde(rename_all = "snake_case")]
pub enum SabotageFormat {
    /// Public rotation: halves of 4, first to 5, one extra pair, then a draw.
    #[default]
    Short,
    /// Halves of 8, first to 9, extra periods of two halves of 3 until decided.
    Match,
}

impl SabotageFormat {
    pub const fn id(self) -> &'static str {
        match self {
            Self::Short => "short",
            Self::Match => "match",
        }
    }

    /// Rounds in each regulation half.
    pub const fn half_rounds(self) -> u32 {
        match self {
            Self::Short => 4,
            Self::Match => 8,
        }
    }

    /// Rounds in each half of an extra period.
    pub const fn extra_half_rounds(self) -> u32 {
        match self {
            Self::Short => 1,
            Self::Match => 3,
        }
    }

    /// Extra periods before a level match is a draw. None plays until decided.
    pub const fn extra_periods(self) -> Option<u32> {
        match self {
            Self::Short => Some(1),
            Self::Match => None,
        }
    }
}

/// One of the two plant sites.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SiteId {
    A,
    B,
}

impl SiteId {
    pub const ALL: [Self; 2] = [Self::A, Self::B];

    pub const fn index(self) -> usize {
        match self {
            Self::A => 0,
            Self::B => 1,
        }
    }

    pub const fn id(self) -> &'static str {
        match self {
            Self::A => "a",
            Self::B => "b",
        }
    }

    /// The English callout for logs and Host lines. Clients key their own.
    pub const fn callout(self) -> &'static str {
        match self {
            Self::A => "A Frame",
            Self::B => "B Server",
        }
    }
}

/// A plant area: a disc on the floor around a correction frame or registry server.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SabotageSite {
    pub id: SiteId,
    /// Centre of the plant area, feet height.
    pub center: [f32; 3],
    /// Horizontal radius of the plant area, metres.
    pub radius: f32,
}

/// A named floor region, so agents, bots, the Host and players say the same words.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Callout {
    /// Stable snake_case id; clients key their own words.
    pub id: String,
    /// Lowest x and z of the region.
    pub min: [f32; 2],
    /// Highest x and z of the region.
    pub max: [f32; 2],
}

impl Callout {
    pub fn contains(&self, x: f32, z: f32) -> bool {
        x >= self.min[0] && x <= self.max[0] && z >= self.min[1] && z <= self.max[1]
    }
}

/// The static Sabotage layout, sent in `MapInfo` and never per tick.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SabotageMap {
    /// The side that carries and plants: always the free coalition. Repeated
    /// so no reader has to infer it.
    pub attackers: Team,
    pub sites: [SabotageSite; 2],
    /// Most specific first: a reader takes the first region that contains a point.
    pub callouts: Vec<Callout>,
}

/// Longest callout id and most regions a layout may carry.
pub const MAX_CALLOUT_ID: usize = 32;
pub const MAX_CALLOUTS: usize = 32;

impl SabotageMap {
    /// The first callout containing a point, most specific first.
    pub fn callout_at(&self, x: f32, z: f32) -> Option<&str> {
        self.callouts
            .iter()
            .find(|c| c.contains(x, z))
            .map(|c| c.id.as_str())
    }

    /// Structural bounds a reader can rely on: two distinct sites in order,
    /// finite coordinates, a usable plant radius and bounded callouts.
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.attackers != Team::Coalition {
            return Err("the free coalition attacks");
        }
        for (index, site) in self.sites.iter().enumerate() {
            if site.id.index() != index {
                return Err("sites must be a then b");
            }
            if !site
                .center
                .iter()
                .all(|v| v.is_finite() && v.abs() <= 1000.0)
            {
                return Err("site centre out of range");
            }
            if !(1.0..=8.0).contains(&site.radius) {
                return Err("plant radius out of range");
            }
        }
        if self.callouts.len() > MAX_CALLOUTS {
            return Err("too many callouts");
        }
        for callout in &self.callouts {
            let id_ok = !callout.id.is_empty()
                && callout.id.len() <= MAX_CALLOUT_ID
                && callout
                    .id
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_');
            if !id_ok {
                return Err("callout id must be short snake_case");
            }
            let finite = callout
                .min
                .iter()
                .chain(callout.max.iter())
                .all(|v| v.is_finite() && v.abs() <= 1000.0);
            if !finite || callout.min[0] >= callout.max[0] || callout.min[1] >= callout.max[1] {
                return Err("callout bounds must be ordered and finite");
            }
        }
        Ok(())
    }
}

/// Where a round stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SabotagePhase {
    /// Held in the spawn zones; pickups work, weapons do not.
    Muster,
    /// One life, the charge unplanted, the round clock running.
    Live,
    /// The charge is planted; its clock replaces the round clock.
    Planted,
    /// The round is decided.
    Over,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChargeStatus {
    Carried,
    Dropped,
    Planted,
    Defused,
    Detonated,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChargeState {
    pub status: ChargeStatus,
    /// Feet position: the carrier's while carried, otherwise where it lies.
    pub position: [f32; 3],
    /// Present only while carried.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub carrier: Option<Uuid>,
    /// The site it was planted at, once planted.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub site: Option<SiteId>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProgressKind {
    Plant,
    Defuse,
}

/// A held Use in progress. Interruption clears it and loses the progress.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SabotageProgress {
    pub kind: ProgressKind,
    pub player_id: Uuid,
    pub site: SiteId,
    /// Ticks held so far, at most `needed`.
    pub ticks: u32,
    /// Ticks the action takes.
    pub needed: u32,
}

/// The round as every reader sees it, in each snapshot of a Sabotage server.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SabotageState {
    pub format: SabotageFormat,
    pub phase: SabotagePhase,
    /// Round of this match, counting from 1.
    pub round: u32,
    /// Extra period, 0 in regulation.
    pub period: u32,
    /// Half of the current period: 1 or 2.
    pub half: u8,
    /// Rounds in each half of the current period.
    pub half_rounds: u32,
    /// Round wins that take the match from here.
    pub rounds_to_win: u32,
    /// Round wins by current uniform. Swaps with the fighters at half.
    pub score: TeamScores,
    /// Fighters still standing on each side.
    pub alive: TeamScores,
    /// Ticks left on the clock that matters now: muster, live or charge.
    pub clock_ticks: u32,
    /// Absent only when no attacker is in the match.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub charge: Option<ChargeState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub progress: Option<SabotageProgress>,
    /// This round is the last of its half: sides swap after it.
    #[serde(default, skip_serializing_if = "super::is_false")]
    pub swap_after: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SabotageEventKind {
    /// Muster is over; weapons are live.
    Live,
    ChargeTaken,
    ChargeDropped,
    PlantStarted,
    PlantInterrupted,
    Planted,
    DefuseStarted,
    DefuseInterrupted,
    Defused,
    Detonated,
    /// Every fighter changed uniform; the score swapped with them.
    SidesSwapped,
}

/// Why a round was decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SabotageReason {
    Elimination,
    Detonation,
    Defused,
    Time,
}

impl SabotageReason {
    pub const fn id(self) -> &'static str {
        match self {
            Self::Elimination => "elimination",
            Self::Detonation => "detonation",
            Self::Defused => "defused",
            Self::Time => "time",
        }
    }
}

/// The round result on `round_end`, with the match result when it is decided.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SabotageResult {
    pub reason: SabotageReason,
    /// The round just played, counting from 1.
    pub round: u32,
    /// Round wins after this round, by the uniform each side wore in it.
    pub score: TeamScores,
    /// Every fighter changes uniform before the next round.
    #[serde(default, skip_serializing_if = "super::is_false")]
    pub sides_swap: bool,
    /// This round decided the match, or ended it level.
    #[serde(default, skip_serializing_if = "super::is_false")]
    pub match_over: bool,
    /// The uniform that won the match. Absent for a draw or an unfinished match.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub match_winner: Option<Team>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn layout() -> SabotageMap {
        SabotageMap {
            attackers: Team::Coalition,
            sites: [
                SabotageSite {
                    id: SiteId::A,
                    center: [-38.0, 0.0, -27.0],
                    radius: 3.0,
                },
                SabotageSite {
                    id: SiteId::B,
                    center: [-38.0, 0.0, 27.0],
                    radius: 3.0,
                },
            ],
            callouts: vec![Callout {
                id: "mid_doors".into(),
                min: [-30.0, -4.0],
                max: [30.0, 4.0],
            }],
        }
    }

    #[test]
    fn formats_name_their_halves_and_extra_time() {
        assert_eq!(SabotageFormat::default(), SabotageFormat::Short);
        assert_eq!(
            (
                SabotageFormat::Short.half_rounds(),
                SabotageFormat::Short.extra_half_rounds(),
                SabotageFormat::Short.extra_periods()
            ),
            (4, 1, Some(1))
        );
        assert_eq!(
            (
                SabotageFormat::Match.half_rounds(),
                SabotageFormat::Match.extra_half_rounds(),
                SabotageFormat::Match.extra_periods()
            ),
            (8, 3, None)
        );
        for format in [SabotageFormat::Short, SabotageFormat::Match] {
            let json = serde_json::to_string(&format).unwrap();
            assert_eq!(json, format!("\"{}\"", format.id()));
        }
    }

    #[test]
    fn layout_validation_refuses_malformed_sites_and_callouts() {
        let good = layout();
        assert!(good.validate().is_ok());
        assert_eq!(good.callout_at(0.0, 0.0), Some("mid_doors"));
        assert_eq!(good.callout_at(0.0, 50.0), None);
        assert_eq!(SiteId::B.callout(), "B Server");
        let mut swapped = good.clone();
        swapped.sites.swap(0, 1);
        assert!(swapped.validate().is_err());
        let mut union = good.clone();
        union.attackers = Team::Union;
        assert!(union.validate().is_err());
        let mut wide = good.clone();
        wide.sites[0].radius = 20.0;
        assert!(wide.validate().is_err());
        let mut lost = good.clone();
        lost.sites[1].center[0] = f32::NAN;
        assert!(lost.validate().is_err());
        let mut shouting = good.clone();
        shouting.callouts[0].id = "Mid Doors".into();
        assert!(shouting.validate().is_err());
        let mut inverted = good.clone();
        inverted.callouts[0].min[0] = 40.0;
        assert!(inverted.validate().is_err());
        let mut crowded = good;
        crowded.callouts = vec![crowded.callouts[0].clone(); MAX_CALLOUTS + 1];
        assert!(crowded.validate().is_err());
    }

    #[test]
    fn state_and_result_omit_defaults_on_the_wire() {
        let state = SabotageState {
            format: SabotageFormat::Short,
            phase: SabotagePhase::Live,
            round: 1,
            period: 0,
            half: 1,
            half_rounds: 4,
            rounds_to_win: 5,
            score: TeamScores::default(),
            alive: TeamScores {
                union: 4,
                coalition: 4,
            },
            clock_ticks: 2100,
            charge: Some(ChargeState {
                status: ChargeStatus::Carried,
                position: [1.0, 0.0, 2.0],
                carrier: Some(Uuid::from_u128(7)),
                site: None,
            }),
            progress: None,
            swap_after: false,
        };
        let json = serde_json::to_value(&state).unwrap();
        assert!(json.get("swap_after").is_none());
        assert!(json.get("progress").is_none());
        assert_eq!(json["phase"], "live");
        assert_eq!(json["charge"]["status"], "carried");
        assert!(json["charge"].get("site").is_none());
        let back: SabotageState = serde_json::from_value(json).unwrap();
        assert_eq!(back, state);
        let result = SabotageResult {
            reason: SabotageReason::Defused,
            round: 4,
            score: TeamScores {
                union: 3,
                coalition: 1,
            },
            sides_swap: true,
            match_over: false,
            match_winner: None,
        };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["reason"], SabotageReason::Defused.id());
        assert_eq!(json["sides_swap"], true);
        assert!(json.get("match_over").is_none());
        assert!(json.get("match_winner").is_none());
        let kinds = serde_json::to_value([
            SabotageEventKind::PlantStarted,
            SabotageEventKind::SidesSwapped,
        ])
        .unwrap();
        assert_eq!(kinds, serde_json::json!(["plant_started", "sides_swapped"]));
        assert!(serde_json::from_str::<SiteId>("\"c\"").is_err());
    }
}
