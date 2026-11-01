use super::*;
use crate::protocol::{GameEvent, GameMode, Role, SabotageEventKind};
use crate::rules::{RuleSet, SabotageConfig};
use crate::sim::{BotBehavior, MapKind, MatchConfig, RoundState};
use uuid::Uuid;

const ATTACKER: Uuid = Uuid::from_u128(1);
const GUEST: Uuid = Uuid::from_u128(2);
const WORKER: Uuid = Uuid::from_u128(3);
const BACKUP: Uuid = Uuid::from_u128(4);

fn player(state: &GameState, id: Uuid) -> &Player {
    state.players.iter().find(|p| p.id == id).unwrap()
}

fn player_mut(state: &mut GameState, id: Uuid) -> &mut Player {
    state.players.iter_mut().find(|p| p.id == id).unwrap()
}

fn put(state: &mut GameState, id: Uuid, at: [f32; 3], offset: f32) {
    let p = player_mut(state, id);
    p.x = at[0] + offset;
    p.y = at[1] + PLAYER_FLOOR_Y;
    p.z = at[2];
    p.vy = 0.0;
}

fn intent(state: &GameState, id: Uuid) -> BotIntent {
    BotController::new(id, BotBehavior::Balanced).sabotage_intent(state, player(state, id))
}

fn planted(map: MapKind, guest_role: Role) -> (GameState, [f32; 3]) {
    let mut state = GameState::with_map(map, false);
    state.seed(11);
    state.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        sabotage: SabotageConfig {
            muster_ticks: 1,
            ..Default::default()
        },
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        ..Default::default()
    });
    for (id, role, team) in [
        (ATTACKER, Role::Agent, Team::Coalition),
        (GUEST, guest_role, Team::Union),
        (WORKER, Role::Agent, Team::Union),
        (BACKUP, Role::Agent, Team::Union),
    ] {
        state.add_player(id, format!("participant-{id}"), role);
        player_mut(&mut state, id).team = Some(team);
    }
    state.bots = [WORKER, BACKUP]
        .map(|id| BotController::new(id, BotBehavior::Balanced))
        .to_vec();
    state.start_round();
    // Opening balance is independent of this mixed-roster objective fixture.
    for p in &mut state.players {
        p.team = Some(if p.id == ATTACKER {
            Team::Coalition
        } else {
            Team::Union
        });
    }
    state
        .sabotage
        .as_mut()
        .unwrap()
        .charge
        .as_mut()
        .unwrap()
        .carrier = Some(ATTACKER);
    state.tick(0.05);
    state.tick(0.05);
    let at = state.map.sabotage_layout().unwrap().wire.sites[0].center;
    put(&mut state, ATTACKER, at, 0.0);
    state.set_action(ATTACKER, work().action);
    for _ in 0..=state.config.sabotage.plant_ticks {
        state.tick(0.05);
    }
    assert_eq!(
        state.sabotage.as_ref().unwrap().phase,
        SabotagePhase::Planted
    );
    state.set_action(ATTACKER, Action::default());
    let far = state.map.sabotage_layout().unwrap().wire.sites[1].center;
    put(&mut state, ATTACKER, far, 0.0);
    state.take_events();
    (state, at)
}

fn drive(state: &mut GameState, id: Uuid) {
    state.set_action(id, intent(state, id).action);
    state.tick(0.05);
}

fn reset_eligibility(p: &mut Player, role: Role) {
    p.hp = 100;
    p.detached = false;
    p.respawn_timer = None;
    p.eliminated = false;
    p.role = role;
    p.team = Some(Team::Union);
    p.is_boss = false;
}

#[test]
fn idle_guest_does_not_prevent_an_actual_bot_defuse() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        for role in [Role::Human, Role::Agent] {
            let (mut state, at) = planted(map, role);
            put(&mut state, GUEST, at, 0.0);
            put(&mut state, WORKER, at, 1.1);
            assert!(intent(&state, WORKER).action.interact, "{map:?} {role:?}");
            let mut session = crate::session::GameSession::with_map(map, false);
            session.bots = state.bots.clone();
            session.state = state;
            let mut events = Vec::new();
            for _ in 0..=session.state.config.sabotage.defuse_ticks {
                events.extend(session.tick_messages(0.05));
            }
            assert_eq!(session.state.round_state, RoundState::Ended);
            assert!(events.iter().any(|event| matches!(event,
                crate::protocol::ServerMessage::Event(GameEvent::Sabotage { kind: SabotageEventKind::Defused, player_id: Some(id), .. })
                if *id == WORKER)));
        }
    }
}

#[test]
fn an_active_bot_finishes_when_a_teammate_moves_closer() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        let (mut state, at) = planted(map, Role::Human);
        put(&mut state, WORKER, at, 1.1);
        for _ in 0..30 {
            drive(&mut state, WORKER);
        }
        assert_eq!(
            state
                .sabotage
                .as_ref()
                .unwrap()
                .hold
                .as_ref()
                .unwrap()
                .player,
            WORKER
        );
        put(&mut state, BACKUP, at, 0.0);
        assert!(intent(&state, WORKER).action.interact);
        assert!(!intent(&state, BACKUP).action.interact);
        for _ in 30..=state.config.sabotage.defuse_ticks {
            drive(&mut state, WORKER);
        }
        let events = state.take_events();
        assert!(events.iter().any(|event| matches!(
            event,
            GameEvent::Sabotage {
                kind: SabotageEventKind::Defused,
                ..
            }
        )));
        assert!(!events.iter().any(|event| matches!(
            event,
            GameEvent::Sabotage {
                kind: SabotageEventKind::DefuseInterrupted,
                ..
            }
        )));
    }
}

#[test]
fn an_active_guest_keeps_the_defuse_and_release_hands_it_to_a_bot() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        for role in [Role::Human, Role::Agent] {
            let (mut state, at) = planted(map, role);
            put(&mut state, GUEST, at, 1.1);
            state.set_action(GUEST, work().action);
            state.tick(0.05);
            put(&mut state, WORKER, at, 0.0);
            assert!(!intent(&state, WORKER).action.interact, "{map:?} {role:?}");
            assert_eq!(
                state
                    .sabotage
                    .as_ref()
                    .unwrap()
                    .hold
                    .as_ref()
                    .unwrap()
                    .player,
                GUEST
            );
            state.set_action(GUEST, Action::default());
            state.tick(0.05);
            drive(&mut state, WORKER);
            assert_eq!(
                state
                    .sabotage
                    .as_ref()
                    .unwrap()
                    .hold
                    .as_ref()
                    .unwrap()
                    .player,
                WORKER
            );
        }
    }
}

#[test]
fn idle_guest_does_not_claim_loose_charge_recovery() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        for role in [Role::Human, Role::Agent] {
            let (mut state, at) = planted(map, role);
            player_mut(&mut state, GUEST).team = Some(Team::Coalition);
            player_mut(&mut state, WORKER).team = Some(Team::Coalition);
            let sab = state.sabotage.as_mut().unwrap();
            sab.phase = SabotagePhase::Live;
            let charge = sab.charge.as_mut().unwrap();
            charge.planted = None;
            charge.dropped_at = None;
            put(&mut state, GUEST, at, 2.0);
            put(&mut state, WORKER, at, -3.0);
            let recovery = intent(&state, WORKER);
            assert_eq!(recovery.goal.unwrap().feet, at, "{map:?} {role:?}");
            // The ordinary bot action closes this clear short gap, then the
            // normal touch resolver gives it the charge without a special API.
            player_mut(&mut state, WORKER).yaw = 0.0;
            for _ in 0..20 {
                drive(&mut state, WORKER);
                if state
                    .sabotage
                    .as_ref()
                    .unwrap()
                    .charge
                    .as_ref()
                    .unwrap()
                    .carrier
                    == Some(WORKER)
                {
                    break;
                }
            }
            assert_eq!(
                state
                    .sabotage
                    .as_ref()
                    .unwrap()
                    .charge
                    .as_ref()
                    .unwrap()
                    .carrier,
                Some(WORKER)
            );
        }
    }
}

#[test]
fn objective_assignment_rejects_ineligible_bodies_and_unregistered_agents() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        let (mut state, at) = planted(map, Role::Agent);
        put(&mut state, GUEST, at, 0.0);
        put(&mut state, WORKER, at, 1.1);
        put(&mut state, BACKUP, at, -1.1);
        assert_eq!(objective_bot(&state, Team::Union, at), Some(WORKER));
        state.players.reverse();
        assert_eq!(objective_bot(&state, Team::Union, at), Some(WORKER));
        for invalid in [
            "dead",
            "detached",
            "waiting",
            "eliminated",
            "spectator",
            "wrong-side",
            "boss",
        ] {
            let p = player_mut(&mut state, WORKER);
            reset_eligibility(p, Role::Agent);
            match invalid {
                "dead" => p.hp = 0,
                "detached" => p.detached = true,
                "waiting" => p.respawn_timer = Some(1),
                "eliminated" => p.eliminated = true,
                "spectator" => p.role = Role::Spectator,
                "wrong-side" => p.team = Some(Team::Coalition),
                "boss" => p.is_boss = true,
                _ => unreachable!(),
            }
            assert_eq!(
                objective_bot(&state, Team::Union, at),
                Some(BACKUP),
                "{map:?} {invalid}"
            );
        }
        state.bots.clear();
        assert_eq!(objective_bot(&state, Team::Union, at), None);
    }
}

#[test]
fn an_ineligible_or_departed_defuser_does_not_block_the_next_bot() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        let (mut state, at) = planted(map, Role::Human);
        put(&mut state, GUEST, at, 1.1);
        state.set_action(GUEST, work().action);
        state.tick(0.05);
        put(&mut state, WORKER, at, 0.0);
        for invalid in [
            "dead",
            "detached",
            "waiting",
            "eliminated",
            "spectator",
            "wrong-side",
        ] {
            let p = player_mut(&mut state, GUEST);
            reset_eligibility(p, Role::Human);
            match invalid {
                "dead" => p.hp = 0,
                "detached" => p.detached = true,
                "waiting" => p.respawn_timer = Some(1),
                "eliminated" => p.eliminated = true,
                "spectator" => p.role = Role::Spectator,
                "wrong-side" => p.team = Some(Team::Coalition),
                _ => unreachable!(),
            }
            // Changing sides must not turn this eligibility case into the
            // separate existing close-enemy combat interruption behavior.
            if invalid == "wrong-side" {
                let far = state.map.sabotage_layout().unwrap().wire.sites[1].center;
                put(&mut state, GUEST, far, 2.0);
            }
            assert!(intent(&state, WORKER).action.interact, "{map:?} {invalid}");
        }
        state.players.retain(|p| p.id != GUEST);
        assert!(intent(&state, WORKER).action.interact);
        // The resolver cancels the abandoned hold before beginning the next.
        drive(&mut state, WORKER);
        assert!(state.sabotage.as_ref().unwrap().hold.is_none());
        drive(&mut state, WORKER);
        assert_eq!(
            state
                .sabotage
                .as_ref()
                .unwrap()
                .hold
                .as_ref()
                .unwrap()
                .player,
            WORKER
        );
    }
}

#[test]
fn a_called_site_gets_the_same_defence_whichever_site_it_is() {
    for side in 2..=6 {
        for hot in [SiteId::A, SiteId::B] {
            let posts: Vec<(SiteId, usize)> = (0..side)
                .map(|slot| defence_post(slot, side, Some(hot)))
                .collect();
            let at_hot = posts.iter().filter(|(site, _)| *site == hot).count();
            let keepers = side - at_hot;
            // Everyone but one keeper in a side of three or more.
            assert_eq!(keepers, usize::from(side >= 3), "side {side} hot {hot:?}");
            // Nobody shares a hold spot at the called site.
            let mut spots: Vec<usize> = posts
                .iter()
                .filter(|(site, _)| *site == hot)
                .map(|(_, spot)| *spot)
                .collect();
            spots.sort_unstable();
            spots.dedup();
            assert_eq!(spots.len(), at_hot, "side {side} hot {hot:?}: {posts:?}");
        }
        // Before a call, even slots anchor A and odd slots B.
        for slot in 0..side {
            let (site, spot) = defence_post(slot, side, None);
            assert_eq!(site == SiteId::A, slot % 2 == 0);
            assert_eq!(spot, slot / 2);
        }
    }
}

#[test]
fn a_holding_anchor_watches_the_attack_lane_not_the_wall() {
    for map in [MapKind::Sector9, MapKind::LowWater] {
        let watch = crate::maps::sabotage_watch(map).expect("both Sabotage maps have lanes");
        let layout = crate::maps::sabotage_layout(map).unwrap();
        for (index, site) in layout.wire.sites.iter().enumerate() {
            for lane in watch[index] {
                let from = site.center;
                // A watched point is out along a lane, in sight of the site.
                let far = horizontal(from, lane);
                assert!(far > 4.0 && far <= 30.5, "{map:?} {lane:?} {far}");
                assert!(crate::maps::navigation(map).line_of_sight(
                    [from[0], from[1] + 1.6, from[2]],
                    [lane[0], lane[1] + 1.6, lane[2]],
                ));
            }
        }
        // The first anchor at A, on its spot, turns toward the main lane.
        let mut state = GameState::with_map(map, false);
        state.seed(3);
        state.apply_config(MatchConfig {
            rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
            sabotage: SabotageConfig {
                muster_ticks: 1,
                ..Default::default()
            },
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..Default::default()
        });
        for (id, team) in [(WORKER, Team::Union), (ATTACKER, Team::Coalition)] {
            state.add_player(id, format!("participant-{id}"), Role::Agent);
            player_mut(&mut state, id).team = Some(team);
        }
        state.bots = vec![
            BotController::new(WORKER, BotBehavior::Balanced),
            BotController::new(ATTACKER, BotBehavior::Balanced),
        ];
        state.start_round();
        for _ in 0..4 {
            state.tick(0.05);
        }
        for p in &mut state.players {
            p.team = Some(if p.id == ATTACKER {
                Team::Coalition
            } else {
                Team::Union
            });
        }
        if state
            .sabotage
            .as_ref()
            .is_none_or(|sab| sab.phase != SabotagePhase::Live)
        {
            continue;
        }
        let spot = hold_spot(layout, SiteId::A, 0);
        put(&mut state, WORKER, spot, 0.0);
        put(&mut state, ATTACKER, [70.0, 0.0, 70.0], 0.0);
        let holder = player_mut(&mut state, WORKER);
        holder.inventory.arm_magazines();
        assert!(holder.inventory.grant_weapon(WeaponType::Flechette));
        holder.weapon = WeaponType::Flechette;
        let lane = watch[0][0];
        let bearing = (lane[2] - spot[2]).atan2(lane[0] - spot[0]);
        // Facing straight away from the lane, the holder turns toward it.
        player_mut(&mut state, WORKER).yaw = bearing + PI;
        let held = intent(&state, WORKER);
        assert!(held.goal.is_none(), "{map:?}: a holder stays on its spot");
        assert!(held.action.turn_left || held.action.turn_right, "{map:?}");
        player_mut(&mut state, WORKER).yaw = bearing;
        let settled = intent(&state, WORKER);
        assert!(
            !settled.action.turn_left && !settled.action.turn_right,
            "{map:?}"
        );
    }
}
