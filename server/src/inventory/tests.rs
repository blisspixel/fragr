use super::*;

fn view(inventory: &Inventory, selected: WeaponType, tick: u64) -> LoadoutState {
    let state = inventory.state(Uuid::nil(), selected, tick).unwrap();
    state.validate().unwrap();
    state
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
    assert_eq!(inventory.grant_ammo(AmmoPool::Cells, u16::MAX), 41);
    let full = view(&inventory, WeaponType::Rail, 4);
    for pool in AmmoPool::ALL {
        assert_eq!(full.ammo(pool), pool.capacity());
    }
    assert_eq!(
        AmmoPool::ALL.map(AmmoPool::capacity),
        [200, 50, 50],
        "Doom caps for bullets and shells; rail cells follow the rocket cap"
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
