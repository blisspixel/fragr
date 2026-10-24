//! Bounded offline-priced model production, with a live account gate before POST.

use std::collections::BTreeSet;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::ledger::{Event, Identity, Ledger, Stage};
use crate::{check_budget, Error, Method, Request, Transport};

pub const API_BASE: &str = "https://api.meshy.ai/openapi/v1";
pub const USD_PER_CREDIT: f64 = 0.02;
pub const PRICING_DATE: &str = "2026-10-03";
/// Largest `--max-credits` one run may name: Nick's reported 1,900-credit
/// monthly allowance. The live balance and retained holds still gate every
/// stage, so a run can never reserve more than the account actually has.
pub const MAX_CREDITS: u64 = 1_900;
/// Largest single stage valuation a reservation may carry.
pub const MAX_STAGE_CREDITS: u64 = 250;
/// Largest number of stages in one model spec.
pub const MAX_STAGES: usize = 32;

/// Validate a run's credit ceiling against [`MAX_CREDITS`].
pub fn check_credit_cap(max_credits: u64) -> Result<(), Error> {
    if max_credits == 0 || max_credits > MAX_CREDITS {
        return Err(Error::Budget(format!(
            "credit cap must be 1 to {MAX_CREDITS}"
        )));
    }
    Ok(())
}
pub const ACCOUNT_HOLD: &str = "art/raw/meshy-account-hold.json";

/// Keep the account carry beside the canonical credential root, independent of
/// the process working directory and per-batch output paths.
pub fn account_hold_for_credentials(path: &Path) -> Result<PathBuf, Error> {
    let credential = path
        .canonicalize()
        .map_err(|_| Error::Io("cannot resolve model account credential location".into()))?;
    let root = credential
        .parent()
        .ok_or_else(|| Error::Io("model account credential location has no parent".into()))?;
    Ok(root.join(ACCOUNT_HOLD))
}

pub fn read_credential(path: &Path) -> Result<String, Error> {
    crate::read_dotenv_value(path, &["meshy", "MESHY_API_KEY"])
}

pub fn validate_api_url(raw: &str) -> Result<reqwest::Url, Error> {
    let url = crate::validate_download_url(raw)?;
    if url.host_str() != Some("api.meshy.ai")
        || url.port_or_known_default() != Some(443)
        || url.query().is_some()
        || !url.path().starts_with("/openapi/v1/")
    {
        return Err(Error::Transport(
            "request is outside the model API origin".into(),
        ));
    }
    Ok(url)
}

fn endpoint(model: &str) -> Result<&'static str, Error> {
    match model {
        "meshy/image-to-3d" => Ok("image-to-3d"),
        "meshy/rigging" => Ok("rigging"),
        _ => Err(Error::Spec("unsupported model production stage".into())),
    }
}

pub fn status_url(model: &str, id: &str) -> Result<String, Error> {
    crate::validation::validate_request_id(id)?;
    Ok(format!("{API_BASE}/{}/{id}", endpoint(model)?))
}

pub fn status_request_id(model: &str, raw: &str) -> Result<String, Error> {
    let url = validate_api_url(raw)?;
    let prefix = format!("/openapi/v1/{}/", endpoint(model)?);
    let id = url
        .path()
        .strip_prefix(&prefix)
        .ok_or_else(|| Error::Transport("invalid model task path".into()))?;
    crate::validation::validate_request_id(id)?;
    Ok(id.to_owned())
}

fn send(transport: &dyn Transport, key: &str, request: &Request) -> Result<Value, Error> {
    validate_api_url(&request.url)?;
    let response = transport.send(key, request).map_err(|_| {
        Error::Transport("model API transport failed; retain any pending reservation".into())
    })?;
    if !matches!(response.status, 200..=202) {
        // Provider bodies and transport errors can echo a credential or signed URL.
        return Err(Error::Api {
            status: response.status,
            body: "model API refused the request".into(),
        });
    }
    if response.body.len() > 4 * 1024 * 1024 {
        return Err(Error::Transport("model API response exceeds 4 MiB".into()));
    }
    serde_json::from_str(&response.body)
        .map_err(|_| Error::Transport("invalid model API JSON".into()))
}

pub fn balance(transport: &dyn Transport, key: &str) -> Result<u64, Error> {
    Ok(balance_details(transport, key)?.balance)
}

#[derive(Debug, Deserialize)]
struct Balance {
    balance: u64,
    monthly_credits: Option<u64>,
    permanent_credits: Option<u64>,
    monthly_resets_at: Option<u64>,
    #[serde(skip)]
    monthly_reset_reported: bool,
}

fn balance_details(transport: &dyn Transport, key: &str) -> Result<Balance, Error> {
    let value = send(
        transport,
        key,
        &Request {
            method: Method::Get,
            url: format!("{API_BASE}/balance"),
            body: None,
        },
    )?;
    // Only the documented reset may explicitly be null. Missing detail remains
    // compatible with the historical balance-only response.
    if ["monthly_credits", "permanent_credits"]
        .iter()
        .any(|field| value.get(field).is_some_and(|v| v.as_u64().is_none()))
    {
        return Err(Error::Transport(
            "invalid model balance credit details".into(),
        ));
    }
    let mut result: Balance = serde_json::from_value(value.clone())
        .map_err(|_| Error::Transport("invalid model balance details".into()))?;
    result.monthly_reset_reported = value.get("monthly_resets_at").is_some();
    Ok(result)
}

/// A migration carry hold is not a fabricated provider task or refund.
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ExternalHold {
    schema: u32,
    credits: u64,
    reason: String,
}

fn validate_hold(hold: &ExternalHold) -> Result<(), Error> {
    if hold.schema != 1
        || hold.credits == 0
        || hold.credits > 1_000_000
        || hold.reason.trim().is_empty()
        || hold.reason.len() > 1024
        || hold.reason.chars().any(char::is_control)
    {
        return Err(Error::Io("invalid external model hold".into()));
    }
    Ok(())
}

pub fn retain_external_hold(path: &Path, credits: u64, reason: &str) -> Result<(), Error> {
    let hold = ExternalHold {
        schema: 1,
        credits,
        reason: reason.into(),
    };
    validate_hold(&hold)?;
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent).map_err(io_error)?;
    }
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|_| Error::Io("external model hold already exists or cannot be created".into()))?;
    serde_json::to_writer(&mut file, &hold)
        .map_err(|_| Error::Io("could not write external model hold".into()))?;
    file.sync_all().map_err(io_error)
}

pub fn external_held_credits(path: &Path) -> Result<u64, Error> {
    use std::io::Read;
    let file = match std::fs::File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),
        Err(_) => return Err(Error::Io("could not read external model hold".into())),
    };
    let mut bytes = Vec::new();
    file.take(4097).read_to_end(&mut bytes).map_err(io_error)?;
    if bytes.len() > 4096 {
        return Err(Error::Io("external model hold exceeds 4 KiB".into()));
    }
    let hold: ExternalHold = serde_json::from_slice(&bytes)
        .map_err(|_| Error::Io("invalid external model hold document".into()))?;
    validate_hold(&hold)?;
    Ok(hold.credits)
}

pub fn pending_credits(ledger: &Ledger) -> Result<u64, Error> {
    let mut held = 0_u64;
    for job in ledger.jobs() {
        let Some(identity) = job
            .identity
            .as_ref()
            .filter(|i| i.model.starts_with("meshy/"))
        else {
            continue;
        };
        let credits = identity
            .request
            .get("credits")
            .and_then(Value::as_u64)
            .ok_or_else(|| Error::Io("model reservation has no credit valuation".into()))?;
        if credits == 0
            || credits > MAX_STAGE_CREDITS
            || (job.estimated_usd - credits as f64 / 50.0).abs() > 0.000001
        {
            return Err(Error::Io(
                "model reservation credit valuation is inconsistent".into(),
            ));
        }
        if job
            .consumed_credits
            .is_some_and(|consumed| consumed > credits)
        {
            return Err(Error::Budget(
                "provider credit price drift requires reconciliation".into(),
            ));
        }
        if !matches!(
            job.stage,
            Stage::Completed { .. } | Stage::Downloaded { .. }
        ) {
            held = held
                .checked_add(credits)
                .ok_or_else(|| Error::Budget("pending credit overflow".into()))?;
        }
    }
    Ok(held)
}

#[derive(Debug, Serialize)]
pub struct CreditCheck {
    pub schema: u32,
    pub pricing_checked: &'static str,
    pub available_api_credits: u64,
    pub monthly_credits: Option<u64>,
    pub permanent_credits: Option<u64>,
    pub monthly_resets_at: Option<u64>,
    pub monthly_reset_reported: bool,
    pub pending_local_credits: u64,
    pub external_held_credits: u64,
    pub required_credits: u64,
    pub sufficient: bool,
    pub generation_submissions: u32,
}

pub fn check(
    transport: &dyn Transport,
    key: &str,
    required: u64,
    ledger: Option<&Ledger>,
    hold_path: &Path,
) -> Result<CreditCheck, Error> {
    check_with_hold(transport, key, required, ledger, hold_path)
}

fn check_with_hold(
    transport: &dyn Transport,
    key: &str,
    required: u64,
    ledger: Option<&Ledger>,
    hold_path: &Path,
) -> Result<CreditCheck, Error> {
    let held = ledger.map(pending_credits).transpose()?.unwrap_or(0);
    let external = external_held_credits(hold_path)?;
    let details = balance_details(transport, key)?;
    let available = details.balance;
    Ok(CreditCheck {
        schema: 1,
        pricing_checked: PRICING_DATE,
        available_api_credits: available,
        monthly_credits: details.monthly_credits,
        permanent_credits: details.permanent_credits,
        monthly_resets_at: details.monthly_resets_at,
        monthly_reset_reported: details.monthly_reset_reported,
        pending_local_credits: held,
        external_held_credits: external,
        required_credits: required,
        sufficient: held
            .checked_add(external)
            .and_then(|reserved| reserved.checked_add(required))
            .is_some_and(|needed| available >= needed),
        generation_submissions: 0,
    })
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Spec {
    pub out_dir: PathBuf,
    pub jobs: Vec<JobSpec>,
    #[serde(skip, default = "account_hold_path")]
    external_hold: PathBuf,
}

fn account_hold_path() -> PathBuf {
    ACCOUNT_HOLD.into()
}

impl Spec {
    pub fn bind_account(&mut self, credential_file: &Path) -> Result<(), Error> {
        self.external_hold = account_hold_for_credentials(credential_file)?;
        external_held_credits(&self.external_hold)?;
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
pub struct JobSpec {
    pub id: String,
    #[serde(flatten)]
    pub stage: JobStage,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum JobStage {
    Image {
        #[serde(default = "standard_model")]
        ai_model: String,
        image_url: String,
        geometry_resolution: String,
        texture_resolution: String,
        target_polycount: u32,
        pose_mode: String,
    },
    Rig {
        input_task_id: String,
        height_meters: f64,
    },
}

fn standard_model() -> String {
    "meshy-7.1".into()
}

impl JobSpec {
    fn priced(&self) -> Result<(Identity, u64), Error> {
        crate::validate_frame_id(&self.id)?;
        let (model, params, credits) = match &self.stage {
            JobStage::Image {
                ai_model,
                image_url,
                geometry_resolution,
                texture_resolution,
                target_polycount,
                pose_mode,
            } => {
                let url = crate::validate_download_url(image_url)?;
                if image_url.len() > 2048
                    || url.port_or_known_default() != Some(443)
                    || !matches!(geometry_resolution.as_str(), "standard" | "2k" | "4k")
                    || !matches!(texture_resolution.as_str(), "2k" | "4k")
                    || !(100..=50000).contains(target_polycount)
                    || !matches!(pose_mode.as_str(), "" | "a-pose" | "t-pose")
                {
                    return Err(Error::Spec("invalid image model parameters".into()));
                }
                if !matches!(ai_model.as_str(), "meshy-7.1" | "meshy-t2")
                    || (ai_model == "meshy-t2"
                        && (geometry_resolution != "standard" || *target_polycount > 15000))
                {
                    return Err(Error::Spec(
                        "unsupported model or Smart Topology settings".into(),
                    ));
                }
                let mut params = json!({"image_url": image_url, "ai_model": ai_model,
                    "model_type": "standard", "geometry_resolution": geometry_resolution,
                    "texture_resolution": texture_resolution, "should_texture": true, "enable_pbr": true,
                    "should_remesh": true, "topology": "triangle", "target_polycount": target_polycount,
                    "pose_mode": pose_mode, "image_enhancement": false, "target_formats": ["glb"]});
                if ai_model == "meshy-t2" {
                    params["model_type"] = json!("smart-topology");
                    let fields = params.as_object_mut().expect("constructed parameters");
                    for key in [
                        "geometry_resolution",
                        "should_remesh",
                        "topology",
                        "image_enhancement",
                    ] {
                        fields.remove(key);
                    }
                }
                (
                    "meshy/image-to-3d",
                    params,
                    if ai_model == "meshy-t2" {
                        15
                    } else if geometry_resolution == "standard" {
                        30
                    } else {
                        35
                    },
                )
            }
            JobStage::Rig {
                input_task_id,
                height_meters,
            } => {
                crate::validation::validate_request_id(input_task_id)?;
                if !height_meters.is_finite() || !(0.5..=3.0).contains(height_meters) {
                    return Err(Error::Spec(
                        "rig height must be between 0.5 and 3 metres".into(),
                    ));
                }
                (
                    "meshy/rigging",
                    json!({"input_task_id": input_task_id, "height_meters": height_meters}),
                    5,
                )
            }
        };
        Ok((
            Identity {
                model: model.into(),
                request: json!({"params": params, "credits": credits,
            "pricing_checked": PRICING_DATE, "usd_per_credit": USD_PER_CREDIT}),
            },
            credits,
        ))
    }
}

pub fn parse_spec(text: &str) -> Result<Spec, Error> {
    if text.len() > 256 * 1024 {
        return Err(Error::Spec("model spec exceeds 256 KiB".into()));
    }
    // Validate unknown fields before flattening a tagged stage.
    let raw: Value = serde_json::from_str(text)
        .map_err(|_| Error::Spec("invalid model specification JSON".into()))?;
    let spec: Spec = serde_json::from_value(raw.clone())
        .map_err(|_| Error::Spec("invalid model specification fields".into()))?;
    if spec.out_dir.as_os_str().is_empty() || spec.jobs.is_empty() || spec.jobs.len() > MAX_STAGES {
        return Err(Error::Spec(
            "model spec needs an output directory and 1 to 32 stages".into(),
        ));
    }
    let mut ids = BTreeSet::new();
    for (job, value) in spec
        .jobs
        .iter()
        .zip(raw["jobs"].as_array().into_iter().flatten())
    {
        let keys: &[&str] = match job.stage {
            JobStage::Image { .. } => &[
                "id",
                "kind",
                "ai_model",
                "image_url",
                "geometry_resolution",
                "texture_resolution",
                "target_polycount",
                "pose_mode",
            ],
            JobStage::Rig { .. } => &["id", "kind", "input_task_id", "height_meters"],
        };
        if value
            .as_object()
            .is_none_or(|v| v.keys().any(|k| !keys.contains(&k.as_str())))
        {
            return Err(Error::Spec("unknown model stage parameter".into()));
        }
        job.priced()?;
        if !ids.insert(job.id.to_ascii_lowercase()) {
            return Err(Error::Spec("duplicate model stage ID".into()));
        }
    }
    Ok(spec)
}

pub fn generate(
    transport: &dyn Transport,
    key: &str,
    spec: &Spec,
    max_credits: u64,
    max_spend_usd: Option<f64>,
    output: &mut dyn Write,
    sleep: &mut dyn FnMut(Duration),
) -> Result<(), Error> {
    check_budget(0.0, max_spend_usd)?;
    check_credit_cap(max_credits)?;
    if spec.out_dir.as_os_str().is_empty() || spec.jobs.is_empty() || spec.jobs.len() > MAX_STAGES {
        return Err(Error::Spec(
            "model spec needs an output directory and 1 to 32 stages".into(),
        ));
    }
    let mut ids = BTreeSet::new();
    for job in &spec.jobs {
        job.priced()?;
        if !ids.insert(job.id.to_ascii_lowercase()) {
            return Err(Error::Spec("duplicate model stage ID".into()));
        }
    }
    let mut ledger = Ledger::open(&spec.out_dir)?;
    let mut fresh = 0;
    for job in &spec.jobs {
        let (identity, credits) = job.priced()?;
        if let Some(previous) = ledger.job(&job.id) {
            if previous.identity.as_ref() != Some(&identity) {
                return Err(Error::Spec("model request identity changed".into()));
            }
            match &previous.stage {
                Stage::Reserved | Stage::Stopped { .. } => return Err(Error::Io("uncertain or stopped model reservation requires reconciliation, never resubmit".into())),
                Stage::Downloaded { files } if files.iter().any(|f| !spec.out_dir.join(f).is_file()) => return Err(Error::Io("model output missing; restore it without paid regeneration".into())),
                _ => {}
            }
        } else {
            fresh += credits;
        }
    }
    check_budget(fresh as f64 / 50.0, max_spend_usd)?;
    if fresh > max_credits {
        return Err(Error::Budget(
            "fresh model stages exceed the credit cap".into(),
        ));
    }
    if fresh > 0 {
        require_balance(transport, key, fresh, &ledger, &spec.external_hold, output)?;
    }
    for job in &spec.jobs {
        let (identity, credits) = job.priced()?;
        if ledger.job(&job.id).is_none() {
            require_balance(
                transport,
                key,
                credits,
                &ledger,
                &spec.external_hold,
                output,
            )?;
            ledger.record(
                &job.id,
                Event::Reserved {
                    identity: identity.clone(),
                    estimated_usd: credits as f64 / 50.0,
                },
            )?;
            let result = send(
                transport,
                key,
                &Request {
                    method: Method::Post,
                    url: format!("{API_BASE}/{}", endpoint(&identity.model)?),
                    body: Some(identity.request["params"].to_string()),
                },
            )?;
            let id = result
                .get("result")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    Error::Transport("model task response has no ID; reservation retained".into())
                })?;
            crate::validation::validate_request_id(id)?;
            ledger.record(
                &job.id,
                Event::Accepted {
                    request_id: id.into(),
                },
            )?;
            writeln!(
                output,
                "{}: accepted {id}, reserved {credits} credits",
                job.id
            )
            .map_err(io_error)?;
        }
        if let Some(crate::ledger::Job {
            stage: Stage::Accepted { request_id },
            ..
        }) = ledger.job(&job.id).cloned()
        {
            ledger.recover(&job.id, &request_id)?;
        }
        let stage = ledger.job(&job.id).expect("prepared job").stage.clone();
        let urls = match stage {
            Stage::Downloaded { .. } => continue,
            Stage::Completed { urls, .. } => urls,
            Stage::Submitted { status_url } => {
                let id = status_request_id(&identity.model, &status_url)?;
                let mut urls = None;
                for attempt in 0..240 {
                    let value = send(
                        transport,
                        key,
                        &Request {
                            method: Method::Get,
                            url: status_url.clone(),
                            body: None,
                        },
                    )?;
                    if value.get("id").and_then(Value::as_str) != Some(id.as_str()) {
                        return Err(Error::Transport("model task ID mismatch".into()));
                    }
                    match value.get("status").and_then(Value::as_str) {
                        Some("PENDING" | "IN_PROGRESS") => {
                            if attempt < 239 {
                                sleep(Duration::from_secs(5));
                            }
                        }
                        Some("SUCCEEDED") => {
                            let received = output_urls(&identity.model, &value)?;
                            if let Some(reported) = value.get("consumed_credits") {
                                let consumed = reported
                                    .as_u64()
                                    .filter(|credits| *credits <= 10000)
                                    .ok_or_else(|| {
                                        Error::Transport("invalid reported model credit use".into())
                                    })?;
                                ledger.record(
                                    &job.id,
                                    Event::Usage {
                                        consumed_credits: consumed,
                                    },
                                )?;
                                writeln!(
                                    output,
                                    "{}: provider reports {consumed} credits consumed",
                                    job.id
                                )
                                .map_err(io_error)?;
                            }
                            ledger.record(
                                &job.id,
                                Event::Completed {
                                    urls: received.clone(),
                                },
                            )?;
                            urls = Some(received);
                            break;
                        }
                        Some("FAILED" | "CANCELED" | "EXPIRED") => {
                            ledger.record(
                                &job.id,
                                Event::Stopped {
                                    status: "failed".into(),
                                },
                            )?;
                            return Err(Error::Transport(
                                "model task stopped; reservation retained for reconciliation"
                                    .into(),
                            ));
                        }
                        _ => return Err(Error::Transport("unknown model task status".into())),
                    }
                }
                urls.ok_or_else(|| {
                    Error::Transport("model polling timed out; resume the same task".into())
                })?
            }
            _ => return Err(Error::Io("model task is not ready to resume".into())),
        };
        let mut files = Vec::new();
        for (index, url) in urls.iter().enumerate() {
            validate_asset_url(url)?;
            let bytes = transport.download(url).map_err(|_| {
                Error::Transport("model download failed; resume without generation".into())
            })?;
            validate_glb(&bytes)?;
            let name = format!("{}-{index}.glb", job.id);
            crate::generation::write_artifact(&spec.out_dir, &name, &bytes)?;
            files.push(name);
        }
        ledger.record(&job.id, Event::Downloaded { files })?;
        writeln!(output, "{}: downloaded candidate, review required", job.id).map_err(io_error)?;
        if ledger
            .job(&job.id)
            .and_then(|job| job.consumed_credits)
            .is_some_and(|consumed| consumed > credits)
        {
            return Err(Error::Budget("provider price exceeded reservation; candidate downloaded, reconcile before another stage".into()));
        }
    }
    Ok(())
}

fn io_error(error: std::io::Error) -> Error {
    Error::Io(error.to_string())
}

fn require_balance(
    transport: &dyn Transport,
    key: &str,
    required: u64,
    ledger: &Ledger,
    hold_path: &Path,
    output: &mut dyn Write,
) -> Result<(), Error> {
    let result = check_with_hold(transport, key, required, Some(ledger), hold_path)?;
    writeln!(
        output,
        "balance {}, pending {}, external hold {}, required {} credits",
        result.available_api_credits,
        result.pending_local_credits,
        result.external_held_credits,
        required
    )
    .map_err(io_error)?;
    if !result.sufficient {
        return Err(Error::Budget(
            "live model API balance is insufficient after pending holds".into(),
        ));
    }
    Ok(())
}

fn output_urls(model: &str, value: &Value) -> Result<Vec<String>, Error> {
    let paths: &[&str] = if model == "meshy/rigging" {
        &[
            "/result/rigged_character_glb_url",
            "/result/basic_animations/walking_glb_url",
            "/result/basic_animations/running_glb_url",
        ]
    } else {
        &["/model_urls/glb"]
    };
    let mut urls = Vec::new();
    for path in paths {
        let url = value
            .pointer(path)
            .and_then(Value::as_str)
            .ok_or_else(|| Error::Transport("completed task lacks required GLB output".into()))?;
        validate_asset_url(url)?;
        urls.push(url.to_owned());
    }
    Ok(urls)
}

fn validate_asset_url(raw: &str) -> Result<(), Error> {
    let url = crate::validate_download_url(raw)?;
    if raw.len() > 8192
        || url.host_str() != Some("assets.meshy.ai")
        || url.port_or_known_default() != Some(443)
    {
        return Err(Error::Transport(
            "model output is outside the documented asset origin".into(),
        ));
    }
    Ok(())
}

pub fn validate_glb(bytes: &[u8]) -> Result<(), Error> {
    let bad = || Error::Transport("invalid or externally dependent GLB candidate".into());
    if bytes.len() < 20
        || bytes.len() > 64 * 1024 * 1024
        || &bytes[..4] != b"glTF"
        || bytes[4..8] != 2_u32.to_le_bytes()
        || bytes[8..12] != (bytes.len() as u32).to_le_bytes()
        || &bytes[16..20] != b"JSON"
    {
        return Err(bad());
    }
    let length = u32::from_le_bytes(bytes[12..16].try_into().map_err(|_| bad())?) as usize;
    let end = 20_usize.checked_add(length).ok_or_else(bad)?;
    if !length.is_multiple_of(4) {
        return Err(bad());
    }
    if end < bytes.len() {
        let header = bytes.get(end..end + 8).ok_or_else(bad)?;
        let bin_length = u32::from_le_bytes(header[..4].try_into().map_err(|_| bad())?) as usize;
        if &header[4..] != b"BIN\0"
            || !bin_length.is_multiple_of(4)
            || end.checked_add(8 + bin_length) != Some(bytes.len())
        {
            return Err(bad());
        }
    }
    let document: Value =
        serde_json::from_slice(bytes.get(20..end).ok_or_else(bad)?).map_err(|_| bad())?;
    if document.pointer("/asset/version").and_then(Value::as_str) != Some("2.0") {
        return Err(bad());
    }
    for key in ["buffers", "images"] {
        if let Some(values) = document.get(key) {
            for entry in values.as_array().ok_or_else(bad)? {
                if entry.get("uri").is_some() {
                    return Err(bad());
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
#[path = "meshy_tests.rs"]
mod tests;
