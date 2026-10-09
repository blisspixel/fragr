use fragr_server::maps::{AuthoredMap, RuntimeMap};
use fragr_server::movement::EYE_HEIGHT;
use fragr_server::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use fragr_server::protocol::{
    Action, AmmoPool, CampaignActor, EnemyKind, LookAt, Role, WeaponType,
};
use fragr_server::session::GameSession;
use fragr_server::sim::PLAYER_FLOOR_Y;
use std::collections::HashSet;
use uuid::Uuid;

const SOURCE: &[u8] = include_bytes!("../maps/test/assessor_foundation_development.json");

#[test]
fn assessor_lesson_has_actual_hover_clearance_finite_stock_and_grounded_flanks() {
    let map = AuthoredMap::read(SOURCE).unwrap();
    let world = RuntimeMap::Authored(map);
    assert_eq!(world.id(), 1043);
    assert!(world.requires_assessor_contract());
    assert!(world.requires_arc_contract());
    let doc: serde_json::Value = serde_json::from_slice(SOURCE).unwrap();
    let point =
        |value: &serde_json::Value| std::array::from_fn(|i| value[i].as_f64().unwrap() as f32);
    let start = point(&doc["spawns"][0]["feet"]);
    let mut routes = 0;
    for destination in doc["landmarks"]
        .as_array()
        .unwrap()
        .iter()
        .chain(doc["supplies"].as_array().unwrap())
    {
        let end = point(&destination["feet"]);
        for (from, to) in [(start, end), (end, start)] {
            assert_eq!(
                world.navigation().route(from, to, SEARCH_LIMIT).status,
                RouteStatus::Complete,
                "route {from:?} -> {to:?}"
            );
            routes += 1;
        }
    }
    assert_eq!(routes, 16);
    assert_eq!(doc["encounters"].as_array().unwrap().len(), 1);
    let enemy = &doc["encounters"][0]["enemies"][0];
    assert_eq!(enemy["kind"], "assessor");
    assert!(enemy["hover"].is_object());
    assert_eq!(
        doc["supplies"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|s| s["grant"]["weapon"] == "arc")
            .count(),
        1
    );
}

#[derive(Default)]
struct Evidence {
    shots: usize,
    launches: HashSet<u32>,
    impacts: HashSet<u32>,
    reload_deadlines: HashSet<u64>,
    killed: bool,
}

fn advance(
    session: &mut GameSession,
    id: Uuid,
    goals: &[[f32; 3]],
    fight: bool,
    evidence: &mut Evidence,
) {
    let mut navigator = Navigator::default();
    let mut next = 0;
    for _ in 0..1600 {
        let state = &session.state;
        let me = state.players.iter().find(|p| p.id == id).unwrap();
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        assert!(
            me.hp > 0,
            "finite ordinary-input drone lesson died at {feet:?}"
        );
        while next < goals.len()
            && (feet[0] - goals[next][0]).hypot(feet[2] - goals[next][2]) < 0.35
        {
            next += 1;
        }
        if next == goals.len() && (!fight || evidence.killed) {
            session.state.set_action(id, Action::default());
            return;
        }
        let loadout = me.inventory.state(id, me.weapon, state.tick).unwrap();
        for magazine in &loadout.loaded {
            if magazine.weapon == WeaponType::Arc {
                if let Some(deadline) = magazine.ready_at {
                    evidence.reload_deadlines.insert(deadline);
                }
            }
        }
        let target = state
            .players
            .iter()
            .find(|p| p.name == "court_assessor" && p.hp > 0);
        let eye = [feet[0], feet[1] + EYE_HEIGHT, feet[2]];
        let target = target.filter(|p| {
            fight
                && feet[2] >= -7.5
                && fragr_server::combat::line_of_sight(
                    eye,
                    [p.x, p.y - PLAYER_FLOOR_Y + 0.6, p.z],
                    &state.current_arena().solids,
                )
        });
        let mut action = if let Some(target) = target {
            // Observe and dodge the first committed volley before returning
            // fire, so the lesson demonstrates travel as well as the counter.
            Action {
                weapon_swap: Some(WeaponType::Arc),
                fire: evidence.launches.len() >= 3,
                left: (state.tick / 12).is_multiple_of(2),
                right: !(state.tick / 12).is_multiple_of(2),
                look_at: Some(LookAt {
                    player_id: None,
                    x: Some(target.x),
                    y: Some(target.y - PLAYER_FLOOR_Y + 0.6),
                    z: Some(target.z),
                }),
                ..Action::default()
            }
        } else {
            navigator.steer(
                state.map.navigation(),
                feet,
                NavigationGoal {
                    feet: *goals.get(next).unwrap_or_else(|| goals.last().unwrap()),
                    combat: false,
                },
                Action {
                    weapon_swap: loadout.owns(WeaponType::Arc).then_some(WeaponType::Arc),
                    ..Action::default()
                },
                state.tick,
                true,
            )
        };
        if loadout.owns(WeaponType::Arc) && loadout.shots(WeaponType::Arc) == Some(0) {
            action.fire = false;
            action.reload = state.tick.is_multiple_of(2);
        }
        assert!(!action.jump, "the lesson keeps an ordinary walking route");
        session.state.set_action(id, action);
        session.tick_messages(0.05);
        let snapshot = session.state.snapshot();
        for round in snapshot.assessor_canisters {
            evidence.launches.insert(round.id);
        }
        for blast in snapshot.explosions {
            if blast.radius == 3.0 {
                evidence.impacts.insert(blast.id);
            }
        }
        for shot in &session.state.shot_results {
            assert_eq!(
                shot.shooter_id, id,
                "drone never substitutes a hitscan Fists ray"
            );
            evidence.shots += 1;
            if shot.killed && shot.target.as_deref() == Some("court_assessor") {
                evidence.killed = true;
            }
        }
    }
    panic!(
        "drone lesson stalled, kills={}, shots={}, next={next}",
        evidence.killed, evidence.shots
    );
}

#[test]
fn actual_human_finds_cells_dodges_visible_volley_reloads_and_downs_assessor() {
    let mut session = GameSession::with_authored_map(AuthoredMap::read(SOURCE).unwrap());
    session.state.seed(1043);
    let id = Uuid::from_u128(1043);
    session
        .state
        .add_player(id, "Canister court visitor".into(), Role::Human);
    session.state.start_round();
    session.state.arm_joined_magazines(id);
    let mut evidence = Evidence::default();
    advance(
        &mut session,
        id,
        &[[-2.0, 0.0, -18.0], [-10.0, 0.0, -17.0]],
        false,
        &mut evidence,
    );
    let me = session.state.players.iter().find(|p| p.id == id).unwrap();
    let found = me
        .inventory
        .state(id, me.weapon, session.state.tick)
        .unwrap();
    assert!(found.owns(WeaponType::Arc));
    assert_eq!(
        (found.ammo(AmmoPool::Cells), found.shots(WeaponType::Arc)),
        (40, Some(12))
    );
    advance(
        &mut session,
        id,
        &[[0.0, 0.0, -6.5], [0.0, 0.0, 0.0]],
        true,
        &mut evidence,
    );
    advance(
        &mut session,
        id,
        &[[0.0, 0.0, 10.0], [0.0, 0.0, 20.0]],
        false,
        &mut evidence,
    );
    let record = session.state.player_record(id).unwrap();
    assert_eq!(
        (
            record.total.weapon(WeaponType::Arc).kills,
            record.total.weapon(WeaponType::Arc).hp_damage
        ),
        (1, 240)
    );
    assert_eq!(record.total.deaths, 0);
    assert!(
        !evidence.reload_deadlines.is_empty(),
        "twelve-round magazine needs an actual reload"
    );
    assert!((14..=40).contains(&evidence.shots));
    assert!(
        evidence.launches.len() >= 3,
        "native encounter must actually launch the visible three-round volley"
    );
    assert!(
        !evidence.impacts.is_empty(),
        "finite rounds must reach actual contact"
    );
    let drone = session.state.players.iter().find(|p| {
        matches!(
            p.campaign,
            Some(CampaignActor::Union {
                kind: EnemyKind::Assessor,
                ..
            })
        )
    });
    if let Some(drone) = drone {
        assert_eq!(
            session
                .state
                .player_record(drone.id)
                .unwrap()
                .total
                .weapon(WeaponType::Fists)
                .attacks,
            0
        );
    }
    println!("Assessor actual finite human lesson: ticks={}, shots={}, reloads={}, launches={}, contacts={}, HP loss={}, armor loss={}",session.state.tick,evidence.shots,evidence.reload_deadlines.len(),evidence.launches.len(),evidence.impacts.len(),record.total.hp_lost,record.total.armor_lost);
}
