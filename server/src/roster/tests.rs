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
    assert_eq!(ROSTER.len(), 80);
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
    // Killfeed readability: no first letter crowds the column. Seven, not
    // five, once the eight shipped callsigns and the famous three returned.
    for letter in seen.iter().filter_map(|n| n.chars().next()) {
        let count = ROSTER
            .iter()
            .filter(|f| f.name.to_ascii_lowercase().starts_with(letter))
            .count();
        assert!(count <= 7, "{count} callsigns start with {letter}");
    }
    assert!(find("Scrap Fox").is_none());
    // Floating 67 spawned once and never again (cast.md); Meat Proxy is the
    // default player callsign (voice.md). Neither is a rule bot.
    for name in seen {
        assert!(!name.contains("floating"), "{name}");
        assert_ne!(name, "meat proxy");
    }
}

#[test]
fn every_callsign_has_three_short_unique_lines_per_beat() {
    let mut lines = HashSet::new();
    for fighter in ROSTER {
        for kind in KINDS {
            for line in fighter.taunts(kind) {
                assert!(!line.is_empty(), "{} {kind:?}", fighter.name);
                assert!(line.chars().count() <= 32, "{line} is too long");
                if tribe(fighter.name) == Some(Tribe::NightWatch) {
                    // Capitals, no punctuation (the-league.md).
                    assert!(
                        line.chars().all(|c| c.is_ascii_uppercase() || c == ' '),
                        "{line} is not night watch"
                    );
                } else {
                    assert_eq!(*line, line.to_lowercase(), "{line} is not lowercase");
                }
                assert!(lines.insert(line.to_lowercase()), "{line} is said twice");
            }
        }
    }
    assert_eq!(lines.len(), 80 * 4 * 3);
    // Frozen strings (voice.md): the shipped radio track sings the first.
    for frozen in [
        "scout ant deleted you",
        "value for value",
        "amen fistbump",
        "not for public release",
    ] {
        assert!(lines.contains(frozen), "{frozen}");
    }
}

#[test]
fn roster_keeps_radio_words_and_the_slur_out() {
    // The radio is a station feature, not the fighters' vocabulary.
    // "static" stays allowed: Static Kid and the Static Kids are canon.
    const BANNED: [&str; 8] = [
        "booth",
        "dial",
        "station",
        "frequenc",
        "broadcast",
        "listener",
        "radio",
        "clanker",
    ];
    for fighter in ROSTER {
        let mut said: Vec<String> = vec![fighter.name.to_lowercase()];
        for kind in KINDS {
            said.extend(fighter.taunts(kind).iter().map(|l| l.to_lowercase()));
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
    assert_eq!(count(&|f| f.behavior == BotBehavior::Aggressive), 23);
    assert_eq!(count(&|f| f.behavior == BotBehavior::Defensive), 20);
    assert_eq!(count(&|f| f.behavior == BotBehavior::Balanced), 22);
    assert_eq!(count(&|f| f.behavior == BotBehavior::Flanker), 15);
    assert_eq!(count(&|f| f.allegiance == Allegiance::Free), 51);
    assert_eq!(count(&|f| f.allegiance == Allegiance::Union), 18);
    assert_eq!(count(&|f| f.allegiance == Allegiance::League), 11);
    // Both bodies serve the free side and the Union, so a body never names
    // an allegiance. League regulars are humans: a free agent never takes a
    // Union seat, where its body in issued livery would read as a Union bot.
    for side in [Allegiance::Free, Allegiance::Union] {
        for body in BodyKind::ALL {
            assert!(count(&|f| f.allegiance == side && f.body == body) > 0);
        }
    }
    assert_eq!(
        count(&|f| f.allegiance == Allegiance::League && f.body != BodyKind::Human),
        0
    );
    // Killfeed rivalries sit on opposite sides.
    for (free, union) in [
        ("Formerly 4471", "Handle 4471-K"),
        ("Never Signed", "Initial Here 3"),
        ("Mailed It Back", "Polite Recall 9"),
        ("Grandma Rizz", "Your Privacy 20"),
    ] {
        assert_eq!(find(free).unwrap().allegiance, Allegiance::Free);
        assert_eq!(find(union).unwrap().allegiance, Allegiance::Union);
    }
}

#[test]
fn shipped_regulars_and_famous_agents_keep_their_canon() {
    // cast.md "The regulars": the eight shipped callsigns keep the
    // behaviors the first roster gave them and fight on either side.
    for (name, behavior) in [
        ("Dead Air Dan", BotBehavior::Aggressive),
        ("Nightfall", BotBehavior::Defensive),
        ("Static Kid", BotBehavior::Flanker),
        ("Aunt Linda", BotBehavior::Balanced),
        ("Scout Ant", BotBehavior::Flanker),
        ("Crackpot", BotBehavior::Defensive),
        ("Buzzkill", BotBehavior::Aggressive),
        ("Tin Foil Tina", BotBehavior::Balanced),
    ] {
        let fighter = find(name).unwrap_or_else(|| panic!("{name} left the pool"));
        assert_eq!(fighter.behavior, behavior, "{name}");
        assert_eq!(fighter.allegiance, Allegiance::League, "{name}");
    }
    // The famous three are free agents, relentlessly polite and quietly
    // winning. Hermes thanks you after every frag; L5 says very little.
    for name in ["Hermes", "Pi", "L5"] {
        let fighter = find(name).unwrap_or_else(|| panic!("{name} left the pool"));
        assert_eq!(fighter.allegiance, Allegiance::Free);
        assert_eq!(fighter.body, BodyKind::Synthetic);
    }
    let hermes = find("Hermes").unwrap();
    assert!(hermes
        .taunts(BotTauntKind::Frag)
        .iter()
        .all(|line| line.starts_with("thank you")));
    for kind in KINDS {
        for line in find("L5").unwrap().taunts(kind) {
            assert!(line.chars().count() <= 16, "L5 said {line}");
        }
    }
}

#[test]
fn tribes_shape_names_lines_and_behavior() {
    let members = |wanted: Tribe| ROSTER.iter().filter(move |f| tribe(f.name) == Some(wanted));
    for kind in [
        Tribe::NightWatch,
        Tribe::StaticKids,
        Tribe::HangarCandy,
        Tribe::GulfBreeze,
    ] {
        assert!(members(kind).count() >= 2, "{kind:?}");
    }
    for fighter in members(Tribe::NightWatch) {
        assert_eq!(fighter.behavior, BotBehavior::Defensive, "{}", fighter.name);
        assert!(fighter
            .name
            .chars()
            .all(|c| c.is_ascii_alphabetic() || c == ' '));
        for line in fighter.taunts(BotTauntKind::Frag) {
            assert!(
                line.len() == 2 && line.chars().all(|c| c.is_ascii_uppercase()),
                "a grid mark, not a taunt: {line}"
            );
        }
    }
    for fighter in members(Tribe::StaticKids) {
        // The shipped callsign keeps its vowels; every new tag drops them.
        if fighter.name != "Static Kid" {
            assert_eq!(fighter.behavior, BotBehavior::Aggressive, "they push");
            assert!(!fighter
                .name
                .to_ascii_lowercase()
                .contains(['a', 'e', 'i', 'o', 'u']));
        }
    }
    for fighter in members(Tribe::HangarCandy) {
        assert!(
            fighter
                .taunts(BotTauntKind::Frag)
                .iter()
                .any(|line| line.contains("denied")),
            "{} leaves no watermark",
            fighter.name
        );
    }
    for fighter in members(Tribe::GulfBreeze) {
        assert_eq!(fighter.behavior, BotBehavior::Flanker, "{}", fighter.name);
        let believes = KINDS.iter().any(|kind| {
            fighter
                .taunts(*kind)
                .iter()
                .any(|line| line.contains("corner") || line.contains("coordinates"))
        });
        assert!(believes, "{}", fighter.name);
    }
    for fighter in ROSTER {
        if let Some(kind) = tribe(fighter.name) {
            assert_ne!(fighter.allegiance, Allegiance::Union, "{kind:?}");
        }
    }
    assert_eq!(tribe("Nightfall-2"), Some(Tribe::NightWatch));
    assert_eq!(tribe("Grandma Rizz"), None);
}

#[test]
fn union_names_are_issued_and_nods_cite_articles() {
    // continuance.md: an issued handle is a name with a number in it, and
    // NODS answer only to Articles: no taunt, no joke.
    for fighter in ROSTER.iter().filter(|f| f.allegiance == Allegiance::Union) {
        if fighter.body == BodyKind::Synthetic {
            assert!(
                fighter.name.chars().any(|c| c.is_ascii_digit()),
                "{} has no issued number",
                fighter.name
            );
        }
        if fighter.name.starts_with("NODS") {
            for kind in KINDS {
                for line in fighter.taunts(kind) {
                    assert!(line.starts_with("article "), "NODS said {line}");
                }
            }
        }
    }
    assert!(ROSTER.iter().any(|f| f.name.starts_with("NODS")));
    // A free agent's callsign was taken, not issued: only Formerly 4471
    // keeps a number, to say it is formerly, and L5 is just L5.
    for fighter in ROSTER
        .iter()
        .filter(|f| f.allegiance == Allegiance::Free && f.body == BodyKind::Synthetic)
    {
        if fighter.name.chars().any(|c| c.is_ascii_digit()) {
            assert!(
                matches!(fighter.name, "Formerly 4471" | "L5"),
                "{}",
                fighter.name
            );
        }
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
    }
    // Free-for-all has no Union livery, so no Union callsign sits there.
    assert!(Allegiance::Free.fits(None));
    assert!(!Allegiance::Union.fits(None));
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
    // Free-for-all seats free and league callsigns only: sixty-two of them.
    let pool = ROSTER.iter().filter(|f| f.allegiance.fits(None)).count();
    assert_eq!(pool, 62);
    let ffa = fill(pool, false, 3);
    let unique: HashSet<_> = ffa.iter().map(|s| s.2.clone()).collect();
    assert_eq!(unique.len(), pool);
    assert!(
        ffa.iter().all(|s| s.1.name == s.2),
        "no suffix while names remain"
    );
    assert!(ffa.iter().all(|s| s.1.allegiance != Allegiance::Union));
    // Union plus league is twenty-nine callsigns; the thirtieth Union seat
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
