//! Play the committed opening through ordinary movement, inventory and combat.
use crate::combat::{line_of_sight, FIGHTER_HEIGHT};
use crate::maps::AuthoredMap;
use crate::movement::EYE_HEIGHT;
use crate::navigation::{NavigationGoal, Navigator};
use crate::protocol::{Action, CampaignActor, EnemyPhase, LookAt, Role, WeaponType};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use std::collections::BTreeSet;
use uuid::Uuid;

struct Walkthrough {
    session: GameSession,
    id: Uuid,
    navigator: Navigator,
    seen: BTreeSet<Uuid>,
    spawned: BTreeSet<Uuid>,
    defeated: BTreeSet<Uuid>,
    shots: usize,
    first_threat: Option<u64>,
    first_shot: Option<u64>,
}

impl Walkthrough {
    fn new(role: Role) -> Self {
        let map = AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice())
            .unwrap();
        let mut session = GameSession::with_authored_map(map);
        session.state.seed(67);
        let id = Uuid::from_u128(100);
        session.state.add_player(id, "Visitor".into(), role);
        Self {
            session,
            id,
            navigator: Navigator::default(),
            seen: BTreeSet::new(),
            spawned: BTreeSet::new(),
            defeated: BTreeSet::new(),
            shots: 0,
            first_threat: None,
            first_shot: None,
        }
    }

    fn step(&mut self, destination: [f32; 3]) {
        let snapshot = self.session.state.snapshot();
        let me = snapshot.players.iter().find(|p| p.id == self.id).unwrap();
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
        for target in &visible {
            self.seen.insert(target.id);
        }
        let target = visible.first();
        let action = if let Some(target) = target {
            self.first_threat.get_or_insert(snapshot.tick);
            let player = &self.session.state.players[0];
            let loadout = player
                .inventory
                .state(self.id, player.weapon, snapshot.tick)
                .unwrap();
            let dry = loadout.weapon(player.weapon).unwrap().magazine == Some(0);
            Action {
                look_at: Some(LookAt {
                    player_id: Some(target.id),
                    ..Default::default()
                }),
                fire: !dry && loadout.reload.is_none(),
                reload: dry && loadout.reload.is_none(),
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
                    if run.defeated.len() == 3 {
                        break;
                    }
                    run.step([0.0, 0.0, -10.0]);
                }
                run.walk([6.0, 0.0, -9.0]);
                run.walk([8.0, 0.0, -8.0]);
                run.walk([8.0, 3.0, 9.0]);
            }
            for _ in 0..400 {
                if run.defeated.len() == 3 {
                    break;
                }
                let p = &run.session.state.players[0];
                run.step([p.x, p.y - PLAYER_FLOOR_Y, p.z]);
            }
            assert_eq!(
                run.defeated.len(),
                3,
                "{role:?}, maintenance={maintenance}; {:?}",
                run.session.state.snapshot().players
            );
            assert_eq!(run.seen.len(), 3, "every enemy was seen before defeat");
            assert_eq!(run.session.state.players[0].weapon, WeaponType::Flechette);
            run.walk([-3.0, 3.0, 20.0]);
            run.use_control(true);
            run.walk([7.0, 3.0, 23.0]);
            run.use_control(false);
            assert_eq!(run.session.state.scores[&run.id], 0);
            eprintln!("M01 {role:?} maintenance={maintenance}: ticks={}, hp={}, shots={}, first_threat={:?}, first_shot={:?}",
                run.session.state.tick, run.session.state.players[0].hp, run.shots, run.first_threat, run.first_shot);
        }
    }
}
