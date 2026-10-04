//! One static curfew town and crater cut: ordered fights, the window lesson
//! and the depot freight departure.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M07MapGeometry, MapDecoration, MapPresentation, MissionObjective,
    MissionObjectiveAction, Region3, UseTarget, M07_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const REQUIRED_GROUPS: [&str; 5] = [
    "curfew_patrol",
    "vault_plaza",
    "curfew_post",
    "rim_lesson",
    "crater_cut",
];
/// Index of the lone marksman lesson. The companion leaves it to the player.
pub(crate) const LESSON_GROUP: usize = 3;
/// Five rim marksmen hold the cut; the brief's climax is not negotiable.
const RIM_MARKSMEN: usize = 5;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
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
struct Departure {
    panel: MapDecoration<String>,
    approach: [f32; 3],
    boarding: Region3,
    requires_encounter: String,
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M07MapGeometry,
    pub(crate) encounters: [usize; 5],
    pub(crate) lesson_encounter: usize,
    pub(crate) departure_encounter: usize,
    pub(crate) navigation: Arc<Navigation>,
}

fn count(group: &EncounterDefinition, kind: EnemyKind) -> usize {
    group.enemies.iter().filter(|e| e.kind == kind).count()
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
        let marksmen: usize = definitions
            .iter()
            .map(|g| count(g, EnemyKind::RangedSweeper))
            .sum();
        if definitions.len() != REQUIRED_GROUPS.len()
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != REQUIRED_GROUPS[i]
                    || g.after.as_deref() != i.checked_sub(1).map(|p| REQUIRED_GROUPS[p])
            })
            || count(&definitions[1], EnemyKind::Notary) != 2
            || count(&definitions[2], EnemyKind::Turret) != 1
            || definitions[LESSON_GROUP].enemies.len() != 1
            || count(&definitions[LESSON_GROUP], EnemyKind::RangedSweeper) != 1
            || count(&definitions[4], EnemyKind::RangedSweeper) != RIM_MARKSMEN
            || count(&definitions[4], EnemyKind::Sweeper) == 0
            || marksmen != RIM_MARKSMEN + 1
        {
            return Err(invalid(
                "M07 requires five ordered groups, an isolated marksman lesson and the rim duel",
            ));
        }
        if self.objectives.len() != M07_OBJECTIVE_IDS.len()
            || self.departure.requires_encounter != REQUIRED_GROUPS[4]
        {
            return Err(invalid("M07 objective or departure binding mismatch"));
        }
        let mut objectives = Vec::with_capacity(M07_OBJECTIVE_IDS.len());
        for (i, s) in self.objectives.into_iter().enumerate() {
            identity(&s.id, seen)?;
            if s.id != M07_OBJECTIVE_IDS[i] || s.requires_encounter != REQUIRED_GROUPS[i] {
                return Err(invalid("M07 objective chain mismatch"));
            }
            objectives.push(MissionObjective {
                id: s.id,
                action: MissionObjectiveAction::Arrival {
                    region: s.arrival,
                    feet: s.approach,
                },
            });
        }
        let host = *ids
            .get(&self.departure.panel.solid)
            .ok_or_else(|| invalid("M07 departure host missing"))?;
        let decoration = presentation.decorations.len();
        presentation
            .decorations
            .push(self.departure.panel.with_solid(host));
        let geometry = M07MapGeometry {
            objectives,
            departure: UseTarget {
                decoration,
                approach: self.departure.approach,
            },
            boarding: self.departure.boarding,
            companion_start: self.companion_start,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        for feet in geometry
            .objectives
            .iter()
            .filter_map(|s| {
                if let MissionObjectiveAction::Arrival { feet, .. } = &s.action {
                    Some(*feet)
                } else {
                    None
                }
            })
            .chain([geometry.departure.approach, geometry.companion_start])
        {
            if !standing(arena, feet)
                || navigation.route(start, feet, SEARCH_LIMIT).status != RouteStatus::Complete
            {
                return Err(invalid(&format!(
                    "M07 objective or companion feet {feet:?} unsupported or unreachable"
                )));
            }
        }
        let target = geometry
            .departure
            .point(presentation, &arena.solids)
            .ok_or_else(|| invalid("M07 departure control missing"))?;
        let approach = geometry.departure.approach;
        let eye = [approach[0], approach[1] + EYE_HEIGHT, approach[2]];
        let distance = (0..3)
            .map(|i| (eye[i] - target[i]).powi(2))
            .sum::<f32>()
            .sqrt();
        if distance <= 0.0
            || distance > USE_DISTANCE
            || !crate::combat::line_of_sight(eye, target, &arena.solids)
        {
            return Err(invalid(
                "M07 departure approach must see the reachable control",
            ));
        }
        Ok(Prepared {
            geometry,
            encounters: [0, 1, 2, 3, 4],
            lesson_encounter: LESSON_GROUP,
            departure_encounter: 4,
            navigation,
        })
    }
}
