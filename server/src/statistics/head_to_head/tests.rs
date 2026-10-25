use super::*;

#[test]
fn the_book_counts_by_callsign_without_case_or_overflow_suffix() {
    let mut book = HeadToHead::default();
    book.record("Nightfall", "Meat Proxy");
    book.record("Nightfall-2", "meat proxy");
    book.record("Meat Proxy", "NIGHTFALL");
    assert_eq!(book.frags("nightfall", "Meat Proxy"), 2);
    assert_eq!(book.frags("Meat Proxy", "Nightfall-3"), 1);
    assert_eq!(book.deficit("Meat Proxy", "Nightfall"), 1);
    assert_eq!(book.deficit("Nightfall", "Meat Proxy"), -1);
    assert!(book.is_dirty());
    // A copy of one's own callsign, a blank or an overlong name is no meeting.
    book.record("Nightfall", "Nightfall-2");
    book.record("", "Nightfall");
    book.record(&"x".repeat(MAX_NAME_CHARS + 1), "Nightfall");
    book.record("Tab\tName", "Nightfall");
    assert_eq!(book.pairs.len(), 2);
}

#[test]
fn a_grudge_is_the_opponent_present_who_is_owed_most() {
    let mut book = HeadToHead::default();
    for _ in 0..3 {
        book.record("Aunt Linda", "Static Kid");
    }
    book.record("Pi", "Static Kid");
    book.record("Static Kid", "Pi");
    book.record("Static Kid", "Hermes");
    let present = ["Static Kid", "Aunt Linda", "Pi", "Hermes"];
    assert_eq!(book.grudge("Static Kid", present), Some("Aunt Linda"));
    // Square with Pi, ahead of Hermes: no grudge there.
    assert_eq!(book.grudge("Static Kid", ["Pi", "Hermes"]), None);
    // Only those present count, and nobody holds one against themselves.
    assert_eq!(book.grudge("Static Kid", ["Static Kid", "Hermes"]), None);
    assert_eq!(book.grudge("Hermes", present), Some("Static Kid"));
}

#[test]
fn the_book_stops_taking_new_pairs_at_its_cap_but_keeps_counting() {
    let mut book = HeadToHead::default();
    for n in 0..MAX_PAIRS {
        book.record(&format!("K{n}"), "Victim");
    }
    book.record("Latecomer", "Victim");
    assert_eq!(book.frags("Latecomer", "Victim"), 0);
    book.record("K7", "Victim");
    assert_eq!(book.frags("K7", "Victim"), 2);
}

#[test]
fn one_schema_round_trips_and_anything_else_is_refused() {
    let mut book = HeadToHead::default();
    book.record("Nightfall", "Meat Proxy");
    book.record("Nightfall", "Meat Proxy");
    book.record("Meat Proxy", "Hermes");
    let text = book.to_json();
    let back = HeadToHead::from_json(&text).unwrap();
    assert_eq!(back.frags("Nightfall", "Meat Proxy"), 2);
    assert_eq!(back.frags("Meat Proxy", "Hermes"), 1);
    assert!(!back.is_dirty());
    assert!(text.contains("\"version\": 1"), "{text}");
    for (bad, why) in [
        (r#"{"version":2,"pairs":[]}"#, "version"),
        (r#"{"version":1}"#, "pairs"),
        (r#"{"version":1,"pairs":[],"extra":0}"#, "unknown field"),
        (
            r#"{"version":1,"pairs":[{"killer":"A","victim":"a","frags":1}]}"#,
            "one fighter twice",
        ),
        (
            r#"{"version":1,"pairs":[{"killer":"A","victim":"B","frags":0}]}"#,
            "no frags",
        ),
        (
            r#"{"version":1,"pairs":[{"killer":"A","victim":"B","frags":1},{"killer":"a","victim":"b","frags":2}]}"#,
            "repeats",
        ),
        ("not json", "not a head-to-head file"),
    ] {
        let error = HeadToHead::from_json(bad).unwrap_err();
        assert!(error.contains(why), "{bad}: {error}");
    }
}

#[test]
fn the_book_saves_and_loads_through_a_file_and_refuses_a_bad_one() {
    let directory = std::env::temp_dir().join(format!(
        "fragr-head-to-head-{}-{}",
        std::process::id(),
        uuid::Uuid::new_v4()
    ));
    let path = directory.join("nested").join("head-to-head.json");
    let (empty, refused) = HeadToHead::load(&path);
    assert_eq!((empty, refused), (HeadToHead::default(), None));
    let mut book = HeadToHead::default();
    book.record("Buzzkill", "Crackpot");
    book.save(&path).unwrap();
    assert!(!book.is_dirty());
    let (loaded, refused) = HeadToHead::load(&path);
    assert_eq!(refused, None);
    assert_eq!(loaded.frags("Buzzkill", "Crackpot"), 1);
    // No temporary file is left beside it.
    let names: Vec<_> = std::fs::read_dir(path.parent().unwrap())
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect();
    assert_eq!(names.len(), 1, "{names:?}");
    // Another version is refused with a reason and the book starts fresh.
    std::fs::write(&path, r#"{"version":0,"pairs":[]}"#).unwrap();
    let (fresh, refused) = HeadToHead::load(&path);
    assert_eq!(fresh, HeadToHead::default());
    assert!(refused.unwrap().contains("version 0"));
    // An oversized file is refused before it is parsed.
    std::fs::write(&path, vec![b' '; MAX_BYTES as usize + 2]).unwrap();
    assert!(HeadToHead::load(&path).1.unwrap().contains("larger than"));
    // A directory where the file should be is a read error, not a panic.
    std::fs::remove_file(&path).unwrap();
    std::fs::create_dir(&path).unwrap();
    assert!(HeadToHead::load(&path).1.is_some());
    assert!(book.save(&path).is_err());
    std::fs::remove_dir_all(&directory).unwrap();
}
