# Bounded spectator delivery

Status: **in flight**.

## Goal

Keep one slow or stopped spectator from growing server memory or delaying the
shared match. Preserve ordered Welcome, MapInfo, mission state, and snapshots
for healthy fighters and watchers. Measure delivery cost before increasing the
connection cap or claiming a larger public audience.

## Scope and seams

Use the existing WebSocket JSON transport and server-owned session. The
per-client outbound queue and writer lifecycle belong in `server/src/net.rs`;
fan-out and initial geometry ordering belong in `server/src/session.rs`.
`tools/playtest` owns the live measurement harness. Keep `ClientSession`
uninitialized until its MapInfo has entered that client's queue. Keep the
existing pawn detach and ten-second resume behavior on a transport drop; an
explicit `leave` still removes the pawn immediately.

Bound each outbound queue, deliver without awaiting a slow receiver inside
the simulation fan-out, and close a connection when that queue fills or its
socket writer stops making progress. A writer failure must wake its reader so
normal disconnect cleanup runs. Do not silently discard arbitrary messages
from a live client. Keep the current cap, WebSocket protocol, admission rules,
and one authoritative match. This increment adds no account system, cloud
apply, UDP path, browser client, or chat.

No wire fields change. Any new measurement field in a developer report needs
its schema and README updated with a test. Reuse existing crates and tracing.

## Verification

- Test Welcome and MapInfo ordering with a full queue before initialization.
  A rejected initial MapInfo must never enable broadcasts.
- Test a stalled spectator while an active fighter and a healthy spectator
  continue receiving ordered snapshots. Confirm that the slow connection
  releases its slot and that a disconnected fighter follows the existing
  detach and resume policy.
- Bound a writer that stops accepting bytes. Exercise both queue overflow and
  writer failure cleanup without sleeping through an uncontrolled timeout.
- Add a reproducible local matrix for 4 and 16 fighters with 1, 8, and 16
  spectators on a small and a large map at fixed seed 42. Record session tick
  and fan-out p50/p99 separately, serialized bytes per second, queue high
  water mark, watcher snapshot age and gaps, disconnects, and actual samples.
  The 16 plus 16 case must respect the current per-address and global caps;
  document a different local arrangement if the cap prevents admission.
- Run the full workspace and Godot checks, mixed map roster, and a live
  first-person watch. Inspect that a healthy watcher follows the same pawn
  through the stressed session. Put results here before changing any cap.

## Success and limits

The slow reader disconnects within a bounded interval and cannot grow an
outbound queue without limit. Healthy clients retain ordered delivery and
normal match progress. The matrix makes simulation cost distinct from
serialization and client fan-out. Any claim about public-server scale waits
for a realistic network and hardware test; local CPU results do not prove it.

Spend: $0. No paid calls, assets, or cloud apply.

## Evidence

Research review of the current path found an unbounded per-client channel in
`net.rs`, a writer without a send deadline, and a reader that does not wake
when the writer fails. `session.rs` clones broadcasts into every initialized
FIFO. The existing benchmark measures simulation and one-copy serialization,
not delivery to each watcher. These observations define the baseline to
measure and correct; implementation results belong here.

The [Tokio bounded sender documentation](https://docs.rs/tokio/latest/tokio/sync/mpsc/struct.Sender.html)
checked 2026-09-23 confirms `try_send` returns immediately with distinct full
and closed errors. The [watch receiver documentation](https://docs.rs/tokio/latest/tokio/sync/watch/struct.Receiver.html)
confirms `changed` is cancellation safe for a reader shutdown signal. Keep the
repository's pinned crate unless a measured need justifies a version change.

Local baseline at `7f9070d` on Windows: `cargo test -p fragr-server --locked
--quiet` passed 394 server library tests (two ignored) plus integration tests.
This establishes behavior before the queue change; it is not a fan-out load
measurement.
