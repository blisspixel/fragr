# Shared body integration

**Status:** in progress, 2026-09-19. Prerequisite for
[enclosed campaign spaces](campaign-spaces.md). Spend: $0.

The live simulation duplicates horizontal slide, grounding, jump and falling
logic from `movement::step`. Recent ledge and fractional-stair repairs needed
changes in both paths. Adding ceiling collision to both would repeat that risk.

Extract one velocity-to-position body integrator in `movement.rs`, used by the
live server and the existing acceleration-based shared step. Preserve the live
server's immediate horizontal response and queued-jump handling; this change does
not enable client prediction or silently introduce acceleration. Mirror the
same split in GDScript without regenerating golden expectations.

Cache each built-in map's immutable movement arena once, use it for navigation,
floor and occupancy queries, and derive wire solids from that same geometry.
Keep the existing map builders and public wire shape. Avoid per-player/per-tick
geometry allocation. No new dependency, weapon behavior or level is involved.

Verification: existing movement goldens and actual-player stair/ledge tests,
full Rust/Godot checks, real-wire roster, and unchanged complete-trace hashes
against the v0.21.0 12,000-tick 16/64/128-bot receipts. Investigate any changed
trace before integration; do not update the expected hashes merely to pass.
Record measurements and update the geometry plan before continuing.

## Implementation and evidence

The live simulation and accelerated step now call `movement::integrate` for
horizontal slide, grounding, jumping and falling. The client mirror has the same
split. Built-in maps cache their movement arena; navigation, shots, floor queries,
occupancy and wire solids reuse it. Live input remains immediate and the wire
shape is unchanged. Existing golden expectations were not regenerated.

Local checks pass: 596 Rust tests with one existing ignored generator, formatting,
warnings-denied Clippy, release builds, dependency license/bans/source checks,
95.45 percent unfiltered workspace line coverage, all seventeen Godot harnesses,
and the checker's six injected success/failure cases. The 21-state OpenGL tour
passes; its contact sheet and shot strips were inspected and nine public stills
were refreshed. The existing large-floor and weak-landmark shortcomings remain.

Serial release measurements on the same Windows Ryzen 7 7840U host, seed 42,
12,000 ticks each, with `--bench-check --bench-assert`:

| Bots / map | Total CPU p99 ms | Maximum ms | Complete trace SHA-256 |
|---|---:|---:|---|
| 16 / Arena Duel | 0.655359 | 2.0546 | `fd6ec849cb20375b267f523588200f4568ca6358513375b7d8ce09db28be508c` |
| 64 / Reclamation Gulch | 1.441791 | 2.8433 | `85f34620de8d42b6eab099122952cd49a2d774e3c37e357739d413e05847fa32` |
| 128 / Tripoint Works | 4.063231 | 7.7915 | `66730d2220cad0b3594379a211b777eff92953c75380c605ab753663c7685f36` |

Every repeat agrees and every complete trace matches the v0.21.0 baseline. These
are CPU-only samples, not evidence of a performance improvement, GPU support or
network capacity. Logs live in `.agents/shared-body-*.log`; benchmark receipts in
`.agents/bench/shared-body-*.json`; inspected tour in `.agents/qa/shared-body/`.

The live movement tour also passes and its contact sheet and jump peak were
inspected: a short Space tap, ascent/descent without jumping, the repaired stair
entrance, and ledge exit all use real input and server positions. Receipts live
in `.agents/qa/shared-body-movement/`. The six-map mixed-client matrix passes
with unchanged assertions:

| Map / seed | Clients | Duration s | Frags | Spawn deaths |
|---|---:|---:|---:|---:|
| Arena Duel / 67 | 2 | 61.90 | 6 | 1 |
| Compliance Yard / 42 | 6 | 61.90 | 30 | 0 |
| Directive 17 / 19 | 6 | 53.80 | 26 | 1 |
| Sector 9 / 42 | 8 | 48.65 | 34 | 2 |
| Reclamation Gulch / 42 | 12 | 59.65 | 55 | 4 |
| Tripoint Works / 42 | 16 | 49.65 | 75 | 8 |

The separate four-client smoke records eight frags and zero spawn deaths in
21.7 seconds. Receipts are `.agents/playtest/shared-body/` and
`.agents/playtest/shared-body-ci.json`. Network scheduling varies; this preserves
the existing sample-aware spawn-death gate rather than claiming ideal spawns.
CI remains required before integration. Enclosed geometry remains separate.
