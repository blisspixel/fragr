//! Generation orchestration shared by the CLI and offline failure tests.

use std::io::Write;
use std::time::Duration;

use crate::ledger::{Event, Identity, Ledger, Stage};
use crate::{
    check_budget, estimate, file_name, image_urls, poll, submit, Error, Frame, Spec, Transport,
};

#[derive(Clone, Copy)]
pub struct Options {
    pub max_spend_usd: Option<f64>,
    pub show_prompts: bool,
}

pub fn generate(
    transport: &dyn Transport,
    credential: &str,
    spec: &Spec,
    selected: &[&Frame],
    options: Options,
    out: &mut dyn Write,
    sleep: &mut dyn FnMut(Duration),
) -> Result<(), Error> {
    check_budget(0.0, options.max_spend_usd)?;
    crate::validation::validate_model_path(&spec.model)?;
    let mut ids = std::collections::BTreeSet::new();
    for frame in selected {
        crate::validate_frame_id(&frame.id)?;
        if !ids.insert(frame.id.to_ascii_lowercase()) {
            return Err(Error::Spec(
                "selected frame IDs collide on case-insensitive filesystems".into(),
            ));
        }
    }
    let mut ledger = Ledger::open(&spec.out_dir)?;
    let mut active = Vec::new();
    // Preflight every selected receipt before pricing or resuming any request.
    for frame in selected {
        if let Some(job) = ledger.job(&frame.id) {
            if let Some(identity) = &job.identity {
                if *identity != Identity::new(&spec.model, frame) {
                    return Err(Error::Spec(format!(
                        "asset {} has a different recorded request; use a new frame ID",
                        frame.id
                    )));
                }
            }
            match &job.stage {
                Stage::Downloaded { files } => {
                    if files.iter().any(|file| !spec.out_dir.join(file).is_file()) {
                        return Err(Error::Io(format!("asset {} has missing recorded files; restore them without regenerating", frame.id)));
                    }
                    continue;
                }
                Stage::Reserved => return Err(Error::Budget(format!(
                    "asset {} has an uncertain submission; verify its request ID in the dashboard and use recover", frame.id))),
                Stage::Stopped { status } => return Err(Error::Budget(format!(
                    "asset {} ended as {status}; reconcile billing before authorizing a new frame ID", frame.id))),
                Stage::Submitted { .. } | Stage::Completed { .. } => {}
            }
        }
        active.push(*frame);
    }
    if active.is_empty() {
        writeln!(
            out,
            "nothing to do; every selected asset has recorded files"
        )
        .map_err(io_error)?;
        return Ok(());
    }
    let mut total = 0.0;
    for frame in &active {
        if ledger.job(&frame.id).is_none() {
            let usd = estimate(transport, credential, &spec.model, frame)?;
            total += usd;
            writeln!(out, "  {:<28} estimated ${usd:.4}", frame.id).map_err(io_error)?;
        }
    }
    let approved = check_budget(total, options.max_spend_usd)?;
    let mut reserved = 0.0;
    for frame in active {
        if ledger.job(&frame.id).is_none() {
            let usd = estimate(transport, credential, &spec.model, frame)?;
            let projected = reserved + usd;
            if !projected.is_finite() || projected > approved {
                return Err(Error::Budget(format!(
                    "new estimate for {} exceeds the approved batch estimate",
                    frame.id
                )));
            }
            if options.show_prompts {
                writeln!(out, "  prompt: {}", frame.prompt()).map_err(io_error)?;
            }
            ledger.record(
                &frame.id,
                Event::Reserved {
                    identity: Identity::new(&spec.model, frame),
                    estimated_usd: usd,
                },
            )?;
            reserved = projected;
            let status_url = submit(transport, credential, &spec.model, frame)?;
            ledger.record(&frame.id, Event::Submitted { status_url })?;
        }
        let status_url = match ledger.job(&frame.id).map(|job| &job.stage) {
            Some(Stage::Submitted { status_url } | Stage::Completed { status_url, .. }) => {
                status_url.clone()
            }
            _ => return Err(Error::Io("asset lost its submitted receipt".into())),
        };
        // Refresh completed URLs too: signed download links may have expired.
        let result = poll(transport, credential, &status_url, sleep, 120)?;
        let status = result
            .get("status")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("unknown");
        if status != "completed" {
            ledger.record(
                &frame.id,
                Event::Stopped {
                    status: status.to_owned(),
                },
            )?;
            return Err(Error::Transport(format!(
                "asset {} ended as {status}; no automatic generation retry",
                frame.id
            )));
        }
        let urls = image_urls(&result);
        if urls.len() > 64 {
            return Err(Error::Transport(
                "completed asset contains more than 64 image URLs".into(),
            ));
        }
        ledger.record(&frame.id, Event::Completed { urls: urls.clone() })?;
        if urls.is_empty() {
            return Err(Error::Transport(format!(
                "asset {} completed without image URLs; request receipt preserved",
                frame.id
            )));
        }
        let mut files = Vec::new();
        for (index, url) in urls.iter().enumerate() {
            let bytes = transport.download(url)?;
            if bytes.is_empty() {
                return Err(Error::Transport(
                    "image download was empty; request receipt preserved".into(),
                ));
            }
            let name = file_name(&frame.id, index, url);
            crate::validation::validate_file_name(&name)?;
            let temporary = spec.out_dir.join(format!("{name}.part"));
            let mut file = std::fs::File::create(&temporary).map_err(io_error)?;
            file.write_all(&bytes).map_err(io_error)?;
            file.sync_all().map_err(io_error)?;
            drop(file);
            std::fs::rename(temporary, spec.out_dir.join(&name)).map_err(io_error)?;
            files.push(name);
        }
        ledger.record(
            &frame.id,
            Event::Downloaded {
                files: files.clone(),
            },
        )?;
        writeln!(out, "  {:<28} downloaded {}", frame.id, files.join(" ")).map_err(io_error)?;
    }
    writeln!(
        out,
        "new requests reserved an estimated ${reserved:.4}; this is not a billing receipt"
    )
    .map_err(io_error)
}

fn io_error(error: std::io::Error) -> Error {
    Error::Io(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestDir;
    use crate::{Method, Request, Response};
    use serde_json::json;
    use std::cell::RefCell;
    use std::collections::VecDeque;
    use std::path::PathBuf;

    const STATUS: &str = "https://api.higgsfield.ai/requests/r1/status";
    const IMAGE: &str = "https://cdn.example/tack.png";

    struct Fake {
        replies: RefCell<VecDeque<Result<Response, Error>>>,
        downloads: RefCell<VecDeque<Result<Vec<u8>, Error>>>,
        calls: RefCell<Vec<Request>>,
        media: RefCell<Vec<String>>,
        ledger_path: PathBuf,
    }

    impl Fake {
        fn new(
            dir: &TestDir,
            replies: Vec<Result<Response, Error>>,
            downloads: Vec<Result<Vec<u8>, Error>>,
        ) -> Self {
            Self {
                replies: RefCell::new(replies.into()),
                downloads: RefCell::new(downloads.into()),
                calls: RefCell::new(vec![]),
                media: RefCell::new(vec![]),
                ledger_path: dir.0.join("ledger.jsonl"),
            }
        }
        fn assert_only_resume(&self) {
            assert!(self
                .calls
                .borrow()
                .iter()
                .all(|r| r.method == Method::Get && r.url == STATUS));
        }
    }

    impl Transport for Fake {
        fn send(&self, _: &str, request: &Request) -> Result<Response, Error> {
            if request.method == Method::Post && !request.url.contains("/estimate/") {
                // The durable reservation must exist before the paid boundary.
                assert!(std::fs::metadata(&self.ledger_path).unwrap().len() > 0);
                assert!(Ledger::open(self.ledger_path.parent().unwrap()).is_err());
            }
            self.calls.borrow_mut().push(request.clone());
            self.replies
                .borrow_mut()
                .pop_front()
                .expect("unexpected API call")
        }
        fn download(&self, url: &str) -> Result<Vec<u8>, Error> {
            assert!(Ledger::open(self.ledger_path.parent().unwrap()).is_err());
            self.media.borrow_mut().push(url.to_owned());
            self.downloads
                .borrow_mut()
                .pop_front()
                .expect("unexpected download")
        }
    }

    fn reply(body: serde_json::Value) -> Result<Response, Error> {
        Ok(Response {
            status: 200,
            body: body.to_string(),
        })
    }
    fn completed() -> Result<Response, Error> {
        reply(json!({"status":"completed","images":[{"url": IMAGE}]}))
    }
    fn first_run(result: Result<Response, Error>) -> Vec<Result<Response, Error>> {
        vec![
            reply(json!({"usd":"0.02"})),
            reply(json!({"usd":"0.02"})),
            reply(json!({"status_url":STATUS})),
            result,
        ]
    }
    fn spec(dir: &TestDir) -> Spec {
        let mut spec = crate::parse_spec(r#"{"model":"model/image","out_dir":"unused","frames":[{"id":"tack","subject":"pistol"}]}"#).unwrap();
        spec.out_dir.clone_from(&dir.0);
        spec
    }
    fn run(fake: &Fake, spec: &Spec) -> Result<String, Error> {
        let mut output = Vec::new();
        generate(
            fake,
            "test",
            spec,
            &spec.frames.iter().collect::<Vec<_>>(),
            Options {
                max_spend_usd: Some(0.05),
                show_prompts: true,
            },
            &mut output,
            &mut |_| {},
        )?;
        Ok(String::from_utf8(output).unwrap())
    }
    fn stage(dir: &TestDir) -> Stage {
        Ledger::open(&dir.0)
            .unwrap()
            .job("tack")
            .unwrap()
            .stage
            .clone()
    }

    #[test]
    fn interruption_after_post_requires_reconciliation_and_never_reposts() {
        let dir = TestDir::new();
        let spec = spec(&dir);
        let fake = Fake::new(
            &dir,
            vec![
                reply(json!({"usd":0.02})),
                reply(json!({"usd":0.02})),
                Err(Error::Transport("connection lost after POST".into())),
            ],
            vec![],
        );
        assert!(run(&fake, &spec).is_err());
        assert_eq!(stage(&dir), Stage::Reserved);
        let untouched = Fake::new(&dir, vec![], vec![]);
        assert!(run(&untouched, &spec)
            .unwrap_err()
            .to_string()
            .contains("uncertain"));
        assert!(untouched.calls.borrow().is_empty());
        Ledger::open(&dir.0).unwrap().recover("tack", "r1").unwrap();
        let resume = Fake::new(&dir, vec![completed()], vec![Ok(vec![1, 2, 3])]);
        let output = run(&resume, &spec).unwrap();
        resume.assert_only_resume();
        assert!(output.contains("estimated $0.0000"));
        assert_eq!(
            std::fs::read(dir.0.join("tack_0.png")).unwrap(),
            vec![1, 2, 3]
        );
        assert!(run(&untouched, &spec).unwrap().contains("nothing to do"));
    }

    #[test]
    fn poll_and_download_failures_resume_the_same_paid_request() {
        for failure in ["poll", "download", "empty", "no_urls", "write"] {
            let dir = TestDir::new();
            let spec = spec(&dir);
            let result = match failure {
                "poll" => Err(Error::Transport("offline".into())),
                "no_urls" => reply(json!({"status":"completed"})),
                _ => completed(),
            };
            let downloads = match failure {
                "download" => vec![Err(Error::Transport("CDN unavailable".into()))],
                "empty" => vec![Ok(vec![])],
                "write" => {
                    std::fs::create_dir(dir.0.join("tack_0.png.part")).unwrap();
                    vec![Ok(vec![8])]
                }
                _ => vec![],
            };
            assert!(
                run(&Fake::new(&dir, first_run(result), downloads), &spec).is_err(),
                "{failure}"
            );
            assert!(matches!(
                stage(&dir),
                Stage::Submitted { .. } | Stage::Completed { .. }
            ));
            if failure == "write" {
                std::fs::remove_dir(dir.0.join("tack_0.png.part")).unwrap();
            }
            let resume = Fake::new(&dir, vec![completed()], vec![Ok(vec![7])]);
            run(&resume, &spec).unwrap();
            resume.assert_only_resume();
            assert_eq!(resume.media.borrow().as_slice(), [IMAGE]);
            assert_eq!(std::fs::read(dir.0.join("tack_0.png")).unwrap(), vec![7]);
        }
    }

    #[test]
    fn interrupted_multi_image_download_can_replace_its_partial_files() {
        let dir = TestDir::new();
        let spec = spec(&dir);
        let result = || {
            reply(
                json!({"status":"completed","images":[{"url":IMAGE},{"url":"https://cdn.example/b.png"}]}),
            )
        };
        let first = Fake::new(
            &dir,
            first_run(result()),
            vec![Ok(vec![1]), Err(Error::Transport("interrupted".into()))],
        );
        assert!(run(&first, &spec).is_err());
        let resume = Fake::new(&dir, vec![result()], vec![Ok(vec![2]), Ok(vec![3])]);
        run(&resume, &spec).unwrap();
        resume.assert_only_resume();
        assert_eq!(std::fs::read(dir.0.join("tack_0.png")).unwrap(), vec![2]);
        assert_eq!(std::fs::read(dir.0.join("tack_1.png")).unwrap(), vec![3]);
    }

    #[test]
    fn terminal_failures_stop_the_batch_without_assuming_a_refund() {
        for status in ["failed", "nsfw", "canceled"] {
            let dir = TestDir::new();
            let spec = spec(&dir);
            let first = Fake::new(&dir, first_run(reply(json!({"status":status}))), vec![]);
            assert!(run(&first, &spec).is_err());
            assert_eq!(
                stage(&dir),
                Stage::Stopped {
                    status: status.into()
                }
            );
            let retry = Fake::new(&dir, vec![], vec![]);
            assert!(run(&retry, &spec)
                .unwrap_err()
                .to_string()
                .contains("reconcile billing"));
            assert!(retry.calls.borrow().is_empty());
        }
    }

    #[test]
    fn changed_request_or_missing_finished_output_never_generates_again() {
        let dir = TestDir::new();
        let mut spec = spec(&dir);
        run(
            &Fake::new(&dir, first_run(completed()), vec![Ok(vec![1])]),
            &spec,
        )
        .unwrap();
        let untouched = Fake::new(&dir, vec![], vec![]);
        let original = spec.frames[0].subject.clone();
        spec.frames[0].subject = "another pistol".into();
        assert!(run(&untouched, &spec)
            .unwrap_err()
            .to_string()
            .contains("different recorded request"));
        spec.frames[0].subject = original;
        std::fs::remove_file(dir.0.join("tack_0.png")).unwrap();
        assert!(run(&untouched, &spec)
            .unwrap_err()
            .to_string()
            .contains("missing recorded files"));
        assert!(untouched.calls.borrow().is_empty());
    }

    #[test]
    fn legacy_completed_rows_skip_only_when_the_recorded_files_exist() {
        let dir = TestDir::new();
        let spec = spec(&dir);
        std::fs::write(
            dir.0.join("ledger.jsonl"),
            "{\"id\":\"tack\",\"usd\":0.02,\"files\":[\"tack_0.png\"]}\n",
        )
        .unwrap();
        let untouched = Fake::new(&dir, vec![], vec![]);
        assert!(run(&untouched, &spec).is_err());
        std::fs::write(dir.0.join("tack_0.png"), [1]).unwrap();
        assert!(run(&untouched, &spec).unwrap().contains("nothing to do"));
        assert!(untouched.calls.borrow().is_empty());
    }

    #[test]
    fn cap_and_price_changes_are_checked_before_paid_requests() {
        let dir = TestDir::new();
        let spec = spec(&dir);
        let untouched = Fake::new(&dir, vec![], vec![]);
        for cap in [None, Some(0.0), Some(-1.0), Some(5.01), Some(f64::NAN)] {
            assert!(generate(
                &untouched,
                "test",
                &spec,
                &[&spec.frames[0]],
                Options {
                    max_spend_usd: cap,
                    show_prompts: false
                },
                &mut Vec::new(),
                &mut |_| {}
            )
            .is_err());
        }
        assert!(!dir.0.join("ledger.jsonl").exists());
        for prices in [vec![0.06], vec![0.02, 0.03]] {
            let fake = Fake::new(
                &dir,
                prices
                    .into_iter()
                    .map(|usd| reply(json!({"usd":usd})))
                    .collect(),
                vec![],
            );
            assert!(matches!(run(&fake, &spec), Err(Error::Budget(_))));
            assert!(fake
                .calls
                .borrow()
                .iter()
                .all(|r| r.url.contains("/estimate/")));
            assert!(Ledger::open(&dir.0).unwrap().job("tack").is_none());
        }
    }

    #[test]
    fn foreign_status_url_preserves_uncertain_receipt_without_following_it() {
        let dir = TestDir::new();
        let spec = spec(&dir);
        let fake = Fake::new(
            &dir,
            vec![
                reply(json!({"usd":0.02})),
                reply(json!({"usd":0.02})),
                reply(json!({"status_url":"https://evil.example/requests/r1/status"})),
            ],
            vec![],
        );
        assert!(run(&fake, &spec).is_err());
        assert_eq!(stage(&dir), Stage::Reserved);
        assert!(fake
            .calls
            .borrow()
            .iter()
            .all(|r| r.url.starts_with(crate::API_BASE)));
        assert_eq!(fake.calls.borrow().len(), 3);
    }

    #[test]
    fn price_increase_after_one_submission_cannot_consume_unapproved_budget() {
        let dir = TestDir::new();
        let mut spec = spec(&dir);
        let mut other = spec.frames[0].clone();
        other.id = "rail".into();
        spec.frames.push(other);
        let fake = Fake::new(
            &dir,
            vec![
                reply(json!({"usd":0.02})),
                reply(json!({"usd":0.02})),
                reply(json!({"usd":0.02})),
                reply(json!({"status_url":STATUS})),
                completed(),
                reply(json!({"usd":0.03})),
            ],
            vec![Ok(vec![1])],
        );
        assert!(matches!(run(&fake, &spec), Err(Error::Budget(_))));
        assert_eq!(
            fake.calls
                .borrow()
                .iter()
                .filter(|r| r.method == Method::Post && !r.url.contains("/estimate/"))
                .count(),
            1
        );
        let ledger = Ledger::open(&dir.0).unwrap();
        assert!(matches!(
            ledger.job("tack").unwrap().stage,
            Stage::Downloaded { .. }
        ));
        assert!(ledger.job("rail").is_none());
    }

    #[test]
    fn preflight_rejects_duplicate_names_and_escaping_models_before_network() {
        let dir = TestDir::new();
        let mut spec = spec(&dir);
        let untouched = Fake::new(&dir, vec![], vec![]);
        spec.model = "../paid-model".into();
        assert!(run(&untouched, &spec).is_err());
        spec.model = "model/image".into();
        let mut other = spec.frames[0].clone();
        other.id = "TACK".into();
        spec.frames.push(other);
        assert!(run(&untouched, &spec).is_err());
        assert!(!dir.0.join("ledger.jsonl").exists());
        assert!(untouched.calls.borrow().is_empty());
        assert!(crate::parse_spec(r#"{"model":"m","out_dir":"o","frames":[{"id":"a","subject":"x"},{"id":"A","subject":"y"}]}"#).is_err());
    }

    #[test]
    fn failed_output_before_submission_does_not_spend() {
        struct Broken;
        impl Write for Broken {
            fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
                Err(std::io::Error::other("closed output"))
            }
            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }
        let dir = TestDir::new();
        let spec = spec(&dir);
        let fake = Fake::new(&dir, vec![reply(json!({"usd":0.02}))], vec![]);
        assert!(generate(
            &fake,
            "test",
            &spec,
            &[&spec.frames[0]],
            Options {
                max_spend_usd: Some(0.05),
                show_prompts: false
            },
            &mut Broken,
            &mut |_| {}
        )
        .is_err());
        assert!(Ledger::open(&dir.0).unwrap().job("tack").is_none());
        assert_eq!(fake.calls.borrow().len(), 1);
    }
}
