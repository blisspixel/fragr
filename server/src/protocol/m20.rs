//! Local Exception: the waterworks crossing, the pier hold and the reprieve.
//!
//! The level has five ordered objectives. The last two are the hold: the
//! pier clock runs from the end of the breath, the harbour display lights at
//! the turn with exactly six minutes left, and the reprieve lands when the
//! clock runs out. The clock is a server fact (`pier_reached_at` plus the
//! map's authored spans); presenters derive the countdown from the tick.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M20_OBJECTIVE_IDS: [&str; 5] = [
    "sluice_crossing",
    "crew_crossing",
    "pier_arrival",
    "pier_hold",
    "last_six",
];

/// The waterworks crew who keep the pumps running for the refuge.
pub const M20_CREW: usize = 3;
/// The harbour display's message is exact: six minutes at 20 Hz.
pub const M20_SIX_MINUTES: u64 = 7_200;
/// The refuge line's barricade. Machines working it wear it down.
pub const M20_REFUGE_INTEGRITY: u16 = 100;
/// The people already waiting at the crossing before anyone the run freed.
pub const M20_REFUGE_BASE: u32 = 400;
/// Upper bound on the run's carried rescue total, for strict readers.
pub const M20_MAX_FREED: u32 = 400;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum M20CrewPhase {
    /// Still running the pumps in the pump hall.
    Working,
    /// Crossing the service road on their own once the crossing is clear.
    Crossing,
    /// Through the wicket and behind the refuge line.
    Arrived,
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M20CrewState {
    pub phase: M20CrewPhase,
    pub feet: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M20MapGeometry {
    pub objectives: Vec<MissionObjective>,
    /// The refuge gate's crossing control, behind the gate.
    pub departure: UseTarget,
    pub boarding: Region3,
    /// The barricade's work zone in front of the refuge fence.
    pub refuge_line: Region3,
    /// Decoration index of the harbour display panel.
    pub harbour_display: usize,
    /// Calm on the pier before the clock runs.
    pub breath_ticks: u64,
    /// Hold ticks before the harbour display lights.
    pub turn_ticks: u64,
    /// Hold ticks before the reprieve. `hold_ticks - turn_ticks` is six minutes.
    pub hold_ticks: u64,
    /// The refuge gate, the level's one door, stands open.
    pub gate_open: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct M20ChallengeState {
    /// Every crew member walked through the wicket.
    pub crew_crossed: bool,
    /// A Surveyor's disc ended under fire before any machine reached it.
    pub mark_broken: bool,
    /// The barricade never fell.
    pub refuge_held: bool,
}

impl M20ChallengeState {
    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.crew_crossed
            && (difficulty == CampaignDifficulty::Assisted
                || self.mark_broken
                    && (difficulty != CampaignDifficulty::Severe || self.refuge_held))
    }
}

/// Who is waiting at the crossing. `persons` is the refuge's own four hundred
/// plus every authored rescue this run actually carried; it changes what the
/// harbour display says, never whether the level can be won.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M20Refuge {
    pub persons: u32,
    /// Edda's clinic team came out of level 4: Edda lit the lamp herself.
    pub edda: bool,
    /// Splice reached the level 5 freight; release alone does not bring them.
    pub splice: bool,
    pub orrin: bool,
    pub sorrel: bool,
}

impl M20Refuge {
    pub fn alone() -> Self {
        Self {
            persons: M20_REFUGE_BASE,
            edda: false,
            splice: false,
            orrin: false,
            sorrel: false,
        }
    }

    fn valid(&self) -> bool {
        (M20_REFUGE_BASE..=M20_REFUGE_BASE + M20_MAX_FREED).contains(&self.persons)
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M20ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M20ChallengeState,
    pub crew: Vec<M20CrewState>,
    /// Tick the party reached the quay. The breath, the hold, the turn and
    /// the reprieve all count from here with the map's authored spans.
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub pier_reached_at: Option<u64>,
    pub refuge_integrity: u16,
    pub display_lit: bool,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub reprieve_at: Option<u64>,
    /// Latch's feet once the reprieve lands and they walk back to the gate.
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub latch: Option<[f32; 3]>,
    pub gate_open: bool,
    pub refuge: M20Refuge,
    pub brief_completed: bool,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M20MapGeometry {
    pub fn departure_objective(&self) -> MissionObjective {
        MissionObjective {
            id: "party_departed".into(),
            action: MissionObjectiveAction::Use {
                target: self.departure.clone(),
            },
        }
    }

    /// Hold tick offsets from the quay arrival: (clock start, turn, reprieve).
    pub fn clock(&self, pier_reached_at: u64) -> (u64, u64, u64) {
        let start = pier_reached_at.saturating_add(self.breath_ticks);
        (
            start,
            start.saturating_add(self.turn_ticks),
            start.saturating_add(self.hold_ticks),
        )
    }

    pub fn validate(
        &self,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let p = presentation.ok_or("M20 requires panel presentation")?;
        if self.objectives.len() != M20_OBJECTIVE_IDS.len() {
            return Err("M20 requires five ordered objectives");
        }
        for (i, obj) in self.objectives.iter().enumerate() {
            if obj.id != M20_OBJECTIVE_IDS[i] {
                return Err("unexpected M20 objective order");
            }
            let MissionObjectiveAction::Arrival { region, feet } = &obj.action else {
                return Err("M20 objectives are arrivals and holds");
            };
            if !region.valid(half_extent) || !point(*feet, half_extent) || !region.contains(*feet) {
                return Err("invalid M20 objective region or feet");
            }
        }
        if !self.boarding.valid(half_extent)
            || !self.refuge_line.valid(half_extent)
            || !point(self.departure.approach, half_extent)
            || !self.boarding.contains(self.departure.approach)
            || self.departure.point(p, solids).is_none()
        {
            return Err("invalid M20 refuge gate");
        }
        let display = p
            .decorations
            .get(self.harbour_display)
            .ok_or("M20 harbour display missing")?;
        if display.solid >= solids.len() {
            return Err("M20 harbour display misses its pylon");
        }
        if !(200..=1_200).contains(&self.breath_ticks)
            || self.turn_ticks < 600
            || self.turn_ticks >= self.hold_ticks
            || self.hold_ticks - self.turn_ticks != M20_SIX_MINUTES
            || self.hold_ticks > 24_000
        {
            return Err("M20 clock must end with exactly six minutes after the turn");
        }
        Ok(())
    }
}

impl M20ObjectiveState {
    pub fn validate(
        &self,
        geometry_clock: Option<(u64, u64, u64)>,
        phase: MissionPhase,
        tick: u64,
    ) -> Result<(), &'static str> {
        let n = super::mission::validate_ordered_progress(
            &self.completed,
            self.current.as_ref(),
            &M20_OBJECTIVE_IDS,
            &[],
            phase,
            tick,
        )?;
        if self.crew.len() != M20_CREW
            || self.refuge_integrity > M20_REFUGE_INTEGRITY
            || !self.refuge.valid()
        {
            return Err("invalid M20 crew, barricade or refuge");
        }
        for member in &self.crew {
            if !member.feet.iter().all(|v| v.is_finite())
                || (n < 2) != (member.phase == M20CrewPhase::Working)
            {
                return Err("M20 crew disagrees with the crossing");
            }
        }
        let crossed = self
            .crew
            .iter()
            .all(|member| member.phase == M20CrewPhase::Arrived);
        if self.challenges.crew_crossed != crossed
            || self.challenges.refuge_held != (self.refuge_integrity > 0)
            || (n >= 3) != self.pier_reached_at.is_some()
            || (n >= 4) != self.display_lit
            || (n >= 5) != self.reprieve_at.is_some()
            || self.latch.is_some() != self.reprieve_at.is_some()
            || self.gate_open && self.reprieve_at.is_none()
            || self
                .latch
                .is_some_and(|feet| !feet.iter().all(|v| v.is_finite()))
        {
            return Err("M20 facts disagree with ordered progress");
        }
        if let Some(reached) = self.pier_reached_at {
            if reached > tick {
                return Err("M20 quay arrival is in the future");
            }
            if let Some((_, turn, reprieve)) = geometry_clock {
                if self.display_lit && tick < turn
                    || self
                        .reprieve_at
                        .is_some_and(|at| at != reprieve || at > tick)
                {
                    return Err("M20 clock disagrees with the authored hold");
                }
            }
        }
        if phase == MissionPhase::Briefing
            && (!self.completed.is_empty()
                || self.refuge_integrity != M20_REFUGE_INTEGRITY
                || self.challenges.mark_broken)
        {
            return Err("briefing M20 cannot carry progress");
        }
        if phase == MissionPhase::Departed && (!self.gate_open || tick == 0) {
            return Err("departed M20 requires the open refuge gate");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts() -> M20ObjectiveState {
        M20ObjectiveState {
            completed: Vec::new(),
            current: Some(MissionObjective {
                id: "sluice_crossing".into(),
                action: MissionObjectiveAction::Arrival {
                    region: Region3 {
                        min: [-40.0, 0.0, -4.0],
                        max: [-30.0, 3.0, 4.0],
                    },
                    feet: [-35.0, 1.0, 0.0],
                },
            }),
            challenges: M20ChallengeState {
                refuge_held: true,
                ..Default::default()
            },
            crew: vec![
                M20CrewState {
                    phase: M20CrewPhase::Working,
                    feet: [0.0; 3],
                };
                M20_CREW
            ],
            pier_reached_at: None,
            refuge_integrity: M20_REFUGE_INTEGRITY,
            display_lit: false,
            reprieve_at: None,
            latch: None,
            gate_open: false,
            refuge: M20Refuge::alone(),
            brief_completed: false,
        }
    }

    #[test]
    fn brief_tiers_add_mark_then_refuge() {
        let mut c = M20ChallengeState::default();
        for d in [
            CampaignDifficulty::Assisted,
            CampaignDifficulty::Standard,
            CampaignDifficulty::Severe,
        ] {
            assert!(!c.brief_completed(d));
        }
        c.crew_crossed = true;
        assert!(c.brief_completed(CampaignDifficulty::Assisted));
        assert!(!c.brief_completed(CampaignDifficulty::Standard));
        c.mark_broken = true;
        assert!(c.brief_completed(CampaignDifficulty::Standard));
        assert!(!c.brief_completed(CampaignDifficulty::Severe));
        c.refuge_held = true;
        assert!(c.brief_completed(CampaignDifficulty::Severe));
    }

    #[test]
    fn strict_facts_refuse_forged_progress() {
        let base = facts();
        base.validate(None, MissionPhase::InProgress, 10).unwrap();
        base.validate(None, MissionPhase::Briefing, 10).unwrap();

        let mut crossing = base.clone();
        crossing.crew[0].phase = M20CrewPhase::Crossing;
        assert!(crossing
            .validate(None, MissionPhase::InProgress, 10)
            .is_err());

        let mut fallen = base.clone();
        fallen.refuge_integrity = 0;
        assert!(fallen.validate(None, MissionPhase::InProgress, 10).is_err());
        fallen.challenges.refuge_held = false;
        fallen.validate(None, MissionPhase::InProgress, 10).unwrap();
        assert!(fallen.validate(None, MissionPhase::Briefing, 10).is_err());

        let mut lit = base.clone();
        lit.display_lit = true;
        assert!(lit.validate(None, MissionPhase::InProgress, 10).is_err());

        let mut gate = base.clone();
        gate.gate_open = true;
        assert!(gate.validate(None, MissionPhase::InProgress, 10).is_err());

        let mut overfull = base.clone();
        overfull.refuge.persons = M20_REFUGE_BASE + M20_MAX_FREED + 1;
        assert!(overfull
            .validate(None, MissionPhase::InProgress, 10)
            .is_err());

        let mut short = base;
        short.crew.pop();
        assert!(short.validate(None, MissionPhase::InProgress, 10).is_err());
    }
}
