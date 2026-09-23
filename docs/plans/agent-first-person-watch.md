# Agent first-person watch

Status: **shipped** ([#219](https://github.com/blisspixel/fragr/pull/219), v0.43.1).
Local validation is recorded below. The merge and main CI passed.

## Goal

Make a local, repeatable first-person watch of a real agent pawn. The capture
must follow the server-assigned participant through eight rendered frames and
pair those frames with the brain's action and zero-spend receipt. Use it to
inspect authored fights and catch camera, identity, or stalled-tick failures.

## Scope and seams

- Add the server-assigned ID to the existing brain run summary. No wire change.
- Pin the existing spectator camera to that ID without changing the normal
  spectator controls. A missing target must not silently switch fighters.
- Run one owned local server, free-rule brain, and Godot spectator from a shell
  wrapper. Keep output under ignored `.agents/watch/` and stop owned processes.
- Capture real rendered pixels, authoritative ticks, eye placement, and facing.
  Check all frames against the same brain participant ID.

No paid provider, player runtime recording feature, matchmaking, or campaign
acceptance claim is part of this change. The harness does not replace later
fresh-player or multiplayer tests.

## Validation and success

Run focused Rust and Godot checks, the repository verification suite, and a
local wrapper run. Inspect the PNG sequence and receipt. Exercise receipt
mismatch and pin loss failure paths. Success means eight nonblank first-person
frames from one live agent with advancing server ticks, a paired brain receipt
with actions and zero spend, and a green CI PR. Update the roadmap after merge.

Spend: $0. The wrapper forces the local provider. No cloud apply or asset
generation.

## Local evidence

- `cargo test -p fragr-brain --locked --quiet`: 70 library and 7 CLI tests passed.
- `tools/godot_check.sh`: passed after the release server build completed, and
  again after the final camera and receipt edits. The first overlapping run
  failed two local-launch harnesses while that binary was still building.
- `FRAGR_WATCH_SECONDS=10 bash tools/qa_watch.sh
  .agents/watch/hardened-smoke`: eight first-person frames and a paired
  server ID, advancing ticks, free-rule actions and $0 spend. The PNG sequence
  was inspected, including the pistol and objective view.
- A receipt with a string `passed` field was rejected with exit code 1.
- Independent review caught server ownership, capture timing, Godot log verdict,
  pin restoration and receipt-type gaps. Each was corrected; the final wrapper
  smoke passed with owned-process cleanup.
- Workspace clippy, tests, release build, benchmark assertion, 95.32% line
  coverage, dependency checks, four-agent playtest and Godot checker self-tests
  passed. `tools/qa_tour.sh --publish` captured 24 states, published 11 stills,
  and the contact sheet, spectator eyes, impact strip and records still were
  inspected.
- `tools/playtest_roster.sh` passed its six-map assertions. The mixed-roster
  reports still show spawn deaths on maps 3 through 6 (3, 4, 3 and 1 at the
  tested seeds). This is a multiplayer map-quality issue for the LAN gate,
  not a pass on spawn safety.

The short watch establishes the live capture path. It does not establish a
mission clear, multi-seed consistency, difficulty acceptance, or human
comprehension. Those remain work in the campaign playtest sequence.
