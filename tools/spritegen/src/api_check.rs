//! Free API capability probes. Never submits generation or uploads media.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{parse_usd, validation, Error, Method, Request, Transport, API_BASE};

pub const DOCUMENTATION_URL: &str = "https://docs.higgsfield.ai/docs/openapi.json";
pub const MAX_SPEC_BYTES: usize = 256 * 1024;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Spec {
    pub probes: Vec<Probe>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Probe {
    /// An API path, not necessarily the identifier used by the web app.
    pub model: String,
    /// Exact model parameters. These are sent only to the estimate endpoint.
    pub params: Value,
}

#[derive(Debug, Serialize)]
pub struct Report {
    pub schema_version: u32,
    pub checked_unix_seconds: u64,
    pub credentials_verified_by_estimate: bool,
    pub generation_submitted: bool,
    pub balance: &'static str,
    pub documentation: Documentation,
    pub probes: Vec<ProbeResult>,
    pub limitation: &'static str,
}

#[derive(Debug, Serialize)]
pub struct Documentation {
    pub source: &'static str,
    pub status: &'static str,
    pub documented_post_paths: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct ProbeResult {
    pub model: String,
    pub http_status: Option<u16>,
    pub status: &'static str,
    pub estimated_usd: Option<f64>,
}

pub fn default_spec() -> Spec {
    Spec {
        probes: vec![Probe {
            model: "higgsfield-ai/soul/v2/standard".into(),
            params: serde_json::json!({"prompt": "Editorial portrait in soft daylight"}),
        }],
    }
}

pub fn parse_spec(text: &str) -> Result<Spec, Error> {
    if text.len() > MAX_SPEC_BYTES {
        return Err(Error::Spec(
            "API-check specification exceeds 256 KiB".into(),
        ));
    }
    let spec: Spec = serde_json::from_str(text)
        .map_err(|_| Error::Spec("invalid API-check specification JSON".into()))?;
    validate(&spec)?;
    Ok(spec)
}

fn validate(spec: &Spec) -> Result<(), Error> {
    if spec.probes.is_empty() || spec.probes.len() > 32 {
        return Err(Error::Spec("API check requires 1 to 32 probes".into()));
    }
    for probe in &spec.probes {
        validation::validate_model_path(&probe.model)?;
        if !probe.params.is_object() || probe.params.to_string().len() > MAX_SPEC_BYTES {
            return Err(Error::Spec(
                "probe params must be a bounded JSON object".into(),
            ));
        }
    }
    Ok(())
}

fn documentation(transport: &dyn Transport) -> Documentation {
    let mut result = Documentation {
        source: DOCUMENTATION_URL,
        status: "unavailable",
        documented_post_paths: Vec::new(),
    };
    let Ok(bytes) = transport.download(DOCUMENTATION_URL) else {
        return result;
    };
    let value = serde_json::from_slice::<Value>(&bytes);
    let Some(paths) = value
        .as_ref()
        .ok()
        .and_then(|v| v.get("paths"))
        .and_then(Value::as_object)
    else {
        result.status = "invalid_document";
        return result;
    };
    result.status = "available";
    for (path, operations) in paths {
        if operations.get("post").is_some()
            && path.starts_with('/')
            && validation::validate_model_path(&path[1..]).is_ok()
        {
            result.documented_post_paths.push(path.clone());
        }
    }
    result.documented_post_paths.sort();
    result
}

pub fn check(transport: &dyn Transport, credential: &str, spec: &Spec) -> Result<Report, Error> {
    validate(spec)?;
    let mut report = Report {
        schema_version: 1,
        checked_unix_seconds: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| Error::Io("system clock precedes Unix epoch".into()))?
            .as_secs(),
        credentials_verified_by_estimate: false,
        generation_submitted: false,
        balance: "unverified: no documented balance endpoint configured",
        documentation: documentation(transport),
        probes: Vec::new(),
        limitation: "An accepted estimate verifies only that key, model path and payload for pricing. It does not prove generation access, balance, output quality or distribution rights. The supplementary OpenAPI document is not a complete catalog; a missing path does not prove a model is unavailable.",
    };
    let mut unauthorized = false;
    for probe in &spec.probes {
        let mut result = ProbeResult {
            model: probe.model.clone(),
            http_status: None,
            status: "skipped_after_invalid_credentials",
            estimated_usd: None,
        };
        if !unauthorized {
            // This fixed prefix is the only authenticated operation in this module.
            let response = transport.send(
                credential,
                &Request {
                    method: Method::Post,
                    url: format!("{API_BASE}/estimate/{}", probe.model),
                    body: Some(probe.params.to_string()),
                },
            );
            result.status = "transport_failed";
            if let Ok(response) = response {
                result.http_status = Some(response.status);
                result.status = match response.status {
                    200 => "invalid_estimate",
                    401 => "invalid_credentials",
                    403 => "forbidden",
                    404 => "route_missing_or_unavailable",
                    400 | 422 => "payload_rejected",
                    402 => "payment_required",
                    423 => "model_locked",
                    429 => "rate_limited",
                    500..=599 => "service_unavailable",
                    _ => "unexpected_status",
                };
                unauthorized = response.status == 401;
                if response.status == 200 {
                    if let Ok(usd) = serde_json::from_str::<Value>(&response.body)
                        .map_err(|_| ())
                        .and_then(|v| parse_usd(&v).map_err(|_| ()))
                    {
                        result.status = "estimate_accepted";
                        result.estimated_usd = Some(usd);
                        report.credentials_verified_by_estimate = true;
                    }
                }
            }
        }
        report.probes.push(result);
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Response;
    use std::cell::RefCell;
    use std::collections::VecDeque;

    struct Fake {
        replies: RefCell<VecDeque<Result<Response, Error>>>,
        sent: RefCell<Vec<Request>>,
        docs: Option<Vec<u8>>,
    }

    impl Transport for Fake {
        fn send(&self, _: &str, request: &Request) -> Result<Response, Error> {
            self.sent.borrow_mut().push(request.clone());
            self.replies
                .borrow_mut()
                .pop_front()
                .expect("unexpected API call")
        }
        fn download(&self, url: &str) -> Result<Vec<u8>, Error> {
            assert_eq!(url, DOCUMENTATION_URL);
            self.docs
                .clone()
                .ok_or_else(|| Error::Transport("offline".into()))
        }
    }

    fn fake(replies: Vec<(u16, &str)>) -> Fake {
        Fake {
            replies: RefCell::new(replies.into_iter().map(|(status, body)| Ok(Response {status, body: body.into()})).collect()),
            sent: RefCell::new(Vec::new()),
            docs: Some(br#"{"paths":{"/model/v1":{"post":{}},"/requests/{id}/status":{"get":{}},"/bad?secret=x":{"post":{}}}}"#.to_vec()),
        }
    }

    #[test]
    fn only_prices_raw_payloads_and_never_generates_or_uploads() {
        let transport = fake(vec![(200, r#"{"usd":"0.025","echo":"secret-pair"}"#)]);
        let spec =
            parse_spec(r#"{"probes":[{"model":"model/v1","params":{"pose_mode":"a-pose"}}]}"#)
                .unwrap();
        let report = check(&transport, "secret-pair", &spec).unwrap();
        assert!(report.credentials_verified_by_estimate);
        assert!(!report.generation_submitted);
        assert_eq!(report.probes[0].estimated_usd, Some(0.025));
        assert_eq!(report.documentation.documented_post_paths, ["/model/v1"]);
        let calls = transport.sent.borrow();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].method, Method::Post);
        assert_eq!(calls[0].url, "https://api.higgsfield.ai/estimate/model/v1");
        assert_eq!(
            serde_json::from_str::<Value>(calls[0].body.as_ref().unwrap()).unwrap(),
            spec.probes[0].params
        );
        assert!(!serde_json::to_string(&report)
            .unwrap()
            .contains("secret-pair"));
    }

    #[test]
    fn failures_do_not_claim_access_or_echo_untrusted_bodies() {
        for (code, status) in [
            (401, "invalid_credentials"),
            (403, "forbidden"),
            (404, "route_missing_or_unavailable"),
            (400, "payload_rejected"),
            (422, "payload_rejected"),
            (402, "payment_required"),
            (423, "model_locked"),
            (429, "rate_limited"),
            (503, "service_unavailable"),
            (302, "unexpected_status"),
        ] {
            let transport = fake(vec![(code, "credential-reflected")]);
            let report = check(&transport, "credential-reflected", &default_spec()).unwrap();
            assert_eq!(report.probes[0].status, status);
            assert!(!report.credentials_verified_by_estimate);
            assert!(!serde_json::to_string(&report)
                .unwrap()
                .contains("credential-reflected"));
        }
        for body in [
            "bad-json",
            r#"{"usd":-1}"#,
            r#"{"usd":"NaN"}"#,
            r#"{"credits":3}"#,
        ] {
            let report = check(&fake(vec![(200, body)]), "key", &default_spec()).unwrap();
            assert_eq!(report.probes[0].status, "invalid_estimate");
            assert!(!report.credentials_verified_by_estimate);
        }
    }

    #[test]
    fn stops_after_unauthorized_and_redacts_transport_errors() {
        let spec =
            parse_spec(r#"{"probes":[{"model":"a","params":{}},{"model":"b","params":{}}]}"#)
                .unwrap();
        let transport = fake(vec![(401, "invalid")]);
        let report = check(&transport, "key", &spec).unwrap();
        assert_eq!(transport.sent.borrow().len(), 1);
        assert_eq!(report.probes[1].status, "skipped_after_invalid_credentials");
        let mut transport = fake(vec![]);
        transport.docs = None;
        transport
            .replies
            .borrow_mut()
            .push_back(Err(Error::Transport("secret-pair".into())));
        let report = check(&transport, "secret-pair", &default_spec()).unwrap();
        assert_eq!(report.probes[0].status, "transport_failed");
        assert_eq!(report.documentation.status, "unavailable");
        assert!(!serde_json::to_string(&report)
            .unwrap()
            .contains("secret-pair"));
        transport.docs = Some(b"not json".to_vec());
        transport.replies.borrow_mut().push_back(Ok(Response {
            status: 200,
            body: r#"{"usd":0}"#.into(),
        }));
        assert_eq!(
            check(&transport, "key", &default_spec())
                .unwrap()
                .documentation
                .status,
            "invalid_document"
        );
    }

    #[test]
    fn rejects_invalid_specs_before_any_effect() {
        for text in [
            r#"{"probes":[]}"#,
            r#"{"probes":[{"model":"../generate","params":{}}]}"#,
            r#"{"probes":[{"model":"a?key=x","params":{}}]}"#,
            r#"{"probes":[{"model":"a","params":[]}]}"#,
            r#"{"probes":[{"model":"a","params":{},"extra":1}]}"#,
            r#"{"probes":[],"secret":"reflected"}"#,
            "not-json",
        ] {
            assert!(parse_spec(text).is_err());
        }
        assert!(parse_spec(&" ".repeat(MAX_SPEC_BYTES + 1)).is_err());
        let oversized = Spec {
            probes: (0..33)
                .map(|_| Probe {
                    model: "a".into(),
                    params: serde_json::json!({}),
                })
                .collect(),
        };
        let transport = fake(vec![]);
        assert!(check(&transport, "key", &oversized).is_err());
        assert!(transport.sent.borrow().is_empty());
        let oversized = Spec {
            probes: vec![Probe {
                model: "a".into(),
                params: serde_json::json!({"prompt":"x".repeat(MAX_SPEC_BYTES)}),
            }],
        };
        assert!(check(&transport, "key", &oversized).is_err());
    }
}
