//! Play the committed opening through ordinary movement, inventory and combat.
use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
use crate::maps::AuthoredMap;
use crate::movement::{Arena, CONTACT_EPSILON, EYE_HEIGHT, RADIUS};
use crate::navigation::{NavigationGoal, Navigator, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    Action, AmmoPool, CampaignActor, EnemyPhase, LookAt, MapDecorationKind, Role, ShotImpact,
    WeaponType,
};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::BTreeSet;
use uuid::Uuid;

/// The magazine-era test emptied one 30 round Flechette magazine here.
const WASTED_BYPASS_BULLETS: usize = 30;

struct Walkthrough {
    session: GameSession,
    id: Uuid,
    navigator: Navigator,
    seen: BTreeSet<Uuid>,
    spawned: BTreeSet<Uuid>,
    defeated: BTreeSet<Uuid>,
    intake: BTreeSet<Uuid>,
    shots: usize,
    first_threat: Option<u64>,
    first_shot: Option<u64>,
}

impl Walkthrough {
    fn new(role: Role) -> Self {
        Self::configured(role, false)
    }

    fn configured(role: Role, solo_run: bool) -> Self {
        let map = AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice())
            .unwrap();
        let mut session = GameSession::with_authored_map(map);
        session.state.seed(67);
        if solo_run {
            session.state.enable_campaign_run().unwrap();
        }
        let id = Uuid::from_u128(100);
        session.state.add_player(id, "Visitor".into(), role);
        let mission = session.state.mission_state().unwrap();
        session.apply_command(crate::net::GameCommand::MissionReady {
            player_id: id,
            ready: crate::protocol::MissionReady {
                id: mission.id,
                attempt: mission.attempt,
            },
        });
        Self {
            session,
            id,
            navigator: Navigator::default(),
            seen: BTreeSet::new(),
            spawned: BTreeSet::new(),
            defeated: BTreeSet::new(),
            intake: BTreeSet::new(),
            shots: 0,
            first_threat: None,
            first_shot: None,
        }
    }

    fn assert_optional_caches_unclaimed(&self) {
        for id in ["bay_medkit", "overlook_armor"] {
            assert!(
                self.session
                    .state
                    .pickups
                    .iter()
                    .find(|pad| pad.id == id)
                    .unwrap()
                    .available,
                "ordinary route claimed optional cache {id}"
            );
        }
    }

    fn step(&mut self, destination: [f32; 3]) {
        let snapshot = self.session.state.snapshot();
        let me = snapshot
            .players
            .iter()
            .find(|p| p.id == self.id)
            .unwrap_or_else(|| {
                let body = self
                    .session
                    .state
                    .players
                    .iter()
                    .find(|p| p.id == self.id)
                    .unwrap();
                panic!(
                    "participant died before {destination:?} at {:?} after {} defeats and {} shots",
                    [body.x, body.y, body.z],
                    self.defeated.len(),
                    self.shots
                );
            });
        assert!(me.hp > 0, "opening route killed the participant");
        let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
        let eye = [me.x, feet[1] + EYE_HEIGHT, me.z];
        let visible: Vec<_> = snapshot
            .players
            .iter()
            .filter(|p| {
                me.is_hostile_to(p)
                    && line_of_sight(
                        eye,
                        [p.x, p.y - PLAYER_FLOOR_Y + FIGHTER_HEIGHT * 0.5, p.z],
                        &self.session.state.map.arena().solids,
                    )
            })
            .collect();
        for actor in &snapshot.players {
            if matches!(
                actor.name.as_str(),
                "intake_security" | "records_sweeper_west" | "records_sweeper_east"
            ) {
                self.intake.insert(actor.id);
            }
        }
        for target in &visible {
            self.seen.insert(target.id);
        }
        let target = visible.iter().min_by(|a, b| {
            (a.x - me.x)
                .hypot(a.z - me.z)
                .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
        });
        let action = if let Some(target) = target {
            self.first_threat.get_or_insert(snapshot.tick);
            let player = &self.session.state.players[0];
            let loadout = player
                .inventory
                .state(self.id, player.weapon, snapshot.tick)
                .unwrap();
            let dry = loadout.shots(player.weapon) == Some(0);
            Action {
                // React to a visible committed tell with ordinary strafing.
                // This is an accurate-aim moving run, not first-player balance.
                left: visible.iter().any(|enemy| {
                    matches!(
                        enemy.campaign,
                        Some(CampaignActor::Union {
                            phase: EnemyPhase::Windup | EnemyPhase::Firing,
                            ..
                        })
                    )
                }),
                look_at: Some(LookAt {
                    player_id: Some(target.id),
                    ..Default::default()
                }),
                fire: !dry,
                ..Default::default()
            }
        } else {
            self.navigator.steer(
                self.session.state.map.navigation(),
                feet,
                NavigationGoal {
                    feet: destination,
                    combat: false,
                },
                Action::default(),
                snapshot.tick,
                true,
            )
        };
        self.session.state.set_action(self.id, action);
        self.session.tick_messages(0.05);
        for shot in &self.session.state.shot_results {
            if shot.shooter_id == self.id {
                self.first_shot.get_or_insert(self.session.state.tick);
                self.shots += 1;
            }
        }
        for p in &self.session.state.players {
            if p.is_campaign_enemy() && self.spawned.insert(p.id) {
                let participant = &self.session.state.players[0];
                let viewer = [
                    participant.x,
                    participant.y - PLAYER_FLOOR_Y + EYE_HEIGHT,
                    participant.z,
                ];
                for height in [0.2, FIGHTER_HEIGHT * 0.5, FIGHTER_HEIGHT] {
                    assert!(
                        !line_of_sight(
                            viewer,
                            [p.x, p.y - PLAYER_FLOOR_Y + height, p.z],
                            &self.session.state.map.arena().solids
                        ),
                        "{} appeared in sight at {:?} from {viewer:?}",
                        p.name,
                        [p.x, p.y, p.z]
                    );
                }
            }
            if matches!(
                p.campaign,
                Some(CampaignActor::Union {
                    phase: EnemyPhase::Dead,
                    ..
                })
            ) {
                self.defeated.insert(p.id);
            }
        }
    }

    fn walk(&mut self, destination: [f32; 3]) {
        for _ in 0..1600 {
            let player = &self.session.state.players[0];
            if (player.x - destination[0]).hypot(player.z - destination[2]) < 0.65
                && (player.y - PLAYER_FLOOR_Y - destination[1]).abs() < 0.1
            {
                return;
            }
            self.step(destination);
        }
        let player = &self.session.state.players[0];
        panic!(
            "route to {destination:?} stalled at {:?}; defeated {}",
            [player.x, player.y - PLAYER_FLOOR_Y, player.z],
            self.defeated.len()
        );
    }

    fn use_control(&mut self, record: bool) {
        let map = self.session.state.map.clone();
        let geometry = map.mission().unwrap();
        let target = if record {
            &geometry.record
        } else {
            &geometry.departure
        };
        self.walk(target.approach);
        // Finish the approach precisely enough for arm's-reach interaction.
        for _ in 0..20 {
            let p = &self.session.state.players[0];
            if (p.x - target.approach[0]).hypot(p.z - target.approach[2]) < 0.3 {
                break;
            }
            self.step(target.approach);
        }
        let point = target
            .point(map.presentation_ref().unwrap(), &map.arena().solids)
            .unwrap();
        self.session.state.set_action(
            self.id,
            Action {
                interact: true,
                look_at: Some(LookAt {
                    x: Some(point[0]),
                    y: Some(point[1]),
                    z: Some(point[2]),
                    player_id: None,
                }),
                ..Action::default()
            },
        );
        self.session.tick_messages(0.05);
        self.session.state.set_action(self.id, Action::default());
        assert_eq!(
            self.session.state.mission_state().unwrap().phase,
            if record {
                crate::protocol::MissionPhase::ReachLift
            } else {
                crate::protocol::MissionPhase::Departed
            }
        );
        self.navigator.clear();
    }

    fn on_bypass(&self, feet: [f32; 3]) -> bool {
        self.session
            .state
            .map
            .encounters()
            .iter()
            .find(|group| group.id == "bypass_watch")
            .is_some_and(|group| group.regions.iter().any(|region| region.contains(feet)))
    }

    /// Fire thirty bullets into the bypass ceiling. Misses here are spent
    /// before sorting and transfer, and they do not claim file-stack stock.
    fn waste_bypass_bullets(&mut self) -> usize {
        let needed = WASTED_BYPASS_BULLETS;
        let anchor = [-18.0, 3.0, 27.0];
        self.walk(anchor);
        assert_eq!(
            self.session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .unwrap()
                .weapon,
            WeaponType::Flechette
        );
        let mut wasted = 0usize;
        for _ in 0..600 {
            if wasted >= needed {
                break;
            }
            let snapshot = self.session.state.snapshot();
            let me = snapshot
                .players
                .iter()
                .find(|player| player.id == self.id)
                .unwrap_or_else(|| {
                    panic!("died on the bypass after {wasted} wasted rounds");
                });
            let feet = [me.x, me.y - PLAYER_FLOOR_Y, me.z];
            let telling = snapshot.players.iter().any(|enemy| {
                me.is_hostile_to(enemy)
                    && matches!(
                        enemy.campaign,
                        Some(CampaignActor::Union {
                            phase: EnemyPhase::Windup | EnemyPhase::Firing,
                            ..
                        })
                    )
            });
            // Yaw zero faces +X, so left is south and right is north.
            let south = feet[2] > anchor[2] + 0.75 || (telling && feet[2] >= anchor[2]);
            let north = !south && (feet[2] < anchor[2] - 0.75 || telling);
            let player = self
                .session
                .state
                .players
                .iter()
                .find(|player| player.id == self.id)
                .unwrap();
            let loadout = player
                .inventory
                .state(self.id, player.weapon, snapshot.tick)
                .unwrap();
            let dry = loadout.shots(player.weapon) == Some(0);
            self.session.state.set_action(
                self.id,
                Action {
                    forward: feet[0] < anchor[0] - 0.35,
                    back: feet[0] > anchor[0] + 0.35,
                    left: south,
                    right: north,
                    yaw: Some(0.0),
                    look_at: Some(LookAt {
                        x: Some(feet[0]),
                        y: Some(feet[1] + 12.0),
                        z: Some(feet[2]),
                        player_id: None,
                    }),
                    fire: !dry,
                    ..Action::default()
                },
            );
            self.session.tick_messages(0.05);
            for shot in &self.session.state.shot_results {
                if shot.shooter_id != self.id {
                    continue;
                }
                self.shots += 1;
                if shot.hit {
                    continue;
                }
                assert!(
                    matches!(
                        shot.trace.as_ref().map(|trace| &trace.impact),
                        Some(ShotImpact::Solid { .. })
                    ),
                    "a wasted bypass round left the building"
                );
                let body = self
                    .session
                    .state
                    .players
                    .iter()
                    .find(|player| player.id == self.id)
                    .unwrap();
                let now = [body.x, body.y - PLAYER_FLOOR_Y, body.z];
                assert!(
                    self.on_bypass(now),
                    "wasted round left the bypass at {now:?}"
                );
                wasted += 1;
            }
            for player in &self.session.state.players {
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
        }
        assert!(
            wasted >= needed,
            "bypass waste stalled at {wasted} of {needed}"
        );
        self.navigator.clear();
        wasted
    }
}

#[test]
fn m01_optional_caches_are_walking_detours_in_both_lift_states() {
    let authored =
        AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice()).unwrap();
    let pairs = [
        ("confiscation_bay", "confiscation_alcove", "bay_medkit"),
        (
            "maintenance_landing",
            "maintenance_overlook",
            "overlook_armor",
        ),
    ];
    let session = GameSession::with_authored_map(authored.clone());
    for (approach, landmark, reward) in pairs {
        let start = authored.landmark(approach).unwrap();
        let cache = authored.landmark(landmark).unwrap();
        assert!(
            (cache[0] - start[0]).hypot(cache[2] - start[2])
                > crate::sim::PICKUP_CLAIM_RADIUS + RADIUS,
            "{reward} can be claimed without leaving the ordinary approach"
        );
        for map in [
            session.state.map.clone(),
            session.state.map.opened_route().unwrap(),
        ] {
            for (from, to) in [(start, cache), (cache, start)] {
                let route = map.navigation().route(from, to, SEARCH_LIMIT);
                assert_eq!(route.status, RouteStatus::Complete, "{landmark}: {route:?}");
                assert!(
                    route.points.iter().all(|point| {
                        (point[1] - cache[1]).abs() <= CONTACT_EPSILON && point[2] < 12.0
                    }),
                    "{landmark} detour leaves its original floor or enters records"
                );
            }
            let pad = map.pickups().into_iter().find(|p| p.id == reward).unwrap();
            assert_eq!([pad.x, pad.floor, pad.z], cache);
            assert_eq!(pad.amount, 25);
        }
    }
    let cache = authored.landmark("maintenance_overlook").unwrap();
    let eye = [cache[0], cache[1] + EYE_HEIGHT, cache[2]];
    assert!(
        line_of_sight(eye, [-17.0, 2.7, -1.0], &session.state.map.arena().solids),
        "maintenance overlook must show the service stair below"
    );
}

#[test]
fn m01_optional_caches_are_consumed_once_and_restore_on_continue() {
    let mut run = Walkthrough::configured(Role::Human, true);
    run.walk([0.0, 0.0, -26.0]);
    run.walk([0.0, 0.0, -21.0]);
    for _ in 0..400 {
        if run
            .session
            .state
            .players
            .iter()
            .all(|p| p.name != "intake_security" || p.hp <= 0)
        {
            break;
        }
        run.step([0.0, 0.0, -21.0]);
    }
    // Stage a useful health claim after the taught fight. Travel and collection
    // still go through the normal controller, collision and pickup rules.
    run.session.state.players[0].hp = 50;
    run.walk([9.0, 0.0, -21.0]);
    assert_eq!(run.session.state.players[0].hp, 75);
    run.walk([0.0, 0.0, -21.0]);
    run.session.state.players[0].hp = 50;
    run.walk([9.0, 0.0, -21.0]);
    assert_eq!(run.session.state.players[0].hp, 50);
    for point in [
        [0.0, 0.0, -21.0],
        [-8.0, 0.0, -18.0],
        [-17.0, 0.0, -18.0],
        [-17.0, 0.0, -14.0],
        [-17.0, 3.0, 8.0],
    ] {
        run.walk(point);
    }
    for _ in 0..400 {
        if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
            break;
        }
        run.step([-17.0, 3.0, 8.0]);
    }
    assert!(run.intake.len() == 3 && run.intake.is_subset(&run.defeated));
    run.session.state.players[0].armor = 0;
    for point in [[-18.5, 3.0, 4.0], [-20.5, 3.0, 3.8]] {
        run.walk(point);
    }
    assert_eq!(run.session.state.players[0].armor, 25);
    run.walk([-17.0, 3.0, 8.0]);
    run.session.state.players[0].armor = 0;
    for point in [[-18.5, 3.0, 4.0], [-20.5, 3.0, 3.8]] {
        run.walk(point);
    }
    run.session.state.set_action(run.id, Action::default());
    for _ in 0..=crate::sim::HEALTH_PICKUP_RESPAWN_TICKS {
        run.session.tick_messages(0.05);
    }
    assert_eq!(run.session.state.players[0].armor, 0);
    for id in ["bay_medkit", "overlook_armor"] {
        let pad = run
            .session
            .state
            .pickups
            .iter()
            .find(|p| p.id == id)
            .unwrap();
        assert!(!pad.available);
        assert!(pad.respawn_timer.is_none());
    }
    let before = run.session.state.mission_state().unwrap();
    run.session.state.players[0].hp = 0;
    run.session.tick_messages(0.05);
    assert!(run.session.state.continue_mission(
        run.id,
        crate::protocol::MissionContinue {
            id: before.id,
            run_id: before.run.unwrap().id,
            attempt: before.attempt,
        },
    ));
    run.assert_optional_caches_unclaimed();
    assert_eq!(run.session.state.players[0].hp, 100);
    assert_eq!(run.session.state.players[0].armor, 0);
    assert_eq!(run.session.state.players[0].weapon, WeaponType::Fists);
    assert_eq!(
        run.session
            .state
            .mission_state()
            .unwrap()
            .run
            .unwrap()
            .continues,
        2
    );
}

#[test]
fn later_guards_are_screened_from_the_previous_encounter_approach() {
    let run = Walkthrough::new(Role::Human);
    for (feet, groups) in [
        (
            [8.0, 3.0, 9.0],
            vec![
                "records_patrol",
                "bypass_watch",
                "stacks_patrol",
                "sorting_security",
                "dispatch_security",
                "transfer_watch",
            ],
        ),
        (
            [-17.0, 3.0, 8.0],
            vec![
                "records_patrol",
                "bypass_watch",
                "stacks_patrol",
                "sorting_security",
                "dispatch_security",
                "transfer_watch",
            ],
        ),
        ([-11.0, 3.0, 36.0], vec!["transfer_watch"]),
    ] {
        let eye = [feet[0], feet[1] + EYE_HEIGHT, feet[2]];
        for encounter in run
            .session
            .state
            .map
            .encounters()
            .iter()
            .filter(|group| groups.contains(&group.id.as_str()))
        {
            for enemy in &encounter.enemies {
                for height in [0.2, FIGHTER_HEIGHT * 0.5, FIGHTER_HEIGHT] {
                    assert!(
                        !line_of_sight(
                            eye,
                            [enemy.feet[0], enemy.feet[1] + height, enemy.feet[2]],
                            &run.session.state.map.arena().solids
                        ),
                        "{} visible before its approach from {feet:?}",
                        enemy.id
                    );
                }
            }
        }
    }
}

#[test]
fn m01_main_and_maintenance_approaches_clear_with_discovered_equipment() {
    for role in [Role::Human, Role::Agent] {
        for maintenance in [false, true] {
            let mut run = Walkthrough::new(role);
            run.walk([0.0, 0.0, -26.0]);
            assert_eq!(run.session.state.players[0].weapon, WeaponType::Tack);
            assert!(run.first_threat.is_none(), "first weapon must be safe");
            assert!(run.seen.is_empty());
            if maintenance {
                for point in [
                    [-8.0, 0.0, -18.0],
                    [-17.0, 0.0, -18.0],
                    [-17.0, 0.0, -14.0],
                    [-17.0, 3.0, 8.0],
                ] {
                    run.walk(point);
                }
            } else {
                run.walk([0.0, 0.0, -10.0]);
                for _ in 0..400 {
                    if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
                        break;
                    }
                    run.step([0.0, 0.0, -10.0]);
                }
                run.walk([6.0, 0.0, -9.0]);
                run.walk([8.0, 0.0, -8.0]);
                run.walk([8.0, 3.0, 9.0]);
            }
            for _ in 0..400 {
                if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
                    break;
                }
                let p = &run.session.state.players[0];
                run.step([p.x, p.y - PLAYER_FLOOR_Y, p.z]);
            }
            assert_eq!(
                run.intake.intersection(&run.defeated).count(),
                3,
                "{role:?}, maintenance={maintenance}; {:?}",
                run.session.state.snapshot().players
            );
            assert!(
                run.intake.is_subset(&run.seen),
                "every intake guard was seen before defeat"
            );
            assert_eq!(run.session.state.players[0].weapon, WeaponType::Flechette);
            run.walk([-19.0, 3.0, 9.0]);
            run.walk([-15.5, 3.0, 17.5]);
            run.walk([-19.0, 3.0, 23.0]);
            if maintenance {
                for point in [[-21.0, 3.0, 27.0], [-16.0, 3.0, 26.0], [-18.0, 3.0, 31.0]] {
                    run.walk(point);
                }
            } else {
                for point in [
                    [-25.0, 3.0, 18.0],
                    [-25.5, 3.0, 23.0],
                    [-32.0, 3.0, 17.0],
                    [-41.5, 3.0, 17.0],
                    [-41.5, 3.0, 14.5],
                    [-37.0, 3.0, 27.0],
                    [-37.0, 3.0, 31.0],
                ] {
                    run.walk(point);
                }
            }
            for point in [
                [-28.0, 3.0, 32.0],
                [-41.5, 3.0, 40.0],
                [-22.0, 3.0, 41.0],
                [-11.0, 3.0, 36.0],
                [-3.0, 3.0, 42.0],
                [-10.5, 3.0, 42.0],
                [-3.0, 3.0, 29.0],
            ] {
                run.walk(point);
            }
            run.walk([-3.0, 3.0, 20.0]);
            run.use_control(true);
            run.walk([7.0, 3.0, 23.0]);
            run.use_control(false);
            run.assert_optional_caches_unclaimed();
            assert!(run.defeated.len() >= if maintenance { 16 } else { 19 });
            assert_eq!(run.session.state.scores[&run.id], 0);
            eprintln!("M01 {role:?} maintenance={maintenance}: ticks={}, hp={}, defeats={}, shots={}, first_threat={:?}, first_shot={:?}",
                run.session.state.tick, run.session.state.players[0].hp, run.defeated.len(), run.shots, run.first_threat, run.first_shot);
        }
    }
}

#[test]
fn east_bypass_departs_with_all_stack_guards_alive() {
    let mut run = Walkthrough::new(Role::Human);
    let solids = run.session.state.map.arena().solids.clone();
    let stack_guards: Vec<_> = [
        "stacks_clerk",
        "archive_clerk",
        "stacks_sweeper",
        "archive_sweeper",
    ]
    .into_iter()
    .map(|id| {
        let enemy = run
            .session
            .state
            .map
            .encounters()
            .iter()
            .flat_map(|group| group.enemies.iter())
            .find(|enemy| enemy.id == id)
            .unwrap();
        (id, enemy.feet)
    })
    .collect();
    // The records approach used to kill stacks_sweeper through the stacks
    // doorway, then lose the reception threshold while clearing the bypass
    // and sorting early. The cabinet return and counter screen close both.
    for feet in [
        [-18.5, 3.0, 10.7],
        [-18.4, 3.0, 10.0],
        [-19.2, 3.0, 12.0],
        [-16.6, 3.0, 8.4],
        [-16.5, 3.0, 14.5],
        [-15.5, 3.0, 16.2],
    ] {
        let eye = [feet[0], feet[1] + EYE_HEIGHT, feet[2]];
        for encounter in run.session.state.map.encounters().iter().filter(|group| {
            matches!(
                group.id.as_str(),
                "stacks_patrol" | "bypass_watch" | "sorting_security" | "dispatch_security"
            )
        }) {
            for enemy in &encounter.enemies {
                for height in [0.2, FIGHTER_HEIGHT * 0.5, FIGHTER_HEIGHT] {
                    assert!(
                        !line_of_sight(
                            eye,
                            [enemy.feet[0], enemy.feet[1] + height, enemy.feet[2]],
                            &solids
                        ),
                        "{} is visible from the records approach at {feet:?}",
                        enemy.id
                    );
                }
            }
        }
    }
    run.walk([0.0, 0.0, -26.0]);
    for point in [
        [-8.0, 0.0, -18.0],
        [-17.0, 0.0, -18.0],
        [-17.0, 0.0, -14.0],
        [-17.0, 3.0, 8.0],
    ] {
        run.walk(point);
    }
    for _ in 0..400 {
        if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
            break;
        }
        let player = &run.session.state.players[0];
        run.step([player.x, player.y - PLAYER_FLOOR_Y, player.z]);
    }
    assert_eq!(run.intake.intersection(&run.defeated).count(), 3);
    assert_eq!(run.session.state.players[0].weapon, WeaponType::Flechette);
    run.walk([-19.0, 3.0, 9.0]);
    run.walk([-15.5, 3.0, 17.5]);
    run.walk([-19.0, 3.0, 23.0]);
    let guards_alive = |run: &Walkthrough| {
        stack_guards.iter().all(|(id, _)| {
            run.session
                .state
                .players
                .iter()
                .any(|player| player.name == *id && player.hp > 0)
        })
    };
    assert!(
        guards_alive(&run),
        "a stack guard died on the records approach"
    );
    for point in [
        [-21.0, 3.0, 27.0],
        [-16.0, 3.0, 26.0],
        [-18.0, 3.0, 31.0],
        [-18.0, 3.0, 38.0],
        [-22.0, 3.0, 41.0],
        [-11.0, 3.0, 36.0],
        [-3.0, 3.0, 42.0],
        [-10.5, 3.0, 42.0],
        [-3.0, 3.0, 29.0],
    ] {
        run.walk(point);
    }
    run.walk([-3.0, 3.0, 20.0]);
    run.use_control(true);
    run.walk([7.0, 3.0, 23.0]);
    run.use_control(false);
    run.assert_optional_caches_unclaimed();
    assert!(guards_alive(&run), "a stack guard died on the east bypass");
    for (id, _) in &stack_guards {
        let guard = run
            .session
            .state
            .players
            .iter()
            .find(|player| player.name == *id)
            .unwrap();
        assert!(
            !run.seen.contains(&guard.id) && !run.defeated.contains(&guard.id),
            "{id} was seen or defeated on the east bypass"
        );
    }
    assert!(
        run.defeated.len() >= 16,
        "east bypass skipped a fought encounter"
    );
    for id in ["stacks_bullets", "stacks_armor", "stacks_medkit"] {
        let pad = run
            .session
            .state
            .pickups
            .iter()
            .find(|pad| pad.id == id)
            .unwrap();
        assert!(pad.available, "{id} was claimed on the east bypass");
    }
    let player = run
        .session
        .state
        .players
        .iter()
        .find(|player| player.id == run.id)
        .unwrap();
    eprintln!(
        "M01 east bypass sightline: ticks={}, hp={}, armor={}, defeats={}, shots={}",
        run.session.state.tick,
        player.hp,
        player.armor,
        run.defeated.len(),
        run.shots
    );
}

#[test]
fn recall_notice_rooms_do_not_share_one_floor() {
    let doc: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../maps/m01-recall-notice.json")).unwrap();
    let solids = doc["solids"].as_array().unwrap();
    let surface = |id: &str| -> &str {
        solids
            .iter()
            .find(|solid| solid["id"] == id)
            .unwrap_or_else(|| panic!("missing solid {id}"))["surface"]
            .as_str()
            .unwrap()
    };
    assert_eq!(surface("reception_floor"), "records_tile");
    assert_eq!(surface("reception_east"), "enamel");
    assert_eq!(surface("stacks_floor"), "records_tile");
    assert_eq!(surface("stacks_south"), "service_steel");
    assert_eq!(surface("sorting_floor"), "concrete");
    assert_eq!(surface("dispatch_floor"), "service_steel");
    assert_eq!(surface("lift_gate"), "lift_panel");
    assert_ne!(surface("reception_floor"), surface("sorting_floor"));
    assert_ne!(surface("reception_east"), surface("stacks_south"));
    assert_ne!(surface("sorting_floor"), surface("dispatch_floor"));
}

#[test]
fn the_bypass_is_its_own_encounter() {
    let map =
        AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice()).unwrap();
    let session = GameSession::with_authored_map(map);
    let encounters = session.state.map.encounters();
    let reception = encounters
        .iter()
        .find(|group| group.id == "records_patrol")
        .unwrap();
    let bypass = encounters
        .iter()
        .find(|group| group.id == "bypass_watch")
        .unwrap();
    assert!(reception
        .enemies
        .iter()
        .all(|enemy| enemy.id != "bypass_sentry"));
    assert_eq!(bypass.after.as_deref(), Some("records_patrol"));
    let sentry = bypass
        .enemies
        .iter()
        .find(|enemy| enemy.id == "bypass_sentry")
        .unwrap();
    let choice = [-19.0, 3.0, 23.0];
    let threshold = [-15.5, 3.0, 17.5];
    assert!(bypass
        .regions
        .iter()
        .all(|region| !region.contains(choice) && !region.contains(threshold)));
    let bullets = session
        .state
        .map
        .pickups()
        .into_iter()
        .find(|pickup| pickup.id == "bypass_bullets")
        .unwrap();
    assert!(
        (bullets.x - sentry.feet[0]).hypot(bullets.z - sentry.feet[2]) > 1.0,
        "bypass ammo is standing on the sentry"
    );
}

#[test]
fn bypass_clear_still_departs_after_wasted_rounds_without_stack_supplies() {
    let mut run = Walkthrough::new(Role::Human);
    run.walk([0.0, 0.0, -26.0]);
    assert_eq!(run.session.state.players[0].weapon, WeaponType::Tack);
    for point in [
        [-8.0, 0.0, -18.0],
        [-17.0, 0.0, -18.0],
        [-17.0, 0.0, -14.0],
        [-17.0, 3.0, 8.0],
    ] {
        run.walk(point);
    }
    for _ in 0..400 {
        if run.intake.len() == 3 && run.intake.is_subset(&run.defeated) {
            break;
        }
        let player = &run.session.state.players[0];
        run.step([player.x, player.y - PLAYER_FLOOR_Y, player.z]);
    }
    assert_eq!(run.intake.intersection(&run.defeated).count(), 3);
    assert_eq!(run.session.state.players[0].weapon, WeaponType::Flechette);
    run.walk([-19.0, 3.0, 9.0]);
    run.walk([-15.5, 3.0, 17.5]);
    run.walk([-19.0, 3.0, 23.0]);
    let wasted = run.waste_bypass_bullets();
    // Stay east of the file stacks. The west sorting points can path through
    // that room, so they cannot prove a sightline from the bypass.
    for point in [
        [-21.0, 3.0, 27.0],
        [-16.0, 3.0, 26.0],
        [-18.0, 3.0, 31.0],
        [-18.0, 3.0, 38.0],
        [-22.0, 3.0, 41.0],
        [-11.0, 3.0, 36.0],
        [-3.0, 3.0, 42.0],
        [-10.5, 3.0, 42.0],
        [-3.0, 3.0, 29.0],
    ] {
        run.walk(point);
    }
    run.walk([-3.0, 3.0, 20.0]);
    run.use_control(true);
    run.walk([7.0, 3.0, 23.0]);
    run.use_control(false);
    assert!(run.defeated.len() >= 16);
    run.assert_optional_caches_unclaimed();
    assert!(run
        .session
        .state
        .players
        .iter()
        .all(|player| player.name != "bypass_sentry" || player.hp <= 0));
    for id in ["stacks_bullets", "stacks_armor", "stacks_medkit"] {
        let pad = run
            .session
            .state
            .pickups
            .iter()
            .find(|pad| pad.id == id)
            .unwrap();
        assert!(pad.available, "{id} was claimed on the bypass clear");
    }
    let player = run
        .session
        .state
        .players
        .iter()
        .find(|player| player.id == run.id)
        .unwrap();
    let loadout = player
        .inventory
        .state(run.id, player.weapon, run.session.state.tick)
        .unwrap();
    eprintln!(
        "M01 wasted bypass: ticks={}, hp={}, armor={}, defeats={}, shots={}, wasted={}, bullets={}",
        run.session.state.tick,
        player.hp,
        player.armor,
        run.defeated.len(),
        run.shots,
        wasted,
        loadout.ammo(AmmoPool::Bullets)
    );
}

fn stands_on_records_deck(arena: &Arena, feet: [f32; 3]) -> bool {
    let [x, y, z] = feet;
    (y - 3.0).abs() <= CONTACT_EPSILON
        && (-12.0..=12.0).contains(&x)
        && (6.0..=12.0).contains(&z)
        && !arena.blocked_body_at(x, z, y, y)
        && [-RADIUS, RADIUS].into_iter().all(|dx| {
            [-RADIUS, RADIUS].into_iter().all(|dz| {
                (arena.support_height(x + dx, z + dz, y + CONTACT_EPSILON) - y).abs()
                    <= CONTACT_EPSILON
            })
        })
}

#[test]
fn records_balcony_sees_the_lift_sign_but_not_the_transfer_guards() {
    let map =
        AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice()).unwrap();
    let balcony = map.landmark("records_balcony").unwrap();
    let reception = map.landmark("records_reception").unwrap();
    let session = GameSession::with_authored_map(map);
    let arena = session.state.map.arena();
    let presentation = session.state.map.presentation_ref().unwrap();
    let signs: Vec<_> = presentation
        .decorations
        .iter()
        .filter(|detail| detail.kind == MapDecorationKind::LiftSign)
        .collect();
    assert_eq!(signs.len(), 1);
    let sign_point = signs[0].point(&arena.solids[signs[0].solid]);
    // The public stair lands at x=8. The reserved opening is x=-5 to -1, so
    // the stand that can see through it is further west, still on the deck
    // and still before reception.
    let feet = [-4.0, 3.0, 9.0];
    assert!(
        stands_on_records_deck(arena, feet),
        "lookout is not standing on the records deck"
    );
    let eye = [feet[0], feet[1] + EYE_HEIGHT, feet[2]];
    assert!(
        line_of_sight(eye, sign_point, &arena.solids),
        "balcony eye {eye:?} cannot see the lift sign at {sign_point:?}"
    );
    let navigation = session.state.map.navigation();
    let along = navigation.route(balcony, feet, SEARCH_LIMIT);
    assert_eq!(along.status, RouteStatus::Complete);
    assert!(
        along
            .points
            .iter()
            .all(|point| point[2] <= 12.0 && (point[1] - 3.0).abs() <= 0.1),
        "stair-to-window route left the deck: {:?}",
        along.points
    );
    let to_reception = navigation.route(feet, reception, SEARCH_LIMIT);
    assert_eq!(to_reception.status, RouteStatus::Complete);
    assert!(
        to_reception
            .points
            .iter()
            .all(|point| point[0] <= -12.0 || point[2] <= 12.0),
        "balcony route entered the transfer office: {:?}",
        to_reception.points
    );
    let guards: Vec<_> = session
        .state
        .map
        .encounters()
        .iter()
        .filter(|group| group.id == "transfer_watch")
        .flat_map(|group| group.enemies.iter())
        .map(|enemy| (enemy.id.clone(), enemy.feet))
        .collect();
    assert_eq!(
        guards.iter().map(|(id, _)| id.as_str()).collect::<Vec<_>>(),
        [
            "transfer_clerk",
            "transfer_sweeper_west",
            "transfer_sweeper_east"
        ]
    );
    let mut samples = 0;
    for step_x in 0..=46 {
        let x = -11.5 + step_x as f32 * 0.5;
        for step_z in 0..=10 {
            let z = 6.5 + step_z as f32 * 0.5;
            let sample = [x, 3.0, z];
            if !stands_on_records_deck(arena, sample) {
                continue;
            }
            samples += 1;
            let sample_eye = [sample[0], sample[1] + EYE_HEIGHT, sample[2]];
            for (id, guard_feet) in &guards {
                for height in [0.2, FIGHTER_HEIGHT * 0.5, FIGHTER_HEIGHT] {
                    assert!(
                        !line_of_sight(
                            sample_eye,
                            [guard_feet[0], guard_feet[1] + height, guard_feet[2]],
                            &arena.solids
                        ),
                        "{id} is visible from the records balcony at {sample:?}"
                    );
                }
            }
        }
    }
    assert!(samples > 100, "balcony sweep covered only {samples} stands");
}
