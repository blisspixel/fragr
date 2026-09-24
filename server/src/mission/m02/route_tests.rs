//! The bundled M02 graybox, fought and walked through the live session by the
//! shared wire, equipment and mission controllers. Players move only through
//! ordinary actions; aim is accurate, so this is authoring evidence.
use super::*;
use crate::maps::AuthoredSource;
use crate::movement::{Arena, BODY_HEIGHT, CONTACT_EPSILON};
use crate::navigation::{Navigation, Navigator};
use crate::protocol::{Action, CampaignActor, EnemyPhase, LookAt, Role, ServerMessage, Snapshot};
use crate::session::GameSession;
use std::collections::BTreeSet;
use std::sync::Arc;

const ORDER: [&str; 2] = ["companion_released", "party_departed"];
const ENEMIES: usize = 9;

fn session() -> GameSession {
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(MissionId::PersonsUnknown)
            .load()
            .unwrap(),
    );
    session.state.seed(67);
    session
}

/// One wire reader: MapInfo rebuilds its own navigation, mission state is
/// validated by the shared controller, and shared controllers choose inputs.
struct Walker {
    id: Uuid,
    client: MissionClient,
    navigator: Navigator,
    world: Option<Arc<Navigation>>,
    snapshot: Option<Snapshot>,
    completed: Vec<String>,
    maps: usize,
    defeated: BTreeSet<Uuid>,
    shots: usize,
    enemy_shots: usize,
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
            defeated: BTreeSet::new(),
            shots: 0,
            enemy_shots: 0,
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
        for shot in &session.state.shot_results {
            if shot.shooter_id == self.id {
                self.shots += 1;
            } else if session
                .state
                .players
                .iter()
                .any(|p| p.id == shot.shooter_id && p.is_campaign_enemy())
            {
                self.enemy_shots += 1;
            }
        }
        for player in &session.state.players {
            if matches!(
                player.campaign,
                Some(CampaignActor::Union {
                    phase: EnemyPhase::Dead,
                    ..
                })
            ) {
                self.defeated.insert(player.id);
            }
        }
        if let Some(ready) = self.client.readiness(Some(self.id)) {
            assert!(session.state.acknowledge_mission(self.id, ready));
        }
        let (Some(world), Some(snapshot)) = (self.world.as_ref(), self.snapshot.as_ref()) else {
            return;
        };
        let Some(me) = snapshot
            .players
            .iter()
            .find(|p| p.id == self.id && p.hp > 0)
        else {
            return;
        };
        // Fight what is visible, strafing on a committed tell. Equipment and
        // the mission route then come from the same controllers agents use.
        let eye = [
            me.x,
            me.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
            me.z,
        ];
        let visible: Vec<_> = snapshot
            .players
            .iter()
            .filter(|p| {
                me.is_hostile_to(p)
                    // Engagement range, not every pixel down a long sightline.
                    && (p.x - me.x).hypot(p.z - me.z) < 24.0
                    && crate::combat::line_of_sight(
                        eye,
                        [
                            p.x,
                            p.y - PLAYER_FLOOR_Y + crate::combat::FIGHTER_HEIGHT * 0.5,
                            p.z,
                        ],
                        &session.state.map.arena().solids,
                    )
            })
            .collect();
        let mut combat = Action::default();
        if let Some(target) = visible.iter().min_by(|a, b| {
            (a.x - me.x)
                .hypot(a.z - me.z)
                .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
        }) {
            combat.look_at = Some(LookAt {
                player_id: Some(target.id),
                ..Default::default()
            });
            combat.fire = true;
            combat.left = visible.iter().any(|enemy| {
                matches!(
                    enemy.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Windup | EnemyPhase::Firing,
                        ..
                    })
                )
            });
        }
        let player = session
            .state
            .players
            .iter()
            .find(|p| p.id == self.id)
            .unwrap();
        let loadout = player
            .inventory
            .state(self.id, player.weapon, snapshot.tick);
        let equipped = crate::inventory::control_action_with_objective(
            self.id,
            snapshot,
            loadout.as_ref(),
            combat,
            true,
        );
        let action = self
            .client
            .steer(&mut self.navigator, world, self.id, snapshot, equipped);
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
            "route stalled after {:?} at {:?} with {} defeats and {} living enemies",
            self.completed,
            session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .map(|player| [
                    player.x,
                    player.y - PLAYER_FLOOR_Y,
                    player.z,
                    player.hp as f32
                ]),
            self.defeated.len(),
            living_enemies(session)
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

fn living_enemies(session: &GameSession) -> usize {
    session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy() && p.hp > 0)
        .count()
}

#[test]
fn bundled_graybox_is_an_open_route_with_arrival_objectives_and_fights() {
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
    // No switches and no gates: the only prepared world is the open one.
    assert!((0..prepared.len()).all(|index| {
        let objective = prepared.objective(index).unwrap();
        objective.control.is_none() && objective.arrival.is_some()
    }));
    assert!(map.prepared_gate_world(0).is_some());
    assert!(map.prepared_gate_world(1).is_none());
    assert_eq!(
        map.encounters()
            .iter()
            .map(|group| group.enemies.len())
            .sum::<usize>(),
        ENEMIES
    );
    let wire = GameState::with_authored_map(match &map {
        crate::maps::RuntimeMap::Authored(map) => map.clone(),
        _ => unreachable!("bundled missions are authored"),
    })
    .map_info();
    assert!(matches!(
        wire,
        ServerMessage::MapInfo {
            map_id: 1002,
            m02_objectives: Some(2),
            mission: None,
            ..
        }
    ));
}

#[test]
fn solo_human_and_agent_fight_through_and_depart() {
    for role in [Role::Human, Role::Agent] {
        let mut session = session();
        let id = Uuid::from_u128(0x0200);
        session.state.add_player(id, "Walker".into(), role);
        let mut walker = Walker::new(id);
        let ticks = walker.until(&mut session, 12000, departed);
        walker.read(session.tick_messages(0.05));
        assert_eq!(walker.completed, ORDER, "{role:?}");
        assert_eq!(walker.maps, 1, "{role:?}: no gate ever changes the world");
        assert_eq!(
            walker.defeated.len(),
            ENEMIES,
            "{role:?} must clear every fight on the way out"
        );
        let state = session.state.mission_state().unwrap();
        assert_eq!(state.phase, MissionPhase::Departed);
        assert_eq!(state.attempt, 1);
        let me = session.state.players.iter().find(|p| p.id == id).unwrap();
        eprintln!(
            "M02 graybox {role:?}: departed after {ticks} ticks, hp {}, armor {}, defeats {}, shots {}, enemy shots {}",
            me.hp,
            me.armor,
            walker.defeated.len(),
            walker.shots,
            walker.enemy_shots
        );
    }
}

#[test]
fn a_wipe_resets_the_objective_and_the_fights() {
    let mut session = session();
    let id = Uuid::from_u128(0x0202);
    session.state.add_player(id, "Walker".into(), Role::Agent);
    let mut walker = Walker::new(id);
    walker.until(&mut session, 12000, |_, walker| walker.completed.len() == 1);
    assert!(!walker.defeated.is_empty(), "the ward fight happened first");
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
    assert!(m02.completed.is_empty());
    assert_eq!(m02.current.unwrap().id, "companion_released");
    walker.until(&mut session, 200, |session, _| {
        living_enemies(session) == ENEMIES
    });
    assert!(session.state.pickups.iter().all(|pickup| pickup.available));
    // The same participant then fights through again from entry.
    walker.defeated.clear();
    walker.until(&mut session, 14000, departed);
    walker.read(session.tick_messages(0.05));
    assert_eq!(walker.completed, ORDER);
    assert_eq!(walker.defeated.len(), ENEMIES);
    assert_eq!(session.state.mission_state().unwrap().attempt, 2);
}
