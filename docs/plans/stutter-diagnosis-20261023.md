# Stutter diagnosis slice, October 23 playtest

Status: implemented (local evidence recorded below), 2026-10-23. Branch
`wave1/stutter-diagnosis` from `e4cec37`. Issue
[#434](https://github.com/blisspixel/fragr/issues/434), second comment
("Concrete player stutter report"), plus the part of step 1 baseline
instrumentation that directly serves it. Windows evidence: **not run**.

## Goal

The October 23 Windows report says play feels "a bit stuttery" with no trace,
build, map, renderer or capture. Make one session able to say which of these
it was, from measurements rather than feel:

- a slow drawn frame, and what was busy behind it (script, network receive and
  Snapshot apply, renderer CPU or GPU, pipeline compilation);
- a server tick that ran late, over budget or skipped;
- a Snapshot that arrived late, and whether the server, the delivery or the
  client's own frame delayed it;
- a prediction correction or reset (and its reason);
- a remote pawn whose interpolation ran out of Snapshots;
- a camera mode change.

Then run it on Linux loopback, against both a client-launched host and a
separately started server, and record a measurement table with sample counts.

## Non-goals

No encode-once, AOI, deltas, lag compensation, transport, tick-rate or ECS
change. No gameplay default change (respawn delay, starting weapon, vsync or
frame cap). No HUD layout change; the only visible addition is a console verb.
No fix is claimed: this slice narrows hypotheses for the next one. No
two-machine, Windows or human-feel claim.

## Architecture impact

Existing seams, extended:

- **Server, `server/src/tick_trace.rs`** (new module) and `run.rs`: opt-in
  `--tick-trace PATH` or absolute `FRAGR_TICK_TRACE`. One NDJSON record per
  served tick carrying the Snapshot tick number, deadline lateness from the
  `tokio::time::Interval` deadline (checked against tokio 1.53.1 source:
  `tick()` returns the scheduled deadline and `Skip` keeps deadlines on period
  multiples, so skipped periods are exact), skipped periods, and simulation,
  byte-measurement, fan-out queuing and total handler microseconds. A writer
  thread owns the file behind a bounded queue; a full queue drops and counts
  instead of delaying the tick. An unwritable path fails the start before the
  listener binds. Off by default; one `Option` test per tick when off.
- **Client, `stutter_trace.gd`** (recorder) and **`stutter_report.gd`**
  (strict reader, join and attribution). Hooks are one boolean test when off:
  `PerformanceOverlay` now runs first in each frame and a child marker runs
  last, giving the whole `_process` span; while tracing it also enables the
  viewport's per-frame render CPU/GPU measurement and reads cumulative
  pipeline-compilation monitors. `net_client.gd` times each socket drain that
  delivered messages. `game_manager.gd` routes Snapshots through a timing
  wrapper, reads `LocalPrediction`'s own counters (no predictor change), notes
  camera mode and pose, and counts starved remote pawns via a new diagnostic
  `RemotePresentation.starved` flag. Console: `stutter start | mark <label> |
  stop [path] | status`; leaving the match saves an open recording.
- **Harness, `qa_stutter.gd`**: rendered scripted session (idle, steady walk
  and turn, first fire, reload, death and respawn, pause menu open/close, walk
  again), each phase a mark. Writes the client trace, joined `report.json`
  and `table.md`. On Linux each phase records load average and the main
  thread's CPU and run-queue wait shares from `/proc/self/task/<tid>/schedstat`.
  `FRAGR_STUTTER_REPORT_ONLY=1` rebuilds the report from saved files, for a
  player's `stutter stop` file plus a host's tick trace.

Verified engine facts before relying on them (Godot 4.7.2 binary, probed under
`.agents/apicheck/`): `PIPELINE_COMPILATIONS_*` monitors are cumulative (5 then
7 after a new material), so per-frame deltas are valid; `Performance.TIME_PROCESS`
refreshes about once a second and is unusable per frame, hence the markers;
`viewport_get_measured_render_time_cpu/gpu` update every frame; `JSON.stringify`
logs an engine error for NaN, so unknown camera samples are written as null.

## Protocol or API changes

None on the wire. New server CLI flag and environment variable (documented in
`docs/BENCHMARK.md` "Stutter diagnosis traces" and the AGENTS.md env list).
`ServerOptions` gains `tick_trace: Option<PathBuf>` (default `None`).

## Verification

| Command | Result |
|---|---|
| `cargo fmt --all -- --check` | pass |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | pass |
| `cargo test -p fragr-server --lib tick_trace` (10 unit, 2 live, 1 CLI) | pass |
| `cargo test --workspace --locked` at load average 50-70 | stopped at the first failing binary: server lib 1503 passed, 4 failed (three geometry runner 30 s deadlines and `four_readers_share_one_start`); later binaries did not run. Not a pass. |
| `cargo test --workspace --locked --no-fail-fast` at load average 17-27 | 53 of 55 test binaries pass; 3 tests fail, all timeouts: two geometry runner 30 s deadlines (server lib 1505 passed) and the adapter `scripted_bot_uses_raised_geometry_under_continuous_snapshots` (116 passed). Not a pass. |
| Reruns of every failing test alone or with `--test-threads=1` on this branch | all pass (the adapter test in 0.25 s, `four_readers` in 0.08 s, the three geometry tests serially); `four_readers` also passes on an untouched `origin/main` export. None of these paths reach the tick trace, which is off unless configured. Clean-host CI is the deciding run. |
| `test_stutter_trace.gd` headless, `--verbose` | PASS, clean log |
| `tools/godot_check.sh` (Godot 4.7.2, release server built) | **PASS** (all scripts parse, every `test_*.gd` harness including the new one) |
| `cargo llvm-cov` 90% floor, playtest matrix, soak | not run in this lane |
| Windows rendered reproduction, release-mode video review | **not run** (Linux host) |

The Godot harness covers: inert when off; first frame only starts the clock;
compile deltas; clamping; frame, Snapshot and event caps with counted drops;
malformed ticks and Acks counted; prediction observation (state change versus
reset of an active predictor, resynchronising after a cleared window); NaN-free
save and read-back; unwritable save path; every tick-trace reader refusal
(missing or late header, version, non-integer, negative, extra field,
non-increasing tick, record after footer, unknown record, bad footer); planted
causes for each attribution (compile, network apply, render, unattributed with
camera change tag; server skip, server stall, delivery, client frame, unknown
without a server trace); same-clock delivery join; phases; main-thread budget;
teleport exclusion; second-long frames without spikes; overlay and marker
wiring; console and manager error paths. Server tests cover header/tick/footer
order, a full queue that drops without blocking, write failure reporting,
unwritable path at create and at `run_server` start (before ready), env path
validation, skipped-period rounding, a live spectator whose every received
Snapshot tick has a trace record, and CLI conflicts.

## Measurements, 2026-10-23

Host: Linux 7.2.8 (Omarchy, Hyprland/Xwayland), AMD Ryzen 7 7840U, 16 threads,
60 GB, AMD Radeon 780M (RADV PHOENIX), Vulkan Forward+, Godot 4.7.2-stable,
release `fragr-server` from this branch. Window 1280x720 requested, tiled by the
compositor to 1090x1404; screen 59.93 Hz. Settings are the shipped defaults
(vsync off, no frame cap, quality Balanced) except windowed display, unless
noted. Arena Duel (map 1), team deathmatch (the host menu default), 4 rule
bots, seed 1. One human fighter played through the ordinary Action path.

**Contention caveat.** Five other lanes were compiling and testing on this
host. Load average was 50 to 76 on 16 threads for the first five runs and 27
to 30 for local-3. The client main thread spent **11 to 73 percent of each
phase runnable but waiting** on the run queue (schedstat; 27 to 40 percent in
local-3). These are measurements of the game on an oversubscribed CPU, not an
uncontended baseline. A bounded 20 minute wait for load below 6 did not
succeed, so an uncontended Linux baseline was **not obtained**.

Session totals (phases are in each run's `table.md`). Frame times in ms;
spikes are at least 1.5x and 4 ms over the median; hitches at least 50 ms.

| Run | Host | Settings | Duration | Frames p50 / p99 / max | Spikes / hitches | Spike causes (top) | Snapshots | Gap p99 / max | Gaps >75 ms (causes) | Corrections n, p99 / max m, visible | Pred. resets | Starved remote frames | Server ticks joined, late p99 / max, handler p99 / max, skipped, over budget | Main thread script / receive / Snapshot share | Max msgs per poll |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| local-1 | client-launched desktop host | defaults | 57.8 s | 3679: 10.7 / 87.0 / 348.6 | 937 / 110 | network apply 617, script 287, render 284 | 1156 | 130.0 / 237.8 | 55 (client frame 50, delivery 5) | 1039, 0.255 / 0.500, 312 | ack_lag 3, ack_timeout 1 | 16 | 1156, 9.9 / 47.3, 12.2 / 18.9, 0, 0 | 0.654 / 0.225 / 0.148 | 19 |
| local-2 | client-launched desktop host | defaults | 51.3 s | 3779: 9.8 / 59.6 / 812.2 | 925 / 52 | network apply 627, render 473, script 285 | 1024 | 103.5 / 194.4 | 31 (client frame 28, delivery 2, server skip 1, server stall 1) | 924, 0.250 / 0.500, 216 | ack_lag 1 | 13 | 1024, 9.7 / 83.4, 7.0 / 15.4, 1, 0 | 0.640 / 0.201 / 0.134 | 33 |
| join-1 | separate `fragr-server` process | defaults | 86.3 s | 5999: 10.7 / 62.3 / 480.4 | 1469 / 90 | network apply 1043, render 821, script 405 | 1725 | 101.6 / 207.7 | 50 (client frame 45, delivery 4, server stall 1) | 1672, 0.032 / 0.357, 10 | ack_lag 1, ack_timeout 1 | 15 | 1725, 6.4 / 35.6, 7.5 / 23.3, 0, 0 (no footer: server killed) | 0.650 / 0.204 / 0.137 | 16 |
| local-cap60 | client-launched desktop host | fps cap 60 | 84.3 s | 3913: 16.8 / 87.3 / 422.7 | 741 / 142 | network apply 600, render 460, script 135 | 1686 | 108.3 / 262.3 | 53 (client frame 53) | 1566, 0.250 / 0.500, 377 | contact_stale 1 | 19 | 1686, 6.9 / 24.9, 6.5 / 22.7, 0, 0 | 0.628 / 0.241 / 0.161 | 17 |
| local-3 | client-launched desktop host | defaults | 40.3 s | 3611: 8.5 / 44.6 / 225.0 | 874 / 25 | render 576, network apply 539, script 306 | 807 | 85.7 / 139.7 | 13 (client frame 11, server stall 2, delivery 1) | 743, 0.017 / 0.356, 7 | none | 2 | 807, 6.9 / 33.7, 7.1 / 42.3, 0, 0 | 0.594 / 0.150 / 0.101 | 8 |
| local-vsync (invalid) | client-launched desktop host | vsync on | 102.9 s | 101: 1001.5 / 1134.5 / 1413.2 | 0 / 0 | n/a | 2043 | 900.4 / 975.8 | 118 (client frame 118) | 5, 0.488 / 0.488, 5 | ack_timeout 93 | 31 | 2043, 10.4 / 32.2, 6.1 / 13.7, 0, 0 | 0.259 / 0.250 / 0.198 | 53 |

Per-Snapshot client handler p99 was 38 to 47 ms (max 109 to 121 ms) in the
heavily loaded runs and 23 ms (max 40 ms) in local-3. Same-clock delivery
(arrival minus server send, valid because both processes share one clock) had
p50 5.5 to 10 ms and p99 47 to 520 ms; the attribution places nearly all of
that tail on the client's own late poll.

Phase outcomes: every valid run reached a server-confirmed first shot. Death
and respawn happened in local-1, local-2, local-cap60 and local-3; join-1
stayed alive for the 60 s bound and is reported as "not reached". local-vsync
is retained as a failed comparison: frames arrived about once per second,
consistent with the compositor throttling vsync presentation of an unexposed
window on this desktop. It says nothing about the game's vsync path.

## Findings and narrowed hypotheses

1. **Server simulation is not the stall in any run.** Across 6,398 joined
   ticks in the five valid runs the handler p99 was 6.5 to 12.2 ms and the
   maximum 42.3 ms against a 50 ms budget, with zero over-budget ticks and one
   skipped period. Late Snapshots were attributed to the server in 5 of 202
   gaps.
2. **The client main thread is saturated and serializes Snapshot apply behind
   slow frames.** With the shipped defaults (vsync off, no cap) the main
   thread's CPU share plus run-queue wait share is about 0.96 to 1.0 in every
   phase: it is always runnable, so any CPU contention becomes frame-time
   variance. Socket drain (parse, validation and handlers) took 15 to 24
   percent of wall time; the Snapshot handler alone 10 to 16 percent. After a
   slow frame 8 to 33 messages were applied in one poll (85 to 201 polls with
   more than two). 187 of 202 late Snapshots were caused by the client's own
   frame, not the network. Less contention (local-3) gave fewer hitches (25
   against 52 to 142) and less bunching, so the magnitudes here are inflated
   by load; the ordering of stages is the finding. Hypothesis for the next
   slice: per-stage cost inside `_on_snapshot_received` and its share at an
   uncontended baseline; whether a frame cap or bounded per-frame apply
   reduces bunching.
3. **Prediction can disagree by whole ticks of travel during sustained body
   contact.** In three of the four local runs that walked into opponents until
   death, 210 to 371 same-tick corrections exceeded 0.05 m, the modal error was
   exactly 0.25 m and the maximum 0.50 m: one and two 50 ms ticks at the
   5.0 m/s `TOP_SPEED`. They were sustained over many seconds of the approach
   rather than clustered at death. The fourth (local-3) died after 14 s with
   one, and the join run that never died had 10. This is consistent with
   prediction treating other bodies as static at their last received
   positions while the server resolves against moved bodies, but the trace
   does not yet record contact distance or sample age, so the cause is **not
   established** and may depend on how long contact lasts. Next: record
   nearest-body distance and contact sample age with each correction, then
   compare against a stationary and a moving opponent.
4. **Remote stepping was rare here**: 2 to 19 starved remote frames per valid
   run. Camera mode changes (3 per session with a death) coincided with at
   most two spikes. Pipeline compilation caused at most 4 spikes per session.
5. **Product defect found while reproducing (not fixed here):** hosting plain
   free-for-all from the desktop menu fails. `fragr-server --desktop-host
   --mode ffa ...` with no mutator exits with "desktop host requires a match
   configuration", because plain rules yield no `MatchConfig`
   (`main.rs` `match_config`) and `local.rs` `validate_arena_options` requires
   one. TDM, the menu default, works. Needs its own issue.

No regression target is set: the issue asks for one only after an
uncontended baseline, which this host could not provide.

## Open questions for Nick

- Whether the Windows reporter used defaults (vsync off, uncapped). The data
  here shows the default loop is always runnable; a default frame cap or vsync
  is a product decision and is **not** changed.
- Whether the reporter hosted (desktop host on the same machine) or joined
  another machine; the slice supports both.
- The commit trailer requested by the workflow conflicts with the AGENTS.md
  attribution lock; commits follow AGENTS.md.

## Reproduce

Linux or Windows Git Bash, from the repository root, after
`cargo build -p fragr-server --release --locked`:

```bash
# Client-launched host (as Host a match); the host inherits the trace path.
FRAGR_QA_DIR=$PWD/.agents/stutter/local FRAGR_TICK_TRACE=$PWD/.agents/stutter/local/server-ticks.ndjson \
  "$GODOT_BIN" --path client --script res://scripts/qa_stutter.gd
# Separate server process.
target/release/fragr-server --bind 127.0.0.1:6801 --mode tdm --map 1 --bots 4 --tick-trace $PWD/.agents/stutter/join/server-ticks.ndjson &
FRAGR_STUTTER_HOST=join FRAGR_SERVER=127.0.0.1:6801 FRAGR_QA_DIR=$PWD/.agents/stutter/join \
  FRAGR_TICK_TRACE=$PWD/.agents/stutter/join/server-ticks.ndjson "$GODOT_BIN" --path client --script res://scripts/qa_stutter.gd
```

For a player: in a match, open the console and type `stutter start`, play the
moment that stutters (`stutter mark walking`, `stutter mark died` as it
happens), then `stutter stop`; the console prints the saved path. A host adds
`--tick-trace` (or sets `FRAGR_TICK_TRACE` before launching the client).
Copy the client file to `client-trace.json` in a directory and run the
harness with `FRAGR_STUTTER_REPORT_ONLY=1`.

Raw evidence (ignored): `.agents/stutter/{local-1,local-2,local-3,join-1,local-cap60,local-vsync}/`
with `client-trace.json`, `server-ticks.ndjson`, `report.json`, `table.md`
and logs.

## Success criteria and status

- Correlate frame, server tick, Snapshot, prediction and camera signals from
  one session: **met** (client and server traces join on Snapshot tick; 8,441
  ticks joined across six runs).
- Opt-in, negligible when off: **met by construction** (one boolean or
  `Option` test per hook; render timing enabled only while recording). Not
  separately benchmarked.
- Run on Linux loopback against a launched host and a separate server, with a
  table and sample counts: **met, under heavy contention** (stated above).
- Reproducible trace or bounded "not reproduced": **reproduced on Linux under
  CPU contention**; Windows **not run**; uncontended baseline **not obtained**.
- Causally supported fix: **not claimed**; three narrowed hypotheses above.

## Independent review, 2026-10-23

A second reviewer read the whole diff against `origin/main` (unchanged since
`e4cec37`), and the plan above. Lane scope holds: no encode-once, AOI, delta,
lag-compensation, transport or HUD layout change, and nothing on the wire.
Fixes applied in a follow-up commit:

- `a_full_queue_drops_and_counts_instead_of_blocking_the_tick` accepted 47 to
  49 drops. That range depended on how many records the writer thread drained
  before it parked, so under load it could fail. The test now waits until the
  writer is parked in its first write and asserts exactly 48 drops. It passed
  30 repeated runs at load average about 18.
- `StutterReport` scanned every poll and event for each slow frame, and every
  frame for each late Snapshot. On a capped 200,000-frame trace under
  contention, that cost would have stalled `stutter stop` and the save made on
  leaving a match. Those lookups now binary-search the time-ordered arrays.
  Poll times are now validated as never going back, which the search relies on
  and which has a new refusal case in `test_stutter_trace.gd`.
- `docs/BENCHMARK.md` said the flag "conflicts with modes that run no tick
  loop". `--local-mission` does run one; it reads only `FRAGR_TICK_TRACE`. The
  doc now names each conflict and says that every host process the client
  starts truncates the same file.

Reviewer verification (Linux, load average 17-19):

| Command | Result |
|---|---|
| `cargo fmt --all -- --check` | pass |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | pass |
| `cargo test -p fragr-server --lib tick_trace` and `--bin fragr-server tick_trace` | pass (12 + 1) |
| Queue-drop test repeated 30 times | pass every time |
| `cargo build -p fragr-server --release --locked`, then `tools/godot_check.sh` (Godot 4.7.2) | **PASS**, including the `test_stutter_trace` and `test_performance_overlay` harnesses |
| `cargo test --workspace --locked` | not re-run by the reviewer; CI decides on the three timeouts listed above |
| Rendered `qa_stutter.gd` rerun | not re-run; the measurement table above is the implementer's evidence and was not reproduced in review |
| Windows rendered reproduction, release-mode video review | **not run** |

Status after review: diagnosis instrumentation implemented and tested; Linux
evidence recorded under contention only. The acceptance in #434 is **not
complete**: there is no uncontended baseline, no Windows trace, no causal fix
and no before/after comparison on the affected path.
