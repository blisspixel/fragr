//! Radial custody archive: ordered lessons, the support-node machine and
//! optional rescue facts. Captives and Renn are presentation of these facts.
use super::{
    MapDecorationKind, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    MissionState, Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

mod neutral;
pub(crate) use neutral::M08NeutralLayout;

/// The required chain, in order. `machine_wrecked` is the support-node Shoot
/// objective; every other step is an arrival bound to its cleared group.
pub const M08_OBJECTIVE_IDS: [&str; 7] = [
    "hall_cleared",
    "lower_gallery_cleared",
    "mines_cleared",
    "auditor_cleared",
    "machine_wrecked",
    "evidence_taken",
    "exit_cleared",
];
/// Chain index of the support-node objective.
pub const M08_MACHINE_STEP: usize = 4;
pub const M08_BAYS_ID: &str = "custody_released";
pub const M08_CABINET_ID: &str = "recovered_mind_secured";
/// Health of each of the four glowing support nodes.
pub const M08_NODE_HP: u8 = 50;
pub const M08_NODES: usize = 4;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M08NodeGeometry {
    pub solid: usize,
    /// Supported feet that see the node over the gallery rail.
    pub approach: [f32; 3],
    pub aim: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M08MapGeometry {
    /// The six arrival steps of the chain, without `machine_wrecked`.
    pub objectives: Vec<MissionObjective>,
    pub nodes: Vec<M08NodeGeometry>,
    pub machine: usize,
    /// The upper gallery seal, the level's one door.
    pub seal: usize,
    pub bays: MissionObjective,
    pub cabinet: MissionObjective,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub companion_start: [f32; 3],
    /// Follows the runtime world: the seal lifts when the Auditor falls.
    pub seal_open: bool,
    /// Follows the runtime world: the machine drops when the last node breaks.
    pub machine_fallen: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct M08ObjectiveState {
    pub completed: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current: Option<MissionObjective>,
    /// Remaining health of each support node, in geometry order.
    pub node_hp: Vec<u8>,
    pub seal_open: bool,
    pub machine_fallen: bool,
    /// Renn offered the layout after the lower gallery cleared.
    pub custodian_joined: bool,
    /// The lower bays were opened after the upper gallery Auditor fell.
    pub custody_released: bool,
    /// Orrin's backup was taken from the cold cabinet.
    pub recovered_mind_secured: bool,
    /// The transfer evidence was taken from the bridge desk.
    pub transfer_evidence: bool,
    /// Released captives reached the freight car with the departing party.
    pub captives_evacuated: bool,
}

impl M08MapGeometry {
    /// The chain step at `index`, or the departure Use after it.
    pub fn step(&self, index: usize, node_hp: &[u8]) -> Option<MissionObjective> {
        match index {
            0..=3 => self.objectives.get(index).cloned(),
            M08_MACHINE_STEP => {
                let next = node_hp.iter().position(|hp| *hp > 0)?;
                let node = self.nodes.get(next)?;
                Some(MissionObjective {
                    id: M08_OBJECTIVE_IDS[M08_MACHINE_STEP].into(),
                    action: MissionObjectiveAction::Shoot {
                        solid: node.solid,
                        approach: node.approach,
                        aim: node.aim,
                    },
                })
            }
            5 | 6 => self.objectives.get(index - 1).cloned(),
            7 => Some(MissionObjective {
                id: "party_departed".into(),
                action: MissionObjectiveAction::Use {
                    target: self.departure.clone(),
                },
            }),
            _ => None,
        }
    }

    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let point = |p: [f32; 3]| {
            p.iter().all(|v| v.is_finite())
                && p[0].abs() <= half
                && p[2].abs() <= half
                && (0.0..=512.0).contains(&p[1])
        };
        let arrival = |s: &MissionObjective, id: &str| {
            s.id == id
                && matches!(&s.action, MissionObjectiveAction::Arrival {region, feet}
                    if region.valid(half) && point(*feet) && region.contains(*feet))
        };
        let presentation = presentation.ok_or("M08 presentation missing")?;
        M08NeutralLayout::read(half, solids, presentation)?;
        let arrivals = [0, 1, 2, 3, 5, 6].map(|i| M08_OBJECTIVE_IDS[i]);
        let mut solids_used = std::collections::HashSet::new();
        if !half.is_finite()
            || half <= 0.0
            || self.objectives.len() != arrivals.len()
            || self
                .objectives
                .iter()
                .zip(arrivals)
                .any(|(s, id)| !arrival(s, id))
            || self.nodes.len() != M08_NODES
            || self.nodes.iter().any(|node| {
                node.solid >= solids.len()
                    || !point(node.approach)
                    || !point(node.aim)
                    || !solids_used.insert(node.solid)
            })
            || self.machine >= solids.len()
            || self.seal >= solids.len()
            || !solids_used.insert(self.machine)
            || !solids_used.insert(self.seal)
            || !arrival(&self.bays, M08_BAYS_ID)
            || !arrival(&self.cabinet, M08_CABINET_ID)
            || !self.boarding.valid(half)
            || !point(self.companion_start)
            || !point(self.departure.approach)
            || !self.boarding.contains(self.departure.approach)
            || self.departure.point(presentation, solids).is_none()
            || self.machine_fallen && !self.seal_open
            || presentation
                .decorations
                .get(self.departure.decoration)
                .is_none_or(|p| p.kind != MapDecorationKind::M08FreightDeparture)
        {
            return Err("invalid M08 geometry");
        }
        Ok(())
    }
}

impl MissionState {
    pub(super) fn validate_m08(&self) -> Result<(), &'static str> {
        let f = self.m08.as_ref().ok_or("M08 facts missing")?;
        if self.m02.is_some()
            || self.m03.is_some()
            || self.m04.is_some()
            || self.m05.is_some()
            || self.m06.is_some()
            || !matches!(
                self.phase,
                MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
            )
        {
            return Err("invalid M08 mission envelope");
        }
        let done = f.completed.len();
        let id = |i: usize| {
            if i == M08_OBJECTIVE_IDS.len() {
                "party_departed"
            } else {
                M08_OBJECTIVE_IDS[i]
            }
        };
        if done > M08_OBJECTIVE_IDS.len() + 1
            || f.completed.iter().enumerate().any(|(i, c)| c != id(i))
            || (self.phase == MissionPhase::Departed) != (done == M08_OBJECTIVE_IDS.len() + 1)
            || f.current.is_some() != (done <= M08_OBJECTIVE_IDS.len())
            || self.phase == MissionPhase::Briefing
                && (done > 0
                    || f.seal_open
                    || f.custody_released
                    || f.recovered_mind_secured
                    || f.node_hp.iter().any(|hp| *hp != M08_NODE_HP))
            || f.node_hp.len() != M08_NODES
            || f.node_hp.iter().any(|hp| *hp > M08_NODE_HP)
            // Nodes take damage only once the machine is the current step.
            || done < M08_MACHINE_STEP && f.node_hp.iter().any(|hp| *hp != M08_NODE_HP)
            || (done > M08_MACHINE_STEP) != f.node_hp.iter().all(|hp| *hp == 0)
            || f.machine_fallen != (done > M08_MACHINE_STEP)
            || done > 3 && !f.seal_open
            || f.seal_open && done < 3
            || f.custodian_joined != (done >= 2)
            || f.transfer_evidence != (done > 5)
            || (f.custody_released || f.recovered_mind_secured) && !f.seal_open
            || f.captives_evacuated && !(f.custody_released && self.phase == MissionPhase::Departed)
        {
            return Err("invalid M08 objective facts");
        }
        if let Some(current) = &f.current {
            let point =
                |p: &[f32; 3]| p.iter().all(|v| v.is_finite() && v.abs() <= 512.0) && p[1] >= 0.0;
            let shape = matches!(
                (&current.action, done),
                (MissionObjectiveAction::Arrival { .. }, 0..=3 | 5 | 6)
                    | (MissionObjectiveAction::Shoot { .. }, M08_MACHINE_STEP)
                    | (MissionObjectiveAction::Use { .. }, 7)
            );
            if current.id != id(done) || !shape {
                return Err("invalid M08 current objective");
            }
            match &current.action {
                MissionObjectiveAction::Arrival { region, feet }
                    if !region.valid(512.0) || !point(feet) || !region.contains(*feet) =>
                {
                    return Err("invalid M08 arrival target");
                }
                MissionObjectiveAction::Shoot {
                    solid,
                    approach,
                    aim,
                } if *solid >= crate::movement::MAX_SOLIDS || !point(approach) || !point(aim) => {
                    return Err("invalid M08 node target");
                }
                MissionObjectiveAction::Use { target }
                    if !point(&target.approach)
                        || target.decoration >= super::MAX_MAP_DECORATIONS =>
                {
                    return Err("invalid M08 use target");
                }
                _ => {}
            }
        }
        Ok(())
    }
}
