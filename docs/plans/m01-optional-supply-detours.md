# M01 optional supply detours

Status: **implemented**. Local checks passed; PR integration is pending.

## Goal

Add two small, readable optional walking detours to Recall Notice. The
confiscation alcove rewards looking beside the property lockers; the maintenance
overlook rewards climbing beyond the direct records approach. Neither supply
is required to clear the mission.

## Scope and architecture

Use the existing authored map JSON, supply-claim lifecycle, navigation budget,
and first-person tour. Keep the mission routes and server authority unchanged.
The alcove moves the existing medkit by one metre; the overlook adds one armor
pad. No new secret counter, weapon, enemy, gate, wire shape, or client runtime
rule. This slice must not depend on unfinished identity, save, or chat work.

## Verification

Assert walking routes to and from both rewards in each lift state, including
solid collision and the return to the original route. Check that ordinary
routes do not claim either optional supply, that a deliberate visit claims it
once, and that a mission continue restores it. Run map validation, seeded M01
walkthroughs and failure paths, the full Rust/Godot suite, and inspect refreshed
visual tour stills and the exploration capture. Record any visual or acceptance
gap instead of marking M01 complete.

## Spend and success

Spend: $0. No paid media, cloud apply, or human acceptance test. Success is
two discoverable supply spaces reachable through ordinary movement, unchanged
required progression, correct claim/retry behavior, clean validation, and a
reviewable PR with honest screenshots.

## Local evidence, 2026-09-22

- Focused M01 tests passed: ordinary human and agent routes, authored route
  walking, optional pads in both lift states, one-time claims, and continue
  restoration. The normal route still ends at the lift without either cache.
- The sequential full workspace test run passed, including 394 server library
  tests. An earlier concurrent run collided with the audio tool's shared fixed
  temporary test path across two worktrees; the isolated rerun passed.
- Rust format, clippy, the release benchmark assertion, cargo-deny, release
  build, 4-agent playtest assertion and six-map mixed roster passed. The
  unfiltered workspace line coverage gate passed at 94.67 percent.
- Godot 4.7.2 headless checks passed. The seven-state OpenGL exploration capture
  had 15 successful walking legs and no blank or failed frames. I inspected the
  alcove, armor, and overlook stills at full size. The 24-state player-facing
  tour passed and refreshed the README stills; its contact sheet was inspected.
- A deliberately unreachable QA waypoint exited nonzero at the walk failure,
  before saving a state frame or manifest. This verifies the capture abort path.
- The Godot checker self-tests passed, including injected error, missing PASS,
  and failed-exit cases. The branch is ready for CI review.

The pickup meshes are provisional blocks. Scripted navigation proves access,
not whether a new player notices either detour, enjoys its timing, or finds the
whole mission balanced. Human acceptance remains deferred until near 1.0.
