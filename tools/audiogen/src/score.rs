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
/// Godot's `config/name` for the client, which names its user data folder.
pub const PROJECT_NAME: &str = "fragr";
/// The client's settings file inside that folder (`FragrSettings.PATH`).
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
        "windows" => PathBuf::from(env("APPDATA")?).join("Godot"),
        "macos" => PathBuf::from(env("HOME")?).join("Library/Application Support/Godot"),
        _ => match env("XDG_DATA_HOME").filter(|value| !value.is_empty()) {
            Some(data) => PathBuf::from(data).join("godot"),
            None => PathBuf::from(env("HOME")?).join(".local/share/godot"),
        },
    };
    Some(
        base.join("app_userdata")
            .join(PROJECT_NAME)
            .join(SETTINGS_FILE),
    )
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
            "kept both takes, no pick yet: {}",
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
/// Every path is checked before anything changes.
pub fn apply_prune(plan: &PrunePlan, score_dir: &Path) -> Result<(), Error> {
    let audio_root = score_dir
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_default();
    for removal in &plan.removals {
        if !valid_slot(&removal.slot) || !TAKES.contains(&removal.take.as_str()) {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Manifest, ManifestEntry};

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "fragr-audiogen-score-{name}-{}",
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
            PathBuf::from("/home/n/.local/share/godot/app_userdata/fragr/settings.cfg")
        );
        assert_eq!(
            settings_path_for("linux", &env(&[("HOME", "/h"), ("XDG_DATA_HOME", "/x")])).unwrap(),
            PathBuf::from("/x/godot/app_userdata/fragr/settings.cfg")
        );
        assert_eq!(
            settings_path_for("macos", &env(&[("HOME", "/Users/n")])).unwrap(),
            PathBuf::from(
                "/Users/n/Library/Application Support/Godot/app_userdata/fragr/settings.cfg"
            )
        );
        assert_eq!(
            settings_path_for(
                "windows",
                &env(&[("APPDATA", "C:/Users/n/AppData/Roaming")])
            )
            .unwrap(),
            PathBuf::from("C:/Users/n/AppData/Roaming/Godot/app_userdata/fragr/settings.cfg")
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
        assert!(text.contains("kept both takes, no pick yet: l02") && text.contains("BLOCKED l03"));
        apply_prune(&plan, &score).unwrap();
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
        assert!(apply_prune(&plan, &score).is_err());
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
        assert!(apply_prune(&bad, &score).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }
}
