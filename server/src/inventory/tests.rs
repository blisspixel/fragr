use super::*;
use crate::protocol::{Action, PickupState, Snapshot, SupplyClaim};

fn view(inventory: &Inventory, selected: WeaponType, tick: u64) -> LoadoutState {
    let state = inventory.state(Uuid::nil(), selected, tick).unwrap();
    state.validate().unwrap();
    state
}

#[test]
fn arc_keeps_one_cells_bag_with_rail_and_sniper_magazines_and_saved_entry() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(inventory.grant_weapon(WeaponType::Arc));
    assert_eq!(
        view(&inventory, WeaponType::Arc, 0).ammo(AmmoPool::Cells),
        40
    );
    assert!(inventory.grant_weapon(WeaponType::Rail));
    assert!(inventory.grant_weapon(WeaponType::Sniper));
    inventory.arm_magazines();
    let armed = view(&inventory, WeaponType::Arc, 1);
    assert_eq!(armed.ammo(AmmoPool::Cells), 58);
    assert_eq!(armed.shots(WeaponType::Arc), Some(12));
    assert_eq!(armed.shots(WeaponType::Rail), Some(4));
    assert_eq!(armed.shots(WeaponType::Sniper), Some(5));
    for gun in [WeaponType::Arc, WeaponType::Rail, WeaponType::Sniper] {
        assert!(inventory.try_fire(gun));
    }
    assert_eq!(
        view(&inventory, WeaponType::Arc, 2).ammo(AmmoPool::Cells),
        55
    );
    let saved = inventory.saved_equipment(WeaponType::Arc).unwrap();
    let entry = inventory.clone();
    for _ in 0..11 {
        assert!(inventory.try_fire(WeaponType::Arc));
    }
    assert!(!inventory.try_fire(WeaponType::Arc));
    let cells = view(&inventory, WeaponType::Arc, 3).ammo(AmmoPool::Cells);
    assert!(inventory.request_reload(WeaponType::Arc, 3));
    inventory.finish_reload(25);
    assert_eq!(
        view(&inventory, WeaponType::Arc, 25).ammo(AmmoPool::Cells),
        cells,
        "reload only moves already carried Cells"
    );
    let revision = inventory.revision();
    inventory.restore_entry(&entry);
    assert!(inventory.revision() > revision);
    assert_eq!(
        view(&inventory, WeaponType::Arc, 26).ammo(AmmoPool::Cells),
        55
    );
    assert_eq!(
        view(&inventory, WeaponType::Arc, 26).shots(WeaponType::Arc),
        Some(11)
    );
    let mut restored = Inventory::new(EquipmentPolicy::Discovery);
    restored.arm_magazines();
    restored.restore_saved_equipment(&saved).unwrap();
    assert_eq!(
        view(&restored, WeaponType::Arc, 27).ammo(AmmoPool::Cells),
        55
    );
    assert_eq!(restored.saved_equipment(WeaponType::Arc).unwrap(), saved);
}

#[test]
fn arc_duplicate_find_refills_finite_bag_without_refilling_partial_magazine() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.arm_magazines();
    assert!(inventory.grant_weapon(WeaponType::Arc));
    assert!(inventory.try_fire(WeaponType::Arc));
    assert_eq!(
        view(&inventory, WeaponType::Arc, 1).shots(WeaponType::Arc),
        Some(11)
    );
    assert!(inventory.grant_weapon(WeaponType::Arc));
    let duplicate = view(&inventory, WeaponType::Arc, 2);
    assert_eq!(duplicate.ammo(AmmoPool::Cells), 79);
    assert_eq!(duplicate.shots(WeaponType::Arc), Some(11));
    assert!(inventory.grant_weapon(WeaponType::Arc));
    assert_eq!(
        view(&inventory, WeaponType::Arc, 3).ammo(AmmoPool::Cells),
        100
    );
    assert!(!inventory.grant_weapon(WeaponType::Arc));
    assert_eq!(
        view(&inventory, WeaponType::Arc, 4).shots(WeaponType::Arc),
        Some(11)
    );
    assert!(inventory.request_reload(WeaponType::Arc, 4));
    inventory.finish_reload(26);
    let loaded = view(&inventory, WeaponType::Arc, 26);
    assert_eq!(loaded.ammo(AmmoPool::Cells), 100);
    assert_eq!(loaded.shots(WeaponType::Arc), Some(12));
}

#[test]
fn grenades_are_counted_separately_capped_and_restored_without_gun_changes() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(!inventory.try_throw());
    assert_eq!(inventory.grant_grenades(100), 6);
    assert_eq!(inventory.grant_grenades(1), 0);
    let saved = inventory.saved_equipment(WeaponType::Fists).unwrap();
    assert_eq!(saved.grenades, 6);
    assert!(inventory.try_throw());
    assert_eq!(inventory.grenades(), 5);
    assert_eq!(
        inventory
            .state(Uuid::nil(), WeaponType::Fists, 1)
            .unwrap()
            .weapons,
        [WeaponType::Fists]
    );
    inventory.restore_saved_equipment(&saved).unwrap();
    assert_eq!(inventory.grenades(), 6);
    let entry = inventory.clone();
    assert!(inventory.try_throw());
    let revision = inventory.revision();
    inventory.restore_entry(&entry);
    assert!(inventory.revision() > revision);
    assert_eq!(inventory.grenades(), 6);
    let mut bad = saved;
    bad.grenades = 7;
    assert!(bad.validate().is_err());
    let mut restricted = Inventory::restricted(WeaponType::Rail);
    assert_eq!(restricted.grant_grenades(6), 0);
    assert!(!restricted.try_throw());
}

#[test]
fn saved_equipment_restores_only_durable_discovery_state() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(inventory.grant_weapon(WeaponType::Tack));
    assert!(inventory.try_fire(WeaponType::Tack));
    inventory.record_claim("entry_supply".into());
    let saved = inventory.saved_equipment(WeaponType::Tack).unwrap();
    assert!(saved.validate().is_ok());
    assert_eq!(saved.weapons, vec![WeaponType::Fists, WeaponType::Tack]);
    let mut restored = Inventory::new(EquipmentPolicy::Discovery);
    restored.restore_saved_equipment(&saved).unwrap();
    let state = view(&restored, saved.selected, 100);
    assert_eq!(state.weapons, saved.weapons);
    assert_eq!(state.ammo, saved.ammo);
    assert_eq!(
        state.ammo(AmmoPool::Bullets),
        WeaponType::Tack.pickup_rounds() - 1
    );
    assert_eq!(state.personal_claims, saved.personal_claims);
    assert_eq!(state.dry_fire_count, 0);
    assert_eq!(restored.revision(), 1);
    let mut invalid = saved.clone();
    invalid.weapons.push(WeaponType::Tack);
    assert!(invalid.validate().is_err());
    assert!(restored.restore_saved_equipment(&invalid).is_err());
    assert_eq!(view(&restored, saved.selected, 100).weapons, saved.weapons);
    assert!(Inventory::new(EquipmentPolicy::FullArsenal)
        .restore_saved_equipment(&saved)
        .is_err());
}

#[test]
fn full_arsenal_retains_its_three_unlimited_guns_without_private_state() {
    let mut inventory = Inventory::new(EquipmentPolicy::FullArsenal);
    for weapon in WeaponType::ALL {
        let allowed = WeaponType::ARCADE.contains(&weapon);
        assert_eq!(inventory.owns(weapon), allowed);
        assert_eq!(inventory.select(WeaponType::Flechette, weapon), allowed);
        assert_eq!(inventory.grant_weapon(weapon), allowed);
        for _ in 0..500 {
            assert_eq!(inventory.try_fire(weapon), allowed);
        }
    }
    assert_eq!(inventory.grant_ammo(AmmoPool::Shells, 30), 0);
    assert!(!inventory.needs_ammo(AmmoPool::Bullets));
    assert_eq!(inventory.revision(), 0);
    assert!(inventory
        .state(Uuid::nil(), WeaponType::Flechette, 10)
        .is_none());
}

#[test]
fn every_shot_spends_one_unit_from_its_count_until_it_is_dry() {
    for weapon in WeaponType::ALL
        .into_iter()
        .filter(|weapon| weapon.ammo_pool().is_some())
    {
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        assert!(!inventory.owns(weapon));
        assert!(!inventory.select(WeaponType::Fists, weapon));
        assert!(!inventory.try_fire(weapon));
        assert!(inventory.grant_weapon(weapon));
        assert!(inventory.select(WeaponType::Fists, weapon));
        let pool = weapon.ammo_pool().unwrap();
        let initial = view(&inventory, weapon, 1);
        assert_eq!(initial.ammo(pool), weapon.pickup_rounds());
        assert_eq!(initial.shots(weapon), Some(weapon.pickup_rounds()));
        for spent in 1..=weapon.pickup_rounds() {
            assert!(inventory.try_fire(weapon));
            assert_eq!(
                view(&inventory, weapon, 1).ammo(pool),
                weapon.pickup_rounds() - spent
            );
        }
        // Dry: a held trigger counts one dry pull, a fresh pull counts again.
        assert!(!inventory.try_fire(weapon));
        assert_eq!(view(&inventory, weapon, 1).dry_fire_count, 1);
        assert!(!inventory.try_fire(weapon));
        assert_eq!(view(&inventory, weapon, 1).dry_fire_count, 1);
        inventory.tick(false);
        assert!(!inventory.try_fire(weapon));
        assert_eq!(view(&inventory, weapon, 2).dry_fire_count, 2);
        // Any pickup of that type makes the weapon live again at once.
        assert_eq!(inventory.grant_ammo(pool, 1), 1);
        assert!(inventory.try_fire(weapon));
        assert!(!inventory.try_fire(weapon));
        // Fists never need anything.
        assert!(inventory.try_fire(WeaponType::Fists));
    }
}

#[test]
fn rifle_and_pistol_share_bullets_while_shells_and_cells_stay_separate() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(inventory.try_fire(WeaponType::Fists));
    assert!(!inventory.grant_weapon(WeaponType::Fists));
    inventory.grant_weapon(WeaponType::Tack);
    inventory.grant_weapon(WeaponType::Flechette);
    inventory.grant_weapon(WeaponType::Scatter);
    inventory.grant_weapon(WeaponType::Rail);
    let state = view(&inventory, WeaponType::Scatter, 0);
    assert_eq!(state.ammo(AmmoPool::Bullets), 50 + 60);
    assert_eq!(state.ammo(AmmoPool::Shells), 12);
    assert_eq!(state.ammo(AmmoPool::Cells), 10);
    // A Scatter blast of seven pellets spends one shell, nothing else.
    assert!(inventory.try_fire(WeaponType::Scatter));
    let after = view(&inventory, WeaponType::Scatter, 1);
    assert_eq!(after.ammo(AmmoPool::Shells), 11);
    assert_eq!(after.ammo(AmmoPool::Bullets), 110);
    assert_eq!(after.ammo(AmmoPool::Cells), 10);
    // Rifle and pistol draw from the same bullets.
    assert!(inventory.try_fire(WeaponType::Flechette));
    assert!(inventory.try_fire(WeaponType::Tack));
    assert_eq!(
        view(&inventory, WeaponType::Tack, 2).ammo(AmmoPool::Bullets),
        108
    );
    assert!(inventory.try_fire(WeaponType::Rail));
    assert_eq!(
        view(&inventory, WeaponType::Rail, 3).ammo(AmmoPool::Cells),
        9
    );

    // Counts clamp at capacity and a full count is not worth a pickup.
    assert_eq!(inventory.grant_ammo(AmmoPool::Bullets, u16::MAX), 92);
    assert!(!inventory.needs_ammo(AmmoPool::Bullets));
    assert!(!inventory.grant_weapon(WeaponType::Flechette));
    assert_eq!(inventory.grant_ammo(AmmoPool::Shells, u16::MAX), 39);
    assert_eq!(inventory.grant_ammo(AmmoPool::Cells, u16::MAX), 91);
    let full = view(&inventory, WeaponType::Rail, 4);
    for pool in AmmoPool::ALL {
        assert_eq!(full.ammo(pool), pool.capacity());
    }
    assert_eq!(
        AmmoPool::ALL.map(AmmoPool::capacity),
        [200, 50, 100],
        "Doom caps for bullets and shells; one hundred rail cells since 2026-09-25"
    );
    // A known weapon picked up again tops its count up.
    inventory.ammo[AmmoPool::Shells.index()] = 45;
    assert!(inventory.grant_weapon(WeaponType::Scatter));
    assert_eq!(
        view(&inventory, WeaponType::Scatter, 5).ammo(AmmoPool::Shells),
        50
    );
    let revision = inventory.revision();
    assert!(inventory.select(WeaponType::Scatter, WeaponType::Rail));
    assert_eq!(inventory.revision(), revision, "selection is not equipment");
}

#[test]
fn private_claims_are_stable_and_invalid_wire_equipment_is_rejected() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.record_claim("bay_tack".into());
    let revision = inventory.revision();
    inventory.record_claim("bay_tack".into());
    assert_eq!(inventory.revision(), revision);
    assert!(inventory.claimed("bay_tack"));
    let valid = view(&inventory, WeaponType::Fists, 1);
    let mut invalids = Vec::new();
    let mut bad = valid.clone();
    bad.selected = WeaponType::Tack;
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.weapons.clear();
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.weapons.push(bad.weapons[0]);
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.weapons = vec![WeaponType::Tack];
    bad.selected = WeaponType::Tack;
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.ammo.clear();
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.ammo[0] = bad.ammo[1].clone();
    invalids.push(bad);
    for pool in AmmoPool::ALL {
        let mut bad = valid.clone();
        bad.ammo[pool.index()].rounds = pool.capacity() + 1;
        invalids.push(bad);
    }
    for id in ["", "../bay", "BAY", "two words"] {
        let mut bad = valid.clone();
        bad.personal_claims = vec![id.into()];
        invalids.push(bad);
    }
    let mut bad = valid.clone();
    bad.personal_claims.push("bay_tack".into());
    invalids.push(bad);
    for bad in invalids {
        assert!(bad.validate().is_err(), "{bad:?}");
    }
    inventory.grant_weapon(WeaponType::Tack);
    inventory.try_fire(WeaponType::Tack);
    let armed = view(&inventory, WeaponType::Tack, 10);
    let json =
        serde_json::to_string(&crate::protocol::ServerMessage::Loadout(armed.clone())).unwrap();
    assert!(
        matches!(serde_json::from_str(&json).unwrap(), crate::protocol::ServerMessage::Loadout(state) if state == armed)
    );
    // The magazine-era shape is refused, never half read.
    let mut legacy = serde_json::to_value(&armed).unwrap();
    legacy["reload"] = serde_json::Value::Null;
    assert!(serde_json::from_value::<LoadoutState>(legacy).is_err());
    let legacy = serde_json::json!({
        "player_id": Uuid::nil(), "tick": 1, "selected": "tack",
        "weapons": [{"weapon": "fists", "magazine": null}, {"weapon": "tack", "magazine": 12}],
        "reserves": [{"pool": "tacks", "rounds": 36}], "reload": null,
        "personal_claims": [], "dry_fire_count": 0
    });
    assert!(serde_json::from_value::<LoadoutState>(legacy).is_err());
}

#[test]
fn the_shiv_is_owned_once_without_ammunition_and_survives_the_saved_entry() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(!inventory.owns(WeaponType::Shiv));
    assert!(!inventory.try_fire(WeaponType::Shiv));
    assert!(!inventory.select(WeaponType::Fists, WeaponType::Shiv));
    assert!(inventory.grant_weapon(WeaponType::Shiv));
    let revision = inventory.revision();
    assert!(
        !inventory.grant_weapon(WeaponType::Shiv),
        "a second Shiv adds nothing"
    );
    assert_eq!(inventory.revision(), revision);
    assert!(inventory.select(WeaponType::Fists, WeaponType::Shiv));
    for _ in 0..500 {
        assert!(inventory.try_fire(WeaponType::Shiv));
    }
    let state = view(&inventory, WeaponType::Shiv, 3);
    assert_eq!(state.weapons, vec![WeaponType::Fists, WeaponType::Shiv]);
    assert_eq!(state.shots(WeaponType::Shiv), None);
    assert!(AmmoPool::ALL.into_iter().all(|pool| state.ammo(pool) == 0));
    assert_eq!(state.dry_fire_count, 0);
    assert_eq!(
        inventory.revision(),
        revision,
        "cutting changes no equipment"
    );
    let json = serde_json::to_value(&state).unwrap();
    assert_eq!(json["weapons"], serde_json::json!(["fists", "shiv"]));
    assert_eq!(json["selected"], "shiv");

    let saved = inventory.saved_equipment(WeaponType::Shiv).unwrap();
    let text = serde_json::to_string(&saved).unwrap();
    let read: SavedEquipment = serde_json::from_str(&text).unwrap();
    let mut restored = Inventory::new(EquipmentPolicy::Discovery);
    restored.restore_saved_equipment(&read).unwrap();
    assert!(restored.owns(WeaponType::Shiv));
    assert_eq!(view(&restored, read.selected, 4).weapons, state.weapons);

    let mut arcade = Inventory::new(EquipmentPolicy::FullArsenal);
    assert!(!arcade.grant_weapon(WeaponType::Shiv));
    assert!(!arcade.owns(WeaponType::Shiv));
}

#[test]
fn a_weapon_only_arsenal_holds_one_weapon_with_unlimited_ammunition() {
    for only in [WeaponType::Rail, WeaponType::Scatter, WeaponType::Fists] {
        let mut inventory = Inventory::restricted(only);
        assert_eq!(inventory.only(), Some(only));
        for weapon in WeaponType::ALL {
            assert_eq!(
                inventory.owns(weapon),
                weapon == only,
                "{only:?} {weapon:?}"
            );
            assert_eq!(inventory.select(only, weapon), weapon == only);
        }
        for _ in 0..500 {
            assert!(inventory.try_fire(only));
        }
        assert!(!inventory.try_fire(WeaponType::Flechette));
        assert!(!inventory.grant_weapon(WeaponType::Flechette));
        assert_eq!(inventory.grant_ammo(AmmoPool::Cells, 10), 0);
        assert!(inventory.state(Uuid::nil(), only, 1).is_none());
    }
}

#[test]
fn the_cells_cap_is_one_hundred_rail_shots() {
    assert_eq!(AmmoPool::Cells.capacity(), 100);
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    for _ in 0..12 {
        inventory.grant_weapon(WeaponType::Rail);
    }
    assert_eq!(
        view(&inventory, WeaponType::Rail, 1).ammo(AmmoPool::Cells),
        100
    );
    assert!(!inventory.grant_weapon(WeaponType::Rail));
}

#[test]
fn proximity_mines_have_their_own_capped_count_and_wire_field() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(!inventory.try_place_mine());
    assert_eq!(view(&inventory, WeaponType::Fists, 0).proximity_mines, 0);
    let quiet = serde_json::to_value(view(&inventory, WeaponType::Fists, 0)).unwrap();
    assert!(quiet.get("proximity_mines").is_none(), "omitted while zero");
    assert_eq!(inventory.grant_mines(100), crate::protocol::MINE_CARRY_CAP);
    assert_eq!(inventory.grant_mines(1), 0);
    assert_eq!(inventory.grenades(), 0, "grenades stay separate");
    let state = view(&inventory, WeaponType::Fists, 1);
    assert_eq!(state.proximity_mines, 4);
    let json = serde_json::to_value(&state).unwrap();
    assert_eq!(json["proximity_mines"], 4);
    let mut bad = state.clone();
    bad.proximity_mines = 5;
    assert!(bad.validate().is_err());
    assert!(serde_json::from_value::<LoadoutState>(json).unwrap() == state);
    let entry = inventory.clone();
    assert!(inventory.try_place_mine());
    assert_eq!(inventory.mines(), 3);
    inventory.restore_entry(&entry);
    assert_eq!(inventory.mines(), 4);
    let saved = inventory.saved_equipment(WeaponType::Fists).unwrap();
    assert_eq!(saved.proximity_mines, 4);
    assert!(inventory.try_place_mine());
    inventory.restore_saved_equipment(&saved).unwrap();
    assert_eq!(inventory.mines(), 4);
    let mut malformed = saved.clone();
    malformed.proximity_mines = 5;
    assert!(inventory.restore_saved_equipment(&malformed).is_err());
    assert_eq!(
        inventory.mines(),
        4,
        "invalid disk restore does not mutate inventory"
    );
    malformed.proximity_mines = 3;
    malformed.grenades = 6;
    inventory.restore_saved_equipment(&malformed).unwrap();
    assert_eq!((inventory.mines(), inventory.grenades()), (3, 6));
    let encoded = serde_json::to_value(&malformed).unwrap();
    assert_eq!(encoded["proximity_mines"], 3);
    let read: SavedEquipment = serde_json::from_value(encoded).unwrap();
    assert_eq!(read, malformed);
    let mut restricted = Inventory::restricted(WeaponType::Rail);
    assert_eq!(restricted.grant_mines(4), 0);
    assert!(!restricted.try_place_mine());
}

#[test]
fn human_magazines_share_one_pool_and_reload_moves_rounds_without_adding_any() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(!inventory.armed());
    inventory.grant_weapon(WeaponType::Tack);
    assert_eq!(inventory.ammo[AmmoPool::Bullets.index()], 50);
    assert!(inventory.try_fire(WeaponType::Tack));
    assert_eq!(inventory.ammo[AmmoPool::Bullets.index()], 49);
    inventory.arm_magazines();
    let state = view(&inventory, WeaponType::Tack, 1);
    assert_eq!(state.ammo(AmmoPool::Bullets), 49);
    assert_eq!(state.shots(WeaponType::Tack), Some(12));
    assert!(state
        .loaded
        .iter()
        .any(|magazine| magazine.weapon == WeaponType::Tack && magazine.rounds == 12));
    let quiet = serde_json::to_value(view(
        &Inventory::new(EquipmentPolicy::Discovery),
        WeaponType::Fists,
        0,
    ))
    .unwrap();
    assert!(quiet.get("loaded").is_none());

    inventory.grant_weapon(WeaponType::Flechette);
    let shared = view(&inventory, WeaponType::Flechette, 2);
    assert_eq!(shared.ammo(AmmoPool::Bullets), 109);
    assert_eq!(shared.shots(WeaponType::Tack), Some(12));
    assert_eq!(shared.shots(WeaponType::Flechette), Some(20));
    let reserve = 109 - 12 - 20;
    assert_eq!(reserve, 77);

    for _ in 0..12 {
        assert!(inventory.try_fire(WeaponType::Tack));
    }
    assert!(!inventory.try_fire(WeaponType::Tack));
    assert_eq!(
        view(&inventory, WeaponType::Tack, 3).ammo(AmmoPool::Bullets),
        97
    );
    assert_eq!(
        view(&inventory, WeaponType::Tack, 3).shots(WeaponType::Tack),
        Some(0)
    );
    assert!(!inventory.request_reload(WeaponType::Fists, 4));
    assert!(inventory.request_reload(WeaponType::Tack, 10));
    assert!(inventory.reloading());
    assert!(!inventory.try_fire(WeaponType::Tack));
    inventory.finish_reload(31);
    assert!(!inventory.reloading());
    let reloaded = view(&inventory, WeaponType::Tack, 32);
    assert_eq!(reloaded.shots(WeaponType::Tack), Some(12));
    assert_eq!(reloaded.ammo(AmmoPool::Bullets), 97);
    assert_eq!(reloaded.shots(WeaponType::Flechette), Some(20));

    let saved = inventory.saved_equipment(WeaponType::Tack).unwrap();
    let text = serde_json::to_value(&saved).unwrap();
    assert!(text.get("loaded").is_none());
    let mut restored = Inventory::new(EquipmentPolicy::Discovery);
    restored.arm_magazines();
    restored.restore_saved_equipment(&saved).unwrap();
    let again = view(&restored, WeaponType::Tack, 4);
    assert_eq!(again.ammo(AmmoPool::Bullets), 97);
    assert_eq!(again.shots(WeaponType::Tack), Some(12));
    assert_eq!(again.shots(WeaponType::Flechette), Some(20));
}

#[test]
fn an_arcade_human_spends_a_finite_bag_and_reloads_from_what_is_left() {
    let mut inventory = Inventory::new(EquipmentPolicy::FullArsenal);
    assert!(inventory
        .state(Uuid::nil(), WeaponType::Flechette, 1)
        .is_none());
    assert_eq!(inventory.grant_ammo(AmmoPool::Bullets, 10), 0);
    inventory.arm_magazines();
    let state = view(&inventory, WeaponType::Flechette, 1);
    assert!(!state.weapons.contains(&WeaponType::Fists));
    assert_eq!(state.shots(WeaponType::Flechette), Some(20));
    assert_eq!(state.shots(WeaponType::Scatter), Some(6));
    assert_eq!(state.shots(WeaponType::Rail), Some(4));
    assert_eq!(state.ammo(AmmoPool::Bullets), 80);
    assert_eq!(state.ammo(AmmoPool::Shells), 24);
    assert_eq!(state.ammo(AmmoPool::Cells), 16);
    assert!(AmmoPool::ALL
        .into_iter()
        .all(|pool| pool.arcade_spawn() <= pool.capacity()));

    assert!(inventory.try_fire(WeaponType::Flechette));
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 2).ammo(AmmoPool::Bullets),
        79
    );
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 2).shots(WeaponType::Flechette),
        Some(19)
    );
    for _ in 0..19 {
        assert!(inventory.try_fire(WeaponType::Flechette));
    }
    assert!(!inventory.try_fire(WeaponType::Flechette));
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 3).ammo(AmmoPool::Bullets),
        60
    );
    assert!(inventory.request_reload(WeaponType::Flechette, 5));
    inventory.finish_reload(5 + u64::from(WeaponType::Flechette.reload_ticks().unwrap()));
    let reloaded = view(&inventory, WeaponType::Flechette, 6);
    assert_eq!(reloaded.shots(WeaponType::Flechette), Some(20));
    assert_eq!(
        reloaded.ammo(AmmoPool::Bullets),
        60,
        "a reload moves rounds"
    );

    for _ in 0..3 {
        for _ in 0..20 {
            assert!(inventory.try_fire(WeaponType::Flechette));
        }
        if view(&inventory, WeaponType::Flechette, 7).ammo(AmmoPool::Bullets) > 0 {
            assert!(inventory.request_reload(WeaponType::Flechette, 8));
            inventory.finish_reload(8 + u64::from(WeaponType::Flechette.reload_ticks().unwrap()));
        }
    }
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 9).ammo(AmmoPool::Bullets),
        0
    );
    assert!(!inventory.request_reload(WeaponType::Flechette, 10));
    assert!(!inventory.try_fire(WeaponType::Flechette));
    assert_eq!(
        view(&inventory, WeaponType::Scatter, 9).shots(WeaponType::Scatter),
        Some(6)
    );
    assert_eq!(
        view(&inventory, WeaponType::Rail, 9).ammo(AmmoPool::Cells),
        16
    );
    inventory.arm_magazines();
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 10).ammo(AmmoPool::Bullets),
        0,
        "a second arm leaves the spent bag alone"
    );

    inventory.refill_if_armed();
    let spawned = view(&inventory, WeaponType::Flechette, 11);
    assert_eq!(spawned.ammo(AmmoPool::Bullets), 80);
    assert_eq!(spawned.ammo(AmmoPool::Shells), 24);
    assert_eq!(spawned.ammo(AmmoPool::Cells), 16);
    assert_eq!(spawned.shots(WeaponType::Flechette), Some(20));
    assert_eq!(spawned.shots(WeaponType::Rail), Some(4));

    assert!(inventory.grant_weapon(WeaponType::Flechette));
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 12).ammo(AmmoPool::Bullets),
        140
    );
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 12).shots(WeaponType::Flechette),
        Some(20),
        "a weapon pad adds to the bag and leaves the magazine alone"
    );
    assert!(inventory.grant_weapon(WeaponType::Flechette));
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 13).ammo(AmmoPool::Bullets),
        200
    );
    assert!(!inventory.grant_weapon(WeaponType::Flechette));
    assert_eq!(
        view(&inventory, WeaponType::Scatter, 13).ammo(AmmoPool::Shells),
        24
    );

    assert!(inventory.grant_weapon(WeaponType::Rail));
    assert_eq!(
        view(&inventory, WeaponType::Rail, 14).ammo(AmmoPool::Cells),
        26
    );
    for cycle in 0..6 {
        for _ in 0..4 {
            assert!(inventory.try_fire(WeaponType::Rail));
        }
        assert!(inventory.request_reload(WeaponType::Rail, 20 + cycle));
        inventory.finish_reload(20 + cycle + u64::from(WeaponType::Rail.reload_ticks().unwrap()));
    }
    let tail = view(&inventory, WeaponType::Rail, 30);
    assert_eq!(tail.ammo(AmmoPool::Cells), 2);
    assert_eq!(tail.shots(WeaponType::Rail), Some(2));
    assert!(!inventory.request_reload(WeaponType::Rail, 40));
    assert!(inventory.try_fire(WeaponType::Rail));
    assert!(inventory.try_fire(WeaponType::Rail));
    assert!(!inventory.try_fire(WeaponType::Rail));

    let mut over = spawned;
    over.ammo
        .iter_mut()
        .find(|count| count.pool == AmmoPool::Bullets)
        .unwrap()
        .rounds = 10;
    assert!(over.validate().is_err(), "magazines cannot outrun the bag");
    over.ammo
        .iter_mut()
        .find(|count| count.pool == AmmoPool::Bullets)
        .unwrap()
        .rounds = 201;
    assert!(
        over.validate().is_err(),
        "the bag stays inside the pool cap"
    );
}

#[test]
fn an_armed_weapon_only_arsenal_reloads_without_a_finite_bag() {
    let mut inventory = Inventory::restricted(WeaponType::Rail);
    inventory.arm_magazines();
    let state = view(&inventory, WeaponType::Rail, 1);
    assert!(state.ammo.iter().all(|count| count.rounds == 0));
    assert_eq!(state.shots(WeaponType::Rail), Some(4));
    for _ in 0..4 {
        assert!(inventory.try_fire(WeaponType::Rail));
    }
    assert!(!inventory.try_fire(WeaponType::Rail));
    assert_eq!(
        view(&inventory, WeaponType::Rail, 2).ammo(AmmoPool::Cells),
        0
    );
    assert!(inventory.request_reload(WeaponType::Rail, 3));
    inventory.finish_reload(3 + u64::from(WeaponType::Rail.reload_ticks().unwrap()));
    assert_eq!(
        view(&inventory, WeaponType::Rail, 4).shots(WeaponType::Rail),
        Some(4)
    );
    assert!(inventory.grant_weapon(WeaponType::Rail));
    assert_eq!(inventory.grant_ammo(AmmoPool::Cells, 10), 0);
    assert!(view(&inventory, WeaponType::Rail, 5)
        .ammo
        .iter()
        .all(|count| count.rounds == 0));
    inventory.refill_if_armed();
    assert_eq!(
        view(&inventory, WeaponType::Rail, 6).shots(WeaponType::Rail),
        Some(4)
    );
}

#[test]
fn a_reload_press_blocks_fire_until_the_magazine_is_full_again() {
    use crate::protocol::{Action, Role};
    use crate::sim::{GameState, RoundState};
    let mut state = GameState::new();
    state.round_state = RoundState::Active;
    let id = Uuid::new_v4();
    state.add_player(id, "Proxy".into(), Role::Human);
    assert!(!state.players[0].inventory.armed());
    state.arm_joined_magazines(id);
    let weapon = state.players[0].weapon;
    let size = weapon.magazine_size().unwrap();
    let ticks = weapon.reload_ticks().unwrap();
    for _ in 0..size {
        assert!(state.players[0].inventory.try_fire(weapon));
    }
    assert!(!state.players[0].inventory.try_fire(weapon));
    state.set_action(
        id,
        Action {
            reload: true,
            ..Default::default()
        },
    );
    state.tick(0.05);
    assert!(state.players[0].inventory.reloading());
    assert!(!state.players[0].inventory.try_fire(weapon));
    for _ in 0..ticks {
        state.tick(0.05);
    }
    assert!(!state.players[0].inventory.reloading());
    assert!(state.players[0].inventory.try_fire(weapon));
    assert_eq!(
        state.players[0]
            .inventory
            .state(id, weapon, state.tick)
            .unwrap()
            .shots(weapon),
        Some(size - 1)
    );
}

#[test]
fn remote_stock_is_finite_independent_and_restores_without_gun_or_other_device_changes() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    inventory.grant_weapon(WeaponType::Tack);
    inventory.grant_grenades(3);
    inventory.grant_mines(2);
    let initial = view(&inventory, WeaponType::Tack, 0);
    assert!(!inventory.try_place_remote_mine());
    assert!(serde_json::to_value(&initial)
        .unwrap()
        .get("remote_mines")
        .is_none());
    assert_eq!(inventory.grant_remote_mines(u16::MAX), 6);
    let full_revision = inventory.revision();
    assert_eq!(inventory.grant_remote_mines(1), 0);
    assert_eq!(inventory.revision(), full_revision);
    let entry = inventory.clone();
    let saved = inventory.saved_equipment(WeaponType::Tack).unwrap();
    let saved_value = serde_json::to_value(&saved).unwrap();
    assert_eq!(saved_value["remote_mines"], 6);
    assert_eq!(
        serde_json::from_value::<SavedEquipment>(saved_value).unwrap(),
        saved
    );
    for count in (0..6).rev() {
        assert!(inventory.try_place_remote_mine());
        let current = view(&inventory, WeaponType::Tack, 1);
        assert_eq!(current.remote_mines, count);
        assert_eq!(current.weapons, initial.weapons);
        assert_eq!(current.ammo, initial.ammo);
        assert_eq!((current.grenades, current.proximity_mines), (3, 2));
    }
    let empty_revision = inventory.revision();
    assert!(!inventory.try_place_remote_mine());
    assert_eq!(inventory.revision(), empty_revision);
    inventory.restore_entry(&entry);
    assert_eq!(inventory.remote_mines(), 6);
    assert!(inventory.revision() > empty_revision);
    inventory.try_place_remote_mine();
    inventory.restore_saved_equipment(&saved).unwrap();
    assert_eq!(inventory.remote_mines(), 6);
    let mut invalid = saved;
    invalid.remote_mines = 7;
    let before = view(&inventory, WeaponType::Tack, 2);
    let revision = inventory.revision();
    assert!(inventory.restore_saved_equipment(&invalid).is_err());
    assert_eq!(view(&inventory, WeaponType::Tack, 2), before);
    assert_eq!(inventory.revision(), revision);
    let mut only = Inventory::restricted(WeaponType::Rail);
    assert_eq!(only.grant_remote_mines(6), 0);
    assert!(!only.try_place_remote_mine());
    assert_eq!(only.remote_mines(), 0);
    // Full-arsenal gun ammunition is unlimited; placed devices still consume
    // their independent actual stock rather than inheriting that gun policy.
    let mut arcade = Inventory::new(EquipmentPolicy::FullArsenal);
    assert_eq!(arcade.grant_remote_mines(2), 2);
    assert!(arcade.try_place_remote_mine());
    assert!(arcade.try_place_remote_mine());
    assert!(!arcade.try_place_remote_mine());
}

#[test]
fn remote_stock_boundary_refuses_malformed_counts_and_omits_current_zero() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    let quiet = inventory.saved_equipment(WeaponType::Fists).unwrap();
    let value = serde_json::to_value(&quiet).unwrap();
    assert!(value.get("remote_mines").is_none());
    assert_eq!(
        serde_json::from_value::<SavedEquipment>(value.clone())
            .unwrap()
            .remote_mines,
        0
    );
    for bad in [
        serde_json::json!(-1),
        serde_json::json!(1.5),
        serde_json::json!("2"),
        serde_json::Value::Null,
    ] {
        let mut malformed = value.clone();
        malformed["remote_mines"] = bad;
        assert!(serde_json::from_value::<SavedEquipment>(malformed).is_err());
    }
    inventory.grant_remote_mines(6);
    let mut loadout = view(&inventory, WeaponType::Fists, 0);
    loadout.remote_mines = 7;
    assert!(loadout.validate().is_err());
}

#[test]
fn useful_supply_recognizes_grenades_and_mines() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    let id = Uuid::new_v4();
    let loadout = view(&inventory, WeaponType::Fists, 0);
    let snapshot = Snapshot {
        tick: 0,
        players: vec![crate::protocol::PlayerState {
            id,
            name: "Seeker".into(),
            x: 0.0,
            y: 0.0,
            z: 0.0,
            yaw: 0.0,
            pitch: 0.0,
            hp: 100,
            armor: 0,
            just_fired: false,
            behavior: None,
            score: 0,
            deaths: 0,
            attacks: 0,
            connects: 0,
            heads: 0,
            damage: 0,
            weapon: "fists".into(),
            team: None,
            lives: None,
            golden: false,
            ducking: false,
            body: None,
            collidable: true,
            campaign: None,
        }],
        round_state: Some("Active".into()),
        round_time_left: None,
        frag_limit: None,
        shot_results: vec![],
        projectiles: vec![],
        grenades: vec![],
        assessor_canisters: vec![],
        mines: vec![],
        remote_mines: vec![],
        auditors: vec![],
        explosions: vec![],
        mode_name: "FFA".into(),
        playlist: "Standard".into(),
        pressure: None,
        host_line: "".into(),
        mvp: None,
        mvp_frags: None,
        pickups: vec![PickupState {
            id: "grenade_1".into(),
            kind: "grenade".into(),
            weapon: "".into(),
            amount: Some(2),
            pool: None,
            x: 5.0,
            y: 0.0,
            z: 0.0,
            available: true,
            respawn_in: None,
            claim: SupplyClaim::Contested,
        }],
        map_id: 1,
        map_name: "Arena Duel".into(),
        episode_id: None,
        episode_title: None,
        episode_objective: None,
        episode_progress: None,
        episode_phase: None,
        jammer_dish: None,
        team_scores: None,
        flags: None,
        capture_scores: None,
        capture_limit: None,
        sabotage: None,
        conquest: None,
        vehicles: vec![],
    };
    let action = control_action(id, &snapshot, Some(&loadout), Action::default());
    assert!(action.forward);
    assert_eq!(action.look_at.unwrap().x, Some(5.0));

    // When grenades are full, bot does not steer towards grenade pickup.
    inventory.grant_grenades(6);
    let full_loadout = view(&inventory, WeaponType::Fists, 0);
    let action_full = control_action(id, &snapshot, Some(&full_loadout), Action::default());
    assert!(!action_full.forward);
    assert!(action_full.look_at.is_none());
}
