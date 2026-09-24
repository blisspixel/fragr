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
- [ ] A local soak of at least 60 minutes recorded below with commit and hardware.
- [ ] A twenty-four hour soak on a release candidate (not this PR).

## Measurements

Filled in from the recorded run.
