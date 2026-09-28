# Continuous WebSocket moving-combat probe

Status: implemented in local draft work, 2026-09-28. Branch `test/websocket-moving-combat`, based on the local prediction draft at `0d75fa5`. Integration and human/LAN gates remain open.

## Goal

Measure one uninterrupted joined human-role session that moves and fires on the existing WebSocket path. Record same-tick prediction correction sizes, fallback reasons including Ack timeouts and unknown sequences, Ack and snapshot cadence, and text payload traffic in one bounded window. Use the result as evidence for the next transport decision, not as a capacity or human-feel claim.

## Scope and architecture

- Reuse `InputAckProbe`, `LocalPrediction`, the real `GameManager` Action path, and the rendered `qa_tour` driver. Add one opt-in tour state that holds ordinary movement and fire input against rule bots, without pausing for screenshots during the timed window. Verify from server snapshots that the fighter moved and shots resolved.
- Snapshot diagnostic counters at the start and end of that same window. Record correction sample count and nearest-rank p50/p95/p99/max in metres, fallback reasons, Ack first/last coverage and gaps, snapshot intervals and tick gaps, and outbound/inbound text payload bytes. Explicitly report death, respawn, role changes or probe interruption as invalid or limited windows.
- Produce an ignored `.agents/qa/` manifest and document exact command, build, map, roster, OS, renderer, duration and observed numbers here. Do not silently use a capture-tour pause as continuous-play evidence.

## Non-goals and API impact

No wire or server authority change, UDP implementation, cloud apply, paid service, 60 Hz migration, human-feel claim, or public-host scale claim. The QA manifest gets a diagnostic state; the gameplay protocol does not change.

## Verification and success

- Extend the Godot QA harness for invalid duration and a zero-shot or zero-movement capture. Keep input and correction unit harnesses green.
- Run the pinned Godot checker, then the rendered loopback tour with a full timed moving-combat window. Require live human-role Actions and matched Acks near both ends, snapshots throughout, resolved shots, nontrivial displacement, no connection/role interruption, and a reported correction/fallback sample set. Inspect the receipt and client/server logs.
- Report measured limits and any failure as evidence. A local pass makes the next LAN or network-induced correction experiment concrete but does not complete the broader controls gate.

## Spend

Local WebSocket and rule-bot work only, $0. No external call or infrastructure apply.

## Local receipt, 2026-09-28

Two loopback capture attempts completed and passed, with zero invalid windows. The final run used Windows 11 Pro 10.0.26200, Godot 4.7.2-stable, the OpenGL compatibility renderer on an AMD Radeon 780M, a release Rust server at `127.0.0.1:6793`, Arena Duel, simulation seed 1, one aggressive rule bot and free-for-all rules. `FRAGR_QA_NO_ROUND_EVENTS=1` disabled the timed boss and compliance pings; ordinary round start, frag and Host events still occurred. A joined human-role client received the same WebSocket JSON snapshots and sent ordinary Actions. The tour held movement and fire for 20 seconds, with no screenshot pause during the window. The client/server logs, full manifest, contact sheet and still are ignored under `.agents/qa/websocket-moving-combat-final/`. The still was inspected and shows a live first-person world and HUD. The first run, before peak-context instrumentation, is under `.agents/qa/websocket-moving-combat/`.

Reproduce from this branch in Git Bash, with Godot 4.7.2 installed:

```bash
export FRAGR_GODOT=/c/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe
export FRAGR_QA_BOTS=1 FRAGR_QA_NO_ROUND_EVENTS=1
export FRAGR_QA_MANIFEST=res://qa/websocket-moving-combat.json FRAGR_PORT=6793
tools/qa_tour.sh .agents/qa/websocket-moving-combat-final
```

| Loopback window | Server-observed travel | Player shots during moving snapshots | Matched Acks / snapshots | Same-tick correction p50 / p95 / p99 / max | Prediction fallbacks | Text payload out / in |
|---|---:|---:|---:|---|---|---:|
| First, 20.018 s | 85.914 m | 94 / 94 | 400 / 400 | 0 / 0 / 0.0008 / 0.2754 m | 0 | 386,039 / 666,954 bytes |
| Final, 20.022 s | 85.513 m | 92 / 93 | 400 / 401 | 0 / 0.0006 / 0.0030 / 0.3536 m | 0 | 387,678 / 668,569 bytes |

The final run had 401 correction samples. Its largest same-tick replay mismatch arrived 15.052 seconds into the window, on authoritative tick 536 at server position `(-12.422, 1.5, -24.314)`. That is near the north gantry area, but this receipt does not identify whether collision, changing aim/direction, or Action selection caused it. The first run did not record peak context. Correction values are rounded to four decimals in the receipt. They measure predicted versus authoritative body position for the same server tick, not latency or rendered camera error. Zeros at that precision do not establish zero latency. The diagnostic reports `ack_timeout: 0` and `unknown_seq: 0` in both runs; it cannot establish their rate on a lossy or remote connection.

In the final run, 2,170 Actions were locally queued and 400 selected Actions received a matched Ack. Action-to-Ack p50/p95/p99 was 11/14/15 ms for those selected Actions only. First/last matched Acks were 56/20,003 ms, and the largest matched Ack gap was 59 ms. Snapshot arrival interval p50/p95/p99 was 49/56/57 ms, with a 58 ms largest gap and zero observed tick gaps. Snapshot samples covered 3/20,002 ms. There was one pre-probe Ack from an Action sent before the window, no invalid Acks or snapshots, no send failure and no connection or role interruption. The player remained alive. A live opponent appeared in 326 polled snapshots, two opponent shots were observed, and the server logged a human frag. Text payload rates were about 19.4 kB/s outbound and 33.4 kB/s inbound, excluding WebSocket and TCP overhead. The 50 ms tour polling saw 383 distinct server snapshots, while the network probe counted all 401 received snapshots. The 85.513 m travel and 93 resolved player shots come from those 383 polled snapshots, so they are sampled lower bounds for the full window.

Verification: focused `test_qa_combat.gd` and `test_local_prediction.gd` passed after the final changes; the pinned `tools/godot_check.sh` completed with `Godot checks: PASS`. The QA tests reject invalid durations, simultaneous probe modes and missing movement or shot evidence. `git diff --check` passed. The local release server build and rendered tour passed. The full Rust/coverage/packaging suite and two-machine LAN or network-induced correction experiment were not run here. This $0 loopback result is a continuous automated combat sample, not a human-feel, remote-latency or server-capacity result.
