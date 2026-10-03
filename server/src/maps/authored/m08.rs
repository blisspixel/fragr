//! The radial custody archive: one static world and two precomputed stages,
//! the lifted upper gallery seal and the fallen custody machine.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M08MapGeometry, M08NodeGeometry, MapDecoration, MapDecorationKind, MapPresentation,
    MissionObjective, MissionObjectiveAction, Region3, UseTarget, M08_BAYS_ID, M08_CABINET_ID,
    M08_NODES, M08_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const REQUIRED_GROUPS: [&str; 6] = [
    "records_hall",
    "lower_gallery",
    "mine_lesson",
    "upper_auditor",
    "machine_bridge",
    "exit_counter",
];

/// The one optional group: an ambush among the cooling pipes past the seal.
/// It binds no objective and never gates departure.
pub(crate) const SERVICE_RING: &str = "service_ring";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    seal: Moved,
    nodes: Vec<Node>,
    machine: Moved,
    bays: Objective,
    cabinet: Objective,
    departure: Departure,
    companion_start: [f32; 3],
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Objective {
    id: String,
    arrival: Region3,
    approach: [f32; 3],
    requires_encounter: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Bounds {
    min: [f32; 3],
    max: [f32; 3],
}
/// A solid with its replacement in a later stage.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Moved {
    solid: String,
    #[serde(alias = "fallen")]
    open: Bounds,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Node {
    solid: String,
    approach: [f32; 3],
    fallen: Bounds,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Departure {
    panel: MapDecoration<String>,
    approach: [f32; 3],
    boarding: Region3,
    requires_encounter: String,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M08MapGeometry,
    /// Required groups in chain order.
    pub(crate) encounters: [usize; 6],
    /// The Auditor group whose fall lifts the seal and frees the bays.
    pub(crate) seal_encounter: usize,
    pub(crate) bridge_encounter: usize,
    pub(crate) departure_encounter: usize,
    /// Seal lifted.
    pub(crate) opened: Arena,
    /// Seal lifted and the machine dropped to the shaft floor.
    pub(crate) fallen: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) opened_navigation: Arc<Navigation>,
    pub(crate) fallen_navigation: Arc<Navigation>,
}

fn solid(bounds: &Bounds) -> Solid {
    Solid {
        min_x: bounds.min[0],
        bottom: bounds.min[1],
        min_z: bounds.min[2],
        max_x: bounds.max[0],
        top: bounds.max[1],
        max_z: bounds.max[2],
    }
}

fn centre(solid: &Solid) -> [f32; 3] {
    [
        (solid.min_x + solid.max_x) * 0.5,
        (solid.bottom + solid.top) * 0.5,
        (solid.min_z + solid.max_z) * 0.5,
    ]
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        ids: &HashMap<String, usize>,
        definitions: &[EncounterDefinition],
        presentation: &mut MapPresentation,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        let auditors = |group: &EncounterDefinition| {
            group
                .enemies
                .iter()
                .filter(|e| e.kind == EnemyKind::Auditor)
                .count()
        };
        let optional_ok = match definitions.get(REQUIRED_GROUPS.len()) {
            None => true,
            Some(g) => {
                definitions.len() == REQUIRED_GROUPS.len() + 1
                    && g.id == SERVICE_RING
                    && g.after.as_deref() == Some(REQUIRED_GROUPS[3])
                    && auditors(g) == 0
            }
        };
        if definitions.len() < REQUIRED_GROUPS.len()
            || !optional_ok
            || definitions[..REQUIRED_GROUPS.len()]
                .iter()
                .enumerate()
                .any(|(i, g)| {
                    g.id != REQUIRED_GROUPS[i]
                        || g.after.as_deref() != i.checked_sub(1).map(|p| REQUIRED_GROUPS[p])
                })
            || definitions[2].enemies.len() != 2
            || definitions[2]
                .enemies
                .iter()
                .any(|e| e.kind != EnemyKind::Sweeper)
            || auditors(&definitions[3]) != 1
            || auditors(&definitions[4]) != 1
            || definitions.iter().map(auditors).sum::<usize>() != 2
            || !definitions[3]
                .enemies
                .iter()
                .any(|e| crate::encounters::enemy::repairable(e.kind))
            || !definitions[4]
                .enemies
                .iter()
                .any(|e| crate::encounters::enemy::repairable(e.kind))
        {
            return Err(invalid(
                "M08 requires six ordered groups, at most an optional service ring after the Auditor, a two-Sweeper mine lesson and one repairing Auditor in each of its two Auditor fights",
            ));
        }
        let arrivals = [0, 1, 2, 3, 5, 6].map(|i| M08_OBJECTIVE_IDS[i]);
        if self.objectives.len() != arrivals.len()
            || self
                .objectives
                .iter()
                .zip(arrivals)
                .enumerate()
                .any(|(i, (s, id))| s.id != id || s.requires_encounter != REQUIRED_GROUPS[i])
            || self.bays.id != M08_BAYS_ID
            || self.cabinet.id != M08_CABINET_ID
            || self.bays.requires_encounter != REQUIRED_GROUPS[3]
            || self.cabinet.requires_encounter != REQUIRED_GROUPS[3]
            || self.departure.requires_encounter != REQUIRED_GROUPS[5]
            || self.nodes.len() != M08_NODES
        {
            return Err(invalid("M08 objective or departure binding mismatch"));
        }
        let arrival = |s: Objective, seen: &mut HashSet<String>| -> io::Result<MissionObjective> {
            identity(&s.id, seen)?;
            Ok(MissionObjective {
                id: s.id,
                action: MissionObjectiveAction::Arrival {
                    region: s.arrival,
                    feet: s.approach,
                },
            })
        };
        let mut objectives = Vec::with_capacity(arrivals.len());
        for s in self.objectives {
            objectives.push(arrival(s, seen)?);
        }
        identity(M08_OBJECTIVE_IDS[crate::protocol::M08_MACHINE_STEP], seen)?;
        let bays = arrival(self.bays, seen)?;
        let cabinet = arrival(self.cabinet, seen)?;
        let index = |name: &str| {
            ids.get(name)
                .copied()
                .ok_or_else(|| invalid("M08 references an unknown solid"))
        };
        let seal = index(&self.seal.solid)?;
        let machine = index(&self.machine.solid)?;
        let mut opened = arena.clone();
        opened.solids[seal] = solid(&self.seal.open);
        let mut fallen = opened.clone();
        fallen.solids[machine] = solid(&self.machine.open);
        let mut nodes = Vec::with_capacity(M08_NODES);
        for node in &self.nodes {
            let at = index(&node.solid)?;
            fallen.solids[at] = solid(&node.fallen);
            nodes.push(M08NodeGeometry {
                solid: at,
                approach: node.approach,
                aim: centre(&arena.solids[at]),
            });
        }
        if opened.solids[seal] == arena.solids[seal]
            || fallen.solids[machine] == arena.solids[machine]
            || nodes
                .iter()
                .any(|node| fallen.solids[node.solid] == arena.solids[node.solid])
        {
            return Err(invalid("M08 seal, machine and nodes must move"));
        }
        for world in [&opened, &fallen] {
            crate::movement::validate_geometry(world.half, &world.solids).map_err(invalid)?;
        }
        let host = index(&self.departure.panel.solid)?;
        if host == seal
            || host == machine
            || nodes.iter().any(|n| n.solid == host)
            || self.departure.panel.kind != MapDecorationKind::M08FreightDeparture
        {
            return Err(invalid("M08 departure needs a fixed freight car control"));
        }
        let departure = UseTarget {
            decoration: presentation.decorations.len(),
            approach: self.departure.approach,
        };
        presentation
            .decorations
            .push(self.departure.panel.with_solid(host));
        for world in [arena, &opened, &fallen] {
            crate::protocol::validate_decorations(&presentation.decorations, &world.solids)
                .map_err(invalid)?;
        }
        let geometry = M08MapGeometry {
            objectives,
            nodes,
            machine,
            seal,
            bays,
            cabinet,
            departure,
            boarding: self.departure.boarding,
            companion_start: self.companion_start,
            seal_open: false,
            machine_fallen: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let opened_navigation = Navigation::shared(opened.clone()).map_err(invalid)?;
        let fallen_navigation = Navigation::shared(fallen.clone()).map_err(invalid)?;
        let feet = |s: &MissionObjective| match &s.action {
            MissionObjectiveAction::Arrival { feet, .. } => *feet,
            _ => start,
        };
        // Before the seal lifts: the first four lessons, the bays and Latch.
        let sealed: Vec<[f32; 3]> = geometry.objectives[..4]
            .iter()
            .map(feet)
            .chain([feet(&geometry.bays), geometry.companion_start, start])
            .collect();
        // After it lifts: every placement past the seal, in both later stages.
        let later: Vec<[f32; 3]> = geometry
            .objectives
            .iter()
            .map(feet)
            .chain([feet(&geometry.cabinet), geometry.departure.approach])
            .chain(geometry.nodes.iter().map(|n| n.approach))
            .collect();
        for (world, nav, points) in [
            (arena, &navigation, &sealed),
            (&opened, &opened_navigation, &later),
            (&fallen, &fallen_navigation, &later),
        ] {
            for point in points {
                if !standing(world, *point)
                    || nav.route(start, *point, SEARCH_LIMIT).status != RouteStatus::Complete
                {
                    return Err(invalid(&format!(
                        "M08 feet {point:?} unsupported or unreachable in its stage"
                    )));
                }
            }
        }
        // The cabinet and the bridge lie past the seal; it must really gate them.
        if navigation
            .route(start, feet(&geometry.cabinet), SEARCH_LIMIT)
            .status
            == RouteStatus::Complete
        {
            return Err(invalid("M08 seal must gate the service ring"));
        }
        for world in [&opened, &fallen] {
            let control = geometry
                .departure
                .point(presentation, &world.solids)
                .ok_or_else(|| invalid("M08 departure control missing"))?;
            let approach = geometry.departure.approach;
            let eye = [approach[0], approach[1] + EYE_HEIGHT, approach[2]];
            let distance = (0..3)
                .map(|i| (eye[i] - control[i]).powi(2))
                .sum::<f32>()
                .sqrt();
            if distance > USE_DISTANCE || !crate::combat::line_of_sight(eye, control, &world.solids)
            {
                return Err(invalid("M08 departure approach cannot use the car control"));
            }
        }
        // Each node approach sees its own node first, with no cover in front.
        for node in &geometry.nodes {
            let eye = [
                node.approach[0],
                node.approach[1] + EYE_HEIGHT,
                node.approach[2],
            ];
            let (yaw, pitch) = crate::combat::aim_at(eye, node.aim)
                .ok_or_else(|| invalid("M08 node aim is degenerate"))?;
            let ray = crate::combat::Ray::dispersed(eye, yaw, pitch, 0.0, [0.0, 0.0]);
            let hit = ray
                .solid(&opened.solids[node.solid], 1000.0)
                .ok_or_else(|| invalid("M08 node approach misses its node"))?;
            if opened.solids.iter().enumerate().any(|(i, s)| {
                i != node.solid
                    && ray
                        .solid(s, hit.distance)
                        .is_some_and(|h| h.distance <= hit.distance)
            }) {
                return Err(invalid("M08 node approach is occluded"));
            }
        }
        Ok(Prepared {
            geometry,
            encounters: [0, 1, 2, 3, 4, 5],
            seal_encounter: 3,
            bridge_encounter: 4,
            departure_encounter: 5,
            opened,
            fallen,
            navigation,
            opened_navigation,
            fallen_navigation,
        })
    }
}
