# Tripoint spawn safety

Status: in flight, 2026-09-20. Task: [#194](https://github.com/blisspixel/fragr/issues/194).
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

No later-respawn deaths occurred in the two changed-layout samples. Their
remaining early deaths followed movement out of the initial cover. These samples
do not establish a universal death rate. Full verification, the six-map repeat,
rendered inspection and integration remain before completion.
