# Durable solo campaign run

**Status:** in flight, 2026-09-23. This is the run-document rung of the
[full build order](../ROADMAP.md#full-build-order-2026-09-22). M01 currently
owns a process-local run and three mission-start continues. Exiting the local
server abandons it; no disk run exists yet.

## Goal

Resume the same solo campaign run at the current mission's entry after closing
and reopening the game. Its ID, difficulty, content identity, starting and
remaining continue allowance, mission, and entry equipment survive. A load
does not spend or refill a continue. After M01 departure, retain the exit
equipment for M02 instead of treating M01 as the whole campaign.

## Scope and boundaries

- `server/src/mission/recovery.rs` owns run facts. A focused sibling module
  owns a bounded, versioned disk document and atomic replacement. The local
  child chooses its own platform user-data location. Clients and network
  requests never choose a filesystem path. Tests inject an isolated directory.
- The single authored-map loader provides a stable identity for the bundled
  mission. Reject an unsupported schema, rules revision, mission, content
  identity, difficulty, impossible allowance, invalid inventory, or trailing
  fields before advertising local readiness. Do not silently migrate a run.
- A committed continue must be durable before the server reports its lower
  allowance. Failed writes remain observable and cannot make a retry free.
  Save at the mission-entry boundary and at departure. Keep the prior valid
  document if a write fails. Use a same-directory temporary file, sync it,
  replace the destination atomically, and sync the parent where supported.
- Loading starts a fresh process clock and input sequence at the saved mission
  entry. It reconstructs enemies, pickups and gates from validated authored
  content. It never serializes live pawns, ticks, controller memory, a reload
  deadline, or mid-mission geometry.
- The menu exposes Continue Run only for a compatible save and starts a new
  run through an explicit choice. A completed M01 save stays retained while
  M02 is unbuilt, with a clear player-facing status. Starting a new run must
  not silently overwrite the prior one; keep a recoverable prior file.

This increment does not add an M02 map, a mid-mission checkpoint, cloud sync,
accounts, co-op saves, a new scripting runtime, or a player-selected save path.
It does not change arena or development-party sessions. Service-record history
remains a separate file and cannot refill a run.

## Contract and implementation order

1. Define and test the document and inventory projection, including content
   identity and exact allowance invariants. Use existing `serde_json`, `sha2`,
   `uuid` and std. Inspect current crate APIs before any dependency change.
2. Add a local-only store with bounded read, atomic write, and fault tests.
   Distinguish missing, compatible, incompatible and corrupt files; never
   destroy a file merely because it could not be loaded.
3. Wire load and save through local server startup, accepted continue and
   departure. Keep the wire action channel and `CampaignRunState` authoritative.
   If the bootstrap contract changes, update both Rust and Godot validators,
   `docs/protocol.md`, and adapter documentation in the same change.
4. Add menu resume/new-run presentation and local launch tests. Run a real
   stop/restart smoke after a spent continue and another after M01 departure.

## Verification and acceptance

- Round-trip the M01 entry and exit loadouts. Reject malformed, oversized,
  mismatched, future-version and impossible-allowance documents. Prove a
  failed replacement preserves the prior valid save.
- Real local-process restart keeps the run ID and reduced allowance, resets
  the mission at entry, and does not duplicate completed outcomes. A second
  restart agrees. New run and incompatible-save choices are explicit.
- Existing continue, admission, M01 route, Godot, six-map roster and full CI
  gates pass. Inspect the affected menu and campaign captures through the
  published QA tour. Record exact commands, results and remaining limits here.

No paid calls or infrastructure apply are needed. Human acceptance remains
near 1.0; these automated checks establish durability, not player clarity.
