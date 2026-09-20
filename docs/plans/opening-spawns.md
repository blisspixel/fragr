# Covered opening spawns

**Status:** in progress, 2026-09-19, PR #175. Spend: $0.

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
`.agents/pr175-playtest/` (the failed CI reports). Verification is in progress.
