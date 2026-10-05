//! Existing ward figures, without health, damage or an independent simulation.
use crate::movement::{contact::ContactBody, Solid};
use crate::protocol::{CampaignActor, CompanionPhase, MissionPhase};
use crate::sim::{contact::civilian, GameState};

pub(crate) const PARTS: [([f32; 3], [f32; 3]); 12] = [
    ([0.0, 1.2, 0.0], [0.62, 0.78, 0.29]),
    ([0.11, 1.38, 0.164], [0.22, 0.16, 0.035]),
    ([0.0, 1.69, 0.0], [0.2, 0.16, 0.19]),
    ([0.0, 1.9, 0.0], [0.36, 0.32, 0.32]),
    ([-0.18, 0.38, 0.0], [0.21, 0.68, 0.22]),
    ([-0.18, 0.09, 0.1], [0.23, 0.13, 0.38]),
    ([-0.42, 1.12, 0.0], [0.19, 0.66, 0.22]),
    ([-0.42, 0.77, 0.01], [0.13, 0.13, 0.15]),
    ([0.18, 0.38, 0.0], [0.21, 0.68, 0.22]),
    ([0.18, 0.09, 0.1], [0.23, 0.13, 0.38]),
    ([0.42, 1.12, 0.0], [0.19, 0.66, 0.22]),
    ([0.42, 0.77, 0.01], [0.13, 0.13, 0.15]),
];

#[derive(Debug, Clone)]
pub(crate) struct Layout {
    pub(crate) first: [f32; 3],
    pub(crate) bay: [f32; 3],
    #[cfg(test)]
    pub(crate) notary: [f32; 3],
}

impl Layout {
    pub(crate) fn read(solids: &[Solid]) -> Option<Self> {
        let mut hosts = solids.iter().filter(|s| {
            s.min_x == 8.0
                && s.max_x == 9.0
                && s.bottom == 0.0
                && s.top == 2.6
                && s.min_z == -13.0
                && s.max_z == -9.0
        });
        let host = hosts.next()?;
        if hosts.next().is_some() {
            return None;
        }
        Some(Self {
            first: [host.min_x - 0.45, host.bottom, host.max_z - 1.0],
            bay: [host.min_x + 0.35, host.bottom, host.min_z - 3.0],
            #[cfg(test)]
            notary: [host.min_x + 2.4, host.bottom + 4.35, host.min_z - 8.3],
        })
    }

    pub(crate) fn second(&self, open: f32) -> Vec<Solid> {
        let local_x = -0.12 + open.clamp(0.0, 1.0) * 0.12;
        PARTS
            .iter()
            .map(|(position, size)| {
                // The existing restraint parent is rotated -PI/2 around Y.
                let x = self.bay[0] - (position[2] - 0.21);
                let y = self.bay[1] + position[1];
                let z = self.bay[2] + position[0] + local_x;
                Solid {
                    min_x: x - size[2] * 0.5,
                    max_x: x + size[2] * 0.5,
                    bottom: y - size[1] * 0.5,
                    top: y + size[1] * 0.5,
                    min_z: z - size[0] * 0.5,
                    max_z: z + size[0] * 0.5,
                }
            })
            .collect()
    }
}

pub(crate) fn opening(phase: CompanionPhase, started: u64, tick: u64) -> f32 {
    if phase != CompanionPhase::Releasing {
        return 1.0;
    }
    ((tick.saturating_sub(started) as f32 - 70.0) / 22.0).clamp(0.0, 1.0)
}

impl GameState {
    pub(crate) fn append_m02_tableau_shots(
        &self,
        cylinders: &mut Vec<ContactBody>,
        boxes: &mut Vec<Solid>,
    ) {
        let Some(_) = self
            .mission
            .as_ref()
            .filter(|r| r.m02.is_some() && r.phase == MissionPhase::InProgress)
        else {
            return;
        };
        if self.map.id() != 1002 || self.map.name() != "Persons Unknown: ward graybox" {
            return;
        }
        let Some(layout) = Layout::read(&self.map.arena().solids) else {
            return;
        };
        let companion = self.players.iter().find(|p| p.is_campaign_companion());
        let open = companion
            .and_then(|p| match p.campaign {
                Some(CampaignActor::Companion {
                    phase,
                    phase_started,
                    ..
                }) => Some(opening(phase, phase_started, self.tick)),
                _ => None,
            })
            .unwrap_or(0.0);
        if companion.is_none() {
            cylinders.push(civilian("m02/restrained_latch".into(), layout.first));
        }
        boxes.extend(layout.second(open));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::combat::Ray;
    use crate::maps::{AuthoredSource, RuntimeMap};
    use crate::protocol::MissionId;

    fn golden() -> serde_json::Value {
        serde_json::from_str(include_str!(
            "../../../../client/golden/m02_tableau_body_vectors.json"
        ))
        .unwrap()
    }

    fn solid(value: &serde_json::Value) -> Solid {
        let field = |name| value[name].as_f64().unwrap() as f32;
        Solid {
            min_x: field("min_x"),
            max_x: field("max_x"),
            bottom: field("bottom"),
            top: field("top"),
            min_z: field("min_z"),
            max_z: field("max_z"),
        }
    }

    #[test]
    fn source_box_goldens_match_all_parts_through_actual_opening() {
        let data = golden();
        let hosts: Vec<_> = data["map"]["solids"]
            .as_array()
            .unwrap()
            .iter()
            .map(solid)
            .collect();
        let layout = Layout::read(&hosts).unwrap();
        for case in data["cases"].as_array().unwrap() {
            let actual = layout.second(case["opening"].as_f64().unwrap() as f32);
            let expected: Vec<_> = case["boxes"]
                .as_array()
                .unwrap()
                .iter()
                .map(solid)
                .collect();
            assert_eq!(actual.len(), expected.len());
            for (a, e) in actual.iter().zip(expected) {
                for (a, e) in [a.min_x, a.max_x, a.bottom, a.top, a.min_z, a.max_z]
                    .into_iter()
                    .zip([e.min_x, e.max_x, e.bottom, e.top, e.min_z, e.max_z])
                {
                    assert!((a - e).abs() < 0.00001, "source part mismatch {a} != {e}");
                }
            }
        }
        let mut doubled = hosts.clone();
        doubled.extend(hosts);
        assert!(Layout::read(&doubled).is_none());
    }

    // Partition a boundary face at every real solid edge. Each resulting cell
    // must have world cover, rather than assuming sampled rays imply a sealed room.
    fn face_covered(
        solids: &[Solid],
        axis: usize,
        plane: f32,
        low: [f32; 2],
        high: [f32; 2],
    ) -> bool {
        let mut rectangles = Vec::new();
        let mut cuts = [vec![low[0], high[0]], vec![low[1], high[1]]];
        for s in solids {
            let bounds = [[s.min_x, s.max_x], [s.bottom, s.top], [s.min_z, s.max_z]];
            if plane < bounds[axis][0] - 0.00001 || plane > bounds[axis][1] + 0.00001 {
                continue;
            }
            let projected: Vec<_> = bounds
                .into_iter()
                .enumerate()
                .filter_map(|(i, b)| (i != axis).then_some(b))
                .collect();
            let a = [projected[0][0].max(low[0]), projected[1][0].max(low[1])];
            let b = [projected[0][1].min(high[0]), projected[1][1].min(high[1])];
            if a[0] >= b[0] || a[1] >= b[1] {
                continue;
            }
            rectangles.push((a, b));
            for i in 0..2 {
                cuts[i].extend([a[i], b[i]]);
            }
        }
        for cut in &mut cuts {
            cut.sort_by(f32::total_cmp);
            cut.dedup();
        }
        cuts[0].windows(2).all(|x| {
            cuts[1].windows(2).all(|y| {
                let p = [(x[0] + x[1]) * 0.5, (y[0] + y[1]) * 0.5];
                rectangles
                    .iter()
                    .any(|(a, b)| (0..2).all(|i| p[i] >= a[i] && p[i] <= b[i]))
            })
        })
    }

    #[test]
    fn passive_notary_full_mesh_and_bob_remain_inside_real_sealed_world() {
        let map = AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap();
        let runtime = RuntimeMap::Authored(map);
        let solids = &runtime.arena().solids;
        let data = golden();
        let body = solid(&data["notary"]["envelope"]);
        assert!(
            body.min_x > 9.08
                && body.max_x < 15.5
                && body.bottom > 0.0
                && body.top < 7.0
                && body.min_z > -24.0
                && body.max_z < -18.0
        );
        for (axis, plane, low, high) in [
            (0, 9.08, [0.0, -24.0], [7.0, -18.0]),
            (0, 15.5, [0.0, -24.0], [7.0, -18.0]),
            (2, -24.0, [9.08, 0.0], [15.5, 7.0]),
            (2, -18.0, [9.08, 0.0], [15.5, 7.0]),
            (1, 7.0, [9.08, -24.0], [15.5, -18.0]),
        ] {
            assert!(
                face_covered(solids, axis, plane, low, high),
                "unsealed face {axis}/{plane}"
            );
        }
        // The ordinary ground plane closes the sixth face at y=0.
        for target in [
            [body.min_x, body.top, body.min_z],
            [body.max_x, body.bottom, body.max_z],
            [10.4, 4.35, -21.3],
        ] {
            for origin in [
                [7.0, 6.8, -22.0],
                [12.0, 8.0, -20.0],
                [17.0, 5.0, -22.0],
                [11.0, 6.0, -26.0],
                [11.0, 6.0, -16.0],
                [11.0, -1.0, -21.0],
            ] {
                let delta: [f32; 3] = std::array::from_fn(|i| target[i] - origin[i]);
                let distance = delta.iter().map(|v| v * v).sum::<f32>().sqrt();
                let ray = Ray {
                    origin,
                    direction: delta.map(|v| v / distance),
                };
                assert!(
                    solids.iter().any(|s| ray.solid(s, distance).is_some())
                        || (origin[1] < 0.0 && target[1] > 0.0),
                    "exposed actual envelope ray {origin:?}"
                );
            }
        }
        let without_glass: Vec<_> = solids
            .iter()
            .copied()
            .filter(|s| !(s.min_x == 9.0 && s.max_x == 9.08 && s.bottom == 3.3 && s.top == 5.2))
            .collect();
        assert!(!face_covered(
            &without_glass,
            0,
            9.08,
            [0.0, -24.0],
            [7.0, -18.0]
        ));
        let through = Ray {
            origin: [8.5, 4.35, -21.3],
            direction: [1.0, 0.0, 0.0],
        };
        assert!(solids.iter().any(|s| through.solid(s, 1.9).is_some()));
        assert!(!without_glass
            .iter()
            .any(|s| through.solid(s, 1.9).is_some()));
    }

    #[test]
    fn actual_tableau_host_parts_and_clock_are_bounded() {
        let map = AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap();
        let runtime = RuntimeMap::Authored(map);
        let layout = Layout::read(&runtime.arena().solids).unwrap();
        assert_eq!(layout.first, [7.55, 0.0, -10.0]);
        assert_eq!(layout.bay, [8.35, 0.0, -16.0]);
        assert_eq!(layout.notary, [10.4, 4.35, -21.3]);
        for open in [0.0, 0.5, 1.0] {
            let parts = layout.second(open);
            assert_eq!(parts.len(), 12);
            assert!((parts.iter().map(|p| p.top).fold(0.0, f32::max) - 2.06).abs() < 0.00001);
            assert!(parts.iter().all(|p| p.min_x >= 8.26 && p.max_x < 8.8));
        }
        assert_eq!(opening(CompanionPhase::Releasing, 100, 169), 0.0);
        assert_eq!(opening(CompanionPhase::Releasing, 100, 181), 0.5);
        assert_eq!(opening(CompanionPhase::Releasing, 100, 192), 1.0);
        assert_eq!(opening(CompanionPhase::Following, 340, 340), 1.0);
        assert_eq!(opening(CompanionPhase::Releasing, 100, 0), 0.0);
        let mut invalid = runtime.arena().solids.clone();
        let host = invalid
            .iter_mut()
            .find(|s| s.min_x == 8.0 && s.max_x == 9.0 && s.min_z == -13.0)
            .unwrap();
        host.top += 0.01;
        assert!(Layout::read(&invalid).is_none());
    }
}
