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
