//! The bundled M02 graybox, fought and walked through the live session by the
//! shared wire, equipment and mission controllers. Players move only through
//! ordinary actions; aim is accurate, so this is authoring evidence.
use super::*;
use crate::maps::AuthoredSource;
use crate::movement::{Arena, BODY_HEIGHT, CONTACT_EPSILON};
use crate::navigation::{Navigation, Navigator};
use crate::net::GameCommand;
use crate::protocol::{
    Action, CampaignActor, CompanionPhase, EnemyPhase, LookAt, Role, ServerMessage, Snapshot,
};
use crate::session::GameSession;
use std::collections::BTreeSet;
use std::sync::Arc;

const ORDER: [&str; 3] = ["ward_reached", "companion_released", "party_departed"];
const ENEMIES: usize = 24;

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
    attempt_enemies: Option<BTreeSet<Uuid>>,
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
    companion_shots: usize,
    companion_damage: u32,
    companion_kills: usize,
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
            attempt_enemies: None,
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
            companion_shots: 0,
            companion_damage: 0,
            companion_kills: 0,
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
                    m02_side_ward,
                    ..
                } => {
                    self.client
                        .replace_map_with_id(
                            map_id,
                            m02_objectives,
                            m02_side_ward,
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
            } else if session
                .state
                .players
                .iter()
                .any(|p| p.id == shot.shooter_id && p.is_campaign_companion())
            {
                self.companion_shots += 1;
                self.companion_damage += shot.damage.max(0) as u32;
                self.companion_kills += usize::from(shot.killed);
            }
        }
        for player in &session.state.players {
            if self
                .attempt_enemies
                .as_ref()
                .is_none_or(|ids| ids.contains(&player.id))
                && matches!(
                    player.campaign,
                    Some(CampaignActor::Union {
                        phase: EnemyPhase::Dead,
                        ..
                    })
                )
            {
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
        let ward_release_pending = !self.completed.iter().any(|id| id == "companion_released");
        let mut equipped = crate::inventory::control_action_with_target_filter(
            self.id,
            snapshot,
            loadout.as_ref(),
            combat,
            true,
            |_, other| !ward_release_pending || other.z < -7.0,
        );
        if equipped.look_at.is_some()
            && !equipped.fire
            && !equipped.forward
            && !equipped.back
            && !equipped.left
            && !equipped.right
        {
            // Do not stand at a distant target the current weapon cannot hit.
            // Approach through the same navigator before resuming the route.
            equipped.forward = true;
        }
        let action = self
            .client
            .steer(&mut self.navigator, world, self.id, snapshot, equipped);
        session.state.set_action(self.id, action);
    }

    fn reset_attempt_evidence(&mut self, session: &GameSession) {
        self.snapshot = None;
        self.navigator.clear();
        self.defeated.clear();
        self.attempt_enemies = Some(
            session
                .state
                .players
                .iter()
                .filter(|player| player.is_campaign_enemy() && player.hp > 0)
                .map(|player| player.id)
                .collect(),
        );
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
            "route stalled at tick {} after {:?} at {:?} with {} defeats and {} living enemies {:?}",
            session.state.tick,
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
            living_enemies(session),
            session.state.players.iter().filter(|p| p.is_campaign_enemy() && p.hp > 0).map(|p| (&p.name, p.x, p.z)).collect::<Vec<_>>()
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
    let before_progress = before_use.m02.unwrap();
    assert!(before_progress.ward_secured);
    assert_eq!(before_progress.gate_mask, 0);
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
    let after_release = state.mission_state().unwrap().m02.unwrap();
    assert_eq!(
        after_release.completed,
        ["ward_reached", "companion_released"]
    );
    assert_eq!(after_release.gate_mask, 1);
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed.len(),
        2
    );
    let companion: Vec<_> = state
        .players
        .iter()
        .filter(|p| p.is_campaign_companion())
        .collect();
    assert_eq!(companion.len(), 1);
    assert_eq!(
        companion[0].campaign,
        Some(CampaignActor::Companion {
            kind: crate::protocol::CompanionKind::Latch,
            phase: CompanionPhase::Releasing,
            phase_started: state.tick,
        })
    );
    assert_eq!(
        [
            companion[0].x,
            companion[0].y - PLAYER_FLOOR_Y,
            companion[0].z
        ],
        LATCH_SECOND_FEET
    );
    assert!(!state.scores.contains_key(&companion[0].id));
    assert!(state.player_record(companion[0].id).is_none());
    assert_eq!(state.mission_state().unwrap().party.len(), 1);
    let status = state.live_status(2);
    assert_eq!(
        (status.fighters, status.humans, status.agents, status.bots),
        (1, 1, 0, 0)
    );
    state.players.retain(|p| !p.is_campaign_companion());
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 21.5];
    state.advance_m02();
    assert!(
        state.mission_departed(),
        "one participant can leave without a Latch seat"
    );
}

#[test]
fn side_ward_clear_is_optional() {
    let (mut state, id) = ward_test_state();
    let side_index = state
        .mission
        .as_ref()
        .unwrap()
        .initial_map
        .encounters()
        .iter()
        .position(|encounter| encounter.id == "side_ward_guards")
        .unwrap();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    defeat_ward_guards(&mut state);
    state.update_encounters();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    assert_eq!(
        state.mission_state().unwrap().m02.unwrap().completed,
        ["ward_reached", "companion_released"]
    );
    for (feet, names, stage) in [
        (
            [6.0, PLAYER_FLOOR_Y, -6.0],
            &[
                "floor_officer",
                "floor_sweeper",
                "floor_entry_clerk",
                "floor_stair_sweeper",
            ][..],
            "floor_entry",
        ),
        (
            [0.0, PLAYER_FLOOR_Y, 5.0],
            &[
                "press_clerk",
                "conveyor_sweeper",
                "floor_lane_clerk",
                "side_return_sweeper",
            ][..],
            "floor_crossfire",
        ),
        (
            [0.0, PLAYER_FLOOR_Y, 12.0],
            &["floor_crawler_west", "floor_crawler_east"][..],
            "floor_crew",
        ),
        (
            [0.0, PLAYER_FLOOR_Y, 17.0],
            &["dock_sweeper", "dock_clerk"][..],
            "dock_watch",
        ),
    ] {
        [state.players[0].x, state.players[0].y, state.players[0].z] = feet;
        state.update_encounters();
        for enemy in state
            .players
            .iter_mut()
            .filter(|player| names.contains(&player.name.as_str()))
        {
            enemy.hp = 0;
        }
        state.update_encounters();
        assert!(state.m02_encounter_complete(stage));
    }
    state.update_encounters();
    assert!(!state.encounters.is_complete(side_index));
    assert!(
        !state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .side_ward_secured
    );
    assert!(state
        .players
        .iter()
        .any(|player| { player.name == "side_ward_clerk" && player.hp > 0 }));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 21.5];
    state.advance_m02();
    assert!(
        state.mission_departed(),
        "the side ward cannot gate the dock"
    );

    let (mut optional, _) = ward_test_state();
    [
        optional.players[0].x,
        optional.players[0].y,
        optional.players[0].z,
    ] = [7.0, PLAYER_FLOOR_Y, -11.0];
    optional.update_encounters();
    defeat_ward_guards(&mut optional);
    optional.update_encounters();
    [
        optional.players[0].x,
        optional.players[0].y,
        optional.players[0].z,
    ] = [23.5, PLAYER_FLOOR_Y, 6.5];
    optional.update_encounters();
    assert!(optional.encounters.is_active_enemy(
        optional
            .players
            .iter()
            .find(|player| player.name == "side_ward_clerk")
            .unwrap()
            .id
    ));
    for enemy in optional.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "side_ward_clerk" | "side_ward_sweeper"
        )
    }) {
        enemy.hp = 0;
    }
    optional.update_encounters();
    assert!(optional.encounters.is_complete(side_index));
    assert!(
        optional
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .side_ward_secured
    );
}

#[test]
fn a_long_shot_can_wake_the_crossfire_without_completing_the_floor() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    defeat_ward_guards(&mut state);
    state.update_encounters();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    let enemy = state
        .players
        .iter()
        .find(|player| player.name == "floor_lane_clerk")
        .unwrap();
    let enemy_id = enemy.id;
    let feet = [enemy.x, enemy.y - PLAYER_FLOOR_Y, enemy.z];
    assert!(!state.encounters.is_active_enemy(enemy_id));
    assert!(!state.m02_encounter_complete("floor_entry"));
    state.encounters.hit(enemy_id, feet, state.tick, false);
    assert!(state.encounters.is_active_enemy(enemy_id));
    assert!(!state.m02_encounter_complete("floor_entry"));
    assert!(!state.m02_encounter_complete("floor_crew"));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 17.0];
    state.update_encounters();
    assert!(state
        .players
        .iter()
        .find(|player| player.name == "dock_clerk")
        .is_some_and(|player| !state.encounters.is_active_enemy(player.id)));
}

#[test]
fn m02_continue_restores_held_captives_and_stable_bay_order() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    defeat_ward_guards(&mut state);
    state.update_encounters();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    [state.players[0].x, state.players[0].y, state.players[0].z] = [23.5, PLAYER_FLOOR_Y, 6.5];
    state.update_encounters();
    for enemy in state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "side_ward_clerk" | "side_ward_sweeper"
        )
    }) {
        enemy.hp = 0;
    }
    state.update_encounters();
    assert!(state.m02_side_ward_secured());
    state.advance_m02_evacuation(0.05);
    assert_eq!(
        state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .evacuation
            .unwrap()
            .phase,
        crate::protocol::M02EvacuationPhase::Freeing
    );
    state.reset_mission();
    state.reset_campaign_encounters();
    let current = state.mission_state().unwrap();
    assert_eq!(current.attempt, 2);
    let progress = current.m02.unwrap();
    assert!(!progress.side_ward_secured);
    assert_eq!(
        progress.evacuation.as_ref().unwrap().phase,
        crate::protocol::M02EvacuationPhase::Held
    );
    assert_eq!(
        progress.evacuation.as_ref().unwrap().captives,
        crate::protocol::M02EvacuationState::HELD_FEET
    );
    for _ in 0..5 {
        state.advance_m02_evacuation(0.05);
    }
    assert_eq!(
        state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .evacuation
            .unwrap()
            .captives,
        crate::protocol::M02EvacuationState::HELD_FEET
    );
}

#[test]
fn dock_clear_and_immediate_departure_do_not_grant_unwalked_evacuation() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    defeat_ward_guards(&mut state);
    state.update_encounters();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    [state.players[0].x, state.players[0].y, state.players[0].z] = [23.5, PLAYER_FLOOR_Y, 6.5];
    state.update_encounters();
    for enemy in state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "side_ward_clerk" | "side_ward_sweeper"
        )
    }) {
        enemy.hp = 0;
    }
    state.update_encounters();
    assert!(state.m02_side_ward_secured());
    [state.players[0].x, state.players[0].y, state.players[0].z] = [6.0, PLAYER_FLOOR_Y, -6.0];
    state.update_encounters();
    for enemy in state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "floor_officer" | "floor_sweeper" | "floor_entry_clerk" | "floor_stair_sweeper"
        )
    }) {
        enemy.hp = 0;
    }
    state.update_encounters();
    assert!(state.m02_encounter_complete("floor_entry"));
    assert!(!state.m02_encounter_complete("floor_crew"));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 5.0];
    state.update_encounters();
    for enemy in state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "press_clerk" | "conveyor_sweeper" | "floor_lane_clerk" | "side_return_sweeper"
        )
    }) {
        enemy.hp = 0;
    }
    state.update_encounters();
    assert!(state.m02_encounter_complete("floor_crossfire"));
    assert!(!state.m02_encounter_complete("floor_crew"));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 12.0];
    state.update_encounters();
    for enemy in state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "floor_crawler_west" | "floor_crawler_east"
        )
    }) {
        enemy.hp = 0;
    }
    state.update_encounters();
    assert!(state.m02_encounter_complete("floor_crew"));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 17.0];
    state.update_encounters();
    for enemy in state
        .players
        .iter_mut()
        .filter(|player| matches!(player.name.as_str(), "dock_sweeper" | "dock_clerk"))
    {
        enemy.hp = 0;
    }
    state.update_encounters();
    assert!(state.m02_encounter_complete("dock_watch"));
    [state.players[0].x, state.players[0].y, state.players[0].z] = [0.0, PLAYER_FLOOR_Y, 21.5];
    state.advance_m02();
    assert!(state.mission_departed());
    state.advance_m02_evacuation(0.05);
    let evacuation = state
        .mission_state()
        .unwrap()
        .m02
        .unwrap()
        .evacuation
        .unwrap();
    assert_eq!(evacuation.phase, crate::protocol::M02EvacuationPhase::Held);
    assert!(!evacuation.evacuated);
    assert_eq!(
        evacuation.captives,
        crate::protocol::M02EvacuationState::HELD_FEET
    );
}

#[test]
fn severe_side_ward_route_survives_with_ordinary_supplies() {
    let mut session = session();
    session
        .state
        .set_campaign_difficulty(crate::protocol::CampaignDifficulty::Severe)
        .unwrap();
    let id = Uuid::from_u128(0x02b0);
    session
        .state
        .add_player(id, "Severe walker".into(), Role::Human);
    let mut walker = Walker::new(id);
    let ticks = walker.until(&mut session, 16000, departed);
    assert_eq!(walker.defeated.len(), ENEMIES);
    assert_eq!(session.state.mission_state().unwrap().attempt, 1);
    assert!(session
        .state
        .players
        .iter()
        .find(|player| player.id == id)
        .is_some_and(|player| player.hp > 0));
    assert!(session.state.m02_side_ward_secured());
    for supply in ["side_ward_medkit", "side_ward_armor"] {
        assert!(session
            .state
            .pickups
            .iter()
            .find(|pickup| pickup.id == supply)
            .is_some_and(|pickup| !pickup.available));
    }
    let player = session
        .state
        .players
        .iter()
        .find(|player| player.id == id)
        .unwrap();
    eprintln!("M02 graybox Severe: departed after {ticks} ticks, hp {}, armor {}, defeats {}, player shots {}, enemy shots {}, companion damage {}", player.hp, player.armor, walker.defeated.len(), walker.shots, walker.enemy_shots, walker.companion_damage);
}

#[test]
fn released_companion_waits_for_tableau_then_follows_and_retry_removes_latch() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    defeat_ward_guards(&mut state);
    state.update_encounters();
    state.players[0].interaction_requested = true;
    state.advance_m02();
    let companion_id = state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .unwrap()
        .id;
    let release_tick = state.tick;
    state.set_action(
        companion_id,
        Action {
            forward: true,
            fire: true,
            ..Action::default()
        },
    );
    for _ in 0..LATCH_RELEASE_TICKS - 1 {
        state.tick(0.05);
    }
    let companion = state.players.iter().find(|p| p.id == companion_id).unwrap();
    assert_eq!(
        [companion.x, companion.y - PLAYER_FLOOR_Y, companion.z],
        LATCH_SECOND_FEET
    );
    assert!(
        matches!(companion.campaign, Some(CampaignActor::Companion { phase: CompanionPhase::Releasing, phase_started, .. }) if phase_started == release_tick)
    );
    assert!(!companion.just_fired);
    state.tick(0.05);
    let companion = state.players.iter().find(|p| p.id == companion_id).unwrap();
    assert!(
        matches!(companion.campaign, Some(CampaignActor::Companion { phase: CompanionPhase::Following, phase_started, .. }) if phase_started == state.tick)
    );
    assert_eq!(
        [companion.x, companion.y - PLAYER_FLOOR_Y, companion.z],
        LATCH_SECOND_FEET
    );
    [state.players[0].x, state.players[0].y, state.players[0].z] = [-4.0, PLAYER_FLOOR_Y, -10.0];
    let (intent_id, intent) = state.m02_companion_intent().unwrap();
    assert_eq!(intent_id, companion_id);
    assert!(
        intent.goal.is_some(),
        "the released ally seeks the distant participant"
    );
    assert!(!intent.action.fire);
    let mut live = session();
    live.state = state;
    for _ in 0..160 {
        live.tick_messages(0.05);
    }
    let moved = live
        .state
        .players
        .iter()
        .find(|p| p.id == companion_id)
        .unwrap();
    assert!(
        (moved.x - LATCH_SECOND_FEET[0]).hypot(moved.z - LATCH_SECOND_FEET[2]) > 5.0,
        "the shared navigator must move Latch out of the bay toward the party"
    );
    let participant = live.state.players.iter().find(|p| p.id == id).unwrap();
    assert!(
        (moved.x - participant.x).hypot(moved.z - participant.z) >= 2.0,
        "the ally holds a lateral slot outside the player's aiming lane"
    );
    let pad = live
        .state
        .pickups
        .iter()
        .find(|p| p.id == "floor_medkit")
        .unwrap()
        .clone();
    let companion = live
        .state
        .players
        .iter_mut()
        .find(|p| p.id == companion_id)
        .unwrap();
    [companion.x, companion.y, companion.z] = [pad.x, pad.floor + PLAYER_FLOOR_Y, pad.z];
    companion.hp = 50;
    live.tick_messages(0.05);
    assert!(
        live.state
            .pickups
            .iter()
            .find(|p| p.id == pad.id)
            .unwrap()
            .available
    );
    assert_eq!(
        live.state
            .players
            .iter()
            .find(|p| p.id == companion_id)
            .unwrap()
            .hp,
        50
    );
    let participant = live.state.players.iter_mut().find(|p| p.id == id).unwrap();
    participant.hp = 0;
    participant.respawn_timer = Some(60);
    live.state.update_encounters();
    assert!(!live.state.players.iter().any(|p| p.is_campaign_companion()));
    assert_eq!(live.state.mission_state().unwrap().party.len(), 1);
    assert_eq!(live.state.mission_state().unwrap().attempt, 2);
    assert_eq!(
        live.state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .completed
            .len(),
        0
    );
    let participant = live.state.players.iter_mut().find(|p| p.id == id).unwrap();
    participant.hp = 100;
    participant.respawn_timer = None;
    at_frame_facing_control(&mut live.state, id);
    live.state.update_encounters();
    live.state.advance_m02();
    defeat_ward_guards(&mut live.state);
    live.state.update_encounters();
    live.state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap()
        .interaction_requested = true;
    live.state.advance_m02();
    let retry_companions: Vec<_> = live
        .state
        .players
        .iter()
        .filter(|p| p.is_campaign_companion())
        .collect();
    assert_eq!(retry_companions.len(), 1);
    assert_ne!(retry_companions[0].id, companion_id);
}

#[test]
fn companion_only_fires_bounded_support_at_visible_active_union() {
    let (mut state, id) = ward_test_state();
    at_frame_facing_control(&mut state, id);
    state.update_encounters();
    state.advance_m02();
    let target_id = state
        .players
        .iter()
        .find(|p| p.name == "ward_sweeper")
        .unwrap()
        .id;
    assert!(state.encounters.is_active_enemy(target_id));
    let companion_id = state.spawn_m02_companion().unwrap();
    let companion = state
        .players
        .iter_mut()
        .find(|p| p.id == companion_id)
        .unwrap();
    [companion.x, companion.y, companion.z] = [6.5, PLAYER_FLOOR_Y, -10.0];
    companion.campaign = Some(CampaignActor::Companion {
        kind: crate::protocol::CompanionKind::Latch,
        phase: CompanionPhase::Following,
        phase_started: state.tick,
    });
    let (shooter, intent) = state.m02_companion_intent().unwrap();
    assert_eq!(shooter, companion_id);
    assert!(
        intent.action.fire,
        "visible active ward guard receives bounded support"
    );
    assert_eq!(
        intent.action.look_at.as_ref().unwrap().player_id,
        Some(target_id)
    );
    let (_, cooling) = state.m02_companion_intent().unwrap();
    assert!(!cooling.action.fire, "the support fire cadence is bounded");
    assert_eq!(
        state
            .mission
            .as_ref()
            .unwrap()
            .m02
            .as_ref()
            .unwrap()
            .support_shots,
        1
    );
    state.set_companion_action(companion_id, intent.action);
    state.tick(0.05);
    assert!(state.snapshot().shot_results.iter().any(|shot| {
        shot.shooter_id == companion_id && shot.target_id == Some(target_id) && shot.damage > 0
    }));
    assert_eq!(state.scores.get(&id), Some(&0));
    assert!(!state.scores.contains_key(&companion_id));
    let companion = state
        .players
        .iter_mut()
        .find(|p| p.id == companion_id)
        .unwrap();
    [companion.x, companion.y, companion.z] = [6.5, PLAYER_FLOOR_Y, -11.0];
    let hp = state.players.iter().find(|p| p.id == id).unwrap().hp;
    state.set_action(
        target_id,
        Action {
            fire: true,
            look_at: Some(LookAt {
                player_id: Some(id),
                ..LookAt::default()
            }),
            ..Action::default()
        },
    );
    state.tick(0.05);
    assert_eq!(
        state
            .players
            .iter()
            .find(|p| p.id == companion_id)
            .unwrap()
            .hp,
        100
    );
    assert!(state.players.iter().find(|p| p.id == id).unwrap().hp < hp);
    for enemy in state
        .players
        .iter_mut()
        .filter(|p| p.is_campaign_enemy() && p.id != target_id)
    {
        enemy.hp = 0;
    }
    let target = state
        .players
        .iter_mut()
        .find(|p| p.id == target_id)
        .unwrap();
    [target.x, target.y, target.z] = [8.5, PLAYER_FLOOR_Y, -13.2];
    let target_height = crate::combat::target_height(target.campaign);
    let companion = state
        .players
        .iter_mut()
        .find(|p| p.id == companion_id)
        .unwrap();
    [companion.x, companion.y, companion.z] = [7.0, PLAYER_FLOOR_Y, -11.0];
    state
        .mission
        .as_mut()
        .unwrap()
        .m02
        .as_mut()
        .unwrap()
        .last_support_tick = None;
    assert!(!crate::combat::line_of_sight(
        [7.0, crate::movement::EYE_HEIGHT, -11.0],
        [8.5, target_height * 0.5, -13.2],
        &state.map.arena().solids,
    ));
    assert!(!state.m02_companion_intent().unwrap().1.action.fire);
    let target = state
        .players
        .iter_mut()
        .find(|p| p.id == target_id)
        .unwrap();
    [target.x, target.y, target.z] = [4.0, PLAYER_FLOOR_Y, -11.0];
    state
        .mission
        .as_mut()
        .unwrap()
        .m02
        .as_mut()
        .unwrap()
        .support_shots = 12;
    assert!(!state.m02_companion_intent().unwrap().1.action.fire);
    let progress = state.mission.as_mut().unwrap().m02.as_mut().unwrap();
    progress.support_shots = 1;
    progress.last_support_tick = None;
    let companion = state
        .players
        .iter_mut()
        .find(|p| p.id == companion_id)
        .unwrap();
    [companion.x, companion.y, companion.z] = [6.5, PLAYER_FLOOR_Y, -10.0];
    let participant = state.players.iter_mut().find(|p| p.id == id).unwrap();
    [participant.x, participant.y, participant.z] = [5.25, PLAYER_FLOOR_Y, -10.5];
    let target = state.players.iter().find(|p| p.id == target_id).unwrap();
    assert!(crate::combat::line_of_sight(
        [6.5, crate::movement::EYE_HEIGHT, -10.0],
        [
            4.0,
            crate::combat::target_height(target.campaign) * 0.5,
            -11.0
        ],
        &state.map.arena().solids,
    ));
    assert!(!state.m02_companion_intent().unwrap().1.action.fire);
    assert_eq!(
        state
            .mission
            .as_ref()
            .unwrap()
            .m02
            .as_ref()
            .unwrap()
            .support_shots,
        1
    );
}

#[test]
fn companion_spread_cannot_turn_a_clear_support_shot_into_a_participant_hit() {
    let (mut state, participant_id) = ward_test_state();
    at_frame_facing_control(&mut state, participant_id);
    state.update_encounters();
    state.advance_m02();
    let target_id = state
        .players
        .iter()
        .find(|p| p.name == "ward_sweeper")
        .unwrap()
        .id;
    assert!(state.encounters.is_active_enemy(target_id));
    for enemy in state
        .players
        .iter_mut()
        .filter(|p| p.is_campaign_enemy() && p.id != target_id)
    {
        enemy.hp = 0;
    }
    let companion_id = state.spawn_m02_companion().unwrap();
    let companion = state
        .players
        .iter_mut()
        .find(|p| p.id == companion_id)
        .unwrap();
    [companion.x, companion.y, companion.z] = [6.5, PLAYER_FLOOR_Y, -10.0];
    companion.campaign = Some(CampaignActor::Companion {
        kind: crate::protocol::CompanionKind::Latch,
        phase: CompanionPhase::Following,
        phase_started: state.tick,
    });
    let target = state
        .players
        .iter_mut()
        .find(|p| p.id == target_id)
        .unwrap();
    [target.x, target.y, target.z] = [4.0, PLAYER_FLOOR_Y, -11.0];
    let participant = state
        .players
        .iter_mut()
        .find(|p| p.id == participant_id)
        .unwrap();
    [participant.x, participant.y, participant.z] = [5.25, PLAYER_FLOOR_Y, -11.05];
    let participant_hp = participant.hp;
    assert!(!state.spawn_shields.contains_key(&participant_id));

    let (_, intent) = state.m02_companion_intent().unwrap();
    assert!(intent.action.fire, "the centered preflight ray is clear");
    assert_eq!(
        intent.action.look_at.as_ref().unwrap().player_id,
        Some(target_id)
    );
    state.seed(9);
    state.set_companion_action(companion_id, intent.action);
    state.tick(0.0);

    assert_eq!(
        state
            .players
            .iter()
            .find(|p| p.id == participant_id)
            .unwrap()
            .hp,
        participant_hp
    );
    assert!(state
        .snapshot()
        .shot_results
        .iter()
        .all(|shot| { shot.shooter_id != companion_id || shot.target_id != Some(participant_id) }));
    let shot = state
        .snapshot()
        .shot_results
        .into_iter()
        .find(|shot| shot.shooter_id == companion_id && shot.target_id == Some(target_id))
        .expect("the shot passes through the participant and reaches the target");
    assert!(shot.damage > 0);
    let trace = shot.trace.unwrap();
    let delta: [f32; 3] = std::array::from_fn(|i| trace.end[i] - trace.origin[i]);
    let length = delta.iter().map(|v| v * v).sum::<f32>().sqrt();
    let ray = crate::combat::Ray {
        origin: trace.origin,
        direction: delta.map(|v| v / length),
    };
    assert!(
        ray.fighter_with_height(
            [5.25, 0.0, -11.05],
            crate::sim::PLAYER_RADIUS,
            crate::combat::FIGHTER_HEIGHT,
            length,
        )
        .is_some(),
        "the actual spread ray crosses the unshielded participant"
    );
}

#[test]
fn controlled_unshielded_escape_companion_reaches_floor_and_resolves_a_shot() {
    for difficulty in [
        crate::protocol::CampaignDifficulty::Standard,
        crate::protocol::CampaignDifficulty::Severe,
    ] {
        let mut session = session();
        session.state.seed(1);
        session.state.set_campaign_difficulty(difficulty).unwrap();
        let id = Uuid::from_u128(0x02ae);
        session
            .state
            .add_player(id, "Controlled observer".into(), Role::Human);
        assert!(session.state.acknowledge_m02(id, 1));
        at_frame_facing_control(&mut session.state, id);
        session.state.update_encounters();
        session.state.advance_m02();
        defeat_ward_guards(&mut session.state);
        session.state.update_encounters();
        session.state.players[0].interaction_requested = true;
        session.state.advance_m02();
        let ally_id = session
            .state
            .players
            .iter()
            .find(|p| p.is_campaign_companion())
            .unwrap()
            .id;
        // The live probe can reach the floor trigger while the 12-second
        // release tableau is still active.
        for _ in 0..LATCH_RELEASE_TICKS - 40 {
            session.tick_messages(0.05);
        }
        [
            session.state.players[0].x,
            session.state.players[0].y,
            session.state.players[0].z,
        ] = [5.5, PLAYER_FLOOR_Y, -6.0];
        // Keep this stationary observation alive without making its body
        // transparent to either side's hitscan. This is not a survivability
        // or normal combat pacing test.
        session.state.players[0].hp = crate::sim::PLAYER_MAX_HP;
        let mut resolved = None;
        let mut first_damage_step = None;
        let mut sampled_positions = Vec::new();
        let mut support_shots = 0;
        let mut support_damage = 0;
        let mut support_kills = 0;
        for step in 0..500 {
            session.tick_messages(0.05);
            let player = session
                .state
                .players
                .iter_mut()
                .find(|p| p.id == id)
                .unwrap();
            assert!(
                player.hp > 0,
                "controlled participant died at tick {}",
                step + 1
            );
            player.hp = crate::sim::PLAYER_MAX_HP;
            if [39, 99, 199].contains(&step) {
                let ally = session
                    .state
                    .players
                    .iter()
                    .find(|p| p.id == ally_id)
                    .unwrap_or_else(|| panic!("companion missing at controlled tick {}", step + 1));
                sampled_positions.push((step + 1, ally.x, ally.z));
            }
            for shot in session
                .state
                .shot_results
                .iter()
                .filter(|shot| shot.shooter_id == ally_id)
            {
                support_shots += 1;
                support_damage += shot.damage.max(0);
                support_kills += usize::from(shot.killed);
                if shot.damage > 0 && resolved.is_none() {
                    first_damage_step = Some(step + 1);
                    resolved = Some(shot.clone());
                }
            }
        }
        let shot = resolved.unwrap_or_else(|| {
        let ally = session.state.players.iter().find(|p| p.id == ally_id).unwrap();
        panic!(
            "Latch must support the active floor group in the controlled stationary case: ally [{:.1},{:.1},{:.1}], phase {:?}, shots {}, floor enemies {:?}",
            ally.x,
            ally.y - PLAYER_FLOOR_Y,
            ally.z,
            ally.campaign,
            session.state.mission.as_ref().unwrap().m02.as_ref().unwrap().support_shots,
            session.state.players.iter().filter(|p| p.name.starts_with("floor_") || p.name.starts_with("press_") || p.name.starts_with("conveyor_")).map(|p| (&p.name, p.hp, p.x, p.z)).collect::<Vec<_>>()
        )
    });
        assert!(shot.target_id.is_some());
        assert_eq!(
            shot.trace.unwrap().weapon,
            crate::protocol::WeaponType::Tack
        );
        assert_eq!(
            session.state.mission_state().unwrap().phase,
            MissionPhase::InProgress
        );
        let living_floor = session
            .state
            .players
            .iter()
            .filter(|p| {
                matches!(
                    p.name.as_str(),
                    "floor_officer" | "floor_sweeper" | "press_clerk" | "conveyor_sweeper"
                ) && p.hp > 0
            })
            .count();
        let ally = session
            .state
            .players
            .iter()
            .find(|p| p.id == ally_id)
            .unwrap();
        let participant = session.state.players.iter().find(|p| p.id == id).unwrap();
        let separation = (ally.x - participant.x).hypot(ally.z - participant.z);
        assert!(
            separation >= 2.0,
            "the floor formation must not crowd the player"
        );
        assert!(
            living_floor > 0,
            "Latch must not clear the floor while the player waits"
        );
        assert!(support_shots <= 12);
        eprintln!("M02 controlled unshielded escape {difficulty:?}: first damaging shot tick {:?}, companion positions at ticks 40/100/200 {:?}, shots {support_shots}, damage {support_damage}, kills {support_kills}, floor enemies alive {living_floor}, separation {separation:.2}m, ally [{:.2},{:.2}]", first_damage_step, sampled_positions, ally.x, ally.z);
    }
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
    [
        session.state.players[0].x,
        session.state.players[0].y,
        session.state.players[0].z,
    ] = [23.5, PLAYER_FLOOR_Y, 6.5];
    session.state.update_encounters();
    for enemy in session.state.players.iter_mut().filter(|player| {
        matches!(
            player.name.as_str(),
            "side_ward_clerk" | "side_ward_sweeper"
        )
    }) {
        enemy.hp = 0;
    }
    session.state.update_encounters();
    assert!(session.state.m02_side_ward_secured());
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
        Some((crate::session::Recipient::Client(client), ServerMessage::MapInfo { solids, m02_side_ward: true, .. }))
            if *client == watcher && solids.iter().any(|solid| {
                solid.min_x == 4.0 && solid.max_x == 7.0
                    && solid.min_z == -8.0 && solid.max_z == -7.0
                    && solid.bottom == 4.0
            })
    ));
    assert!(messages.iter().any(|(recipient, message)| {
        matches!(recipient, crate::session::Recipient::Client(client) if *client == watcher)
            && matches!(message, ServerMessage::Mission { state, .. }
                if state.party.len() == 1
                    && state.m02.as_ref().is_some_and(|m02|
                        m02.ward_secured
                            && m02.side_ward_secured
                            && m02.evacuation.as_ref().is_some_and(|evacuation|
                                evacuation.phase == crate::protocol::M02EvacuationPhase::Held
                                    && evacuation.captives
                                        == crate::protocol::M02EvacuationState::HELD_FEET)
                            && m02.completed == ["ward_reached", "companion_released"]))
    }));
    assert_eq!(session.state.mission_state().unwrap().party.len(), 1);
    let snapshot = session.state.snapshot();
    assert!(snapshot
        .players
        .iter()
        .find(|p| p.campaign.is_some_and(CampaignActor::is_companion))
        .unwrap()
        .body
        .is_none());
    assert_eq!(
        snapshot
            .players
            .iter()
            .filter(|p| matches!(
                p.campaign,
                Some(CampaignActor::Companion {
                    phase: CompanionPhase::Releasing,
                    ..
                })
            ))
            .count(),
        1
    );
    let ally_id = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_companion())
        .unwrap()
        .id;
    session.state.advance_m02_evacuation(0.05);
    let before_departure = session
        .state
        .mission_state()
        .unwrap()
        .m02
        .unwrap()
        .evacuation;
    assert_eq!(
        before_departure.as_ref().unwrap().phase,
        crate::protocol::M02EvacuationPhase::Freeing
    );
    [
        session.state.players[0].x,
        session.state.players[0].y,
        session.state.players[0].z,
    ] = [0.0, PLAYER_FLOOR_Y, 21.5];
    session.state.advance_m02();
    assert!(session.state.mission_departed());
    let before = session
        .state
        .players
        .iter()
        .find(|p| p.id == ally_id)
        .unwrap();
    let feet = [before.x, before.y, before.z];
    session.state.set_companion_action(
        ally_id,
        Action {
            forward: true,
            ..Action::default()
        },
    );
    session.state.tick(0.05);
    assert_eq!(
        session
            .state
            .mission_state()
            .unwrap()
            .m02
            .unwrap()
            .evacuation,
        before_departure,
        "early party departure freezes optional captive progress"
    );
    let after = session
        .state
        .players
        .iter()
        .find(|p| p.id == ally_id)
        .unwrap();
    assert_eq!([after.x, after.y, after.z], feet);
    assert_eq!(
        session
            .state
            .snapshot()
            .players
            .iter()
            .filter(|p| p.id == ally_id)
            .count(),
        1
    );
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
    // Releasing Latch opens the only route out of the ward.
    assert!(map.prepared_gate_world(0).is_some());
    assert!(map.prepared_gate_world(1).is_some());
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
        &wire,
        ServerMessage::MapInfo {
            m02_side_ward: true,
            ..
        }
    ));
    assert_eq!(serde_json::to_value(&wire).unwrap()["m02_side_ward"], true);
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
        assert_eq!(walker.maps, 2, "{role:?}: release opens the ward exit");
        assert_eq!(
            walker.defeated.len(),
            ENEMIES,
            "{role:?} clears the optional room on this authored route"
        );
        let state = session.state.mission_state().unwrap();
        assert_eq!(state.phase, MissionPhase::Departed);
        assert_eq!(state.attempt, 1);
        let me = session.state.players.iter().find(|p| p.id == id).unwrap();
        eprintln!(
            "M02 graybox {role:?}: departed after {ticks} ticks, hp {}, armor {}, defeats {}, player shots {}, enemy shots {}, companion shots {}, companion damage {}, companion kills {}",
            me.hp,
            me.armor,
            walker.defeated.len(),
            walker.shots,
            walker.enemy_shots,
            walker.companion_shots,
            walker.companion_damage,
            walker.companion_kills
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
    assert_eq!(m02.gate_mask, 0);
    assert!(session.state.map.arena().solids.iter().any(|solid| {
        solid.min_x == 4.0
            && solid.max_x == 7.0
            && solid.min_z == -8.0
            && solid.max_z == -7.0
            && solid.bottom == 0.0
    }));
    assert!(!session.state.m02_ward_secured());
    assert!(!session.state.m02_side_ward_secured());
    assert_eq!(m02.current.unwrap().id, "ward_reached");
    assert!(session.state.pickups.iter().all(|pickup| pickup.available));
    walker.until(&mut session, 200, |session, _| {
        living_enemies(session) == ENEMIES
    });
    assert!(session
        .state
        .players
        .iter()
        .any(|player| { player.name == "side_ward_clerk" && player.hp > 0 }));
    // The same participant then fights through again from entry.
    walker.reset_attempt_evidence(&session);
    walker.until(&mut session, 14000, departed);
    walker.read(session.tick_messages(0.05));
    assert_guard_room_lesson(&walker);
    assert_eq!(walker.completed, ORDER);
    assert_eq!(
        walker.defeated.len(),
        ENEMIES,
        "{:?}",
        walker.defeated_names
    );
    assert_eq!(session.state.mission_state().unwrap().attempt, 2);
}
