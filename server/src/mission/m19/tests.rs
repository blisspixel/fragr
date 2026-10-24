use super::*;
use crate::encounters::enemy::paver::{INTERRUPT_DAMAGE, WORK_DAMAGE};
use crate::maps::{AuthoredMap, RuntimeMap};
use crate::movement::jetpack::{hop_input, FUEL_MAX};
use crate::protocol::{
    Action, CampaignActor, CampaignDifficulty, EnemyKind, EnemyPhase, LookAt, MissionReady, Role,
    ServerMessage, UseTarget,
};
use crate::session::GameSession;
use std::sync::{Arc, OnceLock};

const MAP: &str = include_str!("../../../maps/m19-planned-works.json");

fn map() -> Arc<AuthoredMap> {
    static MAP_CACHE: OnceLock<Arc<AuthoredMap>> = OnceLock::new();
    MAP_CACHE
        .get_or_init(|| AuthoredMap::read(MAP.as_bytes()).unwrap())
        .clone()
}

fn session(role: Role, difficulty: CampaignDifficulty) -> (GameSession, Uuid) {
    let mut s = GameSession::with_authored_map(map());
    s.state.set_campaign_difficulty(difficulty).unwrap();
    s.state.use_replay_ids();
    s.state.seed(1019);
    let id = Uuid::from_u128(1019);
    s.state.add_player(id, "Low Water operative".into(), role);
    if role == Role::Human {
        s.state.arm_joined_magazines(id);
    }
    assert!(s.state.acknowledge_mission(
        id,
        MissionReady {
            id: MissionId::PlannedWorks,
            attempt: 1,
        }
    ));
    (s, id)
}

/// One tick, then the wire contract: decorations, the reader and validation.
fn tick(s: &mut GameSession) -> Vec<ServerMessage> {
    let messages = s.tick_messages(0.05);
    let map = &s.state.map;
    crate::protocol::validate_decorations(
        &map.presentation_ref().unwrap().decorations,
        &map.arena().solids,
    )
    .unwrap();
    let mut reader = crate::mission::MissionClient::default();
    reader
        .replace_map_with_id(
            map.id(),
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    reader
        .replace_map_with_m19(
            map.m19_geometry().as_ref(),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let state = s.state.mission_state().unwrap();
    state.validate(s.state.tick).unwrap();
    reader.observe(s.state.tick, state).unwrap();
    let snapshot = s.state.snapshot();
    for strip in &snapshot.paver_strips {
        strip.validate(snapshot.tick, map.half_extent()).unwrap();
    }
    messages
}

fn facts(s: &GameSession) -> M19ObjectiveState {
    s.state.mission_state().unwrap().m19.unwrap()
}

fn place(s: &mut GameSession, id: Uuid, feet: [f32; 3]) {
    let p = s.state.players.iter_mut().find(|p| p.id == id).unwrap();
    [p.x, p.y, p.z] = [feet[0], feet[1] + PLAYER_FLOOR_Y, feet[2]];
    p.vy = 0.0;
    p.clear_input();
}

fn feet_of(s: &GameSession, id: Uuid) -> [f32; 3] {
    let p = s.state.players.iter().find(|p| p.id == id).unwrap();
    [p.x, p.y - PLAYER_FLOOR_Y, p.z]
}

fn interact(s: &mut GameSession, id: Uuid, target: &UseTarget) {
    let point = target
        .point(
            s.state.map.presentation_ref().unwrap(),
            &s.state.map.arena().solids,
        )
        .unwrap();
    place(s, id, target.approach);
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
    tick(s);
}

fn clear_enemies(s: &mut GameSession) {
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if !p.is_participant() && p.hp > 0 {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}

/// Defeat one authored group's living members through ordinary damage.
fn clear_group(s: &mut GameSession, group: usize) {
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if p.hp > 0 && s.state.encounters.enemy_in_group(p.id, group) {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
}

fn arrival_feet(g: &crate::protocol::M19MapGeometry, index: usize) -> [f32; 3] {
    match &g.objectives[index].action {
        crate::protocol::MissionObjectiveAction::Arrival { feet, .. } => *feet,
        _ => panic!("objective {index} is not an arrival"),
    }
}

/// Clear every group present and arrive, objective by objective, until `index`
/// objectives are complete.
fn advance_to(s: &mut GameSession, id: Uuid, index: usize) {
    let g = s.state.map.m19_geometry().unwrap();
    while facts(s).completed.len() < index {
        let n = facts(s).completed.len();
        if n == 0 {
            interact(s, id, &g.stores);
        } else {
            let group = match n {
                2 => Some(0),
                3 => Some(1),
                4 => Some(2),
                6 => Some(3),
                _ => None,
            };
            for _ in 0..3 {
                tick(s);
                if let Some(group) = group {
                    clear_group(s, group);
                }
            }
            place(s, id, arrival_feet(&g, n));
            tick(s);
        }
        assert_eq!(facts(s).completed.len(), n + 1, "stuck at objective {n}");
    }
}

fn lesson_paver(s: &GameSession) -> Uuid {
    s.state
        .players
        .iter()
        .find(|p| {
            p.hp > 0
                && matches!(
                    p.campaign,
                    Some(CampaignActor::Hostile {
                        kind: EnemyKind::Paver,
                        ..
                    })
                )
        })
        .map(|p| p.id)
        .unwrap()
}

fn phase(s: &GameSession, id: Uuid) -> EnemyPhase {
    match s
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .campaign
    {
        Some(CampaignActor::Hostile { phase, .. }) => phase,
        _ => panic!("not a Union actor"),
    }
}

#[test]
fn canonical_worlds_publish_the_closed_and_open_waterworks() {
    let world = RuntimeMap::Authored(map());
    assert_eq!(world.id(), 1019);
    assert_eq!(world.name(), "Planned Works");
    assert_eq!(world.campaign_mission_id(), Some(MissionId::PlannedWorks));
    let g = world.m19_geometry().unwrap();
    assert!(!g.gate_open);
    assert_eq!(world.jetpack_ceiling(), g.jetpack_ceiling);
    let open = world.prepared_m19_world(1).unwrap();
    assert!(open.m19_geometry().unwrap().gate_open);
    assert!(world.prepared_m19_world(2).is_none());
    let trench = arrival_feet(&g, 7);
    assert_ne!(
        world
            .navigation()
            .route(
                trench,
                g.departure.approach,
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        crate::navigation::RouteStatus::Complete,
        "the closed gate holds the boarding"
    );
    assert_eq!(
        open.navigation()
            .route(
                trench,
                g.departure.approach,
                crate::navigation::SEARCH_LIMIT
            )
            .status,
        crate::navigation::RouteStatus::Complete
    );
    // Strict authoring: every M19 panel kind belongs to Planned Works.
    let mut foreign: serde_json::Value = serde_json::from_str(MAP).unwrap();
    foreign.as_object_mut().unwrap().remove("m19");
    foreign["encounters"] = serde_json::json!([]);
    let error = AuthoredMap::read(serde_json::to_vec(&foreign).unwrap().as_slice()).unwrap_err();
    assert!(
        error.to_string().contains("M19 registered panels"),
        "{error}"
    );
    // A ledge at the jetpack ceiling is refused.
    let mut ledge: serde_json::Value = serde_json::from_str(MAP).unwrap();
    let ceiling = ledge["m19"]["jetpack_ceiling"].as_f64().unwrap();
    ledge["solids"][0]["max"][1] = serde_json::json!(ceiling + 0.2);
    let error = AuthoredMap::read(serde_json::to_vec(&ledge).unwrap().as_slice()).unwrap_err();
    assert!(error.to_string().contains("ceiling"), "{error}");
    // A hop that cannot land with one pack is refused.
    let mut far: serde_json::Value = serde_json::from_str(MAP).unwrap();
    far["m19"]["jet_hops"][0]["landing"][2] =
        serde_json::json!(far["m19"]["jet_hops"][0]["landing"][2].as_f64().unwrap() + 30.0);
    assert!(AuthoredMap::read(serde_json::to_vec(&far).unwrap().as_slice()).is_err());
}

#[test]
fn every_hostile_in_low_water_is_the_inheritance_on_the_wire() {
    let (mut s, id) = session(Role::Human, CampaignDifficulty::Standard);
    let check = |s: &GameSession| {
        let mut kinds = Vec::new();
        for player in s.state.snapshot().players.iter().filter(|p| p.id != id) {
            let Some(CampaignActor::Hostile { kind, control, .. }) = player.campaign else {
                continue;
            };
            kinds.push(kind);
            let wire = serde_json::to_value(player.campaign.unwrap()).unwrap();
            assert_eq!(wire["side"], "inheritance", "{wire}");
            if kind == EnemyKind::Paver {
                assert_eq!(control, crate::protocol::ControlDomain::Restoration);
                assert_eq!(wire["control"], "restoration");
            } else {
                assert_eq!(control, crate::protocol::ControlDomain::Absorbed);
                assert_eq!(wire["control"], "absorbed");
            }
        }
        kinds
    };
    tick(&mut s);
    assert!(
        check(&s).contains(&EnemyKind::Sweeper),
        "the crossing is placed"
    );
    advance_to(&mut s, id, 3);
    tick(&mut s);
    assert!(
        check(&s).contains(&EnemyKind::Paver),
        "the lesson Paver is placed"
    );
    // A bot left under Union control, a Union Paver and an absorbed person
    // are all refused before the map loads.
    for (index, control) in [(0, "union"), (5, "union"), (0, "restoration")] {
        let mut wrong: serde_json::Value = serde_json::from_str(MAP).unwrap();
        let mut placements: Vec<&mut serde_json::Value> = wrong["encounters"]
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .flat_map(|group| group["enemies"].as_array_mut().unwrap().iter_mut())
            .collect();
        placements[index]["control"] = serde_json::json!(control);
        assert!(
            AuthoredMap::read(serde_json::to_vec(&wrong).unwrap().as_slice()).is_err(),
            "{index} {control}"
        );
    }
    let mut absorbed_paver: serde_json::Value = serde_json::from_str(MAP).unwrap();
    absorbed_paver["encounters"][1]["enemies"][0]["control"] = serde_json::json!("absorbed");
    let error =
        AuthoredMap::read(serde_json::to_vec(&absorbed_paver).unwrap().as_slice()).unwrap_err();
    assert!(error.to_string().contains("cannot be under"), "{error}");
}

#[test]
fn the_stores_lend_a_pack_only_by_a_real_use_and_a_reset_returns_it() {
    let (mut s, id) = session(Role::Human, CampaignDifficulty::Standard);
    tick(&mut s);
    let g = s.state.map.m19_geometry().unwrap();
    // Pressing use away from the counter lends nothing.
    place(&mut s, id, arrival_feet(&g, 1));
    s.state.set_action(
        id,
        Action {
            interact: true,
            ..Default::default()
        },
    );
    tick(&mut s);
    assert!(!facts(&s).jetpack_taken);
    assert!(s.state.snapshot().jetpacks.is_empty());
    let prompts = s.state.mission_state().unwrap().prompts;
    assert!(prompts.is_empty());
    interact(&mut s, id, &g.stores);
    let f = facts(&s);
    assert_eq!(f.completed, vec!["concourse_stores"]);
    assert!(f.jetpack_taken);
    let packs = s.state.snapshot().jetpacks;
    assert_eq!(packs.len(), 1);
    assert_eq!((packs[0].player_id, packs[0].fuel), (id, FUEL_MAX));
    // The predicting human receives the fuel on the movement ack.
    s.state.set_action(
        id,
        Action {
            seq: Some(7),
            yaw: Some(0.0),
            ..Default::default()
        },
    );
    tick(&mut s);
    assert!(s
        .state
        .input_acks()
        .iter()
        .any(|(player, message)| *player == id
            && matches!(
                message,
                ServerMessage::Ack { movement: Some(m), .. } if m.jet_fuel == Some(FUEL_MAX)
            )));
    // Death of the whole party resets the level: the pack goes back.
    let index = s.state.players.iter().position(|p| p.id == id).unwrap();
    s.state.environmental_self_damage(index, 500);
    for _ in 0..3 {
        tick(&mut s);
    }
    assert!(s
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .jetpack
        .is_none());
    assert!(facts(&s).completed.is_empty());
}

#[test]
fn the_broken_stair_needs_the_pack_and_the_authored_hop_lands_on_the_gallery() {
    let (mut s, id) = session(Role::Agent, CampaignDifficulty::Standard);
    tick(&mut s);
    let g = s.state.map.m19_geometry().unwrap();
    let hop = g.jet_hops[0];
    // Without a pack the same held inputs only jump: the gallery is out of reach.
    place(&mut s, id, hop.launch);
    for _ in 0..80 {
        let feet = feet_of(&s, id);
        let input = hop_input(
            crate::movement::MoveState {
                x: feet[0],
                z: feet[2],
                y: feet[1],
                vx: 0.0,
                vz: 0.0,
                vy: 0.0,
                yaw: 0.0,
            },
            hop.landing,
        );
        s.state.set_action(
            id,
            Action {
                forward: input.forward,
                jump: input.jump,
                yaw: Some(input.yaw),
                ..Default::default()
            },
        );
        tick(&mut s);
        assert!(feet_of(&s, id)[1] < hop.landing[1] - 1.0);
    }
    interact(&mut s, id, &g.stores);
    place(&mut s, id, hop.launch);
    let mut burned = false;
    for _ in 0..crate::movement::jetpack::HOP_TICKS {
        if facts(&s).completed.len() == 2 {
            break;
        }
        let feet = feet_of(&s, id);
        let input = hop_input(
            crate::movement::MoveState {
                x: feet[0],
                z: feet[2],
                y: feet[1],
                vx: 0.0,
                vz: 0.0,
                vy: 0.0,
                yaw: 0.0,
            },
            hop.landing,
        );
        s.state.set_action(
            id,
            Action {
                forward: input.forward,
                jump: input.jump,
                yaw: Some(input.yaw),
                ..Default::default()
            },
        );
        tick(&mut s);
        burned |= s.state.snapshot().jetpacks[0].thrusting;
        assert!(feet_of(&s, id)[1] <= g.jetpack_ceiling + 1e-4);
    }
    assert!(burned);
    assert_eq!(
        facts(&s).completed,
        vec!["concourse_stores", "broken_stair"]
    );
}

#[test]
fn arrivals_wait_for_their_group_and_the_crossing_receipt_follows_the_clear() {
    let (mut s, id) = session(Role::Agent, CampaignDifficulty::Assisted);
    tick(&mut s);
    let g = s.state.map.m19_geometry().unwrap();
    advance_to(&mut s, id, 2);
    // Standing at the concourse exit with the crossing guard alive does nothing.
    place(&mut s, id, arrival_feet(&g, 2));
    for _ in 0..5 {
        tick(&mut s);
    }
    assert_eq!(facts(&s).completed.len(), 2);
    assert!(!facts(&s).challenges.crossing_cleared);
    clear_group(&mut s, 0);
    for _ in 0..3 {
        tick(&mut s);
    }
    place(&mut s, id, arrival_feet(&g, 2));
    tick(&mut s);
    let f = facts(&s);
    assert_eq!(f.completed.len(), 3);
    assert!(f.challenges.crossing_cleared);
    assert!(f.brief_completed, "Assisted asks only for the crossing");
    // The market group is already placed but the street lesson gates it.
    place(&mut s, id, arrival_feet(&g, 4));
    tick(&mut s);
    assert_eq!(facts(&s).completed.len(), 3);
}

/// The free controller arriving while one straggler of the gating group still
/// stands across the open market walks to it. Seeing it was not enough: a
/// sighted hunt that held position waited on a dormant sweeper forever.
#[test]
fn an_arrival_hunt_walks_to_a_visible_straggler_out_of_engagement_range() {
    use crate::navigation::{Navigation, Navigator};
    let (mut s, id) = session(Role::Agent, CampaignDifficulty::Assisted);
    tick(&mut s);
    let g = s.state.map.m19_geometry().unwrap();
    advance_to(&mut s, id, 4);
    for _ in 0..3 {
        tick(&mut s);
    }
    for i in 0..s.state.players.len() {
        let p = &s.state.players[i];
        if p.hp > 0
            && ["market_paver_east", "market_paver_west", "market_heavy"].contains(&p.name.as_str())
        {
            let damage = p.hp + p.armor;
            s.state.environmental_self_damage(i, damage);
        }
    }
    place(&mut s, id, arrival_feet(&g, 4));
    tick(&mut s);
    let straggler = s
        .state
        .players
        .iter()
        .find(|p| p.name == "market_sweeper" && p.hp > 0)
        .map(|p| p.id)
        .unwrap();
    let gap = |s: &GameSession| {
        let me = feet_of(s, id);
        let them = feet_of(s, straggler);
        (me[0] - them[0]).hypot(me[2] - them[2])
    };
    let start = gap(&s);
    assert!(
        start > 30.0,
        "the straggler starts across the market: {start}"
    );
    let map = s.state.map.clone();
    let navigation = Navigation::shared(map.arena().clone()).unwrap();
    let mut client = crate::mission::MissionClient::default();
    client
        .replace_map_with_id(
            map.id(),
            None,
            false,
            None,
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    client
        .replace_map_with_m19(
            map.m19_geometry().as_ref(),
            map.half_extent(),
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    let mut navigator = Navigator::default();
    let mut closest = start;
    for _ in 0..600 {
        client
            .observe(s.state.tick, s.state.mission_state().unwrap())
            .unwrap();
        let snapshot = s.state.snapshot();
        // No target filter engages a dormant sweeper this far away.
        let action = client.steer_with_equipment(
            &mut navigator,
            &navigation,
            id,
            &snapshot,
            Action::default(),
            None,
        );
        s.state.set_action(id, action);
        tick(&mut s);
        closest = closest.min(gap(&s));
        if closest < 12.0 {
            break;
        }
    }
    assert!(
        closest < 12.0,
        "the hunt must close from {start:.1} m to engagement range, reached {closest:.1} m"
    );
}

/// The lesson Paver prepares at a body in the street; returns its id.
fn street_lesson(difficulty: CampaignDifficulty) -> (GameSession, Uuid, Uuid) {
    let (mut s, id) = session(Role::Agent, difficulty);
    tick(&mut s);
    advance_to(&mut s, id, 3);
    let paver = lesson_paver(&s);
    let at = feet_of(&s, paver);
    // Six metres down the street from the projector, on its floor.
    let yaw = s.state.players.iter().find(|p| p.id == paver).unwrap().yaw;
    let stand = [at[0] + yaw.cos() * 6.0, at[1], at[2] + yaw.sin() * 6.0];
    place(&mut s, id, stand);
    for _ in 0..10 {
        tick(&mut s);
        if phase(&s, paver) == EnemyPhase::Windup {
            break;
        }
    }
    assert_eq!(phase(&s, paver), EnemyPhase::Windup);
    (s, id, paver)
}

/// A street-lesson snapshot with the strip being worked, for the client's
/// native receipts (the free controller usually puts every strip out first).
pub(super) fn working_strip_receipt() -> serde_json::Value {
    let (mut s, _, _) = street_lesson(CampaignDifficulty::Standard);
    for _ in 0..80 {
        tick(&mut s);
        let snapshot = s.state.snapshot();
        if snapshot.paver_strips.iter().any(|strip| strip.working) {
            return serde_json::to_value(ServerMessage::Snapshot(snapshot)).unwrap();
        }
    }
    panic!("the street lesson strip must be worked");
}

#[test]
fn a_worked_strip_damages_inside_spares_a_step_out_and_marks_severe() {
    // Standing inside through the whole work cycle.
    let (mut s, id, paver) = street_lesson(CampaignDifficulty::Severe);
    let strip = s.state.snapshot().paver_strips[0];
    assert!(!strip.working);
    assert_eq!(strip.owner_id, paver);
    let hp = s.state.players.iter().find(|p| p.id == id).unwrap().hp;
    let mut worked = false;
    for _ in 0..80 {
        tick(&mut s);
        worked |= s.state.snapshot().paver_strips.iter().any(|s| s.working);
        if phase(&s, paver) == EnemyPhase::Recovery {
            break;
        }
    }
    assert!(worked);
    let player = s.state.players.iter().find(|p| p.id == id).unwrap();
    assert_eq!(player.hp + player.armor, hp - 3 * WORK_DAMAGE);
    let f = facts(&s);
    assert!(f.challenges.strip_struck);
    assert!(!f.brief_completed);

    // The same tell with a lateral step before the work: untouched.
    let (mut s, id, paver) = street_lesson(CampaignDifficulty::Severe);
    let strip = s.state.snapshot().paver_strips[0];
    let feet = feet_of(&s, id);
    let lateral = strip.yaw + std::f32::consts::FRAC_PI_2;
    for side in [1.0_f32, -1.0] {
        let out = [
            feet[0] + lateral.cos() * side * 2.6,
            feet[1],
            feet[2] + lateral.sin() * side * 2.6,
        ];
        if !s
            .state
            .map
            .arena()
            .blocked_body_at(out[0], out[2], out[1], out[1])
        {
            place(&mut s, id, out);
            break;
        }
    }
    let hp = s.state.players.iter().find(|p| p.id == id).unwrap().hp;
    for _ in 0..80 {
        tick(&mut s);
        if phase(&s, paver) == EnemyPhase::Recovery {
            break;
        }
    }
    assert_eq!(phase(&s, paver), EnemyPhase::Recovery);
    assert_eq!(s.state.players.iter().find(|p| p.id == id).unwrap().hp, hp);
    assert!(!facts(&s).challenges.strip_struck);
}

#[test]
fn hits_during_the_preparation_put_the_strip_out_for_the_standard_brief() {
    let (mut s, id, paver) = street_lesson(CampaignDifficulty::Standard);
    // Damage below the threshold keeps the tell; crossing it puts it out.
    let index = s.state.players.iter().position(|p| p.id == paver).unwrap();
    s.state.players[index].hp -= INTERRUPT_DAMAGE / 2;
    tick(&mut s);
    assert_eq!(phase(&s, paver), EnemyPhase::Windup);
    assert!(!facts(&s).challenges.paver_interrupted);
    let index = s.state.players.iter().position(|p| p.id == paver).unwrap();
    s.state.players[index].hp -= INTERRUPT_DAMAGE;
    tick(&mut s);
    assert_eq!(phase(&s, paver), EnemyPhase::Hit);
    assert!(s.state.snapshot().paver_strips.is_empty());
    let hp = s.state.players.iter().find(|p| p.id == id).unwrap().hp;
    for _ in 0..20 {
        tick(&mut s);
    }
    assert_eq!(s.state.players.iter().find(|p| p.id == id).unwrap().hp, hp);
    let f = facts(&s);
    assert!(f.challenges.paver_interrupted);
    // Standard also needs the crossing, which this run cleared.
    assert!(f.brief_completed);
}

#[test]
fn the_trench_opens_the_waterworks_and_departure_needs_the_whole_party_aboard() {
    let (mut s, id) = session(Role::Agent, CampaignDifficulty::Standard);
    let partner = Uuid::from_u128(1920);
    s.state
        .add_player(partner, "Second operative".into(), Role::Agent);
    assert!(s.state.acknowledge_mission(
        partner,
        MissionReady {
            id: MissionId::PlannedWorks,
            attempt: 1,
        }
    ));
    tick(&mut s);
    advance_to(&mut s, id, 7);
    let closed = s.state.map.clone();
    assert!(!facts(&s).gate_open);
    assert!(facts(&s).latch_departed);
    let g = s.state.map.m19_geometry().unwrap();
    for _ in 0..3 {
        tick(&mut s);
        clear_enemies(&mut s);
    }
    place(&mut s, id, arrival_feet(&g, 7));
    let messages = tick(&mut s);
    assert_ne!(s.state.map, closed);
    assert!(facts(&s).gate_open);
    // The changed world reaches readers before the matching mission fact.
    let map_at = messages
        .iter()
        .position(|m| matches!(m, ServerMessage::MapInfo { m19: Some(g), .. } if g.gate_open));
    let mission_at = messages.iter().position(
        |m| matches!(m, ServerMessage::Mission { state, .. } if state.m19.as_ref().is_some_and(|f| f.gate_open)),
    );
    assert!(map_at.is_some() && mission_at.is_some() && map_at < mission_at);
    // One member aboard is not enough.
    interact(&mut s, id, &g.departure);
    assert!(s.state.mission_state().unwrap().prompts.is_empty());
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::InProgress
    );
    place(
        &mut s,
        partner,
        [g.boarding.min[0] + 1.0, 0.0, g.boarding.max[2] - 1.0],
    );
    s.state.set_action(id, Action::default());
    tick(&mut s);
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
    tick(&mut s);
    assert_eq!(
        s.state.mission.as_ref().unwrap().phase,
        MissionPhase::Departed
    );
    let f = facts(&s);
    assert_eq!(f.completed.len(), 9);
    assert!(f.current.is_none());
}
