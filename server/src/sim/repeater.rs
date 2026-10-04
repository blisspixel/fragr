//! Candidate sustained-fire cycle. Outcomes still use ordinary traced shots.
use crate::protocol::WeaponType;

pub const WARMUP_TICKS: u64 = 6;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct RepeaterCycle {
    pub(crate) held_since: Option<u64>,
}

impl RepeaterCycle {
    pub(crate) fn reset(&mut self) {
        self.held_since = None;
    }

    /// Returns permission to attempt an ordinary shot, never a hit or grant.
    pub(crate) fn step(
        &mut self,
        weapon: WeaponType,
        fire: bool,
        active: bool,
        suppressed: bool,
        supplied: bool,
        tick: u64,
    ) -> bool {
        if weapon != WeaponType::Repeater || !fire || !active || suppressed {
            self.reset();
            return weapon != WeaponType::Repeater && fire && active && !suppressed;
        }
        if !supplied {
            self.reset();
            // Preserve ordinary bounded dry-trigger accounting without spinning.
            return true;
        }
        let start = *self.held_since.get_or_insert(tick);
        tick.saturating_sub(start) >= WARMUP_TICKS
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::maps::AuthoredMap;
    use crate::protocol::{Action, AmmoPool, LookAt, Role};
    use crate::sim::GameState;
    use serde_json::json;
    use uuid::Uuid;

    fn arena(wall: bool) -> (GameState, Uuid, Uuid) {
        let map = AuthoredMap::read(serde_json::to_vec(&json!({
            "version": 1, "map_id": 1000, "name": "Repeater fixture", "half_extent": 12,
            "ground": "concrete", "equipment": "discovery",
            "solids": if wall { json!([{ "id":"wall", "min":[1,0,-1], "max":[1.3,3,1], "surface":"enamel" }]) } else { json!([]) },
            "spawns": [{"id":"entry", "feet":[0,0,-6], "yaw":0}],
            "landmarks": [{"id":"exit", "feet":[0,0,10]}]
        })).unwrap().as_slice()).unwrap();
        let mut state = GameState::with_authored_map(map);
        state.seed(42);
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        state.add_player(a, "Shooter".into(), Role::Human);
        state.add_player(b, "Target".into(), Role::Agent);
        for (i, player) in state.players.iter_mut().enumerate() {
            player.x = i as f32 * 3.0;
            player.z = 0.0;
        }
        state.players[0]
            .inventory
            .grant_weapon(WeaponType::Repeater);
        state.players[0].weapon = WeaponType::Repeater;
        (state, a, b)
    }

    fn trigger(state: &mut GameState, shooter: Uuid, target: Uuid, fire: bool) {
        state.set_action(
            shooter,
            Action {
                fire,
                look_at: Some(LookAt {
                    player_id: Some(target),
                    x: None,
                    y: None,
                    z: None,
                }),
                ..Action::default()
            },
        );
    }

    fn bullets(state: &GameState, id: Uuid) -> u16 {
        let player = state.players.iter().find(|p| p.id == id).unwrap();
        player
            .inventory
            .state(id, player.weapon, state.tick)
            .unwrap()
            .ammo(AmmoPool::Bullets)
    }

    #[test]
    fn actual_warmup_spends_nothing_then_resolves_distinct_finite_shots() {
        let (mut state, a, b) = arena(false);
        trigger(&mut state, a, b, true);
        for _ in 0..WARMUP_TICKS {
            state.tick(0.05);
            assert!(state.shot_results.is_empty());
            assert_eq!(bullets(&state, a), 60);
            assert_eq!(state.players[1].hp, 100);
        }
        let mut shot_ticks = vec![];
        for _ in 0..5 {
            state.tick(0.05);
            if !state.shot_results.is_empty() {
                shot_ticks.push(state.tick);
                assert_eq!(
                    state.shot_results[0].trace.as_ref().unwrap().weapon,
                    WeaponType::Repeater
                );
                assert!(state.shot_results[0].hit);
            }
        }
        assert_eq!(shot_ticks, [7, 9, 11]);
        assert_eq!(bullets(&state, a), 57);
        assert_eq!(state.players[1].hp, 58);
        let record = state.player_record(a).unwrap();
        assert_eq!(record.total.weapon(WeaponType::Repeater).attacks, 3);
        assert_eq!(record.total.weapon(WeaponType::Repeater).hp_damage, 42);
        assert_eq!(record.total.weapon(WeaponType::Flechette).attacks, 0);
        assert!(record.legacy_record().is_err());
    }

    #[test]
    fn actual_cover_empty_pool_and_release_preserve_outcome_ownership() {
        let (mut state, a, b) = arena(true);
        while bullets(&state, a) > 2 {
            assert!(state.players[0].inventory.try_fire(WeaponType::Repeater));
        }
        trigger(&mut state, a, b, true);
        for _ in 0..20 {
            state.tick(0.05);
        }
        assert_eq!(bullets(&state, a), 0);
        assert_eq!(state.players[1].hp, 100);
        let record = state.player_record(a).unwrap();
        assert_eq!(record.total.weapon(WeaponType::Repeater).attacks, 2);
        assert_eq!(
            record.total.weapon(WeaponType::Repeater).damaging_attacks,
            0
        );
        assert_eq!(record.total.dry_triggers, 1);
        let rng = state.rng_state;
        for _ in 0..10 {
            state.tick(0.05);
        }
        assert_eq!(state.rng_state, rng);
        assert_eq!(state.player_record(a).unwrap().total.dry_triggers, 1);
        trigger(&mut state, a, b, false);
        state.tick(0.05);
        state.players[0].inventory.grant_ammo(AmmoPool::Bullets, 1);
        trigger(&mut state, a, b, true);
        for _ in 0..WARMUP_TICKS {
            state.tick(0.05);
            assert!(state.shot_results.is_empty());
        }
        state.tick(0.05);
        assert_eq!(state.shot_results.len(), 1);
        assert_eq!(bullets(&state, a), 0);
    }

    #[test]
    fn actual_selection_input_clear_and_dead_wait_restart_warmup() {
        let (mut state, a, b) = arena(false);
        trigger(&mut state, a, b, true);
        for _ in 0..6 {
            state.tick(0.05);
        }
        state.set_action(
            a,
            Action {
                weapon_swap: Some(WeaponType::Fists),
                ..Action::default()
            },
        );
        state.tick(0.05);
        assert_eq!(state.players[0].repeater_cycle.held_since, None);
        state.set_action(
            a,
            Action {
                weapon_swap: Some(WeaponType::Repeater),
                fire: true,
                ..Action::default()
            },
        );
        state.tick(0.05);
        assert!(state.shot_results.is_empty());
        state.players[0].clear_input();
        assert_eq!(state.players[0].repeater_cycle.held_since, None);
        trigger(&mut state, a, b, true);
        state.tick(0.05);
        state.players[0].hp = 0;
        state.players[0].respawn_timer = Some(20);
        state.tick(0.05);
        assert_eq!(state.players[0].repeater_cycle.held_since, None);
        state.remove_player(a);
        assert!(state.players.iter().all(|p| p.id != a));
    }

    #[test]
    fn resolved_death_and_real_campaign_retry_clear_the_private_cycle() {
        let (mut state, a, b) = arena(false);
        state.players[0].hp = 10;
        trigger(&mut state, a, b, true);
        state.tick(0.05);
        state.players[1].inventory.grant_weapon(WeaponType::Rail);
        state.players[1].weapon = WeaponType::Rail;
        trigger(&mut state, b, a, true);
        state.tick(0.05);
        assert_eq!(
            state.players[0].hp, -70,
            "actual 80-damage Rail overkill is distinct from effective record damage"
        );
        assert_eq!(state.players[0].repeater_cycle.held_since, None);
        assert_eq!(state.player_record(a).unwrap().total.deaths, 1);
        assert_eq!(
            state
                .player_record(b)
                .unwrap()
                .total
                .weapon(WeaponType::Rail)
                .hp_damage,
            10
        );
        assert_eq!(
            state
                .player_record(b)
                .unwrap()
                .total
                .weapon(WeaponType::Rail)
                .kills,
            1
        );

        let map = AuthoredMap::read(include_bytes!("../../maps/m01-recall-notice.json").as_slice())
            .unwrap();
        let mut campaign = GameState::with_authored_map(map);
        campaign.add_player(a, "Participant".into(), Role::Human);
        assert!(campaign.acknowledge_mission(
            a,
            crate::protocol::MissionReady {
                id: crate::protocol::MissionId::RecallNotice,
                attempt: 1
            }
        ));
        // Seed only a prototype ownership fixture, never a campaign save/find.
        campaign
            .players
            .iter_mut()
            .find(|p| p.id == a)
            .unwrap()
            .inventory
            .grant_weapon(WeaponType::Repeater);
        campaign
            .players
            .iter_mut()
            .find(|p| p.id == a)
            .unwrap()
            .weapon = WeaponType::Repeater;
        campaign.set_action(
            a,
            Action {
                fire: true,
                ..Action::default()
            },
        );
        campaign.tick(0.05);
        assert!(campaign
            .players
            .iter()
            .find(|p| p.id == a)
            .unwrap()
            .repeater_cycle
            .held_since
            .is_some());
        let dead = campaign.players.iter_mut().find(|p| p.id == a).unwrap();
        dead.hp = 0;
        dead.respawn_timer = Some(2);
        campaign.tick(0.05);
        assert_eq!(campaign.mission_state().unwrap().attempt, 2);
        assert!(campaign.shot_results.is_empty());
        assert_eq!(
            campaign
                .players
                .iter()
                .find(|p| p.id == a)
                .unwrap()
                .repeater_cycle
                .held_since,
            None
        );
        campaign.tick(0.05);
        let reset = campaign.players.iter().find(|p| p.id == a).unwrap();
        assert_eq!(reset.repeater_cycle.held_since, None);
        assert!(!reset.pending_action.fire);
        assert!(!reset.inventory.owns(WeaponType::Repeater));
        assert_eq!(reset.weapon, WeaponType::Fists);
    }

    #[test]
    fn default_arsenal_never_gains_repeater_and_shared_controller_honors_real_ownership() {
        let arcade =
            crate::inventory::Inventory::new(crate::protocol::EquipmentPolicy::FullArsenal);
        assert!(!arcade.owns(WeaponType::Repeater));
        assert!(!arcade.usable(WeaponType::Repeater));
        assert_eq!(
            WeaponType::ARCADE,
            [WeaponType::Flechette, WeaponType::Rail, WeaponType::Scatter]
        );
        let (state, a, _) = arena(false);
        let snapshot = state.snapshot();
        let loadout = state.players[0]
            .inventory
            .state(a, WeaponType::Repeater, state.tick)
            .unwrap();
        let intent = Action {
            weapon_swap: Some(WeaponType::Repeater),
            fire: true,
            ..Action::default()
        };
        let action = crate::inventory::control_action(a, &snapshot, Some(&loadout), intent);
        assert!(
            action.fire,
            "shared controller uses genuine supplied Repeater against an arcade hostile"
        );
        let mut dry = loadout.clone();
        for count in &mut dry.ammo {
            count.rounds = 0;
        }
        let action = crate::inventory::control_action(
            a,
            &snapshot,
            Some(&dry),
            Action {
                fire: true,
                ..Action::default()
            },
        );
        assert!(!action.fire);
        assert_eq!(action.weapon_swap, Some(WeaponType::Fists));
    }

    #[tokio::test]
    async fn real_map_admission_refuses_old_all_roles_before_welcome_and_orders_supported_delivery()
    {
        use futures_util::{SinkExt, StreamExt};
        use std::time::Duration;
        use tokio_tungstenite::{connect_async, tungstenite::Message};
        let directory =
            std::env::temp_dir().join(format!("fragr-repeater-admission-{}", Uuid::new_v4()));
        std::fs::create_dir(&directory).unwrap();
        let path = directory.join("range.json");
        let bytes = serde_json::to_vec(&json!({
            "version":1,"map_id":1000,"name":"Repeater admission","half_extent":12,
            "ground":"concrete","equipment":"discovery","solids":[],
            "supplies":[{"id":"repeater","feet":[0,0,0],"grant":{"kind":"weapon","weapon":"repeater"},"claim":"personal"}],
            "spawns":[{"id":"entry","feet":[0,0,-6],"yaw":0}],
            "landmarks":[{"id":"exit","feet":[0,0,10]}]
        })).unwrap();
        assert!(
            crate::maps::RuntimeMap::Authored(AuthoredMap::read(bytes.as_slice()).unwrap())
                .requires_repeater_contract()
        );
        std::fs::write(&path, bytes).unwrap();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(crate::run::run_server(
            crate::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                authored: Some(crate::maps::AuthoredSource::File(path)),
                ..Default::default()
            },
            async {
                let _ = stop_rx.await;
            },
            Some(ready_tx),
        ));
        let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
            .await
            .unwrap()
            .unwrap();
        for version in [
            crate::protocol::M09_GAMEPLAY_VERSION,
            crate::protocol::REPEATER_GAMEPLAY_VERSION,
        ] {
            for role in ["human", "agent", "spectator"] {
                let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
                socket.send(Message::Text(json!({"type":"hello","role":role,"name":"Reader","gameplay_version":version,"geometry_version":crate::protocol::GEOMETRY_VERSION}).to_string())).await.unwrap();
                tokio::time::timeout(Duration::from_secs(5), async {
                    let mut welcomed = false;
                    let mut mapped = false;
                    loop {
                        let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                            continue;
                        };
                        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
                        if version < crate::protocol::REPEATER_GAMEPLAY_VERSION {
                            assert_eq!(
                                value["type"], "error",
                                "unsupported role must not receive Welcome or new geometry"
                            );
                            assert_eq!(value["code"], "unsupported_gameplay");
                            assert!(value["message"].as_str().unwrap().contains("35"));
                            break;
                        }
                        match value["type"].as_str().unwrap() {
                            "welcome" => welcomed = true,
                            "map_info" => mapped = true,
                            "snapshot" => {
                                assert!(welcomed && mapped);
                                break;
                            }
                            "error" => panic!("supported reader refused: {value}"),
                            _ => {}
                        }
                    }
                })
                .await
                .expect("bounded all-role admission");
                let _ = socket.close(None).await;
            }
        }
        stop_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn warmup_requires_six_complete_ticks_and_release_restarts() {
        let mut cycle = RepeaterCycle::default();
        for tick in 100..106 {
            assert!(!cycle.step(WeaponType::Repeater, true, true, false, true, tick));
        }
        assert!(cycle.step(WeaponType::Repeater, true, true, false, true, 106));
        assert!(!cycle.step(WeaponType::Repeater, false, true, false, true, 107));
        assert!(!cycle.step(WeaponType::Repeater, true, true, false, true, 108));
        assert_eq!(cycle.held_since, Some(108));
        assert!(cycle.step(WeaponType::Repeater, true, true, false, true, 114));
    }

    #[test]
    fn switching_inactivity_suppression_and_empty_pool_clear_cycle() {
        let mut cycle = RepeaterCycle {
            held_since: Some(0),
        };
        assert!(cycle.step(WeaponType::Flechette, true, true, false, true, 20));
        assert_eq!(cycle.held_since, None);
        for (active, suppressed) in [(false, false), (true, true)] {
            cycle.held_since = Some(0);
            assert!(!cycle.step(WeaponType::Repeater, true, active, suppressed, true, 20));
            assert_eq!(cycle.held_since, None);
        }
        cycle.held_since = Some(0);
        assert!(cycle.step(WeaponType::Repeater, true, true, false, false, 20));
        assert_eq!(cycle.held_since, None);
        assert!(!cycle.step(WeaponType::Repeater, true, true, false, true, 21));
    }
}
