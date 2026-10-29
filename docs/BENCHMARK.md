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
  bound. Fixed and measured in
  [Slow-reader close](#slow-reader-close-492) below (#492).
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

### Slow-reader close (#492)

A reader that falls behind is now closed within seconds, three ways, all in
`server/src/net.rs`:

- The kernel send buffer of a game socket is bounded (`SO_SNDBUF`, 64 KiB
  asked; Linux doubles it for its bookkeeping), so the writer blocks within a
  fraction of a second instead of after megabytes, and the backlog stays in
  the outbound queue, where a newer world replaces an unsent one.
- A queued frame still unsent 2.5 s after the tick queued it closes the
  socket (`OUTBOUND_STALE_AFTER`), whether the writer reaches it late or
  its send stalls. The 2 s send timeout now applies to the keepalive ping.
- A ping unanswered for 4 s closes the socket (`READ_BEHIND_AFTER`), with
  the ping every second instead of every five. A client answers a ping only
  after reading every frame before it, so this bounds what the send buffer
  cannot see: bytes already in the reader's own receive buffer, which
  Linux grows to megabytes for a loopback or fast peer. It is longer than
  the frame-age bound so one long client frame hitch is not a disconnect.

The unanswered ping closes with `idle_timeout`, which replaces the old 45 s
no-frame rule (a client that sends nothing also answers no ping, so the ping
always fired first and the old rule could not be reached); the other two
close like a dropped connection. A fighter that asked for resume keeps its
pawn either way.

A client builds a level on its main thread and reads nothing meanwhile, so
after the server sends a `MapInfo` or `Mission` neither the ping nor the
frame-age close applies for 30 s (`LOAD_GRACE`), or until the client answers
a ping sent after that message. Frames that waited out a load age from its
end. Measured with the real Godot client joining as a spectator (a scratch
probe timing every main-thread frame for 20 s against the release server,
2026-10-28, Ryzen 7 7840U with Radeon 780M, shader caches warm): after the
socket opened, the longest frame on M09, M14, M19 and Still Here was 0.21 s
headless and 0.48 s with the Vulkan renderer at 1280 by 720; loading the
match scene itself, before the socket opens, took 1.7 s. A cold pipeline
cache was not measured; 30 s is about sixty times the measured stall and
matches the roughly 29 s a stalled reader survived before this change. The
64-message queue still bounds memory during a load and its overflow close
is unchanged, but with the bounded kernel buffer it now fills sooner than
behind the old 4 MiB one: a busy room with many shots in flight can
disconnect a client whose load lasts several seconds. Tests:
`a_reader_building_a_level_keeps_its_socket_until_the_load_grace_ends`,
`an_answer_after_the_map_ends_the_load_grace_early`,
`a_level_load_holds_off_the_frame_age_close_until_the_grace_ends`.

Healthy readers, MapInfo before state, the reliable facts across world
replacement and the access-list order are unchanged; the tests are in
`server/src/net/tests.rs` (`a_frame_queued_past_its_age_...`,
`a_blocked_send_closes_when_its_frame_goes_stale_...`,
`a_reader_slower_than_the_tick_is_closed_...`,
`a_slow_but_sufficient_link_is_never_closed`,
`a_reader_that_stops_answering_pings_...`,
`accepted_game_socket_bounds_its_send_buffer`) and
`server/src/metrics/tests.rs`.

Measured 2026-10-28, same host as the stage 1 baseline (Ryzen 7 7840U, 16
threads, kernel 7.2.8), release builds, `--fanout-matrix --fanout-stress
--fanout-seconds 30`, Tripoint Works, 16 reflex fighters and 8 healthy
watchers in every row, seed 42. One run per build, each with its load
average; the host was shared with other lanes. Before is `009797ce`. The
middle builds are this branch on the way, kept because they show why each
part is needed. After is the branch head (deltas on, so frames are small).

| Build (load) | Slow readers closed at | Slow picture age p50 / at close | Stalled readers closed at | Healthy tick to read p50 / p99 ms | Tick p99 ms | Over budget / healthy missed |
|---|---|---|---|---|---|---|
| Before (16 to 14) | never in 30 s (38 s in a 120 s run) | 8.9 s / 20 s at the window's end | 28.9 to 29.0 s, by the 2 s send timeout | 0.52 / 2.38 | 0.95 | 0 / 0 |
| 128 KiB buffer, 2.5 s frame age (38 to 24) | 8.7 to 14.0 s | 4.2 s / about 6 s | 5.4 to 5.9 s, three by queue overflow | 2.48 / 11.8 | 6.0 | 0 / 0 |
| 64 KiB buffer, 2.5 s frame age (29 to 37) | 8.0 to 9.3 s | 3.7 s / about 5 s | 5.3 to 5.4 s, by overflow and frame age | 3.43 / 10.5 | 6.0 | 0 / 0 |
| Same, with deltas (28 to 30) | 18.4 to 18.7 s | 9.0 s / about 10 s | 16.0 to 16.8 s, by frame age | 3.54 / 16.0 | 6.6 | 0 / 0 |
| After: 64 KiB, 2.5 s frame age, 4 s unanswered ping, deltas (18) | 7.0 to 12.0 s, by the unanswered ping | 4.0 s / 4 to 6 s | 5.9 s, by the unanswered ping | 1.30 / 11.5 | 5.2 | 0 / 0 |

- **The kernel buffer was the whole delay.** Bounding it alone brought both
  closes from about 29 to 38 s down to 5 to 14 s; 64 KiB against 128 KiB
  saved about a second more, inside the host's noise.
- **A byte bound is a time bound only for one frame size.** With deltas a
  world is about 1.9 KB instead of 6, so the same buffers held three times
  as many worlds and both closes slid back to 16 to 19 s. Most of those
  bytes sat in the reader's own receive buffer, which no server setting
  bounds. The unanswered ping measures time directly, whatever the frame
  size or where the bytes wait, and brought both closes back under 12 s.
- **A half-rate reader is closed once it is about four to six seconds
  behind.** It falls behind half a second per second, so the 4 s ping bound
  trips 8 to 12 s in. After the close it can still read what its own
  receive buffer holds, so the harness's maximum age (14 s) includes that
  drain; the server's part ends at the close.
- **Nothing healthy was closed.** No healthy watcher or input probe dropped
  in any row, no tick ran over budget and no healthy snapshot was missed.
  The healthy and tick tails move with the host load in this table (load
  18 to 38 against 14 to 16 before), not with the change: the baseline row,
  which has no degraded reader, moved the same way.
- The degraded summary counted three of four stalled watchers closed in two
  middle runs while `GET /status` showed all four connections lost; the
  harness's bounded drain after the window, not the server, missed one.
- Not measured: a real thin link (tc netem) and Windows or macOS socket
  buffers. A host that sets `SO_SNDBUF` gets no autotuning on that socket;
  64 KiB carries a 48-fighter world of deltas (about 100 KB/s) on a link
  with up to about half a second of round trip.

### Snapshot deltas (#434 stage 4)

Gameplay 61 sends a world as the change from the world before it
(`snapshot_delta`; gameplay 63 keys its roster by position and replaced this
shape, see the next section and the
[protocol](protocol.md#snapshot-deltas-capability-63)).
The tick encodes each world once in full and once as the delta from the
previous tick's world, and keeps the delta when it is shorter. A session
writer sends the delta only when the last world it put on its socket is the
delta's base; the ordered, reliable stream makes that the reader's world, so
no separate acknowledgement is needed on this transport. Anything else goes
whole: a connection's first world, the first after `MapInfo` or `Mission`, a
world that replaced an unsent one, and every world for a reader below 61.
The wire types and the one Rust reader (`protocol::WorldReader`) live in
`server/src/protocol/delta.rs`; the MCP adapter, playtest harness, brain and
`fragr-wire` read through it, and the Godot client rebuilds the world in
`client/scripts/snapshot_delta.gd` before its usual snapshot validation.
Tests on both sides apply the same vectors
(`client/golden/snapshot_delta_vectors.json`), and a seeded 400-tick fight
rebuilds every world byte for byte. The server parses JSON with
`serde_json`'s `float_roundtrip`, so a value a delta repeats keeps the exact
shortest text of the full world.

Measured 2026-10-28 with the traffic generator against the `fragr-server`
binary: Larak Lot, human fighters at 60 Hz plus spectators, no bots, 15 s
held, seed 42, one run per row. Before is `009797ce` (load 12 to 17); after
is the branch head (load 14 to 15, with a workspace test run on the same
host). Bytes per client are every text frame a connection read, divided by
connections and seconds; a world as JSON text, not counting WebSocket and
TCP framing.

| Connections (fighters + spectators) | Fighters in a world | Full world bytes | KiB/s per client before / after | Change | Server egress MiB/s before / after | Tick encode p50 / p99 ms before / after | Server CPU cores before / after |
|---|---|---|---|---|---|---|---|
| 6 (4 + 2) | 4 | 2,333 | 51.7 / 14.0 | -73 % | 0.30 / 0.08 | 0.018 / 0.062, 0.108 / 0.887 | 0.019 / 0.020 |
| 16 (12 + 4) | 12 | 4,270 | 92.0 / 29.8 | -68 % | 1.41 / 0.46 | 0.018 / 0.039, 0.171 / 1.818 | 0.028 / 0.037 |
| 64 (48 + 16) | 45 | 13,617 | 286.6 / 97.4 | -66 % | 17.37 / 5.95 | 0.036 / 0.071, 0.483 / 4.914 | 0.090 / 0.097 |

- **About two thirds fewer bytes at every size.** At the 64-connection cap
  the server's egress fell from 17.4 to 6.0 MiB/s (about 146 to 50 Mbit/s),
  and each reader's from 287 to 97 KiB/s. Every world still reached every
  reader: snapshot counts matched before and after, and no tick ran over
  budget.
- **The encode is the cost.** Parsing the full world back to a JSON value,
  diffing it and writing the delta take the tick's encode from 0.04 to
  0.48 ms at the median at 48 fighters, about one percent of the 50 ms
  budget (p99 4.9 ms on a host running a test suite). It is still paid once
  per tick, not per reader.
- **What a delta still carries.** A fighter who moved costs its 44-byte
  `id` plus the changed coordinates and angles, each 8 to 14 bytes of
  shortest-form float: about 110 bytes, of which the id is about 40 percent.
  Unchanged entries cost the id alone. The pickups (1.1 KB) and round chrome
  no longer repeat.

Next steps, in the order the numbers suggest. Items 1, 3 and 4 shipped in
wave 15 (gameplay 63, next section):

1. **Short roster keys.** Shipped: carried fighters are keyed by base roster
   position.
2. **Quantized motion.** Coordinates to millimetres and angles to 1e-4 rad
   would shorten each changed float by about four bytes and stop
   sub-millimetre jitter from counting as a change. This changes the values
   readers see, so it needs the movement mirror's reconciliation checked
   against the goldens first. Shipped in wave 16 on the Snapshot only; the
   `Ack` that reconciliation replays from stays exact (see "Quantized
   motion" below).
3. **A per-reader delta after a replaced world.** Shipped.
4. **A cheaper encode.** Shipped as a text diff rather than a typed one.
5. **Explicit acknowledgements** only arrive with an unreliable transport
   (UDP, [TRANSPORT.md](TRANSPORT.md)): then the base must be the last world
   the reader said it applied, and a delta may name an older base.

### Roster keys, per-reader deltas and a text encoder (#434 stage 4, wave 15)

Gameplay 63 changes the delta's roster
([protocol](protocol.md#snapshot-deltas-capability-63)). A carried fighter
no longer repeats its 44-byte `"id":"<uuid>",`: it is named by its position
in the base world's roster (`at`), and the position is omitted when it is one
past the previous carried entry's, which is every entry while the roster
keeps its order. An unchanged fighter costs `{}`. A whole arrival still
carries its `id`, and the rebuilt world has every full id, so facts and
readers keep the UUID. The key needs no per-session mapping message: the base
world both sides hold is the mapping. A reader at 61 or 62 now receives every
world whole.

Two server-side changes ride with it, neither a wire change:

- **Per-reader deltas.** A writer whose reader holds an older world than the
  tick's delta names (the world in between was replaced unsent) encodes its
  own delta from the world it last sent, on its own task, instead of sending
  the whole world. It keeps that world as the shared broadcast (`Arc`), so
  nothing is copied. The writer probe counts these (`rebased_frames`,
  `rebased_bytes`, `rebase_ms`).
- **A cheaper encode.** The encoder diffs the two worlds' JSON text field by
  field through borrowed `serde_json::value::RawValue` slices (the
  `raw_value` feature of the existing `serde_json`), in serializer order, and
  writes the delta directly. No number is parsed and no value is copied,
  where the wave 13 encoder parsed every world into a `serde_json::Value` and
  cloned what changed. Text equality is value equality here because both
  worlds come from the same serializer; the golden test checks the recorded
  deltas of fought worlds against it.

Measured 2026-10-28 with the traffic generator against the `fragr-server`
binary, the same setup as the table above: Larak Lot, human fighters at
60 Hz plus spectators, no bots, 15 s held, seed 42. Three interleaved runs
per row on an AMD Ryzen 7 7840U shared with other sessions (load 3 to 4).
Before is `1a8574c8` (gameplay 62), after is the wave 15 branch. Values are
the mean of three runs; ranges where runs differed visibly.

```bash
cargo run -p fragr-playtest --release --locked -- --traffic --map 1 --traffic-fighters 48 --traffic-spectators 16 --traffic-bots 0 --traffic-hz 60 --traffic-seconds 15 --seed 42 --report .agents/traffic/after-48-16.json
```

| Connections (fighters + spectators) | Mean delta bytes before / after | KiB/s per client, all frames, before / after | Of which worlds | Server egress MiB/s | Tick encode p50 ms | Tick encode p99 ms | Server CPU cores |
|---|---|---|---|---|---|---|---|
| 6 (4 + 2) | 441 / 266 (-40 %) | 14.0 / 10.5 (-25 %) | 8.8 / 5.3 | 0.08 / 0.06 | 0.085 to 0.099 / 0.043 to 0.045 | 0.14 to 0.21 / 0.08 | 0.016 / 0.015 |
| 16 (12 + 4) | 1,225 / 687 (-44 %) | 30.0 / 19.5 (-35 %) | 24.2 / 13.7 | 0.47 / 0.31 | 0.14 to 0.15 / 0.065 to 0.068 | 0.18 to 0.27 / 0.10 to 0.11 | 0.030 / 0.026 |
| 64 (48 + 16) | 4,528 / 2,538 (-44 %) | 97.0 / 57.8 (-40 %) | 89.6 / 50.4 | 6.06 / 3.61 | 0.37 to 0.39 / 0.17 | 0.64 to 0.83 / 0.25 to 0.28 | 0.097 / 0.085 |

- **Bytes.** The id was the measured 40 percent: a mean delta at 45 fighters
  fell from 4.5 to 2.5 KB, and a 64-connection server's egress from 6.1 to
  3.6 MiB/s (about 30 Mbit/s). Since wave 13's start, per-client traffic at
  the cap is 287 to 58 KiB/s. At 6 connections worlds are now half of what a
  fighter reads; the rest is acknowledgements and combat facts.
- **Encode.** The tick encode (every broadcast of a tick, worlds included)
  fell by more than half at every size, p50 0.38 to 0.17 ms at 48 fighters.
  Release microbench (`delta_encode_cost_at_48_fighters`, ignored test, three
  interleaved runs, 46 fighters on Larak Lot): observing one world, delta
  included, took 100 to 102 us before and 41 to 42 us after; serializing the
  world itself is 13 us. Parsing a world into a `Value` alone costs 60 us,
  which is why the first text version, which read both worlds into ordered
  maps, measured 114 us and was replaced by the field list in serializer
  order.
- **Every world still arrived.** Snapshot counts match before and after,
  each connection's first world was its only whole one, and no tick ran
  over budget.
- **Per-reader deltas did not trigger on loopback.** The traffic rows never
  replace a world (no reader falls behind), and in the `--fanout-stress`
  slow-reader row (four watchers reading one frame per 100 ms) the readers'
  backlog sits in the kernel's receive buffer, so the writer never blocks,
  no world is replaced (`missing_snapshot_ticks` 0 before and after) and
  `rebased_frames` stayed 0 until the slow-reader rules closed them. Those
  slow readers did read 41 percent fewer bytes per world read, all frames
  counted (1,385 to 818),
  from the roster keys. The rebase path is covered by tests that force a
  replaced world (`net::tests`, and a fought match rebuilt across gaps of 2
  to 10 ticks in `protocol::delta::tests`); its value on a real short link
  is not measured here.

What stays open for stage 4: quantized motion (item 2 above), and field
evidence of per-reader deltas on a real constrained link. Wave 16 measured
and shipped item 2 (next section) and measured per-reader deltas on a
simulated link ("Simulated links", below); field evidence stays open.

### Quantized motion (#434 stage 4, wave 16)

The encoded Snapshot now writes fighter positions and shot trace points to
the millimetre and fighter yaw and pitch to 1e-4 rad
([protocol](protocol.md#quantized-motion); owner
`server/src/protocol/quantize.rs`). Only the wire rounds: the struct the
tick builds keeps the exact floats, so in-process readers of `snapshot()`
(campaign controllers, bots), lag compensation and every outcome are
unchanged, and the `Ack` that local prediction replays from is not rounded.
The rounding is IEEE multiply, round and divide on literal scales, so no
libm enters it, and its tests use literal inputs only.

It is no gameplay contract change. Every reader parses these fields as
numbers already; the Godot client and the Rust readers are untouched. What
a reader sees moves by at most half a step: 0.5 mm of position and 0.05
mrad of look. The client already read these as shortest `f32` text into a
64-bit float, so it never held the server's exact bits before either. Its
local prediction uses other fighters as contact bodies; a body 0.5 mm off
can change a replayed contact step by that much until the next `Ack`
corrects it.

Measured 2026-10-28 with the traffic generator against the `fragr-server`
binary, the same setup as the wave 15 table: Larak Lot, human fighters at
60 Hz plus spectators, no bots, 15 s held, seed 42. Three interleaved runs
per row on an AMD Ryzen 7 7840U shared with other sessions (load 4 to 8).
Before is `989d9b68` (main, gameplay 63), after is the wave 16 branch.
Bytes are the mean of three runs, encode times the median run.

```bash
cargo run -p fragr-playtest --release --locked -- --traffic --map 1 --traffic-fighters 48 --traffic-spectators 16 --traffic-bots 0 --traffic-hz 60 --traffic-seconds 15 --seed 42 --report .agents/traffic/after-48-16.json
```

| Connections (fighters + spectators) | Mean delta bytes before / after | KiB/s per client, all frames, before / after | Of which worlds | Server egress MiB/s | Tick encode p50 ms | Tick encode p99 ms | Server CPU cores |
|---|---|---|---|---|---|---|---|
| 6 (4 + 2) | 266 / 234 (-12 %) | 10.54 / 9.91 (-6 %) | 5.20 / 4.57 | 0.061 / 0.057 | 0.044 / 0.044 | 0.098 / 0.095 | 0.016 / 0.017 |
| 16 (12 + 4) | 695 / 593 (-15 %) | 19.70 / 17.63 (-11 %) | 13.57 / 11.53 | 0.304 / 0.273 | 0.068 / 0.078 | 0.136 / 0.136 | 0.030 / 0.034 |
| 64 (48 + 16) | 2,502 / 2,177 (-13 %) | 57.30 / 50.63 (-12 %) | 49.11 / 42.79 | 3.51 / 3.10 | 0.172 / 0.184 | 0.288 / 0.301 | 0.091 / 0.099 |

- **It pays, modestly.** A fighter entry's five motion fields (key text
  included, sampled from whole worlds at 48 fighters) fell from 63.3 to
  55.0 bytes, and a delta, which is mostly those fields, by 12 to 15
  percent. Per-client traffic at the 64-connection cap fell 12 percent,
  from 57.3 to 50.6 KiB/s; since wave 13's start that is 287 to 51 KiB/s.
- **Encode cost is inside the noise.** The rounding runs in the serializer
  once per tick; tick encode p50 moved by 0 to 0.012 ms and CPU by under a
  hundredth of a core, both within this host's run-to-run spread.
- **Every world still arrived.** Snapshot counts and whole worlds (one per
  connection) match. One after run at 16 connections read 1.1 percent fewer
  snapshots and recorded one tick over budget, a host stall during a
  shared-load spike; its other two runs and every other row had none.
- **What it does not do.** Traffic fighters move every tick, so the
  sub-step rule (a change under half a step is no change) did not show in
  these rows. Not rounded, because the measurement gave no reason:
  projectiles, grenades, rockets and vehicles (no row here carries many),
  and impact normals. `shot_results`, which a delta carries whole whenever
  anyone fired, was 2,349 bytes of a sampled 48-fighter world before and
  2,174 to 2,260 after: rounding its trace points cut it by 4 to 7 percent,
  so the rest of a shot result, not its floats, is most of that cost.

### Simulated links (#434, wave 16)

There is no root, `tc netem` or container on the measuring host, so the
harness carries its own link: `fragr_playtest::link`, a TCP relay in the
playtest process between real WebSocket clients and the real server. It
shapes the byte stream the way a TCP connection over such a link delivers
it: each direction serializes at the link's capacity, adds a one-way delay
and a seeded jitter draw while keeping order, holds the stream for a
retransmission when a chunk is "lost", holds everything during an outage,
and holds at most `queue_bytes` taken and undelivered. Past that it stops
reading; its own receive buffer toward the server is 16 KiB, so the
backlog moves into the server's bounded send buffer and the writer blocks,
as behind a real full window. It connects from the watcher's own loopback
source address, so admission is unchanged. Its tests check the schedule
(capacity, order under jitter and loss, outages) and the backpressure on a
live socket (`link::tests`).

This is a simulated link on loopback in one process: no packets, no
congestion control, no real radio. Loss is modelled as its effect on a TCP
reader (a 240 ms hole, Linux's 200 ms minimum timeout plus a round trip),
per chunk the relay reads, which on loopback is about one WebSocket frame.
It shows how the server's delivery rules respond to a shaped stream; it is
not field or two-machine evidence.

`--fanout-matrix --fanout-link` runs one row per link on the stress base:
Tripoint Works, 16 reflex fighters, 8 healthy watchers connected directly,
and 4 watchers behind the link, which read every frame as it arrives.
Measured 2026-10-28, release build, seed 42, 30 s per row, two runs on the
same AMD Ryzen 7 7840U (load 4 to 7, then 3 to 5); the table is the second
run. The first had a 5 s outage row where the second has 3.5 and 6 s (see
Outages); its other rows matched the second except where noted. A linked watcher's
worlds are about 14.1 KiB/s of text (116 kbit/s) on this roster.

```bash
cargo run -p fragr-playtest --release --locked -- --fanout-matrix --fanout-link --fanout-seconds 30 --report .agents/fanout/links.json
```

| Link (down capacity, one-way delay, extra) | Linked picture age p50 / p99 / max ms | Worlds read whole / as deltas | Link full (refused bytes), s per watcher | Replaced worlds / per-reader deltas | Linked watchers closed |
|---|---|---|---|---|---|
| relay only (1 Gbit, 0 ms) | 1.2 / 3 / 3 | 0 / 2,400 | 0 | 0 / 0 | none |
| broadband (20 Mbit, 20 ms, jitter 0 to 5 ms) | 24.5 / 28 / 30 | 4 / 2,396 | 0 | 0 / 0 | none |
| jitter (20 Mbit, 30 ms, jitter 0 to 60 ms) | 62.9 / 92 / 94 | 1 / 2,401 | 0 | 0 / 0 | none |
| loss (broadband, 5 % of chunks held 240 ms; 132 held) | 25.4 / 266 / 269 | 0 / 2,398 | 0 | 0 / 0 | none |
| outage 1.5 s every 6 s (broadband) | 25.2 / 1,456 / 1,506 | 4 / 2,388 | 0 | 0 / 0 | none |
| outage 3.5 s every 12 s (broadband) | 25.4 / 3,356 / 3,506 | 4 / 2,396 | 1.4 | 0 / 0 | none |
| outage 6 s every 15 s (broadband) | 25.4 / 5,806 / 6,005 | 4 / 1,556 | 2.1 | 0 / 0 | all 4 at 19 to 20 s, unanswered ping |
| thin 256 kbit, 40 ms, 16 KiB queue | 115 / 492 / 630 | 4 / 2,440 | 29.9 | 0 / 0 | none |
| thin 128 kbit, 40 ms, 16 KiB queue | 1,216 / 2,485 / 2,638 | 4 / 2,308 | 29.2 | 0 / 0 | none |
| thin 64 kbit, 40 ms, 16 KiB queue | 6,738 / 8,625 / 8,676 (run 1: 7,471 / 9,775 / 10,075) | 4 / 636 | 12.9 | 0 / 0 | all 4 at 5.9 s (run 1: 11.9 s), unanswered ping |

In every row the 8 healthy watchers read every world (no missing tick, no
disconnect), their tick-to-read p50 / p99 stayed 0.57 to 0.60 / 1.3 to
1.4 ms, no tick ran over budget (tick p99 0.72 to 0.85 ms), and no queue
overflowed. "Whole" worlds are each linked connection's first world when
it arrived inside the window.

- **Deltas hold on every link that carries the world.** Each linked
  watcher's first world was its only whole one; jitter, held chunks and
  outages up to 3.5 s delivered every later world late, in order, as a
  delta from the one before.
- **Per-reader deltas never triggered, and the numbers say why.** A world
  is replaced only when the writer blocks with a newer world queued, and
  the writer blocks only after the link's queue, the relay's receive
  buffer and the server's send buffer are all full (16, 32 and 128 KiB
  here, the last two as Linux doubles the asked size). At 14 KiB/s of
  worlds that is about 12 s of backlog, while the unanswered ping closes a
  reader 4 to 5 s behind. Even the 64 kbit link, which carries about half
  the world rate, was closed by the ping before its writer blocked. So on
  rosters up to 32 connections the per-reader path is a safety net, not a
  path a short link takes; it would trigger only for a reader whose deficit
  fills those buffers inside the ping bound, about 44 KiB/s, which is
  more than a whole 64-connection world stream (43 KiB/s, table above).
- **A link just under the world rate is not closed; its picture is late.**
  128 kbit carries the 116 kbit/s of worlds with a full 16 KiB queue: a
  picture 1.2 s old at the median and 2.6 s at worst, never closed in 30 s
  because the reader answers pings within the 4 s bound. Bufferbloat, not
  the server, sets that age; a deeper queue would make it older.
- **Outages.** 1.5 and 3.5 s outages delivered the held worlds late and in
  order; a 6 s outage closed every linked watcher by the unanswered ping,
  4 to 5 s into it (19 to 20 s into the window, the outage started at about
  15 s). Where in the ping period the link drops decides that extra second.
  An earlier version of this matrix used a 5 s outage every 12 s: in its
  run the first outage (about 12 to 17 s) closed nobody and the second
  (about 24 to 29 s) closed all four at 28 s, and a one-watcher probe of
  the same outage closed at exactly 4.0 s behind. 5 s is the edge, not a
  guarantee, which is why the rows use 3.5 and 6 s.
- **The frame-age close (2.5 s) never fired.** It needs the writer to take a
  frame late, which needs the writer to block, which none of these links
  caused before the ping did.

What these rows do not show: real congestion control (a real sender backs
off and the bytes wait in its send buffer, not on the wire), packet
reordering, asymmetric paths, Windows or macOS socket buffers, and anything
the Godot client does under these links (the watchers here are Rust
readers). Two machines and a real link remain the field evidence.

### Lag compensation (#434 stage 5)

Gameplay 62 lets a human Action carry `view_tick`, the tick its client draws
other fighters at, and rewinds that human's hitscan shots by up to 200 ms
(contract: [protocol](protocol.md#lag-compensation-capability-62); owner:
`server/src/sim/rewind.rs`).

**How far behind a client sees.** The client draws remote fighters two ticks
(100 ms) behind the newest snapshot arrival (`RemotePresentation`). Its
Action then travels to the server and waits for the next tick. Snapshot and
Action each cross half the round trip, so the view trails the tick that
fires by the interpolation buffer plus the **whole** round trip plus up to a
tick: 100 to 150 ms at 0 ms RTT, 250 to 300 ms at 150 ms RTT. A strafer at
7 m/s moves 0.9 m in the 125 ms a loopback client still trails, more than the
0.5 m body radius.

**Method.** `fragr-playtest --rewind-matrix` is deterministic and in process
(no sockets, no wall clock). Each trial: a still human with a Rail (first
shot, no bloom) 16 m from an agent strafing on a seeded schedule (runs of 3
to 12 ticks, reversals and stops) on Arena Duel. The client is modelled
exactly as `RemotePresentation` draws: the strafer interpolated at the
view time, aimed at the chest, line checked open. The Action arrives at a
seeded phase inside the tick before it fires. "On target on the client" is
every trial (the lane is open); a server miss is a shot the player saw land.
Fixed one-way delays only: no jitter, loss or TCP retransmission, so these
rates are a floor on real misses, not a field measurement.

```bash
cargo run -p fragr-playtest --release --locked -- --rewind-matrix --seed 42 --report .agents/rewind/after.json
```

Measured 2026-10-28, seed 42, 1000 trials per row. Before is the rewind-off
path (no `view_tick`), which is the unchanged pre-62 resolution: at 400
trials it reproduced the numbers from main (`d705d1c9`) exactly.

| RTT | View lag mean / max | Drawn vs present offset mean / p95 | Server misses of client-on-target shots, before | After (200 ms bound) |
|---|---|---|---|---|
| 0 ms | 125 / 150 ms | 0.48 / 0.87 m | 60.4 % (396 of 1000 hit) | 0.0 % |
| 50 ms | 175 / 200 ms | 0.64 / 1.16 m | 64.3 % | 0.0 % |
| 100 ms | 225 / 250 ms | 0.81 / 1.46 m | 64.9 % | 0.0 % (clamped; residual under 50 ms) |
| 150 ms | 275 / 300 ms | 0.95 / 1.75 m | 68.8 % | 15.8 % (clamped by 75 ms on average) |

**Choosing the bound.** The same matrix with other clamps, after rows only:

| Bound | 0 ms | 50 ms | 100 ms | 150 ms |
|---|---|---|---|---|
| 150 ms (3 ticks) | 0.0 % | 0.0 % | 14.9 % | 58.8 % |
| 200 ms (4 ticks, shipped) | 0.0 % | 0.0 % | 0.0 % | 15.8 % |
| 250 ms (5 ticks) | 0.0 % | 0.0 % | 0.0 % | 0.0 % |

200 ms is the planned bound (buttery-controls, #434) and the measurement
keeps it: it covers LAN and same-region play in full in this model and lets
a victim be struck at most 200 ms after reaching cover. 250 ms would also
cover 150 ms RTT, but widening what a victim can be shot through is a fairness
decision this lane does not take. A 150 ms bound would not even cover 100 ms
RTT, because fragr's view trails by the whole round trip plus the buffer.

**Cost at the 64-connection cap.** History: 64 fighters x 5 ticks x 40-byte
volumes = 12,800 bytes, reused in place every tick (asserted in
`rewind::tests`). Release microbench (`rewind_cost_at_64_fighters`, ignored
test, two runs): recording 64 bodies 211 to 213 ns per tick; one body
lookup 74 to 75 ns; one fully rewound shot against 63 targets about 4.7 us.
Offline CPU benchmark, `--bench 64 --bench-ticks 2400 --seed 42` (Larak Lot,
64 rule bots, so recording runs every tick but no shot rewinds), three
interleaved runs each on an AMD Ryzen 7 7840U shared with other sessions
(load 4 to 5):

| Build | Tick mean ms | p50 ms | p99 ms | Trace hash |
|---|---|---|---|---|
| main `d705d1c9` | 0.949 / 0.922 / 0.949 | 0.508 / 0.492 / 0.508 | 1.97 / 1.97 / 2.03 | `baf7a41a8f97` |
| lag compensation | 0.963 / 0.960 / 0.977 | 0.524 / 0.524 / 0.557 | 2.03 / 2.03 / 2.10 | `baf7a41a8f97` |

The identical trace hash shows bot play is unchanged. The tick mean rose
by 0.01 to 0.04 ms (1 to 4 %), more than the 0.2 us the recording itself
measures; the remainder is not attributed and sits inside this host's
run-to-run spread. Either way it is under 0.1 % of the 50 ms budget.

**Clients.** The Godot client sends its presentation clock's render tick
with every Action. Rule bots read the present server state and are never
rewound; neither are agents (the MCP schema refuses `view_tick`, and the
server ignores one from an agent socket), because `look_at` aims at the
present. The brain and the playtest harness agents send none. The traffic
generator's synthetic humans send none, so their shots stay unrewound.

The counters (`GameState::rewind_stats`: `accepted`, `refused`, `rewinds`,
`clamped` and `discontinuities`) are published on `GET /status` as `ops.rewind` since
wave 15 (`ops` in [protocol](protocol.md)), so a host can read the clamped
share of a real night.

**Under modelled jitter and loss (wave 16).** `--rewind-jitter` reruns
every row on modelled links: each snapshot and the Action draw an extra
one-way delay from 0 to the jitter, a lost message (2 in 100 in the last
link) holds the stream 250 ms for its retransmission (Linux's 200 ms
minimum timeout plus a round trip), and the stream stays ordered. The
client's clock is no longer a closed form: the model runs
`RemotePresentation.sample` at every 60 Hz frame over the snapshots that
have arrived, so its render tick follows the earliest arrival offset of the
last 32 snapshots, never runs backwards, and holds at the newest snapshot
when the next is late (starved). The view tick sent is that render tick.
With no jitter the model lands on the fixed rows' closed form
(`the_client_timeline_model_matches_the_fixed_delay_view`), and the fixed
rows above reproduce exactly. Still a model in process, no sockets.

```bash
cargo run -p fragr-playtest --release --locked -- --rewind-matrix --rewind-jitter --seed 42 --report .agents/rewind/jitter.json
```

Measured 2026-10-28, seed 42, 1000 trials per row; deterministic. Misses
are server misses of shots the client saw land; "beyond 200 ms" is the
share of trials whose view lag exceeded the rewind bound.

| Link (extra one-way delay) | RTT | View lag mean / max ms | Starved | Beyond 200 ms | Miss before (no `view_tick`) | Miss after |
|---|---|---|---|---|---|---|
| none | 0 / 50 / 100 / 150 ms | 125 / 150 to 275 / 300 | 0 % | 0, 0, 100, 100 % | 60.4, 64.3, 64.9, 68.8 % | 0.0, 0.0, 0.0, 15.8 % |
| 0 to 20 ms | 0 / 50 / 100 / 150 ms | 136 / 170 to 286 / 319 | 0 % | 0, 21, 100, 100 % | 62.8, 64.7, 65.9, 67.6 % | 0.0, 0.0, 0.0, 29.0 % |
| 0 to 50 ms | 0 / 50 / 100 / 150 ms | 151 / 199 to 301 / 352 | 0 % | 0, 51, 100, 100 % | 63.5, 64.2, 67.5, 68.6 % | 0.0, 0.0, 3.2, 43.5 % |
| 0 to 100 ms | 0 / 50 / 100 / 150 ms | 183 / 256 to 333 / 405 | 19 to 22 % | 30, 79, 100, 100 % | 65.7, 67.1, 68.2, 70.5 % | 0.0, 3.5, 27.7, 56.6 % |
| 0 to 20 ms, 2 % loss | 0 / 50 / 100 / 150 ms | 150 / 550 to 301 / 700 | 8 to 9 % | 7, 29, 100, 100 % | 63.2, 65.3, 66.3, 68.7 % | 3.0, 4.3, 5.0, 32.3 % |

- **Rewind follows the view the client drew, starved or not.** A starved
  timeline holds the newest snapshot and reports that tick, so the server
  rewinds to what was drawn; inside the bound every such shot landed.
- **Jitter spends the bound.** The view lag grows by about half the jitter
  (the Action's own delay; the clock tracks the earliest snapshot, so
  snapshot jitter adds lag only when it starves the 100 ms buffer). At
  50 ms RTT, rewind still lands every drawn hit up to 50 ms of jitter and
  96.5 percent at 100 ms; at 100 ms RTT, 50 ms of jitter already costs 3.2
  percent and 100 ms costs 27.7.
- **A lost message is a miss when it pushes the lag past the bound.** 2
  percent loss costs 3 to 5 percent of drawn hits at 0 to 100 ms RTT. A
  held snapshot starves the view, which the client reports; a held Action
  adds 250 ms after the view was sampled, which no client clock can
  report. The matrix does not split the two.
- Before-rewind misses barely move with jitter (60 to 70 percent in every
  row): without `view_tick` the server was already wrong by the whole lag.

What stays open for #434 stage 5:

1. **Field evidence.** Two machines, real jitter and loss: compare client
   hit-confirm against server results through the existing stutter traces.
   The matrix models fixed delays and, since wave 16, uniform jitter and
   retransmission stalls; real links have neither shape exactly.
2. **Projectiles stay unrewound** by design: a rocket or grenade is a visible
   object the victim can dodge in server time, and rewinding its collisions
   would hit a target that already dodged what it saw. Campaign actors are
   not on the delayed timeline (their own clock), so they are not rewound.
3. **Spectator and agent views** are out of scope: neither shoots through a
   delayed timeline.


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
