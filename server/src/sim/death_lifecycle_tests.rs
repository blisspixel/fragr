//! #441: a death ends that life's input, presses made while down are not
//! queued into the next body, and the countdown a client is told agrees with
//! the tick the server actually respawns on.
use super::*;
use crate::rules::{RuleSet, FFA_RESPAWN_DELAY_TICKS, TEAM_RESPAWN_DELAY_TICKS};

struct Duel {
    state: GameState,
    killer: Uuid,
    victim: Uuid,
    seq: u32,
}

impl Duel {
    fn new() -> Self {
        let mut state = GameState::new();
        state.start_round();
        let killer = Uuid::from_u128(1);
        let victim = Uuid::from_u128(2);
        state.add_player(killer, "Rival".to_string(), Role::Human);
        state.add_player(victim, "Meat".to_string(), Role::Human);
        Self {
            state,
            killer,
            victim,
            seq: 0,
        }
    }

    fn index(&self, id: Uuid) -> usize {
        self.state.players.iter().position(|p| p.id == id).unwrap()
    }

    fn body(&self) -> &Player {
        &self.state.players[self.index(self.victim)]
    }

    /// A numbered human input, as the Godot client sends it.
    fn send(&mut self, action: Action) {
        self.seq += 1;
        let action = Action {
            seq: Some(self.seq),
            yaw: Some(0.0),
            ..action
        };
        self.state.set_action(self.victim, action);
    }

    fn kill(&mut self) {
        let shooter = self.index(self.killer);
        let victim = self.index(self.victim);
        let (_, _, died) = self.state.resolve_fighter_hit(shooter, victim, 1000, None);
        assert!(died);
    }

    fn ack_respawn_ticks(&self) -> Option<u32> {
        self.state
            .input_acks()
            .into_iter()
            .find(|(id, _)| *id == self.victim)
            .and_then(|(_, message)| match message {
                ServerMessage::Ack { respawn_ticks, .. } => respawn_ticks,
                _ => None,
            })
    }

    /// Tick until the victim is back, with no input from its client, which is
    /// exactly what the Godot client sends while it has no body.
    fn tick_to_respawn(&mut self) {
        for _ in 0..=FFA_RESPAWN_DELAY_TICKS + 2 {
            self.state.tick(0.05);
            if self.body().respawn_timer.is_none() && self.body().hp > 0 {
                return;
            }
        }
        panic!("victim never respawned");
    }
}

#[test]
fn death_ends_held_movement_and_queued_presses() {
    let mut duel = Duel::new();
    duel.send(Action {
        forward: true,
        right: true,
        fire: true,
        interact: true,
        throw_grenade: true,
        reload: true,
        ..Default::default()
    });
    duel.kill();
    let body = duel.body();
    assert_eq!(body.respawn_timer, Some(FFA_RESPAWN_DELAY_TICKS));
    assert!(!body.pending_action.forward && !body.pending_action.right);
    assert!(!body.pending_action.fire && !body.pending_action.interact);
    assert!(!body.interaction_requested && !body.throw_requested && !body.reload_requested);
    assert!(!body.jump_requested);
    assert!(body.fire_latched, "a trigger held into death stays latched");
}

#[test]
fn a_respawned_body_does_not_walk_on_the_dead_life_s_input() {
    let mut duel = Duel::new();
    duel.send(Action {
        forward: true,
        ..Default::default()
    });
    duel.state.tick(0.05);
    duel.kill();
    duel.tick_to_respawn();
    let spawned = (duel.body().x, duel.body().z, duel.body().yaw);
    for _ in 0..10 {
        duel.state.tick(0.05);
    }
    let body = duel.body();
    assert_eq!(
        (body.x, body.z, body.yaw),
        spawned,
        "held W at death must not move the next body before its client speaks"
    );
}

#[test]
fn a_trigger_held_through_death_needs_a_release_after_respawn() {
    let mut duel = Duel::new();
    duel.send(Action {
        fire: true,
        ..Default::default()
    });
    duel.kill();
    duel.tick_to_respawn();
    // The client re-enters the body with the trigger still down.
    for _ in 0..8 {
        duel.send(Action {
            fire: true,
            ..Default::default()
        });
        duel.state.tick(0.05);
        assert!(
            !duel.body().just_fired,
            "held trigger fired into a new life"
        );
    }
    duel.send(Action::default());
    duel.state.tick(0.05);
    let mut fired = false;
    for _ in 0..8 {
        duel.send(Action {
            fire: true,
            ..Default::default()
        });
        duel.state.tick(0.05);
        fired |= duel.body().just_fired;
    }
    assert!(fired, "a fresh press after release fires");
}

#[test]
fn presses_made_while_down_are_not_queued_into_the_next_life() {
    let mut duel = Duel::new();
    duel.kill();
    duel.send(Action {
        jump: true,
        interact: true,
        throw_grenade: true,
        place_mine: true,
        reload: true,
        place_remote_mine: true,
        trigger_remote_mines: true,
        fire: true,
        weapon_swap: Some(WeaponType::Rail),
        ..Default::default()
    });
    let body = duel.body();
    assert!(!body.jump_requested && !body.interaction_requested);
    assert!(!body.throw_requested && !body.place_requested && !body.reload_requested);
    assert!(!body.remote_place_requested && !body.remote_trigger_requested);
    assert_eq!(body.pending_action.weapon_swap, None);
    assert!(body.fire_latched, "fire pressed while down is latched");
    // An input that releases the trigger while down clears the latch.
    duel.send(Action::default());
    assert!(!duel.body().fire_latched);
}

#[test]
fn an_unnumbered_controller_that_releases_while_down_respawns_unlatched() {
    // Rule bots and agents do not number inputs; bots send their empty
    // intent every tick while down, so their trigger is never stuck.
    let mut duel = Duel::new();
    let bot = Uuid::from_u128(3);
    duel.state.add_player(bot, "Rule".to_string(), Role::Agent);
    duel.victim = bot;
    duel.state.set_action(
        bot,
        Action {
            fire: true,
            ..Default::default()
        },
    );
    duel.kill();
    assert!(duel.body().fire_latched);
    duel.state.set_action(bot, Action::default());
    assert!(!duel.body().fire_latched);
}

#[test]
fn the_acknowledged_countdown_names_the_respawn_tick() {
    let mut duel = Duel::new();
    duel.send(Action::default());
    duel.state.tick(0.05);
    assert_eq!(duel.ack_respawn_ticks(), None, "alive has no countdown");
    duel.kill();
    let mut promised: Option<u64> = None;
    let mut last: Option<u32> = None;
    for _ in 0..=FFA_RESPAWN_DELAY_TICKS + 2 {
        duel.state.tick(0.05);
        if duel.body().respawn_timer.is_none() {
            assert_eq!(
                Some(duel.state.tick),
                promised,
                "respawned off the told tick"
            );
            assert_eq!(
                duel.ack_respawn_ticks(),
                None,
                "the countdown ends with the life"
            );
            return;
        }
        let ticks = duel
            .ack_respawn_ticks()
            .expect("down fighter is told its countdown");
        assert!(ticks >= 1);
        if let Some(previous) = last {
            assert_eq!(ticks + 1, previous, "one tick per tick, no client clock");
        }
        let target = duel.state.tick + u64::from(ticks);
        assert!(
            promised.is_none_or(|p| p == target),
            "every Ack names the same tick"
        );
        promised = Some(target);
        last = Some(ticks);
    }
    panic!("victim never respawned");
}

#[test]
fn an_eliminated_fighter_is_told_no_countdown() {
    let mut duel = Duel::new();
    duel.send(Action::default());
    let index = duel.index(duel.victim);
    duel.state.players[index].lives = Some(1);
    duel.kill();
    duel.state.tick(0.05);
    assert!(duel.body().eliminated);
    assert_eq!(duel.ack_respawn_ticks(), None);
}

#[test]
fn respawn_delay_is_a_rule_value_with_ffa_separate_from_team_modes() {
    for mode in crate::protocol::GameMode::ALL {
        let rules = RuleSet::new(mode, &[], false).unwrap();
        let expected = if mode.free_for_all() {
            FFA_RESPAWN_DELAY_TICKS
        } else {
            TEAM_RESPAWN_DELAY_TICKS
        };
        assert_eq!(rules.respawn_delay_ticks(), expected, "{mode:?}");
    }
    // Nick, 2026-10-23: four seconds at 20 Hz in free-for-all only. Team
    // modes keep three. Both stay distinct from the one-second spawn shield.
    assert_eq!(FFA_RESPAWN_DELAY_TICKS, 80);
    assert_eq!(TEAM_RESPAWN_DELAY_TICKS, 60);
    assert_ne!(FFA_RESPAWN_DELAY_TICKS, SPAWN_SHIELD_TICKS);
}

#[test]
fn a_respawn_still_raises_the_separate_spawn_shield() {
    let mut duel = Duel::new();
    duel.kill();
    duel.tick_to_respawn();
    assert_eq!(
        duel.state.spawn_shields.get(&duel.victim).copied(),
        Some(SPAWN_SHIELD_TICKS)
    );
}

#[test]
fn a_campaign_death_does_not_read_the_ffa_pacing_value() {
    // Campaign maps run under the default rule sheet, which is FFA. The FFA
    // pacing value must not reach a campaign body through it.
    let map = crate::maps::AuthoredSource::Mission(crate::protocol::MissionId::CustodianOfRecord)
        .load()
        .unwrap();
    let mut state = GameState::with_authored_map(map);
    assert!(state.map.is_campaign());
    assert_eq!(state.config.rules.mode(), crate::protocol::GameMode::Ffa);
    let id = Uuid::from_u128(441);
    state.add_player(id, "Courier".to_string(), Role::Human);
    let index = state.players.iter().position(|p| p.id == id).unwrap();
    let (_, _, died) = state.resolve_fighter_hit(index, index, 1000, None);
    assert!(died);
    assert_eq!(
        state.players[index].respawn_timer,
        Some(crate::rules::CAMPAIGN_RESPAWN_DELAY_TICKS)
    );
}
