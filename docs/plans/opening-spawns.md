# Covered opening spawns

**Status:** shipped and proven, 2026-09-19, PR #175 and v0.21.2. Spend: $0.

## Defect and bounded fix

The six-map network roster caught 9 spawn deaths among 48 frags on Tripoint
Works. Warmup joins bypassed the cover selector unless a fixed ring position was
occupied. The opening fight therefore had weaker placement than active joins
and respawns. A local diagnostic run found four of its five early deaths in the
first 1.05 seconds after the round opened.

Use `GameState::select_spawn_angle` for every join with living opponents. Retain
its existing priority: avoid overlapping fighters, minimize exposed firing lanes,
then maximize clearance. No second spawn algorithm, new shield, damage change,
map rewrite or relaxed playtest threshold.

The existing Reclamation Gulch cover fixture now includes warmup joins, active
joins and respawns in four orientations. Before the fix it places a warmup player
at approximately (0, 0, 92), exposed despite a covered alternative. This is a
deterministic reproduction, separate from variable WebSocket scheduling.

The same PR also repairs an unrelated threshold unit test that asserted the
speed of an instrumented debug run. Known durations now test threshold semantics;
the separate release performance gate remains unchanged. See `../BENCHMARK.md`.

## Completion evidence

Require the regression, workspace checks and coverage, the unchanged six-map
network roster, repeated 16-client Tripoint runs, seeded release benchmarks and
an inspected current tour. Record before/after opening-death evidence rather than
claiming universal spawn fairness from one passing sample. Initial placement
changes seeded match traces intentionally; movement goldens must not change.

Local receipts: `.agents/warmup-spawn-*.log`, `.agents/spawn-evidence*`, and
`.agents/pr175-playtest/` (the failed CI reports).

The regression, workspace tests, warnings-denied Clippy, dependency license/source
checks and local coverage pass (95.46 percent of workspace lines). The unchanged
network matrix and two additional Tripoint runs pass:

| Map / seed | Clients | Seconds | Frags | Spawn deaths |
|---|---:|---:|---:|---:|
| Arena Duel / 67 | 2 | 61.90 | 5 | 0 |
| Compliance Yard / 42 | 6 | 61.90 | 29 | 0 |
| Directive 17 / 19 | 6 | 61.90 | 27 | 3 |
| Sector 9 / 42 | 8 | 51.00 | 34 | 3 |
| Reclamation Gulch / 42 | 12 | 40.05 | 41 | 3 |
| Tripoint Works / 42 | 16 | 39.65 | 58 | 7 |
| Tripoint Works / 42, repeat | 16 | 48.60 | 70 | 4 |
| Tripoint Works / 67 | 16 | 34.10 | 51 | 7 |

These use the existing Wilson lower-bound gate; a passing run does not imply its
raw spawn-death share is below ten percent. Network scheduling varies. The covered
placement regression proves the specific fix; these samples do not prove a general
rate improvement. Tick evidence distinguishes opening deaths from later respawns.

The 21-state OpenGL tour and three-state Tripoint tour pass. Contact sheets and
shot/impact strips were inspected; nine public stills were refreshed. Captures:
`.agents/qa/opening-spawns` and `opening-spawns-tripoint`. Large repetitive open
spaces remain a design gap. This repair does not make those maps final-quality.
Release benchmarks pass with seed 42 and 12,000 ticks, including a repeated
full-trace determinism check. These are local CPU simulation measurements,
not network capacity or client frame-rate claims:

| Bots / map | p99 tick ms | Maximum tick ms | Deterministic |
|---|---:|---:|---|
| 16 / Arena Duel | 0.590 | 1.936 | yes |
| 64 / Reclamation Gulch | 1.442 | 4.091 | yes |
| 128 / Tripoint Works | 3.932 | 7.423 | yes |

Reports: `.agents/bench/opening-spawns-{16,64,128}.json`. The release workspace
build and all 17 Godot harnesses pass. CI run 35488056552 passed all five jobs,
including the Linux mixed-client roster and Windows/macOS checks. Merged as
`703bc89`; v0.21.2 is a source release.
Main's post-merge CI run 35488562108 also passed every job.

Separate lifecycle follow-up: `start_round` resets scores and pickups but does not
reset player vitals, pending combat input or positions when rotating maps. Prove
two-round transitions with damaged/dead fighters and a large-to-small map change,
then establish the intended reset contract. This opening-placement fix does not
claim to resolve that behavior.
