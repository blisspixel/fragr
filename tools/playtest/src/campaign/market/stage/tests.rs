//! Isolated per-action attribution fixtures. Positions, health and strips are
//! calibration inputs, not earned market play.
use super::*;
use fragr_server::protocol::{LoadoutState, WeaponType};

fn loadout(weapons: &[WeaponType], bullets: u16, shells: u16) -> LoadoutState {
    let mut loadout: LoadoutState = serde_json::from_value(serde_json::json!({
        "player_id": Uuid::from_u128(1), "tick": 0, "selected": "fists",
        "weapons": ["fists"], "ammo": [
            {"pool": "bullets", "rounds": bullets}, {"pool": "shells", "rounds": shells},
            {"pool": "cells", "rounds": 0}, {"pool": "rockets", "rounds": 0}],
        "grenades": 0, "personal_claims": [], "dry_fire_count": 0
    }))
    .unwrap();
    loadout.weapons = weapons.to_vec();
    loadout
}

fn strip(owner: u128, origin: [f32; 3], working: bool) -> PaverStripState {
    PaverStripState {
        owner_id: Uuid::from_u128(owner),
        origin,
        yaw: 0.0,
        length: 10.0,
        half_width: 1.6,
        working,
        phase_started: 0,
        phase_ends: 40,
    }
}

fn status(feet: [f32; 3], hp: i32) -> Status {
    Status {
        feet,
        hp,
        armor: 0,
        loadout: loadout(&[WeaponType::Fists, WeaponType::Flechette], 7, 0),
    }
}

struct Step<'a> {
    tick: u64,
    feet: [f32; 3],
    hp: i32,
    recognized: Vec<u128>,
    before: &'a [PaverStripState],
    after: &'a [PaverStripState],
    to: [f32; 3],
    hp_after: i32,
    shots: Vec<(&'a str, i32)>,
}

fn run(tracker: &mut Tracker, facts: &mut Facts, step: Step<'_>) {
    let names = BTreeMap::from([
        (Uuid::from_u128(7), "market_paver_east".to_owned()),
        (Uuid::from_u128(8), "market_paver_west".to_owned()),
    ]);
    tracker.step(
        facts,
        &Decision {
            tick: step.tick,
            feet: step.feet,
            hp: step.hp,
            armor: 0,
            airborne: false,
            moving: true,
            telling: false,
            guard: Some(Guard::Pass),
            recognized: step.recognized.into_iter().map(Uuid::from_u128).collect(),
            strips: step.before,
            names: &names,
        },
        Outcome {
            strips: step.after,
            status: Some(status(step.to, step.hp_after)),
            shots: step
                .shots
                .into_iter()
                .map(|(name, damage)| (name.to_owned(), damage))
                .collect(),
        },
    );
}

#[test]
fn ranged_rounds_count_owned_pools_once_and_ignore_unusable_ammunition() {
    let flechette = loadout(&[WeaponType::Fists, WeaponType::Flechette], 7, 12);
    assert_eq!(ranged_rounds(&flechette), 7, "shells without a Scatter");
    let both = loadout(
        &[
            WeaponType::Fists,
            WeaponType::Flechette,
            WeaponType::Repeater,
        ],
        30,
        0,
    );
    assert_eq!(ranged_rounds(&both), 30, "one shared bullet pool");
    assert_eq!(ranged_rounds(&loadout(&[WeaponType::Fists], 50, 50)), 0);
}

#[test]
fn walking_into_a_working_strip_is_an_unrecognized_strip_hit_not_a_shot() {
    let mut tracker = Tracker::default();
    let mut facts = Facts::default();
    let east = [strip(7, [0.0, 0.0, 0.0], true)];
    // A first step outside: no contact.
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 10,
            feet: [5.0, 0.0, 3.0],
            hp: 50,
            recognized: vec![],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 2.5],
            hp_after: 50,
            shots: vec![],
        },
    );
    assert!(facts.contacts.is_empty());
    // The body steps in and is worked in the same step.
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 11,
            feet: [5.0, 0.0, 2.5],
            hp: 50,
            recognized: vec![],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 1.2],
            hp_after: 32,
            shots: vec![],
        },
    );
    assert_eq!(facts.contacts.len(), 1);
    let contact = &facts.contacts[0];
    assert_eq!(contact.arrival, Arrival::MovedIn);
    assert!(!contact.recognized);
    assert_eq!(contact.owner, "market_paver_east");
    assert_eq!(facts.strip_loss, 18);
    assert!(facts.shot_loss.is_empty());
    let hit = &facts.strip_hits[0];
    assert_eq!(hit.owners, ["market_paver_east"]);
    assert_eq!(hit.recognized, [false]);
    assert_eq!(hit.inside_since, Some(11));
    assert_eq!(hit.arrival, Some(Arrival::MovedIn));
    // Stepping out closes the contact without inventing another hit.
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 12,
            feet: [5.0, 0.0, 1.2],
            hp: 32,
            recognized: vec![7],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 2.0],
            hp_after: 32,
            shots: vec![],
        },
    );
    assert_eq!(facts.contacts[0].left_tick, Some(12));
    assert_eq!(facts.strip_hits.len(), 1);
    assert_eq!(facts.decision_steps, 3);
}

#[test]
fn overlapping_rectangles_name_every_owner_and_shots_stay_with_their_shooter() {
    let mut tracker = Tracker::default();
    let mut facts = Facts::default();
    let pair = [
        strip(7, [0.0, 0.0, 0.0], true),
        strip(8, [0.0, 0.0, 1.0], true),
    ];
    // Both strips are published under a standing body during this step.
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 20,
            feet: [4.0, 0.0, 0.5],
            hp: 100,
            recognized: vec![],
            before: &[],
            after: &[],
            to: [4.0, 0.0, 0.5],
            hp_after: 100,
            shots: vec![],
        },
    );
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 21,
            feet: [4.0, 0.0, 0.5],
            hp: 100,
            recognized: vec![8],
            before: &[],
            after: &pair,
            to: [4.0, 0.0, 0.5],
            hp_after: 39,
            shots: vec![("market_sweeper", 25)],
        },
    );
    assert_eq!(facts.contacts.len(), 2);
    assert!(facts
        .contacts
        .iter()
        .all(|c| c.arrival == Arrival::PlacedOnBody && c.other_strips == 1));
    assert_eq!(facts.shot_loss["market_sweeper"], 25);
    assert_eq!(facts.strip_loss, 36);
    let hit = &facts.strip_hits[0];
    assert_eq!(hit.owners, ["market_paver_east", "market_paver_west"]);
    assert_eq!(hit.recognized, [false, true]);
    assert_eq!(hit.shot_loss, 25);
    assert!(facts.death.is_none());
}

#[test]
fn loss_outside_strips_is_unattributed_and_the_fatal_step_names_its_cause() {
    let mut tracker = Tracker::default();
    let mut facts = Facts::default();
    let east = [strip(7, [0.0, 0.0, 0.0], false)];
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 30,
            feet: [5.0, 0.0, 4.0],
            hp: 40,
            recognized: vec![],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 4.0],
            hp_after: 30,
            shots: vec![],
        },
    );
    assert_eq!(facts.unattributed_loss, 10);
    assert_eq!(facts.strip_loss, 0);
    // A preparation does not damage; only a working strip is credited.
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 31,
            feet: [5.0, 0.0, 4.0],
            hp: 30,
            recognized: vec![],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 1.0],
            hp_after: 0,
            shots: vec![("market_heavy", 50)],
        },
    );
    let death = facts.death.as_ref().unwrap();
    assert_eq!(death.cause, "shot:market_heavy");
    assert_eq!(death.hp_before, 30);
    assert_eq!(death.ranged_rounds, 7);
    assert_eq!(facts.strip_loss, 0);
    // A later step cannot rewrite the first fatal record.
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 32,
            feet: [5.0, 0.0, 1.0],
            hp: 0,
            recognized: vec![],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 1.0],
            hp_after: 0,
            shots: vec![],
        },
    );
    assert_eq!(facts.death.as_ref().unwrap().tick, 31);
}

#[test]
fn a_work_pulse_on_the_fatal_step_is_a_strip_death() {
    let mut tracker = Tracker::default();
    let mut facts = Facts::default();
    let east = [strip(7, [0.0, 0.0, 0.0], true)];
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 40,
            feet: [5.0, 0.0, 0.0],
            hp: 7,
            recognized: vec![7],
            before: &east,
            after: &east,
            to: [5.0, 0.0, 0.2],
            hp_after: 0,
            shots: vec![],
        },
    );
    assert_eq!(facts.contacts[0].arrival, Arrival::AlreadyInside);
    assert_eq!(facts.death.as_ref().unwrap().cause, "strip");
    assert_eq!(facts.strip_hits[0].recognized, [true]);
}

#[test]
fn a_replaced_or_unfinished_stay_is_closed_and_owners_are_counted_once() {
    let mut tracker = Tracker::default();
    let mut facts = Facts::default();
    let first = [strip(7, [0.0, 0.0, 0.0], false)];
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 50,
            feet: [5.0, 0.0, 0.0],
            hp: 100,
            recognized: vec![],
            before: &first,
            after: &first,
            to: [5.0, 0.0, 0.0],
            hp_after: 100,
            shots: vec![],
        },
    );
    // The same owner marks a new strip while the body still stands on the
    // old one; unsorted repeated owners still count as two owners in all.
    let replaced = [
        strip(7, [0.5, 0.0, 0.0], false),
        strip(8, [0.0, 0.0, 9.0], false),
        strip(7, [0.5, 0.0, 0.0], false),
    ];
    run(
        &mut tracker,
        &mut facts,
        Step {
            tick: 51,
            feet: [5.0, 0.0, 0.0],
            hp: 100,
            recognized: vec![],
            before: &first,
            after: &replaced,
            to: [5.0, 0.0, 0.0],
            hp_after: 100,
            shots: vec![],
        },
    );
    assert_eq!(facts.contacts.len(), 2);
    assert_eq!(facts.contacts[0].left_tick, Some(51), "the old stay ended");
    assert_eq!(facts.contacts[1].left_tick, None);
    assert_eq!(facts.contacts[1].arrival, Arrival::PlacedOnBody);
    assert_eq!(facts.contacts[1].other_strips, 1);
    tracker.close(&mut facts, 60);
    assert_eq!(
        facts.contacts[1].left_tick,
        Some(60),
        "a boundary closes it"
    );
    tracker.close(&mut facts, 70);
    assert_eq!(facts.contacts[1].left_tick, Some(60));
}
