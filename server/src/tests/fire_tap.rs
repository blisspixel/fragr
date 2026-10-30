//! The trigger is held state, but a press and release between two ticks is
//! latched like every other press: one tick consumes it and fires once.
use crate::protocol::{Action, Role, WeaponType};
use crate::sim::GameState;
use uuid::Uuid;

const DT: f32 = 0.05;

struct Range {
    state: GameState,
    id: Uuid,
    seq: u32,
}

impl Range {
    fn new(weapon: WeaponType) -> Self {
        let mut state = GameState::new();
        state.start_round();
        let id = Uuid::from_u128(77);
        state.add_player(id, "Tapper".into(), Role::Human);
        let player = state.players.iter_mut().find(|p| p.id == id).unwrap();
        player.inventory.grant_weapon(weapon);
        let mut range = Self { state, id, seq: 0 };
        range.send(Action {
            weapon_swap: Some(weapon),
            ..Default::default()
        });
        // Settle the swap and any spawn-time cooldown with the trigger free.
        for _ in 0..40 {
            range.tick();
        }
        assert_eq!(range.player().weapon, weapon);
        range
    }

    fn player(&self) -> &crate::sim::Player {
        self.state.players.iter().find(|p| p.id == self.id).unwrap()
    }

    fn send(&mut self, action: Action) {
        self.seq += 1;
        self.state.set_action(
            self.id,
            Action {
                seq: Some(self.seq),
                yaw: Some(0.0),
                pitch: Some(0.0),
                ..action
            },
        );
    }

    fn fire(&mut self, held: bool) {
        self.send(Action {
            fire: held,
            ..Default::default()
        });
    }

    /// One tick; the number of shots this fighter fired in it.
    fn tick(&mut self) -> usize {
        self.state.tick(DT);
        self.state.take_events();
        let id = self.id;
        self.state
            .shot_results
            .iter()
            .filter(|s| s.shooter_id == id)
            .count()
    }

    fn tap(&mut self) {
        self.fire(true);
        self.fire(false);
    }
}

#[test]
fn a_tap_between_ticks_fires_exactly_once() {
    for weapon in [WeaponType::Tack, WeaponType::Flechette] {
        let mut range = Range::new(weapon);
        range.tap();
        assert_eq!(range.tick(), 1, "{weapon:?} tap reaches the next tick");
        let later: usize = (0..30).map(|_| range.tick()).sum();
        assert_eq!(
            later, 0,
            "{weapon:?} one tap is one shot, never a held trigger"
        );
    }
}

#[test]
fn held_fire_keeps_its_cadence_and_a_tap_in_cooldown_is_dropped() {
    for weapon in [WeaponType::Tack, WeaponType::Flechette] {
        let mut range = Range::new(weapon);
        let cooldown = weapon.cooldown_ticks() as usize;
        assert!(cooldown >= 2, "{weapon:?} needs a cooldown to test");
        range.fire(true);
        let held: Vec<usize> = (0..=cooldown * 3).map(|_| range.tick()).collect();
        let shots: Vec<usize> = (0..held.len()).filter(|t| held[*t] > 0).collect();
        assert_eq!(
            shots,
            vec![0, cooldown, cooldown * 2, cooldown * 3],
            "{weapon:?} held cadence"
        );
        range.fire(false);
        // Release right after a shot; tap while the weapon is still cooling.
        while range.player().fire_cooldown == 0 {
            range.fire(true);
            range.tick();
            range.fire(false);
        }
        range.tap();
        let during: usize = (0..cooldown * 2).map(|_| range.tick()).sum();
        assert_eq!(
            during, 0,
            "{weapon:?} a tap in cooldown does not queue a shot"
        );
    }
}

#[test]
fn an_eliminated_or_dead_fighter_drops_a_tap() {
    let mut range = Range::new(WeaponType::Tack);
    let index = range
        .state
        .players
        .iter()
        .position(|p| p.id == range.id)
        .unwrap();
    range.state.players[index].eliminated = true;
    range.tap();
    assert_eq!(range.tick(), 0);
    range.state.players[index].eliminated = false;
    assert_eq!(
        range.tick(),
        0,
        "the dropped press does not wait for a later tick"
    );
    range.tap();
    range.state.players[index].hp = 0;
    assert_eq!(range.tick(), 0, "a body at zero health does not fire a tap");
}
