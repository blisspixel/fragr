//! Planned Works: the evacuation concourse, changed Low Water and the tram
//! trench. Ordered facts, the coalition jetpack and the waterworks departure.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M19_OBJECTIVE_IDS: [&str; 8] = [
    "concourse_stores",
    "broken_stair",
    "concourse_crossing",
    "tram_street",
    "market_strips",
    "water_tanks",
    "roof_loop",
    "tram_trench",
];
/// Objectives completed by a deliberate use rather than arrival.
pub const M19_USE_OBJECTIVES: [usize; 1] = [0];
/// Bounds on presentation-only route and paint data.
pub const M19_MAX_LATCH_ROUTE: usize = 12;
pub const M19_MAX_WORK_MARKS: usize = 48;
pub const M19_MAX_JET_HOPS: usize = 4;

/// An authored jetpack shortcut: a supported launch and the landing it
/// reaches with one full pack. Controllers may use it; walking still works.
#[derive(Debug, Clone, Copy, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M19JetHop {
    pub launch: [f32; 3],
    pub landing: [f32; 3],
}

/// Painted demolition marks the machines already laid on the district. They
/// are presentation only: no damage, collision or outcome is attached.
#[derive(Debug, Clone, Copy, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M19WorkMark {
    pub min: [f32; 2],
    pub max: [f32; 2],
    pub y: f32,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M19MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub departure: UseTarget,
    pub boarding: Region3,
    /// Coalition stores counter that lends out the jetpack.
    pub stores: UseTarget,
    /// Feet never rise above this under jetpack thrust.
    pub jetpack_ceiling: f32,
    /// Latch's seat by the tank, then the run toward the waterworks.
    pub latch_route: Vec<[f32; 3]>,
    pub work_marks: Vec<M19WorkMark>,
    pub jet_hops: Vec<M19JetHop>,
    /// Runtime stage: the waterworks gate is open.
    pub gate_open: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct M19ChallengeState {
    /// The concourse crossing group was cleared.
    pub crossing_cleared: bool,
    /// A Paver's preparation was put out by damage this attempt.
    pub paver_interrupted: bool,
    /// A work pulse actually damaged a participant this attempt.
    pub strip_struck: bool,
}

impl M19ChallengeState {
    /// Assisted: clear the crossing. Standard adds an interrupted Paver.
    /// Severe adds no work-strip damage taken.
    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.crossing_cleared
            && (difficulty == CampaignDifficulty::Assisted
                || self.paver_interrupted
                    && (difficulty != CampaignDifficulty::Severe || !self.strip_struck))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M19ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M19ChallengeState,
    pub jetpack_taken: bool,
    pub latch_departed: bool,
    pub gate_open: bool,
    pub brief_completed: bool,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}

impl M19MapGeometry {
    pub fn departure_objective(&self) -> MissionObjective {
        MissionObjective {
            id: "party_departed".into(),
            action: MissionObjectiveAction::Use {
                target: self.departure.clone(),
            },
        }
    }

    pub fn validate(
        &self,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let p = presentation.ok_or("M19 requires panel presentation")?;
        if self.objectives.len() != M19_OBJECTIVE_IDS.len() {
            return Err("M19 requires eight ordered objectives");
        }
        for (index, objective) in self.objectives.iter().enumerate() {
            if objective.id != M19_OBJECTIVE_IDS[index] {
                return Err("unexpected M19 objective order");
            }
            match (&objective.action, M19_USE_OBJECTIVES.contains(&index)) {
                (MissionObjectiveAction::Arrival { region, feet }, false) => {
                    if !region.valid(half_extent)
                        || !point(*feet, half_extent)
                        || !region.contains(*feet)
                    {
                        return Err("invalid M19 arrival region or feet");
                    }
                }
                (MissionObjectiveAction::Use { target }, true) => {
                    if target != &self.stores {
                        return Err("M19 stores objective must use the stores counter");
                    }
                }
                _ => return Err("unexpected M19 objective action"),
            }
        }
        for target in [&self.stores, &self.departure] {
            if !point(target.approach, half_extent)
                || target.decoration >= super::MAX_MAP_DECORATIONS
                || target.point(p, solids).is_none()
            {
                return Err("M19 use target misses its registered panel");
            }
        }
        if !self.boarding.valid(half_extent) || !self.boarding.contains(self.departure.approach) {
            return Err("invalid M19 boarding region");
        }
        if !self.jetpack_ceiling.is_finite() || !(4.0..=32.0).contains(&self.jetpack_ceiling) {
            return Err("invalid M19 jetpack ceiling");
        }
        if self.latch_route.len() < 2
            || self.latch_route.len() > M19_MAX_LATCH_ROUTE
            || self.latch_route.iter().any(|p| !point(*p, half_extent))
        {
            return Err("invalid M19 Latch route");
        }
        if self.work_marks.len() > M19_MAX_WORK_MARKS
            || self.work_marks.iter().any(|mark| {
                !mark
                    .min
                    .iter()
                    .chain(&mark.max)
                    .chain(std::iter::once(&mark.y))
                    .all(|v| v.is_finite())
                    || mark.min[0] >= mark.max[0]
                    || mark.min[1] >= mark.max[1]
                    || mark
                        .min
                        .iter()
                        .chain(&mark.max)
                        .any(|v| v.abs() > half_extent)
                    || !(0.0..=64.0).contains(&mark.y)
            })
        {
            return Err("invalid M19 work marks");
        }
        if self.jet_hops.is_empty()
            || self.jet_hops.len() > M19_MAX_JET_HOPS
            || self.jet_hops.iter().any(|hop| {
                !point(hop.launch, half_extent)
                    || !point(hop.landing, half_extent)
                    || hop.landing[1] + 1.0 > self.jetpack_ceiling
            })
        {
            return Err("invalid M19 jetpack hops");
        }
        Ok(())
    }
}

impl M19ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        let n = super::mission::validate_ordered_progress(
            &self.completed,
            self.current.as_ref(),
            &M19_OBJECTIVE_IDS,
            &M19_USE_OBJECTIVES,
            phase,
            tick,
        )?;
        if self.jetpack_taken != (n >= 1)
            || self.challenges.crossing_cleared != (n >= 3)
            || self.latch_departed != (n >= 6)
            || self.gate_open != (n >= 8)
        {
            return Err("M19 facts disagree with ordered progress");
        }
        if phase == MissionPhase::Briefing
            && (self.challenges.paver_interrupted || self.challenges.strip_struck)
        {
            return Err("briefing M19 cannot carry combat facts");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts(n: usize, phase: MissionPhase) -> M19ObjectiveState {
        let target = UseTarget {
            decoration: 0,
            approach: [0.0; 3],
        };
        let mut completed: Vec<String> = M19_OBJECTIVE_IDS
            .iter()
            .take(n)
            .map(|id| (*id).to_owned())
            .collect();
        if phase == MissionPhase::Departed {
            completed.push("party_departed".into());
        }
        let current = (phase != MissionPhase::Departed).then(|| MissionObjective {
            id: M19_OBJECTIVE_IDS
                .get(n)
                .copied()
                .unwrap_or("party_departed")
                .into(),
            action: if n == 0 || n == 8 {
                MissionObjectiveAction::Use {
                    target: target.clone(),
                }
            } else {
                MissionObjectiveAction::Arrival {
                    region: Region3 {
                        min: [-1.0, 0.0, -1.0],
                        max: [1.0, 2.0, 1.0],
                    },
                    feet: [0.0; 3],
                }
            },
        });
        M19ObjectiveState {
            completed,
            current,
            challenges: M19ChallengeState {
                crossing_cleared: n >= 3,
                paver_interrupted: false,
                strip_struck: false,
            },
            jetpack_taken: n >= 1,
            latch_departed: n >= 6,
            gate_open: n >= 8,
            brief_completed: false,
        }
    }

    #[test]
    fn ordered_facts_bind_pack_crossing_latch_and_gate_to_progress() {
        for n in 0..=8 {
            let phase = if n == 0 {
                MissionPhase::Briefing
            } else {
                MissionPhase::InProgress
            };
            facts(n, phase).validate(phase, 10).unwrap();
            for broken in [
                M19ObjectiveState {
                    jetpack_taken: !(n >= 1),
                    ..facts(n, phase)
                },
                M19ObjectiveState {
                    latch_departed: !(n >= 6),
                    ..facts(n, phase)
                },
                M19ObjectiveState {
                    gate_open: !(n >= 8),
                    ..facts(n, phase)
                },
            ] {
                assert!(broken.validate(phase, 10).is_err(), "{n}");
            }
        }
        facts(8, MissionPhase::Departed)
            .validate(MissionPhase::Departed, 10)
            .unwrap();
        assert!(facts(8, MissionPhase::Departed)
            .validate(MissionPhase::Departed, 0)
            .is_err());
        let mut forged = facts(0, MissionPhase::Briefing);
        forged.challenges.strip_struck = true;
        assert!(forged.validate(MissionPhase::Briefing, 1).is_err());
    }

    #[test]
    fn brief_tiers_add_interruption_then_clean_strips() {
        let mut c = M19ChallengeState::default();
        for tier in [
            CampaignDifficulty::Assisted,
            CampaignDifficulty::Standard,
            CampaignDifficulty::Severe,
        ] {
            assert!(!c.brief_completed(tier));
        }
        c.crossing_cleared = true;
        assert!(c.brief_completed(CampaignDifficulty::Assisted));
        assert!(!c.brief_completed(CampaignDifficulty::Standard));
        c.paver_interrupted = true;
        assert!(c.brief_completed(CampaignDifficulty::Standard));
        assert!(c.brief_completed(CampaignDifficulty::Severe));
        c.strip_struck = true;
        assert!(c.brief_completed(CampaignDifficulty::Standard));
        assert!(!c.brief_completed(CampaignDifficulty::Severe));
    }
}
