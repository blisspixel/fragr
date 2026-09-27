//! The bundled M02 graybox, fought and walked through the live session by the
//! shared wire, equipment and mission controllers. Players move only through
//! ordinary actions; aim is accurate, so this is authoring evidence.
use super::*;
use crate::maps::AuthoredSource;
use crate::movement::{Arena, BODY_HEIGHT, CONTACT_EPSILON};
use crate::navigation::{Navigation, Navigator};
use crate::net::GameCommand;
use crate::protocol::{Action, CampaignActor, EnemyPhase, LookAt, Role, ServerMessage, Snapshot};
use crate::session::GameSession;
use std::collections::BTreeSet;
use std::sync::Arc;

const ORDER: [&str; 3] = ["ward_reached", "companion_released", "party_departed"];
const ENEMIES: usize = 16;

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
    defeated_names: BTreeSet<String>,
    first_fight_names: Option<BTreeSet<String>>,
    guard_room_seated: BTreeSet<String>,
    guard_room_stood: BTreeSet<String>,
    shots: usize,
    scatter_shots: usize,
    guard_room_scatter_hits: BTreeSet<String>,
    guard_room_claimed_at_activation: Option<bool>,
    ward_woke_before_guard_clear: bool,
    guard_room_scatter_shots: Option<usize>,
    guard_room_shotgun_claimed: Option<bool>,
    guard_room_shells_claimed: Option<bool>,
    guard_room_weapon_selected: Option<crate::protocol::WeaponType>,
    enemy_shots: usize,
    crawler_cues: Vec<(u64, [f32; 3], [f32; 3])>,
    first_crawler_clear_tick: Option<u64>,
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
            defeated_names: BTreeSet::new(),
            first_fight_names: None,
            guard_room_seated: BTreeSet::new(),
            guard_room_stood: BTreeSet::new(),
            shots: 0,
            scatter_shots: 0,
            guard_room_scatter_hits: BTreeSet::new(),
            guard_room_claimed_at_activation: None,
            ward_woke_before_guard_clear: false,
            guard_room_scatter_shots: None,
            guard_room_shotgun_claimed: None,
            guard_room_shells_claimed: None,
            guard_room_weapon_selected: None,
            enemy_shots: 0,
            crawler_cues: Vec::new(),
            first_crawler_clear_tick: None,
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
        let feet = session
            .state
            .players
            .iter()
            .find(|player| player.id == self.id)
            .map(|player| [player.x, player.y - PLAYER_FLOOR_Y, player.z]);
        let messages = session.tick_messages(0.05);
        for message in &messages {
            if let ServerMessage::Event(crate::protocol::GameEvent::CrawlerScrabble { position }) =
                message
            {
                self.crawler_cues
                    .push((session.state.tick, feet.unwrap(), *position));
            }
        }
        self.read(messages);
        if session
            .state
            .players
            .iter()
            .any(|p| p.name == "stair_crawler_first" && p.hp <= 0)
            && self.first_crawler_clear_tick.is_none()
        {
            self.first_crawler_clear_tick = Some(session.state.tick);
        }
        for player in session
            .state
            .players
            .iter()
            .filter(|player| player.name.starts_with("guard_room_clerk_"))
        {
            if let Some(CampaignActor::Union { seated, phase, .. }) = player.campaign {
                if seated && phase == EnemyPhase::Idle {
                    self.guard_room_seated.insert(player.name.clone());
                } else if !seated {
                    self.guard_room_stood.insert(player.name.clone());
                }
            }
        }
        let guard_active = session.state.players.iter().any(|player| {
            player.name.starts_with("guard_room_clerk_")
                && matches!(
                    player.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Moving
                            | EnemyPhase::Windup
                            | EnemyPhase::Firing
                            | EnemyPhase::Recovery
                            | EnemyPhase::Hit,
                        ..
                    })
                )
        });
        if guard_active && self.guard_room_claimed_at_activation.is_none() {
            self.guard_room_claimed_at_activation = session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .map(|player| player.inventory.claimed("guard_room_scatter"));
        }
        if self.defeated.len() < 2 {
            self.ward_woke_before_guard_clear |= session.state.players.iter().any(|player| {
                matches!(
                    player.name.as_str(),
                    "ward_clerk" | "ward_sweeper" | "machine_clerk"
                ) && matches!(
                    player.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Moving
                            | EnemyPhase::Windup
                            | EnemyPhase::Firing
                            | EnemyPhase::Recovery
                            | EnemyPhase::Hit,
                        ..
                    })
                )
            });
        }
        for shot in &session.state.shot_results {
            if shot.shooter_id == self.id {
                self.shots += 1;
                self.scatter_shots += usize::from(
                    shot.trace
                        .as_ref()
                        .is_some_and(|trace| trace.weapon == crate::protocol::WeaponType::Scatter),
                );
                if shot.hit
                    && shot
                        .trace
                        .as_ref()
                        .is_some_and(|trace| trace.weapon == crate::protocol::WeaponType::Scatter)
                {
                    if let Some(target) = shot
                        .target
                        .as_ref()
                        .filter(|target| target.starts_with("guard_room_clerk_"))
                    {
                        self.guard_room_scatter_hits.insert(target.clone());
                    }
                }
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
                self.defeated_names.insert(player.name.clone());
            }
        }
        if self.defeated.len() >= 2 && self.guard_room_scatter_shots.is_none() {
            self.first_fight_names = Some(self.defeated_names.clone());
            self.guard_room_scatter_shots = Some(self.scatter_shots);
            self.guard_room_shotgun_claimed = session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .map(|player| player.inventory.claimed("guard_room_scatter"));
            self.guard_room_weapon_selected = session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .map(|player| player.weapon);
            self.guard_room_shells_claimed = session
                .state
                .pickups
                .iter()
                .find(|pickup| pickup.id == "guard_room_shells")
                .map(|pickup| !pickup.available);
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
                            p.y - PLAYER_FLOOR_Y + crate::combat::target_height(p.campaign) * 0.5,
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
                        phase: EnemyPhase::Windup | EnemyPhase::Firing | EnemyPhase::Leaping,
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

    fn reset_attempt_evidence(&mut self) {
        self.defeated.clear();
        self.defeated_names.clear();
        self.first_fight_names = None;
        self.guard_room_seated.clear();
        self.guard_room_stood.clear();
        self.scatter_shots = 0;
        self.guard_room_scatter_hits.clear();
        self.guard_room_claimed_at_activation = None;
        self.ward_woke_before_guard_clear = false;
        self.guard_room_scatter_shots = None;
        self.guard_room_shotgun_claimed = None;
        self.guard_room_shells_claimed = None;
        self.guard_room_weapon_selected = None;
        self.crawler_cues.clear();
        self.first_crawler_clear_tick = None;
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

fn assert_guard_room_lesson(walker: &Walker) {
    let guards = BTreeSet::from([
        "guard_room_clerk_west".to_string(),
        "guard_room_clerk_east".to_string(),
    ]);
    assert_eq!(walker.guard_room_seated, guards);
    assert_eq!(walker.guard_room_stood, guards);
    assert_eq!(
        walker.first_fight_names,
        Some(guards),
        "the first two defeats must be the guard-room Clerks"
    );
    assert_eq!(walker.guard_room_claimed_at_activation, Some(true));
    assert_eq!(walker.guard_room_shotgun_claimed, Some(true));
    assert_eq!(walker.guard_room_shells_claimed, Some(true));
    assert_eq!(
        walker.guard_room_weapon_selected,
        Some(crate::protocol::WeaponType::Scatter)
    );
    assert!(
        walker
            .guard_room_scatter_shots
            .is_some_and(|shots| shots > 0),
        "the first fight must use the Shotgun"
    );
    assert!(
        !walker.guard_room_scatter_hits.is_empty(),
        "the first fight must hit a Clerk with the Shotgun"
    );
    assert!(!walker.ward_woke_before_guard_clear);
}

fn living_enemies(session: &GameSession) -> usize {
    session
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_enemy() && p.hp > 0)
        .count()
}

fn ward_test_state() -> (GameState, Uuid) {
    let map = AuthoredSource::Mission(MissionId::PersonsUnknown)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    let id = Uuid::from_u128(0x02aa);
    state.add_player(id, "Release probe".into(), Role::Human);
    assert!(state.acknowledge_m02(id, 1));
    (state, id)
}

fn release_control_point(state: &GameState) -> [f32; 3] {
    state
        .map
        .m02_objectives()
        .unwrap()
        .objective(1)
        .unwrap()
        .control
        .as_ref()
        .unwrap()
        .point(
            state.map.presentation_ref().unwrap(),
            &state.map.arena().solids,
        )
        .unwrap()
}

fn face_release_control(state: &mut GameState, id: Uuid, x: f32, z: f32) {
    let target = release_control_point(state);
    let player = state
        .players
        .iter_mut()
        .find(|player| player.id == id)
        .unwrap();
    [player.x, player.y, player.z] = [x, PLAYER_FLOOR_Y, z];
    (player.yaw, player.pitch) =
        crate::combat::aim_at([player.x, crate::movement::EYE_HEIGHT, player.z], target).unwrap();
}

fn at_frame_facing_control(state: &mut GameState, id: Uuid) {
    face_release_control(state, id, 7.0, -11.0);
}

fn defeat_ward_guards(state: &mut GameState) {
    for enemy in state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "ward_clerk" | "ward_sweeper" | "machine_clerk"
        )
    }) {
        enemy.hp = 0;
    }
}

#[test]
fn ward_victory_precedes_the_local_release_and_a_second_use_is_inert() {
    let (mut state, id) = ward_test_state();
    {
        let player = state
            .players
            .iter_mut()
            .find(|player| player.id == id)
            .unwrap();
        [player.x, player.y, player.z] = [-8.0, PLAYER_FLOOR_Y, -19.0];
    }
    state.update_encounters();
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached"]
    );
    at_frame_facing_control(&mut state, id);
    assert!(state.mission_state().unwrap().prompts.is_empty());
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached"]
    );
    defeat_ward_guards(&mut state);
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert!(
        !state.m02_ward_secured(),
        "the last death is not yet the completed group"
    );
    state.update_encounters();
    assert!(state.m02_ward_secured());
    let before_use = state.mission_state().unwrap();
    assert!(before_use.m02.unwrap().ward_secured);
    assert_eq!(before_use.prompts.len(), 1);

    state.players[0].hp = 0;
    state.players[0].interaction_requested = true;
    state.advance_m02();
    state.players[0].hp = 100;
    state.players[0].yaw = std::f32::consts::PI;
    state.players[0].pitch = 0.0;
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached"]
    );
    at_frame_facing_control(&mut state, id);
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached", "companion_released"]
    );
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed.len(),
        2
    );
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 21.5];
    state.advance_m02();
    assert!(
        state.mission_departed(),
        "one participant can leave without a Latch seat"
    );
}

#[test]
fn release_control_rejects_briefing_remote_and_occluded_presses() {
    let map = AuthoredSource::Mission(MissionId::PersonsUnknown)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    let id = Uuid::from_u128(0x02ad);
    state.add_player(id, "Release probe".into(), Role::Human);
    at_frame_facing_control(&mut state, id);
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(state.mission_state().unwrap().phase, MissionPhase::Briefing);
    assert!(state.mission_state().unwrap().prompts.is_empty());
    assert!(!state.players[0].interaction_requested);
    assert!(state.acknowledge_m02(id, 1));
    state.update_encounters();
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached"]
    );
    defeat_ward_guards(&mut state);
    state.update_encounters();
    assert!(state.m02_ward_secured());

    face_release_control(&mut state, id, 4.5, -11.0);
    state.players[0].interaction_requested = true;
    assert!(state.mission_state().unwrap().prompts.is_empty());
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed.len(),
        1
    );

    // Even a forged position just behind the frame's south edge has its ray
    // blocked by the solid. Facing and distance alone cannot operate it.
    face_release_control(&mut state, id, 8.5, -13.2);
    let eye = [8.5, crate::movement::EYE_HEIGHT, -13.2];
    let target = release_control_point(&state);
    assert!((target[0] - eye[0]).hypot(target[2] - eye[2]) < crate::protocol::USE_DISTANCE);
    assert!(!crate::combat::line_of_sight(
        eye,
        target,
        &state.map.arena().solids
    ));
    state.players[0].interaction_requested = true;
    assert!(state.mission_state().unwrap().prompts.is_empty());
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed.len(),
        1
    );

    at_frame_facing_control(&mut state, id);
    assert_eq!(state.mission_state().unwrap().prompts.len(), 1);
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached", "companion_released"]
    );
}

#[test]
fn wiping_after_ward_victory_but_before_release_restores_the_restraint() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    defeat_ward_guards(&mut state);
    state.update_encounters();
    assert!(state.m02_ward_secured());
    assert_eq!(state.mission_state().unwrap().prompts.len(), 1);
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed.len(),
        1
    );

    state.players[0].hp = 0;
    state.players[0].respawn_timer = Some(60);
    state.update_encounters();
    let mission = state.mission_state().unwrap();
    assert_eq!(mission.attempt, 2);
    assert!(!mission.m02.as_ref().unwrap().ward_secured);
    assert!(mission.m02.as_ref().unwrap().completed.is_empty());
    assert_eq!(mission.m02.unwrap().current.unwrap().id, "ward_reached");
    assert!(state
        .players
        .iter()
        .all(|player| !player.is_campaign_enemy()));

    state.players[0].hp = 100;
    state.players[0].respawn_timer = None;
    state.update_encounters();
    assert!(state
        .players
        .iter()
        .any(|player| player.name == "ward_clerk"));
    assert!(!state.m02_ward_secured());
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed.len(),
        1
    );
    assert!(state.mission_state().unwrap().prompts.is_empty());
}

#[test]
fn a_bypassed_pack_cannot_leave_the_ward_dormant_at_latch() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    assert_eq!(
        state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .current
            .unwrap()
            .id,
        "companion_released",
        "the frame approach must also satisfy ward_reached for a bypasser"
    );
    assert!(
        !state.encounters.is_complete(2),
        "the pack remains uncleared"
    );
    assert!(state
        .players
        .iter()
        .any(|player| player.name == "ward_clerk" && player.hp > 0));
    defeat_ward_guards(&mut state);
    state.update_encounters();
    assert!(
        state.m02_ward_secured(),
        "the frame-side region wakes the ward despite the pack bypass"
    );
}

#[test]
fn late_spectator_receives_the_durable_release_without_a_party_seat() {
    let mut session = session();
    let id = Uuid::from_u128(0x02ab);
    session
        .state
        .add_player(id, "Release probe".into(), Role::Human);
    assert!(session.state.acknowledge_m02(id, 1));
    at_frame_facing_control(&mut session.state, id);
    session.state.update_encounters();
    session.state.advance_m02();
    defeat_ward_guards(&mut session.state);
    session.state.update_encounters();
    session.state.players[0].interaction_requested = true;
    session.state.advance_m02();
    assert_eq!(
        session
            .state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .completed,
        ["ward_reached", "companion_released"]
    );
    let watcher = Uuid::from_u128(0x02ac);
    session.apply_command(GameCommand::Connected {
        id: watcher,
        role: Role::Spectator,
        name: "Watcher".into(),
        player_id: None,
        body: crate::protocol::BodyKind::Human,
    });
    let messages = session.take_unicasts();
    assert!(matches!(
        messages.first(),
        Some((crate::session::Recipient::Client(client), ServerMessage::MapInfo { .. }))
            if *client == watcher
    ));
    assert!(messages.iter().any(|(recipient, message)| {
        matches!(recipient, crate::session::Recipient::Client(client) if *client == watcher)
            && matches!(message, ServerMessage::Mission { state, .. }
                if state.party.len() == 1
                    && state.m02.as_ref().is_some_and(|m02|
                        m02.ward_secured
                            && m02.completed == ["ward_reached", "companion_released"]))
    }));
    assert_eq!(session.state.mission_state().unwrap().party.len(), 1);
}

#[test]
fn bundled_graybox_has_a_local_release_after_the_ward_fight() {
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
    assert!(prepared.objective(0).unwrap().arrival.is_some());
    assert!(prepared.objective(1).unwrap().control.is_some());
    assert_eq!(prepared.objective(1).unwrap().required_encounter, Some(3));
    assert!(prepared.objective(2).unwrap().arrival.is_some());
    // The restraint control is required, but it opens no route gate.
    assert!(map.prepared_gate_world(0).is_some());
    assert!(map.prepared_gate_world(1).is_none());
    let encounters = map.encounters();
    assert_eq!(encounters[0].id, "guard_room");
    assert!(encounters[0]
        .enemies
        .iter()
        .all(|enemy| enemy.seated && enemy.feet[1] == 3.0));
    for id in ["guard_room_scatter", "guard_room_shells"] {
        assert_eq!(
            map.pickups().iter().find(|pad| pad.id == id).unwrap().floor,
            3.0
        );
    }
    // A player must cross the Shotgun claim radius before any corner of the
    // guard trigger. Leave one full 20 Hz movement step as margin because
    // pickups resolve after movement and encounter triggers before it.
    let scatter = map
        .pickups()
        .into_iter()
        .find(|pad| pad.id == "guard_room_scatter")
        .unwrap();
    for region in &encounters[0].regions {
        for x in [region.min[0], region.max[0]] {
            for z in [region.min[2], region.max[2]] {
                assert!(
                    (x - scatter.x).hypot(z - scatter.z) + crate::movement::TOP_SPEED * 0.05
                        < crate::sim::PICKUP_CLAIM_RADIUS,
                    "guard trigger can be reached before claiming the Shotgun"
                );
            }
        }
    }
    assert_eq!(encounters[1].id, "crawler_first");
    assert_eq!(encounters[1].after.as_deref(), Some("guard_room"));
    assert_eq!(encounters[2].id, "crawler_pack");
    assert_eq!(encounters[2].after.as_deref(), Some("crawler_first"));
    assert_eq!(encounters[3].id, "ward_guards");
    assert_eq!(encounters[3].after, None);
    assert_eq!(encounters[3].regions.len(), 2);
    assert_eq!(
        encounters
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
            m02_objectives: Some(3),
            mission: None,
            ..
        }
    ));
}

#[test]
fn guard_room_arrival_shows_the_pickup_then_publishes_the_wake() {
    let mut session = session();
    let id = Uuid::from_u128(0x0203);
    session.state.add_player(id, "Arrival".into(), Role::Human);
    session.tick_messages(0.05);
    assert!(
        !session
            .state
            .players
            .iter()
            .find(|player| player.id == id)
            .unwrap()
            .inventory
            .claimed("guard_room_scatter"),
        "the Shotgun must remain visible at the starting point"
    );
    let participant = session
        .state
        .players
        .iter_mut()
        .find(|player| player.id == id)
        .unwrap();
    participant.x = -3.1;
    participant.z = -31.0;
    session.state.update_encounters();
    for player in session
        .state
        .snapshot()
        .players
        .iter()
        .filter(|player| player.name.starts_with("guard_room_clerk_"))
    {
        assert!(matches!(
            player.campaign,
            Some(CampaignActor::Union { seated: false, .. })
        ));
    }
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
        assert_guard_room_lesson(&walker);
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
fn crawler_descent_is_walked_in_order_with_a_hidden_first_cue() {
    let mut session = session();
    let id = Uuid::from_u128(0x02c0);
    session.state.add_player(id, "Walker".into(), Role::Human);
    let mut walker = Walker::new(id);
    walker.until(&mut session, 12000, departed);
    assert_eq!(walker.crawler_cues.len(), 2, "each Crawler group cues once");
    let first = walker.crawler_cues[0];
    let pack = walker.crawler_cues[1];
    assert!(first.0 < pack.0, "the first landing precedes the pack");
    assert!(
        walker
            .first_crawler_clear_tick
            .is_some_and(|tick| tick < pack.0),
        "the pack must not wake before the lone Crawler clears"
    );
    assert_eq!(first.2, [-12.0, 0.0, -27.0]);
    assert_eq!(pack.2, [-16.0, 0.5, -28.4]);
    assert!((-10.9..=-10.1).contains(&first.1[0]));
    assert!((0.9..=1.1).contains(&first.1[1]));
    assert!((-30.7..=-28.7).contains(&first.1[2]));
    assert!((-14.8..=-11.8).contains(&pack.1[0]));
    assert!((0.0..=0.6).contains(&pack.1[1]));
    assert!((-29.0..=-22.5).contains(&pack.1[2]));
    let solids = &session.state.map.arena().solids;
    assert!(
        !crate::combat::line_of_sight(
            [
                first.1[0],
                first.1[1] + crate::movement::EYE_HEIGHT,
                first.1[2]
            ],
            [
                first.2[0],
                first.2[1] + crate::combat::CRAWLER_HEIGHT * 0.5,
                first.2[2]
            ],
            solids,
        ),
        "the first scrabble must precede a direct sightline"
    );
}

#[test]
fn engaged_descent_clears_the_lone_crawler_before_the_pack_landing() {
    let mut session = session();
    let id = Uuid::from_u128(0x02c2);
    session.state.add_player(id, "Walker".into(), Role::Human);
    let mut walker = Walker::new(id);
    walker.until(&mut session, 1000, |_, walker| {
        walker.crawler_cues.len() == 1
    });
    walker.until(&mut session, 80, |session, _| {
        session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .is_some_and(|p| {
                (p.y - PLAYER_FLOOR_Y).abs() < 0.1
                    && (-12.7..=-10.5).contains(&p.x)
                    && (-28.0..=-26.5).contains(&p.z)
            })
    });
    let enemy = session
        .state
        .players
        .iter()
        .find(|p| p.name == "stair_crawler_first")
        .unwrap()
        .id;
    let combat_feet = session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .map(|p| [p.x, p.y - PLAYER_FLOOR_Y, p.z])
        .unwrap();
    for _ in 0..100 {
        if session
            .state
            .players
            .iter()
            .find(|p| p.id == enemy)
            .is_some_and(|p| p.hp <= 0)
        {
            break;
        }
        session.state.set_action(
            id,
            Action {
                fire: true,
                look_at: Some(LookAt {
                    player_id: Some(enemy),
                    ..Default::default()
                }),
                ..Default::default()
            },
        );
        walker.read(session.tick_messages(0.05));
    }
    assert!(
        session
            .state
            .players
            .iter()
            .find(|p| p.id == enemy)
            .is_some_and(|p| p.hp <= 0),
        "the lone Crawler must be fightable from the grounded switchback"
    );
    let after_fight = session.state.players.iter().find(|p| p.id == id).unwrap();
    assert!((after_fight.x - combat_feet[0]).abs() < 0.05);
    assert!((after_fight.z - combat_feet[2]).abs() < 0.05);
    assert!(after_fight.hp > 0);
    walker.until(&mut session, 120, |_, walker| {
        walker.crawler_cues.len() == 2
    });
    assert_eq!(walker.crawler_cues.len(), 2);
    assert!(
        (-29.0..=-25.0).contains(&walker.crawler_cues[1].1[2]),
        "the pack cue should occur on the next landing approach"
    );
}

#[test]
fn crawler_pack_can_leave_raised_cover_and_attack_the_approach() {
    let mut session = session();
    let id = Uuid::from_u128(0x02c1);
    session.state.add_player(id, "Anchor".into(), Role::Human);
    let mut walker = Walker::new(id);
    walker.step(&mut session);
    walker.step(&mut session);
    let place = |session: &mut GameSession, x: f32, y: f32, z: f32| {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        player.x = x;
        player.y = PLAYER_FLOOR_Y + y;
        player.z = z;
    };
    place(&mut session, -3.2, 3.0, -31.0);
    session.state.update_encounters();
    for enemy in session
        .state
        .players
        .iter_mut()
        .filter(|p| p.name.starts_with("guard_room_clerk_"))
    {
        enemy.hp = 0;
    }
    session.state.update_encounters();
    place(&mut session, -10.5, 1.0, -29.5);
    session.state.update_encounters();
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.name == "stair_crawler_first")
        .unwrap()
        .hp = 0;
    session.state.update_encounters();
    place(&mut session, -12.5, 0.0, -23.9);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .hp = 1000;
    session.state.update_encounters();
    let mut left_cover = false;
    let mut sweeper_fired = false;
    for _ in 0..400 {
        session.tick_messages(0.05);
        left_cover |= session.state.players.iter().any(|p| {
            p.name.starts_with("stair_crawler_pack_") && p.hp > 0 && (p.x > -14.2 || p.z > -24.0)
        });
        sweeper_fired |= session
            .state
            .shot_results
            .iter()
            .any(|shot| shot.shooter == "stair_pack_sweeper");
        if left_cover && sweeper_fired {
            break;
        }
    }
    assert!(
        left_cover,
        "a Crawler must route around the cover without a script override"
    );
    assert!(
        sweeper_fired,
        "the pack Sweeper must acquire a real shot lane"
    );
}

#[test]
fn first_guard_room_teaches_the_shotgun_across_seeds() {
    for seed in [1, 42, 67, 99] {
        let mut session = session();
        session.state.seed(seed);
        let id = Uuid::from_u128(0x0201);
        session.state.add_player(id, "Walker".into(), Role::Human);
        let mut walker = Walker::new(id);
        walker.until(&mut session, 3000, |_, walker| walker.defeated.len() >= 2);
        assert_guard_room_lesson(&walker);
        assert!(
            session
                .state
                .players
                .iter()
                .any(|player| player.id == id && player.hp > 0),
            "seed {seed}: first fight must be survivable"
        );
    }
}

#[test]
fn a_wipe_resets_the_objective_and_the_fights() {
    let mut session = session();
    let id = Uuid::from_u128(0x0202);
    session.state.add_player(id, "Walker".into(), Role::Agent);
    let mut walker = Walker::new(id);
    walker.until(&mut session, 12000, |_, walker| walker.completed.len() == 2);
    assert!(
        session.state.m02_ward_secured(),
        "the ward fight happened first"
    );
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
    assert!(!session.state.m02_ward_secured());
    assert_eq!(m02.current.unwrap().id, "ward_reached");
    walker.until(&mut session, 200, |session, _| {
        living_enemies(session) == ENEMIES
    });
    assert!(session.state.pickups.iter().all(|pickup| pickup.available));
    // The same participant then fights through again from entry.
    walker.reset_attempt_evidence();
    walker.until(&mut session, 14000, departed);
    walker.read(session.tick_messages(0.05));
    assert_guard_room_lesson(&walker);
    assert!(
        session
            .state
            .pickups
            .iter()
            .find(|pickup| pickup.id == "floor_entry_medkit")
            .is_some_and(|pickup| !pickup.available),
        "the floor-entry recovery must be on the retry route"
    );
    assert_eq!(walker.completed, ORDER);
    assert_eq!(walker.defeated.len(), ENEMIES);
    assert_eq!(session.state.mission_state().unwrap().attempt, 2);
}
