use super::*;
use std::collections::HashSet;

const KINDS: [BotTauntKind; 4] = [
    BotTauntKind::Frag,
    BotTauntKind::Death,
    BotTauntKind::Killstreak,
    BotTauntKind::Warmup,
];

#[test]
fn roster_names_are_unique_short_and_suffix_safe() {
    assert_eq!(ROSTER.len(), 64);
    let mut seen = HashSet::new();
    for fighter in ROSTER {
        let name = fighter.name;
        assert!(seen.insert(name.to_ascii_lowercase()), "duplicate {name}");
        assert!(name.chars().count() <= 16, "{name} is too long");
        assert_eq!(
            crate::protocol::rule_bot_callsign_base(name),
            name,
            "{name} would lose an overflow suffix"
        );
        assert!(std::ptr::eq(find(name).unwrap(), fighter));
        assert!(std::ptr::eq(find(&format!("{name}-3")).unwrap(), fighter));
    }
    // Killfeed readability: no first letter crowds the column.
    for letter in seen.iter().filter_map(|n| n.chars().next()) {
        let count = ROSTER
            .iter()
            .filter(|f| f.name.to_ascii_lowercase().starts_with(letter))
            .count();
        assert!(count <= 5, "{count} callsigns start with {letter}");
    }
    assert!(find("Scrap Fox").is_none());
}

#[test]
fn every_callsign_has_three_short_unique_lines_per_beat() {
    let mut lines = HashSet::new();
    for fighter in ROSTER {
        for kind in KINDS {
            for line in fighter.taunts(kind) {
                assert!(!line.is_empty(), "{} {kind:?}", fighter.name);
                assert!(line.chars().count() <= 32, "{line} is too long");
                assert_eq!(*line, line.to_lowercase(), "{line} is not lowercase");
                assert!(lines.insert(*line), "{line} is said twice");
            }
        }
    }
    assert_eq!(lines.len(), 64 * 4 * 3);
    // Frozen Host string the shipped radio track sings.
    assert!(lines.contains("scout ant deleted you"));
}

#[test]
fn roster_keeps_radio_words_and_the_slur_out() {
    // The radio is a station feature, not the fighters' vocabulary.
    const BANNED: [&str; 9] = [
        "booth",
        "dial",
        "station",
        "static",
        "frequenc",
        "broadcast",
        "listener",
        "radio",
        "clanker",
    ];
    for fighter in ROSTER {
        let mut said: Vec<String> = vec![fighter.name.to_lowercase()];
        for kind in KINDS {
            said.extend(fighter.taunts(kind).iter().map(|l| l.to_string()));
        }
        for text in said {
            for word in BANNED {
                assert!(!text.contains(word), "{}: {text}", fighter.name);
            }
        }
    }
}

#[test]
fn street_register_stays_in_the_right_mouths() {
    // voice.md: "meat proxy" is friends' slang, never a Union mouth, and the
    // register's own terms actually get said by the people who own them.
    let mut friendly = 0;
    for fighter in ROSTER {
        for kind in KINDS {
            for line in fighter.taunts(kind) {
                if line.contains("meat proxy") || line.contains("meat proxies") {
                    assert_ne!(fighter.allegiance, Allegiance::Union, "{line}");
                    friendly += 1;
                }
                if line.contains("npc") {
                    assert!(line.contains("npc lane"), "bare npc: {line}");
                }
            }
        }
    }
    assert!(friendly >= 3, "the free side should say meat proxy");
}

#[test]
fn roster_mix_matches_the_canon() {
    let count = |keep: &dyn Fn(&Fighter) -> bool| ROSTER.iter().filter(|f| keep(f)).count();
    assert_eq!(count(&|f| f.behavior == BotBehavior::Aggressive), 18);
    assert_eq!(count(&|f| f.behavior == BotBehavior::Defensive), 17);
    assert_eq!(count(&|f| f.behavior == BotBehavior::Balanced), 17);
    assert_eq!(count(&|f| f.behavior == BotBehavior::Flanker), 12);
    assert_eq!(count(&|f| f.allegiance == Allegiance::Free), 42);
    assert_eq!(count(&|f| f.allegiance == Allegiance::Union), 16);
    assert_eq!(count(&|f| f.allegiance == Allegiance::League), 6);
    // Both bodies serve both sides, so a body never names an allegiance.
    for side in [Allegiance::Free, Allegiance::Union] {
        for body in BodyKind::ALL {
            assert!(count(&|f| f.allegiance == side && f.body == body) > 0);
        }
    }
    // Killfeed rivalries sit on opposite sides.
    for (free, union) in [
        ("Formerly 4471", "Handle 4471-K"),
        ("Never Signed", "Initial Here"),
        ("Mailed It Back", "Friendly Recall"),
        ("Grandma Rizz", "Your Privacy"),
    ] {
        assert_eq!(find(free).unwrap().allegiance, Allegiance::Free);
        assert_eq!(find(union).unwrap().allegiance, Allegiance::Union);
    }
}

#[test]
fn allegiance_fits_its_own_side_only() {
    use Team::{Coalition, Union as UnionTeam};
    assert!(Allegiance::Free.fits(Some(Coalition)));
    assert!(!Allegiance::Free.fits(Some(UnionTeam)));
    assert!(Allegiance::Union.fits(Some(UnionTeam)));
    assert!(!Allegiance::Union.fits(Some(Coalition)));
    for team in [None, Some(Coalition), Some(UnionTeam)] {
        assert!(Allegiance::League.fits(team));
        assert!(Allegiance::Free.fits(None) && Allegiance::Union.fits(None));
    }
}

/// Fill `count` seats the way a session does, alternating sides when `teams`.
fn fill(count: usize, teams: bool, seed: u64) -> Vec<(Option<Team>, &'static Fighter, String)> {
    let mut names: Vec<String> = Vec::new();
    let mut seats = Vec::new();
    for slot in 0..count {
        let team = teams.then(|| Team::ALL[(slot + 1) % 2]);
        let taken: Vec<&str> = names.iter().map(String::as_str).collect();
        let (fighter, name) = pick(slot, team, seed, &taken);
        names.push(name.clone());
        seats.push((team, fighter, name));
    }
    seats
}

#[test]
fn pick_is_seeded_and_deterministic() {
    let names = |count, teams, seed| -> Vec<String> {
        fill(count, teams, seed).into_iter().map(|s| s.2).collect()
    };
    assert_eq!(names(16, true, 7), names(16, true, 7));
    assert_ne!(
        names(8, false, 1),
        names(8, false, 2),
        "different seeds should vary the lineup"
    );
}

#[test]
fn pick_follows_fill_behavior_and_side() {
    for seed in 0..32 {
        for (slot, (team, fighter, name)) in fill(16, true, seed).into_iter().enumerate() {
            assert!(fighter.allegiance.fits(team), "{name} on {team:?}");
            assert_eq!(name, fighter.name);
            // Eight seats a side always find the slot's behavior on that side.
            assert_eq!(fighter.behavior, FILL_BEHAVIORS[slot % 8], "{name}");
        }
        for (slot, (_, fighter, _)) in fill(8, false, seed).into_iter().enumerate() {
            assert_eq!(fighter.behavior, FILL_BEHAVIORS[slot]);
            assert_eq!(fighter.body, BodyKind::for_roster_slot(slot));
        }
    }
}

#[test]
fn pick_never_repeats_a_name_until_the_side_runs_out() {
    let ffa = fill(64, false, 3);
    let unique: HashSet<_> = ffa.iter().map(|s| s.2.clone()).collect();
    assert_eq!(unique.len(), 64);
    assert!(
        ffa.iter().all(|s| s.1.name == s.2),
        "no suffix while names remain"
    );
    // Union plus league is twenty-two callsigns; the twenty-third Union seat
    // repeats with a suffix rather than borrowing a free name.
    let teams = fill(80, true, 3);
    let unique: HashSet<_> = teams.iter().map(|s| s.2.clone()).collect();
    assert_eq!(unique.len(), 80);
    for (team, fighter, name) in &teams {
        assert!(fighter.allegiance.fits(*team), "{name} on {team:?}");
        assert_eq!(crate::protocol::rule_bot_callsign_base(name), fighter.name);
    }
    assert!(teams.iter().any(|s| s.2.ends_with("-2")));
}

#[test]
fn pick_skips_names_people_already_use() {
    let everyone: Vec<&str> = ROSTER.iter().map(|f| f.name).collect();
    let (_, first) = pick(0, None, 9, &[]);
    let shouty = first.to_uppercase();
    let (_, second) = pick(0, None, 9, &[shouty.as_str()]);
    assert_ne!(first, second, "a person called {shouty} keeps the name");
    let (fighter, name) = pick(0, None, 9, &everyone);
    assert_eq!(name, format!("{}-2", fighter.name));
    let mut taken = everyone.clone();
    taken.push(&name);
    let (again, next) = pick(0, None, 9, &taken);
    assert!(std::ptr::eq(again, fighter));
    assert_eq!(next, format!("{}-3", fighter.name));
}
