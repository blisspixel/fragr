//! Radio music review: listen to shipped tracks and new candidates, mark each
//! keep or reject, and promote the keepers into `client/assets/audio/radio/`.
//!
//! Everything here is offline. The page is served by a small std-only HTTP
//! server bound to loopback; the routing, decision store, catalog scan and
//! promotion planner are plain functions so tests cover them without sockets.

use crate::{load_manifest, save_manifest, write_refusing_symlinks, Error, ManifestEntry};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt::Write as _;
use std::fs;
use std::io::{BufRead, Read, Seek, SeekFrom, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Station list read by `radio.gd`.
pub const DEFAULT_STATIONS_FILE: &str = "client/assets/audio/radio/stations.json";
/// Shipped station folders. Its parent holds the provenance manifest.
pub const DEFAULT_RADIO_DIR: &str = "client/assets/audio/radio";
/// Ignored candidate folders from the 2026-10-23 asset round.
pub const DEFAULT_CANDIDATES_DIR: &str = ".agents/asset-round-20261023/audio/radio";
/// Where review decisions persist.
pub const DEFAULT_DECISIONS_FILE: &str = ".agents/asset-round-20261023/music-review.json";
/// Keepers wanted per station.
pub const DEFAULT_TARGET: usize = 30;
/// `radio.gd` avoids repeating the last 12 tracks, so fewer than that repeats audibly.
pub const DEFAULT_MIN_TRACKS: usize = 12;
/// Loopback port for the review page.
pub const DEFAULT_PORT: u16 = 6780;

const AUDIO_EXTENSIONS: [&str; 3] = ["mp3", "wav", "ogg"];
const MANIFEST_FILE: &str = crate::MANIFEST_FILE;
const MAX_HEADER_BYTES: usize = 16 * 1024;
const MAX_BODY_BYTES: usize = 64 * 1024;
const PAGE: &str = include_str!("review.html");

/// Where a track lives.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Source {
    Shipped,
    Candidate,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Shipped => "shipped",
            Source::Candidate => "candidate",
        }
    }

    fn parse(raw: &str) -> Option<Self> {
        match raw {
            "shipped" => Some(Source::Shipped),
            "candidate" => Some(Source::Candidate),
            _ => None,
        }
    }
}

/// Paths the review tool reads and writes.
#[derive(Debug, Clone, PartialEq)]
pub struct ReviewConfig {
    pub stations_file: PathBuf,
    pub radio_dir: PathBuf,
    pub candidates_dir: PathBuf,
    pub decisions_file: PathBuf,
    pub target: usize,
}

impl Default for ReviewConfig {
    fn default() -> Self {
        ReviewConfig {
            stations_file: PathBuf::from(DEFAULT_STATIONS_FILE),
            radio_dir: PathBuf::from(DEFAULT_RADIO_DIR),
            candidates_dir: PathBuf::from(DEFAULT_CANDIDATES_DIR),
            decisions_file: PathBuf::from(DEFAULT_DECISIONS_FILE),
            target: DEFAULT_TARGET,
        }
    }
}

/// One playable file with whatever provenance the manifests hold for it.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Track {
    /// `<source>/<station>/<file>`, stable across restarts.
    pub id: String,
    pub station: String,
    pub source: Source,
    pub file: String,
    pub title: String,
    pub duration_ms: Option<u64>,
    pub prompt: Option<String>,
    pub model: Option<String>,
    pub bytes: u64,
    /// Manifest key and folder holding it, when provenance was found.
    pub manifest_key: Option<String>,
    #[serde(skip)]
    pub path: PathBuf,
    #[serde(skip)]
    pub entry: Option<ManifestEntry>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub color: String,
    pub tagline: String,
    pub tracks: Vec<Track>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Catalog {
    pub stations: Vec<Station>,
}

impl Catalog {
    pub fn track(&self, id: &str) -> Option<&Track> {
        self.stations
            .iter()
            .flat_map(|station| station.tracks.iter())
            .find(|track| track.id == id)
    }
}

/// A path segment the tool will join onto a root: no separators, no dot
/// prefixes, no parent references, and nothing outside a small ASCII set.
pub fn valid_segment(segment: &str) -> bool {
    !segment.is_empty()
        && segment.len() <= 128
        && !segment.starts_with('.')
        && !segment.contains("..")
        && segment
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
}

fn is_audio(file: &str) -> bool {
    Path::new(file)
        .extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| AUDIO_EXTENSIONS.contains(&ext.to_ascii_lowercase().as_str()))
}

#[derive(Deserialize)]
struct StationsFile {
    stations: Vec<StationInfo>,
}

#[derive(Deserialize)]
struct StationInfo {
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    color: String,
    #[serde(default)]
    tagline: String,
}

/// Audio files directly inside `dir`, sorted. Symlinks and odd names are skipped.
fn audio_files(dir: &Path) -> Result<Vec<String>, Error> {
    let read = match fs::read_dir(dir) {
        Ok(read) => read,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(err) => return Err(err.into()),
    };
    let mut files = Vec::new();
    for item in read {
        let item = item?;
        if !item.file_type()?.is_file() {
            continue;
        }
        let Some(name) = item.file_name().to_str().map(str::to_string) else {
            continue;
        };
        if valid_segment(&name) && is_audio(&name) {
            files.push(name);
        }
    }
    files.sort();
    Ok(files)
}

/// Manifests near a station folder, cached across one scan.
struct ManifestCache {
    loaded: HashMap<PathBuf, Option<crate::Manifest>>,
}

impl ManifestCache {
    fn new() -> Self {
        ManifestCache {
            loaded: HashMap::new(),
        }
    }

    /// Look for an entry whose `file` names this file, starting at the station
    /// folder and walking up to two levels, as `--out-dir` may have pointed at
    /// any of them.
    fn find(
        &mut self,
        station_dir: &Path,
        file: &str,
    ) -> Result<Option<(String, ManifestEntry)>, Error> {
        let mut dir = station_dir.to_path_buf();
        let mut relative = file.to_string();
        let mut parts: Vec<String> = Vec::new();
        for level in 0..3 {
            if level > 0 {
                let Some(name) = dir.file_name().and_then(|n| n.to_str()).map(str::to_string)
                else {
                    break;
                };
                parts.insert(0, name);
                relative = format!("{}/{file}", parts.join("/"));
                match dir.parent() {
                    Some(parent) => dir = parent.to_path_buf(),
                    None => break,
                }
            }
            if !self.loaded.contains_key(&dir) {
                let manifest = if dir.join(MANIFEST_FILE).is_file() {
                    Some(load_manifest(&dir)?)
                } else {
                    None
                };
                self.loaded.insert(dir.clone(), manifest);
            }
            if let Some(Some(manifest)) = self.loaded.get(&dir) {
                if let Some((key, entry)) = manifest
                    .entries
                    .iter()
                    .find(|(_, entry)| entry.file == relative)
                {
                    return Ok(Some((key.clone(), entry.clone())));
                }
            }
        }
        Ok(None)
    }
}

fn stem(file: &str) -> &str {
    file.rsplit_once('.').map_or(file, |(stem, _)| stem)
}

fn duration_ms(entry: &ManifestEntry) -> Option<u64> {
    entry
        .length_ms
        .map(u64::from)
        .or_else(|| entry.seconds.map(|s| (s * 1000.0).round() as u64))
}

/// Read stations and both track sources. Candidates already promoted are hidden.
pub fn scan_catalog(config: &ReviewConfig, decisions: &Decisions) -> Result<Catalog, Error> {
    let text = fs::read_to_string(&config.stations_file)?;
    let file: StationsFile = serde_json::from_str(&text).map_err(|err| {
        Error::Spec(format!(
            "unreadable stations file {}: {err}",
            config.stations_file.display()
        ))
    })?;
    let mut cache = ManifestCache::new();
    let mut stations = Vec::new();
    for info in file.stations {
        if !valid_segment(&info.id) {
            return Err(Error::Spec(format!("unsafe station id '{}'", info.id)));
        }
        let mut tracks = Vec::new();
        for (source, root) in [
            (Source::Shipped, &config.radio_dir),
            (Source::Candidate, &config.candidates_dir),
        ] {
            let dir = root.join(&info.id);
            for file in audio_files(&dir)? {
                let id = format!("{}/{}/{file}", source.as_str(), info.id);
                if source == Source::Candidate
                    && decisions
                        .decisions
                        .get(&id)
                        .is_some_and(|record| record.promoted_to.is_some())
                {
                    continue;
                }
                let path = dir.join(&file);
                let bytes = fs::metadata(&path)?.len();
                let found = cache.find(&dir, &file)?;
                let entry = found.as_ref().map(|(_, entry)| entry.clone());
                let title = entry
                    .as_ref()
                    .and_then(|entry| entry.title.clone())
                    .filter(|title| !title.is_empty())
                    .unwrap_or_else(|| stem(&file).to_string());
                tracks.push(Track {
                    id,
                    station: info.id.clone(),
                    source,
                    file,
                    title,
                    duration_ms: entry.as_ref().and_then(duration_ms),
                    prompt: entry.as_ref().map(|entry| entry.prompt.clone()),
                    model: entry.as_ref().map(|entry| entry.model.clone()),
                    bytes,
                    manifest_key: found.map(|(key, _)| key),
                    path,
                    entry,
                });
            }
        }
        stations.push(Station {
            name: if info.name.is_empty() {
                info.id.clone()
            } else {
                info.name
            },
            id: info.id,
            color: info.color,
            tagline: info.tagline,
            tracks,
        });
    }
    Ok(Catalog { stations })
}

/// Keep or reject.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Decision {
    Keep,
    Reject,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DecisionRecord {
    pub decision: Decision,
    pub at_unix: u64,
    /// Set on a candidate once promotion copied it into the shipped library.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub promoted_to: Option<String>,
}

/// Everything Nick decided, keyed by track id.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Decisions {
    pub version: u32,
    pub decisions: BTreeMap<String, DecisionRecord>,
}

impl Default for Decisions {
    fn default() -> Self {
        Decisions {
            version: 1,
            decisions: BTreeMap::new(),
        }
    }
}

impl Decisions {
    pub fn get(&self, id: &str) -> Option<Decision> {
        self.decisions.get(id).map(|record| record.decision)
    }

    /// Mark or, with `None`, unmark a track.
    pub fn set(&mut self, id: &str, decision: Option<Decision>, now: u64) {
        match decision {
            Some(decision) => {
                self.decisions.insert(
                    id.to_string(),
                    DecisionRecord {
                        decision,
                        at_unix: now,
                        promoted_to: None,
                    },
                );
            }
            None => {
                self.decisions.remove(id);
            }
        }
    }
}

/// A missing file is an empty review. A damaged one is an error, never overwritten.
pub fn load_decisions(path: &Path) -> Result<Decisions, Error> {
    match fs::read_to_string(path) {
        Ok(text) => serde_json::from_str(&text).map_err(|err| {
            Error::Spec(format!(
                "unreadable decisions file {}: {err}",
                path.display()
            ))
        }),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Decisions::default()),
        Err(err) => Err(err.into()),
    }
}

/// Atomic replace, so a crash mid-write leaves the previous file.
pub fn save_decisions(path: &Path, decisions: &Decisions) -> Result<(), Error> {
    let text =
        serde_json::to_string_pretty(decisions).map_err(|err| Error::Spec(err.to_string()))?;
    write_refusing_symlinks(path, format!("{text}\n").as_bytes())
}

// ---------------------------------------------------------------------------
// Promotion

/// One candidate keeper copied into the station.
#[derive(Debug, Clone, PartialEq)]
pub struct Addition {
    pub candidate_id: String,
    pub source: PathBuf,
    pub dest_file: String,
    pub manifest_key: String,
    pub entry: ManifestEntry,
}

/// One rejected shipped track removed from the station.
#[derive(Debug, Clone, PartialEq)]
pub struct Removal {
    pub track_id: String,
    pub file: String,
    pub manifest_key: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StationPlan {
    pub station: String,
    pub current: usize,
    pub additions: Vec<Addition>,
    pub removals: Vec<Removal>,
    /// Candidate keepers that cannot ship, with the reason.
    pub problems: Vec<String>,
}

impl StationPlan {
    pub fn final_count(&self) -> usize {
        self.current - self.removals.len() + self.additions.len()
    }

    pub fn changes(&self) -> bool {
        !self.additions.is_empty() || !self.removals.is_empty()
    }

    /// Only a station that loses tracks can be blocked by the minimum.
    pub fn below_min(&self, min_tracks: usize) -> bool {
        !self.removals.is_empty() && self.final_count() < min_tracks
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PromotionPlan {
    pub stations: Vec<StationPlan>,
}

/// Lowercase words joined by `-`, with any leading track number removed.
pub fn slugify(raw: &str) -> String {
    let trimmed = raw.trim_start_matches(|c: char| c.is_ascii_digit());
    let trimmed = if trimmed.len() < raw.len() {
        trimmed.trim_start_matches(['-', '_', ' '])
    } else {
        raw
    };
    let mut slug = String::new();
    for c in trimmed.chars() {
        if c.is_ascii_alphanumeric() {
            slug.push(c.to_ascii_lowercase());
        } else if !slug.ends_with('-') && !slug.is_empty() {
            slug.push('-');
        }
    }
    let slug = slug.trim_end_matches('-').to_string();
    if slug.is_empty() {
        "track".to_string()
    } else {
        slug
    }
}

/// `NN-slug` stems use a leading number; this returns it.
fn track_number(file: &str) -> Option<u32> {
    let digits: String = file.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok()
}

fn name_part(file: &str) -> String {
    let stem = stem(file);
    let rest = stem.trim_start_matches(|c: char| c.is_ascii_digit());
    rest.trim_start_matches('-').to_string()
}

fn extension(file: &str) -> String {
    file.rsplit_once('.')
        .map_or_else(|| "mp3".to_string(), |(_, ext)| ext.to_ascii_lowercase())
}

/// Work out what promotion would do. Pure: reads only the catalog and decisions.
pub fn plan_promotion(
    config: &ReviewConfig,
    catalog: &Catalog,
    decisions: &Decisions,
) -> PromotionPlan {
    let radio_name = config
        .radio_dir
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("radio")
        .to_string();
    let mut plan = PromotionPlan::default();
    for station in &catalog.stations {
        let shipped: Vec<&Track> = station
            .tracks
            .iter()
            .filter(|track| track.source == Source::Shipped)
            .collect();
        let mut next = shipped
            .iter()
            .filter_map(|track| track_number(&track.file))
            .max()
            .unwrap_or(0)
            + 1;
        let mut taken: BTreeSet<String> =
            shipped.iter().map(|track| name_part(&track.file)).collect();
        let mut station_plan = StationPlan {
            station: station.id.clone(),
            current: shipped.len(),
            additions: Vec::new(),
            removals: Vec::new(),
            problems: Vec::new(),
        };
        for track in &shipped {
            if decisions.get(&track.id) == Some(Decision::Reject) {
                station_plan.removals.push(Removal {
                    track_id: track.id.clone(),
                    file: track.file.clone(),
                    manifest_key: track.manifest_key.clone(),
                });
            }
        }
        for track in station
            .tracks
            .iter()
            .filter(|track| track.source == Source::Candidate)
        {
            if decisions.get(&track.id) != Some(Decision::Keep) {
                continue;
            }
            let Some(entry) = track.entry.clone() else {
                station_plan.problems.push(format!(
                    "{} has no audiogen manifest entry, so it has no provenance to ship",
                    track.id
                ));
                continue;
            };
            let base = slugify(stem(&track.file));
            let mut slug = base.clone();
            let mut suffix = 2;
            while taken.contains(&slug) {
                slug = format!("{base}-{suffix}");
                suffix += 1;
            }
            taken.insert(slug.clone());
            let dest_stem = format!("{next:02}-{slug}");
            next += 1;
            let dest_file = format!("{dest_stem}.{}", extension(&track.file));
            let manifest_key = format!("{radio_name}/{}/{dest_stem}", station.id);
            let mut entry = entry;
            entry.file = format!("{radio_name}/{}/{dest_file}", station.id);
            entry.bytes = track.bytes;
            station_plan.additions.push(Addition {
                candidate_id: track.id.clone(),
                source: track.path.clone(),
                dest_file,
                manifest_key,
                entry,
            });
        }
        plan.stations.push(station_plan);
    }
    plan
}

/// Human-readable plan, one block per station that changes or has problems.
pub fn describe_plan(plan: &PromotionPlan, min_tracks: usize, force: bool) -> String {
    let mut out = String::new();
    let mut any = false;
    for station in &plan.stations {
        if !station.changes() && station.problems.is_empty() {
            continue;
        }
        any = true;
        let _ = writeln!(
            out,
            "{}: {} -> {} tracks (+{} -{}){}",
            station.station,
            station.current,
            station.final_count(),
            station.additions.len(),
            station.removals.len(),
            if station.below_min(min_tracks) {
                if force {
                    format!(" below minimum {min_tracks}, forced")
                } else {
                    format!(" REFUSED: below minimum {min_tracks} (use --force)")
                }
            } else {
                String::new()
            }
        );
        for addition in &station.additions {
            let _ = writeln!(
                out,
                "  add    {} <- {}",
                addition.dest_file, addition.candidate_id
            );
        }
        for removal in &station.removals {
            let _ = writeln!(out, "  remove {}", removal.file);
        }
        for problem in &station.problems {
            let _ = writeln!(out, "  BLOCKED {problem}");
        }
    }
    if !any {
        out.push_str("nothing to promote: no candidate keepers and no rejected shipped tracks\n");
    }
    out
}

/// Why `apply_promotion` must refuse, if anything.
pub fn promotion_refusal(plan: &PromotionPlan, min_tracks: usize, force: bool) -> Option<String> {
    let problems: Vec<&String> = plan
        .stations
        .iter()
        .flat_map(|station| station.problems.iter())
        .collect();
    if !problems.is_empty() {
        return Some(format!(
            "{} keeper(s) lack provenance; fix their manifests or unmark them",
            problems.len()
        ));
    }
    if force {
        return None;
    }
    let low: Vec<String> = plan
        .stations
        .iter()
        .filter(|station| station.below_min(min_tracks))
        .map(|station| format!("{} ({})", station.station, station.final_count()))
        .collect();
    if low.is_empty() {
        None
    } else {
        Some(format!(
            "would drop below {min_tracks} tracks: {}; pass --force to allow",
            low.join(", ")
        ))
    }
}

/// Copy keepers in, delete rejected shipped files and their `.import`
/// sidecars, update the shipped manifest, and record the result in the
/// decisions file so a second run does not copy anything twice.
pub fn apply_promotion(
    config: &ReviewConfig,
    plan: &PromotionPlan,
    decisions: &mut Decisions,
    now: u64,
) -> Result<(), Error> {
    let audio_root = config
        .radio_dir
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_default();
    validate_promotion(config, plan)?;
    let mut manifest = load_manifest(&audio_root)?;
    for station in &plan.stations {
        let dir = config.radio_dir.join(&station.station);
        for addition in &station.additions {
            let bytes = fs::read(&addition.source)?;
            write_refusing_symlinks(&dir.join(&addition.dest_file), &bytes)?;
            manifest
                .entries
                .insert(addition.manifest_key.clone(), addition.entry.clone());
            if let Some(record) = decisions.decisions.get_mut(&addition.candidate_id) {
                record.promoted_to = Some(addition.manifest_key.clone());
            }
            decisions.set(
                &format!("shipped/{}/{}", station.station, addition.dest_file),
                Some(Decision::Keep),
                now,
            );
        }
        for removal in &station.removals {
            fs::remove_file(dir.join(&removal.file))?;
            let sidecar = dir.join(format!("{}.import", removal.file));
            if fs::symlink_metadata(&sidecar).is_ok() {
                fs::remove_file(&sidecar)?;
            }
            if let Some(key) = &removal.manifest_key {
                manifest.entries.remove(key);
            }
            decisions.decisions.remove(&removal.track_id);
        }
    }
    save_manifest(&audio_root, &manifest)?;
    save_decisions(&config.decisions_file, decisions)?;
    Ok(())
}

/// Check every path before touching anything, so a bad plan changes nothing.
fn validate_promotion(config: &ReviewConfig, plan: &PromotionPlan) -> Result<(), Error> {
    for station in &plan.stations {
        if !valid_segment(&station.station) {
            return Err(Error::InvalidArgument(format!(
                "unsafe station id '{}'",
                station.station
            )));
        }
        let dir = config.radio_dir.join(&station.station);
        for addition in &station.additions {
            if !valid_segment(&addition.dest_file) {
                return Err(Error::InvalidArgument(format!(
                    "unsafe destination '{}'",
                    addition.dest_file
                )));
            }
            crate::validate_name(&addition.manifest_key)?;
            let dest = dir.join(&addition.dest_file);
            if fs::symlink_metadata(&dest).is_ok() {
                return Err(Error::InvalidArgument(format!(
                    "{} already exists; refusing to overwrite",
                    dest.display()
                )));
            }
            ensure_inside(&config.candidates_dir, &addition.source)?;
        }
        for removal in &station.removals {
            if !valid_segment(&removal.file) {
                return Err(Error::InvalidArgument(format!(
                    "unsafe file '{}'",
                    removal.file
                )));
            }
            ensure_inside(&config.radio_dir, &dir.join(&removal.file))?;
        }
    }
    Ok(())
}

/// Refuse a path that resolves outside `root` (symlinks included).
pub fn ensure_inside(root: &Path, path: &Path) -> Result<(), Error> {
    let root = fs::canonicalize(root)?;
    let resolved = fs::canonicalize(path)?;
    if resolved.starts_with(&root) && resolved != root {
        Ok(())
    } else {
        Err(Error::InvalidArgument(format!(
            "{} is outside {}",
            path.display(),
            root.display()
        )))
    }
}

// ---------------------------------------------------------------------------
// HTTP

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpRequest {
    pub method: String,
    pub path: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl HttpRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpResponse {
    pub status: u16,
    pub content_type: &'static str,
    pub headers: Vec<(&'static str, String)>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    fn new(status: u16, content_type: &'static str, body: Vec<u8>) -> Self {
        HttpResponse {
            status,
            content_type,
            headers: Vec::new(),
            body,
        }
    }

    fn text(status: u16, message: &str) -> Self {
        Self::new(
            status,
            "text/plain; charset=utf-8",
            message.as_bytes().to_vec(),
        )
    }

    fn json(value: &serde_json::Value) -> Self {
        Self::new(
            200,
            "application/json",
            serde_json::to_vec(value).unwrap_or_default(),
        )
    }

    /// Serialize with `Connection: close`; one request per connection.
    pub fn write_to(&self, out: &mut dyn Write) -> std::io::Result<()> {
        let reason = match self.status {
            200 => "OK",
            206 => "Partial Content",
            400 => "Bad Request",
            403 => "Forbidden",
            404 => "Not Found",
            405 => "Method Not Allowed",
            413 => "Payload Too Large",
            415 => "Unsupported Media Type",
            416 => "Range Not Satisfiable",
            _ => "Internal Server Error",
        };
        let mut head = format!(
            "HTTP/1.1 {} {reason}\r\nContent-Type: {}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n",
            self.status,
            self.content_type,
            self.body.len()
        );
        for (name, value) in &self.headers {
            let _ = write!(head, "{name}: {value}\r\n");
        }
        head.push_str("\r\n");
        out.write_all(head.as_bytes())?;
        out.write_all(&self.body)?;
        out.flush()
    }
}

/// Parse one request. Header and body sizes are capped.
pub fn read_request(reader: &mut dyn BufRead) -> Result<HttpRequest, Error> {
    let mut head = Vec::new();
    loop {
        let mut line = Vec::new();
        let read =
            Read::take(&mut *reader, MAX_HEADER_BYTES as u64).read_until(b'\n', &mut line)?;
        if read == 0 {
            return Err(Error::InvalidArgument("connection closed".into()));
        }
        if line == b"\r\n" || line == b"\n" {
            break;
        }
        head.extend_from_slice(&line);
        if head.len() > MAX_HEADER_BYTES {
            return Err(Error::InvalidArgument("headers too large".into()));
        }
    }
    let head = String::from_utf8(head)
        .map_err(|_| Error::InvalidArgument("headers are not UTF-8".into()))?;
    let mut lines = head.lines();
    let request_line = lines.next().unwrap_or_default();
    let mut parts = request_line.split_whitespace();
    let (Some(method), Some(path)) = (parts.next(), parts.next()) else {
        return Err(Error::InvalidArgument("malformed request line".into()));
    };
    let mut headers = Vec::new();
    for line in lines {
        if let Some((name, value)) = line.split_once(':') {
            headers.push((name.trim().to_string(), value.trim().to_string()));
        }
    }
    let mut request = HttpRequest {
        method: method.to_string(),
        path: path.to_string(),
        headers,
        body: Vec::new(),
    };
    let length: usize = match request.header("content-length") {
        Some(raw) => raw
            .parse()
            .map_err(|_| Error::InvalidArgument("bad content-length".into()))?,
        None => 0,
    };
    if length > MAX_BODY_BYTES {
        return Err(Error::InvalidArgument("body too large".into()));
    }
    request.body = vec![0; length];
    reader.read_exact(&mut request.body)?;
    Ok(request)
}

/// Decode `%XX` escapes. Invalid escapes or non-UTF-8 results are refused.
pub fn percent_decode(raw: &str) -> Option<String> {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = raw.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// `bytes=a-b`, `bytes=a-` or `bytes=-n` against a file of `len` bytes.
pub fn parse_range(header: &str, len: u64) -> Option<(u64, u64)> {
    let spec = header.trim().strip_prefix("bytes=")?;
    if spec.contains(',') || len == 0 {
        return None;
    }
    let (start, end) = spec.split_once('-')?;
    let (start, end) = if start.is_empty() {
        let suffix: u64 = end.parse().ok()?;
        if suffix == 0 {
            return None;
        }
        (len.saturating_sub(suffix), len - 1)
    } else {
        let start: u64 = start.parse().ok()?;
        let end = if end.is_empty() {
            len - 1
        } else {
            end.parse::<u64>().ok()?.min(len - 1)
        };
        (start, end)
    };
    (start <= end && start < len).then_some((start, end))
}

fn audio_type(file: &str) -> &'static str {
    match extension(file).as_str() {
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        "ogg" => "audio/ogg",
        _ => "application/octet-stream",
    }
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// State behind the review page.
pub struct ReviewServer {
    pub config: ReviewConfig,
    pub decisions: Decisions,
    pub catalog: Catalog,
    port: u16,
}

#[derive(Deserialize)]
struct DecisionBody {
    id: String,
    decision: Option<Decision>,
}

impl ReviewServer {
    pub fn new(config: ReviewConfig, port: u16) -> Result<Self, Error> {
        let decisions = load_decisions(&config.decisions_file)?;
        let catalog = scan_catalog(&config, &decisions)?;
        Ok(ReviewServer {
            config,
            decisions,
            catalog,
            port,
        })
    }

    /// Only loopback hosts on our own port, which blocks DNS rebinding.
    fn host_allowed(&self, request: &HttpRequest) -> bool {
        let Some(host) = request.header("host") else {
            return false;
        };
        [
            format!("127.0.0.1:{}", self.port),
            format!("localhost:{}", self.port),
        ]
        .iter()
        .any(|allowed| allowed.eq_ignore_ascii_case(host))
    }

    fn origin_allowed(&self, request: &HttpRequest) -> bool {
        match request.header("origin") {
            None => true,
            Some(origin) => [
                format!("http://127.0.0.1:{}", self.port),
                format!("http://localhost:{}", self.port),
            ]
            .iter()
            .any(|allowed| allowed.eq_ignore_ascii_case(origin)),
        }
    }

    pub fn handle(&mut self, request: &HttpRequest) -> HttpResponse {
        if !self.host_allowed(request) {
            return HttpResponse::text(403, "forbidden host");
        }
        let path = request.path.split('?').next().unwrap_or_default();
        match (request.method.as_str(), path) {
            ("GET", "/") => HttpResponse::new(200, "text/html; charset=utf-8", PAGE.into()),
            ("GET", "/api/state") => self.state(),
            ("POST", "/api/decision") => self.decide(request),
            ("GET", _) if path.starts_with("/audio/") => self.audio(request, &path[7..]),
            ("GET" | "POST", _) => HttpResponse::text(404, "not found"),
            _ => HttpResponse::text(405, "method not allowed"),
        }
    }

    fn state(&mut self) -> HttpResponse {
        match scan_catalog(&self.config, &self.decisions) {
            Ok(catalog) => self.catalog = catalog,
            Err(err) => return HttpResponse::text(500, &err.to_string()),
        }
        let stations: Vec<serde_json::Value> = self
            .catalog
            .stations
            .iter()
            .map(|station| {
                let tracks: Vec<serde_json::Value> = station
                    .tracks
                    .iter()
                    .map(|track| {
                        let mut value = serde_json::to_value(track).unwrap_or_default();
                        value["decision"] =
                            serde_json::to_value(self.decisions.get(&track.id)).unwrap_or_default();
                        value
                    })
                    .collect();
                serde_json::json!({
                    "id": station.id,
                    "name": station.name,
                    "color": station.color,
                    "tagline": station.tagline,
                    "tracks": tracks,
                })
            })
            .collect();
        HttpResponse::json(&serde_json::json!({
            "target": self.config.target,
            "decisions_file": self.config.decisions_file.display().to_string(),
            "stations": stations,
        }))
    }

    fn decide(&mut self, request: &HttpRequest) -> HttpResponse {
        if !self.origin_allowed(request) {
            return HttpResponse::text(403, "forbidden origin");
        }
        let json = request
            .header("content-type")
            .is_some_and(|value| value.starts_with("application/json"));
        if !json {
            return HttpResponse::text(415, "expected application/json");
        }
        let body: DecisionBody = match serde_json::from_slice(&request.body) {
            Ok(body) => body,
            Err(err) => return HttpResponse::text(400, &format!("bad body: {err}")),
        };
        if self.catalog.track(&body.id).is_none() {
            return HttpResponse::text(404, "unknown track");
        }
        let previous = self.decisions.clone();
        self.decisions.set(&body.id, body.decision, now_unix());
        if let Err(err) = save_decisions(&self.config.decisions_file, &self.decisions) {
            self.decisions = previous;
            return HttpResponse::text(500, &format!("could not save: {err}"));
        }
        HttpResponse::json(&serde_json::json!({
            "id": body.id,
            "decision": body.decision,
        }))
    }

    fn audio(&self, request: &HttpRequest, rest: &str) -> HttpResponse {
        let segments: Option<Vec<String>> = rest.split('/').map(percent_decode).collect();
        let Some(segments) = segments else {
            return HttpResponse::text(400, "bad escape");
        };
        let [source, station, file] = segments.as_slice() else {
            return HttpResponse::text(404, "not found");
        };
        if Source::parse(source).is_none() || !valid_segment(station) || !valid_segment(file) {
            return HttpResponse::text(404, "not found");
        }
        let id = format!("{source}/{station}/{file}");
        let Some(track) = self.catalog.track(&id) else {
            return HttpResponse::text(404, "not found");
        };
        let root = match track.source {
            Source::Shipped => &self.config.radio_dir,
            Source::Candidate => &self.config.candidates_dir,
        };
        if ensure_inside(root, &track.path).is_err() {
            return HttpResponse::text(403, "outside the review roots");
        }
        match read_audio(&track.path, request.header("range")) {
            Ok(mut response) => {
                response.content_type = audio_type(&track.file);
                response
            }
            Err(err) => HttpResponse::text(500, &err.to_string()),
        }
    }
}

fn read_audio(path: &Path, range: Option<&str>) -> Result<HttpResponse, Error> {
    let mut file = fs::File::open(path)?;
    let len = file.metadata()?.len();
    let mut response = match range {
        None => {
            let mut body = Vec::with_capacity(len as usize);
            file.read_to_end(&mut body)?;
            HttpResponse::new(200, "", body)
        }
        Some(header) => match parse_range(header, len) {
            None => {
                let mut response = HttpResponse::new(416, "", Vec::new());
                response
                    .headers
                    .push(("Content-Range", format!("bytes */{len}")));
                return Ok(response);
            }
            Some((start, end)) => {
                file.seek(SeekFrom::Start(start))?;
                let mut body = vec![0; (end - start + 1) as usize];
                file.read_exact(&mut body)?;
                let mut response = HttpResponse::new(206, "", body);
                response
                    .headers
                    .push(("Content-Range", format!("bytes {start}-{end}/{len}")));
                response
            }
        },
    };
    response.headers.push(("Accept-Ranges", "bytes".into()));
    Ok(response)
}

fn handle_connection(stream: TcpStream, server: &Mutex<ReviewServer>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(30)));
    let Ok(reader_stream) = stream.try_clone() else {
        return;
    };
    let mut reader = std::io::BufReader::new(reader_stream);
    let response = match read_request(&mut reader) {
        Ok(request) => server
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .handle(&request),
        Err(err) => HttpResponse::text(400, &err.to_string()),
    };
    let mut stream = stream;
    let _ = response.write_to(&mut stream);
}

/// Accept connections until the listener fails. One thread per connection.
pub fn serve(listener: TcpListener, server: ReviewServer) -> Result<(), Error> {
    let server = Arc::new(Mutex::new(server));
    for stream in listener.incoming() {
        let stream = stream?;
        let server = Arc::clone(&server);
        std::thread::spawn(move || handle_connection(stream, &server));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Manifest;
    use std::io::Cursor;

    struct Fixture {
        root: PathBuf,
        config: ReviewConfig,
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    fn entry(file: &str, title: &str) -> ManifestEntry {
        ManifestEntry {
            kind: "music".into(),
            file: file.into(),
            prompt: format!("prompt for {title}"),
            model: "music_v2_5".into(),
            format: "mp3_44100_128".into(),
            title: Some(title.into()),
            voice: None,
            seconds: None,
            length_ms: Some(120_000),
            looping: false,
            channels: 0,
            bytes: 3,
            generated_unix: 1,
        }
    }

    /// Two stations. rock ships 01-a and 02-b; candidates hold 05-new-song
    /// (with provenance in the round manifest) and stray (none).
    fn fixture(name: &str) -> Fixture {
        let root = std::env::temp_dir().join(format!("fragr-review-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let audio = root.join("client/assets/audio");
        let radio = audio.join("radio");
        let cand_audio = root.join("round/audio");
        let candidates = cand_audio.join("radio");
        fs::create_dir_all(radio.join("rock")).unwrap();
        fs::create_dir_all(radio.join("chill")).unwrap();
        fs::create_dir_all(candidates.join("rock")).unwrap();
        fs::write(
            radio.join("stations.json"),
            r##"{"stations": [{"id": "rock", "name": "Rock", "color": "#7A3A22"}, {"id": "chill"}]}"##,
        )
        .unwrap();
        for file in ["01-a.mp3", "02-b.mp3"] {
            fs::write(radio.join("rock").join(file), b"abc").unwrap();
            fs::write(radio.join("rock").join(format!("{file}.import")), b"x").unwrap();
        }
        fs::write(radio.join("rock/notes.txt"), b"ignored").unwrap();
        let mut shipped = Manifest::default();
        shipped
            .entries
            .insert("radio/rock/01-a".into(), entry("radio/rock/01-a.mp3", "A"));
        shipped
            .entries
            .insert("radio/rock/02-b".into(), entry("radio/rock/02-b.mp3", "B"));
        save_manifest(&audio, &shipped).unwrap();
        fs::write(candidates.join("rock/05-new-song.mp3"), b"newsong").unwrap();
        fs::write(candidates.join("rock/stray.mp3"), b"zz").unwrap();
        let mut round = Manifest::default();
        round.entries.insert(
            "radio/rock/05-new-song".into(),
            entry("radio/rock/05-new-song.mp3", "New Song"),
        );
        save_manifest(&cand_audio, &round).unwrap();
        let config = ReviewConfig {
            stations_file: radio.join("stations.json"),
            radio_dir: radio,
            candidates_dir: candidates,
            decisions_file: root.join("round/music-review.json"),
            target: 30,
        };
        Fixture { root, config }
    }

    #[test]
    fn scans_both_sources_with_provenance() {
        let fx = fixture("scan");
        let catalog = scan_catalog(&fx.config, &Decisions::default()).unwrap();
        assert_eq!(catalog.stations.len(), 2);
        let rock = &catalog.stations[0];
        assert_eq!(rock.name, "Rock");
        assert_eq!(catalog.stations[1].name, "chill");
        let ids: Vec<&str> = rock.tracks.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(
            ids,
            [
                "shipped/rock/01-a.mp3",
                "shipped/rock/02-b.mp3",
                "candidate/rock/05-new-song.mp3",
                "candidate/rock/stray.mp3"
            ]
        );
        assert_eq!(rock.tracks[0].title, "A");
        assert_eq!(rock.tracks[0].duration_ms, Some(120_000));
        assert_eq!(
            rock.tracks[0].manifest_key.as_deref(),
            Some("radio/rock/01-a")
        );
        assert_eq!(rock.tracks[2].title, "New Song");
        assert_eq!(
            rock.tracks[2].prompt.as_deref(),
            Some("prompt for New Song")
        );
        assert_eq!(rock.tracks[3].title, "stray");
        assert!(rock.tracks[3].entry.is_none());
    }

    #[test]
    fn station_ids_must_be_safe() {
        let fx = fixture("unsafe-station");
        fs::write(
            &fx.config.stations_file,
            r#"{"stations": [{"id": "../x"}]}"#,
        )
        .unwrap();
        assert!(matches!(
            scan_catalog(&fx.config, &Decisions::default()),
            Err(Error::Spec(_))
        ));
    }

    #[test]
    fn decisions_persist_and_survive_reload() {
        let fx = fixture("persist");
        let path = &fx.config.decisions_file;
        assert_eq!(load_decisions(path).unwrap(), Decisions::default());
        let mut decisions = Decisions::default();
        decisions.set("shipped/rock/01-a.mp3", Some(Decision::Reject), 10);
        decisions.set("candidate/rock/05-new-song.mp3", Some(Decision::Keep), 11);
        save_decisions(path, &decisions).unwrap();
        let reloaded = load_decisions(path).unwrap();
        assert_eq!(reloaded, decisions);
        assert_eq!(
            reloaded.get("shipped/rock/01-a.mp3"),
            Some(Decision::Reject)
        );
        let text = fs::read_to_string(path).unwrap();
        assert!(text.contains("\"reject\""), "{text}");
        decisions.set("shipped/rock/01-a.mp3", None, 12);
        save_decisions(path, &decisions).unwrap();
        assert_eq!(
            load_decisions(path).unwrap().get("shipped/rock/01-a.mp3"),
            None
        );
        fs::write(path, "{not json").unwrap();
        assert!(matches!(load_decisions(path), Err(Error::Spec(_))));
    }

    #[test]
    fn segments_and_slugs() {
        for good in ["rock", "01-a.mp3", "x_y.wav"] {
            assert!(valid_segment(good), "{good}");
        }
        for bad in [
            "", ".", "..", "../x", "a/b", ".hidden", "a..b", "a\\b", "a b", "%2e",
        ] {
            assert!(!valid_segment(bad), "{bad}");
        }
        assert_eq!(slugify("05-new-song"), "new-song");
        assert_eq!(slugify("Neon Rain!!"), "neon-rain");
        assert_eq!(slugify("12"), "track");
        assert_eq!(slugify("2049_blade"), "blade");
        assert_eq!(slugify("abc"), "abc");
    }

    #[test]
    fn plans_additions_removals_and_minimum() {
        let fx = fixture("plan");
        let mut decisions = Decisions::default();
        decisions.set("candidate/rock/05-new-song.mp3", Some(Decision::Keep), 1);
        decisions.set("shipped/rock/02-b.mp3", Some(Decision::Reject), 1);
        decisions.set("shipped/rock/01-a.mp3", Some(Decision::Keep), 1);
        let catalog = scan_catalog(&fx.config, &decisions).unwrap();
        let plan = plan_promotion(&fx.config, &catalog, &decisions);
        let rock = &plan.stations[0];
        assert_eq!(rock.current, 2);
        assert_eq!(rock.additions.len(), 1);
        assert_eq!(rock.additions[0].dest_file, "03-new-song.mp3");
        assert_eq!(rock.additions[0].manifest_key, "radio/rock/03-new-song");
        assert_eq!(rock.additions[0].entry.file, "radio/rock/03-new-song.mp3");
        assert_eq!(rock.additions[0].entry.bytes, 7);
        assert_eq!(rock.removals.len(), 1);
        assert_eq!(rock.removals[0].file, "02-b.mp3");
        assert_eq!(rock.final_count(), 2);
        assert!(!plan.stations[1].changes());
        assert!(rock.below_min(3));
        assert!(!rock.below_min(2));
        assert!(promotion_refusal(&plan, 3, false)
            .unwrap()
            .contains("rock (2)"));
        assert_eq!(promotion_refusal(&plan, 3, true), None);
        assert_eq!(promotion_refusal(&plan, 2, false), None);
        let text = describe_plan(&plan, 3, false);
        assert!(
            text.contains("rock: 2 -> 2 tracks (+1 -1) REFUSED"),
            "{text}"
        );
        assert!(text.contains("add    03-new-song.mp3 <- candidate/rock/05-new-song.mp3"));
        assert!(text.contains("remove 02-b.mp3"));
        assert!(describe_plan(&plan, 3, true).contains("forced"));
        assert!(describe_plan(&PromotionPlan::default(), 3, false).contains("nothing to promote"));
    }

    #[test]
    fn keepers_without_provenance_block_and_slugs_do_not_collide() {
        let fx = fixture("provenance");
        fs::write(fx.config.candidates_dir.join("rock/09-a.mp3"), b"q").unwrap();
        let mut round = load_manifest(fx.config.candidates_dir.parent().unwrap()).unwrap();
        round.entries.insert(
            "radio/rock/09-a".into(),
            entry("radio/rock/09-a.mp3", "Another A"),
        );
        save_manifest(fx.config.candidates_dir.parent().unwrap(), &round).unwrap();
        let mut decisions = Decisions::default();
        decisions.set("candidate/rock/stray.mp3", Some(Decision::Keep), 1);
        decisions.set("candidate/rock/09-a.mp3", Some(Decision::Keep), 1);
        let catalog = scan_catalog(&fx.config, &decisions).unwrap();
        let plan = plan_promotion(&fx.config, &catalog, &decisions);
        let rock = &plan.stations[0];
        assert_eq!(rock.additions[0].dest_file, "03-a-2.mp3");
        assert_eq!(rock.problems.len(), 1);
        assert!(rock.problems[0].contains("candidate/rock/stray.mp3"));
        assert!(promotion_refusal(&plan, 0, true)
            .unwrap()
            .contains("provenance"));
        assert!(describe_plan(&plan, 0, false).contains("BLOCKED"));
    }

    #[test]
    fn apply_copies_removes_and_is_idempotent() {
        let fx = fixture("apply");
        let mut decisions = Decisions::default();
        decisions.set("candidate/rock/05-new-song.mp3", Some(Decision::Keep), 1);
        decisions.set("shipped/rock/02-b.mp3", Some(Decision::Reject), 1);
        save_decisions(&fx.config.decisions_file, &decisions).unwrap();
        let catalog = scan_catalog(&fx.config, &decisions).unwrap();
        let plan = plan_promotion(&fx.config, &catalog, &decisions);
        apply_promotion(&fx.config, &plan, &mut decisions, 99).unwrap();
        let rock = fx.config.radio_dir.join("rock");
        assert_eq!(fs::read(rock.join("03-new-song.mp3")).unwrap(), b"newsong");
        assert!(!rock.join("02-b.mp3").exists());
        assert!(!rock.join("02-b.mp3.import").exists());
        assert!(rock.join("01-a.mp3").exists());
        let manifest = load_manifest(fx.config.radio_dir.parent().unwrap()).unwrap();
        assert!(!manifest.entries.contains_key("radio/rock/02-b"));
        let added = &manifest.entries["radio/rock/03-new-song"];
        assert_eq!(added.file, "radio/rock/03-new-song.mp3");
        assert_eq!(added.prompt, "prompt for New Song");
        let saved = load_decisions(&fx.config.decisions_file).unwrap();
        assert_eq!(
            saved.decisions["candidate/rock/05-new-song.mp3"]
                .promoted_to
                .as_deref(),
            Some("radio/rock/03-new-song")
        );
        assert_eq!(
            saved.get("shipped/rock/03-new-song.mp3"),
            Some(Decision::Keep)
        );
        assert_eq!(saved.get("shipped/rock/02-b.mp3"), None);
        // A second pass finds nothing left to do.
        let catalog = scan_catalog(&fx.config, &saved).unwrap();
        assert!(catalog.track("candidate/rock/05-new-song.mp3").is_none());
        let again = plan_promotion(&fx.config, &catalog, &saved);
        assert!(again.stations.iter().all(|s| !s.changes()));
    }

    #[test]
    fn apply_refuses_to_overwrite_or_escape() {
        let fx = fixture("escape");
        let mut decisions = Decisions::default();
        decisions.set("candidate/rock/05-new-song.mp3", Some(Decision::Keep), 1);
        let catalog = scan_catalog(&fx.config, &decisions).unwrap();
        let plan = plan_promotion(&fx.config, &catalog, &decisions);
        fs::write(fx.config.radio_dir.join("rock/03-new-song.mp3"), b"x").unwrap();
        assert!(apply_promotion(&fx.config, &plan, &mut decisions.clone(), 1).is_err());
        fs::remove_file(fx.config.radio_dir.join("rock/03-new-song.mp3")).unwrap();
        let mut escaping = plan.clone();
        escaping.stations[0].additions[0].source =
            fx.root.join("client/assets/audio/radio/stations.json");
        let err = apply_promotion(&fx.config, &escaping, &mut decisions.clone(), 1).unwrap_err();
        assert!(err.to_string().contains("outside"), "{err}");
        let mut traversal = plan.clone();
        traversal.stations[0].additions[0].dest_file = "../evil.mp3".into();
        assert!(apply_promotion(&fx.config, &traversal, &mut decisions.clone(), 1).is_err());
        let mut bad_station = plan;
        bad_station.stations[0].station = "..".into();
        assert!(apply_promotion(&fx.config, &bad_station, &mut decisions, 1).is_err());
        assert!(ensure_inside(&fx.config.radio_dir, &fx.config.radio_dir).is_err());
    }

    fn get(path: &str) -> HttpRequest {
        HttpRequest {
            method: "GET".into(),
            path: path.into(),
            headers: vec![("Host".into(), "127.0.0.1:6780".into())],
            body: Vec::new(),
        }
    }

    fn post(body: &str) -> HttpRequest {
        HttpRequest {
            method: "POST".into(),
            path: "/api/decision".into(),
            headers: vec![
                ("Host".into(), "localhost:6780".into()),
                ("Content-Type".into(), "application/json".into()),
                ("Origin".into(), "http://localhost:6780".into()),
            ],
            body: body.as_bytes().to_vec(),
        }
    }

    #[test]
    fn routes_page_state_and_decisions() {
        let fx = fixture("routes");
        let mut server = ReviewServer::new(fx.config.clone(), 6780).unwrap();
        let page = server.handle(&get("/"));
        assert_eq!(page.status, 200);
        assert!(String::from_utf8_lossy(&page.body).contains("<title>"));
        let state = server.handle(&get("/api/state?x=1"));
        assert_eq!(state.status, 200);
        let value: serde_json::Value = serde_json::from_slice(&state.body).unwrap();
        assert_eq!(value["target"], 30);
        assert_eq!(value["stations"][0]["tracks"][0]["source"], "shipped");
        assert!(value["stations"][0]["tracks"][0]["decision"].is_null());
        assert!(value["stations"][0]["tracks"][0].get("path").is_none());

        let keep = server.handle(&post(
            r#"{"id": "shipped/rock/01-a.mp3", "decision": "keep"}"#,
        ));
        assert_eq!(keep.status, 200);
        // Persisted immediately, and a fresh server sees it.
        let fresh = ReviewServer::new(fx.config.clone(), 6780).unwrap();
        assert_eq!(
            fresh.decisions.get("shipped/rock/01-a.mp3"),
            Some(Decision::Keep)
        );
        let unmark = server.handle(&post(
            r#"{"id": "shipped/rock/01-a.mp3", "decision": null}"#,
        ));
        assert_eq!(unmark.status, 200);
        assert_eq!(
            load_decisions(&fx.config.decisions_file)
                .unwrap()
                .get("shipped/rock/01-a.mp3"),
            None
        );

        assert_eq!(
            server
                .handle(&post(
                    r#"{"id": "shipped/rock/nope.mp3", "decision": "keep"}"#
                ))
                .status,
            404
        );
        assert_eq!(server.handle(&post(r#"{"id": 3}"#)).status, 400);
        let mut wrong_type = post(r#"{"id": "shipped/rock/01-a.mp3", "decision": "keep"}"#);
        wrong_type.headers[1].1 = "text/plain".into();
        assert_eq!(server.handle(&wrong_type).status, 415);
        let mut cross_site = post(r#"{"id": "shipped/rock/01-a.mp3", "decision": "keep"}"#);
        cross_site.headers[2].1 = "http://evil.example".into();
        assert_eq!(server.handle(&cross_site).status, 403);
        let mut rebind = get("/api/state");
        rebind.headers[0].1 = "evil.example:6780".into();
        assert_eq!(server.handle(&rebind).status, 403);
        let mut no_host = get("/");
        no_host.headers.clear();
        assert_eq!(server.handle(&no_host).status, 403);
        assert_eq!(server.handle(&get("/missing")).status, 404);
        let mut delete = get("/");
        delete.method = "DELETE".into();
        assert_eq!(server.handle(&delete).status, 405);
    }

    #[test]
    fn serves_audio_with_ranges_and_refuses_traversal() {
        let fx = fixture("audio");
        fs::write(fx.root.join("secret.mp3"), b"secret").unwrap();
        let mut server = ReviewServer::new(fx.config.clone(), 6780).unwrap();
        let full = server.handle(&get("/audio/candidate/rock/05-new-song.mp3"));
        assert_eq!(full.status, 200);
        assert_eq!(full.content_type, "audio/mpeg");
        assert_eq!(full.body, b"newsong");
        let mut ranged = get("/audio/candidate/rock/05-new-song.mp3");
        ranged.headers.push(("Range".into(), "bytes=3-".into()));
        let part = server.handle(&ranged);
        assert_eq!(part.status, 206);
        assert_eq!(part.body, b"song");
        assert!(part
            .headers
            .contains(&("Content-Range", "bytes 3-6/7".into())));
        ranged.headers[1].1 = "bytes=50-60".into();
        assert_eq!(server.handle(&ranged).status, 416);
        assert_eq!(
            server.handle(&get("/audio/shipped/rock/01-a.mp3")).body,
            b"abc"
        );
        for bad in [
            "/audio/shipped/../../secret.mp3",
            "/audio/shipped/rock/..%2F..%2F..%2F..%2Fsecret.mp3",
            "/audio/shipped/rock/%2e%2e",
            "/audio/other/rock/01-a.mp3",
            "/audio/shipped/rock/notes.txt",
            "/audio/shipped/rock/01-a.mp3/extra",
            "/audio/shipped/rock/stations.json",
        ] {
            let status = server.handle(&get(bad)).status;
            assert!(status == 404 || status == 400, "{bad} -> {status}");
        }
        assert_eq!(server.handle(&get("/audio/shipped/rock/%zz")).status, 400);
        // A catalog entry whose file was swapped for something outside is refused.
        server.catalog.stations[0].tracks[0].path = fx.root.join("secret.mp3");
        assert_eq!(
            server.handle(&get("/audio/shipped/rock/01-a.mp3")).status,
            403
        );
    }

    #[test]
    fn parses_requests_ranges_and_escapes() {
        let raw =
            b"POST /api/decision HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Length: 4\r\n\r\nbody";
        let request = read_request(&mut Cursor::new(&raw[..])).unwrap();
        assert_eq!(request.method, "POST");
        assert_eq!(request.header("content-length"), Some("4"));
        assert_eq!(request.body, b"body");
        assert!(read_request(&mut Cursor::new(&b""[..])).is_err());
        assert!(read_request(&mut Cursor::new(&b"\r\n"[..])).is_err());
        let huge = format!(
            "GET / HTTP/1.1\r\nContent-Length: {}\r\n\r\n",
            MAX_BODY_BYTES + 1
        );
        assert!(read_request(&mut Cursor::new(huge.as_bytes())).is_err());
        let bad_len = b"GET / HTTP/1.1\r\nContent-Length: x\r\n\r\n";
        assert!(read_request(&mut Cursor::new(&bad_len[..])).is_err());
        let long = format!(
            "GET / HTTP/1.1\r\nX: {}\r\n\r\n",
            "a".repeat(MAX_HEADER_BYTES * 2)
        );
        assert!(read_request(&mut Cursor::new(long.as_bytes())).is_err());

        assert_eq!(parse_range("bytes=0-1", 10), Some((0, 1)));
        assert_eq!(parse_range("bytes=5-", 10), Some((5, 9)));
        assert_eq!(parse_range("bytes=-3", 10), Some((7, 9)));
        assert_eq!(parse_range("bytes=2-99", 10), Some((2, 9)));
        assert_eq!(parse_range("bytes=9-2", 10), None);
        assert_eq!(parse_range("bytes=-0", 10), None);
        assert_eq!(parse_range("bytes=0-1,3-4", 10), None);
        assert_eq!(parse_range("items=0-1", 10), None);
        assert_eq!(parse_range("bytes=0-", 0), None);

        assert_eq!(percent_decode("a%20b").as_deref(), Some("a b"));
        assert_eq!(percent_decode("%2e%2E").as_deref(), Some(".."));
        assert_eq!(percent_decode("%"), None);
        assert_eq!(percent_decode("%g0"), None);
        assert_eq!(percent_decode("%ff"), None);

        let mut out = Vec::new();
        let mut response = HttpResponse::text(206, "hi");
        response.headers.push(("Accept-Ranges", "bytes".into()));
        response.write_to(&mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.starts_with("HTTP/1.1 206 Partial Content\r\n"));
        assert!(text.contains("Content-Length: 2\r\n"));
        assert!(text.contains("Accept-Ranges: bytes\r\n"));
        assert!(text.ends_with("\r\n\r\nhi"));
    }

    #[test]
    fn serves_over_a_loopback_socket() {
        let fx = fixture("socket");
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = ReviewServer::new(fx.config.clone(), port).unwrap();
        std::thread::spawn(move || serve(listener, server));
        let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(
            stream,
            "GET /api/state HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n"
        )
        .unwrap();
        let mut text = String::new();
        stream.read_to_string(&mut text).unwrap();
        assert!(text.starts_with("HTTP/1.1 200 OK"), "{text}");
        assert!(text.contains("\"stations\""));
        let mut garbage = TcpStream::connect(("127.0.0.1", port)).unwrap();
        garbage.write_all(b"\r\n").unwrap();
        let mut text = String::new();
        garbage.read_to_string(&mut text).unwrap();
        assert!(text.starts_with("HTTP/1.1 400"), "{text}");
    }
}
