//! Free decision models that run on this machine.
//!
//! Two providers cost nothing and need no key:
//!
//! - `ollama` asks APUS-OpenJev-v1 (Apache 2.0, fine-tuned from Qwen3.5) through
//!   a local Ollama server. The model does not write JSON: it scores 2 to 16
//!   caller-supplied candidates, each given a letter A to P, and the answer is
//!   read from the log probabilities of those letters at the first output
//!   position. The prompt here reproduces the published training contract
//!   (`jev.dynamic.prompt.v2`, `openjev_contracts.py` in the GGUF repository,
//!   checked 2026-09-26) byte for byte, wrapped in the no-thinking Qwen turn and
//!   sent in raw mode so Ollama's own renderer cannot open a thinking block.
//! - `openjev` posts the TypeSafe `systemone` body to a server the user runs
//!   themselves. The openjev/openjev weights are CC BY-NC 4.0, non-commercial
//!   only, so fragr never bundles, downloads, or defaults to them.
//!
//! Both are reached on loopback only unless the caller explicitly allows a
//! remote host. Every reply is untrusted: bounded, parsed strictly, checked
//! against the questions actually asked, and turned into an error (and so a
//! local-rules fallback) when anything is off. The whole decision, every
//! question included, has one latency budget; a late answer is a timeout.

use crate::decision::{Answer, DecisionResponse, Question};
use crate::provider::{api_error_message, parse_decision, HttpRequest, HttpResponse, Method};
use crate::provider::{Provider, Transport};
use crate::Error;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::net::IpAddr;
use std::time::{Duration, Instant};

/// Ollama's default listener.
pub const OLLAMA_BASE_URL: &str = "http://127.0.0.1:11434";
/// The openjev helper's documented listener (`helper/shim.py --port 3000`).
pub const OPENJEV_BASE_URL: &str = "http://127.0.0.1:3000";
/// The recommended quantization of the 4B model, as Ollama names a Hugging Face pull.
pub const APUS_OLLAMA_MODEL: &str = "hf.co/apus-ailab/APUS-OpenJev-v1-4B-GGUF:Q8_0";
/// The model name the openjev helper answers to.
pub const OPENJEV_MODEL: &str = "openjev";
/// Candidate letters, one tokenizer token each in the trained contract.
pub const LABELS: [&str; 16] = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
];
pub const MIN_CANDIDATES: usize = 2;
pub const MAX_CANDIDATES: usize = LABELS.len();
/// Context the published Modelfile sets; matching it avoids a model reload.
pub const NUM_CTX: u32 = 9216;
/// A rendered prompt above this many bytes is refused rather than silently
/// truncated. A token is at least one byte, so it always fits `NUM_CTX`.
pub const MAX_PROMPT_BYTES: usize = 8192;
/// Ollama returns at most twenty alternatives per position.
pub const TOP_LOGPROBS: u32 = 20;
/// A local reply larger than this is not a decision.
pub const MAX_REPLY_BYTES: usize = 64 * 1024;
/// How long the first request may take while Ollama loads the weights.
pub const WARMUP_TIMEOUT: Duration = Duration::from_secs(180);
/// How long Ollama keeps the weights loaded between decisions.
pub const KEEP_ALIVE: &str = "10m";
/// The trained no-thinking Qwen turn around the rendered prompt.
const TURN_OPEN: &str = "<|im_start|>user\n";
const TURN_CLOSE: &str = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
/// A log probability is at most zero; allow rounding noise above it.
const LOGPROB_SLACK: f64 = 1e-6;
/// Probabilities from a systemone server must add up to one within this.
const SUM_TOLERANCE: f64 = 1e-3;

/// Check a local model's base URL. Loopback (`localhost`, 127.0.0.0/8, `::1`)
/// is accepted; anything else needs `allow_remote`. Credentials, queries and
/// fragments are refused either way. Returns the URL without a trailing slash.
pub fn checked_base_url(url: &str, allow_remote: bool) -> Result<String, Error> {
    let parsed = reqwest::Url::parse(url.trim())
        .map_err(|err| Error::InvalidArgument(format!("model url {url:?}: {err}")))?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err(Error::InvalidArgument(format!(
            "model url {url:?} must be http or https"
        )));
    }
    if !parsed.username().is_empty() || parsed.password().is_some() {
        return Err(Error::InvalidArgument(
            "model url must not carry credentials".to_string(),
        ));
    }
    if parsed.query().is_some() || parsed.fragment().is_some() {
        return Err(Error::InvalidArgument(
            "model url must not carry a query or fragment".to_string(),
        ));
    }
    let host = parsed.host_str().unwrap_or("");
    if !allow_remote && !is_loopback_host(host) {
        return Err(Error::InvalidArgument(format!(
            "model url host {host:?} is not loopback; pass --allow-remote-model to use it"
        )));
    }
    Ok(parsed.as_str().trim_end_matches('/').to_string())
}

/// Whether a URL host names this machine.
pub fn is_loopback_host(host: &str) -> bool {
    if host.eq_ignore_ascii_case("localhost") {
        return true;
    }
    host.trim_start_matches('[')
        .trim_end_matches(']')
        .parse::<IpAddr>()
        .is_ok_and(|ip| ip.is_loopback())
}

/// One candidate as the model sees it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub id: String,
    pub description: String,
}

/// How a question's letter distribution becomes an answer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Readout {
    /// Named options; the answer is the most likely one.
    Choice,
    /// The canonical yes and no pair; the answer is the probability of yes.
    Noul,
    /// Ordered levels asked as a choice; the answer carries the expectation.
    Score,
}

/// A question in the model's own shape: a primitive, instructions and candidates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Scoring {
    pub primitive: &'static str,
    pub instructions: String,
    pub candidates: Vec<Candidate>,
    pub readout: Readout,
}

fn nonempty(text: &str) -> bool {
    !text.trim().is_empty()
}

/// Map one of fragr's typed questions onto the candidate contract. A score is
/// asked as a choice over its levels (the model's own `score_level` judges a
/// single proposition and is not an ordinal scale). A question with fewer than
/// two or more than sixteen candidates, or an empty text, cannot be asked and
/// returns `None`; the plan keeps local rules for that field.
pub fn scoring_for(question: &Question) -> Option<Scoring> {
    let scoring = match question {
        Question::Choice {
            instructions,
            criteria,
        } => Scoring {
            primitive: "choice",
            instructions: instructions.clone(),
            // The id rides in the description because the prompt shows only
            // descriptions, and the state names weapons and stances by id.
            candidates: criteria
                .iter()
                .map(|(id, text)| Candidate {
                    id: id.clone(),
                    description: format!("{id}: {text}"),
                })
                .collect(),
            readout: Readout::Choice,
        },
        Question::Noul {
            instructions,
            criteria,
        } => {
            let mut text = instructions.clone();
            if let Some(criteria) = criteria {
                text.push_str(&format!(
                    " True when: {} False when: {}",
                    criteria.yes, criteria.no
                ));
            }
            Scoring {
                primitive: "noul",
                instructions: text,
                candidates: vec![
                    Candidate {
                        id: "yes".to_string(),
                        description: "The stated proposition is true.".to_string(),
                    },
                    Candidate {
                        id: "no".to_string(),
                        description: "The stated proposition is false.".to_string(),
                    },
                ],
                readout: Readout::Noul,
            }
        }
        Question::Score {
            instructions,
            criteria,
        } => Scoring {
            primitive: "choice",
            instructions: instructions.clone(),
            candidates: criteria
                .iter()
                .enumerate()
                .map(|(index, text)| Candidate {
                    id: index.to_string(),
                    description: text.clone(),
                })
                .collect(),
            readout: Readout::Score,
        },
    };
    let count = scoring.candidates.len();
    let texts_ok = nonempty(&scoring.instructions)
        && scoring
            .candidates
            .iter()
            .all(|c| nonempty(&c.id) && nonempty(&c.description));
    ((MIN_CANDIDATES..=MAX_CANDIDATES).contains(&count) && texts_ok).then_some(scoring)
}

fn json_string(text: &str) -> String {
    // serde_json escapes the same set Python's json.dumps(ensure_ascii=False)
    // does: quote, backslash, and control characters, with lowercase hex.
    serde_json::to_string(text).unwrap_or_else(|_| "\"\"".to_string())
}

/// The state as the model reads it: text as given, anything else as compact JSON.
pub fn state_text(state: &Value) -> Result<String, Error> {
    let text = match state {
        Value::String(text) => text.clone(),
        other => other.to_string(),
    };
    if nonempty(&text) {
        Ok(text)
    } else {
        Err(Error::InvalidArgument(
            "the decision state is empty".to_string(),
        ))
    }
}

/// Render the prompt exactly as `render_prompt` in `openjev_contracts.py`:
/// the shared state, then the task as sorted-key JSON with Python's default
/// separators, then the letter instruction.
pub fn render_prompt(state: &str, scoring: &Scoring) -> String {
    let labels = &LABELS[..scoring.candidates.len()];
    let criteria: Vec<String> = labels
        .iter()
        .zip(&scoring.candidates)
        .map(|(label, candidate)| {
            format!(
                "{{\"description\": {}, \"label\": {}}}",
                json_string(&candidate.description),
                json_string(label)
            )
        })
        .collect();
    let task = format!(
        "{{\"criteria\": [{}], \"instructions\": {}, \"primitive\": {}}}",
        criteria.join(", "),
        json_string(&scoring.instructions),
        json_string(scoring.primitive)
    );
    format!(
        "Shared state:\n{state}\n\n{task}\nReturn only the selected letter: {}.\nAnswer:",
        labels.join(", ")
    )
}

/// One scoring request to Ollama: raw mode with the trained turn, one token,
/// greedy, with the top letter alternatives.
pub fn ollama_request(base_url: &str, model: &str, prompt: &str, timeout: Duration) -> HttpRequest {
    HttpRequest {
        method: Method::Post,
        url: format!("{base_url}/api/generate"),
        headers: vec![("Content-Type".to_string(), "application/json".to_string())],
        body: Some(json!({
            "model": model,
            "prompt": format!("{TURN_OPEN}{prompt}{TURN_CLOSE}"),
            "raw": true,
            "think": false,
            "stream": false,
            "logprobs": true,
            "top_logprobs": TOP_LOGPROBS,
            "keep_alive": KEEP_ALIVE,
            "options": {"temperature": 0, "num_predict": 1, "num_ctx": NUM_CTX},
        })),
        timeout: Some(timeout),
    }
}

/// Ask Ollama to load the model without generating, so the first decision in
/// play does not pay the load time. A missing model answers 404.
pub fn ollama_warmup_request(base_url: &str, model: &str) -> HttpRequest {
    HttpRequest {
        method: Method::Post,
        url: format!("{base_url}/api/generate"),
        headers: vec![("Content-Type".to_string(), "application/json".to_string())],
        body: Some(json!({"model": model, "keep_alive": KEEP_ALIVE, "stream": false})),
        timeout: Some(WARMUP_TIMEOUT),
    }
}

/// Send the warmup and explain a missing model in terms of the fix.
pub fn warm_up(transport: &dyn Transport, base_url: &str, model: &str) -> Result<(), Error> {
    let response = transport.send(&ollama_warmup_request(base_url, model))?;
    match response.status {
        200..=299 => Ok(()),
        404 => Err(Error::InvalidArgument(format!(
            "Ollama has no model {model:?}; pull it first with `ollama pull {model}`"
        ))),
        status => Err(Error::Api {
            status,
            message: api_error_message(&response.body),
        }),
    }
}

/// A systemone decision request for a self-hosted openjev helper: the same
/// body the TypeSafe provider sends, no key, loopback base URL.
pub fn systemone_request(
    base_url: &str,
    model: &str,
    state: &Value,
    questions: &BTreeMap<String, Question>,
    timeout: Duration,
) -> HttpRequest {
    HttpRequest {
        method: Method::Post,
        url: format!("{base_url}/v1/systemone"),
        headers: vec![("Content-Type".to_string(), "application/json".to_string())],
        body: Some(json!({"model": model, "state": state, "questions": questions})),
        timeout: Some(timeout),
    }
}

#[derive(Debug, Deserialize)]
struct TokenLogprob {
    token: String,
    logprob: f64,
}

#[derive(Debug, Deserialize)]
struct PositionLogprob {
    token: String,
    logprob: f64,
    #[serde(default)]
    top_logprobs: Vec<TokenLogprob>,
}

#[derive(Debug, Deserialize)]
struct GenerateReply {
    response: String,
    #[serde(default)]
    logprobs: Option<Vec<PositionLogprob>>,
}

fn bounded(response: &HttpResponse) -> Result<(), Error> {
    if !(200..300).contains(&response.status) {
        return Err(Error::Api {
            status: response.status,
            message: api_error_message(&response.body),
        });
    }
    if response.body.len() > MAX_REPLY_BYTES {
        return Err(Error::Malformed(format!(
            "local reply of {} bytes is over the {MAX_REPLY_BYTES} byte bound",
            response.body.len()
        )));
    }
    Ok(())
}

fn shown(text: &str) -> String {
    text.chars()
        .filter(|c| !c.is_control())
        .take(24)
        .collect::<String>()
}

/// The letter distribution from one Ollama reply, in candidate order.
///
/// The selected token must be one of the offered letters. Letters missing from
/// the twenty alternatives are given the lowest returned log probability, an
/// upper bound on their true value, which can only narrow the margin the gate
/// reads and so never makes an answer look more certain than it was.
pub fn letter_distribution(response: &HttpResponse, count: usize) -> Result<Vec<f64>, Error> {
    bounded(response)?;
    if !(MIN_CANDIDATES..=MAX_CANDIDATES).contains(&count) {
        return Err(Error::InvalidArgument(format!(
            "{count} candidates; the model scores {MIN_CANDIDATES} to {MAX_CANDIDATES}"
        )));
    }
    let reply: GenerateReply =
        serde_json::from_slice(&response.body).map_err(|err| Error::Malformed(err.to_string()))?;
    let positions = reply
        .logprobs
        .ok_or_else(|| Error::Malformed("no logprobs in the reply".to_string()))?;
    let [position] = positions.as_slice() else {
        return Err(Error::Malformed(format!(
            "expected one scored position, got {}",
            positions.len()
        )));
    };
    let labels = &LABELS[..count];
    let selected = reply.response.trim();
    if !labels.contains(&selected) {
        return Err(Error::Malformed(format!(
            "model answered {:?}, not one of the offered letters",
            shown(&reply.response)
        )));
    }
    let mut floor = f64::INFINITY;
    let mut found: BTreeMap<&str, f64> = BTreeMap::new();
    let alternatives = position
        .top_logprobs
        .iter()
        .map(|entry| (entry.token.as_str(), entry.logprob))
        .chain(std::iter::once((position.token.as_str(), position.logprob)));
    for (token, logprob) in alternatives {
        if !logprob.is_finite() || logprob > LOGPROB_SLACK {
            return Err(Error::Malformed(format!(
                "log probability {logprob} is not a log probability"
            )));
        }
        floor = floor.min(logprob);
        if let Some(label) = labels.iter().find(|label| **label == token) {
            let entry = found.entry(label).or_insert(f64::NEG_INFINITY);
            *entry = entry.max(logprob);
        }
    }
    if !found.contains_key(selected) {
        return Err(Error::Malformed(
            "the selected letter is missing from its own log probabilities".to_string(),
        ));
    }
    let logprobs: Vec<f64> = labels
        .iter()
        .map(|label| found.get(label).copied().unwrap_or(floor))
        .collect();
    let peak = logprobs.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let weights: Vec<f64> = logprobs.iter().map(|lp| (lp - peak).exp()).collect();
    let total: f64 = weights.iter().sum();
    Ok(weights.into_iter().map(|w| w / total).collect())
}

/// Build the answer for one question from its candidate distribution.
pub fn answer_from(scoring: &Scoring, distribution: &[f64]) -> Answer {
    let probabilities: BTreeMap<String, f64> = scoring
        .candidates
        .iter()
        .zip(distribution)
        .map(|(candidate, p)| (candidate.id.clone(), *p))
        .collect();
    match scoring.readout {
        Readout::Choice => {
            let mut best = 0;
            for (index, p) in distribution.iter().enumerate() {
                if *p > distribution[best] {
                    best = index;
                }
            }
            Answer::Choice {
                choice: scoring.candidates[best].id.clone(),
                // The letter probabilities are uncalibrated relative
                // preferences, so no confidence is claimed: only the margin
                // gate can accept them.
                confidence: None,
                probabilities,
            }
        }
        Readout::Noul => Answer::Noul {
            noul: distribution[0],
        },
        Readout::Score => Answer::Score {
            score: distribution
                .iter()
                .enumerate()
                .map(|(index, p)| index as f64 * p)
                .sum(),
            confidence: None,
            legend: Value::Null,
            probabilities,
        },
    }
}

fn in_unit(value: f64) -> bool {
    value.is_finite() && (0.0..=1.0).contains(&value)
}

fn check_distribution(
    name: &str,
    probabilities: &BTreeMap<String, f64>,
    allowed: impl Fn(&str) -> bool,
) -> Result<(), Error> {
    for (key, p) in probabilities {
        if !allowed(key) || !in_unit(*p) {
            return Err(Error::Malformed(format!(
                "answer {name:?} has an invalid probability for {:?}",
                shown(key)
            )));
        }
    }
    if !probabilities.is_empty() {
        let total: f64 = probabilities.values().sum();
        if (total - 1.0).abs() > SUM_TOLERANCE {
            return Err(Error::Malformed(format!(
                "answer {name:?} probabilities add up to {total}"
            )));
        }
    }
    Ok(())
}

/// Keep only answers to the questions asked, and refuse any answer whose type,
/// option, level, or probability does not fit its question. `required` makes
/// a missing answer an error (a systemone server answers every question).
pub fn validate_answers(
    questions: &BTreeMap<String, Question>,
    answers: BTreeMap<String, Answer>,
    required: bool,
) -> Result<BTreeMap<String, Answer>, Error> {
    let mut kept = BTreeMap::new();
    for (name, question) in questions {
        let Some(answer) = answers.get(name) else {
            if required {
                return Err(Error::Malformed(format!("no answer for {name:?}")));
            }
            continue;
        };
        let confidence_ok = |c: &Option<f64>| c.is_none_or(in_unit);
        match (question, answer) {
            (
                Question::Choice { criteria, .. },
                Answer::Choice {
                    choice,
                    confidence,
                    probabilities,
                },
            ) => {
                if !criteria.contains_key(choice) || !confidence_ok(confidence) {
                    return Err(Error::Malformed(format!(
                        "answer {name:?} chose {:?}, which was not offered",
                        shown(choice)
                    )));
                }
                check_distribution(name, probabilities, |key| criteria.contains_key(key))?;
            }
            (
                Question::Score { criteria, .. },
                Answer::Score {
                    score,
                    confidence,
                    probabilities,
                    ..
                },
            ) => {
                let top = criteria.len().saturating_sub(1) as f64;
                if !score.is_finite() || *score < 0.0 || *score > top || !confidence_ok(confidence)
                {
                    return Err(Error::Malformed(format!(
                        "answer {name:?} score {score} is outside its levels"
                    )));
                }
                check_distribution(name, probabilities, |key| {
                    key.parse::<usize>().is_ok_and(|i| i < criteria.len())
                })?;
            }
            (Question::Noul { .. }, Answer::Noul { noul }) => {
                if !in_unit(*noul) {
                    return Err(Error::Malformed(format!(
                        "answer {name:?} probability {noul} is not a probability"
                    )));
                }
            }
            _ => {
                return Err(Error::Malformed(format!(
                    "answer {name:?} does not match its question type"
                )))
            }
        }
        kept.insert(name.clone(), answer.clone());
    }
    Ok(kept)
}

fn remaining(started: Instant, budget: Duration) -> Result<Duration, Error> {
    budget
        .checked_sub(started.elapsed())
        .filter(|left| !left.is_zero())
        .ok_or_else(|| {
            Error::Timeout(format!(
                "local decision over its {} ms budget",
                budget.as_millis()
            ))
        })
}

/// Ask APUS-OpenJev through Ollama, one scoring request per askable question,
/// all inside one latency budget.
pub fn decide_ollama(
    transport: &dyn Transport,
    base_url: &str,
    model: &str,
    state: &Value,
    questions: &BTreeMap<String, Question>,
    budget: Duration,
) -> Result<DecisionResponse, Error> {
    let started = Instant::now();
    let state = state_text(state)?;
    let mut answers = BTreeMap::new();
    for (name, question) in questions {
        let Some(scoring) = scoring_for(question) else {
            continue;
        };
        let prompt = render_prompt(&state, &scoring);
        if prompt.len() > MAX_PROMPT_BYTES {
            return Err(Error::InvalidArgument(format!(
                "prompt for {name:?} is {} bytes, over the {MAX_PROMPT_BYTES} byte bound",
                prompt.len()
            )));
        }
        let request = ollama_request(base_url, model, &prompt, remaining(started, budget)?);
        let response = transport.send(&request)?;
        let distribution = letter_distribution(&response, scoring.candidates.len())?;
        answers.insert(name.clone(), answer_from(&scoring, &distribution));
    }
    remaining(started, budget)?;
    if answers.is_empty() {
        return Err(Error::InvalidArgument(
            "no question fits the candidate contract".to_string(),
        ));
    }
    Ok(DecisionResponse {
        id: None,
        model: model.to_string(),
        provider: Some(Provider::Ollama.name().to_string()),
        answers: validate_answers(questions, answers, false)?,
        usage: None,
    })
}

/// Ask a self-hosted openjev helper once for every question.
pub fn decide_openjev(
    transport: &dyn Transport,
    base_url: &str,
    model: &str,
    state: &Value,
    questions: &BTreeMap<String, Question>,
    budget: Duration,
) -> Result<DecisionResponse, Error> {
    let started = Instant::now();
    if questions.is_empty() {
        return Err(Error::InvalidArgument("at least one question".to_string()));
    }
    let request = systemone_request(
        base_url,
        model,
        state,
        questions,
        remaining(started, budget)?,
    );
    let response = transport.send(&request)?;
    bounded(&response)?;
    let parsed = parse_decision(&response)?;
    remaining(started, budget)?;
    Ok(DecisionResponse {
        // The server's own id, model and billing fields are not trusted or needed.
        id: None,
        model: model.to_string(),
        provider: Some(Provider::OpenJev.name().to_string()),
        answers: validate_answers(questions, parsed.answers, true)?,
        usage: None,
    })
}

/// One free local decision through whichever local provider is configured.
pub fn decide(
    transport: &dyn Transport,
    provider: Provider,
    base_url: &str,
    model: &str,
    state: &Value,
    questions: &BTreeMap<String, Question>,
    budget: Duration,
) -> Result<DecisionResponse, Error> {
    match provider {
        Provider::Ollama => decide_ollama(transport, base_url, model, state, questions, budget),
        Provider::OpenJev => decide_openjev(transport, base_url, model, state, questions, budget),
        other => Err(Error::InvalidArgument(format!(
            "{} is not a local model provider",
            other.name()
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decision::{campaign_questions, tactical_questions, NoulCriteria, Q_DANGER};
    use crate::provider::fakes::FakeTransport;
    use fragr_server::protocol::WeaponType;

    fn reply(response: &str, alternatives: &[(&str, f64)]) -> HttpResponse {
        let top: Vec<Value> = alternatives
            .iter()
            .map(|(token, logprob)| json!({"token": token, "logprob": logprob}))
            .collect();
        let chosen = alternatives
            .iter()
            .find(|(token, _)| *token == response)
            .map_or(-0.1, |(_, lp)| *lp);
        HttpResponse {
            status: 200,
            body: json!({
                "model": APUS_OLLAMA_MODEL,
                "response": response,
                "done": true,
                "logprobs": [{"token": response, "logprob": chosen, "top_logprobs": top}],
            })
            .to_string()
            .into_bytes(),
        }
    }

    fn ok(body: Value) -> HttpResponse {
        HttpResponse {
            status: 200,
            body: body.to_string().into_bytes(),
        }
    }

    /// A transport that answers every scoring request with the same letters
    /// and records every request it saw.
    struct Letters {
        reply: HttpResponse,
        seen: std::sync::Mutex<Vec<HttpRequest>>,
        delay: Duration,
    }

    impl Transport for Letters {
        fn send(&self, request: &HttpRequest) -> Result<HttpResponse, Error> {
            std::thread::sleep(self.delay);
            self.seen.lock().unwrap().push(request.clone());
            Ok(self.reply.clone())
        }
    }

    fn letters(reply: HttpResponse, delay: Duration) -> Letters {
        Letters {
            reply,
            seen: std::sync::Mutex::new(Vec::new()),
            delay,
        }
    }

    #[test]
    fn loopback_is_required_unless_allowed() {
        for url in [
            "http://127.0.0.1:11434",
            "http://127.0.0.1:11434/",
            "http://localhost:3000",
            "http://LOCALHOST:3000",
            "http://127.9.9.9:1",
            "http://[::1]:11434",
            "https://127.0.0.1",
        ] {
            assert!(checked_base_url(url, false).is_ok(), "{url}");
        }
        assert_eq!(
            checked_base_url("http://127.0.0.1:11434/", false).unwrap(),
            "http://127.0.0.1:11434"
        );
        for url in [
            "http://192.168.1.20:11434",
            "http://10.0.0.1",
            "http://0.0.0.0:11434",
            "http://example.com",
            "http://localhost.example.com",
            "http://[::]:1",
        ] {
            let err = checked_base_url(url, false).unwrap_err();
            assert!(err.to_string().contains("--allow-remote-model"), "{url}");
            assert!(checked_base_url(url, true).is_ok(), "{url} with the flag");
        }
        for url in [
            "ftp://127.0.0.1",
            "file:///etc/passwd",
            "http://user:pw@127.0.0.1",
            "http://127.0.0.1/?x=1",
            "http://127.0.0.1/#f",
            "not a url",
        ] {
            assert!(
                matches!(checked_base_url(url, true), Err(Error::InvalidArgument(_))),
                "{url}"
            );
        }
        assert!(is_loopback_host("::1"));
        assert!(!is_loopback_host(""));
    }

    #[test]
    fn prompt_matches_the_published_contract() {
        // The support example from the model's own client, rendered by
        // openjev_contracts.render_prompt.
        let scoring = Scoring {
            primitive: "choice",
            instructions: "Select the next support action.".to_string(),
            candidates: vec![
                Candidate {
                    id: "close_ticket".into(),
                    description: "Close the ticket as resolved.".into(),
                },
                Candidate {
                    id: "escalate".into(),
                    description: "Escalate to a human agent.".into(),
                },
                Candidate {
                    id: "refund".into(),
                    description: "Issue a refund.".into(),
                },
            ],
            readout: Readout::Choice,
        };
        let expected = "Shared state:\nOrder 731 was delivered. The customer confirms that the issue is resolved.\n\n{\"criteria\": [{\"description\": \"Close the ticket as resolved.\", \"label\": \"A\"}, {\"description\": \"Escalate to a human agent.\", \"label\": \"B\"}, {\"description\": \"Issue a refund.\", \"label\": \"C\"}], \"instructions\": \"Select the next support action.\", \"primitive\": \"choice\"}\nReturn only the selected letter: A, B, C.\nAnswer:";
        assert_eq!(
            render_prompt(
                "Order 731 was delivered. The customer confirms that the issue is resolved.",
                &scoring
            ),
            expected
        );
        let quoted = Scoring {
            instructions: "Say \"hi\"\tthen\u{1}stop, café".into(),
            ..scoring
        };
        assert!(render_prompt("s", &quoted)
            .contains(r#""instructions": "Say \"hi\"\tthen\u0001stop, café""#));
    }

    #[test]
    fn fragr_questions_map_to_candidates() {
        let questions = tactical_questions();
        let stance = scoring_for(&questions["stance"]).unwrap();
        assert_eq!(stance.primitive, "choice");
        assert_eq!(stance.readout, Readout::Choice);
        assert_eq!(stance.candidates.len(), 4);
        assert!(stance.candidates[0]
            .description
            .starts_with(&format!("{}: ", stance.candidates[0].id)));
        let danger = scoring_for(&questions[Q_DANGER]).unwrap();
        assert_eq!(danger.primitive, "choice");
        assert_eq!(danger.readout, Readout::Score);
        let ids: Vec<&str> = danger.candidates.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, ["0", "1", "2", "3", "4"]);
        let noul = scoring_for(&Question::Noul {
            instructions: "Is the fighter stuck?".into(),
            criteria: Some(NoulCriteria {
                yes: "No progress for a second.".into(),
                no: "Moving.".into(),
            }),
        })
        .unwrap();
        assert_eq!(noul.primitive, "noul");
        assert_eq!(noul.candidates[0].id, "yes");
        assert_eq!(noul.candidates[1].id, "no");
        assert!(noul.instructions.contains("True when: No progress"));
        let bare = scoring_for(&Question::Noul {
            instructions: "Stuck?".into(),
            criteria: None,
        })
        .unwrap();
        assert_eq!(bare.instructions, "Stuck?");
        // One carried weapon is not a decision; seventeen levels do not fit.
        let fists = campaign_questions(&[WeaponType::Fists]);
        assert!(scoring_for(&fists["weapon"]).is_none());
        let wide = Question::Score {
            instructions: "x".into(),
            criteria: (0..17).map(|i| format!("level {i}")).collect(),
        };
        assert!(scoring_for(&wide).is_none());
        let blank = Question::Choice {
            instructions: " ".into(),
            criteria: BTreeMap::from([("a".into(), "x".into()), ("b".into(), "y".into())]),
        };
        assert!(scoring_for(&blank).is_none());
        assert_eq!(state_text(&json!("words")).unwrap(), "words");
        assert_eq!(state_text(&json!({"a": 1})).unwrap(), r#"{"a":1}"#);
        assert!(matches!(
            state_text(&json!("  ")),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn letter_distributions_are_read_strictly() {
        let good = reply("B", &[("B", -0.2), ("A", -2.0), ("C", -3.0), ("x", -4.0)]);
        let dist = letter_distribution(&good, 3).unwrap();
        assert!((dist.iter().sum::<f64>() - 1.0).abs() < 1e-9);
        assert!(dist[1] > dist[0] && dist[0] > dist[2]);
        // A missing letter takes the lowest returned value, never more.
        let partial = reply("A", &[("A", -0.1), ("B", -1.0), ("zz", -9.0)]);
        let dist = letter_distribution(&partial, 3).unwrap();
        assert!(dist[2] < dist[1] && dist[2] > 0.0);
        let cases = vec![
            reply("Q", &[("Q", -0.1), ("A", -2.0)]),
            reply("The", &[("The", -0.1), ("A", -2.0)]),
            reply("A", &[("A", 0.5), ("B", -2.0)]),
            reply("A", &[("A", f64::NAN)]),
            ok(json!({"response": "A"})),
            ok(json!({"response": "A", "logprobs": []})),
            ok(json!({"response": "A", "logprobs": [
                {"token": "A", "logprob": -0.1},
                {"token": "B", "logprob": -0.1}
            ]})),
            ok(
                json!({"response": "A", "logprobs": [{"token": "B", "logprob": -0.1, "top_logprobs": []}]}),
            ),
            HttpResponse {
                status: 200,
                body: b"not json".to_vec(),
            },
            HttpResponse {
                status: 200,
                body: vec![b' '; MAX_REPLY_BYTES + 1],
            },
        ];
        for case in cases {
            assert!(
                matches!(letter_distribution(&case, 3), Err(Error::Malformed(_))),
                "{}",
                String::from_utf8_lossy(&case.body[..case.body.len().min(120)])
            );
        }
        assert!(matches!(
            letter_distribution(
                &HttpResponse {
                    status: 404,
                    body: br#"{"error":"model 'x' not found"}"#.to_vec()
                },
                3
            ),
            Err(Error::Api { status: 404, .. })
        ));
        assert!(matches!(
            letter_distribution(&good, 1),
            Err(Error::InvalidArgument(_))
        ));
        assert!(matches!(
            letter_distribution(&good, 17),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn answers_carry_the_distribution_without_claiming_confidence() {
        let questions = tactical_questions();
        let danger = scoring_for(&questions[Q_DANGER]).unwrap();
        match answer_from(&danger, &[0.0, 0.1, 0.2, 0.6, 0.1]) {
            Answer::Score {
                score,
                confidence,
                probabilities,
                ..
            } => {
                assert!((score - 2.7).abs() < 1e-9);
                assert_eq!(confidence, None);
                assert_eq!(probabilities["3"], 0.6);
            }
            other => panic!("{other:?}"),
        }
        let stance = scoring_for(&questions["stance"]).unwrap();
        match answer_from(&stance, &[0.1, 0.1, 0.7, 0.1]) {
            Answer::Choice {
                choice, confidence, ..
            } => {
                assert_eq!(choice, stance.candidates[2].id);
                assert_eq!(confidence, None);
            }
            other => panic!("{other:?}"),
        }
        let noul = scoring_for(&Question::Noul {
            instructions: "Stuck?".into(),
            criteria: None,
        })
        .unwrap();
        assert_eq!(answer_from(&noul, &[0.8, 0.2]), Answer::Noul { noul: 0.8 });
    }

    #[test]
    fn ollama_decisions_ask_each_question_in_the_trained_shape() {
        let transport = letters(
            reply(
                "A",
                &[
                    ("A", -0.05),
                    ("B", -3.0),
                    ("C", -4.0),
                    ("D", -5.0),
                    ("E", -6.0),
                ],
            ),
            Duration::ZERO,
        );
        let questions = tactical_questions();
        let decision = decide(
            &transport,
            Provider::Ollama,
            OLLAMA_BASE_URL,
            APUS_OLLAMA_MODEL,
            &json!({"self": {"health": "high"}}),
            &questions,
            Duration::from_secs(5),
        )
        .unwrap();
        assert_eq!(decision.answers.len(), 3);
        assert_eq!(decision.provider.as_deref(), Some("ollama"));
        assert_eq!(decision.usage, None);
        let seen = transport.seen.lock().unwrap();
        assert_eq!(seen.len(), 3, "one scoring request per question");
        let body = seen[0].body.as_ref().unwrap();
        assert_eq!(seen[0].url, "http://127.0.0.1:11434/api/generate");
        assert!(seen[0].headers.iter().all(|(n, _)| n != "Authorization"));
        assert_eq!(body["raw"], true);
        assert_eq!(body["think"], false);
        assert_eq!(body["stream"], false);
        assert_eq!(body["logprobs"], true);
        assert_eq!(body["top_logprobs"], 20);
        assert_eq!(body["options"]["num_predict"], 1);
        assert_eq!(body["options"]["temperature"], 0);
        let prompt = body["prompt"].as_str().unwrap();
        assert!(prompt.starts_with("<|im_start|>user\nShared state:\n{\"self\":"));
        assert!(
            prompt.ends_with("Answer:<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
        );
        assert!(seen
            .iter()
            .all(|r| r.timeout.is_some_and(|t| t <= Duration::from_secs(5))));
        drop(seen);

        // A campaign with one carried weapon skips that question and still decides.
        let one_weapon = campaign_questions(&[WeaponType::Fists]);
        let decision = decide_ollama(
            &transport,
            OLLAMA_BASE_URL,
            APUS_OLLAMA_MODEL,
            &json!("state"),
            &one_weapon,
            Duration::from_secs(5),
        )
        .unwrap();
        assert!(!decision.answers.contains_key("weapon"));
        assert_eq!(decision.answers.len(), 2);
        let nothing = BTreeMap::from([("weapon".to_string(), one_weapon["weapon"].clone())]);
        assert!(matches!(
            decide_ollama(
                &transport,
                OLLAMA_BASE_URL,
                "m",
                &json!("s"),
                &nothing,
                Duration::from_secs(5)
            ),
            Err(Error::InvalidArgument(_))
        ));
        let huge = json!("x".repeat(MAX_PROMPT_BYTES));
        assert!(matches!(
            decide_ollama(
                &transport,
                OLLAMA_BASE_URL,
                "m",
                &huge,
                &questions,
                Duration::from_secs(5)
            ),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn a_slow_local_model_times_out_as_a_whole() {
        let slow = letters(
            reply(
                "A",
                &[
                    ("A", -0.1),
                    ("B", -2.0),
                    ("C", -3.0),
                    ("D", -4.0),
                    ("E", -5.0),
                ],
            ),
            Duration::from_millis(40),
        );
        let err = decide_ollama(
            &slow,
            OLLAMA_BASE_URL,
            "m",
            &json!("s"),
            &tactical_questions(),
            Duration::from_millis(60),
        )
        .unwrap_err();
        assert!(matches!(err, Error::Timeout(_)), "{err}");
        assert!(
            slow.seen.lock().unwrap().len() < 3,
            "no request is sent once the budget is spent"
        );
        let transport = FakeTransport::new(vec![Err(Error::Timeout("read".into()))]);
        assert!(decide_ollama(
            &transport,
            OLLAMA_BASE_URL,
            "m",
            &json!("s"),
            &tactical_questions(),
            Duration::from_secs(1),
        )
        .is_err());
        let late = letters(ok(json!({"answers": {}})), Duration::from_millis(30));
        assert!(matches!(
            decide_openjev(
                &late,
                OPENJEV_BASE_URL,
                OPENJEV_MODEL,
                &json!("s"),
                &tactical_questions(),
                Duration::from_millis(10)
            ),
            Err(Error::Timeout(_))
        ));
        assert!(matches!(
            remaining(Instant::now(), Duration::ZERO),
            Err(Error::Timeout(_))
        ));
    }

    fn openjev_answers() -> Value {
        json!({
            "id": "local-1",
            "model": "anything",
            "answers": {
                "stance": {"type": "choice", "choice": "push_enemy", "confidence": 0.7,
                    "probabilities": {"push_enemy": 0.7, "hold_angle": 0.2, "kite_distance": 0.05, "fall_back_heal": 0.05}},
                "weapon": {"type": "choice", "choice": "rail", "probabilities": {"rail": 0.9, "scatter": 0.1}},
                "danger": {"type": "score", "score": 1.2, "probabilities": {"0": 0.2, "1": 0.5, "2": 0.2, "3": 0.1}},
                "extra": {"type": "noul", "noul": 0.3}
            },
            "usage": {"input_tokens": 900, "output_tokens": 0, "cost": 7.0}
        })
    }

    #[test]
    fn openjev_speaks_systemone_without_a_key() {
        let transport = FakeTransport::ok(openjev_answers());
        let questions = tactical_questions();
        let decision = decide(
            &transport,
            Provider::OpenJev,
            OPENJEV_BASE_URL,
            OPENJEV_MODEL,
            &json!({"self": {}}),
            &questions,
            Duration::from_secs(2),
        )
        .unwrap();
        assert_eq!(decision.answers.len(), 3, "unasked answers are dropped");
        assert_eq!(decision.model, OPENJEV_MODEL);
        assert_eq!(decision.id, None);
        assert_eq!(decision.usage, None, "a local server bills nothing");
        let sent = transport.last_request.lock().unwrap().clone().unwrap();
        assert_eq!(sent.url, "http://127.0.0.1:3000/v1/systemone");
        assert!(sent.headers.iter().all(|(n, _)| n != "Authorization"));
        let body = sent.body.unwrap();
        assert_eq!(body["model"], "openjev");
        assert_eq!(body["questions"]["stance"]["type"], "choice");
        assert!(matches!(
            decide(
                &transport,
                Provider::Typesafe,
                "u",
                "m",
                &json!("s"),
                &questions,
                Duration::from_secs(1)
            ),
            Err(Error::InvalidArgument(_))
        ));
        assert!(matches!(
            decide_openjev(
                &transport,
                OPENJEV_BASE_URL,
                "m",
                &json!("s"),
                &BTreeMap::new(),
                Duration::from_secs(1)
            ),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn untrusted_systemone_answers_are_refused() {
        let questions = tactical_questions();
        let mutate = |path: &[&str], value: Value| {
            let mut body = openjev_answers();
            let mut node = &mut body;
            for key in &path[..path.len() - 1] {
                node = &mut node[*key];
            }
            node[path[path.len() - 1]] = value;
            body
        };
        let bad = vec![
            mutate(&["answers", "stance", "choice"], json!("teleport")),
            mutate(&["answers", "stance", "confidence"], json!(1.5)),
            mutate(
                &["answers", "stance", "probabilities"],
                json!({"push_enemy": 0.9, "bfg": 0.1}),
            ),
            mutate(
                &["answers", "stance", "probabilities"],
                json!({"push_enemy": 0.9, "hold_angle": 0.9}),
            ),
            mutate(
                &["answers", "stance", "probabilities"],
                json!({"push_enemy": -0.5, "hold_angle": 1.5}),
            ),
            mutate(&["answers", "danger", "score"], json!(7.0)),
            mutate(&["answers", "danger", "score"], json!(-1.0)),
            mutate(&["answers", "danger", "probabilities"], json!({"9": 1.0})),
            mutate(&["answers", "danger", "probabilities"], json!({"x": 1.0})),
            mutate(&["answers", "weapon"], json!({"type": "noul", "noul": 0.5})),
            {
                let mut body = openjev_answers();
                body["answers"].as_object_mut().unwrap().remove("weapon");
                body
            },
            json!({"nothing": true}),
        ];
        for body in bad {
            let transport = FakeTransport::ok(body.clone());
            let result = decide_openjev(
                &transport,
                OPENJEV_BASE_URL,
                OPENJEV_MODEL,
                &json!("s"),
                &questions,
                Duration::from_secs(2),
            );
            assert!(matches!(result, Err(Error::Malformed(_))), "{body}");
        }
        let noul = BTreeMap::from([(
            "stuck".to_string(),
            Question::Noul {
                instructions: "Stuck?".into(),
                criteria: None,
            },
        )]);
        let answers = |p: f64| BTreeMap::from([("stuck".to_string(), Answer::Noul { noul: p })]);
        assert!(validate_answers(&noul, answers(0.4), true).is_ok());
        assert!(matches!(
            validate_answers(&noul, answers(1.2), true),
            Err(Error::Malformed(_))
        ));
        assert!(validate_answers(&noul, BTreeMap::new(), false)
            .unwrap()
            .is_empty());
        let oversized = HttpResponse {
            status: 200,
            body: vec![b' '; MAX_REPLY_BYTES + 1],
        };
        let transport = FakeTransport::new(vec![Ok(oversized)]);
        assert!(matches!(
            decide_openjev(
                &transport,
                OPENJEV_BASE_URL,
                OPENJEV_MODEL,
                &json!("s"),
                &questions,
                Duration::from_secs(2)
            ),
            Err(Error::Malformed(_))
        ));
        let refused = FakeTransport::new(vec![Ok(HttpResponse {
            status: 503,
            body: br#"{"detail":"loading"}"#.to_vec(),
        })]);
        assert!(matches!(
            decide_openjev(
                &refused,
                OPENJEV_BASE_URL,
                OPENJEV_MODEL,
                &json!("s"),
                &questions,
                Duration::from_secs(2)
            ),
            Err(Error::Api { status: 503, .. })
        ));
    }

    #[test]
    fn warmup_names_the_pull_command_for_a_missing_model() {
        let request = ollama_warmup_request(OLLAMA_BASE_URL, APUS_OLLAMA_MODEL);
        assert_eq!(request.timeout, Some(WARMUP_TIMEOUT));
        assert!(request.body.as_ref().unwrap().get("prompt").is_none());
        let loaded = FakeTransport::ok(json!({"done": true}));
        assert!(warm_up(&loaded, OLLAMA_BASE_URL, APUS_OLLAMA_MODEL).is_ok());
        let missing = FakeTransport::new(vec![Ok(HttpResponse {
            status: 404,
            body: br#"{"error":"model not found"}"#.to_vec(),
        })]);
        let err = warm_up(&missing, OLLAMA_BASE_URL, "m").unwrap_err();
        assert!(err.to_string().contains("ollama pull m"), "{err}");
        let broken = FakeTransport::new(vec![Ok(HttpResponse {
            status: 500,
            body: br#"{"error":"out of memory"}"#.to_vec(),
        })]);
        assert!(matches!(
            warm_up(&broken, OLLAMA_BASE_URL, "m"),
            Err(Error::Api { status: 500, .. })
        ));
        let offline = FakeTransport::new(vec![Err(Error::Transport("refused".into()))]);
        assert!(warm_up(&offline, OLLAMA_BASE_URL, "m").is_err());
    }
}
