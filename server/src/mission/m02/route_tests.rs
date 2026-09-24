//! The bundled M02 graybox, walked through the live session by the shared
//! wire controller. Players move only through ordinary actions.
use super::*;
use crate::maps::AuthoredSource;
use crate::movement::{Arena, BODY_HEIGHT, CONTACT_EPSILON};
use crate::navigation::{Navigation, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{Action, Role, ServerMessage, Snapshot};
use crate::session::GameSession;
use std::sync::Arc;

const ORDER: [&str; 5] = [
    "ward_reached",
    "correction_stopped",
    "companion_released",
    "loading_gate_open",
    "party_departed",
];

fn session() -> GameSession {
    GameSession::with_authored_map(
        AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap(),
    )
}

/// One wire reader: MapInfo rebuilds its own navigation, mission state is
/// validated by the shared controller, and the controller chooses every input.
struct Walker {
    id: Uuid,
    client: MissionClient,
    navigator: Navigator,
    world: Option<Arc<Navigation>>,
    snapshot: Option<Snapshot>,
    completed: Vec<String>,
    maps: usize,
}

impl Walker {
    fn new(id: Uuid) -> Self {
        Self {
            id,
            client: MissionClient::default(),
            navigator: Navigator::default(),
            world: None,
            snapshot: None,
            completed: Vec::new(),
            maps: 0,
        }
    }

    fn read(&mut self, messages: Vec<ServerMessage>) {
        for message in messages {
            match message {
                ServerMessage::MapInfo {
                    map_id,
                    half_extent,
                    solids,
                    presentation,
                    mission,
                    m02_objectives,
                    ..
                } => {
                    self.client
                        .replace_map_with_id(
                            map_id,
                            m02_objectives,
                            mission.as_ref(),
                            half_extent,
                            &solids,
                            presentation.as_ref(),
                        )
                        .unwrap();
                    self.world = Some(
                        Navigation::shared(Arena {
                            half: half_extent,
                            solids,
                        })
                        .unwrap(),
                    );
                    self.navigator.clear();
                    self.maps += 1;
                }
                ServerMessage::Mission { tick, state } => {
                    let m02 = state.m02.clone().unwrap();
                    assert!(
                        m02.completed.starts_with(&self.completed) || m02.completed.is_empty(),
                        "objectives must only extend in order or reset"
                    );
                    assert!(m02.completed.len() <= self.completed.len() + 1);
                    self.completed = m02.completed;
                    self.client.observe(tick, state).unwrap();
                }
                ServerMessage::Snapshot(snapshot) => self.snapshot = Some(snapshot),
                _ => {}
            }
        }
    }

    fn step(&mut self, session: &mut GameSession) {
        let messages = session.tick_messages(0.05);
        self.read(messages);
        if let Some(ready) = self.client.readiness(Some(self.id)) {
            assert!(session.state.acknowledge_mission(self.id, ready));
        }
        let (Some(world), Some(snapshot)) = (self.world.as_ref(), self.snapshot.as_ref()) else {
            return;
        };
        let action = self.client.steer(
            &mut self.navigator,
            world,
            self.id,
            snapshot,
            Action::default(),
        );
        session.state.set_action(self.id, action);
    }

    fn until(
        &mut self,
        session: &mut GameSession,
        limit: usize,
        done: impl Fn(&GameSession, &Self) -> bool,
    ) -> usize {
        for tick in 0..limit {
            if done(session, self) {
                return tick;
            }
            self.step(session);
            assert_body_clear(session, self.id);
        }
        panic!(
            "route stalled after {:?} at {:?}",
            self.completed,
            session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .map(|player| [player.x, player.y - PLAYER_FLOOR_Y, player.z])
        );
    }
}

fn assert_body_clear(session: &GameSession, id: Uuid) {
    let Some(player) = session.state.players.iter().find(|p| p.id == id) else {
        return;
    };
    let feet = player.y - PLAYER_FLOOR_Y;
    assert!(
        !session.state.map.arena().solids.iter().any(|solid| {
            solid.covers(player.x, player.z)
                && solid.top > feet + CONTACT_EPSILON
                && solid.bottom < feet + BODY_HEIGHT - CONTACT_EPSILON
        }),
        "body entered a volume at {:?}",
        [player.x, feet, player.z]
    );
}

fn departed(session: &GameSession, _: &Walker) -> bool {
    session.state.mission_departed()
}

#[test]
fn bundled_graybox_prepares_the_authored_chain_and_every_gate_world() {
    let map = crate::maps::RuntimeMap::Authored(
        AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap(),
    );
    let prepared = map.m02_objectives().unwrap();
    let ids: Vec<_> = (0..prepared.len())
        .map(|index| prepared.objective(index).unwrap().id.as_str())
        .collect();
    assert_eq!(ids, ORDER);
    for mask in [0, 1, 3, 7] {
        assert!(map.prepared_gate_world(mask).is_some(), "mask {mask}");
    }
    for mask in [2, 4, 5, 6] {
        assert!(map.prepared_gate_world(mask).is_none(), "mask {mask}");
    }
    assert!(map.mission().is_none() && map.is_campaign());
    let wire = GameState::with_authored_map(match &map {
        crate::maps::RuntimeMap::Authored(map) => map.clone(),
        _ => unreachable!("bundled missions are authored"),
    })
    .map_info();
    assert!(matches!(
        wire,
        ServerMessage::MapInfo {
            map_id: 1002,
            m02_objectives: Some(5),
            mission: None,
            ..
        }
    ));
}

#[test]
fn solo_human_and_agent_clear_the_graybox_in_order_through_the_shared_controller() {
    for role in [Role::Human, Role::Agent] {
        let mut session = session();
        let id = Uuid::from_u128(0x0200);
        session.state.add_player(id, "Walker".into(), role);
        let mut walker = Walker::new(id);
        let ticks = walker.until(&mut session, 6000, departed);
        walker.read(session.tick_messages(0.05));
        assert_eq!(walker.completed, ORDER, "{role:?}");
        // The closed world plus one resend for each prepared gate.
        assert_eq!(walker.maps, 4, "{role:?}");
        let state = session.state.mission_state().unwrap();
        assert_eq!(state.phase, MissionPhase::Departed);
        assert_eq!(state.attempt, 1);
        assert_eq!(state.m02.unwrap().gate_mask, 7);
        assert!(ticks < 6000);
        eprintln!("M02 graybox {role:?} departed after {ticks} ticks");
    }
}

#[test]
fn shut_gates_block_the_premature_route_on_foot_and_in_navigation() {
    let mut session = session();
    let id = Uuid::from_u128(0x0201);
    session.state.add_player(id, "Pusher".into(), Role::Human);
    assert!(session.state.acknowledge_m02(id, 1));
    session.tick_messages(0.05);
    let map = session.state.map.clone();
    let prepared = map.m02_objectives().unwrap();
    let start = [0.0, 3.0, -31.0];
    // Correction is reachable at once; every later step waits on its gate.
    for (index, expected) in [
        (1, RouteStatus::Complete),
        (2, RouteStatus::Unreachable),
        (3, RouteStatus::Unreachable),
        (4, RouteStatus::Unreachable),
    ] {
        let goal = prepared.objective(index).unwrap().feet;
        assert_eq!(
            map.navigation().route(start, goal, SEARCH_LIMIT).status,
            expected,
            "objective {index}"
        );
    }
    // Stand at each closed gate and walk into it. The authoritative body stops.
    for (front, limit) in [
        ([5.5, 0.0, -16.5], -15.0),
        ([-4.0, 0.0, -9.5], -8.0),
        ([0.0, 0.0, 12.5], 14.0),
    ] {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|player| player.id == id)
            .unwrap();
        [player.x, player.y, player.z] = [front[0], front[1] + PLAYER_FLOOR_Y, front[2]];
        for _ in 0..60 {
            session.state.set_action(
                id,
                Action {
                    forward: true,
                    jump: true,
                    yaw: Some(std::f32::consts::FRAC_PI_2),
                    ..Action::default()
                },
            );
            session.tick_messages(0.05);
        }
        let player = session.state.players.iter().find(|p| p.id == id).unwrap();
        assert!(
            player.z + crate::movement::RADIUS <= limit + CONTACT_EPSILON,
            "a closed gate let the body through at {:?}",
            [player.x, player.z]
        );
    }
    let state = session.state.mission_state().unwrap();
    assert_eq!(state.m02.unwrap().gate_mask, 0);
}

#[test]
fn retry_after_release_restores_the_first_objective_and_closed_world() {
    let mut session = session();
    let id = Uuid::from_u128(0x0202);
    session.state.add_player(id, "Walker".into(), Role::Agent);
    let mut walker = Walker::new(id);
    walker.until(&mut session, 6000, |session, _| {
        session
            .state
            .mission_state()
            .and_then(|state| state.m02)
            .is_some_and(|m02| m02.gate_mask == 3)
    });
    assert_eq!(
        session.state.map.arena().solids[gate_index("bay_gate")].bottom,
        3.0
    );
    assert_eq!(
        session.state.map.arena().solids[gate_index("floor_gate")].bottom,
        3.0
    );
    let maps_before = walker.maps;
    // The same death state combat leaves behind, with ordinary entry respawn.
    let fallen = session
        .state
        .players
        .iter_mut()
        .find(|player| player.id == id)
        .unwrap();
    fallen.hp = 0;
    fallen.respawn_timer = Some(60);
    walker.step(&mut session);
    walker.step(&mut session);
    let state = session.state.mission_state().unwrap();
    let m02 = state.m02.clone().unwrap();
    assert_eq!(state.attempt, 2);
    assert_eq!(state.phase, MissionPhase::InProgress);
    assert!(m02.completed.is_empty());
    assert_eq!(m02.gate_mask, 0);
    assert_eq!(m02.current.unwrap().id, "ward_reached");
    assert!(walker.maps > maps_before, "the closed world is resent");
    let closed = session.state.map.arena();
    for gate in ["bay_gate", "floor_gate", "loading_gate"] {
        let index = gate_index(gate);
        assert_eq!(closed.solids[index].bottom, 0.0, "{gate}");
    }
    // The same participant then clears the restored mission from entry.
    walker.until(&mut session, 8000, departed);
    walker.read(session.tick_messages(0.05));
    assert_eq!(walker.completed, ORDER);
    assert_eq!(session.state.mission_state().unwrap().attempt, 2);
}

fn gate_index(id: &str) -> usize {
    let document: serde_json::Value =
        serde_json::from_str(include_str!("../../../maps/m02-persons-unknown.json")).unwrap();
    document["solids"]
        .as_array()
        .unwrap()
        .iter()
        .position(|solid| solid["id"] == id)
        .unwrap()
}
