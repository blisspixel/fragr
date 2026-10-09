//! Foundry gate authoring. The key is optional. A map without it is unchanged.
use super::{encounters::EncounterDefinition, invalid, standing};
use crate::mission::m13::{
    deck_at, hazard_overlap, step_blocked, workers_distance, Cycle, Gates, LiftBody,
};
use crate::movement::{Solid, BODY_HEIGHT};
use crate::protocol::{MapDecoration, MapDecorationKind, Region3, USE_DISTANCE};
use serde::Deserialize;
use std::collections::HashMap;
use std::io;

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) gates: Gates,
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
        let panel = presentation
            .decorations
            .iter()
            .find(|decoration| {
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
        Ok(Prepared {
            gates: Gates {
                relay,
                protected,
                hazard: self.hazard,
                bypass: self.bypass,
                cycle,
                release_approach: self.release.approach,
                quarters_group,
                deck_index,
                deck,
                inset_min: self.inset.min,
                inset_max: self.inset.max,
                lift_top: self.lift_top,
            },
        })
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
