//! Tender targets and fixed patrol geometry prepared before readiness.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT, RADIUS};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M11MapGeometry, MapDecoration, MapDecorationKind, MapPresentation, MissionObjective,
    MissionObjectiveAction, Region3, UseTarget, M11_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 4] = [
    "spine_patrol",
    "crew_holds",
    "records_redactor",
    "counter_boarders",
];
pub(crate) const OBJECTIVE_GROUPS: [Option<usize>; 6] =
    [None, Some(0), Some(1), Some(2), Some(3), Some(3)];

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SpinePatrol {
    pub(crate) from: [f32; 3],
    pub(crate) to: [f32; 3],
    pub(crate) cycle_ticks: u32,
    pub(crate) spacing: f32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    transfer_release: PanelTarget,
    records_document: PanelTarget,
    departure: PanelTarget,
    boarding: Region3,
    companion_start: [f32; 3],
    transfer_people: Vec<[f32; 3]>,
    spine_patrol: SpinePatrol,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Objective {
    id: String,
    arrival: Region3,
    approach: [f32; 3],
    #[serde(default)]
    requires_encounter: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PanelTarget {
    panel: MapDecoration<String>,
    approach: [f32; 3],
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M11MapGeometry,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) spine_patrol: SpinePatrol,
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
        let roles: [&[EnemyKind]; 4] = [
            &[EnemyKind::Clerk, EnemyKind::Clerk, EnemyKind::Clerk],
            &[EnemyKind::Sweeper, EnemyKind::Sweeper, EnemyKind::Turret],
            &[EnemyKind::Redactor],
            &[
                EnemyKind::Clerk,
                EnemyKind::Clerk,
                EnemyKind::Clerk,
                EnemyKind::Sweeper,
                EnemyKind::Sweeper,
                EnemyKind::Enforcer,
            ],
        ];
        if definitions.len() != GROUPS.len()
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != GROUPS[i]
                    || g.after.as_deref() != i.checked_sub(1).map(|prior| GROUPS[prior])
                    || g.enemies.len() != roles[i].len()
                    || roles[i].iter().any(|kind| {
                        g.enemies.iter().filter(|e| e.kind == *kind).count()
                            != roles[i].iter().filter(|k| **k == *kind).count()
                    })
            })
            || self.objectives.len() != M11_OBJECTIVE_IDS.len()
        {
            return Err(invalid(
                "M11 requires its four exact ordered tender encounters",
            ));
        }
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let reachable = |feet| {
            standing(arena, feet)
                && navigation.route(start, feet, SEARCH_LIMIT).status == RouteStatus::Complete
        };
        let mut objectives = Vec::new();
        for (index, objective) in self.objectives.into_iter().enumerate() {
            identity(&objective.id, seen)?;
            if objective.id != M11_OBJECTIVE_IDS[index]
                || objective.requires_encounter.as_deref()
                    != OBJECTIVE_GROUPS[index].map(|g| GROUPS[g])
                || !objective.arrival.valid(arena.half)
                || !objective.arrival.contains(objective.approach)
                || !reachable(objective.approach)
            {
                return Err(invalid(
                    "M11 arrival must bind its ordered group and supported reachable approach",
                ));
            }
            objectives.push(MissionObjective {
                id: objective.id,
                action: MissionObjectiveAction::Arrival {
                    region: objective.arrival,
                    feet: objective.approach,
                },
            });
        }
        if !reachable(self.companion_start)
            || self.transfer_people.len() != 3
            || self.transfer_people.iter().any(|feet| !reachable(*feet))
        {
            return Err(invalid(
                "M11 companion and transfer people require ordinary supported routes",
            ));
        }
        let panel = |definition: PanelTarget,
                     expected: MapDecorationKind,
                     presentation: &mut MapPresentation|
         -> io::Result<UseTarget> {
            if definition.panel.kind != expected || !reachable(definition.approach) {
                return Err(invalid(
                    "M11 interaction must use its registered kind and supported approach",
                ));
            }
            let host = *ids
                .get(&definition.panel.solid)
                .ok_or_else(|| invalid("M11 interaction host missing"))?;
            let target = UseTarget {
                decoration: presentation.decorations.len(),
                approach: definition.approach,
            };
            presentation
                .decorations
                .push(definition.panel.with_solid(host));
            let point = target
                .point(presentation, &arena.solids)
                .ok_or_else(|| invalid("M11 panel placement invalid"))?;
            let eye = [
                target.approach[0],
                target.approach[1] + EYE_HEIGHT,
                target.approach[2],
            ];
            if (0..3)
                .map(|i| (point[i] - eye[i]).powi(2))
                .sum::<f32>()
                .sqrt()
                > USE_DISTANCE
                || !crate::combat::line_of_sight(eye, point, &arena.solids)
            {
                return Err(invalid(
                    "M11 interaction requires a real use-distance and unobstructed lane",
                ));
            }
            Ok(target)
        };
        let geometry = M11MapGeometry {
            objectives,
            transfer_release: panel(
                self.transfer_release,
                MapDecorationKind::M11TransferRelease,
                presentation,
            )?,
            records_document: panel(
                self.records_document,
                MapDecorationKind::M11RecordsDocument,
                presentation,
            )?,
            departure: panel(
                self.departure,
                MapDecorationKind::M11SternRelease,
                presentation,
            )?,
            boarding: self.boarding,
            companion_start: self.companion_start,
            transfer_people: self.transfer_people,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let patrol = self.spine_patrol;
        let walking_step = crate::movement::TOP_SPEED
            * crate::encounters::enemy::gait(EnemyKind::Clerk)
            * crate::movement::DT_LIVE;
        if !(240..=800).contains(&patrol.cycle_ticks)
            || !patrol.spacing.is_finite()
            || !(RADIUS * 2.0 + 0.1..=2.0).contains(&patrol.spacing)
            || (patrol.from[0] - patrol.to[0]).abs() > 0.001
            || (patrol.from[1] - patrol.to[1]).abs() > 0.001
            || patrol.to[2] - patrol.from[2] < 6.0
            || patrol.to[2] - patrol.from[2] > 16.0
            || (patrol.to[2] - patrol.from[2]) / (patrol.cycle_ticks as f32 * 0.5) > walking_step
        {
            return Err(invalid(
                "M11 spine patrol requires a bounded northbound file and cadence",
            ));
        }
        for index in 0..3 {
            let mut from = patrol.from;
            let mut to = patrol.to;
            from[2] -= index as f32 * patrol.spacing;
            to[2] -= index as f32 * patrol.spacing;
            if definitions[0].enemies[index].feet != from
                || !reachable(from)
                || !reachable(to)
                || !navigation.walkable(from, to)
                || !navigation.walkable(to, from)
            {
                return Err(invalid(
                    "M11 patrol members must start in their supported file slots",
                ));
            }
            for sample in 0..=64 {
                let position = [
                    from[0],
                    from[1],
                    from[2] + (to[2] - from[2]) * sample as f32 / 64.0,
                ];
                if !standing(arena, position) {
                    return Err(invalid(
                        "M11 spine patrol crosses unsupported or blocked body space",
                    ));
                }
            }
        }
        Ok(Prepared {
            geometry,
            navigation,
            spine_patrol: patrol,
        })
    }
}
