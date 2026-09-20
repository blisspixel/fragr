# Tripoint spawn safety

Status: shipped in [#193](https://github.com/blisspixel/fragr/pull/193) and
[v0.28.0](https://github.com/blisspixel/fragr/releases/tag/v0.28.0), 2026-09-20.
Task: [#194](https://github.com/blisspixel/fragr/issues/194).
Spend: $0. This investigation gates the campaign-opening integration in #193.

## Evidence and outcome

CI run 35519428024 at `4f77f71` failed the unchanged 16-client Tripoint roster:
seed 42, 10 spawn deaths among 51 frags. Four deaths occurred in the opening
volley; six followed later respawns. Local Windows evidence had seven among 51.
The earlier #175 fix removed a warmup bypass of the cover selector. It did not
prove safe placement at every density.

Preserve the failed report, compare against main, and identify the spatial or
lifecycle defect before changing the rules. Deliver safer playable spawns with
an explicit regression and measured network evidence. Do not rerun CI until a
passing sample hides the failure.

## Boundaries

`GameState::select_spawn_angle` owns placement choice. `RuntimeMap::spawn` and
the built-in map definitions own candidate positions and collision surfaces.
Shared combat sight tests, movement and existing navigation prove viability.
Do not introduce a second spawn algorithm in Session or the client.

Inspect selected support heights, occupied distances, incoming lanes and usable
escape routes. Fix the demonstrated failure at its source. Retain damage,
shields, spawn-death definitions and acceptance limits; any separate balance
change needs its own evidence. No protocol change, dependency, paid API or
full arena redesign is planned.

## Verification

- Reproducible diagnostic and deterministic failing regression before the fix.
- Original covered-opening, movement, map-validation and benchmark invariants.
- Strict Rust, full workspace tests and unfiltered coverage.
- Six-map mixed-client roster plus predefined Tripoint seeds and repeats, keeping
  failures and per-spawn evidence. Network scheduling is not deterministic.
- Inspected rendered Tripoint route and current public gallery if geometry moves.
- Cross-platform CI before integration. Record remaining limitations honestly.

Raw evidence: `.agents/playtest/pr193-failure/` and
`.agents/m01-opening-ci-rust-failure.log`. Temporary diagnostics stay in `.agents/`.

## Local findings and repair

The failure reproduces on unchanged main (`d961b64`): seed 42 records 12 spawn
deaths among 65 frags. A deterministic 16-person opening puts 14 participants in
an incoming firing lane. Selected support heights are ground level, so this
reproduction is an exposed-ring layout defect rather than spawning on wall tops.

Tripoint now uses the existing `spawn_pockets` builder at 16 positions. These
sorting bays interrupt the perimeter rail lanes without enclosing the central
plaza. The northern health pickup moves inside the compound to avoid the new
rear block. Spawn selection, damage, shielding and thresholds are unchanged.

The new regression fails before the geometry change at a 40.97 m opening lane.
Afterwards it proves all 16 starting fighters are mutually screened within Rail
range and non-overlapping. Each actual selected position can reach the center
using the existing server movement/navigation test helper, without jumping.
Whole-roster map validation and actual walking routes to every pickup also pass.

Predefined local network comparisons, 16 mixed clients on Windows:

| Geometry | Seed | Frags | Spawn deaths | Gate |
|---|---|---|---|---|
| Main | 42 | 65 | 12 | Fail |
| Main | 67 | 81 | 6 | Pass |
| Sorting bays | 42 | 58 | 1 | Pass |
| Sorting bays | 67 | 71 | 2 | Pass |
| Sorting bays, full roster repeat | 42 | 52 | 3 | Pass |

No later-respawn deaths occurred in the first two changed-layout samples. Their
remaining early deaths followed movement out of the initial cover. The full
roster repeat recorded one opening death and two later-respawn deaths, retained
in its log. These samples do not establish a universal death rate or eliminate
the need to balance respawns during an active fight.

The combined opening/placement build passes 705 workspace tests, strict Clippy,
95.81 percent unfiltered line coverage, release build, dependency policy and all
27 Godot harnesses. The existing eight verifier fault cases also pass. The live
three-state Tripoint tour and shot strip were inspected; the cover matches the
authoritative geometry, while the larger repetitive layout remains unfinished.

Local release CPU measurements, Ryzen 7 7840U, Windows x86_64, seed 42, shared
session plus encoding scope. Both full traces repeat deterministically and pass the unchanged
tick-budget assertions:

| Map | Rule bots | Ticks | p99 tick ms | Maximum tick ms |
|---|---|---|---|---|
| Arena Duel | 16 | 1,200 | 0.688 | 1.425 |
| Tripoint Works | 128 | 12,000 | 8.913 | 16.574 |

These are simulation measurements, not network capacity, GPU performance or
evidence that 128 players are balanced on this map. Reports:
`.agents/m01-tripoint-bench16.json` and `.agents/tripoint-covered-bench128.json`.
The complete six-map repeat passed the unchanged assertions; its results are
listed in [the opening plan](m01-opening.md). The 21-state gallery passed and
all current stills, shot and impact strips were inspected and published. Reports
live under `.agents/playtest/m01-tripoint-roster/`, with current gallery evidence
under `.agents/qa/m01-tripoint-gallery/`. Integration and release evidence is
recorded on #193 and the linked task.
