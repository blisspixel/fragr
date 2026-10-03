//! Custodian of Record: ordered lessons, the lifted seal, the support-node
//! machine, optional rescue facts, retry and the freight departure.
use crate::maps::{AuthoredMap, AuthoredSource, RuntimeMap};
use crate::protocol::{
    Action, LookAt, MissionId, MissionObjectiveAction, MissionPhase, MissionReady, Role,
    WeaponType, M08_NODE_HP,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::sync::{Arc, OnceLock};
use uuid::Uuid;

fn map() -> Arc<AuthoredMap> {
    static MAP: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP.get_or_init(|| {
        AuthoredSource::Mission(MissionId::CustodianOfRecord)
            .load()
            .expect("bundled M08 route proof")
    })
    .clone()
}

fn advance(s: &mut GameSession, ticks: usize) {
    for _ in 0..ticks {
        s.tick_messages(0.05);
    }
}

fn fixture() -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.seed(42);
    let id = Uuid::from_u128(8008);
    s.state.add_player(id, "Visitor".into(), Role::Human);
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::CustodianOfRecord,
            attempt: 1
        }
    ));
    advance(&mut s, 1);
    (s, id)
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = feet[0];
    p.y = feet[1] + PLAYER_FLOOR_Y;
    p.z = feet[2];
    p.vy = 0.0;
    p.hp = 100;
    p.clear_input();
}

fn arrival_feet(objective: &crate::protocol::MissionObjective) -> [f32; 3] {
    let MissionObjectiveAction::Arrival { feet, .. } = objective.action else {
        panic!("arrival");
    };
    feet
}

fn facts(s: &GameSession) -> crate::protocol::M08ObjectiveState {
    s.state.mission_state().unwrap().m08.unwrap()
}

/// Wake a group at its own trigger, defeat it through the encounter seam and
/// stand on the step's arrival.
fn clear(s: &mut GameSession, id: Uuid, group: usize, arrival: Option<[f32; 3]>) {
    let definition = s.state.map.encounters()[group].clone();
    // Supported feet inside each group's own trigger.
    let wake = match group {
        3 => [18.0, 6.0, 2.0],
        5 => [-8.5, 6.0, 22.0],
        _ => arrival.expect("wake at the arrival"),
    };
    place(s, id, wake);
    advance(s, 2);
    for enemy in &definition.enemies {
        let Some(p) = s.state.players.iter_mut().find(|p| p.name == enemy.id) else {
            panic!("{} spawned for {}", enemy.id, definition.id);
        };
        p.hp = 0;
        let feet = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
        s.state.encounters.hit(p.id, feet, s.state.tick, true);
    }
    // Leave no Auditor time to reach a disabled body.
    advance(s, 2);
    assert!(
        s.state.encounters.is_complete(group),
        "{} cleared",
        definition.id
    );
    if let Some(feet) = arrival {
        place(s, id, feet);
        advance(s, 2);
    }
}

fn shoot_node(s: &mut GameSession, id: Uuid, node: usize) {
    let g = s.state.map.m08_geometry().unwrap();
    let target = &g.nodes[node];
    place(s, id, target.approach);
    let player = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    player.inventory.grant_weapon(WeaponType::Rail);
    player
        .inventory
        .grant_ammo(crate::protocol::AmmoPool::Cells, 10);
    player.weapon = WeaponType::Rail;
    player.fire_cooldown = 0;
    s.state.set_action(
        id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                x: Some(target.aim[0]),
                y: Some(target.aim[1]),
                z: Some(target.aim[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    advance(s, 1);
    s.state.set_action(id, Action::default());
    advance(s, 1);
}

#[test]
fn bundled_custodian_of_record_prepares_three_stages() {
    let runtime = RuntimeMap::Authored(map());
    assert_eq!(runtime.id(), 1008);
    assert_eq!(
        runtime.campaign_mission_id(),
        Some(MissionId::CustodianOfRecord)
    );
    let g = runtime.m08_geometry().unwrap();
    assert_eq!(g.objectives.len(), 6);
    assert_eq!(g.nodes.len(), 4);
    assert!(!g.seal_open && !g.machine_fallen);
    // Six ordered groups and the optional service ring ambush.
    assert_eq!(runtime.encounters().len(), 7);
    assert_eq!(runtime.encounters()[6].id, "service_ring");
    assert!(runtime.has_custody_devices());
    let opened = runtime.prepared_m08_world(1).unwrap();
    let fallen = runtime.prepared_m08_world(2).unwrap();
    assert!(runtime.prepared_m08_world(3).is_none());
    assert_eq!(opened.m08_stage(), 1);
    assert_eq!(fallen.m08_stage(), 2);
    let opened_g = opened.m08_geometry().unwrap();
    assert!(opened_g.seal_open && !opened_g.machine_fallen);
    assert!(fallen.m08_geometry().unwrap().machine_fallen);
    // The seal solid lifts into the roof; the machine lands on the shaft floor.
    assert!(opened.arena().solids[g.seal].bottom > 8.9);
    assert!(fallen.arena().solids[g.machine].bottom < 0.01);
    assert_eq!(
        runtime.arena().solids.len(),
        fallen.arena().solids.len(),
        "surfaces stay one per solid"
    );
    let required: usize = runtime.encounters()[..6]
        .iter()
        .map(|group| group.enemies.len())
        .sum();
    assert_eq!(required, 25);
    assert_eq!(runtime.encounters()[6].enemies.len(), 3, "optional ambush");
}

#[test]
fn m08_lessons_arrive_in_order_and_the_auditor_lifts_the_seal() {
    let (mut s, id) = fixture();
    let initial: Vec<String> = s
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy())
        .map(|p| p.name.clone())
        .collect();
    assert_eq!(initial.len(), 5, "only the records hall is placed");
    let g = s.state.map.m08_geometry().unwrap();
    assert_eq!(facts(&s).current.unwrap().id, "hall_cleared");
    clear(&mut s, id, 0, Some(arrival_feet(&g.objectives[0])));
    assert_eq!(facts(&s).completed, ["hall_cleared"]);
    assert!(!facts(&s).custodian_joined);
    clear(&mut s, id, 1, Some(arrival_feet(&g.objectives[1])));
    assert!(facts(&s).custodian_joined, "Renn offers the layout");
    // The mine lesson needs the alcove: its arrival waits for the clear.
    let mines = arrival_feet(&g.objectives[2]);
    place(&mut s, id, mines);
    advance(&mut s, 2);
    assert_eq!(
        facts(&s).completed.len(),
        2,
        "arrival alone cannot clear a live group"
    );
    clear(&mut s, id, 2, Some(mines));
    assert_eq!(facts(&s).completed.len(), 3);
    // The bays and the cabinet are refused before the Auditor falls.
    place(&mut s, id, arrival_feet(&g.bays));
    advance(&mut s, 2);
    assert!(!facts(&s).custody_released);
    assert_eq!(s.state.map.m08_stage(), 0);
    clear(&mut s, id, 3, None);
    advance(&mut s, 1);
    assert_eq!(
        s.state.map.m08_stage(),
        1,
        "the seal lifted when the Auditor fell"
    );
    assert!(facts(&s).seal_open);
    assert!(s.state.map.m08_geometry().unwrap().seal_open);
    place(&mut s, id, arrival_feet(&g.objectives[3]));
    advance(&mut s, 2);
    assert_eq!(facts(&s).completed.len(), 4);
    let current = facts(&s).current.unwrap();
    assert!(
        matches!(current.action, MissionObjectiveAction::Shoot { solid, .. } if solid == g.nodes[0].solid)
    );
    place(&mut s, id, arrival_feet(&g.bays));
    advance(&mut s, 2);
    assert!(facts(&s).custody_released);
    place(&mut s, id, arrival_feet(&g.cabinet));
    advance(&mut s, 2);
    assert!(facts(&s).recovered_mind_secured);
    let state = s.state.mission_state().unwrap();
    state.validate(s.state.tick).unwrap();
}

#[test]
fn m08_a_won_fight_counts_once_the_next_fight_wakes_without_its_arrival() {
    let (mut s, id) = fixture();
    // Clear the records hall from its doorway, never standing at the rail.
    place(&mut s, id, [0.0, 0.0, -18.0]);
    advance(&mut s, 2);
    let hall = s.state.map.encounters()[0].clone();
    for enemy in &hall.enemies {
        let p = s
            .state
            .players
            .iter_mut()
            .find(|p| p.name == enemy.id)
            .unwrap();
        p.hp = 0;
        let feet = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
        s.state.encounters.hit(p.id, feet, s.state.tick, true);
    }
    advance(&mut s, 4);
    assert!(s.state.encounters.is_complete(0));
    assert!(
        facts(&s).completed.is_empty(),
        "a won fight alone waits for its arrival or the next fight"
    );
    // Walking on up the west stair wakes the lower gallery.
    place(&mut s, id, [-14.0, 3.0, -9.0]);
    advance(&mut s, 2);
    assert!(s.state.encounters.is_awake(1));
    assert_eq!(facts(&s).completed, ["hall_cleared"]);
    assert_eq!(facts(&s).current.unwrap().id, "lower_gallery_cleared");
}

#[test]
fn m08_nodes_take_resolved_rays_only_on_their_step_and_drop_the_machine() {
    let (mut s, id) = fixture();
    let g = s.state.map.m08_geometry().unwrap();
    // A ray before the machine step changes nothing.
    shoot_node(&mut s, id, 0);
    assert!(facts(&s).node_hp.iter().all(|hp| *hp == M08_NODE_HP));
    for group in 0..3 {
        let arrival = arrival_feet(&g.objectives[group]);
        clear(&mut s, id, group, Some(arrival));
    }
    clear(&mut s, id, 3, None);
    advance(&mut s, 1);
    place(&mut s, id, arrival_feet(&g.objectives[3]));
    advance(&mut s, 2);
    assert_eq!(facts(&s).completed.len(), 4);
    shoot_node(&mut s, id, 0);
    assert_eq!(facts(&s).node_hp[0], 0, "one Rail hit breaks a 50 HP node");
    let next = facts(&s).current.unwrap();
    assert!(
        matches!(next.action, MissionObjectiveAction::Shoot { solid, .. } if solid == g.nodes[1].solid)
    );
    for node in 1..4 {
        shoot_node(&mut s, id, node);
    }
    let after = facts(&s);
    assert!(after.node_hp.iter().all(|hp| *hp == 0));
    assert!(after.machine_fallen);
    assert_eq!(after.completed.len(), 5);
    assert_eq!(s.state.map.m08_stage(), 2);
    assert!(s.state.map.arena().solids[g.machine].bottom < 0.01);
    s.state
        .mission_state()
        .unwrap()
        .validate(s.state.tick)
        .unwrap();
}

#[test]
fn m08_full_seeded_clear_departs_with_released_captives_and_retry_restores_entry() {
    let (mut s, id) = fixture();
    let g = s.state.map.m08_geometry().unwrap();
    for group in 0..3 {
        clear(&mut s, id, group, Some(arrival_feet(&g.objectives[group])));
    }
    clear(&mut s, id, 3, None);
    advance(&mut s, 1);
    place(&mut s, id, arrival_feet(&g.objectives[3]));
    advance(&mut s, 2);
    place(&mut s, id, arrival_feet(&g.bays));
    advance(&mut s, 2);
    for node in 0..4 {
        shoot_node(&mut s, id, node);
    }
    clear(&mut s, id, 4, Some(arrival_feet(&g.objectives[4])));
    assert!(facts(&s).transfer_evidence);
    clear(&mut s, id, 5, Some(arrival_feet(&g.objectives[5])));
    assert_eq!(facts(&s).completed.len(), 7);
    // A fresh aimed Use with the party aboard departs.
    place(&mut s, id, g.departure.approach);
    let point = g
        .departure
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    s.state.set_action(
        id,
        Action {
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    advance(&mut s, 2);
    assert!(!s.state.mission_state().unwrap().prompts.is_empty());
    s.state.set_action(
        id,
        Action {
            interact: true,
            look_at: Some(LookAt {
                x: Some(point[0]),
                y: Some(point[1]),
                z: Some(point[2]),
                player_id: None,
            }),
            ..Default::default()
        },
    );
    advance(&mut s, 2);
    let state = s.state.mission_state().unwrap();
    assert_eq!(state.phase, MissionPhase::Departed);
    let done = state.m08.unwrap();
    assert!(done.captives_evacuated && done.custody_released);
    assert_eq!(done.completed.last().unwrap(), "party_departed");

    // A party wipe returns the archive to its entry world and facts.
    let (mut s, id) = fixture();
    for group in 0..3 {
        clear(&mut s, id, group, Some(arrival_feet(&g.objectives[group])));
    }
    clear(&mut s, id, 3, None);
    advance(&mut s, 1);
    assert_eq!(s.state.map.m08_stage(), 1);
    let attempt = s.state.mission_state().unwrap().attempt;
    if let Some(p) = s.state.players.iter_mut().find(|p| p.id == id) {
        p.hp = 0;
        p.respawn_timer = Some(60);
    }
    advance(&mut s, 3);
    if let Some(p) = s.state.players.iter_mut().find(|p| p.id == id) {
        p.hp = 100;
        p.respawn_timer = None;
    }
    advance(&mut s, 2);
    let state = s.state.mission_state().unwrap();
    assert!(state.attempt > attempt);
    assert_eq!(s.state.map.m08_stage(), 0, "the seal closes again on retry");
    let reset = state.m08.unwrap();
    assert!(reset.completed.is_empty() && !reset.seal_open);
    assert!(reset.node_hp.iter().all(|hp| *hp == M08_NODE_HP));
}

#[test]
fn m08_wire_refuses_inconsistent_facts() {
    let (s, _) = fixture();
    let state = s.state.mission_state().unwrap();
    state.validate(s.state.tick).unwrap();
    let forge = |f: &dyn Fn(&mut crate::protocol::M08ObjectiveState)| {
        let mut bad = state.clone();
        f(bad.m08.as_mut().unwrap());
        bad.validate(s.state.tick)
    };
    assert!(
        forge(&|f| f.node_hp[0] = 10).is_err(),
        "nodes take no damage early"
    );
    assert!(forge(&|f| f.seal_open = true).is_err());
    assert!(forge(&|f| f.machine_fallen = true).is_err());
    assert!(forge(&|f| f.custodian_joined = true).is_err());
    assert!(forge(&|f| f.custody_released = true).is_err());
    assert!(forge(&|f| f.captives_evacuated = true).is_err());
    assert!(forge(&|f| f.node_hp.push(50)).is_err());
    assert!(forge(&|f| f.completed.push("mines_cleared".into())).is_err());
    let mut wrong_mission = state.clone();
    wrong_mission.m06 = None;
    wrong_mission.id = MissionId::PortOfEntry;
    assert!(wrong_mission.validate(s.state.tick).is_err());
}

#[test]
fn m08_post_pair_walks_into_the_corridor_mines() {
    let (mut s, id) = fixture();
    let g = s.state.map.m08_geometry().unwrap();
    for group in 0..2 {
        clear(&mut s, id, group, Some(arrival_feet(&g.objectives[group])));
    }
    // Take the cage mines: entering the alcove dispatches the distant post.
    place(&mut s, id, [-18.5, 3.0, 14.5]);
    advance(&mut s, 2);
    let carried = |s: &GameSession| {
        s.state
            .players
            .iter()
            .find(|p| p.id == id)
            .unwrap()
            .inventory
            .mines()
    };
    assert_eq!(carried(&s), 4);
    let face_yaw = |s: &mut GameSession, feet: [f32; 3], yaw: f32| {
        place(s, id, feet);
        let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
        p.yaw = yaw;
        p.pitch = 0.0;
    };
    let face = |s: &mut GameSession, feet: [f32; 3]| face_yaw(s, feet, 0.0);
    let throw = |s: &mut GameSession| {
        s.state.set_action(
            id,
            Action {
                place_mine: true,
                ..Default::default()
            },
        );
        advance(s, 1);
        s.state.set_action(id, Action::default());
        advance(s, 16);
    };
    // As the tour does: one mine level down the corridor the post walks up,
    // a second level from the mouth, then back into the blind corner.
    face_yaw(&mut s, [-10.0, 3.0, 18.5], 1.5 * std::f32::consts::PI);
    throw(&mut s);
    face(&mut s, [-13.5, 3.0, 17.5]);
    throw(&mut s);
    assert_eq!(carried(&s), 2);
    let post_down = |s: &GameSession| {
        s.state
            .players
            .iter()
            .filter(|p| p.name.starts_with("post_sweeper_"))
            .all(|p| p.hp <= 0)
    };
    for _ in 0..900 {
        face(&mut s, [-17.5, 3.0, 15.5]);
        advance(&mut s, 1);
        if post_down(&s) {
            break;
        }
    }
    assert!(
        post_down(&s),
        "the post pair walked into the corridor mines"
    );
    let record = s.state.player_record(id).unwrap();
    assert_eq!(record.total.mines.kills, 2, "both fell to the mines");
    advance(&mut s, 8);
    assert!(
        s.state.snapshot().mines.is_empty(),
        "both mines sprang, so the route back out is clear"
    );
}

#[test]
fn m08_gallery_auditor_reaches_a_disabled_custody_sweeper() {
    let (mut s, id) = fixture();
    let g = s.state.map.m08_geometry().unwrap();
    for group in 0..3 {
        clear(&mut s, id, group, Some(arrival_feet(&g.objectives[group])));
    }
    place(&mut s, id, [18.0, 6.0, 2.0]);
    advance(&mut s, 2);
    let sweeper = s
        .state
        .players
        .iter()
        .find(|p| p.name == "upper_sweeper_middle")
        .unwrap()
        .id;
    if let Some(p) = s.state.players.iter_mut().find(|p| p.id == sweeper) {
        p.hp = 0;
        let feet = [p.x, p.y - PLAYER_FLOOR_Y, p.z];
        s.state.encounters.hit(p.id, feet, s.state.tick, true);
    }
    // Hide behind the east tower so the Auditor is free to channel.
    place(&mut s, id, [28.0, 3.0, -6.0]);
    let mut channel = None;
    for _ in 0..60 {
        advance(&mut s, 1);
        place(&mut s, id, [28.0, 3.0, -6.0]);
        if let Some(target) = s
            .state
            .snapshot()
            .auditors
            .iter()
            .find_map(|auditor| auditor.channel_target)
        {
            channel = Some(target);
            break;
        }
    }
    assert_eq!(
        channel,
        Some(sweeper),
        "the gallery Auditor reaches its own Sweeper"
    );
}

#[test]
fn m08_strict_authoring_rejects_roster_binding_seal_and_control_failures() {
    let original: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m08_custodian_of_record.json")).unwrap();
    for failure in [
        "unknown",
        "order",
        "auditor",
        "mines",
        "unsealed",
        "machine",
        "control",
        "panel",
        "optional",
        "ring_auditor",
    ] {
        let mut d = original.clone();
        match failure {
            "unknown" => d["m08"]["phantom"] = serde_json::json!(true),
            "order" => d["m08"]["objectives"][0]["id"] = serde_json::json!("exit_cleared"),
            "auditor" => d["encounters"][3]["enemies"][0]["kind"] = serde_json::json!("clerk"),
            "mines" => d["encounters"][2]["enemies"][0]["kind"] = serde_json::json!("clerk"),
            // A seal that never lifts leaves nothing to prepare.
            "unsealed" => {
                d["m08"]["seal"]["open"] = serde_json::json!({"min":[-6.3,6,-16],"max":[-6,9,-12]})
            }
            "machine" => d["m08"]["machine"]["solid"] = serde_json::json!("node_north_west"),
            "control" => d["m08"]["departure"]["approach"] = serde_json::json!([0, 0, 24]),
            // Only the service ring may follow the six, and it repairs nothing.
            "optional" => d["encounters"][6]["id"] = serde_json::json!("side_room"),
            "ring_auditor" => {
                d["encounters"][6]["enemies"][0]["kind"] = serde_json::json!("auditor")
            }
            _ => {
                d["decorations"][0]["kind"] = serde_json::json!("m08_seal_open");
            }
        }
        assert!(
            AuthoredMap::read(serde_json::to_vec(&d).unwrap().as_slice()).is_err(),
            "{failure}"
        );
    }
    // Registered archive panels belong to the archive.
    let mut range: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/test/custody-range.json")).unwrap();
    range["decorations"] = serde_json::json!([
        {"solid":"bay_desk","face":"north","center":[0,0],"size":[1,0.5],"kind":"m08_registry"}
    ]);
    assert!(AuthoredMap::read(serde_json::to_vec(&range).unwrap().as_slice()).is_err());
}

#[test]
fn m08_controller_follows_forward_stages_and_steers_each_step() {
    let (mut s, id) = fixture();
    let map = s.state.map.clone();
    let g = map.m08_geometry().unwrap();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m08(
            Some(&g),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    client
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    let mut nav = crate::navigation::Navigator::default();
    let walking = client.steer(
        &mut nav,
        map.navigation(),
        id,
        &s.state.snapshot(),
        Action::default(),
    );
    assert!(walking.forward || walking.yaw.is_some() || walking.look_at.is_some());
    // The stage flags move with the world and return on a retry; the facts
    // must then agree with the bound stage.
    let mut lifted = g.clone();
    lifted.seal_open = true;
    let mut back = client.clone();
    back.replace_map_with_m08(
        Some(&lifted),
        map.half_extent(),
        &map.arena().solids,
        map.presentation_ref(),
    )
    .unwrap();
    let lifted_facts = s.state.mission_state().unwrap();
    assert!(
        back.observe(s.state.tick, lifted_facts).is_err(),
        "sealed facts on a lifted map"
    );
    back.replace_map_with_m08(
        Some(&g),
        map.half_extent(),
        &map.arena().solids,
        map.presentation_ref(),
    )
    .unwrap();
    let mut moved = g.clone();
    moved.companion_start[0] += 1.0;
    let mut other = client.clone();
    assert!(other
        .replace_map_with_m08(
            Some(&moved),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref()
        )
        .is_err());
    // A forged current objective is refused against the bound map.
    let mut forged = s.state.mission_state().unwrap();
    forged.m08.as_mut().unwrap().current = Some(g.objectives[2].clone());
    assert!(client.observe(s.state.tick, forged).is_err());
    // On the machine step the controller fires at the next node from its approach.
    for group in 0..3 {
        clear(&mut s, id, group, Some(arrival_feet(&g.objectives[group])));
    }
    clear(&mut s, id, 3, None);
    advance(&mut s, 1);
    place(&mut s, id, arrival_feet(&g.objectives[3]));
    advance(&mut s, 2);
    let staged = s.state.map.clone();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_m08(
            staged.m08_geometry().as_ref(),
            staged.half_extent(),
            &staged.arena().solids,
            staged.presentation_ref(),
        )
        .unwrap();
    client
        .observe(s.state.tick, s.state.mission_state().unwrap())
        .unwrap();
    place(&mut s, id, g.nodes[0].approach);
    let mut nav = crate::navigation::Navigator::default();
    let shot = client.steer(
        &mut nav,
        staged.navigation(),
        id,
        &s.state.snapshot(),
        Action::default(),
    );
    assert!(shot.fire);
    let aim = shot.look_at.unwrap();
    assert_eq!(
        [aim.x, aim.y, aim.z],
        [
            Some(g.nodes[0].aim[0]),
            Some(g.nodes[0].aim[1]),
            Some(g.nodes[0].aim[2])
        ]
    );
}
