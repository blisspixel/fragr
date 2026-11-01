//! The policy, enforced. These tests fail when the fun metrics record could
//! carry something about a person: a new field the policy does not list, a
//! text, id or address type in the record's source, or a string on disk that
//! is not one of the game's own closed words. Adding a field means changing
//! `record.rs`, `FIELDS` below and the field list in `docs/PRIVACY.md` in the
//! same change, after asking whether the number could point at anybody.
use super::record::*;
use crate::protocol::{GameMode, Mutator, WeaponType};
use crate::sim::BotSkill;
use serde_json::Value;
use std::collections::BTreeSet;

/// Every leaf a record writes. A per-gun table is one entry with `*`.
const FIELDS: &[&str] = &[
    "schema",
    "map_id",
    "mode",
    "mutators",
    "friendly_fire",
    "bot_tier",
    "finished",
    "match_ticks",
    "fighters_peak",
    "bots_peak",
    "tally.rounds",
    "tally.live_ticks",
    "tally.frags",
    "tally.spawns",
    "tally.spawn_deaths",
    "tally.hits",
    "tally.self_deaths",
    "tally.lead_changes",
    "tally.pickups",
    "tally.power_returns",
    "tally.power_claims",
    "tally.power_wait_ticks",
    "tally.appointments",
    "tally.contested_frags",
    "tally.plate_claims",
    "tally.rocket_claims",
    "tally.drop_claims",
    "tally.captures",
    "tally.shots.*",
    "tally.frag_weapons.*",
    "tally.zone_hits.head",
    "tally.zone_hits.torso",
    "tally.zone_hits.legs",
    "tally.zone_hits.plate",
    "tally.zone_hits.weak",
    "tally.kill_zones.head",
    "tally.kill_zones.torso",
    "tally.kill_zones.legs",
    "tally.kill_zones.plate",
    "tally.kill_zones.weak",
    "tally.kill_distance_cm.*",
    "tally.time_to_kill_ticks",
    "tally.respawn_to_contact_ticks",
    "tally.respawn_to_hit_ticks",
    "tally.sabotage.rounds",
    "tally.sabotage.attack_wins",
    "tally.sabotage.defence_wins",
    "tally.sabotage.level_rounds",
    "tally.sabotage.by_elimination",
    "tally.sabotage.by_detonation",
    "tally.sabotage.by_defuse",
    "tally.sabotage.by_time",
    "tally.sabotage.plants",
    "tally.sabotage.matches_decided",
    "tally.conquest.matches_decided",
    "tally.conquest.union_wins",
    "tally.conquest.coalition_wins",
    "tally.conquest.site_flips",
    "tally.conquest.union_sites_at_end",
    "tally.conquest.coalition_sites_at_end",
    "tally.conquest.union_tickets_left",
    "tally.conquest.coalition_tickets_left",
    "tick_health.ticks",
    "tick_health.p50_us",
    "tick_health.p99_us",
    "tick_health.max_us",
    "tick_health.over_budget",
];

/// Per-gun tables: their keys are guns, never free text.
const WEAPON_TABLES: &[&str] = &["shots", "frag_weapons", "kill_distance_cm"];

/// Words no field name may contain, whatever it holds.
const FORBIDDEN_WORDS: &[&str] = &[
    "ip",
    "addr",
    "address",
    "name",
    "callsign",
    "player",
    "agent",
    "human",
    "user",
    "id",
    "uuid",
    "ticket",
    "token",
    "resume",
    "chat",
    "speak",
    "say",
    "voice",
    "audio",
    "hardware",
    "gpu",
    "cpu",
    "device",
    "os",
    "location",
    "country",
    "city",
    "timestamp",
    "date",
    "clock",
    "unix",
    "epoch",
    "wall",
    "seed",
    "hash",
    "secret",
    "email",
    "account",
    "host",
    "peer",
];

/// Field names that contain a forbidden word but name the game, not anybody.
const ALLOWED_DESPITE: &[&str] = &["map_id"];

/// Types the record's source must never name.
const FORBIDDEN_TYPES: &[&str] = &[
    "String",
    "str",
    "char",
    "Uuid",
    "IpAddr",
    "Ipv4Addr",
    "Ipv6Addr",
    "SocketAddr",
    "Path",
    "PathBuf",
    "OsString",
    "OsStr",
    "Value",
    "SystemTime",
    "Instant",
    "Cow",
    "Box",
    "HashMap",
    "BTreeMap",
];

fn full_record() -> FunRecord {
    let mut tally = MatchTally {
        rounds: 1,
        live_ticks: 2,
        frags: 3,
        spawns: 4,
        spawn_deaths: 5,
        hits: 6,
        self_deaths: 7,
        lead_changes: 8,
        pickups: 9,
        power_returns: 10,
        power_claims: 11,
        power_wait_ticks: 12,
        appointments: 13,
        contested_frags: 14,
        plate_claims: 15,
        rocket_claims: 16,
        drop_claims: 17,
        captures: 18,
        time_to_kill_ticks: Samples(vec![1]),
        respawn_to_contact_ticks: Samples(vec![2]),
        respawn_to_hit_ticks: Samples(vec![3]),
        sabotage: SabotageTally {
            rounds: 1,
            attack_wins: 1,
            defence_wins: 1,
            level_rounds: 1,
            by_elimination: 1,
            by_detonation: 1,
            by_defuse: 1,
            by_time: 1,
            plants: 1,
            matches_decided: 1,
        },
        zone_hits: ZoneTally {
            head: 1,
            torso: 1,
            legs: 1,
            plate: 1,
            weak: 1,
        },
        kill_zones: ZoneTally {
            head: 1,
            torso: 1,
            legs: 1,
            plate: 1,
            weak: 1,
        },
        conquest: ConquestTally {
            matches_decided: 1,
            union_wins: 1,
            coalition_wins: 1,
            site_flips: 1,
            union_sites_at_end: 1,
            coalition_sites_at_end: 1,
            union_tickets_left: 1,
            coalition_tickets_left: 1,
        },
        ..MatchTally::default()
    };
    for weapon in WeaponType::ALL {
        *tally.shots.get_mut(weapon) = 1;
        *tally.frag_weapons.get_mut(weapon) = 1;
        tally.kill_distance_cm.get_mut(weapon).push(100);
    }
    FunRecord {
        schema: RECORD_SCHEMA,
        map_id: 1,
        mode: GameMode::Ffa,
        mutators: Mutator::ALL.to_vec(),
        friendly_fire: true,
        bot_tier: BotSkill::NoCrumbs,
        finished: true,
        match_ticks: 1,
        fighters_peak: 1,
        bots_peak: 1,
        tally,
        tick_health: Some(TickHealth {
            ticks: 1,
            p50_us: 1,
            p99_us: 1,
            max_us: 1,
            over_budget: 1,
        }),
    }
}

fn leaves(value: &Value, path: &str, table: bool, out: &mut BTreeSet<String>) {
    match value {
        Value::Object(map) => {
            for (key, child) in map {
                let segment = if table { "*" } else { key.as_str() };
                let next = if path.is_empty() {
                    segment.to_string()
                } else {
                    format!("{path}.{segment}")
                };
                leaves(child, &next, WEAPON_TABLES.contains(&key.as_str()), out);
            }
        }
        _ => {
            out.insert(path.to_string());
        }
    }
}

fn strings(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::String(text) => out.push(text.clone()),
        Value::Array(items) => items.iter().for_each(|item| strings(item, out)),
        Value::Object(map) => map.values().for_each(|item| strings(item, out)),
        _ => {}
    }
}

fn wire(value: impl serde::Serialize) -> String {
    serde_json::to_value(value)
        .unwrap()
        .as_str()
        .unwrap()
        .to_string()
}

#[test]
fn a_record_holds_exactly_the_fields_the_policy_names() {
    let json = serde_json::to_value(full_record()).unwrap();
    let mut found = BTreeSet::new();
    leaves(&json, "", false, &mut found);
    let expected: BTreeSet<String> = FIELDS.iter().map(|f| f.to_string()).collect();
    let added: Vec<&String> = found.difference(&expected).collect();
    let missing: Vec<&String> = expected.difference(&found).collect();
    assert!(
        added.is_empty() && missing.is_empty(),
        "the record's fields changed (added {added:?}, missing {missing:?}): \
         a fun metrics field ships only with docs/PRIVACY.md and this list, \
         and only if it cannot point at a person"
    );
}

#[test]
fn no_field_name_reads_like_something_about_a_person() {
    for field in FIELDS {
        for segment in field.split('.') {
            if segment == "*" || ALLOWED_DESPITE.contains(&segment) {
                continue;
            }
            for word in segment.split('_') {
                assert!(
                    !FORBIDDEN_WORDS.contains(&word),
                    "{field}: {word:?} has no place in a fun metrics record"
                );
            }
        }
    }
}

#[test]
fn every_string_on_disk_is_one_of_the_game_s_own_words() {
    let mut words: BTreeSet<String> = GameMode::ALL.into_iter().map(wire).collect();
    words.extend(Mutator::ALL.into_iter().map(wire));
    words.extend(BotSkill::ALL.into_iter().map(wire));
    let json = serde_json::to_value(full_record()).unwrap();
    let mut found = Vec::new();
    strings(&json, &mut found);
    assert!(!found.is_empty(), "the record names its mode and tier");
    for text in found {
        assert!(words.contains(&text), "{text:?} is free text in a record");
    }
    // A gun table's keys are guns and only guns.
    let guns: BTreeSet<String> = WeaponType::ALL.into_iter().map(wire).collect();
    for table in WEAPON_TABLES {
        let keys: BTreeSet<String> = json["tally"][*table]
            .as_object()
            .unwrap()
            .keys()
            .cloned()
            .collect();
        assert_eq!(keys, guns, "{table}");
    }
}

#[test]
fn the_record_source_names_no_text_id_or_address_type() {
    let source = include_str!("record.rs");
    for (number, line) in source.lines().enumerate() {
        let code = line.split("//").next().unwrap_or_default();
        for token in code.split(|c: char| !(c.is_alphanumeric() || c == '_')) {
            assert!(
                !FORBIDDEN_TYPES.contains(&token),
                "record.rs line {}: {token} could carry something about a person",
                number + 1
            );
        }
    }
}

#[test]
fn a_record_refuses_a_field_it_does_not_know() {
    let mut json = serde_json::to_value(full_record()).unwrap();
    json["callsign"] = Value::String("Nightfall".into());
    assert!(serde_json::from_value::<FunRecord>(json).is_err());
    let mut json = serde_json::to_value(full_record()).unwrap();
    json["tally"]["chat"] = Value::from(1);
    assert!(serde_json::from_value::<FunRecord>(json).is_err());
    let back: FunRecord =
        serde_json::from_value(serde_json::to_value(full_record()).unwrap()).unwrap();
    assert_eq!(back, full_record());
}

#[test]
fn the_policy_lists_exactly_the_recorded_fields() {
    let policy = include_str!("../../../docs/PRIVACY.md");
    let start = policy
        .find("<!-- fun-metrics-fields -->")
        .expect("docs/PRIVACY.md marks the recorded field list");
    let end = policy
        .find("<!-- /fun-metrics-fields -->")
        .expect("docs/PRIVACY.md closes the recorded field list");
    let listed: BTreeSet<String> = policy[start..end]
        .split('`')
        .skip(1)
        .step_by(2)
        .map(str::to_string)
        .collect();
    let expected: BTreeSet<String> = FIELDS.iter().map(|f| f.to_string()).collect();
    assert_eq!(
        listed, expected,
        "docs/PRIVACY.md and the record must name the same fields"
    );
    assert!(policy.contains("67 days"));
    assert_eq!(super::RETENTION_DAYS, 67);
}
