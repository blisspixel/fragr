# Plan: server observability and soak harness

**Status:** in flight, 2026-09-24.
**Branch:** `feat/observability-soak`
**Spend:** $0. Local processes only. No paid model, asset, or cloud call.

## Goal

Phase 2.8 of [`../ROADMAP.md`](../ROADMAP.md) ("Tick time histogram, per-client
bandwidth, crash-free uptime, and a health check") and the tooling behind the
1.0 bar ("a twenty-four hour soak with no crash, proven by the status JSON at
start and end"). This plan does not claim that soak. It builds the status
fields and the harness, and records one local run of at least an hour.

## Non-goals

- A metrics stack or a Prometheus endpoint. Nothing scrapes one yet.
- Server-side memory figures. `unsafe_code` is forbidden, so the server cannot
  call the Windows process API; the soak harness samples the child's resident
  set from outside with OS tools instead, and says so when it cannot.
- Internet, TLS, or remote-network evidence. Everything here is loopback.
- A twenty-four hour result. The command exists; the run belongs to a release.

## Architecture impact

- **Histogram.** `hdrhistogram` was the pre-approved crate. Checked on
  crates.io 2026-09-24: 7.6.0, MIT or Apache-2.0 (both allowed by `deny.toml`),
  Rust 1.88. It is not added. `server/src/bench.rs` already owns a bounded
  log-linear `Histogram` (1025 buckets, upper-bucket error under 6.25 percent)
  with its own tests; this plan adds `merge` and a p95 to it and reuses it. One
  fewer dependency, one percentile definition for the bench, the log line and
  `/status`.
- **`server/src/metrics.rs`** (new) owns the operator view: process start and
  uptime, build identity, a sixty second ring of six ten second tick
  histograms plus a lifetime one, outbound queue overflows, per-connection
  and total traffic counters, and the health verdict. It is the only place
  that turns those into `/status` fields.
- **`server/src/net.rs`** counts text payload bytes and messages per session:
  outbound in the session writer (welcome included), inbound in the reader
  (every data frame, before the inbound budget). Counters are atomics on a
  per-connection `ClientTraffic` held by `ClientSession`, with process totals
  that survive a disconnect. The role is recorded at hello. `/status?clients=1`
  adds an anonymous per-connection list; the plain `/status` stays small.
- **`server/src/run.rs`** times the whole tick handler (expiry, sim, run save,
  broadcast and unicast enqueue) into the ring, feeds queue overflows, and
  refreshes the operator block once a second. The `STATUS` log line is
  unchanged. A change of health is logged once, at warn when it degrades.
- **`tools/playtest`** gains `--soak`: it starts the real `fragr-server`
  binary as a child with rule bots, connects N reflex agents and M spectators
  over WebSocket, samples `GET /status?clients=1` and the child's resident set
  on an interval into NDJSON under `.agents/soak/`, stops the child by its own
  handle (never by name or port), and checks the result.

## Protocol and API changes

`GET /status` keeps `schema_version` 2 and every existing field, so the
v0.37.0 multiplayer page (which accepts exactly schema 2 and reads `kind`,
`map`, `fighters` and `connections`) is unchanged. New fields are additive:
`health` (`{status, reasons}`) and `ops` (its own `ops.version`, 1). The
plain body stays far below the client's 4096 byte limit; a test pins it
under 2048 bytes. Full schema in [`../protocol.md`](../protocol.md).

Health is `degraded` when any of these hold, otherwise `ok`:

| Reason | Threshold |
|---|---|
| `tick_p99_over_budget` | p99 tick handler time over the last 60 s is at or above 50 ms, with at least 100 ticks in the window |
| `tick_rate_low` | the loop ran under 19 ticks per second (95 percent of 20) over a window of at least 30 s: the scheduler skipped ticks, which tick handler time alone does not show |
| `outbound_drops` | at least one outbound queue overflow (a slow reader dropped) in the last 60 s |
| `stale` | the served snapshot is more than 2 s older than the process clock (the tick loop stopped refreshing it) |

## Verification

- Unit tests: histogram merge and p95, the ring window rotation and expiry,
  health thresholds (each reason and the minimum sample rule), status JSON
  schema and size, detail query parsing, traffic counters and rates.
- Integration: a live loopback server answers `/status` with `ops`, counts
  a client's bytes in both directions, and adds the client list only on
  `?clients=1`.
- Soak: verdict tests for crash, stall, RSS growth, p99, connection drift and
  overflows; a short in-process soak exercising the sampler end to end.
- Client: `test_frontend.gd` feeds a schema 2 body with `health` and `ops`.
- Full AGENTS.md list, plus the playtest smoke and roster.

## Success criteria

- [ ] `/status` reports tick p50/p95/p99/max and over-budget counts (window and
      lifetime), per-client and total traffic, connections by role, uptime,
      start time, build identity and health, documented in `docs/protocol.md`.
- [ ] `fragr-playtest --soak` writes NDJSON samples and fails on a crash, a
      stall, RSS growth, p99 over budget, connection drift or queue drops.
- [x] A local soak of at least 60 minutes recorded below with commit and hardware (two runs; the second failed its own tick rate rule under host load).
- [ ] A twenty-four hour soak on a release candidate (not this PR).

## Measurements

Host: Windows 11 Pro, AMD Ryzen 7 7840U (8 cores, 16 threads), 62 GB RAM,
rustc 1.97.1, release builds. The machine was shared with other worktrees'
builds and a Godot check run during both soaks; that load is part of the
result, not excluded from it. Roster for both: 4 rule bots, 4 reflex agents
and 2 spectators on loopback, `--soak-map-rotate` (all six arena maps),
seed 1, one sample a minute. Evidence NDJSON stays under `.agents/soak/`.

```bash
target/release/fragr-playtest --soak --soak-seconds 3900 --soak-sample-seconds 60 --soak-bots 4 --agents 4 --soak-spectators 2 --soak-map-rotate --assert --soak-log .agents/soak/final-65min.ndjson
```

| | Run A | Run B |
|---|---|---|
| Server commit (`ops.build.commit`) | `1d5933b` | `d1c2a69` (adds `tick_rate_low`) |
| Measured span | 4200 s (70 min), 71 samples | 3900 s (65 min), 66 samples |
| Server exit during run | none | none |
| Ticks start to end | 34 to 82866 (19.72 Hz) | 33 to 77597 (19.89 Hz) |
| Slowest minute | 16.06 Hz; 6 of 70 minutes under 19 Hz | 18.07 Hz; 2 of 65 minutes under 19 Hz |
| Window p50/p95/p99 at start | 0.17 / 0.79 / 0.83 ms (21 ticks) | 0.18 / 0.22 / 1.14 ms (20 ticks) |
| Window p50/p95/p99 at end | 0.24 / 0.85 / 1.38 ms | 0.15 / 0.25 / 0.43 ms |
| Lifetime p50/p95/p99, max | 0.23 / 0.79 / 1.57 ms, 139.0 ms | 0.20 / 0.51 / 1.18 ms, 114.7 ms |
| Ticks at or over 50 ms | 6 of 82845 | 1 of 77577 |
| Outbound bytes per client per second | 47554 | 48091 |
| Inbound bytes per client per second | 2348 | 2385 |
| Queue overflows | 0 | 0 |
| Connections (agents, spectators) | 4, 2 at every sample | 4, 2 at every sample |
| Resident set start, end, max | 38.2, 33.6, 40.7 MiB | 37.9, 39.7, 40.9 MiB |
| Health at start and end | ok, ok | ok, ok |
| Degraded samples | 0 (rule not yet built) | 2 (`tick_rate_low`, 18.8 and 18.1 Hz) |
| Harness verdict | pass | **fail** (the two degraded samples) |

Run B end status (abridged): `schema_version` 2, map Compliance Yard, round
44, tick 77597, 8 fighters, 6 connections, health ok, uptime 3902 s,
1 125 648 264 bytes out and 55 817 069 in since start.

Reading: tick handler time never approached the budget (p99 under 1.6 ms
over both runs), memory was flat within about 3 MiB, and no connection,
queue or process failed. What Run A showed, and Run B's new rule then
flagged, is the scheduler skipping ticks on a loaded desktop: minutes at 16
to 18 Hz with a fast handler. That is a host-contention signal, not a tick
cost; a dedicated host has to show it clean. Run B is therefore recorded as a
failed soak by its own rule, and neither run is the 1.0 soak.

Outbound per client is about 47 KB/s of JSON text on this roster, before
WebSocket framing and TCP. That matches the fanout matrix order of magnitude
and is the number the snapshot efficiency work should move.

CI: the `soak` job on PR #244 passed 120 s with 9 samples, 20.00 Hz, window
p99 0.38 ms at the end, lifetime max 0.83 ms, 46228 out and 2349 in bytes per
client per second, resident set 37.2 to 37.9 MiB.

## Gaps

- No twenty-four hour run, and no run on an idle or dedicated host.
- Loopback only. No Internet path, TLS, packet loss or remote clients.
- No human clients in the roster; humans count only through role tests.
- Windows memory is the working set from `tasklist`; Linux uses VmRSS.
