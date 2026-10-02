//! Swept living bodies, separate from world support and combat hit boxes.
use super::{integrate_with_height, Arena, MoveState};

pub const EPSILON: f32 = 0.0001;
pub const PASSES: usize = 8;

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ContactBody {
    pub key: String,
    pub from: MoveState,
    pub proposed: MoveState,
    pub height: f32,
    pub radius: f32,
    pub jump: bool,
}

/// First strictly overlapping horizontal/vertical interval, including motion
/// of both bodies. Existing overlap permits radial escape without teleporting.
pub fn sweep_time(a: &ContactBody, b: &ContactBody) -> Option<f32> {
    let x = a.from.x - b.from.x;
    let z = a.from.z - b.from.z;
    let dx = (a.proposed.x - a.from.x) - (b.proposed.x - b.from.x);
    let dz = (a.proposed.z - a.from.z) - (b.proposed.z - b.from.z);
    let r = a.radius + b.radius;
    let c = x * x + z * z - r * r;
    let dot = x * dx + z * dz;
    let initially_overlapping =
        a.from.y + a.height > b.from.y + EPSILON && b.from.y + b.height > a.from.y + EPSILON;
    if c < EPSILON && dot >= -EPSILON && initially_overlapping {
        return None;
    }
    let speed = dx * dx + dz * dz;
    if speed <= EPSILON * EPSILON {
        return None;
    }
    let disc = dot * dot - speed * c;
    if disc <= 0.0 {
        return None;
    }
    let root = disc.sqrt();
    let mut enter = ((-dot - root) / speed).max(0.0);
    let mut exit = ((-dot + root) / speed).min(1.0);
    // Strict vertical overlap. Linear endpoints include jumps and short actors.
    for (start, end) in [
        (
            a.from.y + a.height - b.from.y,
            a.proposed.y + a.height - b.proposed.y,
        ),
        (
            b.from.y + b.height - a.from.y,
            b.proposed.y + b.height - a.proposed.y,
        ),
    ] {
        if start <= EPSILON && end <= EPSILON {
            return None;
        }
        let delta = end - start;
        if delta.abs() > EPSILON {
            let crossing = (EPSILON - start) / delta;
            if delta > 0.0 {
                enter = enter.max(crossing);
            } else {
                exit = exit.min(crossing);
            }
        }
    }
    (enter < exit - EPSILON && enter < 1.0 - EPSILON).then_some(enter)
}

fn reintegrate(body: &ContactBody, dx: f32, dz: f32, dt: f32, arena: &Arena) -> MoveState {
    let mut start = body.from;
    start.vx = dx / dt;
    start.vz = dz / dt;
    let mut result = integrate_with_height(start, body.jump, dt, arena, body.height);
    result.vx = (result.x - body.from.x) / dt;
    result.vz = (result.z - body.from.z) / dt;
    result
}

/// Eight bounded deterministic projection passes, then a conservative stop of
/// unresolved movers. Every changed endpoint recomputes world support from the
/// original vertical state; actors never become floors or push stationary peers.
pub fn resolve(bodies: &[ContactBody], dt: f32, arena: &Arena) -> Vec<MoveState> {
    if !dt.is_finite() || dt <= 0.0 {
        return bodies.iter().map(|b| b.from).collect();
    }
    let mut work = bodies.to_vec();
    let mut order: Vec<_> = (0..work.len()).collect();
    order.sort_by(|&a, &b| work[a].key.cmp(&work[b].key));
    for _ in 0..PASSES {
        let mut changed = false;
        for (offset, &i) in order.iter().enumerate() {
            for &j in &order[offset + 1..] {
                let Some(t) = sweep_time(&work[i], &work[j]) else {
                    continue;
                };
                let a = &work[i];
                let b = &work[j];
                let ax = a.proposed.x - a.from.x;
                let az = a.proposed.z - a.from.z;
                let bx = b.proposed.x - b.from.x;
                let bz = b.proposed.z - b.from.z;
                let nx = a.from.x + ax * t - b.from.x - bx * t;
                let nz = a.from.z + az * t - b.from.z - bz * t;
                let length = nx.hypot(nz);
                let (nx, nz) = if length > EPSILON {
                    (nx / length, nz / length)
                } else {
                    (1.0, 0.0)
                };
                for (index, dx, dz, sign) in [(i, ax, az, 1.0), (j, bx, bz, -1.0)] {
                    let inward = (dx * nx + dz * nz) * sign;
                    if inward < -EPSILON {
                        let remaining = 1.0 - t;
                        work[index].proposed = reintegrate(
                            &work[index],
                            dx - nx * sign * inward * remaining,
                            dz - nz * sign * inward * remaining,
                            dt,
                            arena,
                        );
                        changed = true;
                    }
                }
            }
        }
        if !changed {
            break;
        }
    }
    // Curved sliding is represented by a tick chord. Recheck that chord, rather
    // than trusting a projected endpoint that could cut back through a body.
    for _ in 0..work.len() {
        let mut changed = false;
        for (offset, &i) in order.iter().enumerate() {
            for &j in &order[offset + 1..] {
                if sweep_time(&work[i], &work[j]).is_some() {
                    for index in [i, j] {
                        if (work[index].proposed.x - work[index].from.x).abs() > EPSILON
                            || (work[index].proposed.z - work[index].from.z).abs() > EPSILON
                        {
                            work[index].proposed = reintegrate(&work[index], 0.0, 0.0, dt, arena);
                            changed = true;
                        }
                    }
                }
            }
        }
        if !changed {
            break;
        }
    }
    work.into_iter().map(|b| b.proposed).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn body(key: &str, x: f32, z: f32, dx: f32, dz: f32) -> ContactBody {
        let from = MoveState {
            x,
            y: 0.0,
            z,
            vx: 0.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        ContactBody {
            key: key.into(),
            from,
            proposed: MoveState {
                x: x + dx,
                z: z + dz,
                vx: dx / 0.05,
                vz: dz / 0.05,
                ..from
            },
            height: 1.8,
            radius: 0.5,
            jump: false,
        }
    }
    fn arena() -> Arena {
        Arena {
            half: 40.0,
            solids: vec![],
        }
    }
    #[test]
    fn actor_contact_stop_slide_mutual_and_overlap_escape() {
        let blocker = body("b", 0.0, 0.0, 0.0, 0.0);
        let stopped = resolve(
            &[body("a", -1.2, 0.0, 0.3, 0.0), blocker.clone()],
            0.05,
            &arena(),
        );
        assert!((stopped[0].x + 1.0).abs() < 0.0005);
        assert_eq!(stopped[1], blocker.from);
        let mut mover = body("a", -1.2, 0.0, 0.3, 0.2);
        let slid = resolve(&[mover.clone(), blocker.clone()], 0.05, &arena());
        assert!(
            slid[0].z > 0.1,
            "glancing contact must retain tangent motion: {:?}",
            slid[0]
        );
        assert!(slid[0].x.hypot(slid[0].z) >= 0.9999);
        mover.from = slid[0];
        for _ in 0..20 {
            mover.proposed = MoveState {
                x: mover.from.x + 0.15,
                z: mover.from.z + 0.15,
                ..mover.from
            };
            let result = resolve(&[mover.clone(), blocker.clone()], 0.05, &arena());
            assert!(result[0].z >= mover.from.z);
            mover.from = result[0];
        }
        assert!(
            mover.from.z > 2.0,
            "repeated contact must make cumulative tangent progress"
        );
        let pair = vec![
            body("a", -1.1, 0.0, 0.2, 0.0),
            body("b", 1.1, 0.0, -0.2, 0.0),
        ];
        let mut approaching = pair;
        for _ in 0..12 {
            let result = resolve(&approaching, 0.05, &arena());
            assert!(result[1].x - result[0].x >= 0.9999);
            for (b, r) in approaching.iter_mut().zip(result) {
                let dx = b.proposed.x - b.from.x;
                b.from = r;
                b.proposed = MoveState { x: r.x + dx, ..r };
            }
        }
        let escape = body("a", -0.5, 0.0, -0.2, 0.1);
        assert_eq!(
            resolve(&[escape.clone(), blocker.clone()], 0.05, &arena())[0],
            escape.proposed
        );
        let inward = resolve(&[body("a", -0.5, 0.0, 0.2, 0.0), blocker], 0.05, &arena());
        assert!(inward[0].x <= -0.5);
    }
    #[test]
    fn actor_contact_height_support_wall_and_no_peer_identity() {
        let lone = body("a", -1.0, 0.0, 0.25, 0.15);
        assert_eq!(
            resolve(std::slice::from_ref(&lone), 0.05, &arena())[0],
            lone.proposed
        );
        let mut drone = body("b", 0.0, 0.0, 0.0, 0.0);
        drone.height = 0.7;
        drone.from.y = 2.5;
        drone.proposed.y = 2.5;
        assert_eq!(
            resolve(&[lone.clone(), drone], 0.05, &arena())[0],
            lone.proposed
        );
        let mut low = body("b", 0.0, 0.0, 0.0, 0.0);
        low.height = 0.8;
        let mut above = lone.clone();
        above.from.y = 1.0;
        above.proposed.y = 1.0;
        assert!(sweep_time(&above, &low).is_none());
        let mut world = arena();
        world.solids.push(super::super::Solid {
            min_x: -0.9,
            max_x: 1.0,
            min_z: -2.0,
            max_z: 2.0,
            bottom: 0.0,
            top: 0.5,
        });
        let start = MoveState {
            x: -1.1,
            y: 0.0,
            z: 0.0,
            vx: 5.0,
            vz: 0.0,
            vy: 0.0,
            yaw: 0.0,
        };
        let proposed = integrate_with_height(start, false, 0.05, &world, 1.8);
        assert_eq!(proposed.y, 0.5);
        let b = ContactBody {
            key: "a".into(),
            from: start,
            proposed,
            height: 1.8,
            radius: 0.5,
            jump: false,
        };
        let stopped = resolve(&[b, body("b", -0.05, 0.0, 0.0, 0.0)], 0.05, &world);
        assert!(stopped[0].x <= -1.05 + 0.0005);
        assert_eq!(
            stopped[0].y, 0.0,
            "rejected step cannot retain its support height"
        );
    }

    #[test]
    fn actor_contact_shared_vectors() {
        let mut elevated = body("b", 0.0, 0.0, 0.0, 0.0);
        elevated.height = 0.7;
        elevated.from.y = 2.5;
        elevated.proposed.y = 2.5;
        let examples = vec![
            ("alone", vec![body("a", -1.2, 0.0, 0.3, 0.2)]),
            (
                "head_on",
                vec![
                    body("a", -1.2, 0.0, 0.3, 0.0),
                    body("b", 0.0, 0.0, 0.0, 0.0),
                ],
            ),
            (
                "glancing",
                vec![
                    body("a", -1.2, 0.0, 0.3, 0.2),
                    body("b", 0.0, 0.0, 0.0, 0.0),
                ],
            ),
            (
                "mutual",
                vec![
                    body("b", 0.6, 0.0, -0.2, 0.0),
                    body("a", -0.6, 0.0, 0.2, 0.0),
                ],
            ),
            (
                "overlap_escape",
                vec![
                    body("a", -0.5, 0.0, -0.2, 0.1),
                    body("b", 0.0, 0.0, 0.0, 0.0),
                ],
            ),
            (
                "raised_notary",
                vec![body("a", -1.2, 0.0, 0.3, 0.0), elevated],
            ),
        ];
        let cases:Vec<_>=examples.into_iter().map(|(name,bodies)|serde_json::json!({"name":name,"arena":arena(),"expected":resolve(&bodies,0.05,&arena()),"bodies":bodies})).collect();
        let a = body("a", -1.2, 0.0, 0.3, 0.0);
        let b = body("b", 0.0, 0.0, 0.0, 0.0);
        let data = serde_json::json!({"version":1,"dt":0.05,"sweep_cases":[{"name":"head_on","expected":sweep_time(&a,&b),"a":a,"b":b}],"cases":cases});
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../client/golden/actor_contact_vectors.json");
        if std::env::var_os("FRAGR_REGENERATE_CONTACT_GOLDENS").is_some() {
            std::fs::write(
                &path,
                format!("{}\n", serde_json::to_string_pretty(&data).unwrap()),
            )
            .unwrap();
        }
        assert_eq!(
            std::fs::read_to_string(path).unwrap(),
            format!("{}\n", serde_json::to_string_pretty(&data).unwrap())
        );
    }

    #[test]
    fn actor_contact_dense_queue_and_wall_slide() {
        let mut bodies: Vec<_> = (0..32)
            .map(|i| {
                body(
                    &format!("b{i:02}"),
                    i as f32 * 1.001,
                    0.0,
                    if i < 31 { 0.25 } else { 0.0 },
                    0.0,
                )
            })
            .collect();
        let distant = body("z", 0.0, 10.0, 0.25, 0.0);
        bodies.push(distant.clone());
        let result = resolve(&bodies, 0.05, &arena());
        for (i, a) in result.iter().enumerate() {
            for b in &result[i + 1..] {
                assert!((a.x - b.x).hypot(a.z - b.z) >= 0.9999);
            }
        }
        assert_eq!(*result.last().unwrap(), distant.proposed);
        let mut world = arena();
        world.solids.push(super::super::Solid {
            min_x: -3.0,
            max_x: -1.6,
            min_z: -10.0,
            max_z: 10.0,
            bottom: 0.0,
            top: 4.0,
        });
        let a = body("a", -1.1, 0.0, 0.15, 0.2);
        let b = body("b", 0.0, 0.0, 0.0, 0.0);
        let result = resolve(&[a, b], 0.05, &world);
        assert!(
            result[0].z > 0.1,
            "wall and body must preserve an open tangent route"
        );
        assert!(result[0].x >= -1.1001);
        assert!(result[0].x.hypot(result[0].z) >= 0.9999);
    }

    #[test]
    fn actor_contact_new_vertical_overlap_and_roster_order() {
        let mut falling = body("a", 0.5, 0.0, 0.25, 0.0);
        falling.from.y = 2.0;
        falling.proposed.y = 1.5;
        let target = body("b", 0.0, 0.0, 0.0, 0.0);
        assert!(
            sweep_time(&falling, &target).is_some(),
            "new vertical intersection is not existing overlap escape"
        );
        let a = body("a", -0.6, 0.0, 0.2, 0.1);
        let b = body("b", 0.6, 0.0, -0.2, -0.1);
        let forward = resolve(&[a.clone(), b.clone()], 0.05, &arena());
        let reverse = resolve(&[b, a], 0.05, &arena());
        assert_eq!(forward[0], reverse[1]);
        assert_eq!(forward[1], reverse[0]);
        assert_eq!(
            resolve(&[falling.clone()], f32::NAN, &arena())[0],
            falling.from
        );
    }
}
