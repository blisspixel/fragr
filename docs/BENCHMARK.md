# Benchmark and recording contract

The current utility measures server CPU work without sockets. A rendered showcase
is planned in [`plans/showcase-benchmark.md`](plans/showcase-benchmark.md).
Headless results cannot establish GPU support, visual quality, network capacity,
or the maximum number of players a public server supports.

## Run and reproduce

Use the release profile and a fixed seed, map, bot count, and tick count. Keep the
report with the tested commit, CPU model, power mode, and any competing workload.
Run repeated samples before interpreting a small performance difference.

```bash
cargo run -p fragr-server --release --locked -- --bench 16 --bench-ticks 1200 --map 1 --seed 42 --bench-check --bench-assert
```

`--bench-check` compares SHA-256 hashes of the complete header, tick, and score
records across two runs. Stable offline entity IDs also cover dynamically spawned
drones. Normal live sessions retain UUIDv4. Equality proves repeatable observable
output on the tested build; it does not prove every hidden state variable matches
or that floating-point execution is bit-identical on every CPU architecture.

`--bench-assert` rejects any measured step at or above the 50 ms budget, or a p99
above `--bench-max-budget-p99` of that budget (default 0.5). Invalid fractions and
zero tick counts are errors. A debug build is identified in the report and should
not be compared to release measurements.

Threshold unit tests feed known durations through `TickStats` so boundary and
failure-message checks remain deterministic under coverage instrumentation.
Actual speed remains enforced by CI's separate release benchmark and its
unchanged budget gate. A synthetic sample is never performance evidence.

## Report version 2

`config` carries bots, ticks, map identity, seed, and crate version. `environment`
carries OS, architecture, build profile, and available parallelism. The crate
version is not a source revision; retain the commit with published measurements.

| Field | Meaning |
|---|---|
| `stats.timing_scope` | `session_and_encoding` in an offline benchmark; `session` in the live status log |
| `stats.tick_ms` | Total duration for that declared scope |
| `session_ms` | Bot decisions, simulation, snapshot/event construction, and unicast collection |
| `encode_ms` | Encode each broadcast and targeted payload once using the shared wire types |
| `stats.broadcast_bytes` | All broadcast payload bytes per tick before fan-out and framing |
| `unicast_bytes` | All targeted payload bytes per tick, even if no socket receives them |
| `trace_sha256` | Complete recording content identity |
| `deterministic` | `null` without a repeat, otherwise the complete-trace comparison result |
| `frags` | Final round scores, sorted by callsign; not lifetime kills |

Each distribution includes count, mean, exact min/max, p50, p90, p99, and p99.9.
Percentiles use upper edges of 16 log-linear buckets per power of two, conservatively
overestimating by less than 6.25 percent. Budget violation counts use exact samples.
The old `snapshot_bytes` field actually counted all broadcasts; version 2 renames
it to `broadcast_bytes`. Old simulation-only tick results cannot be compared to
version 2 total CPU step times without selecting the same phase.

Timers exclude hashing, trace construction/writing, sleeps, network fan-out, socket
serialization per recipient, transport framing, scheduler delay, and rendering.
The live status line measures the session phase and counts encoded broadcasts;
it does not claim a whole-network tick duration. `GET /status` reports a
different scope, `tick_handler` (simulation plus broadcast and unicast enqueue
and the status refresh), over a sixty second window and the process lifetime,
from the same histogram type; see `docs/protocol.md`. Unicast bytes in a rule-bot-only
run are normally zero because these bots do not send numbered input acknowledgements.
Recording still affects caches and wall-clock load, so compare like configurations.

## Local spectator fan-out

The playtest harness has a separate live WebSocket matrix for 4 or 16 fighters
and 1, 8, or 16 spectators on Arena Duel and Tripoint Works, all at seed 42:

```bash
cargo run -p fragr-playtest --release --locked -- --fanout-matrix --fanout-seconds 10 --report .agents/fanout/matrix.json
```

Each row starts a fresh server and records sample counts. `session_ms` measures
authoritative tick construction. `fanout_enqueue_ms` measures queueing cloned
messages for connected clients, including targeted sends in that tick. It does
not include the socket writer's JSON serialization, transport framing, network
latency, or rendering. Queue high water and overflow counts describe the
bounded outbound FIFOs. Watcher snapshot intervals, missed tick numbers, and
relative arrival spread describe the local receiving side. Watcher text payload
bytes exclude WebSocket and TCP framing. Read the report
with its source revision and host details before comparing results. Loopback
numbers do not establish public-server capacity.

## Trace version 1

Create the output directory first. `--bench-trace PATH` requires `--bench`, opens
a new file, and refuses to overwrite an existing artifact. Disk and encoding
failures stop the run. An interrupted file is incomplete and must be rejected.

UTF-8 NDJSON, one compact object per line, LF terminated, in this order:

1. `header`: `version: 1`, `tick_hz: 20`, `config` matching the report.
2. Exactly `config.ticks` `tick` records: consecutive `tick` starting at 1,
   `broadcast` as shared `ServerMessage` objects, and `unicasts` as pairs of
   recipient (`{"player":"UUID"}` or `{"client":"UUID"}`) and message.
3. `scores`: `frags` as sorted `[callsign, score]` pairs, including dead fighters.
4. `complete`: `ticks` and lowercase `sha256`.

SHA-256 covers the exact bytes of every header, tick, and score line, including
each LF. It excludes the completion line, timings, and environment metadata.
Each tick contains exactly one snapshot with the matching tick number. The first
tick includes authoritative map geometry. This is an offline format, not a new
network protocol. The server exports shared wire types without a second DTO copy.

```bash
cargo run -p fragr-server --release --locked -- --bench-verify-trace .agents/match.ndjson
```

Verification streams one record at a time with an 8 MiB record limit. Unsupported
versions, missing/duplicate headers or scores, missing or misordered ticks, wrong
snapshot tick numbers, truncation, checksum mismatch, or data after completion
fail. A matching hash proves file integrity, not trusted authorship. Client replay,
camera paths, frame-time statistics, and GPU comparisons remain future work.
