# Durable solo campaign run

**Status:** in flight, 2026-09-23. This is the run-document rung of the
[full build order](../ROADMAP.md#full-build-order-2026-09-22). M01 previously
owned only a process-local run and three mission-start continues. This branch
adds the local disk document and resume flow; integration and cross-platform
CI are pending.

## Goal

Resume the same solo campaign run at the current mission's entry after closing
and reopening the game. Its ID, difficulty, content identity, starting and
remaining continue allowance, mission, and entry equipment survive. A load
does not spend or refill a continue. After M01 departure, record M01 as the
completed mission and M02 as pending, with the exact exit equipment. This is
not a replayable M01 entry or a completed campaign.

## Scope and boundaries

- `server/src/mission/recovery.rs` owns run facts. A focused sibling module
  owns a bounded, versioned disk document and file replacement. The local
  child chooses its own platform user-data location. Clients and network
  requests never choose a filesystem path. Tests inject an isolated directory.
- The single authored-map loader provides a stable identity for the bundled
  mission. Reject an unsupported schema, rules revision, mission, content
  identity, difficulty, impossible allowance, invalid inventory, or trailing
  fields before advertising local readiness. Do not silently migrate a run.
- Persist the death decision before reporting `Continue` or `Failed`. A quit
  while a retry is pending must reopen that same decision rather than give a
  free mission-entry retry. A committed continue must be durable before the
  server reports its lower allowance. Extract prepare, persist, commit steps
  from the existing synchronous command path. Apply the same ordering to
  departure before its new state is broadcast. On a pre-rename write failure,
  preserve the prior valid file and do not publish the new state.
- Keep one process-level lock on a fixed file beside the run document for the
  entire local session. A second child must refuse to open the same run, not
  load and later overwrite its allowance. Use a unique, same-directory
  `create_new` temporary file, sync and close it before replacement, then
  sync the parent directory where supported. If replacement succeeds but a
  later sync fails, treat commit status as uncertain and reconcile from disk;
  do not claim that the old file was preserved.
- Loading starts a fresh process clock and input sequence at the saved mission
  entry. It reconstructs enemies, pickups and gates from validated authored
  content. It never serializes live pawns, ticks, controller memory, a reload
  deadline, or mid-mission geometry.
- The Rust local store exposes a read-only compatibility preview, with the
  same resolver and validator used at launch. Godot does not parse save JSON
  or decide its path. The menu exposes Continue Run only for a compatible
  save, starts a new run through an explicit launch mode, and distinguishes
  exit-to-menu from explicit abandonment. A completed M01 save stays retained
  while M02 is unbuilt, with a clear player-facing status. Starting a new run
  must not silently overwrite the prior one; keep a recoverable prior file.
- The campaign contract allows a human or free-agent protagonist. Current M01
  does not yet expose that body choice. Do not infer it from the network's
  human/agent control role or hard-code a fictional body in the save. Add the
  chosen playable identity when that player choice is implemented, with an
  explicit schema migration for older runs.

This increment does not add an M02 map, a mid-mission checkpoint, cloud sync,
accounts, co-op saves, a new scripting runtime, or a player-selected save path.
It does not change arena or development-party sessions. Service-record history
remains a separate file and cannot refill a run.

## Contract and implementation order

1. Define and test the document and inventory projection, including content
   identity and exact allowance invariants. Use existing `serde_json`, `sha2`,
   `uuid` and std. Inspect current crate APIs before any dependency change.
2. Add a local-only store with bounded read, one fixed lock, replacement and
   fault tests. Distinguish missing, compatible, incompatible and corrupt
   files; never destroy a file merely because it could not be loaded. Probe
   and launch use the same validation and platform path resolver.
3. Wire load and save through local server startup, death, accepted continue
   and departure. Hydrate both the allowance and derived attempt, and apply
   saved entry equipment after participant admission without old input or
   reload state. Keep the wire action channel and `CampaignRunState`
   authoritative.
   If the bootstrap contract changes, update both Rust and Godot validators,
   `docs/protocol.md`, and adapter documentation in the same change.
4. Add menu resume/new-run presentation and local launch tests. Run a real
   stop/restart smoke after a spent continue and another after M01 departure.

## Verification and acceptance

- Round-trip the M01 entry and exit loadouts. Represent M01-complete with M02
  pending as its own nonplayable state, retaining the same run ID and exact
  exit equipment. Reject malformed, oversized, mismatched, future-version
  and impossible-allowance documents. Prove a pre-rename failure preserves
  the prior valid save.
- Real local-process restart keeps the run ID and reduced allowance, resets
  the mission at entry, and does not duplicate completed outcomes. Crash or
  exit after death but before Continue preserves the pending choice; a second
  restart agrees. A concurrent second child is refused. New run,
  exit-to-menu, explicit abandonment and incompatible-save choices are
  distinct and tested.
- Existing continue, admission, M01 route, Godot, six-map roster and full CI
  gates pass. Inspect the affected menu and campaign captures through the
  published QA tour. Record exact commands, results and remaining limits here.

No paid calls or infrastructure apply are needed. Human acceptance remains
near 1.0; these automated checks establish durability, not player clarity.

## Design review, 2026-09-23

The current sim enters `Continue` at death without spending allowance. That
state needs a durable pending-death record. `Session` accepts Continue in one
synchronous mutation, while departure happens during a tick, so persistence
must be ordered before observable transition. Local menu exit currently sends
`leave`, which marks the in-memory run abandoned; a resumable disk run needs
a separate exit meaning. The attempt invariant derives from spent allowance,
not from the new process's tick. These are implementation gates, not claims
that the save exists. Rust's [`rename`](https://doc.rust-lang.org/std/fs/fn.rename.html),
[`sync_all`](https://doc.rust-lang.org/std/fs/struct.File.html#method.sync_all),
[`try_lock`](https://doc.rust-lang.org/std/fs/struct.File.html#method.try_lock),
and [`create_new`](https://doc.rust-lang.org/std/fs/struct.OpenOptions.html#method.create_new)
contracts were checked on 2026-09-23. Replacement and durability behavior
need Windows, macOS and Linux checks rather than an assumption from one host.

## Implementation evidence, 2026-09-23

The server now hashes the exact bundled M01 content bytes and validates one
versioned run document. It records run identity, rules, allowance, the M01 entry
equipment and one of these steps: mission entry, pending Continue, failed,
abandoned, or M01 complete with M02 pending. Resume rejects a terminal step.
The authoritative departure transition freezes exit equipment before the owner
can leave, so later disconnects cannot invalidate the completed document.
The disk store bounds reads, holds a writer lock, archives old bytes on an
explicit new start, and replaces a same-folder temporary file after syncing it.
A post-rename sync failure inspects the live path and reports uncertain
durability. A pre-rename fault leaves the previous valid document in place.

The local child saves before readiness and before delivering changed game state.
The menu previews through the Rust validator and exposes Continue Run only for
a compatible playable save. Exit to Menu disconnects and stops the owned child
without sending Leave; a wire Leave durably marks the run abandoned. A failed
run and an M01-complete run remain visible but are not offered as Continue Run.
The opening is skipped on resume. Tests isolate `FRAGR_RUN_DIR` so they cannot
read or change the player's normal save.

Evidence on this branch: focused run-document and store tests (9 passed), real
child tests (8 passed, including restart, lock refusal, invalid previews and
explicit Leave), a Godot headless suite with the real M01 death, pending-Continue
restart and spent-Continue restart harness, and an inspected 24-state visual
tour published through `tools/qa_tour.sh --publish`. The unfiltered workspace
line coverage was 93.46 percent. The six-map mixed roster, four-agent playtest,
deterministic benchmark, dependency policy check, and serialized release build
passed locally. PR CI is still required before integration.

A free local-rules agent cleared M01 on Standard seed 67 in one attempt through
an owned local child. The child wrote an `awaiting_mission` document with three
continues, 40 HP, Tack selected, its live magazine and reserves, and the bay
claim. A fresh `--local-run-preview` reported `awaiting_mission`; a separate
owned child with `--run-mode resume` exited without readiness because this M01
step is terminal. The receipt and isolated run file are under ignored
`.agents/departure-7213984ec6d648d3adacedd5d944c678/`. M02 is unbuilt, so
this does not prove a cross-mission load yet.

That probe also exposed a completed-owner disconnect error. Departure now
freezes exit equipment before the owner can leave. A second free local-rules
probe cleared Standard seed 67 after one spent continue and then exited its
agent. The owned child stayed alive, accepted its parent shutdown, and exited
0 with an empty error stream. Its file and a new preview both reported
`awaiting_mission` with two continues and the live 80 HP exit. The route test
also proves a subsequent tick after owner removal keeps the same completed
document. This receipt is under ignored
`.agents/departure-recheck-93260f88fd884025bcb1f4c94ccf8b74/`.

The probe used the release binaries with an isolated `FRAGR_RUN_DIR` and an
open parent stdin lease:

```text
fragr-server --local-mission recall_notice --run-mode new --difficulty standard --seed 67
fragr-brain --provider local --no-ledger play --server <ready.url> --name FreeRunProbe --max-seconds 240
fragr-server --local-run-preview
fragr-server --local-mission recall_notice --run-mode resume
```

The run file is a mission-entry save, not a mid-level checkpoint. Participant
service-record history remains separate and does not accumulate across process
restarts. This work remains in flight until CI is recorded. Windows is the
local durability platform; Linux and macOS need CI checks and a
platform-specific durability review.
