//! One optional shutter, with exactly two worlds built before readiness.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    M04ClinicGeometry, M04MapGeometry, M04PatientGeometry, MapDecoration, MapDecorationKind,
    MapPresentation, MissionObjective, MissionObjectiveAction, Region3, UseTarget,
    M04_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    clinic: Clinic,
    patients: Vec<M04PatientGeometry>,
    objectives: Vec<Objective>,
    departure: Departure,
    companion_start: [f32; 3],
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Clinic {
    panel: MapDecoration<String>,
    approach: [f32; 3],
    gate: Gate,
    requires_encounter: String,
    release: Region3,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Gate {
    solid: String,
    lift: f32,
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
struct Departure {
    panel: MapDecoration<String>,
    approach: [f32; 3],
    boarding: Region3,
    requires_encounter: String,
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M04MapGeometry,
    pub(crate) encounters: Vec<usize>,
    pub(crate) clinic_encounter: usize,
    pub(crate) departure_encounter: usize,
    pub(crate) opened: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) initial_navigation: Arc<Navigation>,
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
        let encounter = |id: &str| {
            definitions
                .iter()
                .position(|e| e.id == id)
                .ok_or_else(|| invalid("M04 references an unknown encounter"))
        };
        if definitions.len() != 6
            || definitions.iter().enumerate().any(|(index, group)| {
                group.after.as_deref()
                    != index
                        .checked_sub(1)
                        .map(|previous| definitions[previous].id.as_str())
                    || group
                        .enemies
                        .iter()
                        .filter(|e| e.kind == crate::protocol::EnemyKind::Notary)
                        .count()
                        > 2
            })
            || definitions[1].enemies.len() != 1
            || definitions[1].enemies[0].kind != crate::protocol::EnemyKind::Notary
            || definitions[0]
                .enemies
                .iter()
                .any(|e| e.kind == crate::protocol::EnemyKind::Notary)
        {
            return Err(invalid("M04 requires six chained fights, a lone Notary lesson and at most two drones per group"));
        }
        let gate = *ids
            .get(&self.clinic.gate.solid)
            .ok_or_else(|| invalid("M04 clinic shutter missing"))?;
        if !self.clinic.gate.lift.is_finite() || !(0.125..=8.0).contains(&self.clinic.gate.lift) {
            return Err(invalid("M04 shutter lift out of bounds"));
        }
        let mut opened = arena.clone();
        opened.solids[gate].bottom += self.clinic.gate.lift;
        opened.solids[gate].top += self.clinic.gate.lift;
        crate::movement::validate_geometry(opened.half, &opened.solids).map_err(invalid)?;
        for enemy in definitions.iter().flat_map(|group| &group.enemies) {
            if let Some(hover) = &enemy.hover {
                hover.validate_for(&opened, enemy.feet, enemy.kind)?;
            } else if !standing(&opened, enemy.feet) {
                return Err(invalid(
                    "M04 enemy must remain supported and clear after clinic opening",
                ));
            }
        }
        let clinic_encounter = encounter(&self.clinic.requires_encounter)?;
        if clinic_encounter != 2 {
            return Err(invalid(
                "M04 clinic must require the mixed street encounter",
            ));
        }
        let departure_encounter = encounter(&self.departure.requires_encounter)?;
        let mut targets = Vec::new();
        for (panel, approach, clinic) in [
            (self.clinic.panel, self.clinic.approach, true),
            (self.departure.panel, self.departure.approach, false),
        ] {
            let host = *ids
                .get(&panel.solid)
                .ok_or_else(|| invalid("M04 panel host missing"))?;
            if host == gate
                || !matches!(
                    panel.kind,
                    MapDecorationKind::LiftControl
                        | MapDecorationKind::Terminal
                        | MapDecorationKind::M04ClinicControl
                        | MapDecorationKind::M04RoofDeparture
                )
                || !clinic
                    && !matches!(
                        panel.kind,
                        MapDecorationKind::LiftControl | MapDecorationKind::M04RoofDeparture
                    )
                || clinic && panel.kind == MapDecorationKind::M04RoofDeparture
            {
                return Err(invalid("M04 controls require registered fixed hosts"));
            }
            targets.push(UseTarget {
                decoration: presentation.decorations.len(),
                approach,
            });
            presentation.decorations.push(panel.with_solid(host));
        }
        let mut encounters = Vec::new();
        let mut objectives = Vec::new();
        if self.objectives.len() != 6 {
            return Err(invalid("M04 needs six ordered objectives"));
        }
        for (objective, expected) in self.objectives.into_iter().zip(M04_OBJECTIVE_IDS) {
            identity(&objective.id, seen)?;
            let group = encounter(&objective.requires_encounter)?;
            if objective.id != expected
                || encounters.contains(&group)
                || encounters
                    .last()
                    .is_some_and(|previous: &usize| *previous >= group)
            {
                return Err(invalid("M04 objective encounter order invalid"));
            }
            encounters.push(group);
            objectives.push(MissionObjective {
                id: objective.id,
                action: MissionObjectiveAction::Arrival {
                    region: objective.arrival,
                    feet: objective.approach,
                },
            });
        }
        if encounters.last() != Some(&departure_encounter) {
            return Err(invalid("M04 departure must require court encounter"));
        }
        for patient in &self.patients {
            identity(&patient.id, seen)?;
        }
        let geometry = M04MapGeometry {
            clinic_open: false,
            clinic: M04ClinicGeometry {
                control: targets.remove(0),
                release: self.clinic.release,
            },
            patients: self.patients,
            objectives,
            departure: targets.remove(0),
            boarding: self.departure.boarding,
            companion_start: self.companion_start,
        };
        let initial_navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let navigation = Navigation::shared(opened.clone()).map_err(invalid)?;
        for (world, nav) in [(arena, &initial_navigation), (&opened, &navigation)] {
            geometry
                .validate(world.half, &world.solids, Some(presentation))
                .map_err(invalid)?;
            crate::protocol::validate_decorations(&presentation.decorations, &world.solids)
                .map_err(invalid)?;
            for feet in [
                start,
                geometry.clinic.control.approach,
                geometry.departure.approach,
                geometry.companion_start,
            ]
            .into_iter()
            .chain(geometry.objectives.iter().filter_map(|o| match o.action {
                MissionObjectiveAction::Arrival { feet, .. } => Some(feet),
                _ => None,
            })) {
                if !standing(world, feet)
                    || nav.route(start, feet, SEARCH_LIMIT).status != RouteStatus::Complete
                {
                    return Err(invalid(
                        "M04 exterior route must work in both clinic states",
                    ));
                }
            }
            for target in [&geometry.clinic.control, &geometry.departure] {
                let target_point = target
                    .point(presentation, &world.solids)
                    .ok_or_else(|| invalid("M04 control unavailable"))?;
                let eye = [
                    target.approach[0],
                    target.approach[1] + EYE_HEIGHT,
                    target.approach[2],
                ];
                if (0..3)
                    .map(|i| (eye[i] - target_point[i]).powi(2))
                    .sum::<f32>()
                    .sqrt()
                    > USE_DISTANCE
                    || !crate::combat::line_of_sight(eye, target_point, &world.solids)
                {
                    return Err(invalid("M04 control approach cannot reach visible switch"));
                }
            }
        }
        for patient in &geometry.patients {
            if !geometry.clinic.release.contains(patient.held) {
                return Err(invalid("M04 clinic release must cover held patients"));
            }
            for feet in &patient.route {
                if !standing(&opened, *feet)
                    || navigation.route(start, *feet, SEARCH_LIMIT).status != RouteStatus::Complete
                {
                    return Err(invalid(
                        "M04 patient route must be supported and reachable after opening",
                    ));
                }
            }
            if patient
                .route
                .windows(2)
                .any(|p| !navigation.walkable(p[0], p[1]))
            {
                return Err(invalid("M04 patient route segment blocked"));
            }
        }
        Ok(Prepared {
            geometry,
            encounters,
            clinic_encounter,
            departure_encounter,
            opened,
            navigation,
            initial_navigation,
        })
    }
}
