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
    assert!(inventory.begin_reload(WeaponType::Tack, 5));
    let saved = inventory.saved_equipment(WeaponType::Tack).unwrap();
    assert!(saved.validate().is_ok());
    assert_eq!(saved.weapons.len(), 2);
    let mut restored = Inventory::new(EquipmentPolicy::Discovery);
    restored.restore_saved_equipment(&saved).unwrap();
    let state = view(&restored, saved.selected, 100);
    assert_eq!(state.weapons, saved.weapons);
    assert_eq!(state.reserves, saved.reserves);
    assert_eq!(state.personal_claims, saved.personal_claims);
    assert!(state.reload.is_none());
    assert_eq!(state.dry_fire_count, 0);
    assert_eq!(restored.revision(), 1);
    let mut invalid = saved.clone();
    invalid.weapons.push(invalid.weapons[1].clone());
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
        assert!(!inventory.begin_reload(weapon, 10));
    }
    assert_eq!(inventory.grant_ammo(AmmoPool::Darts, 30), 0);
    assert!(!inventory.needs_ammo(AmmoPool::Tacks));
    assert_eq!(inventory.revision(), 0);
    assert!(inventory
        .state(Uuid::nil(), WeaponType::Flechette, 10)
        .is_none());
}

#[test]
fn finite_magazines_reload_on_the_exact_tick_without_creating_rounds() {
    for weapon in WeaponType::ALL
        .into_iter()
        .filter(|weapon| *weapon != WeaponType::Fists)
    {
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        assert!(!inventory.owns(weapon));
        assert!(!inventory.select(WeaponType::Fists, weapon));
        assert!(!inventory.try_fire(weapon));
        assert!(!inventory.begin_reload(weapon, 1));
        assert!(inventory.grant_weapon(weapon));
        assert!(inventory.select(WeaponType::Fists, weapon));
        let pool = weapon.ammo_pool().unwrap();
        let initial = view(&inventory, weapon, 1);
        assert_eq!(
            initial.weapon(weapon).unwrap().magazine,
            Some(weapon.magazine_size())
        );
        assert_eq!(initial.reserve(pool), weapon.initial_reserve());
        assert!(!inventory.begin_reload(weapon, 1));
        for _ in 0..weapon.magazine_size() {
            assert!(inventory.try_fire(weapon));
        }
        assert!(!inventory.try_fire(weapon));
        assert_eq!(view(&inventory, weapon, 1).dry_fire_count, 1);
        assert!(!inventory.try_fire(weapon));
        assert_eq!(view(&inventory, weapon, 1).dry_fire_count, 1);
        inventory.tick(2, false);
        assert!(!inventory.try_fire(weapon));
        assert_eq!(view(&inventory, weapon, 2).dry_fire_count, 2);
        assert!(inventory.begin_reload(weapon, 10));
        assert!(!inventory.begin_reload(weapon, 11));
        let completes = 10 + weapon.reload_ticks();
        inventory.tick(completes - 1, true);
        let before = view(&inventory, weapon, completes - 1);
        assert_eq!(before.weapon(weapon).unwrap().magazine, Some(0));
        assert_eq!(before.reserve(pool), initial.reserve(pool));
        assert!(!inventory.try_fire(weapon));
        inventory.tick(completes, true);
        let after = view(&inventory, weapon, completes);
        assert!(after.reload.is_none());
        assert_eq!(
            after.weapon(weapon).unwrap().magazine,
            Some(weapon.magazine_size())
        );
        assert_eq!(
            after.reserve(pool) + weapon.magazine_size() * weapon.ammo_cost(),
            initial.reserve(pool)
        );
        assert!(inventory.try_fire(weapon));
    }
}

#[test]
fn interrupted_and_partial_reloads_share_pools_without_discarding_ammunition() {
    let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
    assert!(inventory.try_fire(WeaponType::Fists));
    assert!(!inventory.begin_reload(WeaponType::Fists, 1));
    assert!(!inventory.grant_weapon(WeaponType::Fists));
    inventory.grant_weapon(WeaponType::Flechette);
    inventory.grant_weapon(WeaponType::Scatter);
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 0).reserve(AmmoPool::Darts),
        120
    );
    assert!(!inventory.needs_ammo(AmmoPool::Darts));
    assert!(!inventory.grant_weapon(WeaponType::Flechette));
    assert_eq!(inventory.grant_ammo(AmmoPool::Darts, u16::MAX), 0);
    assert!(inventory.try_fire(WeaponType::Flechette));
    assert!(inventory.begin_reload(WeaponType::Flechette, 5));
    let revision = inventory.revision();
    assert!(!inventory.select(WeaponType::Flechette, WeaponType::Rail));
    assert_eq!(inventory.revision(), revision);
    assert!(inventory.select(WeaponType::Flechette, WeaponType::Scatter));
    inventory.tick(100, false);
    let after = view(&inventory, WeaponType::Scatter, 100);
    assert!(after.reload.is_none());
    assert_eq!(
        after.weapon(WeaponType::Flechette).unwrap().magazine,
        Some(29)
    );
    assert_eq!(after.reserve(AmmoPool::Darts), 120);
    assert!(inventory.try_fire(WeaponType::Scatter));
    assert!(inventory.begin_reload(WeaponType::Scatter, 101));
    inventory.tick(127, false);
    assert_eq!(
        view(&inventory, WeaponType::Scatter, 127).reserve(AmmoPool::Darts),
        116
    );

    // One reserve dart cannot load a Scatter shell; Flechette can still use it.
    inventory.reserves[AmmoPool::Darts.index()] = 1;
    assert!(inventory.try_fire(WeaponType::Scatter));
    assert!(!inventory.begin_reload(WeaponType::Scatter, 128));
    assert!(inventory.begin_reload(WeaponType::Flechette, 128));
    inventory.tick(150, false);
    assert_eq!(
        view(&inventory, WeaponType::Flechette, 150).reserve(AmmoPool::Darts),
        0
    );
    assert_eq!(inventory.grant_ammo(AmmoPool::Darts, u16::MAX), 120);
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
    bad.weapons.push(bad.weapons[0].clone());
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.weapons[0].magazine = Some(1);
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.weapons.push(WeaponAmmo {
        weapon: WeaponType::Tack,
        magazine: None,
    });
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.weapons.push(WeaponAmmo {
        weapon: WeaponType::Rail,
        magazine: Some(5),
    });
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.reserves.clear();
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.reserves[0] = bad.reserves[1].clone();
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.reserves[0].rounds = 221;
    invalids.push(bad);
    for id in ["", "../bay", "BAY", "two words"] {
        let mut bad = valid.clone();
        bad.personal_claims = vec![id.into()];
        invalids.push(bad);
    }
    let mut bad = valid.clone();
    bad.personal_claims.push("bay_tack".into());
    invalids.push(bad);
    let mut bad = valid.clone();
    bad.reload = Some(ReloadState {
        weapon: WeaponType::Fists,
        complete_at: 2,
    });
    invalids.push(bad);
    for bad in invalids {
        assert!(bad.validate().is_err(), "{bad:?}");
    }
    inventory.grant_weapon(WeaponType::Tack);
    inventory.try_fire(WeaponType::Tack);
    inventory.begin_reload(WeaponType::Tack, 10);
    let reloading = view(&inventory, WeaponType::Tack, 10);
    for completion in [9, 10, 29, u64::MAX] {
        let mut bad = reloading.clone();
        bad.reload.as_mut().unwrap().complete_at = completion;
        assert!(bad.validate().is_err());
    }
    let json =
        serde_json::to_string(&crate::protocol::ServerMessage::Loadout(reloading.clone())).unwrap();
    assert!(
        matches!(serde_json::from_str(&json).unwrap(), crate::protocol::ServerMessage::Loadout(state) if state == reloading)
    );
}
