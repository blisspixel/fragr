//! Planned Works: validate the concourse, changed Low Water and the trench,
//! prepare the closed and open waterworks worlds and prove their routes.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    ControlDomain, EnemyKind, M19JetHop, M19MapGeometry, M19WorkMark, MapPresentation,
    MissionObjective, MissionObjectiveAction, Region3, UseTarget, M19_OBJECTIVE_IDS,
    M19_USE_OBJECTIVES, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 5] = [
    "crossing_guard",
    "street_paver",
    "market_strip_crew",
    "roof_watch",
    "trench_works",
];

/// Exact authored rosters, in group order. The lone Paver teaches before any
/// mixed strip encounter.
pub(crate) const ROSTERS: [&[EnemyKind]; 5] = [
    &[
        EnemyKind::Sweeper,
        EnemyKind::Sweeper,
        EnemyKind::HeavySweeper,
        EnemyKind::Notary,
        EnemyKind::Sweeper,
    ],
    &[EnemyKind::Paver],
    &[
        EnemyKind::Paver,
        EnemyKind::Paver,
        EnemyKind::HeavySweeper,
        EnemyKind::Sweeper,
    ],
    &[
        EnemyKind::Notary,
        EnemyKind::Notary,
        EnemyKind::Paver,
        EnemyKind::Sweeper,
    ],
    &[EnemyKind::Paver, EnemyKind::Paver, EnemyKind::HeavySweeper],
];

/// A ledge this close to the jetpack ceiling could be reached only by a
/// hovering body skimming the limit; refuse the ambiguity.
const CEILING_LEDGE_MARGIN: f32 = 0.5;
/// Thrust needs room above every authored place a body is asked to stand.
const CEILING_HEADROOM: f32 = 2.0;

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum ObjectiveDefinition {
    Arrival {
        id: String,
        arrival: Region3,
        approach: [f32; 3],
    },
    Use {
        id: String,
    },
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<ObjectiveDefinition>,
    departure: UseTarget,
    boarding: Region3,
    stores: UseTarget,
    jetpack_ceiling: f32,
    latch_route: Vec<[f32; 3]>,
    work_marks: Vec<M19WorkMark>,
    jet_hops: Vec<M19JetHop>,
    waterworks_gate: String,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M19MapGeometry,
    pub(crate) initial: Arena,
    pub(crate) open: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) open_navigation: Arc<Navigation>,
}

fn reach(target: &UseTarget, presentation: &MapPresentation, solids: &[Solid]) -> io::Result<()> {
    let point = target
        .point(presentation, solids)
        .ok_or_else(|| invalid("M19 use target point missing"))?;
    let eye = [
        target.approach[0],
        target.approach[1] + EYE_HEIGHT,
        target.approach[2],
    ];
    let distance = (0..3)
        .map(|axis| (point[axis] - eye[axis]).powi(2))
        .sum::<f32>()
        .sqrt();
    if distance > USE_DISTANCE - 0.2 || !crate::combat::line_of_sight(eye, point, solids) {
        return Err(invalid("M19 use target approach out of reach"));
    }
    Ok(())
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        definitions: &[EncounterDefinition],
        presentation: &MapPresentation,
        ids: &HashMap<String, usize>,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        if definitions.len() != GROUPS.len()
            || definitions.iter().enumerate().any(|(i, group)| {
                group.id != GROUPS[i]
                    || group.after.as_deref() != i.checked_sub(1).map(|p| GROUPS[p])
                    || group.enemies.len() != ROSTERS[i].len()
                    || ROSTERS[i].iter().any(|kind| {
                        group.enemies.iter().filter(|e| e.kind == *kind).count()
                            != ROSTERS[i].iter().filter(|k| *k == kind).count()
                    })
            })
        {
            return Err(invalid("M19 requires five exact chained encounter rosters"));
        }
        // After the wipe nothing hostile in Low Water answers to the Union:
        // every bot is absorbed and every Paver is a restoration machine.
        if definitions
            .iter()
            .flat_map(|group| &group.enemies)
            .any(|enemy| enemy.control == ControlDomain::Union)
        {
            return Err(invalid(
                "M19 hostiles are absorbed bots and restoration machines, never the Union's",
            ));
        }
        if self.objectives.len() != M19_OBJECTIVE_IDS.len() {
            return Err(invalid("M19 requires eight ordered objectives"));
        }
        let mut objectives = Vec::with_capacity(M19_OBJECTIVE_IDS.len());
        for (index, definition) in self.objectives.into_iter().enumerate() {
            let objective = match definition {
                ObjectiveDefinition::Arrival {
                    id,
                    arrival,
                    approach,
                } if !M19_USE_OBJECTIVES.contains(&index) => MissionObjective {
                    id,
                    action: MissionObjectiveAction::Arrival {
                        region: arrival,
                        feet: approach,
                    },
                },
                ObjectiveDefinition::Use { id } if M19_USE_OBJECTIVES.contains(&index) => {
                    MissionObjective {
                        id,
                        action: MissionObjectiveAction::Use {
                            target: self.stores.clone(),
                        },
                    }
                }
                _ => return Err(invalid("M19 objective action out of order")),
            };
            if objective.id != M19_OBJECTIVE_IDS[index] {
                return Err(invalid("M19 objective id mismatch"));
            }
            identity(&objective.id, seen)?;
            objectives.push(objective);
        }
        let gate = *ids
            .get(&self.waterworks_gate)
            .ok_or_else(|| invalid("M19 waterworks gate solid missing"))?;
        let geometry = M19MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            stores: self.stores,
            jetpack_ceiling: self.jetpack_ceiling,
            latch_route: self.latch_route,
            work_marks: self.work_marks,
            jet_hops: self.jet_hops,
            gate_open: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        reach(&geometry.stores, presentation, &arena.solids)?;

        // Vertical clearance: no ledge just under the ceiling, and room to
        // thrust above every authored standing place.
        let ceiling = geometry.jetpack_ceiling;
        if arena
            .solids
            .iter()
            .any(|solid| (solid.top - ceiling).abs() < CEILING_LEDGE_MARGIN)
        {
            return Err(invalid("M19 ledge sits at the jetpack ceiling"));
        }
        // The ordered route a party walks: the counter, then every arrival.
        let route: Vec<[f32; 3]> = std::iter::once(geometry.stores.approach)
            .chain(
                geometry
                    .objectives
                    .iter()
                    .filter_map(|objective| match &objective.action {
                        MissionObjectiveAction::Arrival { feet, .. } => Some(*feet),
                        _ => None,
                    }),
            )
            .collect();
        let mut places = vec![start, geometry.departure.approach];
        places.extend(&route);
        for group in definitions {
            places.extend(
                group
                    .enemies
                    .iter()
                    .filter(|enemy| enemy.hover.is_none())
                    .map(|enemy| enemy.feet),
            );
        }
        if places
            .iter()
            .any(|place| place[1] + CEILING_HEADROOM > ceiling)
        {
            return Err(invalid("M19 jetpack ceiling leaves no headroom"));
        }

        // The ordinary walking route reaches every objective without fuel.
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        if !standing(arena, start) {
            return Err(invalid("M19 entry is not supported"));
        }
        let mut walked = start;
        for place in &route {
            if navigation.route(walked, *place, SEARCH_LIMIT).status != RouteStatus::Complete {
                return Err(invalid(&format!(
                    "M19 walking route cannot reach {place:?} from {walked:?}"
                )));
            }
            walked = *place;
        }

        // Every authored hop is walkable to its launch and actually lands
        // with one full pack under the ordinary live step.
        for hop in &geometry.jet_hops {
            if !standing(arena, hop.launch)
                || !standing(arena, hop.landing)
                || navigation.route(start, hop.launch, SEARCH_LIMIT).status != RouteStatus::Complete
                || crate::movement::jetpack::simulate_hop(arena, hop.launch, hop.landing, ceiling)
                    .is_none()
            {
                return Err(invalid("M19 jetpack hop does not land"));
            }
        }

        let mut open = arena.clone();
        let closed = open.solids[gate];
        open.solids[gate] = Solid {
            bottom: 0.0,
            top: 0.05,
            ..closed
        };
        if closed.top < 2.0 || !geometry.boarding.contains(geometry.departure.approach) {
            return Err(invalid("M19 waterworks gate must close the boarding"));
        }
        let open_navigation = Navigation::shared(open.clone()).map_err(invalid)?;
        let trench = match &geometry.objectives[7].action {
            MissionObjectiveAction::Arrival { feet, .. } => *feet,
            _ => unreachable!("validated above"),
        };
        if navigation
            .route(trench, geometry.departure.approach, SEARCH_LIMIT)
            .status
            == RouteStatus::Complete
        {
            return Err(invalid("M19 closed gate does not hold the boarding"));
        }
        if open_navigation
            .route(trench, geometry.departure.approach, SEARCH_LIMIT)
            .status
            != RouteStatus::Complete
        {
            return Err(invalid("M19 open waterworks cannot reach the departure"));
        }
        reach(&geometry.departure, presentation, &open.solids)?;
        Ok(Prepared {
            geometry,
            initial: arena.clone(),
            open,
            navigation,
            open_navigation,
        })
    }
}
