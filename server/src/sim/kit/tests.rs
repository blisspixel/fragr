//! The free-for-all Pistol start, its exceptions, and the map supply that
//! makes it fair.
use super::*;
use crate::protocol::{AmmoPool, GameEvent, Mutator, Role, ServerMessage};
use crate::rules::{RuleSet, FFA_RESPAWN_DELAY_TICKS};
use crate::sim::{MapKind, MatchConfig, PickupKind, RoundState, PLAYER_FLOOR_Y};

const DT: f32 = 0.05;

fn ffa(map: MapKind) -> GameState {
    let mut state = GameState::with_map(map, false);
    state.seed(42);
    state.config = MatchConfig {
        warmup_ticks: 1,
        boss_spawn_ticks: None,
        compliance_ping_ticks: None,
        ..MatchConfig::default()
    };
    state.start_round();
    state
}

fn join(state: &mut GameState, n: u128, role: Role) -> Uuid {
    let id = Uuid::from_u128(n);
    state.add_player(id, format!("F{n}"), role);
    id
}

fn fighter(state: &GameState, id: Uuid) -> &crate::sim::Player {
    state.players.iter().find(|p| p.id == id).unwrap()
}

fn owned(state: &GameState, id: Uuid) -> Vec<WeaponType> {
    let p = fighter(state, id);
    WeaponType::ALL
        .into_iter()
        .filter(|w| p.inventory.owns(*w))
        .collect()
}

fn stand_on(state: &mut GameState, id: Uuid, pad: &str) {
    let (x, z, floor) = state
        .pickups
        .iter()
        .find(|p| p.id == pad)
        .map(|p| (p.x, p.z, p.floor))
        .unwrap();
    let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = x;
    p.z = z;
    p.y = PLAYER_FLOOR_Y + floor;
}

fn park(state: &mut GameState, id: Uuid) {
    let p = state.players.iter_mut().find(|p| p.id == id).unwrap();
    p.x = 0.0;
    p.z = 0.0;
    p.y = PLAYER_FLOOR_Y;
}

fn kill(state: &mut GameState, killer: Uuid, victim: Uuid) {
    assert!(state.hit_for_test(killer, victim, 1000));
}

fn select(state: &mut GameState, id: Uuid, weapon: WeaponType) {
    state.set_action(
        id,
        crate::protocol::Action {
            weapon_swap: Some(weapon),
            ..Default::default()
        },
    );
    state.tick(DT);
}

#[test]
fn a_free_for_all_life_starts_with_the_pistol_and_fists_and_nothing_else() {
    let mut state = ffa(MapKind::ComplianceYard);
    let human = join(&mut state, 1, Role::Human);
    let agent = join(&mut state, 2, Role::Agent);
    state.arm_joined_magazines(human);
    for id in [human, agent] {
        assert_eq!(fighter(&state, id).weapon, WeaponType::Tack);
        assert_eq!(owned(&state, id), [WeaponType::Fists, WeaponType::Tack]);
        let loadout = fighter(&state, id)
            .inventory
            .state(id, WeaponType::Tack, state.tick)
            .unwrap();
        assert_eq!(
            loadout.ammo(AmmoPool::Bullets),
            WeaponType::Tack.pickup_rounds()
        );
        assert_eq!(loadout.ammo(AmmoPool::Shells), 0);
        assert_eq!(loadout.ammo(AmmoPool::Cells), 0);
    }
    // A human reloads a twelve-round Pistol magazine from the fifty.
    let human_loadout = fighter(&state, human)
        .inventory
        .state(human, WeaponType::Tack, state.tick)
        .unwrap();
    assert_eq!(human_loadout.shots(WeaponType::Tack), Some(12));
    // Stronger guns cannot be selected before they are owned.
    for weapon in [WeaponType::Flechette, WeaponType::Scatter, WeaponType::Rail] {
        select(&mut state, human, weapon);
        assert_eq!(
            fighter(&state, human).weapon,
            WeaponType::Tack,
            "{weapon:?}"
        );
        assert!(!fighter(&state, human).inventory.usable(weapon));
    }
    select(&mut state, human, WeaponType::Fists);
    assert_eq!(fighter(&state, human).weapon, WeaponType::Fists);
    // Every reader sees the kit in the rules.
    let rules = state.wire_rules().unwrap();
    assert_eq!(rules.start_kit, [WeaponType::Fists, WeaponType::Tack]);
    assert_eq!(
        state.equipment_policy(),
        crate::protocol::EquipmentPolicy::Discovery
    );
    assert!(state.sidearm_start());
}

#[test]
fn a_weapon_pad_grants_the_gun_once_and_repeat_pickups_add_ammo_without_a_switch() {
    let mut state = ffa(MapKind::ComplianceYard);
    let id = join(&mut state, 1, Role::Human);
    state.arm_joined_magazines(id);
    stand_on(&mut state, id, "pad_flechette");
    state.tick(DT);
    // A newly found gun becomes current once.
    assert_eq!(fighter(&state, id).weapon, WeaponType::Flechette);
    assert!(fighter(&state, id).inventory.owns(WeaponType::Flechette));
    let events = state.take_events();
    assert!(events.iter().any(|e| matches!(e,
        GameEvent::Pickup { kind, weapon, pickup_id, .. }
            if kind == "weapon" && weapon == "Flechette" && pickup_id == "pad_flechette")));
    let pad = state
        .pickups
        .iter()
        .find(|p| p.id == "pad_flechette")
        .unwrap();
    assert!(!pad.available);
    assert_eq!(
        pad.respawn_timer,
        Some(crate::rules::FFA_WEAPON_RESPAWN_TICKS)
    );
    // Back on the Pistol, the pad returns, and taking it again is ammunition.
    select(&mut state, id, WeaponType::Tack);
    assert_eq!(fighter(&state, id).weapon, WeaponType::Tack);
    let before = fighter(&state, id)
        .inventory
        .state(id, WeaponType::Tack, state.tick)
        .unwrap()
        .ammo(AmmoPool::Bullets);
    park(&mut state, id);
    for _ in 0..crate::rules::FFA_WEAPON_RESPAWN_TICKS {
        state.tick(DT);
    }
    assert!(
        state
            .pickups
            .iter()
            .find(|p| p.id == "pad_flechette")
            .unwrap()
            .available
    );
    stand_on(&mut state, id, "pad_flechette");
    state.tick(DT);
    let after = fighter(&state, id)
        .inventory
        .state(id, WeaponType::Tack, state.tick)
        .unwrap()
        .ammo(AmmoPool::Bullets);
    assert!(after > before, "{before} -> {after}");
    assert_eq!(
        fighter(&state, id).weapon,
        WeaponType::Tack,
        "a repeat pickup never forces a switch"
    );
}

#[test]
fn free_for_all_pad_clocks_are_appointments_and_team_clocks_are_unchanged() {
    let ffa_rules = RuleSet::default();
    assert_eq!(
        ffa_rules.pad_respawn_ticks(Some(WeaponType::Flechette), false),
        Some(20 * 15)
    );
    assert_eq!(
        ffa_rules.pad_respawn_ticks(Some(WeaponType::Scatter), false),
        Some(20 * 15)
    );
    assert_eq!(
        ffa_rules.pad_respawn_ticks(Some(WeaponType::Rail), false),
        Some(20 * 25)
    );
    assert_eq!(
        ffa_rules.pad_respawn_ticks(Some(WeaponType::Sniper), false),
        Some(20 * 25)
    );
    assert_eq!(
        ffa_rules.pad_respawn_ticks(Some(WeaponType::Tack), false),
        Some(20 * 8)
    );
    assert_eq!(ffa_rules.pad_respawn_ticks(None, true), Some(20 * 25));
    let team = RuleSet::new(GameMode::Tdm, &[], false).unwrap();
    assert_eq!(
        team.pad_respawn_ticks(Some(WeaponType::Rail), false),
        Some(20 * 30)
    );
    assert_eq!(team.pad_respawn_ticks(None, true), None);

    let mut state = ffa(MapKind::ComplianceYard);
    let id = join(&mut state, 1, Role::Human);
    for (pad, ticks) in [
        ("pad_rail", crate::rules::FFA_POWER_WEAPON_RESPAWN_TICKS),
        ("pad_armor", crate::rules::FFA_HEALTH_ARMOR_RESPAWN_TICKS),
    ] {
        stand_on(&mut state, id, pad);
        state.tick(DT);
        let pad = state.pickups.iter().find(|p| p.id == pad).unwrap();
        assert_eq!(pad.respawn_timer, Some(ticks), "{}", pad.id);
    }
}

#[test]
fn death_loses_the_found_guns_and_the_next_life_starts_on_the_kit_after_four_seconds() {
    let mut state = ffa(MapKind::ComplianceYard);
    let victim = join(&mut state, 1, Role::Human);
    let killer = join(&mut state, 2, Role::Agent);
    state.arm_joined_magazines(victim);
    stand_on(&mut state, victim, "pad_rail");
    state.tick(DT);
    assert_eq!(fighter(&state, victim).weapon, WeaponType::Rail);
    park(&mut state, victim);
    kill(&mut state, killer, victim);
    // While down, the private loadout still names what this life carried, so
    // the death view can say exactly what was lost.
    let down = fighter(&state, victim);
    assert_eq!(down.respawn_timer, Some(FFA_RESPAWN_DELAY_TICKS));
    assert!(down.inventory.owns(WeaponType::Rail));
    let revision = down.inventory.revision();
    for _ in 0..FFA_RESPAWN_DELAY_TICKS - 1 {
        state.tick(DT);
        assert!(fighter(&state, victim).respawn_timer.is_some());
    }
    for _ in 0..3 {
        state.tick(DT);
    }
    let back = fighter(&state, victim);
    assert!(back.respawn_timer.is_none() && back.hp > 0);
    assert_eq!(back.weapon, WeaponType::Tack);
    assert_eq!(owned(&state, victim), [WeaponType::Fists, WeaponType::Tack]);
    assert!(
        back.inventory.armed(),
        "a human keeps magazines across lives"
    );
    assert!(
        back.inventory.revision() > revision,
        "the private loadout never rewinds"
    );
    assert_eq!(FFA_RESPAWN_DELAY_TICKS, 80);
}

#[test]
fn a_round_restart_and_a_reconnect_both_start_on_the_kit() {
    let mut state = ffa(MapKind::ComplianceYard);
    let id = join(&mut state, 1, Role::Human);
    stand_on(&mut state, id, "pad_scatter");
    state.tick(DT);
    assert!(fighter(&state, id).inventory.owns(WeaponType::Scatter));
    state.end_round("show over".into());
    state.start_round();
    assert_eq!(state.round_state, RoundState::Active);
    assert_eq!(fighter(&state, id).weapon, WeaponType::Tack);
    assert_eq!(owned(&state, id), [WeaponType::Fists, WeaponType::Tack]);

    stand_on(&mut state, id, "pad_scatter");
    state.tick(DT);
    assert!(fighter(&state, id).inventory.owns(WeaponType::Scatter));
    // A reconnect is a new participant: it never resumes a found arsenal.
    state.remove_player(id);
    let again = join(&mut state, 1, Role::Human);
    assert_eq!(owned(&state, again), [WeaponType::Fists, WeaponType::Tack]);
}

#[test]
fn every_exception_keeps_its_own_kit() {
    let kit = |mode: GameMode, mutators: &[Mutator]| {
        let mut state = GameState::with_map(MapKind::Sector9, false);
        state.apply_config(MatchConfig {
            rules: RuleSet::new(mode, mutators, false).unwrap(),
            ..MatchConfig::default()
        });
        let (inventory, weapon) = state.fresh_inventory();
        let owned: Vec<WeaponType> = WeaponType::ALL
            .into_iter()
            .filter(|w| inventory.owns(*w))
            .collect();
        (weapon, owned, state.wire_rules().unwrap().start_kit)
    };
    let arsenal = vec![WeaponType::Flechette, WeaponType::Scatter, WeaponType::Rail];
    for (mode, mutators) in [
        (GameMode::Tdm, vec![]),
        (GameMode::Ctf, vec![]),
        (GameMode::Ffa, vec![Mutator::GoldenRail]),
        (GameMode::Ffa, vec![Mutator::FullArsenal]),
        (
            GameMode::Ffa,
            vec![Mutator::FullArsenal, Mutator::LicenceToKill],
        ),
    ] {
        let (weapon, owned, wire) = kit(mode, &mutators);
        assert_eq!(weapon, WeaponType::Flechette, "{mode:?} {mutators:?}");
        assert_eq!(owned, arsenal, "{mode:?} {mutators:?}");
        assert_eq!(wire, arsenal, "{mode:?} {mutators:?}");
    }
    for (mutator, weapon) in [
        (Mutator::RailOnly, WeaponType::Rail),
        (Mutator::ShotgunOnly, WeaponType::Scatter),
        (Mutator::FistsOnly, WeaponType::Fists),
    ] {
        assert_eq!(
            kit(GameMode::Ffa, &[mutator]),
            (weapon, vec![weapon], vec![weapon])
        );
    }
    // Licence to Kill and Two Lives do not choose weapons: the Pistol start holds.
    for mutator in [Mutator::LicenceToKill, Mutator::TwoLives] {
        let (weapon, owned, _) = kit(GameMode::Ffa, &[mutator]);
        assert_eq!(weapon, WeaponType::Tack);
        assert_eq!(owned, [WeaponType::Fists, WeaponType::Tack]);
    }
    // Sabotage owns its starts: empty-handed by default, the Pistol in 5v5.
    let (weapon, _, wire) = kit(GameMode::Sabotage, &[]);
    assert_eq!((weapon, wire), (WeaponType::Fists, vec![WeaponType::Fists]));
    let mut five = GameState::with_map(MapKind::Sector9, false);
    let mut config = MatchConfig {
        rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
        ..MatchConfig::default()
    };
    config.sabotage.five_vs_five = true;
    five.apply_config(config);
    assert_eq!(five.fresh_inventory().1, WeaponType::Tack);
    // Episode 0 keeps the arena arsenal it was built around.
    let mut episode = GameState::with_map(MapKind::ArenaDuel, false);
    episode.solo_broadcast.enabled = true;
    assert_eq!(episode.fresh_inventory().1, WeaponType::Flechette);
    assert!(!episode.sidearm_start());
    // A campaign map carries its own equipment and names no kit.
    let map = crate::maps::AuthoredMap::read(
        include_str!("../../../maps/m06_port_of_entry.json").as_bytes(),
    )
    .unwrap();
    let campaign = GameState::with_authored_map(map);
    assert!(campaign.start_kit().is_none());
    assert!(campaign.wire_rules().is_none());
    assert_eq!(campaign.fresh_inventory().1, WeaponType::Fists);
}

#[test]
fn full_arsenal_is_a_free_for_all_host_rule_only() {
    assert!(RuleSet::new(GameMode::Ffa, &[Mutator::FullArsenal], false).is_ok());
    for mode in [
        GameMode::Tdm,
        GameMode::Ctf,
        GameMode::Sabotage,
        GameMode::Conquest,
    ] {
        let error = RuleSet::new(mode, &[Mutator::FullArsenal], false).unwrap_err();
        assert!(error.contains("own kit"), "{error}");
    }
    for twin in [Mutator::RailOnly, Mutator::FistsOnly, Mutator::GoldenRail] {
        let error = RuleSet::new(GameMode::Ffa, &[Mutator::FullArsenal, twin], false).unwrap_err();
        assert!(error.contains("full-arsenal"), "{error}");
    }
    let rules = RuleSet::new(GameMode::Ffa, &[Mutator::FullArsenal], false).unwrap();
    assert_eq!(rules.name(), "Free-for-all: Full Arsenal");
    assert!(!rules.is_plain());
}

#[test]
fn the_cpu_benchmark_fixture_keeps_the_arena_arsenal() {
    let config = crate::bench::fixture_config();
    assert!(config.rules.has(Mutator::FullArsenal));
    let mut session = crate::session::GameSession::with_map(MapKind::ArenaDuel, false);
    session.state.config = config;
    session.spawn_bots(2);
    assert!(!session.state.sidearm_start());
    assert!(session
        .state
        .players
        .iter()
        .all(|p| p.inventory.owns(WeaponType::Rail)));
}

#[test]
fn a_joined_human_receives_the_kit_privately_and_spectators_receive_nothing() {
    let mut session = crate::session::GameSession::with_map(MapKind::ArenaDuel, false);
    let id = Uuid::from_u128(7);
    session
        .state
        .add_player(id, "Meat Proxy".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    session.client_to_player.insert(Uuid::from_u128(70), id);
    session.tick_messages(DT);
    let unicasts = session.take_unicasts();
    let loadout = unicasts
        .iter()
        .find_map(|(recipient, message)| match (recipient, message) {
            (crate::session::Recipient::Player(to), ServerMessage::Loadout(l)) if *to == id => {
                Some(l.clone())
            }
            _ => None,
        })
        .expect("the joined fighter receives its loadout");
    assert_eq!(loadout.selected, WeaponType::Tack);
    assert_eq!(loadout.weapons, [WeaponType::Fists, WeaponType::Tack]);
    assert!(unicasts.iter().all(|(recipient, message)| !matches!(
        message,
        ServerMessage::Loadout(_)
    ) || *recipient
        == crate::session::Recipient::Player(id)));
}

/// Agents, the scripted bot, the brain and the harness share one equipment
/// helper. On the Pistol it goes and gets a gun, and holding one it fights.
#[test]
fn the_shared_agent_helper_routes_a_pistol_life_to_a_gun_pad() {
    let mut state = ffa(MapKind::ComplianceYard);
    let agent = join(&mut state, 1, Role::Agent);
    let rival = join(&mut state, 2, Role::Agent);
    park(&mut state, agent);
    let far = state.players.iter_mut().find(|p| p.id == rival).unwrap();
    far.x = 0.0;
    far.z = 40.0;
    let loadout = |state: &GameState| {
        let p = fighter(state, agent);
        p.inventory.state(agent, p.weapon, state.tick).unwrap()
    };
    let wanted = crate::protocol::Action {
        fire: true,
        look_at: Some(crate::protocol::LookAt {
            player_id: Some(rival),
            ..Default::default()
        }),
        ..Default::default()
    };
    let action = crate::inventory::control_action(
        agent,
        &state.snapshot(),
        Some(&loadout(&state)),
        wanted.clone(),
    );
    let goal = action.look_at.as_ref().expect("routes somewhere");
    assert!(
        goal.player_id.is_none() && action.forward && !action.fire,
        "{action:?}"
    );
    let pad = state
        .pickups
        .iter()
        .find(|p| Some(p.x) == goal.x && Some(p.z) == goal.z)
        .expect("the route ends on a pad");
    assert!(matches!(pad.kind, PickupKind::Weapon(w) if w != WeaponType::Tack));
    // A rival inside the Pistol's reach, with no gun a few steps away, is a
    // fight on the Pistol rather than a walk past it.
    let pad_distance = pad.x.hypot(pad.z);
    assert!(pad_distance > 8.0, "the nearest gun is past the detour");
    let close = state.players.iter_mut().find(|p| p.id == rival).unwrap();
    close.z = 20.0;
    let action = crate::inventory::control_action(
        agent,
        &state.snapshot(),
        Some(&loadout(&state)),
        wanted.clone(),
    );
    assert_eq!(
        action.look_at.as_ref().and_then(|aim| aim.player_id),
        Some(rival),
        "{action:?}"
    );
    assert!(action.fire, "{action:?}");
    let far = state.players.iter_mut().find(|p| p.id == rival).unwrap();
    far.z = 40.0;
    // A campaign participant on its found Pistol keeps its mission's pacing:
    // the same intent stays a fight.
    let mut mission = state.snapshot();
    for p in &mut mission.players {
        p.campaign = Some(if p.id == agent {
            crate::protocol::CampaignActor::Participant {}
        } else {
            crate::protocol::CampaignActor::Hostile {
                kind: crate::protocol::EnemyKind::Clerk,
                phase: crate::protocol::EnemyPhase::Idle,
                phase_started: 0,
                phase_ends: 0,
                seated: false,
                control: crate::protocol::ControlDomain::Union,
            }
        });
    }
    let action =
        crate::inventory::control_action(agent, &mission, Some(&loadout(&state)), wanted.clone());
    assert_eq!(
        action.look_at.as_ref().and_then(|aim| aim.player_id),
        Some(rival)
    );
    // Holding the Shotgun, the same intent is a fight again.
    stand_on(&mut state, agent, "scrap_scatter_s");
    state.tick(DT);
    assert!(fighter(&state, agent).inventory.owns(WeaponType::Scatter));
    let action =
        crate::inventory::control_action(agent, &state.snapshot(), Some(&loadout(&state)), wanted);
    assert_eq!(action.look_at.and_then(|aim| aim.player_id), Some(rival));
}

#[test]
fn free_for_all_supply_pads_are_laid_only_in_free_for_all() {
    for (map, modes) in [
        (MapKind::ComplianceYard, vec![GameMode::Tdm, GameMode::Ctf]),
        (
            MapKind::Sector9,
            vec![GameMode::Tdm, GameMode::Ctf, GameMode::Sabotage],
        ),
    ] {
        let scrap: Vec<String> = map.scrap_pads().into_iter().map(|p| p.id).collect();
        assert!(!scrap.is_empty(), "{}", map.name());
        let laid = |state: &GameState| {
            scrap
                .iter()
                .filter(|id| state.pickups.iter().any(|p| &p.id == *id))
                .count()
        };
        let mut state = GameState::with_map(map, false);
        assert_eq!(laid(&state), scrap.len());
        state.start_round();
        assert_eq!(laid(&state), scrap.len());
        for mode in modes {
            state.apply_config(MatchConfig {
                rules: RuleSet::new(mode, &[], false).unwrap(),
                ..MatchConfig::default()
            });
            assert_eq!(laid(&state), 0, "{} {mode:?}", map.name());
        }
        state.apply_config(MatchConfig::default());
        assert_eq!(laid(&state), scrap.len());
        // An armed free-for-all start has no use for them either.
        state.apply_config(MatchConfig {
            rules: RuleSet::new(GameMode::Ffa, &[Mutator::FullArsenal], false).unwrap(),
            ..MatchConfig::default()
        });
        assert_eq!(laid(&state), 0, "{} full arsenal", map.name());
    }
    assert!(MapKind::LowWater.scrap_pads().is_empty());
}

/// Walking metres from a spawn to the nearest weapon pad, by the same
/// navigation routes the bots follow to a pad.
fn walk_to_nearest_gun(map: MapKind, from: [f32; 3]) -> Option<f32> {
    let navigation = crate::maps::navigation(map);
    map.pickups()
        .iter()
        .chain(&map.scrap_pads())
        .filter(|pad| matches!(pad.kind, PickupKind::Weapon(_)))
        .filter_map(|pad| {
            let route = navigation.route(
                from,
                [pad.x, pad.floor, pad.z],
                crate::navigation::SEARCH_LIMIT,
            );
            (route.status == crate::navigation::RouteStatus::Complete).then(|| {
                route
                    .points
                    .windows(2)
                    .map(|pair| (pair[1][0] - pair[0][0]).hypot(pair[1][2] - pair[0][2]))
                    .sum::<f32>()
            })
        })
        .min_by(f32::total_cmp)
}

/// Every map that can host free-for-all has a stronger gun within a fair
/// walk of every spawn point. The bound is seconds at top speed.
#[test]
fn every_free_for_all_map_puts_a_gun_within_reach_of_every_spawn() {
    let mut report = Vec::new();
    for map in MapKind::ALL {
        let mut worst: f32 = 0.0;
        let mut total = 0.0;
        let samples = 16;
        for i in 0..samples {
            let angle = std::f32::consts::TAU * i as f32 / samples as f32;
            let (x, z, _, floor) = crate::sim::spawn_on_ring(map, angle);
            let walk = walk_to_nearest_gun(map, [x, floor, z])
                .unwrap_or_else(|| panic!("{}: no gun is reachable from spawn {i}", map.name()));
            worst = worst.max(walk);
            total += walk;
        }
        let seconds = worst / crate::movement::TOP_SPEED;
        report.push(format!(
            "{}: mean {:.1} s, worst {:.1} s",
            map.name(),
            total / samples as f32 / crate::movement::TOP_SPEED,
            seconds
        ));
        assert!(
            seconds <= max_walk_to_gun_seconds(map),
            "{}: a spawn is {seconds:.1} s from the nearest gun\n{}",
            map.name(),
            report.join("\n")
        );
    }
    println!("{}", report.join("\n"));
}

/// Seconds at top speed from any spawn to the nearest gun, by the size tiers
/// in `docs/plans/multiplayer-maps.md`: small maps 10 s, the medium hall
/// 12 s, the large maps 15 s.
fn max_walk_to_gun_seconds(map: MapKind) -> f32 {
    match map {
        MapKind::ReclamationGulch | MapKind::TripointWorks | MapKind::HoldfastAtoll => 15.0,
        MapKind::Sector9 => 12.0,
        _ => 10.0,
    }
}

/// Rule bots on the Pistol go and get a gun: every map, from a standing
/// start, with no human to chase.
#[test]
fn rule_bots_take_a_gun_from_the_floor_on_every_free_for_all_map() {
    let mut report = Vec::new();
    for map in MapKind::ALL {
        let mut session = crate::session::GameSession::with_map(map, false);
        session.state.seed(42);
        session.state.config = MatchConfig {
            warmup_ticks: 1,
            boss_spawn_ticks: None,
            compliance_ping_ticks: None,
            ..MatchConfig::default()
        };
        session.spawn_bots(4);
        assert!(session.state.sidearm_start());
        let bots: Vec<Uuid> = session.bots.iter().map(|bot| bot.player_id).collect();
        let mut first: std::collections::HashMap<Uuid, u64> = Default::default();
        for _ in 0..20 * 40 {
            for message in session.tick_messages(DT) {
                if let ServerMessage::Event(GameEvent::Pickup {
                    player_id, kind, ..
                }) = message
                {
                    if kind == "weapon" {
                        first.entry(player_id).or_insert(session.state.tick);
                    }
                }
            }
            if bots.iter().all(|id| first.contains_key(id)) {
                break;
            }
        }
        let mut seconds: Vec<f32> = first.values().map(|tick| *tick as f32 / 20.0).collect();
        seconds.sort_by(f32::total_cmp);
        report.push(format!(
            "{}: {} of {} bots armed, first-gun times {:?} s",
            map.name(),
            first.len(),
            bots.len(),
            seconds
        ));
        assert!(
            first.len() * 2 >= bots.len(),
            "{}: bots did not route to weapon pads\n{}",
            map.name(),
            report.join("\n")
        );
    }
    println!("{}", report.join("\n"));
}

/// The clock a joined agent learns from the wire (`PickupState::clock_ticks`)
/// is the clock the server runs (`ArenaPickup::clock`), for every pad kind in
/// free-for-all and team modes.
#[test]
fn the_wire_pad_clock_matches_the_server_clock() {
    let mut kinds: Vec<PickupKind> = WeaponType::ALL
        .into_iter()
        .map(PickupKind::Weapon)
        .collect();
    kinds.extend([
        PickupKind::Health,
        PickupKind::Armor,
        PickupKind::Grenade { count: 1 },
        PickupKind::ProximityMine { count: 1 },
        PickupKind::RemoteMine { count: 1 },
        PickupKind::Ammo {
            pool: AmmoPool::Bullets,
            rounds: 10,
        },
    ]);
    for rules in [
        RuleSet::default(),
        RuleSet::new(GameMode::Tdm, &[], false).unwrap(),
    ] {
        for kind in &kinds {
            let pad = crate::sim::ArenaPickup {
                claim: crate::protocol::SupplyClaim::Contested,
                id: "pad".into(),
                kind: *kind,
                amount: 25,
                x: 0.0,
                y: 0.4,
                z: 0.0,
                floor: 0.0,
                available: false,
                respawn_timer: Some(1),
                secret: false,
            };
            assert_eq!(
                pad.to_state().clock_ticks(rules.teams()),
                pad.clock(&rules),
                "{kind:?} under {:?}",
                rules.mode()
            );
        }
    }
}

#[test]
fn the_custody_plate_stacks_to_one_fifty_drains_back_and_keeps_its_clock_in_every_mode() {
    let mut state = ffa(MapKind::ArenaDuel);
    let id = join(&mut state, 1, Role::Human);
    let plate = crate::maps::larak_lot::PLATE_ID;
    state.players.iter_mut().find(|p| p.id == id).unwrap().armor = 70;
    stand_on(&mut state, id, plate);
    state.tick(DT);
    assert_eq!(fighter(&state, id).armor, crate::sim::PLATE_MAX_ARMOR);
    let events = state.take_events();
    assert!(events.iter().any(|e| matches!(e,
        GameEvent::Pickup { kind, amount, pickup_id, .. }
            if kind == "plate" && *amount == Some(80) && pickup_id == plate)));
    let pad = state.pickups.iter().find(|p| p.id == plate).unwrap();
    assert_eq!(pad.respawn_timer, Some(crate::rules::PLATE_RESPAWN_TICKS));
    assert_eq!(pad.to_state().kind, "plate");
    // The excess drains a point a second, back to the ordinary cap and no
    // further; an ordinary armour pad is no use to a plated fighter.
    park(&mut state, id);
    for _ in 0..20 * 10 {
        state.tick(DT);
    }
    let armor = fighter(&state, id).armor;
    assert!((139..=141).contains(&armor), "{armor}");
    for _ in 0..20 * 60 {
        state.tick(DT);
    }
    assert_eq!(fighter(&state, id).armor, crate::sim::PLAYER_MAX_ARMOR);
    stand_on(&mut state, id, "larak_armor_bridge");
    state.tick(DT);
    assert!(
        state
            .pickups
            .iter()
            .find(|p| p.id == "larak_armor_bridge")
            .unwrap()
            .available
    );
    // Team modes keep the heavy plate on the same 35 s.
    let tdm = RuleSet::new(GameMode::Tdm, &[], false).unwrap();
    let pad = state.pickups.iter().find(|p| p.id == plate).unwrap();
    assert_eq!(pad.clock(&tdm), crate::rules::PLATE_RESPAWN_TICKS);
}

#[test]
fn the_pit_rocket_is_found_in_free_for_all_and_never_eaten_by_an_arsenal() {
    let rocket = crate::maps::larak_lot::ROCKET_ID;
    let mut state = ffa(MapKind::ArenaDuel);
    let id = join(&mut state, 1, Role::Human);
    state.arm_joined_magazines(id);
    stand_on(&mut state, id, rocket);
    state.tick(DT);
    assert!(fighter(&state, id).inventory.owns(WeaponType::Rocket));
    assert_eq!(fighter(&state, id).weapon, WeaponType::Rocket);
    let pad = state.pickups.iter().find(|p| p.id == rocket).unwrap();
    assert_eq!(
        pad.respawn_timer,
        Some(crate::rules::FFA_POWER_WEAPON_RESPAWN_TICKS)
    );

    // Team deathmatch has no Rocket on the lot at all.
    let mut team = ffa(MapKind::ArenaDuel);
    team.apply_config(MatchConfig {
        rules: RuleSet::new(GameMode::Tdm, &[], false).unwrap(),
        ..MatchConfig::default()
    });
    assert!(team.pickups.iter().all(|p| p.id != rocket));

    // An arsenal bag never spends a pad for a gun it cannot hold.
    let arsenal = crate::inventory::Inventory::new(crate::protocol::EquipmentPolicy::FullArsenal);
    assert!(!arsenal.weapon_pad_useful(WeaponType::Rocket));
    assert!(!arsenal.weapon_pad_useful(WeaponType::Sniper));
    assert!(arsenal.weapon_pad_useful(WeaponType::Rail));
}
