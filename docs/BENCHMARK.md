# Benchmark and recording contract

The server utility measures CPU work without sockets. The menu benchmark
measures rendered frame cadence on this computer using one recorded local
fight. A broader authored showcase remains planned in
[`plans/showcase-benchmark.md`](plans/showcase-benchmark.md).
Headless results cannot establish GPU support, visual quality, network capacity,
or the maximum number of players a public server supports.

## Run and reproduce

Use the release profile and a fixed seed, map, bot count, and tick count. Keep the
report with the tested commit, CPU model, power mode, and any competing workload.
Run repeated samples before interpreting a small performance difference.

```bash
cargo run -p fragr-server --release --locked -- --bench 16 --bench-ticks 1200 --map 1 --seed 42 --bench-check --bench-assert
```

The CPU fixture runs free-for-all under the `full-arsenal` mutator, so every
bot is armed from the first tick as before the Pistol start (2026-10-23) and
CPU timings stay comparable. Its recorded rules now name that mutator, so a
trace hash from a build before the change does not match one after it; compare
timings, not hashes, across that line.

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

Timers exclude hashing, trace construction/writing, sleeps, network fan-out,
per-session encoding of targeted messages, transport framing, scheduler delay,
and rendering. The live status line measures the session phase and counts encoded broadcasts;
it does not claim a whole-network tick duration. `GET /status` reports a
different scope, `tick_handler` (simulation, the one encode of each broadcast,
broadcast and unicast enqueue, and the status refresh), over a sixty second window and the process lifetime,
from the same histogram type; see `docs/protocol.md`. Unicast bytes in a rule-bot-only
run are normally zero because these bots do not send numbered input acknowledgements.
Recording still affects caches and wall-clock load, so compare like configurations.

## Local spectator fan-out

The playtest harness has a separate live WebSocket matrix for 4 or 16 fighters
and 1, 8, or 16 spectators on map 1 and Tripoint Works, all at seed 42. Map 1
has been Larak Lot since 2026-10-23; matrix rows recorded before that date ran
on the retired Arena Duel field and are not comparable:

```bash
cargo run -p fragr-playtest --release --locked -- --fanout-matrix --fanout-seconds 10 --report .agents/fanout/matrix.json
cargo run -p fragr-playtest --release --locked -- --fanout-matrix --fanout-stress --fanout-seconds 30 --report .agents/fanout/stress.json
cargo run -p fragr-playtest --release --locked -- --traffic --map 6 --traffic-fighters 48 --traffic-spectators 16 --traffic-bots 32 --traffic-hz 60 --traffic-seconds 15 --seed 42 --report .agents/traffic/sat.json
```

Each row starts a fresh server and records sample counts. The fighters are
in-process reflex agents and also receive every broadcast, so a row has
fighters plus spectators recipients. The server admits eight loopback
spectators per address, so each eight watchers connect from the next 127/8
source address (Linux routes all of 127/8 to loopback; elsewhere the
sixteen-watcher rows fail at the bind). Report schema 3 carries the build
commit and the host environment beside the rows, and names each row's
`scenario`.

`--fanout-stress` (with `--fanout-matrix`) runs the stress rows instead, all
on Tripoint Works at seed 42 with sixteen reflex fighters and eight healthy
watchers: `baseline`; `slow_readers`, plus four watchers that read one frame
every 100 ms (half the snapshot rate); `stalled_readers`, plus four that stop
reading when the window opens; and `steady_input` and `bursty_input`, plus
four human input probes sending the same 60 actions a second either one every
16.7 ms or 30 at once every 500 ms. Degraded watchers are summarized apart
from the healthy ones (`degraded`), probes under `input`.

The stages stay separate, all from one process and one monotonic clock:

| Field | Stage |
|---|---|
| `server_metrics.session_ms` | Authoritative tick construction |
| `server_metrics.broadcast_encode_ms` | The tick task encoding each broadcast once, which also counts its bytes |
| `server_metrics.fanout_enqueue_ms` | Queueing that tick's broadcasts and targeted sends for connected clients |
| `server_metrics.writer.residence_ms` | Enqueue to a session writer taking the message |
| `server_metrics.writer.encode_ms`, `encodes` | JSON serialization inside session writers, one sample per encode |
| `server_metrics.writer.shared_frames`, `shared_bytes` | Frames sent from a tick-encoded payload, and the bytes copied into each frame |
| `server_metrics.writer.send_ms` | Framing and the socket write: send completion, not peer receipt |
| `tick_to_watcher_ms` | Server tick start to a watcher reading the Snapshot frame, before it parses |
| `serialization_ms_per_second` | Tick and writer encode time per measured second |
| `server_metrics.tick_ms`, `late_ms` | The whole tick handler, and how long after its scheduled deadline it began |
| `server_metrics.over_budget`, `skipped_periods` | Handlers at or above 50 ms, and whole periods the loop skipped |
| `server_metrics.writer.send_failures_ms` | When in the window a writer's send timed out or failed, closing that socket |
| `degraded.tick_to_watcher_ms` | The same tick-start-to-read age for slow or stalled watchers: how stale their picture became |
| `degraded.closed_by_server` | Degraded watchers whose socket the server closed before the harness stopped |
| `input.input_to_ack_ms` | A probe writing an action to reading the first applied Ack whose sequence covers it |
| `connection_losses_ms` | When `GET /status`, polled every 100 ms, first showed each lost connection |
| `sockets` | Kernel memory of the server's established sockets at the window's end (`ss -m`, Linux) |

A probe's action sent while an Ack shows it down, or before the server has
applied its first input, is counted in `actions_unapplied` and not timed. A
burst's later actions overwrite earlier ones within one tick, so a covered
action was acknowledged, not necessarily applied by itself.

Queue high water and overflow counts describe the bounded outbound FIFOs.
Watcher snapshot intervals, missed tick numbers, and relative arrival spread
describe the local receiving side. Watcher text payload bytes exclude WebSocket
and TCP framing. The watchers, fighters and server share one process and its
cores, so client work competes with the server; resident memory and process CPU
are not reported because they would mix the two. Read the report with its
source revision and host details before comparing results. Loopback numbers do
not establish public-server capacity.

### Encode-once broadcasts (#434 stage 2)

Before this change each session writer serialized every broadcast for its own
socket and the tick deep-cloned each message into every queue. Now the tick
encodes each broadcast once (the same encode that already counted its bytes)
and every queue holds one shared payload; writers copy its text into the frame
that tungstenite 0.24 owns and encode only targeted messages, which are boxed so
a queue slot is pointer sized instead of a several-kilobyte inline message. The
wire bytes are identical.

Measured 2026-10-24 on Linux x86_64, 16 hardware threads, release build,
10 seconds per row, seed 42. Before is commit `cf4436c` (the instrumented
harness on the old delivery path); after is commit `633d906`. Three matrix
runs each, interleaved before, after, before, after so host load drifted
evenly; each cell is the median of the three, as before / after. The host was
shared with other builds (load average 4.5 to 12), so tail latency is noisy.

| Row (fighters / watchers) | Serialization ms/s | Writer encodes/s | Enqueue p50 ms | Enqueue p99 ms | Tick to watcher p50 ms | Tick to watcher p99 ms | Watcher KiB/s |
|---|---|---|---|---|---|---|---|
| Larak Lot 4 / 1 | 1.40 / 0.34 | 115 / 5 | 0.030 / 0.010 | 0.111 / 0.019 | 0.23 / 0.19 | 0.35 / 0.29 | 41 / 41 |
| Larak Lot 4 / 8 | 2.63 / 0.35 | 268 / 5 | 0.057 / 0.014 | 0.188 / 0.031 | 0.30 / 0.25 | 0.93 / 0.47 | 331 / 331 |
| Larak Lot 4 / 16 | 3.93 / 0.37 | 443 / 6 | 0.086 / 0.018 | 0.221 / 0.059 | 0.36 / 0.31 | 0.58 / 0.61 | 662 / 662 |
| Larak Lot 16 / 1 | 6.58 / 0.63 | 651 / 37 | 0.106 / 0.018 | 0.475 / 0.066 | 0.46 / 0.32 | 0.99 / 0.92 | 87 / 87 |
| Larak Lot 16 / 8 | 8.46 / 0.67 | 909 / 38 | 0.180 / 0.023 | 0.721 / 0.078 | 0.56 / 0.43 | 1.19 / 0.92 | 699 / 699 |
| Larak Lot 16 / 16 | 12.24 / 0.59 | 1192 / 37 | 0.377 / 0.024 | 1.966 / 0.070 | 0.69 / 0.46 | 5.19 / 1.01 | 1397 / 1386 |
| Tripoint Works 4 / 1 | 1.77 / 0.38 | 105 / 4 | 0.039 / 0.012 | 1.311 / 0.049 | 0.28 / 0.21 | 3.20 / 0.51 | 46 / 46 |
| Tripoint Works 4 / 8 | 3.08 / 0.38 | 246 / 4 | 0.082 / 0.015 | 0.205 / 0.057 | 0.30 / 0.29 | 0.57 / 1.08 | 370 / 370 |
| Tripoint Works 4 / 16 | 6.05 / 0.39 | 410 / 4 | 0.188 / 0.019 | 0.655 / 0.055 | 0.43 / 0.35 | 1.54 / 0.56 | 740 / 740 |
| Tripoint Works 16 / 1 | 6.92 / 0.58 | 492 / 23 | 0.221 / 0.017 | 0.590 / 0.059 | 0.55 / 0.39 | 1.46 / 1.10 | 90 / 90 |
| Tripoint Works 16 / 8 | 8.97 / 0.58 | 687 / 22 | 0.311 / 0.020 | 0.754 / 0.066 | 0.60 / 0.46 | 1.38 / 1.30 | 721 / 721 |
| Tripoint Works 16 / 16 | 12.28 / 0.60 | 909 / 23 | 0.410 / 0.026 | 1.245 / 0.442 | 0.70 / 0.48 | 2.40 / 3.74 | 1442 / 1442 |

What this shows, and what it does not:

- JSON encoding falls from 1.4 to 12.3 ms per second of server work to 0.3 to
  0.7 ms, and stops growing with the watcher count. The remaining writer
  encodes are targeted messages: geometry on join, acknowledgements and
  inventory for the in-process fighters.
- The tick's enqueue median falls in every row, by 3 to 16 times, because a
  queue now takes a pointer instead of a deep copy of the Snapshot. An earlier
  five-pair run of the same change without boxed targeted messages, in a
  busier period, cut it by at most about nine times. The tick-side broadcast encode stays about 0.02 ms
  per tick: it was already paid to count bytes.
- Watcher bytes per second match within game-state variance in every row, and
  no run missed a tick, dropped a watcher or overflowed a queue, before or after.
- The median tick-to-watcher time falls in every row; the p99 rises in three
  (Larak Lot 4 / 16, Tripoint Works 4 / 8 and 16 / 16), so no tail latency win
  is claimed on this shared host. The serialization saved was at most
  about 1.2 percent of one core, so this removes repeated work rather than
  fixing a measured bottleneck. It is not evidence of 32 to 64 player
  capacity, two-machine feel or public-server behavior.
- Not measured here: slow or stalled readers under load, bursty input and
  saturation (the stage 1 stress baseline below). Slow-reader isolation, ordering, private targeted state and
  cancellation are covered by tests in `server/src/session.rs`,
  `server/src/net/tests.rs` and `server/src/net/outbound/tests.rs`.

### Stage 1 stress baseline (#434)

Measured 2026-10-27 on Linux x86_64 (kernel 7.2.8), AMD Ryzen 7 7840U, 16
hardware threads, release builds, seed 42. The host was shared with other
lanes' builds and playtests, so every step logged the load average beside its
report; each cell is the median of three runs. Two harnesses: the in-process
stress rows above (stage-separated server timings; clients share the process)
and the traffic generator against the `fragr-server` binary as a child
process (its own resident set, CPU time, sockets and tick trace; clients in
the harness process). Server crate commit `8a5528c8`; the stress harness
commit is `ea59ea97`, which changes only how probes time input. Kernel
defaults: `tcp_wmem` 4 KiB / 16 KiB / 4 MiB, `tcp_rmem` 4 KiB / 128 KiB /
32 MiB. Socket completion is not peer receipt, and loopback is not a public
network.

The first three runs of each harness were taken while the load average sat at
24 to 52 on 16 threads. They are kept below as the contention result; the
tables were rerun at load 7 to 36.

**Slow and stalled readers, bursty input.** `--fanout-matrix --fanout-stress
--fanout-seconds 30`, load 7 to 18. Tripoint Works, 16 reflex fighters and 8
healthy watchers in every row; timings in ms.

| Row | Tick p50 / p99 | Late p99 | Over budget / skipped | Healthy watcher tick to read p50 / p99 | Healthy missed ticks | Queue high water / overflows / replaced worlds | Degraded watchers or probes |
|---|---|---|---|---|---|---|---|
| baseline | 0.20 / 1.25 | 1.64 | 0 / 0 | 0.53 / 2.89 | 0 | 11 / 0 / 0 | |
| 4 slow readers | 0.26 / 3.67 | 2.62 | 0 / 0 | 1.09 / 7.65 | 0 | 11 / 0 / 0 | never closed; picture 8.9 s stale at p50, 20.2 s at the end; 2.0 MiB unsent in the kernel per socket |
| 4 stalled readers | 0.24 / 2.88 | 2.62 | 0 / 0 | 0.81 / 4.86 | 0 | 30 / 0 / 119 | all 12 (three runs) closed by the 2 s send timeout at 28.7 to 29.2 s |
| 4 probes, steady 60 Hz | 0.24 / 3.80 | 1.57 | 0 / 0 | 0.59 / 6.38 | 0 | 10 / 0 / 0 | input to Ack p50 28.5, p99 50.9 (4844 timed) |
| 4 probes, 30 every 500 ms | 0.22 / 1.18 | 1.88 | 0 / 0 | 0.52 / 1.58 | 0 | 8 / 0 / 0 | input to Ack p50 44.8, p99 46.6 (4860 timed) |

- **Healthy readers and the tick are isolated.** No row missed a deadline,
  skipped a period, dropped a healthy watcher or overflowed a queue; slow or
  stalled sockets moved the healthy p99 by a few milliseconds.
- **A stalled reader is closed after about 29 s.** Until then the kernel send
  buffer absorbs its backlog: the 64-slot queue never overflowed, and only
  once the writer blocked did world replacement start (about 120 replaced
  worlds). `GET /status` showed each loss within one 100 ms poll.
- **A slow reader is never closed in a 30 s window and falls ever further
  behind.** Reading 10 frames a second against about 25 sent, it held 2 MiB
  in the kernel per socket. One 120 s run (load 12 to 19) closed the four at
  38 s, by then 35 s stale. The backlog sits in the kernel buffer, not the
  queue, so neither world replacement nor overflow acts until that buffer
  fills: the choke the [server plan](plans/server-excellence.md) asks to
  bound. Bounding the socket send buffer, or closing a writer whose oldest
  unsent frame is too old, are candidate fixes; neither is measured here.
- **Bursty input costs the tick nothing measurable**, in process or against
  the binary below. A probe's latency is the wait for the next tick plus the
  Ack's way back; a burst lands at one phase of the tick, so its spread is
  narrow. Actions sent while the probe was down, or before its first applied
  Ack (2220 to 2346 per row), are not timed.

Retained contention result (load 24 to 52): the same rows reported tick p99
13 to 55 ms, eight over-budget ticks and fifteen missed healthy watcher ticks
in the baseline, and healthy tick-to-read p99 25 to 71 ms. Identical rows at
low load had none, so those misses track the host, not the roster.

**Memory per connection.** `--traffic`, Larak Lot, no bots, 15 s held, load
12 to 36. Resident set of the server process in MiB.

| Roster | Connections | Before clients | Connected | End | After leave | Per connection, connected minus before | Server CPU, cores | Kernel socket memory at end |
|---|---|---|---|---|---|---|---|---|
| 16 spectators | 16 | 10.56 | 12.07 | 12.46 | 12.50 | 97 KiB | 0.01 | 0 |
| 16 idle fighters | 16 | 10.61 | 12.13 | 12.82 | 12.86 | 99 KiB | 0.02 | 128 KiB |
| 48 idle fighters, 16 spectators | 64 | 10.62 | 15.70 | 16.43 | 16.47 | 82 KiB | 0.04 | 0 |
| 48 fighters at 60 Hz, 16 spectators | 64 | 10.73 | 16.13 | 18.83 | 18.84 | 86 KiB | 0.10 | 64 KiB |

- About 80 to 100 KiB of resident set per connection, including the fighter
  each joined human adds to the match; the fixed part amortizes over 64.
- Active input grew the set 2.7 MiB in 15 s against 0.7 MiB idle, and the
  allocator returned nothing when clients left: after-leave equals end in
  every row.
- Healthy sockets held at most 0.13 MiB of kernel memory in total; one slow
  or stalled reader holds about 2 MiB on its own (above). Socket buffers are
  outside the resident set.
- Input load, 32 fighters and 8 spectators: idle, steady 60 Hz and bursts of
  30 used 0.03, 0.08 and 0.05 cores, with tick p99 7.9, 7.8 and 11.0 ms and
  nothing over budget.
- Not measured: a per-structure heap breakdown. These are process totals,
  not the size of a connection's own state.

**Saturation.** `--traffic`, Tripoint Works, human fighters at 60 Hz, rule
bots, 15 s held. The 48 + 16 rows sit at the 64-connection cap and ran free on
all CPUs and pinned to one with `taskset`, interleaved, load 8 to 18; the
smaller rows are from the load 12 to 36 set. Fighters is the mean number of
`players` entries a spectator read.

| Clients (fighters + spectators), bots | CPUs | Fighters | Server CPU, cores | CPU ms per tick | Tick p50 / p99 / max ms | Over budget / skipped | Snapshot KB | Egress MiB/s |
|---|---|---|---|---|---|---|---|---|
| 16 + 8, 0 | all | 16 | 0.04 | 1.9 | 0.25 / 5.1 / - | 0 / 0 | 5.4 | 2.6 |
| 32 + 16, 0 | all | 32 | 0.07 | 3.3 | 0.37 / 8.2 / - | 0 / 0 | 9.2 | 9.0 |
| 48 + 16, 0 | all | 48 | 0.08 | 4.1 | 0.44 / 1.8 / 3.1 | 0 / 0 | 13.3 | 17.1 |
| 48 + 16, 0 | one | 48 | 0.07 | 3.4 | 0.43 / 2.3 / 9.8 | 0 / 0 | 13.3 | 17.1 |
| 48 + 16, 32 | all | 69 | 0.13 | 6.4 | 1.6 / 5.5 / 11.1 | 0 / 0 | 20.2 | 25.5 |
| 48 + 16, 32 | one | 68 | 0.11 | 5.4 | 2.6 / 6.7 / 9.2 | 0 / 0 | 20.2 | 25.3 |
| 48 + 16, 96 | all | 101 | 0.19 | 9.7 | 3.4 / 16.1 / 20.9 | 0 / 1 | 32.5 | 33.2 |
| 48 + 16, 96 | one | 101 | 0.17 | 8.4 | 4.7 / 13.6 / 16.4 | 0 / 1 | 33.7 | 33.0 |

- **No tick ran over budget up to the connection cap with 96 rule bots**,
  about 101 fighters, on all CPUs or one; each 96-bot run had one
  host-scheduled skipped period. Saturation was not reached inside
  the server's own caps on this host. Offline beyond the caps (`--bench`, no
  sockets, Tripoint Works, 600 ticks, one run each at load 17 to 18), the
  simulation and encode stayed inside budget through 256 bots:

  | Bots | Tick p50 / p99 / max ms | Over budget | Broadcast bytes per tick |
  |---|---|---|---|
  | 64 | 1.2 / 3.7 / 5.0 | 0 | 15020 |
  | 128 | 4.5 / 18.9 / 32.4 | 0 | 24687 |
  | 192 | 6.3 / 24.1 / 31.3 | 0 | 34889 |
  | 256 | 7.9 / 25.2 / 30.8 | 0 | 45339 |

- Bytes, not CPU, grow fastest: every connection receives the whole snapshot,
  13 KB at 48 fighters and 33 KB at 101, so egress at the cap reached 17 to
  33 MiB/s (about 140 to 280 Mbit/s). The once-per-tick encode stayed under
  0.1 ms at p50.
- Retained contention result (load 30 to 47): the 48 + 16 rows missed 82 to
  91 deadlines in 15 s with the server at half a core, and 48 + 16 with 96
  bots failed to welcome its clients in one of three runs (18 ticks in 15 s).
  A one-CPU sweep taken just after the load fell looked five times cheaper;
  the interleaved A/B above shows that was the load falling, not the pinning.

**Snapshot shape and relevance (stage 3).** One spectator parsed about one
snapshot a second. For every live fighter, the share of the other live
fighters farther away than each radius, straight-line distance only.

| Map and roster | Fighters | Snapshot KB | Beyond 16 / 32 / 64 m |
|---|---|---|---|
| Larak Lot, 32 bots | 18.9 | 7.9 | 82 / 56 / 5 % |
| Larak Lot, 48 synthetic fighters, 16 spectators | 45 | 13.5 | 79 / 60 / 8 % |
| Tripoint Works, 32 bots | 27.3 | 9.8 | 99 / 92 / 81 % |
| Tripoint Works, 64 bots | 49.1 | 16.8 | 98 / 91 / 79 % |

(Larak Lot holds fewer bots alive at once than it was given: fighters waiting
to respawn are not in the count.) A `players` entry is 250 to 300 bytes of
JSON: the UUID `id` alone is 44, `name`, `behavior`, `just_fired`,
`collidable`, `body` and `weapon` 15 to 22 each, each coordinate 8 to 14, and
the cumulative counters (`score`, `deaths`, `attacks`, `connects`, `damage`,
`heads`) about 50 together although they change rarely. The fixed part of a
snapshot (pickups and round chrome) is about 1.4 KB.

**Decision: no relevance change at the current scale.** Against the three
reasons to cull per recipient:

- CPU: the shared encode costs under 0.1 ms per tick at 101 fighters, so
  encoding does not limit 32 to 64 players. Culling would trade the one
  encode for one per recipient.
- Bytes: per-recipient bytes do matter at 48 fighters and 64 connections
  (17 MiB/s, past most home uplinks). But on Larak Lot, the hero arena, only
  5 to 8 percent of fighters are beyond 64 m of each other, and nearer radii
  (56 to 60 percent beyond 32 m) would hide fighters in plain sight across
  the lot: distance is not visibility. Only Tripoint Works, not yet authored
  for 32 or more, shows a large cut (about 80 percent beyond 64 m).
- Contract: the client frees any fighter missing from a Snapshot, which today
  means down or gone (`game_manager.gd`), so culling needs a wire change
  (culled is not down), spectator, death-view and team exceptions, and
  lifecycle rules. A 5
  percent saving on the hero map does not pay for that or for losing the
  shared payload.

The larger byte lever on every map is stage 4: acknowledged deltas and a
compact encoding of the entries above. Relevance is revisited when a map built
for 32 or more fighters exists (pass 7 of the server plan), with these rows
as its before table. No wire, client or server behavior changed.


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
fail. A matching hash proves file integrity, not trusted authorship. Client replay of
a server trace and the nine-scene camera path remain future work. The menu
comparison below captures its own bounded in-memory snapshot sequence.

## Player benchmark

Choose **Benchmark** from the main menu to measure the current preset or compare
Performance, Balanced and High. It first records 28 seconds of an owned local
ten-bot Larak Lot match, then stops that host. Every preset replays the same
authoritative snapshots and time-based camera path. Eight warm-up seconds are
discarded, followed by twenty scored seconds. V-sync and the frame cap are
temporarily disabled; completion, cancellation and failure restore the user's
settings without saving the temporary graphics draft.

The camera is a scripted orbit that follows nobody: no fighter is hidden for an
eye view and no viewmodel is drawn. The match HUD is hidden for the whole run,
for every preset alike. The benchmark's own readout (`BenchmarkHud`) names the
step (recording, loading, warming up, measuring), shows overall progress against
the nominal content time (28 s plus 28 s per preset; loading between presets is
not counted, so the remaining time reads "about"), and a live frame rate and
frame time over roughly the last second, refreshed four times a second. While a
preset is scored it also shows that preset's running average (scored frames over
scored seconds). Live figures are labelled live and are never the result. A
refresh restyles the step chips only when the step changes, so the readout's
script cost stays small inside the measured frames; `qa_benchmark.gd` prints
that cost on the host it runs on. The
readout starts below the player's frame counter when that counter is on, using
the same reserved-region rule as the match HUD. Esc cancels; the Benchmark page
then says the run was cancelled and nothing was saved.

A completed result leads with **Benchmark complete** and, per preset, average
FPS, one 1% low, the 99th percentile frame time and frames at or above 33 ms,
then one frame-time timeline: every scored frame, one row per preset on a shared
scale named in its heading, with 60 and 30 FPS guides. Rows shrink with the
window so the cards, the whole timeline and the actions share one screen at
1280x720 and above. **Details** holds p50/p95/p99.9/maximum frame time, the
0.1% low, frames at or above 50 ms, hitches against the trailing second, the 3D
render size, system, the shared Display settings, what each preset changes
(MSAA, shadow atlas, light fixture shadows, ambient occlusion, glow, read from
the same `RenderQuality` rules that applied them), definitions and the last
compatible run. Run again, Copy summary, Open results folder and Back to menu
stay on screen without scrolling. Focus stays on those actions for mouse,
keyboard and pad alike; up and down (arrows, D-pad, stick) and page up and down
scroll the figures and Details. A stopped run (settings changed, window
resized, frames stopped for two seconds, a preset or the match did not load)
says **Benchmark stopped** with one card: the reason, the step it stopped
during, any presets that finished (their figures are not kept), that nothing was
saved and that settings were restored. It has no figures.

The 1% low is 1000 divided by the mean milliseconds of the slowest
`ceil(frame_count * 0.01)` frames. Average FPS is frame count over measured time.
Monotonic whole-frame intervals measure visible cadence, not GPU execution time,
display latency or input latency. Report schema 3 keeps every scored interval in
whole microseconds (`runs[].frame_us`); `FrameStats` on those values reproduces
every displayed figure and the timeline. The JSON and CSV also retain the
adapter, renderer, engine, build, resolutions, applied settings, sample count
and replay digest. Use **Open results folder** to find the local artifacts. No
raw participant or network recording is saved.

Compared presets within a run receive the same fight; a new run records a new
fight. A result is compared with an earlier one only when their `compatibility`
keys match: schema, workload id, metric version, engine and build, OS, display
server, renderer, driver, adapter, graphics API, output size, and each preset's
3D render size and settings. The display server is in the key because
presentation is part of what is measured: on one Linux host, each of eight X11
(XWayland) runs stalled for 0.2 to 0.8 s at the same two points of every
preset, one inside the scored window, before the frame's first physics step;
one native Wayland run, which the compositor also sized differently, had no
scored frame over 0.15 s. The workload id changes whenever the measured scene
changes (hiding the match HUD was such a change), so older results never
compare as equal.
Matching keys rule out unlike runs; they do not make two recordings the same
fight. Repeated runs and a representative workload matter before judging small
differences. The report records `scene_revision`: revision 2 is Larak Lot with
an orbit 31 m out and 17 m up; revision 1 circled the retired Arena Duel field
and its scores are not comparable. This scene does not establish 64-player capacity or
island performance. Headless checks cover arithmetic and lifecycle, not hardware
frame rates. A frame rate is not a CI gate. The server `--bench` results above
remain separate CPU measurements. The
[comparison plan](plans/benchmark-preset-comparison-20261006.md) records the
actual renderer acceptance and remaining broader showcase work.

## Stutter diagnosis traces

Two opt-in recordings, one per process, join on the Snapshot tick so a
player-reported hitch can be separated into a slow drawn frame, a server stall
or skip, a late delivery, a prediction correction or reset, a remote pawn whose
interpolation ran dry, or a camera mode change. Both are off by default and
cost one boolean test per hook while off. The
[stutter diagnosis plan](plans/stutter-diagnosis-20261023.md) holds the first
measurements and their limits.

**Server tick trace version 1.** `fragr-server --tick-trace PATH` (or
`FRAGR_TICK_TRACE` set to an absolute path, which a client-launched desktop or
campaign host inherits) truncates `PATH` and writes UTF-8 NDJSON: a `header`
(`version`, `tick_us`, `build`, `started_unix_us`), one `tick` record per served
tick and a `complete` footer (`ticks`, `dropped`, `over_budget`,
`skipped_periods`) on clean shutdown. A killed process leaves no footer; its
flushed ticks remain readable. Each `tick` carries the Snapshot tick number,
`unix_us` at handler start, `late_us` after the scheduled deadline,
`skipped` whole periods the interval skipped, and microseconds for
`sim_us` (session tick and run persistence), `measure_us` (encoding each
broadcast once, the payload every session sends, and counting its bytes),
`fanout_us` (queuing broadcasts and unicasts, not socket
completion) and `total_us`, plus clients, messages, bytes and queue
overflows. A writer thread owns the file behind a bounded 1,024-record queue;
a full queue drops and counts records rather than delay a tick. An unwritable
path fails the start. The flag is refused beside `--bench`,
`--bench-verify-trace` and `--local-run-preview`, which run no served tick
loop, and beside `--local-mission`, which reads only `FRAGR_TICK_TRACE`. Every
host process the client starts truncates the same file, so copy a trace before
hosting or starting a mission again.

**Client stutter trace version 1.** In a match, the console's `stutter start`,
`stutter mark <label>` and `stutter stop [path]` record a bounded window and
write JSON under `user://diagnostics/` by default. Leaving the match saves an
open recording. Per drawn frame it keeps the interval, the whole `_process`
span (first and last process-priority markers on the PerformanceOverlay), the
renderer's measured CPU and GPU time, new pipeline compilations, starved remote
pawns and the camera pose; per network poll that delivered messages, the drain
time and message count; per Snapshot, tick, arrival and handler time; per Ack,
sequence and tick; prediction corrections, resets and state changes; camera
mode changes and marks. `StutterReport` reads both files, refuses malformed
input, and names a cause only when a measured stage holds at least half of a
slow interval's excess over the median frame. `client/scripts/qa_stutter.gd`
drives a scripted rendered session through these phases and writes the joined
report and table. Wall-clock delivery figures assume one shared clock and
hold only when client and server run on the same machine.
