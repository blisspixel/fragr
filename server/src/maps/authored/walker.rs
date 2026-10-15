//! Strict bounded Walker authoring; no mission identity is inferred from map ids.
use super::{invalid, standing};
use crate::movement::{Arena, Solid};
use crate::navigation::Navigation;
use crate::protocol::{Region3, WalkerGeometry};
use serde::Deserialize;
use std::{io, sync::Arc};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    solids: [String; 5],
    stations: [[f32; 3]; 3],
    activation: Region3,
    arena: Region3,
    approach: [f32; 3],
}

#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: WalkerGeometry,
    pub(crate) navigation: Arc<Navigation>,
}

pub(crate) fn overlaps(a: Solid, b: Solid) -> bool {
    a.min_x < b.max_x
        && a.max_x > b.min_x
        && a.min_z < b.max_z
        && a.max_z > b.min_z
        && a.bottom < b.top
        && a.top > b.bottom
}

impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        ids: &std::collections::HashMap<String, usize>,
    ) -> io::Result<Prepared> {
        let mut registered = [0; 5];
        for (slot, id) in registered.iter_mut().zip(self.solids) {
            *slot = ids
                .get(&id)
                .copied()
                .ok_or_else(|| invalid("Walker requires registered body solids"))?;
        }
        let geometry = WalkerGeometry {
            solids: registered,
            stations: self.stations,
            activation: self.activation,
            arena: self.arena,
            approach: self.approach,
        };
        geometry
            .validate(arena.half, &arena.solids)
            .map_err(invalid)?;
        if !standing(arena, geometry.approach) {
            return Err(invalid("Walker approach requires supported infantry feet"));
        }
        let mut conservative = arena.clone();
        for &index in &geometry.solids {
            let initial = arena.solids[index];
            let mut sweep = initial;
            for station in geometry.stations {
                let s = geometry.translated(initial, station);
                sweep.min_x = sweep.min_x.min(s.min_x);
                sweep.max_x = sweep.max_x.max(s.max_x);
                sweep.min_z = sweep.min_z.min(s.min_z);
                sweep.max_z = sweep.max_z.max(s.max_z);
            }
            if arena
                .solids
                .iter()
                .enumerate()
                .any(|(i, s)| !geometry.solids.contains(&i) && overlaps(sweep, *s))
            {
                return Err(invalid("Walker relocation sweep intersects static cover"));
            }
            // No supported routes across or beneath a moving machine.
            sweep.bottom = 0.0;
            conservative.solids[index] = sweep;
        }
        let navigation = Navigation::shared(conservative).map_err(invalid)?;
        Ok(Prepared {
            geometry,
            navigation,
        })
    }
}
