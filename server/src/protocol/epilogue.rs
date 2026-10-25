//! Still Here: the survival-gated epilogue after Local Exception.
//!
//! One place in two worlds. The refuge in the first light after the reprieve,
//! then the same refuge years later. There is nothing to fight and nothing to
//! fail. Two ordered objectives and a last use: stay with Latch while they
//! count (the world then turns), walk the court years later, and ask Latch the
//! score. Who is present comes from the people this run actually freed, read
//! from the saved survival result; it changes faces, never the ending.
use super::{MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase, UseTarget};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const EPILOGUE_OBJECTIVE_IDS: [&str; 2] = ["stay_with_latch", "years_later"];
/// The transition between the two worlds: the card that says years have
/// passed, at 20 Hz. The world turns this long after Latch's use.
pub const EPILOGUE_TURN_TICKS: u64 = 80;
/// Everyone authored across both worlds, named and not.
pub const EPILOGUE_MAX_PEOPLE: usize = 120;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EpilogueStage {
    /// The first light after the reprieve.
    Aftermath,
    /// The same court, years later.
    Later,
}

/// A rescue the run carried into the refuge. Presence only, never a score.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EpilogueSurvivor {
    /// Latch opened at least one recall car in level 3.
    Cars,
    /// Edda's clinic team came out of level 4.
    Edda,
    /// Splice reached the level 5 freight; release alone does not count.
    Splice,
    /// Orrin's backup was secured in level 8.
    Orrin,
    /// Sorrel was freed of control in level 11.
    Sorrel,
    /// The games' entrants were armed in level 15.
    Entrants,
    /// The prison bus was freed on the avenue in level 16.
    Bus,
}

/// How a presenter places a person. People on their feet or on the ground
/// block a walker; people on furniture leave that to the furniture.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EpiloguePose {
    Stand,
    /// Sitting on the ground.
    Sit,
    Child,
    Work,
    /// Sitting on a bench, a crate or a cab seat.
    Perch,
    /// Lying on a cot.
    Lie,
}

impl EpiloguePose {
    pub fn blocks(self) -> bool {
        !matches!(self, Self::Perch | Self::Lie)
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct EpiloguePerson {
    pub id: String,
    pub stage: EpilogueStage,
    pub feet: [f32; 3],
    pub yaw: f32,
    pub pose: EpiloguePose,
    /// Present only when the run carried this rescue.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requires: Option<EpilogueSurvivor>,
    /// Present only when the run did not: somebody else lit the lamp.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unless: Option<EpilogueSurvivor>,
}

impl EpiloguePerson {
    pub fn present(&self, stage: EpilogueStage, refuge: &EpilogueRefuge) -> bool {
        self.stage == stage
            && self.requires.is_none_or(|who| refuge.has(who))
            && self.unless.is_none_or(|who| !refuge.has(who))
    }
}

/// Who the run brought to the refuge. Every flag is a person or a group the
/// player actually freed; an absent flag never confirms a death.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct EpilogueRefuge {
    pub cars: bool,
    pub edda: bool,
    pub splice: bool,
    pub orrin: bool,
    pub sorrel: bool,
    pub entrants: bool,
    pub bus: bool,
}

impl EpilogueRefuge {
    /// Everyone a run can bring, for fixtures and the fullest court.
    pub const EVERYONE: Self = Self {
        cars: true,
        edda: true,
        splice: true,
        orrin: true,
        sorrel: true,
        entrants: true,
        bus: true,
    };

    pub fn has(&self, who: EpilogueSurvivor) -> bool {
        match who {
            EpilogueSurvivor::Cars => self.cars,
            EpilogueSurvivor::Edda => self.edda,
            EpilogueSurvivor::Splice => self.splice,
            EpilogueSurvivor::Orrin => self.orrin,
            EpilogueSurvivor::Sorrel => self.sorrel,
            EpilogueSurvivor::Entrants => self.entrants,
            EpilogueSurvivor::Bus => self.bus,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct EpilogueMapGeometry {
    /// Latch's ledger on the repair table: stay with Latch while they count.
    pub latch: UseTarget,
    /// The court years later, from the tram stop to the quay.
    pub arrival: super::Region3,
    pub arrival_feet: [f32; 3],
    /// The quay bench where Latch sits years later: ask the score.
    pub departure: UseTarget,
    /// Where the party stands when the world turns.
    pub later_spawn: [f32; 3],
    pub later_yaw: f32,
    /// Decoration index of the salvaged harbour display on the quay.
    pub ferry_board: usize,
    pub people: Vec<EpiloguePerson>,
    /// Solid indices standing only in the first light, and only years later.
    /// The other world stows them outside the square; presenters hide them.
    pub aftermath_only: Vec<usize>,
    pub later_only: Vec<usize>,
    /// Runtime world: false the first light, true years later.
    pub later: bool,
}

fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=crate::movement::MAX_HALF_EXTENT * 2.0).contains(&p[1])
}

fn identifier(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 32
        && id
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}

impl EpilogueMapGeometry {
    pub fn latch_objective(&self) -> MissionObjective {
        MissionObjective {
            id: EPILOGUE_OBJECTIVE_IDS[0].into(),
            action: MissionObjectiveAction::Use {
                target: self.latch.clone(),
            },
        }
    }

    pub fn arrival_objective(&self) -> MissionObjective {
        MissionObjective {
            id: EPILOGUE_OBJECTIVE_IDS[1].into(),
            action: MissionObjectiveAction::Arrival {
                region: self.arrival.clone(),
                feet: self.arrival_feet,
            },
        }
    }

    pub fn departure_objective(&self) -> MissionObjective {
        MissionObjective {
            id: "party_departed".into(),
            action: MissionObjectiveAction::Use {
                target: self.departure.clone(),
            },
        }
    }

    /// Where each party member stands when the world turns: the spawn, then
    /// alternately either side of it across the platform.
    pub fn later_slots(&self) -> [[f32; 3]; super::MISSION_PARTY_LIMIT] {
        let across = [-self.later_yaw.sin(), self.later_yaw.cos()];
        std::array::from_fn(|slot| {
            let step = slot.div_ceil(2) as f32 * 0.9;
            let offset = if slot % 2 == 1 { step } else { -step };
            [
                self.later_spawn[0] + across[0] * offset,
                self.later_spawn[1],
                self.later_spawn[2] + across[1] * offset,
            ]
        })
    }

    pub fn stage(&self) -> EpilogueStage {
        if self.later {
            EpilogueStage::Later
        } else {
            EpilogueStage::Aftermath
        }
    }

    /// Everyone in this world for this run who blocks a walker, in authored
    /// order. People on furniture are left to the furniture.
    pub fn blocking(&self, refuge: &EpilogueRefuge) -> Vec<EpiloguePresent> {
        let stage = self.stage();
        self.people
            .iter()
            .filter(|person| person.present(stage, refuge) && person.pose.blocks())
            .map(|person| EpiloguePresent {
                id: person.id.clone(),
                feet: person.feet,
            })
            .collect()
    }

    pub fn validate(
        &self,
        half_extent: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let p = presentation.ok_or("Still Here requires panel presentation")?;
        for (target, kind) in [
            (&self.latch, super::MapDecorationKind::EpilogueLedger),
            (&self.departure, super::MapDecorationKind::EpilogueBench),
        ] {
            let panel = p
                .decorations
                .get(target.decoration)
                .ok_or("Still Here references an unknown panel")?;
            if panel.kind != kind
                || target.point(p, solids).is_none()
                || !point(target.approach, half_extent)
            {
                return Err("invalid Still Here use target");
            }
        }
        if p.decorations
            .get(self.ferry_board)
            .is_none_or(|panel| panel.kind != super::MapDecorationKind::EpilogueFerryBoard)
        {
            return Err("Still Here ferry board missing");
        }
        if !self.arrival.valid(half_extent)
            || !point(self.arrival_feet, half_extent)
            || !self.arrival.contains(self.arrival_feet)
            || !point(self.later_spawn, half_extent)
            || !self.later_yaw.is_finite()
            || self.arrival.contains(self.later_spawn)
        {
            return Err("invalid Still Here walk");
        }
        let mut worlds = std::collections::HashSet::new();
        if self.aftermath_only.len() > 32
            || self.later_only.len() > 32
            || self
                .aftermath_only
                .iter()
                .chain(&self.later_only)
                .any(|index| *index >= solids.len() || !worlds.insert(*index))
            || p.decorations
                .iter()
                .any(|panel| worlds.contains(&panel.solid))
        {
            return Err("invalid Still Here world solids");
        }
        if self.people.len() > EPILOGUE_MAX_PEOPLE {
            return Err("too many Still Here people");
        }
        let mut seen = std::collections::HashSet::new();
        for person in &self.people {
            if !identifier(&person.id)
                || !seen.insert((person.stage, person.id.as_str()))
                || !point(person.feet, half_extent)
                || !person.yaw.is_finite()
                || person.requires.is_some() && person.requires == person.unless
            {
                return Err("invalid Still Here person");
            }
        }
        Ok(())
    }
}

/// A person standing in the current world, keyed for contact as
/// `epilogue/<id>`.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct EpiloguePresent {
    pub id: String,
    pub feet: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct EpilogueObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub refuge: EpilogueRefuge,
    /// Tick of the use beside Latch. The world turns `EPILOGUE_TURN_TICKS`
    /// later.
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub turning_at: Option<u64>,
    /// The court is years later.
    pub later: bool,
    /// People standing or sitting on the ground in the current world, keyed
    /// for contact as `epilogue/<id>`.
    pub blocking: Vec<EpiloguePresent>,
}

impl EpilogueObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        let n = super::mission::validate_ordered_progress(
            &self.completed,
            self.current.as_ref(),
            &EPILOGUE_OBJECTIVE_IDS,
            &[0],
            phase,
            tick,
        )?;
        if (n >= 1) != self.turning_at.is_some()
            || n >= 2 && !self.later
            || self.later
                && self
                    .turning_at
                    .is_none_or(|at| at.saturating_add(EPILOGUE_TURN_TICKS) > tick)
            || self.turning_at.is_some_and(|at| at > tick)
            || phase == MissionPhase::Departed && !self.later
        {
            return Err("Still Here facts disagree with ordered progress");
        }
        if self.blocking.len() > EPILOGUE_MAX_PEOPLE {
            return Err("too many Still Here people");
        }
        let mut seen = std::collections::HashSet::new();
        for person in &self.blocking {
            if !identifier(&person.id)
                || !seen.insert(person.id.as_str())
                || !person.feet.iter().all(|v| v.is_finite())
            {
                return Err("invalid Still Here person");
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Region3;

    fn facts() -> EpilogueObjectiveState {
        EpilogueObjectiveState {
            completed: Vec::new(),
            current: Some(MissionObjective {
                id: "stay_with_latch".into(),
                action: MissionObjectiveAction::Use {
                    target: UseTarget {
                        decoration: 0,
                        approach: [20.0, 0.0, -6.0],
                    },
                },
            }),
            refuge: EpilogueRefuge::default(),
            turning_at: None,
            later: false,
            blocking: vec![EpiloguePresent {
                id: "latch".into(),
                feet: [21.0, 0.0, -6.0],
            }],
        }
    }

    fn arrival() -> MissionObjective {
        MissionObjective {
            id: "years_later".into(),
            action: MissionObjectiveAction::Arrival {
                region: Region3 {
                    min: [-30.0, 0.0, -6.0],
                    max: [-20.0, 3.0, 6.0],
                },
                feet: [-25.0, 0.0, 0.0],
            },
        }
    }

    #[test]
    fn strict_facts_follow_the_turn() {
        let base = facts();
        base.validate(MissionPhase::Briefing, 0).unwrap();
        base.validate(MissionPhase::InProgress, 10).unwrap();

        // The use beside Latch starts the turn; years later only after it.
        let mut turning = base.clone();
        turning.completed = vec!["stay_with_latch".into()];
        turning.current = Some(arrival());
        assert!(turning.validate(MissionPhase::InProgress, 100).is_err());
        turning.turning_at = Some(100);
        turning.validate(MissionPhase::InProgress, 100).unwrap();
        assert!(
            turning.validate(MissionPhase::InProgress, 99).is_err(),
            "a turn cannot start in the future"
        );
        let mut early = turning.clone();
        early.later = true;
        assert!(early
            .validate(MissionPhase::InProgress, 100 + EPILOGUE_TURN_TICKS - 1)
            .is_err());
        early
            .validate(MissionPhase::InProgress, 100 + EPILOGUE_TURN_TICKS)
            .unwrap();

        // Arriving years later needs the later world.
        let mut walked = turning.clone();
        walked.completed.push("years_later".into());
        walked.current = Some(MissionObjective {
            id: "party_departed".into(),
            action: MissionObjectiveAction::Use {
                target: UseTarget {
                    decoration: 1,
                    approach: [-30.0, 0.0, 0.0],
                },
            },
        });
        assert!(walked.validate(MissionPhase::InProgress, 400).is_err());
        walked.later = true;
        walked.validate(MissionPhase::InProgress, 400).unwrap();

        let mut done = walked.clone();
        done.completed.push("party_departed".into());
        done.current = None;
        done.validate(MissionPhase::Departed, 500).unwrap();
        assert!(done.validate(MissionPhase::InProgress, 500).is_err());

        let mut twice = base.clone();
        twice.blocking.push(twice.blocking[0].clone());
        assert!(twice.validate(MissionPhase::InProgress, 10).is_err());
        let mut odd = base;
        odd.blocking[0].id = "Latch".into();
        assert!(odd.validate(MissionPhase::InProgress, 10).is_err());
    }

    #[test]
    fn presence_follows_the_carried_rescues() {
        let person = |requires, unless| EpiloguePerson {
            id: "edda".into(),
            stage: EpilogueStage::Aftermath,
            feet: [0.0; 3],
            yaw: 0.0,
            pose: EpiloguePose::Work,
            requires,
            unless,
        };
        let alone = EpilogueRefuge::default();
        let with_edda = EpilogueRefuge {
            edda: true,
            ..alone
        };
        let edda = person(Some(EpilogueSurvivor::Edda), None);
        assert!(!edda.present(EpilogueStage::Aftermath, &alone));
        assert!(edda.present(EpilogueStage::Aftermath, &with_edda));
        assert!(!edda.present(EpilogueStage::Later, &with_edda));
        let stand_in = person(None, Some(EpilogueSurvivor::Edda));
        assert!(stand_in.present(EpilogueStage::Aftermath, &alone));
        assert!(!stand_in.present(EpilogueStage::Aftermath, &with_edda));
        for who in [
            EpilogueSurvivor::Cars,
            EpilogueSurvivor::Splice,
            EpilogueSurvivor::Orrin,
            EpilogueSurvivor::Sorrel,
            EpilogueSurvivor::Entrants,
            EpilogueSurvivor::Bus,
        ] {
            assert!(!alone.has(who));
        }
    }
}
