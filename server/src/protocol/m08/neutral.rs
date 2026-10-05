//! Non-wire placement of the archive's existing visible people. The same
//! registered panel frame is mirrored by M08NeutralBodies in the client.
use crate::movement::Solid;
use crate::protocol::{MapDecoration, MapDecorationKind, MapFace, MapPresentation};

pub(crate) const KEYS: [&str; 5] = [
    "m08/renn",
    "m08/captive/0",
    "m08/captive/1",
    "m08/captive/2",
    "m08/captive/3",
];

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct M08NeutralLayout {
    pub(crate) renn: [f32; 3],
    pub(crate) held: [[f32; 3]; 4],
    pub(crate) released: [[f32; 3]; 4],
}

impl M08NeutralLayout {
    pub(crate) fn read(
        half: f32,
        solids: &[Solid],
        presentation: &MapPresentation,
    ) -> Result<Self, &'static str> {
        crate::protocol::validate_decorations(&presentation.decorations, solids)?;
        let panel = |kind| {
            let mut matches = presentation.decorations.iter().filter(|p| p.kind == kind);
            let detail = matches.next().ok_or("M08 neutral panel missing")?;
            if matches.next().is_some() {
                return Err("M08 neutral panel duplicated");
            }
            Ok(detail)
        };
        let registry = panel(MapDecorationKind::M08Registry)?;
        let bays = panel(MapDecorationKind::M08BayRelease)?;
        let freight = panel(MapDecorationKind::M08FreightDeparture)?;
        // The old visual offset left 12 mm of a standard body inside the desk.
        // Two centimetres back preserves the placement with 8 mm clearance.
        let renn = offset(registry, &solids[registry.solid], -0.6, -1.52, [0.0; 3]);
        let held = std::array::from_fn(|i| {
            offset(
                bays,
                &solids[bays.solid],
                -4.5 + i as f32 * 3.0,
                0.8,
                [0.0; 3],
            )
        });
        let released = std::array::from_fn(|i| {
            let mut feet = offset(
                freight,
                &solids[freight.solid],
                0.0,
                2.5,
                [[-2.49, -1.0, 1.0, 2.49][i], 0.0, -3.5],
            );
            feet[1] = 0.0;
            feet
        });
        let layout = Self {
            renn,
            held,
            released,
        };
        if !half.is_finite()
            || half <= 0.0
            || std::iter::once(&layout.renn)
                .chain(&layout.held)
                .chain(&layout.released)
                .any(|p| {
                    p.iter().any(|n| !n.is_finite())
                        || p[0].abs() > half
                        || p[2].abs() > half
                        || !(0.0..=512.0).contains(&p[1])
                })
        {
            return Err("M08 neutral feet outside map");
        }
        Ok(layout)
    }

    pub(crate) fn people(
        &self,
        joined: bool,
        released: bool,
    ) -> impl Iterator<Item = (&'static str, [f32; 3])> + '_ {
        joined.then_some((KEYS[0], self.renn)).into_iter().chain(
            KEYS[1..].iter().copied().zip(
                if released { &self.released } else { &self.held }
                    .iter()
                    .copied(),
            ),
        )
    }
}

fn offset(
    detail: &MapDecoration,
    host: &Solid,
    right: f32,
    outward: f32,
    world: [f32; 3],
) -> [f32; 3] {
    let [x, z] = match detail.face {
        MapFace::West => [[0.0, 0.0, 1.0], [-1.0, 0.0, 0.0]],
        MapFace::East => [[0.0, 0.0, -1.0], [1.0, 0.0, 0.0]],
        MapFace::Down => [[1.0, 0.0, 0.0], [0.0, -1.0, 0.0]],
        MapFace::Up => [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
        MapFace::North => [[-1.0, 0.0, 0.0], [0.0, 0.0, -1.0]],
        MapFace::South => [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0]],
    };
    let point = detail.point(host);
    let mut feet = std::array::from_fn(|i| point[i] + x[i] * right + z[i] * outward + world[i]);
    feet[1] = host.bottom;
    feet
}

#[cfg(test)]
mod tests;
