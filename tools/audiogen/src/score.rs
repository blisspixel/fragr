//! Campaign score takes. Every score slot (a level bed or a story cue) ships
//! two takes, `client/assets/audio/score/<slot>/a.mp3` and `b.mp3`, until Nick
//! picks one per slot while playing. The game keeps each pick in its settings
//! file (`[score] takes`). `score-picks` reads that file and reports or saves
//! the picks; `score-prune` deletes the takes that were not picked, with their
//! `.import` sidecars and manifest entries, in one step.
//!
//! Everything here is offline and spends nothing.

use crate::{load_manifest, save_manifest, Error};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

/// The slot list the client and the review page read.
pub const DEFAULT_SLOTS_FILE: &str = "client/assets/audio/score/slots.json";
/// Shipped takes, `<dir>/<slot>/<take>.mp3`; its parent holds the manifest.
pub const DEFAULT_SCORE_DIR: &str = "client/assets/audio/score";
/// Where `score-picks --save` writes by default (ignored scratch).
pub const DEFAULT_PICKS_FILE: &str = ".agents/score-picks.json";
/// Godot's `config/custom_user_dir_name`, separate from the display title.
pub const PROJECT_NAME: &str = "localexception";
/// The client's settings file inside that folder (`LocalExceptionSettings.PATH`).
pub const SETTINGS_FILE: &str = "settings.cfg";
pub const TAKES: [&str; 2] = ["a", "b"];
const TAKE_EXTENSION: &str = "mp3";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Slot {
    pub id: String,
    pub kind: String,
    #[serde(default)]
    pub name: String,
}

#[derive(Deserialize)]
struct SlotsFile {
    slots: Vec<Slot>,
}

/// Slot ids the client accepts (`CampaignScore.SLOT_PATTERN`).
pub fn valid_slot(id: &str) -> bool {
    let mut chars = id.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_lowercase() || c.is_ascii_digit())
        && id.len() <= 32
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

pub fn load_slots(path: &Path) -> Result<Vec<Slot>, Error> {
    let text = fs::read_to_string(path).map_err(|err| {
        Error::InvalidArgument(format!(
            "no score slots at {} ({err}); run from the repo root or pass --slots",
            path.display()
        ))
    })?;
    let file: SlotsFile = serde_json::from_str(&text)
        .map_err(|err| Error::Spec(format!("unreadable slots file {}: {err}", path.display())))?;
    for slot in &file.slots {
        if !valid_slot(&slot.id) {
            return Err(Error::Spec(format!("unsafe slot id '{}'", slot.id)));
        }
    }
    Ok(file.slots)
}

/// Godot's user data folder for this project on each desktop target, from
/// the platform and its environment. `None` when the needed variable is unset.
pub fn settings_path_for(os: &str, env: &dyn Fn(&str) -> Option<String>) -> Option<PathBuf> {
    let base = match os {
        "windows" => PathBuf::from(env("APPDATA")?),
        "macos" => PathBuf::from(env("HOME")?).join("Library/Application Support"),
        _ => match env("XDG_DATA_HOME").filter(|value| !value.is_empty()) {
            Some(data) => PathBuf::from(data),
            None => PathBuf::from(env("HOME")?).join(".local/share"),
        },
    };
    Some(base.join(PROJECT_NAME).join(SETTINGS_FILE))
}

pub fn default_settings_path() -> Option<PathBuf> {
    settings_path_for(std::env::consts::OS, &|name| std::env::var(name).ok())
}

/// The `[score] takes` dictionary from a Godot ConfigFile. Godot writes a
/// Dictionary as JSON-shaped text that may span lines. Entries the game would
/// refuse (unknown shape, a take other than A or B) are dropped, as at load.
pub fn parse_takes(cfg: &str) -> Result<BTreeMap<String, String>, Error> {
    let mut in_score = false;
    let mut value: Option<String> = None;
    for line in cfg.lines() {
        let trimmed = line.trim();
        if let Some(acc) = value.as_mut() {
            acc.push('\n');
            acc.push_str(line);
            if balanced(acc) {
                break;
            }
            continue;
        }
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            in_score = trimmed == "[score]";
            continue;
        }
        if in_score {
            if let Some(rest) = trimmed.strip_prefix("takes=") {
                let acc = rest.to_string();
                if balanced(&acc) {
                    value = Some(acc);
                    break;
                }
                value = Some(acc);
            }
        }
    }
    let Some(text) = value else {
        return Ok(BTreeMap::new());
    };
    let parsed: serde_json::Value = serde_json::from_str(&text)
        .map_err(|err| Error::Spec(format!("unreadable [score] takes value: {err}")))?;
    let mut takes = BTreeMap::new();
    if let serde_json::Value::Object(map) = parsed {
        for (slot, take) in map {
            if let Some(take) = take.as_str() {
                if valid_slot(&slot) && TAKES.contains(&take) {
                    takes.insert(slot, take.to_string());
                }
            }
        }
    }
    Ok(takes)
}

fn balanced(text: &str) -> bool {
    let open = text.matches('{').count();
    open > 0 && open == text.matches('}').count()
}

/// One slot's state: what was picked in game and which takes still ship.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PickRow {
    pub slot: String,
    pub kind: String,
    pub name: String,
    pub pick: Option<String>,
    pub available: Vec<String>,
}

pub fn take_file(score_dir: &Path, slot: &str, take: &str) -> PathBuf {
    score_dir
        .join(slot)
        .join(format!("{take}.{TAKE_EXTENSION}"))
}

pub fn collect_picks(
    slots: &[Slot],
    takes: &BTreeMap<String, String>,
    score_dir: &Path,
) -> Vec<PickRow> {
    slots
        .iter()
        .map(|slot| PickRow {
            slot: slot.id.clone(),
            kind: slot.kind.clone(),
            name: if slot.name.is_empty() {
                slot.id.clone()
            } else {
                slot.name.clone()
            },
            pick: takes.get(&slot.id).cloned(),
            available: TAKES
                .iter()
                .filter(|take| take_file(score_dir, &slot.id, take).is_file())
                .map(|take| take.to_string())
                .collect(),
        })
        .collect()
}

pub fn describe_picks(rows: &[PickRow]) -> String {
    let mut out = String::new();
    let picked = rows.iter().filter(|row| row.pick.is_some()).count();
    for row in rows {
        let pick = row
            .pick
            .as_deref()
            .map_or("-".to_string(), str::to_uppercase);
        let ships: Vec<String> = row.available.iter().map(|t| t.to_uppercase()).collect();
        let _ = writeln!(
            out,
            "{:<9} pick {:<2} ships {:<4} {}",
            row.slot,
            pick,
            if ships.is_empty() {
                "none".to_string()
            } else {
                ships.join("+")
            },
            row.name
        );
    }
    let _ = writeln!(
        out,
        "{picked} of {} slots picked; an unpicked slot plays take A in game",
        rows.len()
    );
    out
}

/// One unpicked take to delete.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PruneRemoval {
    pub slot: String,
    pub take: String,
    pub file: PathBuf,
    pub manifest_key: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PrunePlan {
    pub removals: Vec<PruneRemoval>,
    /// Slots left alone because nothing was picked.
    pub unpicked: Vec<String>,
    /// Slots whose pick no longer ships; nothing there is deleted.
    pub problems: Vec<String>,
}

/// Pure: for every picked slot whose pick still ships, remove the other takes.
pub fn plan_prune(rows: &[PickRow], score_dir: &Path) -> PrunePlan {
    let mut plan = PrunePlan::default();
    let folder = score_dir
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("score")
        .to_string();
    for row in rows {
        let Some(pick) = &row.pick else {
            if row.available.len() > 1 {
                plan.unpicked.push(row.slot.clone());
            }
            continue;
        };
        if !row.available.contains(pick) {
            plan.problems.push(format!(
                "{}: picked take {} does not ship, so nothing there is removed",
                row.slot,
                pick.to_uppercase()
            ));
            continue;
        }
        for take in row.available.iter().filter(|take| *take != pick) {
            plan.removals.push(PruneRemoval {
                slot: row.slot.clone(),
                take: take.clone(),
                file: take_file(score_dir, &row.slot, take),
                manifest_key: format!("{folder}/{}/{take}", row.slot),
            });
        }
    }
    plan
}

pub fn describe_prune(plan: &PrunePlan) -> String {
    let mut out = String::new();
    for removal in &plan.removals {
        let _ = writeln!(
            out,
            "remove {} ({} take {})",
            removal.file.display(),
            removal.slot,
            removal.take.to_uppercase()
        );
    }
    if !plan.unpicked.is_empty() {
        let _ = writeln!(
            out,
            "kept every take, no pick yet: {}",
            plan.unpicked.join(", ")
        );
    }
    for problem in &plan.problems {
        let _ = writeln!(out, "BLOCKED {problem}");
    }
    if plan.removals.is_empty() {
        out.push_str("nothing to prune\n");
    }
    out
}

/// Delete the planned takes, their `.import` sidecars and manifest entries.
/// Every path is checked before anything changes; `takes` names the take ids
/// that folder may hold (`TAKES` for the score, `JINGLE_TAKES` for the jingle).
pub fn apply_prune(plan: &PrunePlan, score_dir: &Path, takes: &[&str]) -> Result<(), Error> {
    let audio_root = score_dir
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_default();
    for removal in &plan.removals {
        if !valid_slot(&removal.slot) || !takes.contains(&removal.take.as_str()) {
            return Err(Error::InvalidArgument(format!(
                "unsafe removal {}",
                removal.file.display()
            )));
        }
        crate::validate_name(&removal.manifest_key)?;
        crate::review::ensure_inside(score_dir, &removal.file)?;
    }
    let mut manifest = load_manifest(&audio_root)?;
    for removal in &plan.removals {
        fs::remove_file(&removal.file)?;
        let sidecar = removal
            .file
            .with_extension(format!("{TAKE_EXTENSION}.import"));
        if fs::symlink_metadata(&sidecar).is_ok() {
            fs::remove_file(&sidecar)?;
        }
        manifest.entries.remove(&removal.manifest_key);
    }
    save_manifest(&audio_root, &manifest)
}

/// The benchmark jingle (`client/scripts/benchmark_jingle.gd`) ships six takes,
/// `<dir>/benchmark/<take>.mp3`, until Nick picks one on the benchmark results
/// screen; the game saves it as `[audio] benchmark_jingle`. `jingle-prune`
/// reuses the score's plan and apply steps on that one slot.
pub const DEFAULT_JINGLE_DIR: &str = "client/assets/audio/jingle";
pub const JINGLE_SLOT: &str = "benchmark";
/// `BenchmarkJingle.TAKES`.
pub const JINGLE_TAKES: [&str; 6] = ["1a", "1b", "2a", "2b", "3a", "3b"];

/// The `[audio] benchmark_jingle` pick from a Godot ConfigFile, or `None` when
/// the file has none or holds a take the game would refuse. A missing pick is
/// a take the game has never saved, which plays 1A.
pub fn parse_jingle_pick(cfg: &str) -> Option<String> {
    let mut in_audio = false;
    for line in cfg.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            in_audio = trimmed == "[audio]";
            continue;
        }
        if !in_audio {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("benchmark_jingle=") {
            let take = rest.trim().trim_matches('"');
            return JINGLE_TAKES.contains(&take).then(|| take.to_string());
        }
    }
    None
}

/// The jingle as one pick row: its pick and the takes that still ship.
pub fn jingle_row(pick: Option<String>, jingle_dir: &Path) -> PickRow {
    PickRow {
        slot: JINGLE_SLOT.to_string(),
        kind: "jingle".to_string(),
        name: "Benchmark jingle".to_string(),
        pick,
        available: JINGLE_TAKES
            .iter()
            .filter(|take| take_file(jingle_dir, JINGLE_SLOT, take).is_file())
            .map(|take| take.to_string())
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Manifest, ManifestEntry};

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "localexception-audiogen-score-{name}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn entry(file: &str) -> ManifestEntry {
        ManifestEntry {
            kind: "music".into(),
            file: file.into(),
            prompt: "bed".into(),
            model: "music_v2_5".into(),
            format: "mp3_44100_64".into(),
            title: None,
            voice: None,
            seconds: None,
            length_ms: Some(160_000),
            looping: false,
            channels: 2,
            bytes: 1,
            generated_unix: 1,
        }
    }

    #[test]
    fn reads_godot_dictionaries_single_and_multi_line() {
        let cfg = "[audio]\n\nmusic=0.7\ntakes={\n\"l01\": \"b\"\n}\n\n[score]\n\nenabled=true\ntakes={\n\"cue-l19\": \"b\",\n\"l04\": \"a\",\n\"Bad\": \"b\",\n\"l05\": \"c\"\n}\n\n[meta]\n";
        let takes = parse_takes(cfg).unwrap();
        assert_eq!(
            takes,
            BTreeMap::from([
                ("cue-l19".to_string(), "b".to_string()),
                ("l04".to_string(), "a".to_string()),
            ])
        );
        assert_eq!(
            parse_takes("[score]\ntakes={\"l02\": \"b\"}\n").unwrap()["l02"],
            "b"
        );
        assert!(parse_takes("[score]\ntakes={}\n").unwrap().is_empty());
        assert!(parse_takes("[video]\nfps_cap=0\n").unwrap().is_empty());
        assert!(parse_takes("[score]\ntakes={nonsense}\n").is_err());
    }

    #[test]
    fn settings_paths_follow_godot_user_data() {
        let env = |pairs: &'static [(&'static str, &'static str)]| {
            move |name: &str| {
                pairs
                    .iter()
                    .find(|(key, _)| *key == name)
                    .map(|(_, value)| value.to_string())
            }
        };
        assert_eq!(
            settings_path_for("linux", &env(&[("HOME", "/home/n")])).unwrap(),
            PathBuf::from("/home/n/.local/share/localexception/settings.cfg")
        );
        assert_eq!(
            settings_path_for("linux", &env(&[("HOME", "/h"), ("XDG_DATA_HOME", "/x")])).unwrap(),
            PathBuf::from("/x/localexception/settings.cfg")
        );
        assert_eq!(
            settings_path_for("macos", &env(&[("HOME", "/Users/n")])).unwrap(),
            PathBuf::from("/Users/n/Library/Application Support/localexception/settings.cfg")
        );
        assert_eq!(
            settings_path_for(
                "windows",
                &env(&[("APPDATA", "C:/Users/n/AppData/Roaming")])
            )
            .unwrap(),
            PathBuf::from("C:/Users/n/AppData/Roaming/localexception/settings.cfg")
        );
        assert!(settings_path_for("windows", &env(&[])).is_none());
        assert!(default_settings_path().is_some() || std::env::var("HOME").is_err());
    }

    #[test]
    fn slots_load_and_refuse_unsafe_ids() {
        let dir = temp("slots");
        let path = dir.join("slots.json");
        fs::write(
            &path,
            r#"{"slots": [{"id": "l01", "kind": "bed", "name": "Level 1", "mission": "x"}]}"#,
        )
        .unwrap();
        let slots = load_slots(&path).unwrap();
        assert_eq!(slots[0].id, "l01");
        fs::write(&path, r#"{"slots": [{"id": "../x", "kind": "bed"}]}"#).unwrap();
        assert!(load_slots(&path).is_err());
        assert!(load_slots(&dir.join("missing.json"))
            .unwrap_err()
            .to_string()
            .contains("--slots"));
        assert!(valid_slot("cue-l19") && !valid_slot("-x") && !valid_slot("L1") && !valid_slot(""));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn picks_report_and_prune_only_unpicked_takes() {
        let dir = temp("prune");
        let score = dir.join("audio/score");
        for (slot, takes) in [
            ("l01", &["a", "b"][..]),
            ("l02", &["a", "b"][..]),
            ("l03", &["a"][..]),
            ("l04", &["a", "b"][..]),
        ] {
            fs::create_dir_all(score.join(slot)).unwrap();
            for take in takes {
                fs::write(score.join(slot).join(format!("{take}.mp3")), b"x").unwrap();
                fs::write(score.join(slot).join(format!("{take}.mp3.import")), b"i").unwrap();
            }
        }
        let mut manifest = Manifest::default();
        for key in [
            "score/l01/a",
            "score/l01/b",
            "score/l02/a",
            "score/l02/b",
            "score/l03/a",
            "score/l04/a",
            "score/l04/b",
            "radio/rock/01-x",
        ] {
            manifest
                .entries
                .insert(key.to_string(), entry(&format!("{key}.mp3")));
        }
        save_manifest(&dir.join("audio"), &manifest).unwrap();
        let slots: Vec<Slot> = ["l01", "l02", "l03", "l04"]
            .iter()
            .map(|id| Slot {
                id: id.to_string(),
                kind: "bed".into(),
                name: String::new(),
            })
            .collect();
        let takes =
            parse_takes("[score]\ntakes={\n\"l01\": \"b\",\n\"l03\": \"b\",\n\"l04\": \"a\"\n}\n")
                .unwrap();
        let rows = collect_picks(&slots, &takes, &score);
        assert_eq!(rows[2].available, vec!["a".to_string()]);
        let report = describe_picks(&rows);
        assert!(report.contains("l01       pick B  ships A+B"), "{report}");
        assert!(report.contains("3 of 4 slots picked"), "{report}");
        let plan = plan_prune(&rows, &score);
        let removed: Vec<&str> = plan
            .removals
            .iter()
            .map(|removal| removal.manifest_key.as_str())
            .collect();
        assert_eq!(removed, vec!["score/l01/a", "score/l04/b"]);
        assert_eq!(plan.unpicked, vec!["l02".to_string()]);
        assert_eq!(plan.problems.len(), 1, "l03 picked B, which does not ship");
        let text = describe_prune(&plan);
        assert!(text.contains("kept every take, no pick yet: l02") && text.contains("BLOCKED l03"));
        apply_prune(&plan, &score, &TAKES).unwrap();
        assert!(!score.join("l01/a.mp3").exists() && !score.join("l01/a.mp3.import").exists());
        assert!(score.join("l01/b.mp3").exists() && score.join("l02/a.mp3").exists());
        assert!(score.join("l02/b.mp3").exists() && score.join("l03/a.mp3").exists());
        assert!(!score.join("l04/b.mp3").exists() && score.join("l04/a.mp3").exists());
        let after = load_manifest(&dir.join("audio")).unwrap();
        assert!(
            !after.entries.contains_key("score/l01/a")
                && !after.entries.contains_key("score/l04/b")
        );
        assert!(
            after.entries.contains_key("score/l01/b")
                && after.entries.contains_key("radio/rock/01-x")
        );
        // A second pass has nothing to do.
        let again = plan_prune(&collect_picks(&slots, &takes, &score), &score);
        assert!(again.removals.is_empty());
        assert!(describe_prune(&again).contains("nothing to prune"));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn prune_refuses_paths_outside_the_score() {
        let dir = temp("escape");
        let score = dir.join("audio/score");
        fs::create_dir_all(&score).unwrap();
        fs::write(dir.join("outside.mp3"), b"x").unwrap();
        let plan = PrunePlan {
            removals: vec![PruneRemoval {
                slot: "l01".into(),
                take: "a".into(),
                file: dir.join("outside.mp3"),
                manifest_key: "score/l01/a".into(),
            }],
            ..PrunePlan::default()
        };
        assert!(apply_prune(&plan, &score, &TAKES).is_err());
        assert!(dir.join("outside.mp3").exists());
        let bad = PrunePlan {
            removals: vec![PruneRemoval {
                slot: "../x".into(),
                take: "a".into(),
                file: score.join("x"),
                manifest_key: "score/x/a".into(),
            }],
            ..PrunePlan::default()
        };
        assert!(apply_prune(&bad, &score, &TAKES).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn jingle_pick_reads_the_audio_section_only() {
        let cfg =
            "[score]\nbenchmark_jingle=\"3b\"\n\n[audio]\nmaster=0.9\nbenchmark_jingle=\"2a\"\n";
        assert_eq!(parse_jingle_pick(cfg), Some("2a".to_string()));
        assert_eq!(
            parse_jingle_pick("[score]\nbenchmark_jingle=\"3b\"\n"),
            None
        );
        assert_eq!(
            parse_jingle_pick("[audio]\nbenchmark_jingle=\"9z\"\n"),
            None
        );
        assert_eq!(parse_jingle_pick("[audio]\nmaster=0.9\n"), None);
    }

    #[test]
    fn jingle_prune_keeps_only_the_pick() {
        let dir = temp("jingle");
        let jingle = dir.join("audio/jingle");
        fs::create_dir_all(jingle.join(JINGLE_SLOT)).unwrap();
        let mut manifest = Manifest::default();
        for take in JINGLE_TAKES {
            let file = jingle.join(JINGLE_SLOT).join(format!("{take}.mp3"));
            fs::write(&file, b"x").unwrap();
            fs::write(file.with_extension("mp3.import"), b"i").unwrap();
            let key = format!("jingle/{JINGLE_SLOT}/{take}");
            manifest
                .entries
                .insert(key.clone(), entry(&format!("{key}.mp3")));
        }
        manifest
            .entries
            .insert("score/l01/a".into(), entry("score/l01/a.mp3"));
        save_manifest(&dir.join("audio"), &manifest).unwrap();
        // No pick yet: every take stays.
        let unpicked = plan_prune(&[jingle_row(None, &jingle)], &jingle);
        assert!(unpicked.removals.is_empty() && unpicked.unpicked == vec![JINGLE_SLOT]);
        let row = jingle_row(Some("2b".into()), &jingle);
        assert_eq!(row.available.len(), 6);
        let plan = plan_prune(&[row], &jingle);
        assert_eq!(plan.removals.len(), 5);
        assert!(plan
            .removals
            .iter()
            .all(|removal| removal.take != "2b" && removal.manifest_key.starts_with("jingle/")));
        // The score's take list refuses jingle takes, so nothing changes.
        assert!(apply_prune(&plan, &jingle, &TAKES).is_err());
        assert!(jingle.join(JINGLE_SLOT).join("1a.mp3").exists());
        apply_prune(&plan, &jingle, &JINGLE_TAKES).unwrap();
        let left: Vec<String> = jingle_row(Some("2b".into()), &jingle).available;
        assert_eq!(left, vec!["2b".to_string()]);
        assert!(!jingle.join(JINGLE_SLOT).join("1a.mp3.import").exists());
        let after = load_manifest(&dir.join("audio")).unwrap();
        assert!(after.entries.contains_key("jingle/benchmark/2b"));
        assert!(!after.entries.contains_key("jingle/benchmark/1a"));
        assert!(after.entries.contains_key("score/l01/a"));
        fs::remove_dir_all(&dir).unwrap();
    }
}
