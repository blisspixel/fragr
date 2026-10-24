//! The live tick loop writes one trace record per served tick, numbered like
//! the Snapshot a client receives, and refuses an unwritable path at start.

use crate::tick_trace::{TickSample, TickTraceRecord, TICK_TRACE_VERSION};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::time::Duration;
use tokio_tungstenite::{connect_async, tungstenite::Message};

fn trace_path(label: &str) -> std::path::PathBuf {
    std::env::temp_dir().join(format!("fragr-{label}-{}.ndjson", uuid::Uuid::new_v4()))
}

#[tokio::test]
async fn live_trace_ticks_join_the_snapshots_a_spectator_receives() {
    let path = trace_path("tick-trace");
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(crate::run::run_server(
        crate::run::ServerOptions {
            bind: "127.0.0.1:0".into(),
            bots: 2,
            status_every_s: 0,
            tick_trace: Some(path.clone()),
            ..Default::default()
        },
        async {
            let _ = stop_rx.await;
        },
        Some(ready_tx),
    ));
    let address = tokio::time::timeout(Duration::from_secs(30), ready_rx)
        .await
        .unwrap()
        .unwrap();
    let (mut socket, _) = connect_async(format!("ws://{address}")).await.unwrap();
    socket
        .send(Message::Text(
            json!({
                "type": "hello", "role": "spectator", "name": "TraceProbe",
                "gameplay_version": crate::protocol::GAMEPLAY_VERSION,
                "geometry_version": crate::protocol::GEOMETRY_VERSION
            })
            .to_string(),
        ))
        .await
        .unwrap();
    let mut received: Vec<u64> = Vec::new();
    tokio::time::timeout(Duration::from_secs(20), async {
        while received.len() < 12 {
            let Message::Text(text) = socket.next().await.unwrap().unwrap() else {
                continue;
            };
            let value: serde_json::Value = serde_json::from_str(&text).unwrap();
            if value["type"] == "snapshot" {
                received.push(value["tick"].as_u64().unwrap());
            }
        }
    })
    .await
    .expect("a dozen snapshots");
    let _ = socket.close(None).await;
    stop_tx.send(()).unwrap();
    server.await.unwrap().unwrap();

    let text = std::fs::read_to_string(&path).unwrap();
    let _ = std::fs::remove_file(&path);
    let records: Vec<TickTraceRecord> = text
        .lines()
        .map(|line| serde_json::from_str(line).expect("every line is one strict record"))
        .collect();
    assert!(matches!(
        records.first(),
        Some(TickTraceRecord::Header { version, tick_us: 50_000, .. }) if *version == TICK_TRACE_VERSION
    ));
    let ticks: Vec<TickSample> = records
        .iter()
        .filter_map(|record| match record {
            TickTraceRecord::Tick(sample) => Some(*sample),
            _ => None,
        })
        .collect();
    let Some(TickTraceRecord::Complete {
        ticks: counted,
        dropped,
        ..
    }) = records.last()
    else {
        panic!("a clean shutdown writes the footer: {:?}", records.last());
    };
    assert_eq!(*dropped, 0);
    assert_eq!(*counted, ticks.len() as u64);
    assert!(ticks.windows(2).all(|pair| pair[1].tick > pair[0].tick));
    for tick in &received {
        let sample = ticks
            .iter()
            .find(|sample| sample.tick == *tick)
            .unwrap_or_else(|| panic!("received snapshot tick {tick} has no trace record"));
        assert!(sample.clients >= 1, "the spectator was connected at {tick}");
        assert!(sample.messages >= 1 && sample.bytes > 0);
        assert!(
            sample.total_us >= sample.sim_us + sample.measure_us + sample.fanout_us,
            "phases are disjoint parts of the handler: {sample:?}"
        );
        assert!(sample.unix_us > 0);
    }
}

#[tokio::test]
async fn an_unwritable_trace_path_fails_the_start_before_ready() {
    let path = std::env::temp_dir()
        .join(format!("fragr-missing-{}", uuid::Uuid::new_v4()))
        .join("trace.ndjson");
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let result = tokio::time::timeout(
        Duration::from_secs(30),
        crate::run::run_server(
            crate::run::ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                status_every_s: 0,
                tick_trace: Some(path.clone()),
                ..Default::default()
            },
            std::future::pending::<()>(),
            Some(ready_tx),
        ),
    )
    .await
    .expect("the start fails promptly");
    let error = result.expect_err("an unwritable trace path is refused");
    assert!(
        error.to_string().contains("Tick trace"),
        "the error names the trace: {error}"
    );
    assert!(ready_rx.await.is_err(), "ready was never sent");
}
