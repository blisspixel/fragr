# Latest pending world delivery

Status: **implemented**, 2026-10-07. Local transport work with bounded queue
tests and a measured 64-client loopback delivery sample. No release or WAN
capacity claim. Parent: [server excellence](server-excellence.md).

## Goal

Keep at most one replaceable unsent world snapshot per connection on the
existing WebSocket transport. A slow reader must not delay the simulation,
lose resolved combat facts, or observe a new world before its geometry.

## Design and boundaries

Use the existing per-client delivery seam in `server/src/net.rs` and
`server/src/session.rs`. The bounded reliable FIFO retains welcome/geometry,
events, round results, inventory, input acknowledgements and fact-bearing
snapshots. Snapshot shots and explosions are one-tick facts and must remain
reliable. Exact roster, scores, statistics and other discrete snapshot changes
also prevent replacement. Only a snapshot with unchanged discrete facts may
occupy the single replaceable slot. Replacing it moves the new world to its
correct place after intervening reliable messages. A queued geometry or mission
change freezes the older world before that boundary. Writes retain their
existing timeout. The total queue, including its replaceable world, stays at
64 messages. The local measurement report counts replaced worlds separately
from reliable overflow; the status wire schema is unchanged.

There is no gameplay or message-shape change, delta encoding, interest filter,
tick-rate change, new dependency or paid service. An in-progress socket write
cannot be recalled. Fact-bearing snapshots remain bounded by the reliable
queue limit; heavy combat may exhaust it and disconnect a stalled reader.

## Verification

Before acceptance, deterministic queue tests must prove replacement under
sustained movement, exact shot/explosion and score retention, geometry ordering,
reliable ordering and overflow, receiver/sender shutdown, and isolated slow
client eviction. The existing stalled-sink timeout test must keep passing.
Run focused Rust tests with `--locked`, then the server checks required for
integration. Review races and drop behavior independently. Capacity and hit
alignment require separate measurements; this queue change cannot prove them.

## Spend and success

$0. No external calls or assets. Success is bounded pending world state with
reliable fact delivery and unchanged wire compatibility, backed by the tests
above. Record commands, results and remaining evidence here before handoff.

## Local evidence

- `cargo check --locked -p fragr-server --lib`: passed.
- `cargo test --locked -p fragr-server --lib net::outbound --no-fail-fast`: eleven
  tests passed, including actual active simulation movement, Sabotage clock and
  carrier movement, exact score/statistic transitions, exact shots/explosions
  before ACK, same-ID geometry barriers, full-queue replacement and refusal,
  sender-clone shutdown, receiver drop and wakeup behavior. Moving vehicles
  coalesce while HP, occupants, control lock and burn transitions remain exact.
- `cargo test --locked -p fragr-server --lib net:: --no-fail-fast`: 52 passed,
  including the ten queue tests, stalled writes, lifecycle and network abuse.
- Matching `session::session_tests` and `statistics::tests` checks: 27 and 22
  passed, including initial geometry ordering, isolated slow-client overflow
  and private record compatibility. This change is not merged or deployed.
- Independent source review found no correctness defect in queue indexing,
  FIFO barriers, cancellation/wakeup handling or sender/receiver shutdown. It
  called out conservative non-replacement of changing projectiles as a
  measurement limit rather than a delivery guarantee. Vehicle integration now
  explicitly separates replaceable movement and heat from discrete facts.
- An initial test compile ran out of local disk space. The disposable server
  development artifacts were cleaned through Cargo, test source restored, and
  the successful retry used `CARGO_INCREMENTAL=0`. No game data was removed.

The implementation preserves all shot and explosion snapshots and exact
discrete changes in the same 64-message FIFO. Consequently this is conservative
coalescing, not a promise that a congested combat stream stays current. Further
projectile and objective-state extensions must make an explicit replacement
decision in the exhaustive snapshot matcher. Reliable overflow and the existing
two-second send timeout still close stalled connections.

## Measurement commands

Build the release server and playtest tool with locked dependencies. For a
bounded first sample use `fragr-playtest --traffic --traffic-fighters 8
--traffic-spectators N --traffic-bots 8 --traffic-seconds 60 --traffic-hz 60
--map 1 --seed 1 --assert --report PATH`, setting `N` to 8, 24 and 56 for
16, 32 and 64 connections. These are sixteen fighters with changing spectator
loads, not 64-fighter evidence. Record the machine and release build beside
each report. `--fanout-matrix --fanout-seconds 10` additionally records separate
session/enqueue timing, queue high water, overflow and `replaced_worlds` in its
local server metrics. It currently stops at 32 connections. No population
measurement is claimed by this plan's unit tests.

## Final loopback sample

The final composed release passed `fragr-playtest --traffic
--traffic-fighters 64 --traffic-spectators 0 --traffic-bots 0
--traffic-seconds 60 --traffic-hz 60 --map 7 --seed 42 --assert --report PATH`
on 2026-10-07. All 64 human-role WebSocket clients remained connected, with
228,672 actions, 76,864 received fighter snapshots, zero disconnects, healthy
status and 11.0100 ms server p99 ticks. Aggregate outbound traffic was
26,125,306 bytes/s, about 24.91 MiB/s. The full
[native evidence](../evidence/native-island-quality-20261006.md) and
[structured receipt](../evidence/native-island-measurements-20261007.json)
retain commands, exact executable hashes and machine details.

These clients send fixed movement and fire without reload, pathfinding or
vehicle use. Human magazines may empty early; this is delivery evidence,
not sustained 64-fighter combat or 64-player spawn-quality evidence. The sample
does not introduce slow readers, measure replacement counts or prove WAN
latency or bandwidth capacity. Ordering and bounded eviction remain separately
verified by deterministic queue and socket tests.
