//! Voice casting through the ElevenLabs API: search the shared voice library,
//! design or remix a voice from a text description, and save a chosen preview.
//!
//! Library search is a free GET. Designing or remixing charges the characters of
//! the preview text once per request (three previews come back), so it goes
//! through the same finite credit cap and pending receipt as every other paid
//! call. Saving a preview creates a voice in the account and charges no credits.

use crate::{
    pending_receipt, reserve_generation, validate_name, write_refusing_symlinks, Error, Method,
    Request, Transport,
};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

/// Voice Design models accepted by `POST /v1/text-to-voice/design`.
pub const DESIGN_MODELS: [&str; 2] = ["eleven_ttv_v3", "eleven_multilingual_ttv_v2"];
/// The newer design model; reference audio and prompt strength need it.
pub const DEFAULT_DESIGN_MODEL: &str = "eleven_ttv_v3";
pub const DEFAULT_DESIGN_FORMAT: &str = "mp3_44100_128";
const DESIGN_TEXT_MIN_CHARS: usize = 100;
const DESIGN_TEXT_MAX_CHARS: usize = 1_000;
const LIBRARY_PAGE_MAX: u32 = 100;
const LIBRARY_CATEGORIES: [&str; 3] = ["professional", "famous", "high_quality"];
const LIBRARY_SORTS: [&str; 4] = [
    "created_date",
    "usage_character_count_1y",
    "trending",
    "cloned_by_count",
];

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// Filters for `GET /v1/shared-voices`. Empty fields are not sent.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct LibraryQuery {
    pub search: Option<String>,
    pub gender: Option<String>,
    pub age: Option<String>,
    pub accent: Option<String>,
    pub language: Option<String>,
    pub use_cases: Vec<String>,
    pub category: Option<String>,
    pub min_notice_days: Option<u32>,
    /// Voices with a legacy custom rate bill extra credits; they are excluded unless asked.
    pub include_custom_rates: bool,
    pub sort: Option<String>,
    pub page_size: u32,
    pub page: u32,
}

impl LibraryQuery {
    pub fn validate(&self) -> Result<(), Error> {
        if self.page_size == 0 || self.page_size > LIBRARY_PAGE_MAX {
            return Err(Error::InvalidArgument(format!(
                "library page size {} is outside 1..={LIBRARY_PAGE_MAX}",
                self.page_size
            )));
        }
        if let Some(category) = &self.category {
            if !LIBRARY_CATEGORIES.contains(&category.as_str()) {
                return Err(Error::InvalidArgument(format!(
                    "library category '{category}' is not one of {}",
                    LIBRARY_CATEGORIES.join(", ")
                )));
            }
        }
        if let Some(sort) = &self.sort {
            if !LIBRARY_SORTS.contains(&sort.as_str()) {
                return Err(Error::InvalidArgument(format!(
                    "library sort '{sort}' is not one of {}",
                    LIBRARY_SORTS.join(", ")
                )));
            }
        }
        Ok(())
    }
}

pub fn library_request(query: &LibraryQuery) -> Result<Request, Error> {
    query.validate()?;
    let mut pairs: Vec<(String, String)> = vec![
        ("page_size".into(), query.page_size.to_string()),
        ("page".into(), query.page.to_string()),
        (
            "include_custom_rates".into(),
            query.include_custom_rates.to_string(),
        ),
    ];
    let optional = [
        ("search", &query.search),
        ("gender", &query.gender),
        ("age", &query.age),
        ("accent", &query.accent),
        ("language", &query.language),
        ("category", &query.category),
        ("sort", &query.sort),
    ];
    for (key, value) in optional {
        if let Some(value) = value.as_deref().filter(|v| !v.trim().is_empty()) {
            pairs.push((key.to_string(), value.to_string()));
        }
    }
    for use_case in query.use_cases.iter().filter(|v| !v.trim().is_empty()) {
        pairs.push(("use_cases".into(), use_case.clone()));
    }
    if let Some(days) = query.min_notice_days {
        pairs.push(("min_notice_period_days".into(), days.to_string()));
    }
    Ok(Request {
        method: Method::Get,
        path: "/v1/shared-voices".to_string(),
        query: pairs,
        body: None,
    })
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct SharedVoice {
    pub voice_id: String,
    #[serde(default)]
    pub public_owner_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub category: Option<String>,
    #[serde(default)]
    pub gender: Option<String>,
    #[serde(default)]
    pub age: Option<String>,
    #[serde(default)]
    pub accent: Option<String>,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub descriptive: Option<String>,
    #[serde(default)]
    pub use_case: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub preview_url: Option<String>,
    #[serde(default)]
    pub notice_period: Option<serde_json::Value>,
    #[serde(default)]
    pub rate: Option<serde_json::Value>,
    #[serde(default)]
    pub free_users_allowed: Option<bool>,
    #[serde(default)]
    pub cloned_by_count: Option<u64>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct SharedVoicesPage {
    #[serde(default)]
    pub voices: Vec<SharedVoice>,
    #[serde(default)]
    pub has_more: bool,
    #[serde(default)]
    pub total_count: Option<u64>,
}

pub fn parse_library(body: &[u8]) -> Result<SharedVoicesPage, Error> {
    serde_json::from_slice(body).map_err(|err| Error::Api {
        status: 200,
        message: format!("unreadable shared voices body: {err}"),
    })
}

fn shown(value: &Option<serde_json::Value>) -> String {
    match value {
        None | Some(serde_json::Value::Null) => "none".to_string(),
        Some(serde_json::Value::String(text)) => text.clone(),
        Some(other) => other.to_string(),
    }
}

/// Two lines per voice: identity and casting facts, then the owner's description.
pub fn describe_library(page: &SharedVoicesPage) -> String {
    if page.voices.is_empty() {
        return "no shared voices matched".to_string();
    }
    let mut lines = Vec::with_capacity(page.voices.len() * 2 + 1);
    for voice in &page.voices {
        let tags: Vec<&str> = [
            &voice.gender,
            &voice.age,
            &voice.accent,
            &voice.language,
            &voice.descriptive,
            &voice.use_case,
        ]
        .iter()
        .filter_map(|value| value.as_deref())
        .filter(|value| !value.is_empty())
        .collect();
        lines.push(format!(
            "{}  {}  owner={}  [{}]  {}  notice={}  rate={}  free_users={}  cloned_by={}  preview={}",
            voice.voice_id,
            voice.name,
            voice.public_owner_id,
            voice.category.as_deref().unwrap_or("?"),
            tags.join(" / "),
            shown(&voice.notice_period),
            shown(&voice.rate),
            voice
                .free_users_allowed
                .map_or("unknown".to_string(), |v| v.to_string()),
            voice
                .cloned_by_count
                .map_or("unknown".to_string(), |v| v.to_string()),
            voice.preview_url.as_deref().unwrap_or("none"),
        ));
        let description: String = voice
            .description
            .as_deref()
            .unwrap_or("")
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .chars()
            .take(200)
            .collect();
        if !description.is_empty() {
            lines.push(format!("    {description}"));
        }
    }
    lines.push(format!(
        "{} shown, total {}, more: {}",
        page.voices.len(),
        page.total_count
            .map_or("unknown".to_string(), |v| v.to_string()),
        page.has_more
    ));
    lines.join("\n")
}

/// One Voice Design or remix request. `remix_voice_id` switches to the remix endpoint.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DesignParams {
    pub description: String,
    /// Preview text, 100 to 1000 characters. Required so the charge is known in advance.
    pub text: String,
    pub model: String,
    pub remix_voice_id: Option<String>,
    pub seed: Option<u64>,
    pub guidance_scale: Option<f64>,
    pub loudness: Option<f64>,
    pub prompt_strength: Option<f64>,
    pub format: String,
}

impl DesignParams {
    pub fn validate(&self) -> Result<(), Error> {
        if self.description.trim().is_empty() {
            return Err(Error::InvalidArgument(
                "voice description is empty".to_string(),
            ));
        }
        let chars = self.text.chars().count();
        if !(DESIGN_TEXT_MIN_CHARS..=DESIGN_TEXT_MAX_CHARS).contains(&chars) {
            return Err(Error::InvalidArgument(format!(
                "preview text is {chars} characters; it must be {DESIGN_TEXT_MIN_CHARS} to {DESIGN_TEXT_MAX_CHARS}"
            )));
        }
        if !DESIGN_MODELS.contains(&self.model.as_str()) {
            return Err(Error::InvalidArgument(format!(
                "design model '{}' is not one of {}",
                self.model,
                DESIGN_MODELS.join(", ")
            )));
        }
        if let Some(id) = &self.remix_voice_id {
            if !valid_id(id) {
                return Err(Error::InvalidArgument(format!(
                    "remix voice id '{id}' is not a valid ElevenLabs voice id"
                )));
            }
        }
        if let Some(loudness) = self.loudness {
            if !(-1.0..=1.0).contains(&loudness) {
                return Err(Error::InvalidArgument(format!(
                    "loudness {loudness} is outside -1..=1"
                )));
            }
        }
        if let Some(guidance) = self.guidance_scale {
            if !guidance.is_finite() || guidance < 0.0 {
                return Err(Error::InvalidArgument(format!(
                    "guidance scale {guidance} must be a finite non-negative number"
                )));
            }
        }
        if let Some(strength) = self.prompt_strength {
            if !(0.0..=1.0).contains(&strength) {
                return Err(Error::InvalidArgument(format!(
                    "prompt strength {strength} is outside 0..=1"
                )));
            }
            if self.model != DEFAULT_DESIGN_MODEL {
                return Err(Error::InvalidArgument(format!(
                    "prompt strength needs the {DEFAULT_DESIGN_MODEL} model"
                )));
            }
        }
        if !self.format.starts_with("mp3_") {
            return Err(Error::InvalidArgument(format!(
                "design previews are written as MP3; format '{}' is not mp3_*",
                self.format
            )));
        }
        crate::parse_format(&self.format).map(|_| ())
    }

    /// Voice Design charges the preview text once per request.
    pub fn estimate_credits(&self) -> u64 {
        self.text.chars().count() as u64
    }
}

/// `POST /v1/text-to-voice/design`, or `POST /v1/text-to-voice/{id}/remix`.
/// The remix endpoint documents no model field, so none is sent there.
pub fn design_request(params: &DesignParams) -> Result<Request, Error> {
    params.validate()?;
    let mut body = serde_json::Map::new();
    body.insert(
        "voice_description".into(),
        params.description.clone().into(),
    );
    body.insert("text".into(), params.text.clone().into());
    body.insert("auto_generate_text".into(), false.into());
    if params.remix_voice_id.is_none() {
        body.insert("model_id".into(), params.model.clone().into());
    }
    if let Some(seed) = params.seed {
        body.insert("seed".into(), seed.into());
    }
    if let Some(guidance) = params.guidance_scale {
        body.insert("guidance_scale".into(), guidance.into());
    }
    if let Some(loudness) = params.loudness {
        body.insert("loudness".into(), loudness.into());
    }
    if let Some(strength) = params.prompt_strength {
        body.insert("prompt_strength".into(), strength.into());
    }
    let path = match &params.remix_voice_id {
        Some(id) => format!("/v1/text-to-voice/{id}/remix"),
        None => "/v1/text-to-voice/design".to_string(),
    };
    Ok(Request {
        method: Method::Post,
        path,
        query: vec![("output_format".to_string(), params.format.clone())],
        body: Some(serde_json::Value::Object(body)),
    })
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
struct DesignPreview {
    generated_voice_id: String,
    audio_base_64: String,
    #[serde(default)]
    duration_secs: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
struct DesignResponse {
    previews: Vec<DesignPreview>,
}

/// Provenance written beside the previews so a chosen one can be saved later.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DesignRecord {
    pub name: String,
    pub endpoint: String,
    pub model: String,
    pub description: String,
    pub text: String,
    pub seed: Option<u64>,
    pub guidance_scale: Option<f64>,
    pub loudness: Option<f64>,
    pub prompt_strength: Option<f64>,
    pub estimated_credits: u64,
    pub previews: Vec<DesignRecordPreview>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DesignRecordPreview {
    pub file: String,
    pub generated_voice_id: String,
    pub duration_secs: Option<f64>,
    pub bytes: u64,
}

/// Standard base64 with optional padding; whitespace is ignored.
pub fn decode_base64(text: &str) -> Result<Vec<u8>, Error> {
    fn value(byte: u8) -> Option<u32> {
        match byte {
            b'A'..=b'Z' => Some(u32::from(byte - b'A')),
            b'a'..=b'z' => Some(u32::from(byte - b'a') + 26),
            b'0'..=b'9' => Some(u32::from(byte - b'0') + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let bad = || Error::Api {
        status: 200,
        message: "preview audio is not valid base64".to_string(),
    };
    let clean: Vec<u8> = text
        .bytes()
        .filter(|byte| !byte.is_ascii_whitespace())
        .collect();
    let trimmed: &[u8] = {
        let pad = clean.iter().rev().take_while(|&&b| b == b'=').count();
        if pad > 2 {
            return Err(bad());
        }
        &clean[..clean.len() - pad]
    };
    if trimmed.len() % 4 == 1 {
        return Err(bad());
    }
    let mut out = Vec::with_capacity(trimmed.len() * 3 / 4);
    for chunk in trimmed.chunks(4) {
        let mut acc: u32 = 0;
        for (index, &byte) in chunk.iter().enumerate() {
            acc |= value(byte).ok_or_else(bad)? << (18 - 6 * index as u32);
        }
        let bytes = acc.to_be_bytes();
        out.extend_from_slice(&bytes[1..chunk.len()]);
    }
    Ok(out)
}

fn preview_file(name: &str, index: usize) -> String {
    format!("{name}_{index}.mp3")
}

fn record_file(name: &str) -> String {
    format!("{name}.design.json")
}

/// Design or remix one voice. Writes `<name>_<n>.mp3` previews and `<name>.design.json`.
#[allow(clippy::too_many_arguments)]
pub fn run_design(
    name: &str,
    params: &DesignParams,
    out_dir: Option<&Path>,
    overwrite: bool,
    dry_run: bool,
    max_credits: Option<u64>,
    transport: &dyn Transport,
    api_key: &str,
    out: &mut dyn Write,
) -> Result<(), Error> {
    validate_name(name)?;
    let request = design_request(params)?;
    let credits = params.estimate_credits();
    let Some(out_dir) = out_dir else {
        return Err(Error::InvalidArgument(
            "design previews are candidates: pass --out-dir outside client/assets".to_string(),
        ));
    };
    if dry_run {
        writeln!(
            out,
            "dry-run design {name} -> {} (~{credits} credits): POST {}?{} {}",
            out_dir.join(record_file(name)).display(),
            request.path,
            request
                .query
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&"),
            request
                .body
                .as_ref()
                .map(ToString::to_string)
                .unwrap_or_default()
        )?;
        return Ok(());
    }
    let record_path = out_dir.join(record_file(name));
    if record_path.exists() && !overwrite {
        writeln!(
            out,
            "skip design {name}: {} exists (pass --overwrite to replace)",
            record_path.display()
        )?;
        return Ok(());
    }
    let Some(cap) = max_credits else {
        return Err(Error::InvalidArgument(
            "a finite --max-credits cap is required before a paid voice design".into(),
        ));
    };
    if credits > cap {
        return Err(Error::InvalidArgument(format!(
            "estimated {credits} credits exceeds --max-credits {cap}"
        )));
    }
    reserve_generation(out_dir, name, credits)?;
    let response = transport.send(api_key, &request)?;
    if !(200..300).contains(&response.status) {
        return Err(Error::Api {
            status: response.status,
            message: crate::api_error_message(response.status, &response.body),
        });
    }
    let parsed: DesignResponse =
        serde_json::from_slice(&response.body).map_err(|err| Error::Api {
            status: response.status,
            message: format!("unreadable design body: {err}"),
        })?;
    if parsed.previews.is_empty() {
        return Err(Error::Api {
            status: response.status,
            message: "design returned no previews".to_string(),
        });
    }
    let mut previews = Vec::with_capacity(parsed.previews.len());
    for (index, preview) in parsed.previews.iter().enumerate() {
        if !valid_id(&preview.generated_voice_id) {
            return Err(Error::Api {
                status: response.status,
                message: "design returned an invalid generated voice id".to_string(),
            });
        }
        let audio = decode_base64(&preview.audio_base_64)?;
        if audio.is_empty() {
            return Err(Error::Api {
                status: response.status,
                message: "design returned an empty preview".to_string(),
            });
        }
        let file = preview_file(name, index + 1);
        write_refusing_symlinks(&out_dir.join(&file), &audio)?;
        writeln!(
            out,
            "wrote preview {} -> {} ({} bytes)",
            preview.generated_voice_id,
            out_dir.join(&file).display(),
            audio.len()
        )?;
        previews.push(DesignRecordPreview {
            file,
            generated_voice_id: preview.generated_voice_id.clone(),
            duration_secs: preview.duration_secs,
            bytes: audio.len() as u64,
        });
    }
    let record = DesignRecord {
        name: name.to_string(),
        endpoint: request.path.clone(),
        model: if params.remix_voice_id.is_some() {
            "remix".to_string()
        } else {
            params.model.clone()
        },
        description: params.description.clone(),
        text: params.text.clone(),
        seed: params.seed,
        guidance_scale: params.guidance_scale,
        loudness: params.loudness,
        prompt_strength: params.prompt_strength,
        estimated_credits: credits,
        previews,
    };
    let json = serde_json::to_string_pretty(&record).map_err(|err| Error::Spec(err.to_string()))?;
    write_refusing_symlinks(&record_path, format!("{json}\n").as_bytes())?;
    let _ = fs::remove_file(pending_receipt(out_dir, name));
    writeln!(out, "wrote {}", record_path.display())?;
    Ok(())
}

/// Save a design preview as a voice in the account (`POST /v1/text-to-voice`).
#[derive(Debug, Clone, PartialEq)]
pub struct SaveVoiceParams {
    pub generated_voice_id: String,
    pub voice_name: String,
    pub description: String,
}

pub fn save_voice_request(params: &SaveVoiceParams) -> Result<Request, Error> {
    if !valid_id(&params.generated_voice_id) {
        return Err(Error::InvalidArgument(format!(
            "generated voice id '{}' is not valid",
            params.generated_voice_id
        )));
    }
    if params.voice_name.trim().is_empty() || params.description.trim().is_empty() {
        return Err(Error::InvalidArgument(
            "a saved voice needs a name and a description".to_string(),
        ));
    }
    Ok(Request {
        method: Method::Post,
        path: "/v1/text-to-voice".to_string(),
        query: Vec::new(),
        body: Some(serde_json::json!({
            "voice_name": params.voice_name,
            "voice_description": params.description,
            "generated_voice_id": params.generated_voice_id,
        })),
    })
}

#[derive(Debug, Deserialize)]
struct SavedVoice {
    voice_id: String,
}

pub fn run_save_voice(
    params: &SaveVoiceParams,
    dry_run: bool,
    transport: &dyn Transport,
    api_key: &str,
    out: &mut dyn Write,
) -> Result<(), Error> {
    let request = save_voice_request(params)?;
    if dry_run {
        writeln!(
            out,
            "dry-run save-voice (0 credits): POST {} {}",
            request.path,
            request
                .body
                .as_ref()
                .map(ToString::to_string)
                .unwrap_or_default()
        )?;
        return Ok(());
    }
    let response = transport.send(api_key, &request)?;
    if !(200..300).contains(&response.status) {
        return Err(Error::Api {
            status: response.status,
            message: crate::api_error_message(response.status, &response.body),
        });
    }
    let saved: SavedVoice = serde_json::from_slice(&response.body).map_err(|err| Error::Api {
        status: response.status,
        message: format!("unreadable saved voice body: {err}"),
    })?;
    writeln!(
        out,
        "saved {} -> voice_id {}",
        params.voice_name, saved.voice_id
    )?;
    Ok(())
}

/// Where a design run writes, for callers that need to check before running.
pub fn design_paths(out_dir: &Path, name: &str, previews: usize) -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> = (1..=previews)
        .map(|index| out_dir.join(preview_file(name, index)))
        .collect();
    paths.push(out_dir.join(record_file(name)));
    paths
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Response;
    use std::cell::RefCell;

    struct Fake {
        responses: RefCell<Vec<Response>>,
        seen: RefCell<Vec<Request>>,
    }

    impl Fake {
        fn new(responses: Vec<Response>) -> Self {
            Fake {
                responses: RefCell::new(responses),
                seen: RefCell::new(Vec::new()),
            }
        }
    }

    impl Transport for Fake {
        fn send(&self, _api_key: &str, request: &Request) -> Result<Response, Error> {
            self.seen.borrow_mut().push(request.clone());
            let mut responses = self.responses.borrow_mut();
            if responses.is_empty() {
                return Err(Error::Transport("no scripted response".into()));
            }
            Ok(responses.remove(0))
        }
    }

    fn temp_dir(tag: &str) -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default();
        let dir = std::env::temp_dir().join(format!("fragr-audiogen-casting-{tag}-{nanos}"));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn encode(bytes: &[u8]) -> String {
        const TABLE: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::new();
        for chunk in bytes.chunks(3) {
            let mut buf = [0u8; 3];
            buf[..chunk.len()].copy_from_slice(chunk);
            let n = (u32::from(buf[0]) << 16) | (u32::from(buf[1]) << 8) | u32::from(buf[2]);
            for i in 0..4 {
                if i <= chunk.len() {
                    out.push(TABLE[((n >> (18 - 6 * i)) & 63) as usize] as char);
                } else {
                    out.push('=');
                }
            }
        }
        out
    }

    fn design(text_len: usize) -> DesignParams {
        DesignParams {
            description: "A warm, unhurried narrator, close microphone.".into(),
            text: "a".repeat(text_len),
            model: DEFAULT_DESIGN_MODEL.into(),
            remix_voice_id: None,
            seed: Some(7),
            guidance_scale: Some(3.0),
            loudness: None,
            prompt_strength: None,
            format: DEFAULT_DESIGN_FORMAT.into(),
        }
    }

    #[test]
    fn base64_round_trips_and_rejects_garbage() {
        for sample in [&b""[..], b"f", b"fo", b"foo", b"foob", b"fooba", b"foobar"] {
            assert_eq!(decode_base64(&encode(sample)).unwrap(), sample);
        }
        assert_eq!(decode_base64("Zm9v\nYmFy").unwrap(), b"foobar");
        assert_eq!(decode_base64("Zm9vYg").unwrap(), b"foob");
        assert!(decode_base64("Zm9v!").is_err());
        assert!(decode_base64("Z===").is_err());
        assert!(decode_base64("Zm9vY").is_err());
    }

    #[test]
    fn library_request_sends_only_set_filters() {
        let query = LibraryQuery {
            search: Some("narrator".into()),
            gender: Some("neutral".into()),
            use_cases: vec!["narrative_story".into(), "".into()],
            min_notice_days: Some(365),
            sort: Some("cloned_by_count".into()),
            page_size: 25,
            ..LibraryQuery::default()
        };
        let request = library_request(&query).unwrap();
        assert_eq!(request.method, Method::Get);
        assert_eq!(request.path, "/v1/shared-voices");
        let has = |k: &str, v: &str| request.query.iter().any(|(a, b)| a == k && b == v);
        assert!(has("search", "narrator"));
        assert!(has("gender", "neutral"));
        assert!(has("use_cases", "narrative_story"));
        assert!(has("min_notice_period_days", "365"));
        assert!(has("include_custom_rates", "false"));
        assert!(has("page_size", "25"));
        assert!(!request.query.iter().any(|(k, _)| k == "accent"));
        assert_eq!(
            request
                .query
                .iter()
                .filter(|(k, _)| k == "use_cases")
                .count(),
            1
        );
    }

    #[test]
    fn library_query_rejects_bad_values() {
        let base = LibraryQuery {
            page_size: 30,
            ..LibraryQuery::default()
        };
        assert!(library_request(&LibraryQuery {
            page_size: 0,
            ..base.clone()
        })
        .is_err());
        assert!(library_request(&LibraryQuery {
            page_size: 101,
            ..base.clone()
        })
        .is_err());
        assert!(library_request(&LibraryQuery {
            category: Some("premade".into()),
            ..base.clone()
        })
        .is_err());
        assert!(library_request(&LibraryQuery {
            sort: Some("random".into()),
            ..base
        })
        .is_err());
    }

    #[test]
    fn library_page_parses_and_describes() {
        let body = br#"{"voices":[{"public_owner_id":"own1","voice_id":"v1","name":"Quiet Teller",
            "accent":"neutral","gender":"neutral","age":"middle_aged","descriptive":"calm",
            "use_case":"narrative_story","category":"professional","notice_period":730,
            "rate":null,"free_users_allowed":true,"cloned_by_count":12,
            "preview_url":"https://example.invalid/p.mp3","description":"Low,  warm\nand close."}],
            "has_more":true,"total_count":40}"#;
        let page = parse_library(body).unwrap();
        let text = describe_library(&page);
        assert!(text.contains("v1  Quiet Teller  owner=own1  [professional]"));
        assert!(text.contains("notice=730"));
        assert!(text.contains("rate=none"));
        assert!(text.contains("    Low, warm and close."));
        assert!(text.contains("1 shown, total 40, more: true"));
        assert_eq!(
            describe_library(&SharedVoicesPage::default()),
            "no shared voices matched"
        );
        assert!(parse_library(b"not json").is_err());
    }

    #[test]
    fn design_request_matches_api_shape() {
        let request = design_request(&design(120)).unwrap();
        assert_eq!(request.method, Method::Post);
        assert_eq!(request.path, "/v1/text-to-voice/design");
        assert_eq!(
            request.query,
            vec![("output_format".to_string(), "mp3_44100_128".to_string())]
        );
        let body = request.body.unwrap();
        assert_eq!(body["model_id"], "eleven_ttv_v3");
        assert_eq!(body["auto_generate_text"], false);
        assert_eq!(body["seed"], 7);
        assert_eq!(body["guidance_scale"], 3.0);
        assert!(body.get("loudness").is_none());
    }

    #[test]
    fn remix_uses_the_voice_path_and_no_model() {
        let mut params = design(150);
        params.remix_voice_id = Some("abcDEF123".into());
        params.prompt_strength = Some(0.3);
        let request = design_request(&params).unwrap();
        assert_eq!(request.path, "/v1/text-to-voice/abcDEF123/remix");
        let body = request.body.unwrap();
        assert!(body.get("model_id").is_none());
        assert_eq!(body["prompt_strength"], 0.3);
    }

    #[test]
    fn design_validation_rejects_bad_values() {
        assert!(design_request(&design(99)).is_err());
        assert!(design_request(&design(1001)).is_err());
        assert!(design_request(&design(100)).is_ok());
        let mut p = design(200);
        p.description = "  ".into();
        assert!(design_request(&p).is_err());
        let mut p = design(200);
        p.model = "eleven_v3".into();
        assert!(design_request(&p).is_err());
        let mut p = design(200);
        p.loudness = Some(1.5);
        assert!(design_request(&p).is_err());
        let mut p = design(200);
        p.model = "eleven_multilingual_ttv_v2".into();
        p.prompt_strength = Some(0.5);
        assert!(design_request(&p).is_err());
        let mut p = design(200);
        p.format = "pcm_24000".into();
        assert!(design_request(&p).is_err());
        let mut p = design(200);
        p.remix_voice_id = Some("../x".into());
        assert!(design_request(&p).is_err());
        assert_eq!(design(321).estimate_credits(), 321);
    }

    #[test]
    fn design_dry_run_sends_nothing_and_needs_an_out_dir() {
        let fake = Fake::new(Vec::new());
        let mut out = Vec::new();
        let dir = temp_dir("dry");
        run_design(
            "narrator/a",
            &design(150),
            Some(&dir),
            false,
            true,
            None,
            &fake,
            "k",
            &mut out,
        )
        .unwrap();
        assert!(fake.seen.borrow().is_empty());
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("~150 credits"));
        assert!(text.contains("POST /v1/text-to-voice/design?output_format=mp3_44100_128"));
        assert!(fs::read_dir(&dir).unwrap().next().is_none());
        let err = run_design(
            "narrator/a",
            &design(150),
            None,
            false,
            true,
            None,
            &fake,
            "k",
            &mut Vec::new(),
        );
        assert!(err.is_err());
    }

    #[test]
    fn design_requires_a_cap_that_covers_the_estimate() {
        let fake = Fake::new(Vec::new());
        let dir = temp_dir("cap");
        let none = run_design(
            "n",
            &design(150),
            Some(&dir),
            false,
            false,
            None,
            &fake,
            "k",
            &mut Vec::new(),
        );
        assert!(none.is_err());
        let low = run_design(
            "n",
            &design(150),
            Some(&dir),
            false,
            false,
            Some(149),
            &fake,
            "k",
            &mut Vec::new(),
        );
        assert!(low
            .unwrap_err()
            .to_string()
            .contains("exceeds --max-credits 149"));
        assert!(fake.seen.borrow().is_empty());
        assert!(!pending_receipt(&dir, "n").exists());
    }

    #[test]
    fn design_writes_previews_and_record_then_clears_the_receipt() {
        let body = serde_json::json!({
            "previews": [
                {"generated_voice_id": "gen1", "audio_base_64": encode(b"ID3one"), "media_type": "audio/mpeg", "duration_secs": 9.5},
                {"generated_voice_id": "gen2", "audio_base_64": encode(b"ID3two"), "media_type": "audio/mpeg"}
            ],
            "text": "ignored"
        });
        let fake = Fake::new(vec![Response {
            status: 200,
            body: body.to_string().into_bytes(),
        }]);
        let dir = temp_dir("write");
        let mut out = Vec::new();
        run_design(
            "narrator/a",
            &design(150),
            Some(&dir),
            false,
            false,
            Some(150),
            &fake,
            "k",
            &mut out,
        )
        .unwrap();
        assert_eq!(fake.seen.borrow().len(), 1);
        assert_eq!(fs::read(dir.join("narrator/a_1.mp3")).unwrap(), b"ID3one");
        assert_eq!(fs::read(dir.join("narrator/a_2.mp3")).unwrap(), b"ID3two");
        let record: DesignRecord =
            serde_json::from_str(&fs::read_to_string(dir.join("narrator/a.design.json")).unwrap())
                .unwrap();
        assert_eq!(record.previews.len(), 2);
        assert_eq!(record.previews[0].generated_voice_id, "gen1");
        assert_eq!(record.previews[0].duration_secs, Some(9.5));
        assert_eq!(record.estimated_credits, 150);
        assert!(!pending_receipt(&dir, "narrator/a").exists());
        // A second run skips instead of paying again.
        let again = Fake::new(Vec::new());
        let mut out = Vec::new();
        run_design(
            "narrator/a",
            &design(150),
            Some(&dir),
            false,
            false,
            Some(150),
            &again,
            "k",
            &mut out,
        )
        .unwrap();
        assert!(again.seen.borrow().is_empty());
        assert!(String::from_utf8(out)
            .unwrap()
            .contains("skip design narrator/a"));
        assert_eq!(design_paths(&dir, "narrator/a", 2).len(), 3);
    }

    #[test]
    fn design_failure_keeps_the_receipt_and_is_not_retried() {
        let fake = Fake::new(vec![Response {
            status: 500,
            body: br#"{"detail":{"status":"server_error","message":"boom"}}"#.to_vec(),
        }]);
        let dir = temp_dir("fail");
        let err = run_design(
            "n",
            &design(150),
            Some(&dir),
            false,
            false,
            Some(500),
            &fake,
            "k",
            &mut Vec::new(),
        )
        .unwrap_err();
        assert!(err.to_string().contains("boom"));
        assert_eq!(fake.seen.borrow().len(), 1);
        assert!(pending_receipt(&dir, "n").exists());
        // The unreconciled receipt blocks a blind second charge.
        let next = Fake::new(Vec::new());
        assert!(run_design(
            "n",
            &design(150),
            Some(&dir),
            true,
            false,
            Some(500),
            &next,
            "k",
            &mut Vec::new()
        )
        .is_err());
        assert!(next.seen.borrow().is_empty());
    }

    #[test]
    fn design_rejects_malformed_previews() {
        let body = serde_json::json!({"previews": [{"generated_voice_id": "g/1", "audio_base_64": "QQ=="}]});
        let fake = Fake::new(vec![Response {
            status: 200,
            body: body.to_string().into_bytes(),
        }]);
        let dir = temp_dir("malformed");
        assert!(run_design(
            "n",
            &design(150),
            Some(&dir),
            false,
            false,
            Some(150),
            &fake,
            "k",
            &mut Vec::new()
        )
        .is_err());
        let empty = Fake::new(vec![Response {
            status: 200,
            body: br#"{"previews":[]}"#.to_vec(),
        }]);
        let dir = temp_dir("empty");
        assert!(run_design(
            "n",
            &design(150),
            Some(&dir),
            false,
            false,
            Some(150),
            &empty,
            "k",
            &mut Vec::new()
        )
        .is_err());
    }

    #[test]
    fn save_voice_posts_the_preview_and_prints_the_id() {
        let params = SaveVoiceParams {
            generated_voice_id: "gen1".into(),
            voice_name: "fragr narrator".into(),
            description: "Warm, unhurried narrator.".into(),
        };
        let request = save_voice_request(&params).unwrap();
        assert_eq!(request.path, "/v1/text-to-voice");
        assert_eq!(request.body.as_ref().unwrap()["generated_voice_id"], "gen1");
        let fake = Fake::new(vec![Response {
            status: 200,
            body: br#"{"voice_id":"saved9"}"#.to_vec(),
        }]);
        let mut out = Vec::new();
        run_save_voice(&params, false, &fake, "k", &mut out).unwrap();
        assert!(String::from_utf8(out).unwrap().contains("voice_id saved9"));
        let dry = Fake::new(Vec::new());
        let mut out = Vec::new();
        run_save_voice(&params, true, &dry, "k", &mut out).unwrap();
        assert!(dry.seen.borrow().is_empty());
        assert!(save_voice_request(&SaveVoiceParams {
            voice_name: " ".into(),
            ..params.clone()
        })
        .is_err());
        assert!(save_voice_request(&SaveVoiceParams {
            generated_voice_id: "a b".into(),
            ..params
        })
        .is_err());
    }
}
