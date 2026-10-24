//! Local Exception: validate the waterworks, the quay, the pressure schedule
//! and both prepared worlds (gate shut, gate open) before readiness.
use super::{encounters::EncounterDefinition, identity, invalid, standing};
use crate::movement::{Arena, Solid, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    ControlDomain, EnemyKind, M20MapGeometry, MapPresentation, MissionObjective,
    MissionObjectiveAction, Region3, UseTarget, M20_CREW, M20_OBJECTIVE_IDS, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

/// The two ordered lessons before the quay. The Surveyor teaches alone; the
/// one machine that follows it joins only after its lesson window. Every
/// later group is pressure.
pub(crate) const SLUICE_GROUP: usize = 0;
pub(crate) const CROSSING_GROUP: usize = 1;
pub(crate) const FOLLOW_GROUP: usize = 2;
pub(crate) const FIRST_PRESSURE_GROUP: usize = 3;
const MAX_FOLLOW: usize = 2;
/// No pressure group can exceed the smallest population cap.
pub(crate) const MAX_PRESSURE_GROUP: usize = 4;
/// The last group is the work front that walks past the refuge after the
/// reprieve. It never fights and is never pressure.
const PASSING_ID: &str = "passing_work";
const MAX_PASSING: usize = 8;

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum ObjectiveDefinition {
    Arrival {
        id: String,
        arrival: Region3,
        approach: [f32; 3],
    },
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CrewDefinition {
    start: [f32; 3],
    route: Vec<[f32; 3]>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CrateDefinition {
    supplies: Vec<String>,
    release: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PressureDefinition {
    group: String,
    at: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<ObjectiveDefinition>,
    departure: UseTarget,
    boarding: Region3,
    refuge_line: Region3,
    harbour_display: usize,
    refuge_gate: String,
    breath_ticks: u64,
    turn_ticks: u64,
    hold_ticks: u64,
    crew: Vec<CrewDefinition>,
    latch_route: Vec<[f32; 3]>,
    refuge_marks: Vec<[f32; 3]>,
    reprieve_exits: Vec<[f32; 3]>,
    passing_exit: [f32; 3],
    crates: Vec<CrateDefinition>,
    pressure: Vec<PressureDefinition>,
}

/// One crew member's authored crossing, walked on fixed straight segments.
#[derive(Debug, Clone)]
pub(crate) struct CrewRoute {
    pub(crate) start: [f32; 3],
    pub(crate) route: Vec<[f32; 3]>,
}

/// Hidden pressure budget: a group becomes eligible `at` hold ticks.
#[derive(Debug, Clone, Copy)]
pub(crate) struct PressureSlot {
    pub(crate) group: usize,
    pub(crate) at: u64,
}

#[derive(Debug, Clone)]
pub(crate) struct ResupplyCrate {
    pub(crate) supplies: Vec<String>,
    pub(crate) release: u64,
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M20MapGeometry,
    pub(crate) gate: usize,
    pub(crate) crew: Vec<CrewRoute>,
    pub(crate) latch_route: Vec<[f32; 3]>,
    pub(crate) refuge_marks: Vec<[f32; 3]>,
    pub(crate) reprieve_exits: Vec<[f32; 3]>,
    pub(crate) crates: Vec<ResupplyCrate>,
    pub(crate) pressure: Vec<PressureSlot>,
    /// The work front after the reprieve: its group and the far exit it
    /// walks to, past the refuge line and on to the next district.
    pub(crate) passing: (usize, [f32; 3]),
    pub(crate) presentation: MapPresentation,
    pub(crate) initial: Arena,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) opened: Arena,
    pub(crate) opened_navigation: Arc<Navigation>,
}

fn walkable(arena: &Arena, points: &[[f32; 3]]) -> bool {
    points
        .windows(2)
        .all(|pair| crate::mission::m09_route_segment_valid(arena, pair[0], pair[1]))
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
        if self.objectives.len() != M20_OBJECTIVE_IDS.len() {
            return Err(invalid("M20 requires five ordered objectives"));
        }
        let mut objectives = Vec::with_capacity(M20_OBJECTIVE_IDS.len());
        for (
            index,
            ObjectiveDefinition::Arrival {
                id,
                arrival,
                approach,
            },
        ) in self.objectives.into_iter().enumerate()
        {
            if id != M20_OBJECTIVE_IDS[index] {
                return Err(invalid("M20 objective id mismatch"));
            }
            identity(&id, seen)?;
            objectives.push(MissionObjective {
                id,
                action: MissionObjectiveAction::Arrival {
                    region: arrival,
                    feet: approach,
                },
            });
        }
        let gate = *ids
            .get(&self.refuge_gate)
            .ok_or_else(|| invalid("M20 refuge gate solid missing"))?;
        let geometry = M20MapGeometry {
            objectives,
            departure: self.departure,
            boarding: self.boarding,
            refuge_line: self.refuge_line,
            harbour_display: self.harbour_display,
            breath_ticks: self.breath_ticks,
            turn_ticks: self.turn_ticks,
            hold_ticks: self.hold_ticks,
            gate_open: false,
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let point = geometry
            .departure
            .point(presentation, &arena.solids)
            .ok_or_else(|| invalid("M20 crossing control missing"))?;
        let eye = [
            geometry.departure.approach[0],
            geometry.departure.approach[1] + EYE_HEIGHT,
            geometry.departure.approach[2],
        ];
        if (0..3)
            .map(|a| (point[a] - eye[a]).powi(2))
            .sum::<f32>()
            .sqrt()
            > USE_DISTANCE + 0.6
            || !standing(arena, geometry.departure.approach)
        {
            return Err(invalid("M20 crossing control approach out of reach"));
        }

        // Exact encounter structure: a lone Surveyor lesson, one crossing, the
        // machine that follows the lesson, then every later group scheduled
        // once as bounded pressure.
        let surveyors = |g: &EncounterDefinition| {
            g.enemies
                .iter()
                .filter(|e| e.kind == EnemyKind::Surveyor)
                .count()
        };
        let walking = |g: &EncounterDefinition| {
            g.enemies
                .iter()
                .all(|e| e.hover.is_none() && crate::encounters::enemy::gait(e.kind) > 0.0)
        };
        let passing = definitions.len().saturating_sub(1);
        if definitions.len() < FIRST_PRESSURE_GROUP + 2
            || definitions[SLUICE_GROUP].id != "sluice_watch"
            || surveyors(&definitions[SLUICE_GROUP]) != 1
            || definitions[SLUICE_GROUP].enemies.len() != 1
            || definitions[CROSSING_GROUP].id != "crossing"
            || definitions[CROSSING_GROUP].after.as_deref() != Some("sluice_watch")
            || surveyors(&definitions[CROSSING_GROUP]) != 0
            || definitions[FOLLOW_GROUP].id != "sluice_follow"
            || definitions[FOLLOW_GROUP].after.is_some()
            || !(1..=MAX_FOLLOW).contains(&definitions[FOLLOW_GROUP].enemies.len())
            || !walking(&definitions[FOLLOW_GROUP])
            || definitions[FIRST_PRESSURE_GROUP..passing].iter().any(|g| {
                g.after.is_some() || g.enemies.len() > MAX_PRESSURE_GROUP || surveyors(g) > 1
            })
        {
            return Err(invalid(
                "M20 requires the lone Surveyor lesson, the crossing, its follower and bounded pressure groups",
            ));
        }
        // After the wipe nothing hostile at the waterworks answers to the
        // Union: every bot is absorbed and every Surveyor and Paver is a
        // restoration machine.
        if definitions
            .iter()
            .flat_map(|group| &group.enemies)
            .any(|enemy| enemy.control == ControlDomain::Union)
        {
            return Err(invalid(
                "M20 hostiles are absorbed bots and restoration machines, never the Union's",
            ));
        }
        let front = &definitions[passing];
        if front.id != PASSING_ID
            || front.after.is_some()
            || front.enemies.is_empty()
            || front.enemies.len() > MAX_PASSING
            || front
                .enemies
                .iter()
                .any(|e| crate::encounters::enemy::gait(e.kind) <= 0.0)
            || !standing(arena, self.passing_exit)
            || geometry.refuge_line.contains(self.passing_exit)
        {
            return Err(invalid(
                "M20 ends with a walking work front and an exit away from the line",
            ));
        }
        if self.pressure.len() != definitions.len() - FIRST_PRESSURE_GROUP - 1 {
            return Err(invalid("M20 schedules every pressure group exactly once"));
        }
        let mut pressure = Vec::with_capacity(self.pressure.len());
        let mut previous = 0;
        for (slot, entry) in self.pressure.iter().enumerate() {
            let group = slot + FIRST_PRESSURE_GROUP;
            if definitions[group].id != entry.group
                || entry.at < previous
                || entry.at >= self.hold_ticks
            {
                return Err(invalid(
                    "M20 pressure must follow encounter order inside the hold",
                ));
            }
            previous = entry.at;
            pressure.push(PressureSlot {
                group,
                at: entry.at,
            });
        }

        if self.crew.len() != M20_CREW {
            return Err(invalid("M20 requires three waterworks crew"));
        }
        let mut crew = Vec::with_capacity(M20_CREW);
        for member in self.crew {
            let mut path = vec![member.start];
            path.extend(member.route.iter().copied());
            if member.route.is_empty()
                || member.route.len() > 12
                || !standing(arena, member.start)
                || !walkable(arena, &path)
                || !geometry
                    .refuge_line
                    .contains(*member.route.last().expect("non-empty route"))
            {
                return Err(invalid(
                    "M20 crew route must walk from the pump hall to the refuge line",
                ));
            }
            crew.push(CrewRoute {
                start: member.start,
                route: member.route,
            });
        }
        if !(2..=12).contains(&self.latch_route.len())
            || !standing(arena, self.latch_route[0])
            || !walkable(arena, &self.latch_route)
            || !geometry
                .refuge_line
                .contains(*self.latch_route.last().expect("non-empty route"))
        {
            return Err(invalid("M20 Latch route must walk to the refuge gate"));
        }
        if !(1..=8).contains(&self.refuge_marks.len())
            || self
                .refuge_marks
                .iter()
                .any(|p| !geometry.refuge_line.contains(*p) || !standing(arena, *p))
        {
            return Err(invalid("M20 refuge marks must stand on the barricade line"));
        }
        if !(1..=4).contains(&self.reprieve_exits.len())
            || self
                .reprieve_exits
                .iter()
                .any(|p| !standing(arena, *p) || geometry.refuge_line.contains(*p))
        {
            return Err(invalid("M20 reprieve exits must lead away from the line"));
        }
        let mut crated = HashSet::new();
        if self.crates.is_empty() || self.crates.len() > 8 {
            return Err(invalid("M20 requires a bounded set of resupply crates"));
        }
        for c in &self.crates {
            if c.supplies.is_empty()
                || c.supplies.len() > 2
                || c.release >= self.hold_ticks
                || c.supplies.iter().any(|id| !crated.insert(id.clone()))
            {
                return Err(invalid(
                    "M20 crates hold one or two registered supplies released inside the hold",
                ));
            }
        }
        let crates = self
            .crates
            .into_iter()
            .map(|c| ResupplyCrate {
                supplies: c.supplies,
                release: c.release,
            })
            .collect();

        let navigation = Navigation::shared(arena.clone()).map_err(invalid)?;
        let route = |nav: &Navigation, from: [f32; 3], to: [f32; 3]| {
            nav.route(from, to, SEARCH_LIMIT).status == RouteStatus::Complete
        };
        for objective in &geometry.objectives {
            let MissionObjectiveAction::Arrival { feet, .. } = objective.action else {
                unreachable!("validated arrivals");
            };
            if !standing(arena, feet) || !route(&navigation, start, feet) {
                return Err(invalid("M20 objective feet unreachable from the sluice"));
            }
        }
        for mark in self.refuge_marks.iter().chain(&self.reprieve_exits) {
            if !route(&navigation, start, *mark) {
                return Err(invalid("M20 barricade or exit unreachable"));
            }
        }
        if front
            .enemies
            .iter()
            .any(|e| !route(&navigation, e.feet, self.passing_exit))
        {
            return Err(invalid("M20 work front cannot walk to its exit"));
        }

        let mut opened = arena.clone();
        let shut = arena.solids[gate];
        opened.solids[gate] = Solid {
            top: shut.bottom + 0.05,
            ..shut
        };
        let opened_navigation = Navigation::shared(opened.clone()).map_err(invalid)?;
        if !route(
            &opened_navigation,
            self.latch_route[self.latch_route.len() - 1],
            geometry.departure.approach,
        ) {
            return Err(invalid("M20 open gate must lead to the crossing control"));
        }
        if route(&navigation, start, geometry.departure.approach) {
            return Err(invalid("M20 gate must be the one door to the crossing"));
        }

        Ok(Prepared {
            geometry,
            gate,
            crew,
            latch_route: self.latch_route,
            refuge_marks: self.refuge_marks,
            reprieve_exits: self.reprieve_exits,
            crates,
            pressure,
            passing: (passing, self.passing_exit),
            presentation: presentation.clone(),
            initial: arena.clone(),
            navigation,
            opened,
            opened_navigation,
        })
    }
}
