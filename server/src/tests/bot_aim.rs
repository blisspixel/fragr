//! Rule bots aim by body zone (wave 23): centre mass is the middle of the
//! torso band, the head is the middle of the head band, and a rung goes for
//! the head on its own share of sightings, only where its gun's cone fits.
use crate::combat::{band_for, head_centre, torso_centre, Band};
use crate::protocol::WeaponType;
use crate::sim::bot_senses::{aim_zone, AimZone};
use crate::sim::BotSkill;
use uuid::Uuid;

const EYE: [f32; 3] = [0.0, 1.6, 0.0];

/// Share of sightings this rung aims at the head with this gun at this range.
fn head_share(skill: BotSkill, weapon: WeaponType, distance: f32) -> f64 {
    let profile = skill.profile();
    let head = head_centre([distance, 0.0, 0.0], None, false);
    let mut heads = 0;
    let mut draws = 0;
    for bot in 1..=20u128 {
        for target in 100..120u128 {
            for sighting in [3u64, 47, 210, 999, 4_001] {
                draws += 1;
                let zone = aim_zone(
                    &profile,
                    Uuid::from_u128(bot),
                    Uuid::from_u128(target),
                    sighting,
                    EYE,
                    head,
                    weapon,
                );
                heads += u32::from(zone == AimZone::Head);
            }
        }
    }
    f64::from(heads) / f64::from(draws)
}

#[test]
fn centre_mass_and_head_points_sit_inside_their_own_bands_in_both_stances() {
    for floor in [0.0, 3.5] {
        for ducking in [false, true] {
            let feet = [3.0, floor, 4.0];
            let centre = torso_centre(feet, None, ducking);
            let head = head_centre(feet, None, ducking);
            assert_eq!((centre[0], centre[2]), (3.0, 4.0));
            assert_eq!(band_for(floor, centre[1], None, ducking), Some(Band::Torso));
            assert_eq!(band_for(floor, head[1], None, ducking), Some(Band::Head));
            // A gun's cone strays about as far before it leaves the torso
            // upward as downward: neither gate is within 0.25 m.
            for edge in [-0.25, 0.25] {
                assert_eq!(
                    band_for(floor, centre[1] + edge, None, ducking),
                    Some(Band::Torso),
                    "{ducking} {edge}"
                );
            }
            assert_eq!(
                band_for(floor, head[1] + 0.12, None, ducking),
                Some(Band::Head)
            );
            assert_eq!(
                band_for(floor, head[1] - 0.12, None, ducking),
                Some(Band::Head)
            );
        }
    }
}

#[test]
fn each_rung_goes_for_the_head_at_its_own_share_and_the_tourist_never_does() {
    let mut last = -1.0;
    for skill in BotSkill::ALL {
        let share = head_share(skill, WeaponType::Rail, 20.0);
        let want = f64::from(skill.profile().head_aim);
        assert!(
            (share - want).abs() < 0.04,
            "{skill:?}: {share} against {want}"
        );
        assert!(
            share > last || skill == BotSkill::Tourist,
            "{skill:?} climbs"
        );
        last = share;
    }
    assert_eq!(head_share(BotSkill::Tourist, WeaponType::Rail, 20.0), 0.0);
    assert!(head_share(BotSkill::Headliner, WeaponType::Rail, 20.0) >= 0.15);
}

#[test]
fn a_sighting_keeps_its_choice_and_new_sightings_draw_again() {
    let profile = BotSkill::NoCrumbs.profile();
    let head = head_centre([20.0, 0.0, 0.0], None, false);
    let zone = |sighting: u64| {
        aim_zone(
            &profile,
            Uuid::from_u128(7),
            Uuid::from_u128(8),
            sighting,
            EYE,
            head,
            WeaponType::Rail,
        )
    };
    for sighting in 0..200 {
        assert_eq!(zone(sighting), zone(sighting));
    }
    let heads = (0..200).filter(|s| zone(*s) == AimZone::Head).count();
    assert!((20..120).contains(&heads), "{heads} of 200 sightings");
}

#[test]
fn a_cone_too_wide_for_the_head_keeps_centre_mass() {
    // The Scatter's pellet cone covers more than the head past a few metres,
    // and the Rifle's past about seven: the top rung keeps centre mass there.
    assert_eq!(
        head_share(BotSkill::NoCrumbs, WeaponType::Scatter, 12.0),
        0.0
    );
    assert_eq!(
        head_share(BotSkill::NoCrumbs, WeaponType::Flechette, 15.0),
        0.0
    );
    assert!(head_share(BotSkill::NoCrumbs, WeaponType::Scatter, 2.5) > 0.15);
    assert!(head_share(BotSkill::NoCrumbs, WeaponType::Flechette, 5.0) > 0.15);
    // The Railgun's tight cone fits the head across a long lane.
    assert!(head_share(BotSkill::NoCrumbs, WeaponType::Rail, 24.0) > 0.15);
}
