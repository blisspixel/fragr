//! Preparatory M02 objective authoring. No mission wire or live transition uses this yet.
use super::{identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    MapDecoration, MapDecorationKind, MapPresentation, Region3, UseTarget, USE_DISTANCE,
};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::io;
use std::sync::Arc;

const MAX_OBJECTIVES: usize = 8;
const MAX_GATES: usize = 3;
const MAX_HALF_EXTENT: f32 = 128.0;
const MAX_SOLIDS: usize = 128;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    gates: Vec<Gate>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Objective {
    id: String,
    #[serde(default)]
    after: Option<String>,
    action: Action,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Action {
    Arrival {
        region: Region3,
        feet: [f32; 3],
    },
    Use {
        panel: MapDecoration<String>,
        approach: [f32; 3],
    },
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Gate {
    id: String,
    solid: String,
    lift: f32,
    after: String,
}

#[derive(Debug, Clone)]
struct World {
    mask: u8,
    arena: Arena,
    navigation: Arc<Navigation>,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    worlds: Vec<World>,
    objectives: Vec<PreparedObjective>,
}

#[derive(Debug, Clone)]
struct PreparedObjective {
    id: String,
    feet: [f32; 3],
    required_mask: u8,
    control: Option<UseTarget>,
    arrival: Option<Region3>,
}

impl Prepared {
    pub(crate) fn world(&self, mask: u8) -> Option<(&Arena, &Arc<Navigation>)> {
        self.worlds
            .iter()
            .find(|world| world.mask == mask)
            .map(|world| (&world.arena, &world.navigation))
    }

    pub(super) fn navigations(&self) -> impl Iterator<Item = &Navigation> {
        self.worlds.iter().map(|world| world.navigation.as_ref())
    }

    fn validate_routes(&self, start: [f32; 3], presentation: &MapPresentation) -> io::Result<()> {
        let mut previous_mask = 0;
        for objective in &self.objectives {
            let (arena, navigation) = self
                .world(objective.required_mask)
                .ok_or_else(|| invalid("M02 objective has no prepared gate world"))?;
            if !standing(arena, objective.feet)
                || navigation.route(start, objective.feet, SEARCH_LIMIT).status
                    != RouteStatus::Complete
            {
                return Err(invalid(&format!(
                    "M02 objective {} is unreachable",
                    objective.id
                )));
            }
            if objective.required_mask != previous_mask {
                let (closed_arena, previous) = self
                    .world(previous_mask)
                    .ok_or_else(|| invalid("M02 gate has no prior world"))?;
                if previous.route(start, objective.feet, SEARCH_LIMIT).status
                    != RouteStatus::Unreachable
                {
                    return Err(invalid(
                        "M02 gate does not block its next required objective",
                    ));
                }
                if let Some(region) = &objective.arrival {
                    // A trigger that spans the closed barrier could be entered
                    // from the old side even when its sample point is beyond it.
                    if region.contains(start)
                        || closed_arena.solids.iter().any(|solid| {
                            region.min[0] < solid.max_x
                                && region.max[0] > solid.min_x
                                && region.min[2] < solid.max_z
                                && region.max[2] > solid.min_z
                                && region.min[1] < solid.top
                                && region.max[1] + crate::movement::BODY_HEIGHT > solid.bottom
                        })
                    {
                        return Err(invalid("M02 arrival region spans a closed gate"));
                    }
                }
            }
            previous_mask = objective.required_mask;
            if let Some(control) = &objective.control {
                let point = control
                    .point(presentation, &arena.solids)
                    .ok_or_else(|| invalid("M02 control has no use point"))?;
                let eye = [
                    objective.feet[0],
                    objective.feet[1] + EYE_HEIGHT,
                    objective.feet[2],
                ];
                let distance = (0..3)
                    .map(|axis| (eye[axis] - point[axis]).powi(2))
                    .sum::<f32>()
                    .sqrt();
                if distance > USE_DISTANCE
                    || !crate::combat::line_of_sight(eye, point, &arena.solids)
                {
                    return Err(invalid("M02 approach cannot reach and see its control"));
                }
            }
        }
        if self.worlds.len() > 1 {
            let exit = self
                .objectives
                .last()
                .ok_or_else(|| invalid("M02 has no exit"))?;
            if self.world(0).is_some_and(|(_, nav)| {
                nav.route(start, exit.feet, SEARCH_LIMIT).status != RouteStatus::Unreachable
            }) {
                return Err(invalid(
                    "M02 closed gates do not block the premature exit route",
                ));
            }
        }
        Ok(())
    }
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        solid_ids: &HashMap<String, usize>,
        presentation: &mut MapPresentation,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        if self.objectives.is_empty()
            || self.objectives.len() > MAX_OBJECTIVES
            || self.gates.len() > MAX_GATES
            || arena.half > MAX_HALF_EXTENT
            || arena.solids.len() > MAX_SOLIDS
        {
            return Err(invalid("M02 objective or gate budget exceeded"));
        }
        let mut gate_solids = HashSet::new();
        let mut gate_after = HashSet::new();
        let mut gates = Vec::with_capacity(self.gates.len());
        for gate in self.gates {
            identity(&gate.id, seen)?;
            let solid = *solid_ids
                .get(&gate.solid)
                .ok_or_else(|| invalid("M02 gate references an unknown solid"))?;
            if !gate_solids.insert(solid)
                || !gate_after.insert(gate.after.clone())
                || !gate.lift.is_finite()
                || !(0.125..=16.0).contains(&gate.lift)
            {
                return Err(invalid(
                    "M02 gate needs a unique solid and trigger, with bounded lift",
                ));
            }
            gates.push((solid, gate.lift, gate.after));
        }
        let mut objectives = Vec::with_capacity(self.objectives.len());
        let mut previous: Option<String> = None;
        for objective in self.objectives {
            identity(&objective.id, seen)?;
            // A linear authored chain gives exactly one legal next objective and
            // at most MAX_GATES + 1 prepared worlds. Branching needs a separate
            // explicit state-budget design before it enters the live mission.
            if objective.after != previous {
                return Err(invalid(
                    "M02 objectives need a linear, acyclic prerequisite chain",
                ));
            }
            let (feet, control, arrival) = match objective.action {
                Action::Arrival { region, feet } => {
                    if !region.valid(arena.half) || !region.contains(feet) {
                        return Err(invalid(
                            "M02 arrival region does not contain its standing point",
                        ));
                    }
                    (feet, None, Some(region))
                }
                Action::Use { panel, approach } => {
                    let host = *solid_ids
                        .get(&panel.solid)
                        .ok_or_else(|| invalid("M02 control references an unknown solid"))?;
                    if gate_solids.contains(&host)
                        || !matches!(
                            panel.kind,
                            MapDecorationKind::Terminal | MapDecorationKind::LiftControl
                        )
                    {
                        return Err(invalid(
                            "M02 control needs a static host and a usable panel kind",
                        ));
                    }
                    let target = UseTarget {
                        decoration: presentation.decorations.len(),
                        approach,
                    };
                    presentation.decorations.push(panel.with_solid(host));
                    (approach, Some(target), None)
                }
            };
            objectives.push(PreparedObjective {
                id: objective.id.clone(),
                feet,
                required_mask: 0,
                control,
                arrival,
            });
            previous = Some(objective.id);
        }
        if objectives
            .last()
            .is_none_or(|last| last.id != "party_departed")
        {
            return Err(invalid("M02 final objective must be party_departed"));
        }
        for (_, _, after) in &gates {
            if !objectives.iter().any(|objective| &objective.id == after)
                || after == "party_departed"
            {
                return Err(invalid("M02 gate trigger must name a nonfinal objective"));
            }
        }
        let mut mask = 0u8;
        for objective in &mut objectives {
            objective.required_mask = mask;
            if let Some((index, _)) = gates
                .iter()
                .enumerate()
                .find(|(_, (_, _, after))| *after == objective.id)
            {
                mask |= 1 << index;
            }
        }
        // Only the actually reachable sequence of masks is constructed. Each
        // variant has its own collision and topology before server readiness.
        let mut worlds = Vec::with_capacity(gates.len() + 1);
        let mut mask = 0u8;
        let mut current = arena.clone();
        worlds.push(Self::build_world(mask, current.clone(), presentation)?);
        for objective in &objectives {
            if let Some((index, (solid, lift, _))) = gates
                .iter()
                .enumerate()
                .find(|(_, (_, _, after))| *after == objective.id)
            {
                mask |= 1 << index;
                current.solids[*solid].bottom += lift;
                current.solids[*solid].top += lift;
                worlds.push(Self::build_world(mask, current.clone(), presentation)?);
            }
        }
        let prepared = Prepared { worlds, objectives };
        prepared.validate_routes(start, presentation)?;
        Ok(prepared)
    }

    fn build_world(mask: u8, arena: Arena, presentation: &MapPresentation) -> io::Result<World> {
        crate::movement::validate_geometry(arena.half, &arena.solids).map_err(invalid)?;
        crate::protocol::validate_map_presentation(Some(presentation), &arena.solids)
            .map_err(invalid)?;
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        Ok(World {
            mask,
            arena,
            navigation,
        })
    }
}
