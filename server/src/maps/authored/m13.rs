//! Foundry gate authoring. The key is optional. A map without it is unchanged.
use super::{encounters::EncounterDefinition, invalid, standing};
use crate::mission::m13::{
    deck_at, hazard_overlap, step_blocked, workers_distance, Cycle, Gates, LiftBody,
};
use crate::movement::{Solid, BODY_HEIGHT};
use crate::protocol::{MapDecoration, MapDecorationKind, Region3, UseTarget, USE_DISTANCE};
use serde::Deserialize;
use std::collections::HashMap;
use std::io;

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) gates: Gates,
    pub(crate) geometry: Option<crate::protocol::M13MapGeometry>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    relay: String,
    protected: Vec<String>,
    hazard: Region3,
    bypass: Region3,
    cycle: CycleDef,
    release: PanelTarget,
    quarters_encounter: String,
    deck: String,
    inset: Inset,
    lift_top: f32,
    #[serde(default)]
    connected: Option<Connected>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Connected {
    arrivals: [Arrival; 5],
    relay_approach: [f32; 3],
    relay_aim: [f32; 3],
    departure: PanelTarget,
    workers: [[f32; 3]; 3],
    worker_destinations: [[f32; 3]; 3],
    overseer: [f32; 3],
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Arrival {
    region: Region3,
    feet: [f32; 3],
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CycleDef {
    period: u32,
    warning: u32,
    active: u32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PanelTarget {
    panel: MapDecoration<String>,
    approach: [f32; 3],
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Inset {
    min: [f32; 2],
    max: [f32; 2],
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &crate::movement::Arena,
        ids: &HashMap<String, usize>,
        encounters: &[EncounterDefinition],
        presentation: &crate::protocol::MapPresentation,
    ) -> io::Result<Prepared> {
        let relay = *ids
            .get(&self.relay)
            .ok_or_else(|| invalid("foundry relay is missing"))?;
        if self.protected.is_empty()
            || self
                .protected
                .iter()
                .any(|id| ids.get(id).is_none_or(|index| *index == relay))
        {
            return Err(invalid("foundry utility shares the relay"));
        }
        let protected: Vec<usize> = self.protected.iter().map(|id| ids[id.as_str()]).collect();
        let deck_index = *ids
            .get(&self.deck)
            .ok_or_else(|| invalid("foundry deck is missing"))?;
        let deck = arena.solids[deck_index];
        let cycle = Cycle {
            period: self.cycle.period,
            warning: self.cycle.warning,
            active: self.cycle.active,
        };
        cycle.validate().map_err(invalid)?;
        if !self.hazard.valid(arena.half)
            || !self.bypass.valid(arena.half)
            || hazard_overlap(&self.hazard, &self.bypass)
        {
            return Err(invalid("foundry hazard overlaps its bypass"));
        }
        let quarters_group = encounters
            .iter()
            .position(|encounter| encounter.id == self.quarters_encounter)
            .ok_or_else(|| invalid("foundry quarters encounter is missing"))?;
        let panel_solid = *ids
            .get(&self.release.panel.solid)
            .ok_or_else(|| invalid("foundry release panel is not on the map"))?;
        let (decoration, panel) = presentation
            .decorations
            .iter()
            .enumerate()
            .find(|(_, decoration)| {
                decoration.solid == panel_solid
                    && decoration.face == self.release.panel.face
                    && decoration.kind == MapDecorationKind::Terminal
                    && decoration.center == self.release.panel.center
                    && decoration.size == self.release.panel.size
            })
            .ok_or_else(|| invalid("foundry release panel is not on the map"))?;
        let point = panel.point(&arena.solids[panel_solid]);
        if !standing(arena, self.release.approach)
            || workers_distance(self.release.approach, point) > USE_DISTANCE
        {
            return Err(invalid("foundry release is out of reach"));
        }
        if !inset_holds(deck, self.inset.min, self.inset.max)
            || deck_at(deck, deck.top).is_none()
            || !self.lift_top.is_finite()
            || self.lift_top <= deck.top + 0.05
            || !travel_clear(
                arena,
                deck_index,
                deck,
                self.inset.min,
                self.inset.max,
                self.lift_top,
            )
        {
            return Err(invalid("foundry lift target is below the deck"));
        }
        let gates = Gates {
            relay,
            protected,
            hazard: self.hazard,
            bypass: self.bypass,
            cycle,
            release: UseTarget {
                decoration,
                approach: self.release.approach,
            },
            quarters_group,
            deck_index,
            deck,
            inset_min: self.inset.min,
            inset_max: self.inset.max,
            lift_top: self.lift_top,
        };
        let geometry = self
            .connected
            .map(|c| {
                use crate::protocol::{
                    M13HazardCycle, M13MapGeometry, MissionObjective, MissionObjectiveAction,
                    M13_OBJECTIVE_IDS,
                };
                let expected = [
                    "foundry_edge",
                    "machine_hall",
                    "quarters_approach",
                    "freight_lesson",
                    "freight_counterattack",
                    "ladle_galleries",
                ];
                if encounters.len() != expected.len()
                    || encounters
                        .iter()
                        .zip(expected)
                        .enumerate()
                        .any(|(i, (e, id))| {
                            e.id != id
                                || e.after.as_deref() != i.checked_sub(1).map(|j| expected[j])
                        })
                {
                    return Err(invalid("M13 requires ordered foundry encounters"));
                }
                use crate::protocol::EnemyKind::{
                    Assessor, Clerk, Enforcer, HeavySweeper, Notary, RangedSweeper, Sweeper,
                };
                let roles: [&[(&str, crate::protocol::EnemyKind)]; 6] = [
                    &[
                        ("edge_clerk_west", Clerk),
                        ("edge_clerk_east", Clerk),
                        ("edge_sweeper_west", Sweeper),
                        ("edge_sweeper_east", Sweeper),
                    ],
                    &[
                        ("machine_heavy", HeavySweeper),
                        ("machine_clerk", Clerk),
                        ("machine_sweeper", Sweeper),
                        ("machine_notary_west", Notary),
                        ("machine_notary_east", Notary),
                    ],
                    &[("quarters_clerk", Clerk), ("office_clerk", Clerk)],
                    &[
                        ("freight_sweeper_west", Sweeper),
                        ("freight_sweeper_center", Sweeper),
                        ("freight_sweeper_east", Sweeper),
                    ],
                    &[
                        ("freight_clerk_west", Clerk),
                        ("freight_clerk_east", Clerk),
                        ("freight_enforcer", Enforcer),
                        ("freight_assessor", Assessor),
                        ("counter_sweeper_west", Sweeper),
                        ("counter_sweeper_east", Sweeper),
                    ],
                    &[
                        ("gallery_clerk_west", Clerk),
                        ("gallery_clerk_east", Clerk),
                        ("gallery_clerk_back", Clerk),
                        ("gallery_heavy", HeavySweeper),
                        ("gallery_marksman", RangedSweeper),
                    ],
                ];
                if encounters.iter().zip(roles).any(|(e, roles)| {
                    e.enemies.len() != roles.len()
                        || roles.iter().any(|(id, kind)| {
                            !e.enemies.iter().any(|a| a.id == *id && a.kind == *kind)
                        })
                }) {
                    return Err(invalid(
                        "M13 requires its registered Rocket lesson and gallery support defenders",
                    ));
                }
                if encounters[5]
                    .enemies
                    .iter()
                    .any(|a| a.feet[1] < 3.0 || a.feet[2] < 27.0)
                {
                    return Err(invalid(
                        "M13 support defenders require actual upper galleries",
                    ));
                }
                let host = *ids
                    .get(&c.departure.panel.solid)
                    .ok_or_else(|| invalid("M13 lift control host missing"))?;
                let decoration = presentation
                    .decorations
                    .iter()
                    .position(|d| {
                        d.solid == host
                            && d.face == c.departure.panel.face
                            && d.kind == MapDecorationKind::LiftControl
                            && d.center == c.departure.panel.center
                            && d.size == c.departure.panel.size
                    })
                    .ok_or_else(|| invalid("M13 lift control missing"))?;
                let departure = UseTarget {
                    decoration,
                    approach: c.departure.approach,
                };
                let mut objectives = Vec::new();
                let mut arrivals = c.arrivals.into_iter();
                for (i, id) in M13_OBJECTIVE_IDS.into_iter().enumerate() {
                    let action = match i {
                        4 => MissionObjectiveAction::Shoot {
                            solid: relay,
                            approach: c.relay_approach,
                            aim: c.relay_aim,
                        },
                        6 => MissionObjectiveAction::Use {
                            target: departure.clone(),
                        },
                        _ => {
                            let a = arrivals.next().unwrap();
                            if !standing(arena, a.feet) {
                                return Err(invalid("M13 objective lacks standing support"));
                            }
                            MissionObjectiveAction::Arrival {
                                region: a.region,
                                feet: a.feet,
                            }
                        }
                    };
                    objectives.push(MissionObjective {
                        id: id.into(),
                        action,
                    });
                }
                let g = M13MapGeometry {
                    objectives,
                    release: gates.release.clone(),
                    departure,
                    relay,
                    protected: gates.protected.clone(),
                    hazard: gates.hazard.clone(),
                    bypass: gates.bypass.clone(),
                    cycle: M13HazardCycle {
                        period: cycle.period,
                        warning: cycle.warning,
                        active: cycle.active,
                    },
                    deck: deck_index,
                    parked_top: deck.top,
                    lift_top: gates.lift_top,
                    inset_min: gates.inset_min,
                    inset_max: gates.inset_max,
                    workers: c.workers,
                    worker_destinations: c.worker_destinations,
                    overseer: c.overseer,
                };
                g.validate(arena.half, &arena.solids, Some(presentation))
                    .map_err(invalid)?;
                for target in [&g.release, &g.departure] {
                    let point = target
                        .point(presentation, &arena.solids)
                        .ok_or_else(|| invalid("M13 control has no physical face"))?;
                    let eye = [
                        target.approach[0],
                        target.approach[1] + crate::movement::EYE_HEIGHT,
                        target.approach[2],
                    ];
                    if workers_distance(eye, point) > USE_DISTANCE
                        || !crate::combat::line_of_sight(eye, point, &arena.solids)
                    {
                        return Err(invalid("M13 control approach is not physically reachable"));
                    }
                }
                if !standing(arena, g.departure.approach)
                    || !standing(arena, c.relay_approach)
                    || g.workers
                        .iter()
                        .chain(&g.worker_destinations)
                        .chain(std::iter::once(&g.overseer))
                        .any(|p| !standing(arena, *p))
                {
                    return Err(invalid("M13 people or controls lack support"));
                }
                for i in 0..2 {
                    let mut state = crate::movement::MoveState {
                        x: g.workers[i][0],
                        y: g.workers[i][1],
                        z: g.workers[i][2],
                        vx: 0.0,
                        vz: 0.0,
                        vy: 0.0,
                        yaw: 0.0,
                    };
                    let to = g.worker_destinations[i];
                    for _ in 0..800 {
                        let dx = to[0] - state.x;
                        let dz = to[2] - state.z;
                        let distance = dx.hypot(dz);
                        if distance < 0.01 {
                            break;
                        }
                        let speed = (distance / 0.05).min(1.2);
                        state.vx = dx / distance * speed;
                        state.vz = dz / distance * speed;
                        state = crate::movement::integrate(state, false, 0.05, arena);
                    }
                    if (state.x - to[0]).hypot(state.z - to[2]) > 0.01
                        || (state.y - to[1]).abs() > 0.05
                    {
                        return Err(invalid(&format!(
                            "M13 worker route {i} is not grounded and clear: {:?} to {to:?}",
                            [state.x, state.y, state.z]
                        )));
                    }
                }
                Ok(g)
            })
            .transpose()?;
        Ok(Prepared { gates, geometry })
    }
}

fn inset_holds(deck: Solid, min: [f32; 2], max: [f32; 2]) -> bool {
    min[0] < max[0]
        && min[1] < max[1]
        && deck.covers(min[0], min[1])
        && deck.covers(max[0], min[1])
        && deck.covers(min[0], max[1])
        && deck.covers(max[0], max[1])
}

fn travel_clear(
    arena: &crate::movement::Arena,
    deck_index: usize,
    deck: Solid,
    inset_min: [f32; 2],
    inset_max: [f32; 2],
    lift_top: f32,
) -> bool {
    let Some(end) = deck_at(deck, lift_top) else {
        return false;
    };
    if step_blocked(deck, end, &[], &arena.solids, deck_index) {
        return false;
    }
    let mid_x = (inset_min[0] + inset_max[0]) * 0.5;
    let mid_z = (inset_min[1] + inset_max[1]) * 0.5;
    let samples = [
        [inset_min[0], inset_min[1]],
        [inset_min[0], inset_max[1]],
        [inset_max[0], inset_min[1]],
        [inset_max[0], inset_max[1]],
        [mid_x, mid_z],
    ];
    samples.iter().all(|sample| {
        !step_blocked(
            deck,
            end,
            &[LiftBody {
                x: sample[0],
                y: deck.top,
                z: sample[1],
                height: BODY_HEIGHT,
                supported: true,
            }],
            &arena.solids,
            deck_index,
        )
    })
}
