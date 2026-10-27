use super::*;
use crate::protocol::{AmmoPool, Role, Team};
use crate::sim::PLAYER_FLOOR_Y;

fn pair(id: u128) -> (GameState, BotController) {
    let mut state = GameState::arsenal();
    state.seed(42);
    state.start_round();
    let bot = BotController::new(Uuid::from_u128(id), BotBehavior::Balanced);
    state.add_player(bot.player_id, "Observer".into(), Role::Agent);
    state.add_player(Uuid::from_u128(id + 100), "Target".into(), Role::Human);
    for (player, x) in state.players.iter_mut().zip([-5.0, 5.0]) {
        player.x = x;
        player.z = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.yaw = 0.0;
        player.weapon = WeaponType::Flechette;
    }
    state.spawn_shields.clear();
    assert!(visible(&state, &state.players[0], &state.players[1]));
    (state, bot)
}

fn observe(state: &mut GameState, bot: &BotController, tick: u64) {
    state.tick = tick;
    state.update_bot_senses(std::slice::from_ref(bot));
}

#[test]
fn conquest_keeps_capture_destination_and_uses_delayed_imperfect_observation() {
    let (mut state, bot) = pair(2);
    state.config.rules = crate::rules::RuleSet::new(GameMode::Conquest, &[], false).unwrap();
    state.conquest = Some(crate::sim::conquest::initial());
    state.players[0].team = Some(Team::Union);
    state.players[1].team = Some(Team::Coalition);
    let destination = bot.intent(&state).goal.unwrap().feet;
    observe(&mut state, &bot, 0);
    let first = bot.intent(&state);
    assert_eq!(first.goal.unwrap().feet, destination);
    assert!(
        !first.action.fire,
        "newly seen enemies cannot trigger an instant shot"
    );
    let observed = state.players[0].bot_senses.target.unwrap();
    let (ideal_yaw, ideal_pitch) =
        crate::combat::aim_at(fighter_eye(&state.players[0]), observed.chest).unwrap();
    assert_ne!(first.action.yaw.unwrap(), ideal_yaw);
    assert_ne!(first.action.pitch.unwrap(), ideal_pitch);
    assert!((first.action.yaw.unwrap() - ideal_yaw).abs() <= AIM_ERROR);
    observe(&mut state, &bot, 12);
    let ready = bot.intent(&state);
    assert!(bot.guard_sensed_action(&state, ready.action.clone()).fire);
    assert_eq!(ready.goal.unwrap().feet, destination);
    // Moving behind cover between observation ticks can veto a shot but
    // cannot feed a new hidden position into either aim or capture routing.
    state.players[1].x = 25.0;
    observe(&mut state, &bot, 13);
    let hidden = bot.intent(&state);
    assert_eq!(hidden.action.yaw, ready.action.yaw);
    assert_eq!(hidden.goal.unwrap().feet, destination);
    assert!(!bot.guard_sensed_action(&state, hidden.action).fire);
    observe(&mut state, &bot, 14);
    let lost = bot.intent(&state);
    assert!(!lost.action.fire);
    assert_eq!(lost.goal.unwrap().feet, destination);
}

#[test]
fn cone_and_authoritative_cover_refuse_acquisition() {
    let (mut state, bot) = pair(2);
    state.players[0].yaw = PI;
    observe(&mut state, &bot, 0);
    assert!(state.players[0].bot_senses.target.is_none());
    assert!(!bot.update(&state).fire);
    state.players[0].yaw = 0.0;
    // The map's east gantry blocks this ray across x=19.
    state.players[1].x = 25.0;
    assert!(!crate::combat::line_of_sight(
        fighter_eye(&state.players[0]),
        fighter_chest(&state.players[1]),
        &state.current_arena().solids,
    ));
    observe(&mut state, &bot, 2);
    assert!(state.players[0].bot_senses.target.is_none());
    assert!(!bot.update(&state).fire);
}

#[test]
fn seeded_eight_and_sixteen_observers_react_after_varied_delays() {
    for count in [8, 16] {
        let mut first_shots = std::collections::BTreeSet::new();
        let mut phases = [0; 2];
        for id in 1..=count {
            let (mut state, bot) = pair(id);
            let mut first = None;
            for tick in 0..12 {
                observe(&mut state, &bot, tick);
                let action = bot.guard_sensed_action(&state, bot.update(&state));
                if action.fire {
                    first = Some(tick);
                    break;
                }
                assert!(
                    tick < 10,
                    "bot failed to react to a stationary visible target"
                );
            }
            let first = first.unwrap();
            assert!((4..=9).contains(&first), "fired at {first}");
            first_shots.insert(first);
            phases[salt(bot.player_id) as usize % 2] += 1;
            let (mut repeat, repeated_bot) = pair(id);
            for tick in 0..=first {
                observe(&mut repeat, &repeated_bot, tick);
            }
            assert_eq!(
                serde_json::to_string(&bot.update(&state)).unwrap(),
                serde_json::to_string(&repeated_bot.update(&repeat)).unwrap()
            );
        }
        assert!(
            first_shots.len() >= 3,
            "opponents should not react in lockstep"
        );
        assert_eq!(phases[0], phases[1]);
    }
}

#[test]
fn aim_has_repeatable_bounded_error_and_turn_speed() {
    let (mut state, bot) = pair(2);
    observe(&mut state, &bot, 0);
    let observed = state.players[0].bot_senses.target.unwrap();
    for tick in 0..120 {
        let error = aim_error(bot.player_id, tick);
        assert_eq!(error, aim_error(bot.player_id, tick));
        assert!(error.iter().all(|value| value.abs() <= AIM_ERROR));
    }
    let action = bot.update(&state);
    let (ideal_yaw, ideal_pitch) =
        crate::combat::aim_at(fighter_eye(&state.players[0]), observed.chest).unwrap();
    assert_ne!(action.yaw.unwrap(), ideal_yaw);
    assert_ne!(action.pitch.unwrap(), ideal_pitch);
    assert!((action.yaw.unwrap() - ideal_yaw).abs() <= AIM_ERROR);
    assert!((action.pitch.unwrap() - ideal_pitch).abs() <= AIM_ERROR);
    state.players[0].yaw = 0.9;
    let action = bot.update(&state);
    assert!(angle_difference(action.yaw.unwrap(), 0.9).abs() <= TURN_PER_TICK + 0.00001);
    assert!(!action.fire);
}

#[test]
fn unseen_motion_does_not_update_memory_and_memory_expires() {
    let (mut state, bot) = pair(2);
    observe(&mut state, &bot, 0);
    let last = state.players[0].bot_senses.target.unwrap();
    state.players[1].x = 25.0;
    observe(&mut state, &bot, 2);
    let remembered = state.players[0].bot_senses.target.unwrap();
    assert!(!remembered.visible);
    assert_eq!(remembered.feet, last.feet);
    assert_eq!(bot.intent(&state).goal.unwrap().feet, last.feet);
    assert!(!bot.update(&state).fire);
    state.players[1].z = 1.0;
    observe(&mut state, &bot, 4);
    assert_eq!(state.players[0].bot_senses.target.unwrap().feet, last.feet);
    observe(&mut state, &bot, MEMORY_TICKS + 2);
    assert!(state.players[0].bot_senses.target.is_none());
    assert_ne!(bot.intent(&state).goal.unwrap().feet, last.feet);
}

#[test]
fn reacquisition_and_respawn_require_a_new_reaction() {
    let (mut state, bot) = pair(2);
    observe(&mut state, &bot, 0);
    observe(&mut state, &bot, 12);
    assert!(bot.guard_sensed_action(&state, bot.update(&state)).fire);
    state.players[1].x = 25.0;
    observe(&mut state, &bot, 14);
    state.players[1].x = 5.0;
    observe(&mut state, &bot, 16);
    assert!(state.players[0].bot_senses.target.unwrap().ready_at >= 20);
    assert!(!bot.update(&state).fire);
    state.players[0].respawn_timer = Some(1);
    observe(&mut state, &bot, 18);
    assert!(state.players[0].bot_senses.target.is_none());
    assert!(!bot.update(&state).fire);
    state.do_respawn(bot.player_id);
    assert!(state.players[0].bot_senses.target.is_none());
    let restored = state.players[0]
        .inventory
        .state(bot.player_id, WeaponType::Flechette, state.tick)
        .unwrap();
    assert_eq!(
        restored.ammo(AmmoPool::Bullets),
        AmmoPool::Bullets.arcade_spawn()
    );
}

#[test]
fn current_cover_vetoes_fire_between_observations() {
    let (mut state, bot) = pair(2);
    observe(&mut state, &bot, 0);
    observe(&mut state, &bot, 12);
    let aimed = bot.update(&state);
    assert!(bot.guard_sensed_action(&state, aimed.clone()).fire);
    state.players[1].x = 25.0;
    observe(&mut state, &bot, 13);
    assert!(state.players[0].bot_senses.target.unwrap().visible);
    assert!(!bot.guard_sensed_action(&state, aimed).fire);
    assert_eq!(state.players[0].bot_senses.target.unwrap().feet[0], 5.0);
}

#[test]
fn allies_parked_dead_and_removed_targets_are_not_combat_goals() {
    let (mut state, bot) = pair(2);
    state.players[0].team = Some(Team::Union);
    state.players[1].team = Some(Team::Union);
    observe(&mut state, &bot, 0);
    assert!(state.players[0].bot_senses.target.is_none());
    state.players[1].team = Some(Team::Coalition);
    state.players[1].detached = true;
    observe(&mut state, &bot, 2);
    assert!(state.players[0].bot_senses.target.is_none());
    state.players[1].detached = false;
    state.players[1].hp = 0;
    observe(&mut state, &bot, 4);
    assert!(state.players[0].bot_senses.target.is_none());
    state.players[1].hp = 100;
    observe(&mut state, &bot, 6);
    assert!(state.players[0].bot_senses.target.is_some());
    state.players.pop();
    assert!(!bot.update(&state).fire);
    observe(&mut state, &bot, 8);
    assert!(state.players[0].bot_senses.target.is_none());
}

#[test]
fn arcade_bot_uses_human_bag_and_timed_reload_without_arming_other_agents() {
    let (mut state, bot) = pair(2);
    state.arm_joined_magazines(state.players[1].id);
    observe(&mut state, &bot, 0);
    let bot_loadout = state.players[0]
        .inventory
        .state(bot.player_id, WeaponType::Flechette, 0)
        .unwrap();
    let human_loadout = state.players[1]
        .inventory
        .state(state.players[1].id, WeaponType::Flechette, 0)
        .unwrap();
    assert_eq!(bot_loadout.loaded, human_loadout.loaded);
    assert_eq!(bot_loadout.ammo, human_loadout.ammo);
    for _ in 0..WeaponType::Flechette.magazine_size().unwrap() {
        assert!(state.players[0].inventory.try_fire(WeaponType::Flechette));
    }
    assert!(!state.players[0].inventory.try_fire(WeaponType::Flechette));
    observe(&mut state, &bot, 2);
    assert!(state.players[0].inventory.reloading());
    state.players[0].inventory.finish_reload(23);
    assert!(!state.players[0].inventory.usable(WeaponType::Flechette));
    state.players[0].inventory.finish_reload(24);
    assert!(state.players[0].inventory.usable(WeaponType::Flechette));
    let loadout = state.players[0]
        .inventory
        .state(bot.player_id, WeaponType::Flechette, 24)
        .unwrap();
    assert_eq!(loadout.ammo(AmmoPool::Bullets), 60);
    let external = Uuid::from_u128(1000);
    state.add_player(external, "External".into(), Role::Agent);
    observe(&mut state, &bot, 26);
    assert!(!state.players.last().unwrap().inventory.armed());
}

fn drain(inventory: &mut crate::inventory::Inventory, weapon: WeaponType) -> usize {
    let mut shots = 0;
    loop {
        if inventory.try_fire(weapon) {
            shots += 1;
            assert!(shots < 500, "finite inventory failed to empty");
        } else if inventory.request_reload(weapon, 0) {
            inventory.finish_reload(100);
        } else {
            return shots;
        }
    }
}

#[test]
fn exhausted_bag_switches_guns_then_routes_to_supply_and_restocks() {
    let (mut state, bot) = pair(2);
    observe(&mut state, &bot, 0);
    assert_eq!(
        drain(&mut state.players[0].inventory, WeaponType::Flechette),
        80
    );
    assert_eq!(bot.update(&state).weapon_swap, Some(WeaponType::Rail));
    assert_eq!(drain(&mut state.players[0].inventory, WeaponType::Rail), 16);
    assert_eq!(
        drain(&mut state.players[0].inventory, WeaponType::Scatter),
        24
    );
    let intent = bot.intent(&state);
    assert!(!intent.action.fire);
    let goal = intent.goal.unwrap();
    assert!(!goal.combat);
    let pad = state
        .pickups
        .iter()
        .find(|pad| [pad.x, pad.floor, pad.z] == goal.feet)
        .unwrap();
    let weapon = pad.kind.weapon().unwrap();
    let pool = weapon.ammo_pool().unwrap();
    state.players[0].x = goal.feet[0];
    state.players[0].y = goal.feet[1] + PLAYER_FLOOR_Y;
    state.players[0].z = goal.feet[2];
    state.tick(0.0);
    let bag = state.players[0]
        .inventory
        .state(bot.player_id, state.players[0].weapon, state.tick)
        .unwrap();
    assert!(
        bag.ammo(pool) > 0,
        "the bot must claim actual authoritative supply"
    );
    state.players[0].weapon = weapon;
    observe(&mut state, &bot, 2);
    assert!(state.players[0].inventory.reloading());
    state.players[0].inventory.finish_reload(100);
    assert!(state.players[0].inventory.usable(weapon));
}

#[test]
fn session_path_preserves_reaction_before_any_resolved_shot() {
    let mut session = crate::session::GameSession::new();
    session.state.seed(42);
    session.spawn_bots(1);
    session.state.start_round();
    session
        .state
        .add_player(Uuid::from_u128(100), "Target".into(), Role::Human);
    let id = session.bots[0].player_id;
    // Enter on this bot's observation phase, before route steering changes its
    // facing. The opposite phase is covered by the staggered reaction fixture.
    session.state.tick = salt(id) % OBSERVE_EVERY;
    for (player, x) in session.state.players.iter_mut().zip([-5.0, 5.0]) {
        player.x = x;
        player.z = 0.0;
        player.y = PLAYER_FLOOR_Y;
        player.yaw = 0.0;
    }
    for _ in 0..4 {
        session.tick_messages(0.05);
        assert!(!session
            .state
            .shot_results
            .iter()
            .any(|shot| shot.shooter_id == id));
    }
    let mut fired = false;
    for _ in 0..20 {
        session.tick_messages(0.05);
        fired |= session
            .state
            .shot_results
            .iter()
            .any(|shot| shot.shooter_id == id);
    }
    assert!(
        fired,
        "reaction gate must eventually permit an ordinary shot"
    );
}

#[test]
fn weapon_only_has_timed_magazines_and_mode_change_restores_single_count() {
    let (mut state, bot) = pair(2);
    state.players[0].inventory = crate::inventory::Inventory::restricted(WeaponType::Rail);
    state.players[0].weapon = WeaponType::Rail;
    observe(&mut state, &bot, 0);
    for _ in 0..4 {
        assert!(state.players[0].inventory.try_fire(WeaponType::Rail));
    }
    assert!(!state.players[0].inventory.try_fire(WeaponType::Rail));
    observe(&mut state, &bot, 2);
    state.players[0].inventory.finish_reload(29);
    assert!(!state.players[0].inventory.usable(WeaponType::Rail));
    state.players[0].inventory.finish_reload(30);
    assert!(state.players[0].inventory.usable(WeaponType::Rail));
    // Every arcade mode now senses; Solo Broadcast keeps the single count.
    state.solo_broadcast.enabled = true;
    observe(&mut state, &bot, 32);
    assert!(!state.players[0].inventory.armed());
    assert!(state.players[0].bot_senses.target.is_none());
    for _ in 0..40 {
        assert!(state.players[0].inventory.try_fire(WeaponType::Rail));
    }
}

#[test]
fn bot_senses_sees_vehicle_occupant_and_seated_bot_sees_target() {
    let (mut state, bot) = pair(2);
    state.add_jeep([5.0, 0.0, 0.0], 0.0).unwrap();
    state.vehicles[0].state.driver = Some(state.players[1].id);
    assert!(visible(&state, &state.players[0], &state.players[1]));

    state.vehicles[0].state.driver = Some(bot.player_id);
    assert!(visible(&state, &state.players[0], &state.players[1]));
}

fn sides(state: &mut GameState, mode: GameMode) {
    state.config.rules = crate::rules::RuleSet::new(mode, &[], false).unwrap();
    state.players[0].team = Some(Team::Union);
    state.players[1].team = Some(Team::Coalition);
}

#[test]
fn ctf_and_sabotage_bots_need_sight_before_they_fight() {
    for mode in [GameMode::Ctf, GameMode::Sabotage] {
        let (mut state, bot) = pair(2);
        sides(&mut state, mode);
        assert!(bot.uses_senses(&state, &state.players[0]), "{mode:?}");
        // Facing away: an opponent five metres behind is not there to fight.
        state.players[0].yaw = PI;
        for tick in 0..12 {
            observe(&mut state, &bot, tick);
            assert!(bot.sensed_enemy(&state, &state.players[0], 25.0).is_none());
            assert!(!bot.guard_sensed_action(&state, bot.update(&state)).fire);
        }
        // Behind the east gantry: still nobody to fight.
        state.players[0].yaw = 0.0;
        state.players[1].x = 25.0;
        for tick in 12..24 {
            observe(&mut state, &bot, tick);
            assert!(bot.sensed_enemy(&state, &state.players[0], 40.0).is_none());
        }
        // In view and in the clear: seen, then fought after a reaction.
        state.players[1].x = 5.0;
        observe(&mut state, &bot, 24);
        observe(&mut state, &bot, 25);
        let (seen, distance) = bot.sensed_enemy(&state, &state.players[0], 25.0).unwrap();
        assert_eq!(seen.id, state.players[1].id);
        assert!((distance - 10.0).abs() < 0.01);
        assert!(bot.sensed_enemy(&state, &state.players[0], 8.0).is_none());
        let fired = (26..40).any(|tick| {
            observe(&mut state, &bot, tick);
            bot.sensed_fight(&state, &state.players[0], None, false)
                .is_some_and(|fight| fight.action.fire)
        });
        assert!(fired, "{mode:?}: a seen opponent is fought");
    }
}

#[test]
fn a_hit_from_out_of_view_turns_the_bot_toward_the_shot() {
    let (mut state, bot) = pair(2);
    state.pickups.clear();
    state.players[0].yaw = PI;
    for tick in 0..4 {
        observe(&mut state, &bot, tick);
    }
    assert!(state.players[0].bot_senses.target.is_none());
    let shooter = state.players[1].id;
    let from = [state.players[1].x, 0.0, state.players[1].z];
    state.players[0].bot_senses.hurt_by(shooter, from, 4);
    // The shooter moves on; the clue is where the shot came from.
    state.players[1].z = 12.0;
    for tick in 5..8 {
        observe(&mut state, &bot, tick);
    }
    let clue = state.players[0].bot_senses.target.unwrap();
    assert!(!clue.visible);
    assert_eq!(clue.feet, from);
    assert_eq!(bot.sensed_threat(&state, &state.players[0]), Some(from));
    let intent = bot.intent(&state);
    assert!(!intent.action.fire, "a clue is never a shot");
    assert_eq!(intent.goal.unwrap().feet, from);
    // The clue fades.
    observe(&mut state, &bot, 4 + HURT_MEMORY + 2);
    observe(&mut state, &bot, 4 + HURT_MEMORY + 3);
    assert!(bot.sensed_threat(&state, &state.players[0]).is_none());
}

#[test]
fn a_fresh_hit_spoils_the_aim_for_a_few_ticks() {
    let deviation = |hurt: bool| {
        let (mut state, bot) = pair(2);
        if hurt {
            let shooter = state.players[1].id;
            state.players[0]
                .bot_senses
                .hurt_by(shooter, [5.0, 0.0, 0.0], 0);
        }
        observe(&mut state, &bot, 0);
        observe(&mut state, &bot, 1);
        let observed = state.players[0].bot_senses.target.unwrap();
        let (ideal, _) =
            crate::combat::aim_at(fighter_eye(&state.players[0]), observed.chest).unwrap();
        let action = bot.update(&state);
        angle_difference(action.yaw.unwrap(), ideal).abs()
    };
    let steady = deviation(false);
    let flinched = deviation(true);
    assert!(steady > 0.0);
    assert!(
        flinched > steady * 2.0 || flinched >= TURN_PER_TICK - 0.0001,
        "steady {steady}, flinched {flinched}"
    );
}

fn full_bag(weapons: &[WeaponType]) -> crate::inventory::Inventory {
    let mut bag = crate::inventory::Inventory::new(EquipmentPolicy::Discovery);
    for weapon in weapons {
        bag.grant_weapon(*weapon);
    }
    for pool in AmmoPool::ALL {
        bag.grant_ammo(pool, 40);
    }
    bag
}

fn lone_bot_with_rail_pad(ahead: f32) -> (GameState, BotController, [f32; 3]) {
    let (mut state, bot) = pair(2);
    state.players.truncate(1);
    state.players[0].inventory = full_bag(&[WeaponType::Flechette]);
    state.players[0].weapon = WeaponType::Flechette;
    let feet = [state.players[0].x + ahead, 0.0, state.players[0].z];
    state.pickups = vec![crate::sim::ArenaPickup {
        claim: crate::protocol::SupplyClaim::Contested,
        id: "rail".into(),
        kind: crate::sim::PickupKind::Weapon(WeaponType::Rail),
        amount: 0,
        x: feet[0],
        y: 0.4,
        z: feet[2],
        floor: 0.0,
        available: false,
        respawn_timer: Some(crate::rules::FFA_POWER_WEAPON_RESPAWN_TICKS),
        secret: false,
    }];
    (state, bot, feet)
}

/// A lone free-for-all bot on the Pistol, with a Rocket dropped `ahead`
/// metres along +x, the bot facing `yaw`.
fn bot_and_drop(yaw: f32, ahead: f32) -> (GameState, BotController, [f32; 3]) {
    let mut state = GameState::new();
    state.seed(42);
    state.config.boss_spawn_ticks = None;
    state.config.compliance_ping_ticks = None;
    state.start_round();
    let bot = BotController::new(Uuid::from_u128(9), BotBehavior::Balanced);
    state.add_player(bot.player_id, "Observer".into(), Role::Agent);
    assert!(state.drops_guns());
    let (x, z, floor) = (-5.0, 0.0, 0.0);
    // Only the drop to want: no pads to weigh it against.
    state.pickups.clear();
    let player = &mut state.players[0];
    player.x = x;
    player.z = z;
    player.y = PLAYER_FLOOR_Y + floor;
    player.yaw = yaw;
    let feet = [x + ahead, floor, z];
    state.dropped_guns.push(crate::sim::drops::DroppedGun {
        serial: 1,
        weapon: WeaponType::Rocket,
        rounds: 3,
        x: feet[0],
        y: floor + 0.4,
        z: feet[2],
        floor,
        expires_at: 10_000,
    });
    (state, bot, feet)
}

fn look_around(state: &mut GameState, bot: &BotController, from: u64) {
    for tick in 0..16 {
        observe(state, bot, from + tick);
    }
}

#[test]
fn a_bot_knows_a_dropped_gun_only_once_it_has_seen_it() {
    // Behind the bot and past underfoot reach: unknown, so not a goal.
    let (mut state, bot, feet) = bot_and_drop(PI, 6.0);
    look_around(&mut state, &bot, 100);
    assert!(state.players[0].bot_senses.pads.drops().is_empty());
    let goal = bot.intent(&state).goal.map(|goal| goal.feet);
    assert_ne!(goal, Some(feet));

    // In view: a gun it cannot fire, close by, is where it goes.
    let (mut state, bot, feet) = bot_and_drop(0.0, 6.0);
    look_around(&mut state, &bot, 100);
    assert_eq!(state.players[0].bot_senses.pads.drops().len(), 1);
    assert_eq!(bot.intent(&state).goal.map(|goal| goal.feet), Some(feet));

    // Somebody takes it while the bot watches: it forgets the gun.
    state.dropped_guns.clear();
    look_around(&mut state, &bot, 120);
    assert!(state.players[0].bot_senses.pads.drops().is_empty());

    // Taken out of view: the bot still believes it is there, until it has
    // surely gone, and walks to see.
    let (mut state, bot, feet) = bot_and_drop(0.0, 6.0);
    look_around(&mut state, &bot, 100);
    state.dropped_guns.clear();
    state.players[0].yaw = PI;
    look_around(&mut state, &bot, 120);
    assert_eq!(bot.intent(&state).goal.map(|goal| goal.feet), Some(feet));
    let expiry = u64::from(crate::sim::drops::DROPPED_GUN_TICKS);
    look_around(&mut state, &bot, 200 + expiry);
    assert!(state.players[0].bot_senses.pads.drops().is_empty());
}

fn rail_eta(state: &GameState) -> Option<u64> {
    state.players[0]
        .bot_senses
        .pad_eta(state, &state.players[0], 0)
}

#[test]
fn a_taken_pad_is_known_only_once_seen_and_its_clock_is_learned() {
    let (mut state, bot, _) = lone_bot_with_rail_pad(10.0);
    // Facing away, the bot cannot know the Rail went.
    state.players[0].yaw = PI;
    for tick in 0..8 {
        observe(&mut state, &bot, tick);
    }
    assert_eq!(rail_eta(&state), Some(0));
    // Turned to it: empty, back on the published clock from now.
    state.players[0].yaw = 0.0;
    for tick in 8..16 {
        observe(&mut state, &bot, tick);
    }
    let eta = rail_eta(&state).unwrap();
    let clock = u64::from(crate::rules::FFA_POWER_WEAPON_RESPAWN_TICKS);
    assert!(eta > clock - 16 && eta <= clock, "eta {eta}");
    // The live timer says something else; the bot's belief does not move.
    state.pickups[0].respawn_timer = Some(5);
    observe(&mut state, &bot, 16);
    observe(&mut state, &bot, 17);
    assert!(rail_eta(&state).unwrap() > 100);
    // Unseen, the learned clock runs out and the pad is believed back.
    // The Railgun is a free-for-all power pad on the 25 s clock.
    let later = clock + 60;
    state.players[0].yaw = PI;
    for tick in later..later + 8 {
        observe(&mut state, &bot, tick);
    }
    assert_eq!(rail_eta(&state), Some(0));
    // A new body still knows the map; a new round puts every pad back.
    state.players[0].yaw = 0.0;
    for tick in later + 8..later + 16 {
        observe(&mut state, &bot, tick);
    }
    assert!(rail_eta(&state).unwrap() > 0);
    state.players[0].bot_senses.forget_fighters();
    assert!(rail_eta(&state).unwrap() > 0);
    state.round_number += 1;
    assert_eq!(rail_eta(&state), Some(0));
}

#[test]
fn a_bot_leaves_for_a_returning_rail_and_waits_on_it() {
    let (mut state, bot, feet) = lone_bot_with_rail_pad(10.0);
    for tick in 0..8 {
        observe(&mut state, &bot, tick);
    }
    let back_at = 8 + rail_eta(&state).unwrap();
    // Twelve seconds early is not an appointment: the bot roams.
    let roam = bot.intent(&state);
    assert_ne!(roam.goal.map(|goal| goal.feet), Some(feet));
    // Inside the walk plus a little slack, it sets off before the return.
    state.players[0].yaw = PI;
    for tick in back_at - 70..back_at - 62 {
        observe(&mut state, &bot, tick);
    }
    let set_off = bot.intent(&state);
    assert_eq!(set_off.goal.unwrap().feet, feet);
    assert!(
        !state.pickups[0].available,
        "it left before the pad came back"
    );
    // Standing on the empty pad, it holds and sweeps instead of wandering.
    state.players[0].x = feet[0];
    state.players[0].z = feet[2];
    state.players[0].yaw = 0.0;
    for tick in back_at - 20..back_at - 12 {
        observe(&mut state, &bot, tick);
    }
    let waiting = bot.intent(&state);
    assert!(waiting.goal.is_none());
    assert!(waiting.action.turn_left || waiting.action.turn_right);
    assert!(!waiting.action.forward);
}

#[test]
fn personalities_take_found_guns_to_their_distances() {
    let (mut state, _) = pair(2);
    state.players[0].inventory = full_bag(&[
        WeaponType::Flechette,
        WeaponType::Sniper,
        WeaponType::Repeater,
        WeaponType::Rocket,
    ]);
    let bot = &state.players[0];
    for weapon in [WeaponType::Sniper, WeaponType::Repeater, WeaponType::Rocket] {
        assert!(bot.inventory.usable(weapon), "{weapon:?} in the bag");
    }
    let own = |behavior| (behavior, crate::roster::behavior_habits(behavior));
    let pick = |(behavior, habits), distance| preferred_weapon(behavior, habits, bot, distance);
    assert_eq!(pick(own(BotBehavior::Defensive), 40.0), WeaponType::Sniper);
    assert_eq!(pick(own(BotBehavior::Aggressive), 15.0), WeaponType::Rocket);
    // Inside the Rocket's safe distance the rusher fights with the next gun.
    assert_eq!(
        pick(own(BotBehavior::Aggressive), 5.0),
        WeaponType::Repeater
    );
    // A launcher in the bag is every personality's mid-range gun...
    assert_eq!(pick(own(BotBehavior::Flanker), 15.0), WeaponType::Rocket);
    assert_eq!(pick(own(BotBehavior::Balanced), 15.0), WeaponType::Rocket);
    // ...except where canon names a favourite: Hangar Candy are flechette
    // mains, and the Night Watch keep the rail for a long lane.
    let candy = crate::roster::habits("Eyes Only", BotBehavior::Balanced);
    assert_eq!(
        pick((BotBehavior::Balanced, candy), 15.0),
        WeaponType::Flechette
    );
    assert_eq!(pick(own(BotBehavior::Flanker), 3.0), WeaponType::Flechette);
    // A Rocket is never fired into a body at arm's length.
    let (mut state, bot) = pair(2);
    state.players[0].inventory = full_bag(&[WeaponType::Rocket]);
    state.players[0].weapon = WeaponType::Rocket;
    state.players[1].x = -2.0;
    for tick in 0..20 {
        observe(&mut state, &bot, tick);
        let observed = state.players[0].bot_senses.target.unwrap();
        let fight = bot.observed_combat_intent(&state, &state.players[0], observed, None, false);
        assert!(!fight.action.fire, "tick {tick}");
    }
}

/// Watch a target walk +z at `speed` metres a second for `ticks` ticks.
fn watch_strafe(state: &mut GameState, bot: &BotController, speed: f32, ticks: u64) {
    let start = state.players[1].z;
    for tick in 0..ticks {
        state.players[1].z = start + speed * tick as f32 / 20.0;
        observe(state, bot, tick);
    }
}

#[test]
fn the_rocket_goes_at_the_floor_where_a_strafing_body_will_be() {
    let (mut state, bot) = pair(30);
    open_ground(&mut state, &[10.0]);
    state.players[0].inventory = full_bag(&[WeaponType::Rocket]);
    state.players[0].weapon = WeaponType::Rocket;
    watch_strafe(&mut state, &bot, 3.0, 12);
    let observed = state.players[0].bot_senses.target.unwrap();
    // Two sightings in a row give the ground velocity it watched.
    assert!(
        (observed.velocity[1] - 3.0).abs() < 0.5,
        "{:?}",
        observed.velocity
    );
    assert!(observed.velocity[0].abs() < 0.1);
    let distance =
        (observed.feet[0] - state.players[0].x).hypot(observed.feet[2] - state.players[0].z);
    let aim = rocket_aim(&state, &state.players[0], &observed, distance);
    // At the shins, led by the flight time, on the body's own floor.
    let lead = observed.velocity[1] * distance / crate::sim::rocket::SPEED;
    assert!(
        (aim.point[2] - (observed.feet[2] + lead)).abs() < 0.01,
        "{aim:?}"
    );
    assert!((aim.point[1] - (observed.feet[1] + ROCKET_AIM_HEIGHT)).abs() < 0.01);
    assert!(aim.clear);
    // A long lead is capped.
    let mut quick = observed;
    quick.velocity = [0.0, 40.0];
    let capped = rocket_aim(&state, &state.players[0], &quick, distance);
    assert!((capped.point[2] - quick.feet[2] - ROCKET_MAX_LEAD).abs() < 0.01);
    // A body standing above the shooter's floor takes the led chest instead.
    let mut above = observed;
    above.feet[1] += 2.0;
    above.chest[1] += 2.0;
    let high = rocket_aim(&state, &state.players[0], &above, distance);
    assert!((high.point[1] - above.chest[1]).abs() < 0.01, "{high:?}");
    // And once ready, it fires at that point.
    let ready = bot.observed_combat_intent(&state, &state.players[0], observed, None, true);
    let (yaw, _) = crate::combat::aim_at(fighter_eye(&state.players[0]), aim.point).unwrap();
    assert!((ready.action.yaw.unwrap() - state.players[0].yaw).abs() <= TURN_PER_TICK + 1e-4);
    assert!(angle_difference(yaw, state.players[0].yaw).abs() < 0.6);
}

/// Put the observer on a stretch of the lot's ground floor with nothing
/// between its eye and the floor at each of `aheads` metres in front, across
/// a six metre strafe, so a floor aim is not refused by a kerb or a queue
/// rail. The target stands at the first distance.
fn open_ground(state: &mut GameState, aheads: &[f32]) {
    let arena = state.current_arena().into_owned();
    let flat = |x: f32, z: f32| arena.support_height(x, z, 3.0).abs() < 0.01;
    let eye_height = fighter_eye(&state.players[0])[1] - (state.players[0].y - PLAYER_FLOOR_Y);
    for x in (-40..=40).step_by(2).map(|x| x as f32) {
        for z in (-40..=40).step_by(2).map(|z| z as f32) {
            let eye = [x, eye_height, z];
            let clear = flat(x, z)
                && aheads.iter().all(|ahead| {
                    (0..=12).all(|step| {
                        let along = z + step as f32 * 0.5;
                        flat(x + ahead, along)
                            && [0.2, 1.6].iter().all(|height| {
                                crate::combat::line_of_sight(
                                    eye,
                                    [x + ahead, *height, along],
                                    &arena.solids,
                                )
                            })
                    })
                });
            if clear {
                state.players[0].x = x;
                state.players[0].z = z;
                state.players[1].x = x + aheads[0];
                state.players[1].z = z;
                return;
            }
        }
    }
    panic!("no open ground on the lot");
}

fn observe_for(state: &mut GameState, bot: &BotController, ticks: std::ops::Range<u64>) {
    for tick in ticks {
        observe(state, bot, tick);
    }
}

#[test]
fn the_rocket_holds_inside_its_safe_distance_and_gives_ground() {
    let (mut state, bot) = pair(31);
    open_ground(&mut state, &[4.0]);
    state.players[0].inventory = full_bag(&[WeaponType::Rocket, WeaponType::Flechette]);
    state.players[0].weapon = WeaponType::Rocket;
    observe_for(&mut state, &bot, 0..2);
    for tick in 2..20 {
        observe(&mut state, &bot, tick);
        let observed = state.players[0].bot_senses.target.unwrap();
        let distance =
            (observed.feet[0] - state.players[0].x).hypot(observed.feet[2] - state.players[0].z);
        assert!(!rocket_aim(&state, &state.players[0], &observed, distance).clear);
        let fight = bot.observed_combat_intent(&state, &state.players[0], observed, None, false);
        assert!(!fight.action.fire, "tick {tick}");
        assert!(fight.action.back && !fight.action.forward, "it backs off");
        // Preferring a gun, it changes hands instead.
        let prefer = bot.observed_combat_intent(&state, &state.players[0], observed, None, true);
        assert_eq!(prefer.action.weapon_swap, Some(WeaponType::Flechette));
    }
}

#[test]
fn between_fights_a_bot_readies_the_gun_for_the_next_one() {
    let (mut state, bot) = pair(32);
    state.players.truncate(1);
    state.players[0].inventory =
        full_bag(&[WeaponType::Tack, WeaponType::Flechette, WeaponType::Rocket]);
    state.players[0].weapon = WeaponType::Tack;
    observe_for(&mut state, &bot, 0..2);
    // The balanced regular reaches for the Rocket it carries.
    assert_eq!(
        bot.intent(&state).action.weapon_swap,
        Some(WeaponType::Rocket)
    );
    // Hangar Candy keep the Flechette in hand.
    state.players[0].name = "Need To Know".into();
    assert_eq!(
        bot.intent(&state).action.weapon_swap,
        Some(WeaponType::Flechette)
    );
}

fn pad_behind(state: &mut GameState, kind: crate::sim::PickupKind) -> [f32; 3] {
    let feet = [state.players[0].x - 30.0, 0.0, state.players[0].z];
    state.pickups = vec![crate::sim::ArenaPickup {
        claim: crate::protocol::SupplyClaim::Contested,
        id: "behind".into(),
        kind,
        amount: 100,
        x: feet[0],
        y: 0.4,
        z: feet[2],
        floor: 0.0,
        available: true,
        respawn_timer: None,
        secret: false,
    }];
    feet
}

#[test]
fn a_plate_timer_walks_off_a_long_trade_for_the_plate_and_still_shoots() {
    let (mut state, _) = pair(33);
    open_ground(&mut state, &[20.0, 8.0]);
    let bot = BotController::new(state.players[0].id, BotBehavior::Aggressive);
    state.players[0].inventory = full_bag(&[WeaponType::Flechette]);
    let feet = pad_behind(&mut state, crate::sim::PickupKind::Plate);
    // A body in a long trade, past the appointment distance.
    observe_for(&mut state, &bot, 0..12);
    assert!(state.players[0].bot_senses.target.unwrap().visible);
    let walk = bot.intent(&state);
    assert_eq!(walk.goal.unwrap().feet, feet, "the Plate is due: it goes");
    assert!(walk.action.yaw.is_some(), "and keeps its aim on the fight");
    // Close in, the fight wins.
    state.players[1].x = state.players[0].x + 8.0;
    observe_for(&mut state, &bot, 12..24);
    assert!(bot.intent(&state).goal.unwrap().combat);
    // A balanced regular does not time the Plate: the long trade goes on.
    state.players[1].x = state.players[0].x + 20.0;
    let balanced = BotController::new(state.players[0].id, BotBehavior::Balanced);
    observe_for(&mut state, &balanced, 24..36);
    assert!(balanced.intent(&state).goal.unwrap().combat);
    // Crackpot, sitting a balanced seat here, times it by canon.
    state.players[0].name = "Crackpot".into();
    assert_eq!(balanced.intent(&state).goal.unwrap().feet, feet);
    // And anyone holding the gun they like goes for plate next.
    state.players[0].name = "Observer".into();
    state.players[0].inventory = full_bag(&[WeaponType::Flechette, WeaponType::Rocket]);
    assert_eq!(balanced.intent(&state).goal.unwrap().feet, feet);
}

#[test]
fn a_fresh_life_on_the_pistol_arms_up_before_a_long_trade() {
    let (mut state, bot) = pair(34);
    open_ground(&mut state, &[20.0]);
    state.players[0].inventory = full_bag(&[WeaponType::Tack]);
    state.players[0].weapon = WeaponType::Tack;
    let feet = pad_behind(
        &mut state,
        crate::sim::PickupKind::Weapon(WeaponType::Scatter),
    );
    observe_for(&mut state, &bot, 0..12);
    assert!(state.players[0].bot_senses.target.unwrap().visible);
    assert_eq!(bot.intent(&state).goal.unwrap().feet, feet);
    // With a real gun in hand the same trade is fought.
    state.players[0].inventory = full_bag(&[WeaponType::Tack, WeaponType::Flechette]);
    assert!(bot.intent(&state).goal.unwrap().combat);
}

#[test]
fn among_new_sightings_the_fighter_a_bot_owes_comes_first() {
    let (mut state, bot) = pair(35);
    open_ground(&mut state, &[6.0, 9.0]);
    let owed = Uuid::from_u128(36);
    state.add_player(owed, "Owed".into(), Role::Human);
    let (x, z) = (state.players[0].x, state.players[0].z);
    let last = state.players.len() - 1;
    state.players[last].x = x + 9.0;
    state.players[last].z = z;
    state.players[last].y = PLAYER_FLOOR_Y;
    state.spawn_shields.clear();
    observe_for(&mut state, &bot, 0..2);
    assert_eq!(
        state.players[0].bot_senses.target.unwrap().id,
        state.players[1].id,
        "with a clean book the nearest comes first"
    );
    state.players[0].bot_senses = BotSenses::default();
    state.head_to_head.record("Owed", "Observer");
    observe_for(&mut state, &bot, 2..4);
    assert_eq!(state.players[0].bot_senses.target.unwrap().id, owed);
}
