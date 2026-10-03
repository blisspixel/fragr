use std::cell::RefCell;
use std::collections::VecDeque;

use super::*;
use crate::test_support::TestDir;
use crate::Response;

struct Fake {
    replies: RefCell<VecDeque<Result<Response, Error>>>,
    sent: RefCell<Vec<Request>>,
    downloads: RefCell<Vec<String>>,
    bytes: Vec<u8>,
    ledger: Option<PathBuf>,
}

impl Fake {
    fn new(values: Vec<Value>) -> Self {
        Self {
            replies: RefCell::new(
                values
                    .into_iter()
                    .map(|v| {
                        Ok(Response {
                            status: 200,
                            body: v.to_string(),
                        })
                    })
                    .collect(),
            ),
            sent: RefCell::new(Vec::new()),
            downloads: RefCell::new(Vec::new()),
            bytes: glb(json!({"asset":{"version":"2.0"}})),
            ledger: None,
        }
    }
    fn posts(&self) -> usize {
        self.sent
            .borrow()
            .iter()
            .filter(|r| r.method == Method::Post)
            .count()
    }
}

impl Transport for Fake {
    fn send(&self, _: &str, request: &Request) -> Result<Response, Error> {
        if request.method == Method::Post {
            if let Some(path) = &self.ledger {
                assert!(
                    std::fs::metadata(path.join("ledger.jsonl")).unwrap().len() > 0,
                    "POST preceded durable reserve"
                );
                assert!(
                    Ledger::open(path).is_err(),
                    "POST must retain the account ledger lock"
                );
            }
        }
        self.sent.borrow_mut().push(request.clone());
        self.replies
            .borrow_mut()
            .pop_front()
            .expect("unexpected request")
    }
    fn download(&self, url: &str) -> Result<Vec<u8>, Error> {
        self.downloads.borrow_mut().push(url.into());
        Ok(self.bytes.clone())
    }
}

fn glb(value: Value) -> Vec<u8> {
    let mut text = value.to_string().into_bytes();
    while !text.len().is_multiple_of(4) {
        text.push(b' ');
    }
    let mut bytes = b"glTF".to_vec();
    bytes.extend(2_u32.to_le_bytes());
    bytes.extend((20_u32 + text.len() as u32).to_le_bytes());
    bytes.extend((text.len() as u32).to_le_bytes());
    bytes.extend(b"JSON");
    bytes.extend(text);
    bytes
}

fn spec(dir: &TestDir, ids: &[&str]) -> Spec {
    Spec {
        out_dir: dir.0.clone(),
        jobs: ids
            .iter()
            .map(|id| JobSpec {
                id: (*id).into(),
                stage: JobStage::Image {
                    image_url: "https://example.com/reference.png".into(),
                    geometry_resolution: "2k".into(),
                    texture_resolution: "4k".into(),
                    target_polycount: 12000,
                    pose_mode: "a-pose".into(),
                },
            })
            .collect(),
    }
}

fn completed(id: &str) -> Value {
    json!({"id": id,"status":"SUCCEEDED","consumed_credits":35,"model_urls":{"glb":"https://assets.meshy.ai/task/model.glb?Expires=123"}})
}
fn run(fake: &Fake, spec: &Spec, credits: u64, cap: Option<f64>) -> Result<(), Error> {
    generate(
        fake,
        "private-key",
        spec,
        credits,
        cap,
        &mut Vec::new(),
        &mut |_| {},
    )
}

#[test]
fn balance_is_free_strict_and_does_not_echo_errors() {
    let fake = Fake::new(vec![json!({"balance":3100})]);
    let result = check(&fake, "private-key", 150, None).unwrap();
    assert!(result.sufficient);
    assert_eq!(result.available_api_credits, 3100);
    assert_eq!(fake.posts(), 0);
    for value in [
        json!({"balance":-1}),
        json!({"balance":"100"}),
        json!({"balance":1.5}),
        json!({}),
        json!({"balance":null}),
    ] {
        assert!(balance(&Fake::new(vec![value]), "private-key").is_err());
    }
    assert_eq!(
        balance(&Fake::new(vec![json!({"balance":0})]), "key").unwrap(),
        0
    );
    assert!(
        !check(&Fake::new(vec![json!({"balance":0})]), "key", 1, None)
            .unwrap()
            .sufficient
    );
    for response in [
        Ok(Response {
            status: 401,
            body: "private-key".into(),
        }),
        Err(Error::Transport("private-key".into())),
        Ok(Response {
            status: 200,
            body: "private-key".into(),
        }),
        Ok(Response {
            status: 200,
            body: "x".repeat(4 * 1024 * 1024 + 1),
        }),
    ] {
        let fake = Fake::new(vec![]);
        fake.replies.borrow_mut().push_back(response);
        assert!(!balance(&fake, "private-key")
            .unwrap_err()
            .to_string()
            .contains("private-key"));
    }
}

#[test]
fn credentials_are_alias_aware_bounded_and_never_echoed() {
    let dir = TestDir::new();
    let path = dir.0.join(".env");
    for text in [
        "# hi\nmeshy=abc",
        "export MESHY_API_KEY='abc'\n",
        "meshy=abc\nMESHY_API_KEY=abc",
    ] {
        std::fs::write(&path, text).unwrap();
        assert_eq!(read_credential(&path).unwrap(), "abc");
    }
    for text in [
        "meshy=abc\nMESHY_API_KEY=private-key",
        "meshy=",
        "meshy='private-key with space'",
        "meshy=\t",
    ] {
        std::fs::write(&path, text).unwrap();
        let error = read_credential(&path).unwrap_err();
        assert!(!error.to_string().contains("private-key"));
    }
    std::fs::write(&path, "meshy=".to_owned() + &"x".repeat(513)).unwrap();
    assert!(read_credential(&path).is_err());
    std::fs::write(&path, "x".repeat(65537)).unwrap();
    assert!(read_credential(&path).is_err());
    assert!(read_credential(&dir.0.join("missing")).is_err());
}

#[test]
fn origins_and_recovery_ids_are_bound_to_the_stage() {
    assert_eq!(
        status_request_id(
            "meshy/rigging",
            &status_url("meshy/rigging", "task-1").unwrap()
        )
        .unwrap(),
        "task-1"
    );
    for url in [
        "http://api.meshy.ai/openapi/v1/balance",
        "https://api.meshy.ai.evil/openapi/v1/balance",
        "https://api.meshy.ai:444/openapi/v1/balance",
        "https://a@api.meshy.ai/openapi/v1/balance",
        "https://api.meshy.ai/openapi/v1/balance?key=x",
        "https://api.meshy.ai/not-api",
        "https://api.meshy.ai/openapi/v1/balance#x",
    ] {
        assert!(validate_api_url(url).is_err());
    }
    assert!(status_url("other", "task").is_err());
    assert!(status_url("meshy/rigging", "../task").is_err());
    assert!(status_request_id(
        "meshy/rigging",
        "https://api.meshy.ai/openapi/v1/image-to-3d/task"
    )
    .is_err());
    assert!(status_request_id(
        "meshy/rigging",
        "https://api.meshy.ai/openapi/v1/rigging/task/other"
    )
    .is_err());
}

#[test]
fn exact_pricing_and_unknown_parameters_are_validated_locally() {
    let dir = TestDir::new();
    let valid = json!({"out_dir":dir.0,"jobs":[{"id":"model","kind":"image","image_url":"https://example.com/image.png","geometry_resolution":"2k","texture_resolution":"4k","target_polycount":12000,"pose_mode":"a-pose"}]});
    let parsed = parse_spec(&valid.to_string()).unwrap();
    assert_eq!(parsed.jobs[0].priced().unwrap().1, 35);
    let mut base = valid.clone();
    base["jobs"][0]["geometry_resolution"] = json!("standard");
    assert_eq!(
        parse_spec(&base.to_string()).unwrap().jobs[0]
            .priced()
            .unwrap()
            .1,
        30
    );
    for (field, value) in [
        ("target_polycount", json!(99)),
        ("pose_mode", json!("standing")),
        ("texture_resolution", json!("8k")),
        ("geometry_resolution", json!("latest")),
        ("image_url", json!("http://example.com/x")),
        ("unknown", json!(true)),
        ("id", json!("../file")),
    ] {
        let mut bad = valid.clone();
        bad["jobs"][0][field] = value;
        assert!(parse_spec(&bad.to_string()).is_err(), "{field}");
    }
    for bad in [
        "{}".into(),
        "private-key".into(),
        "x".repeat(256 * 1024 + 1),
        json!({"out_dir":"","jobs":[]}).to_string(),
    ] {
        assert!(parse_spec(&bad).is_err());
    }
    let mut duplicate = valid.clone();
    duplicate["jobs"]
        .as_array_mut()
        .unwrap()
        .push(valid["jobs"][0].clone());
    assert!(parse_spec(&duplicate.to_string()).is_err());
    let rig = json!({"out_dir":dir.0,"jobs":[{"id":"rig","kind":"rig","input_task_id":"task","height_meters":1.8}]});
    assert_eq!(
        parse_spec(&rig.to_string()).unwrap().jobs[0]
            .priced()
            .unwrap()
            .1,
        5
    );
    let mut bad = rig;
    bad["jobs"][0]["height_meters"] = json!(0.1);
    assert!(parse_spec(&bad.to_string()).is_err());
}

#[test]
fn caps_and_whole_batch_balance_precede_any_post() {
    let dir = TestDir::new();
    let spec = spec(&dir, &["a", "b"]);
    for (credits, cap) in [
        (0, Some(5.0)),
        (251, Some(5.0)),
        (150, None),
        (150, Some(6.0)),
        (35, Some(5.0)),
        (150, Some(1.0)),
    ] {
        let fake = Fake::new(vec![]);
        assert!(run(&fake, &spec, credits, cap).is_err());
        assert_eq!(fake.posts(), 0);
    }
    let fake = Fake::new(vec![json!({"balance":69})]);
    assert!(run(&fake, &spec, 150, Some(3.0)).is_err());
    assert_eq!(fake.posts(), 0);
    let fake = Fake::new(vec![json!({"balance":100}), json!({"balance":34})]);
    assert!(run(&fake, &spec, 150, Some(3.0)).is_err());
    assert_eq!(fake.posts(), 0);
}

#[test]
fn each_paid_stage_rechecks_balance_and_completed_models_resume_free() {
    let dir = TestDir::new();
    let spec = spec(&dir, &["a", "b"]);
    let mut fake = Fake::new(vec![
        json!({"balance":100}),
        json!({"balance":100}),
        json!({"result":"task-a"}),
        json!({"id":"task-a","status":"IN_PROGRESS"}),
        completed("task-a"),
        json!({"balance":34}),
    ]);
    fake.ledger = Some(dir.0.clone());
    assert!(run(&fake, &spec, 150, Some(3.0)).is_err());
    assert_eq!(fake.posts(), 1);
    assert!(dir.0.join("a-0.glb").is_file());
    let next = Fake::new(vec![
        json!({"balance":35}),
        json!({"balance":35}),
        json!({"result":"task-b"}),
        completed("task-b"),
    ]);
    run(&next, &spec, 35, Some(0.7)).unwrap();
    assert_eq!(next.posts(), 1);
    run(&Fake::new(vec![]), &spec, 1, Some(0.01)).unwrap();
    std::fs::remove_file(dir.0.join("a-0.glb")).unwrap();
    assert!(run(&Fake::new(vec![]), &spec, 35, Some(1.0)).is_err());
}

#[test]
fn uncertain_submission_is_held_and_never_retried_automatically() {
    let dir = TestDir::new();
    let spec = super::tests::spec(&dir, &["a"]);
    let fake = Fake::new(vec![
        json!({"balance":100}),
        json!({"balance":100}),
        json!({"unexpected":true}),
    ]);
    assert!(run(&fake, &spec, 35, Some(1.0)).is_err());
    assert_eq!(fake.posts(), 1);
    assert_eq!(pending_credits(&Ledger::open(&dir.0).unwrap()).unwrap(), 35);
    assert!(run(&Fake::new(vec![]), &spec, 35, Some(1.0)).is_err());
    let mut ledger = Ledger::open(&dir.0).unwrap();
    ledger.recover("a", "task-a").unwrap();
    drop(ledger);
    let resumed = Fake::new(vec![completed("task-a")]);
    run(&resumed, &spec, 1, Some(0.01)).unwrap();
    assert_eq!(resumed.posts(), 0);
}

#[test]
fn pending_holds_reduce_usable_balance_and_bad_reservations_refuse() {
    let dir = TestDir::new();
    let mut ledger = Ledger::open(&dir.0).unwrap();
    let (identity, credits) = spec(&dir, &["held"]).jobs[0].priced().unwrap();
    ledger
        .record(
            "held",
            Event::Reserved {
                identity,
                estimated_usd: credits as f64 * USD_PER_CREDIT,
            },
        )
        .unwrap();
    let checked = check(
        &Fake::new(vec![json!({"balance":40})]),
        "key",
        6,
        Some(&ledger),
    )
    .unwrap();
    assert!(!checked.sufficient);
    assert_eq!(checked.pending_local_credits, 35);
    assert!(
        !check(
            &Fake::new(vec![json!({"balance":u64::MAX})]),
            "key",
            u64::MAX,
            Some(&ledger)
        )
        .unwrap()
        .sufficient
    );
    let identity = Identity {
        model: "meshy/rigging".into(),
        request: json!({"credits":5}),
    };
    ledger
        .record(
            "bad",
            Event::Reserved {
                identity,
                estimated_usd: 1.0,
            },
        )
        .unwrap();
    assert!(pending_credits(&ledger).is_err());
}

#[test]
fn task_status_failure_mismatch_and_timeout_preserve_reservations() {
    for status in [
        "FAILED", "EXPIRED", "CANCELED", "UNKNOWN", "MISMATCH", "TIMEOUT",
    ] {
        let dir = TestDir::new();
        let spec = super::tests::spec(&dir, &["a"]);
        let mut values = vec![
            json!({"balance":100}),
            json!({"balance":100}),
            json!({"result":"task-a"}),
        ];
        if status == "TIMEOUT" {
            values.extend((0..240).map(|_| json!({"id":"task-a","status":"PENDING"})));
        } else {
            values.push(
                json!({"id":if status=="MISMATCH" {"other"} else {"task-a"},"status":status}),
            );
        }
        let fake = Fake::new(values);
        assert!(run(&fake, &spec, 35, Some(1.0)).is_err());
        assert_eq!(fake.posts(), 1);
        assert_eq!(pending_credits(&Ledger::open(&dir.0).unwrap()).unwrap(), 35);
    }
}

#[test]
fn changed_identity_and_invalid_download_are_never_paid_again() {
    let dir = TestDir::new();
    let mut spec = spec(&dir, &["a"]);
    let mut fake = Fake::new(vec![
        json!({"balance":100}),
        json!({"balance":100}),
        json!({"result":"task-a"}),
        completed("task-a"),
    ]);
    fake.bytes = b"bad".to_vec();
    assert!(run(&fake, &spec, 35, Some(1.0)).is_err());
    assert_eq!(pending_credits(&Ledger::open(&dir.0).unwrap()).unwrap(), 0);
    let resumed = Fake::new(vec![]);
    run(&resumed, &spec, 1, Some(0.01)).unwrap();
    assert_eq!(resumed.posts(), 0);
    spec.jobs[0].stage = JobStage::Rig {
        input_task_id: "task-a".into(),
        height_meters: 1.8,
    };
    assert!(run(&Fake::new(vec![]), &spec, 5, Some(1.0)).is_err());
}

#[test]
fn rig_downloads_only_documented_outputs_and_rejects_foreign_urls() {
    let dir = TestDir::new();
    let spec = Spec {
        out_dir: dir.0.clone(),
        jobs: vec![JobSpec {
            id: "rig".into(),
            stage: JobStage::Rig {
                input_task_id: "task-a".into(),
                height_meters: 1.8,
            },
        }],
    };
    let fake = Fake::new(vec![
        json!({"balance":5}),
        json!({"balance":5}),
        json!({"result":"rig-a"}),
        json!({"id":"rig-a","status":"SUCCEEDED","result":{
        "rigged_character_glb_url":"https://assets.meshy.ai/rig.glb", "basic_animations":{"walking_glb_url":"https://assets.meshy.ai/walk.glb","running_glb_url":"https://assets.meshy.ai/run.glb"}}}),
    ]);
    run(&fake, &spec, 5, Some(0.1)).unwrap();
    assert_eq!(fake.downloads.borrow().len(), 3);
    assert!(output_urls("meshy/image-to-3d", &json!({})).is_err());
    assert!(output_urls(
        "meshy/image-to-3d",
        &json!({"model_urls":{"glb":"https://evil/model.glb"}})
    )
    .is_err());
    for value in [
        glb(json!({"asset":{"version":"1.0"}})),
        glb(json!({"asset":{"version":"2.0"},"buffers":[{"uri":"https://evil/x"}]})),
        glb(json!({"asset":{"version":"2.0"},"images":{}})),
        b"bad".to_vec(),
    ] {
        assert!(validate_glb(&value).is_err());
    }
}

#[test]
fn consumption_receipts_survive_reopen_and_price_drift_stops_next_stage() {
    let dir = TestDir::new();
    let spec = spec(&dir, &["a", "b"]);
    let mut result = completed("task-a");
    result["consumed_credits"] = json!(40);
    let fake = Fake::new(vec![
        json!({"balance":100}),
        json!({"balance":100}),
        json!({"result":"task-a"}),
        result,
    ]);
    assert!(matches!(
        run(&fake, &spec, 150, Some(3.0)),
        Err(Error::Budget(_))
    ));
    assert_eq!(fake.posts(), 1);
    assert!(dir.0.join("a-0.glb").is_file());
    let mut ledger = Ledger::open(&dir.0).unwrap();
    assert_eq!(ledger.job("a").unwrap().consumed_credits, Some(40));
    assert!(matches!(pending_credits(&ledger), Err(Error::Budget(_))));
    assert!(ledger
        .record(
            "a",
            Event::Usage {
                consumed_credits: 40
            }
        )
        .is_err());
    drop(ledger);
    let dir = TestDir::new();
    let spec = super::tests::spec(&dir, &["a"]);
    let mut result = completed("task-a");
    result["consumed_credits"] = json!(-1);
    let fake = Fake::new(vec![
        json!({"balance":100}),
        json!({"balance":100}),
        json!({"result":"task-a"}),
        result,
    ]);
    assert!(run(&fake, &spec, 35, Some(1.0)).is_err());
    assert_eq!(fake.posts(), 1);
}
