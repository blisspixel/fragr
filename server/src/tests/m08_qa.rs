//! Ordinary declared archive routes, walked with shared movement in the stage
//! each state is played in. Combat drift and rendered timing need the live tour.
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::movement::{integrate, Arena, MoveState, TOP_SPEED};
use crate::protocol::MissionId;
use crate::sim::{PICKUP_CLAIM_HEIGHT, PICKUP_CLAIM_RADIUS};
use serde_json::Value;

fn walk(arena: &Arena, from: [f32; 3], to: [f32; 3]) -> bool {
    walk_ticks(arena, from, to, 4.0, &mut |_| {}).is_some()
}

/// Ticks an ordinary walk takes at `speed`, or `None` when it is blocked.
/// `each` sees the supported feet after every tick.
fn walk_ticks(
    arena: &Arena,
    from: [f32; 3],
    to: [f32; 3],
    speed: f32,
    each: &mut dyn FnMut([f32; 3]),
) -> Option<u32> {
    let mut body = MoveState {
        x: from[0],
        y: from[1],
        z: from[2],
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    for tick in 0..900 {
        let dx = to[0] - body.x;
        let dz = to[2] - body.z;
        let distance = dx.hypot(dz);
        if distance < 0.2 && (body.y - to[1]).abs() < 0.03 {
            return Some(tick);
        }
        let speed = speed.min(distance / 0.05);
        body.vx = dx / distance.max(0.001) * speed;
        body.vz = dz / distance.max(0.001) * speed;
        body = integrate(body, false, 0.05, arena);
        each([body.x, body.y, body.z]);
    }
    None
}

fn tour() -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../client/qa/m08_custodian_of_record.json");
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

#[test]
fn authored_m08_tour_walks_every_gallery_stair_and_stage() {
    let sealed = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::CustodianOfRecord)
            .load()
            .unwrap(),
    );
    let opened = sealed.prepared_m08_world(1).unwrap();
    let fallen = sealed.prepared_m08_world(2).unwrap();
    let mut count = 0;
    let mut stage = &sealed;
    let mut previous_end: Option<[f32; 3]> = None;
    for state in tour()["states"].as_array().unwrap() {
        let name = state["name"].as_str().unwrap();
        // The seal lifts at the Auditor's fall; the machine drops with the last node.
        if name == "m08_seal_lifted" {
            stage = &opened;
        }
        if name == "m08_machine_fallen" {
            stage = &fallen;
        }
        for (kind, points) in [
            ("walk", state.get("walk_to")),
            ("search", state["combat"].get("search_route")),
        ] {
            let Some(points) = points else {
                continue;
            };
            let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
            if kind == "walk" {
                if let (Some(from), Some(to)) = (previous_end, points.first()) {
                    assert!(
                        walk(stage.arena(), from, *to),
                        "{name} handoff {from:?}->{to:?} blocked"
                    );
                }
            }
            for segment in points.windows(2) {
                assert!(
                    walk(stage.arena(), segment[0], segment[1]),
                    "{name} {kind} {:?}->{:?} blocked",
                    segment[0],
                    segment[1]
                );
                count += 1;
            }
            if kind == "walk" {
                previous_end = points.last().copied().or(previous_end);
            }
        }
    }
    assert!(count > 80, "tour lost ordinary route coverage: {count}");
}

/// Tour states that end on a deliberate sight: a reveal, a rescue, a secret or
/// the evidence. Their end resets the quiet clock like a fight or a pickup.
const BEATS: [&str; 11] = [
    "m08_observation_secret",
    "m08_shaft_reveal",
    "m08_hall_arrival",
    "m08_lost_property_secret",
    "m08_registry",
    "m08_seal_lifted",
    "m08_lower_bays",
    "m08_cold_cabinet",
    "m08_machine_fallen",
    "m08_evidence",
    "m08_authorized_noise",
];

/// Pacing on the declared route at full running speed. First contact is the
/// direct ordinary route from the checkpoint spawn, past the entry Rifle, into
/// the records hall's trigger. A quiet stretch is walking with no fight, no
/// supply claimed and no beat; combat time itself belongs to the live tour.
#[test]
fn m08_pacing_first_contact_and_longest_quiet_walk() {
    let sealed = RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::CustodianOfRecord)
            .load()
            .unwrap(),
    );
    let opened = sealed.prepared_m08_world(1).unwrap();
    let fallen = sealed.prepared_m08_world(2).unwrap();
    let groups = sealed.encounters().to_vec();
    let direct = [
        [-1.0, 0.0, -33.0],
        [-2.5, 0.0, -30.0],
        [-5.0, 0.0, -28.0],
        [-5.0, 0.0, -23.0],
        [0.0, 0.0, -21.5],
        [0.0, 0.0, -19.5],
    ];
    let mut contact = None;
    let mut ticks = 0;
    for segment in direct.windows(2) {
        let mut each = |feet: [f32; 3]| {
            ticks += 1;
            if contact.is_none() && groups[0].regions.iter().any(|r| r.contains(feet)) {
                contact = Some(ticks);
            }
        };
        walk_ticks(sealed.arena(), segment[0], segment[1], TOP_SPEED, &mut each)
            .expect("direct route to the records hall");
    }
    let contact = contact.expect("the direct route wakes the records hall");
    // Quiet clock over the tour as played, optional detours included.
    let mut pads: Vec<_> = sealed.pickups();
    let mut woken = vec![false; groups.len()];
    let mut stage = &sealed;
    let mut previous_end: Option<[f32; 3]> = None;
    let (mut quiet, mut longest, mut longest_at) = (0_u32, 0_u32, String::new());
    let (mut main_longest, mut main_at, mut breath) = (0_u32, String::new(), 0_u32);
    for state in tour()["states"].as_array().unwrap() {
        let name = state["name"].as_str().unwrap().to_string();
        if name == "m08_seal_lifted" {
            stage = &opened;
        }
        if name == "m08_machine_fallen" {
            stage = &fallen;
        }
        // The optional lower bays: down from the seal and back up to it.
        let detour = matches!(name.as_str(), "m08_lower_bays" | "m08_service_ambush");
        // The one deliberate breath: the walk back to the bridge desk after the
        // machine's fall, before the counterattack.
        let breath_walk = name == "m08_evidence";
        let Some(points) = state.get("walk_to") else {
            if state.get("combat").is_some() {
                quiet = 0;
            }
            continue;
        };
        let points: Vec<[f32; 3]> = serde_json::from_value(points.clone()).unwrap();
        let mut legs: Vec<[[f32; 3]; 2]> = previous_end
            .zip(points.first())
            .map(|(from, to)| vec![[from, *to]])
            .unwrap_or_default();
        legs.extend(points.windows(2).map(|w| [w[0], w[1]]));
        for [from, to] in legs {
            let mut each = |feet: [f32; 3]| {
                quiet += 1;
                let before = pads.len();
                pads.retain(|pad| {
                    (pad.x - feet[0]).hypot(pad.z - feet[2]) > PICKUP_CLAIM_RADIUS
                        || (feet[1] - pad.floor).abs() > PICKUP_CLAIM_HEIGHT
                });
                for (index, group) in groups.iter().enumerate() {
                    if !woken[index] && group.regions.iter().any(|r| r.contains(feet)) {
                        woken[index] = true;
                        quiet = 0;
                    }
                }
                if pads.len() != before {
                    quiet = 0;
                }
                if quiet > longest {
                    longest = quiet;
                    longest_at = name.clone();
                }
                if breath_walk {
                    breath = breath.max(quiet);
                } else if !detour && quiet > main_longest {
                    main_longest = quiet;
                    main_at = name.clone();
                }
            };
            walk_ticks(stage.arena(), from, to, TOP_SPEED, &mut each)
                .unwrap_or_else(|| panic!("{name} {from:?}->{to:?} blocked"));
        }
        previous_end = points.last().copied().or(previous_end);
        // A state walks first and then fights; a broken node is an action
        // beat like a fight.
        if state.get("combat").is_some()
            || BEATS.contains(&name.as_str())
            || state.get("trigger").is_some_and(|t| t == "fire")
        {
            quiet = 0;
        }
    }
    eprintln!(
        "M08 pacing: first contact {:.1} s; longest quiet walk {:.1} s on the main route ({main_at}); breath after the machine falls {:.1} s; {:.1} s with the optional bays ({longest_at})",
        contact as f32 * 0.05,
        main_longest as f32 * 0.05,
        breath as f32 * 0.05,
        longest as f32 * 0.05
    );
    assert!(
        contact <= 200,
        "first contact within ten seconds: {contact} ticks"
    );
    assert!(
        main_longest <= 300,
        "no main-route quiet walk past fifteen seconds: {main_longest} ticks in {main_at}"
    );
    assert!(
        breath <= 400,
        "the one breath stays under twenty seconds: {breath} ticks"
    );
    assert!(
        longest <= 400,
        "the optional bays add at most twenty quiet seconds: {longest} ticks in {longest_at}"
    );
}
