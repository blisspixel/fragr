# Human action-to-Ack baseline

**Status:** in flight, 2026-09-27. Measurement rung before live prediction or a UDP gameplay pilot. Follows the [controls plan](buttery-controls.md) and [transport decision](../TRANSPORT.md).

## Goal and why

Measure the actual Godot human Action path on the existing WebSocket server. The client can send up to 120 numbered Actions per second, while the server applies the newest one at each 20 Hz tick and acknowledges that sequence. A sequence is currently a send sample, not one replayable simulation step. The Ack lacks vertical position and velocity, and the live movement path does not yet match the accelerated golden step. Prediction needs a measured input and tick contract first.

## Scope

- Add an opt-in client probe at `GameManager._send_local_action`, `_on_ack_received` and `_on_snapshot_received`. Use Godot's existing monotonic microsecond clock. Keep all gameplay behavior and the on-wire protocol unchanged.
- A bounded helper tracks send timestamps and the first matching Ack. Count sent, uniquely matched, skipped, repeated, stale, invalid, unknown and expired sequences. Record action-to-Ack and snapshot arrival intervals in bounded histograms, plus snapshot tick gaps. A gap is an observed delivery gap, not proof of packet loss. An Action-to-Ack interval is not round-trip time.
- Count queued outbound and received WebSocket text payload bytes locally. The probe report contains no message content, addresses, callsigns, IDs or tickets; the existing QA observation has its own ignored participant record. A connection change invalidates the active capture; starting a new one resets all counts. Write only aggregate probe metrics when an explicit 60-second joined-fighter state requests it.
- Run a local loopback capture, then a two-machine LAN capture when a second host is available. Record commit, OS, renderer, map, roster, duration and transport with each run. Do not claim two-machine or public behavior from loopback.

## Non-goals

No prediction, movement math or Ack wire change, UDP socket, tick-rate change, cloud deployment, account or paid service. The eventual correction p99 target requires a live predictor and is outside this measurement. RTT needs a separate echo clock or synchronized measurement and is not estimated from an Ack.

## Verification

Deterministic Godot tests cover matched, skipped, repeated, stale, invalid, unknown and expired sequences, bounded history, snapshot gaps and reset. Run the pinned Godot checker, its fault-injection self-test, a real 60-second joined-fighter loopback tour, and the unchanged Rust and release gates. The QA report must carry sample counts and percentile definitions so a zero-sample run cannot pass as a baseline. Compare server tick percentiles from `/status` only when sampled from the same run.

### Loopback capture, 2026-09-28 UTC

Source code revision: `67dfc94f7406200eb64902cdcbf6f8737b76a873`. Host: Windows NT 10.0.26200.0, Godot 4.7.2-stable, OpenGL compatibility renderer on AMD Radeon 780M. Transport: local WebSocket on TCP, one joined fighter on Arena Duel, zero rule bots and round events disabled. The QA input makes one jump and is otherwise idle. This is a live human-role client path with synthetic input, not an unsteered human or a LAN measurement. Captured report: ignored `.agents/qa/human-ack-baseline-verified/manifest.json`; UTC time 06:55:35. The still was inspected and shows a live first-person Arena Duel match.

| Window | Queued Actions | Matched Acks | Other sequences without individual Acks | Snapshots | Ack timing p50/p95/p99 | Snapshot arrival p50/p95/p99 | Largest arrival gap | Text payload out/in |
|---|---:|---:|---:|---:|---|---|---|---|
| 60.08 s | 6,510 | 1,200 | 5,308 | 1,202 | 12/14/15 ms | 49/56/57 ms | 165 ms | 1,138,730/1,456,955 bytes |

The first and last matched Ack arrived 22 ms and 60,076 ms into the window; snapshots covered 20 ms to 60,073 ms. A queued Action means Godot's `send_text` returned `OK`; it does not prove server receipt. There were zero local send errors, expired sends, invalid Acks, invalid snapshots or snapshot tick gaps. The gate requires at least 30 queued Actions and 15 matched Acks and snapshots per requested second, samples near both ends, and no gap above 250 ms. Histograms use one-millisecond buckets and nearest-rank percentiles; values at or above 1,001 ms enter an overflow bucket. These Ack percentiles describe only the 1,200 Actions the server selected, about 18 percent of locally queued sends. They do not measure an arbitrary button press, RTT or motion-to-photon latency. A sequence without its own Ack may be normal tick selection or another server-side cause; this probe does not assign one.

The server's 60-second status interval was logged during this run, but it begins at process start and does not align with the client's probe window. Its tick percentiles are therefore not compared numerically here. Two-machine LAN and moving combat samples remain open.

The inbound text payload averaged about 24.2 kB/s for one fighter, before WebSocket and TCP overhead. That already exceeds the older controls plan's proposed 20 kB/s down per client at eight fighters. State serialization and replication need their own budget review; changing transport alone does not remove these bytes.

Local verification: `tools/godot_check.sh` passed on Godot 4.7.2-stable, `tools/test_godot_check.sh` passed all ten fault scenarios, and the joined-fighter capture passed its full-window gate. The final diff passed `git diff --check`. Rust, release and portability gates remain for CI on the draft PR.

## Spend and success

Local probes cost $0. No external API or GCP apply is needed. The branch succeeds when the opt-in probe is stable, its report is reproducible on loopback, and its limitations are explicit. The two-machine table remains open until measured. The next implementation rung can then specify one input per authoritative step, a validated full 3D Ack and replay against live movement before reconsidering UDP.
