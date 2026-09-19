# Authoritative shot impacts and combat feedback

Status: locally verified, integration pending, 2026-09-19.
Branch: `feat/shot-impact-feedback`. Spend: $0.

## Problem and scope

Vertical aim now resolves real 3D shots, but clients cannot show where a miss
landed. The wire outcome lacks weapon and geometry. The playtest observer infers
these from surviving fighters, losing shots when their shooters die in the same
tick. Its latest smoke reports ten kills from only ten counted shots and assigns
kills to a weapon with zero counted shots. Those figures cannot guide tuning.

Deliver visible world impacts and rail traces from the authoritative result,
with complete shot/kill accounting. Preserve current weapons, damage tables,
movement, maps, and server authority. This is not projectiles, headshots, a final
animation/art pass, or completed performance/scale certification.

## Contract and seams

- Extend shared `ShotResult` with optional typed shot evidence for older recordings:
  weapon, eye origin, end point, and an exhaustive fighter/solid/range impact.
  Surface impacts carry a normal; range exhaustion does not. Current servers
  always include evidence. Add an explicit lethal-result flag, default false for
  old data, so one committed shot owns a kill.
- Refine `server/src/combat.rs` intersections to return distance and normal. One
  resolved ray in `sim.rs` determines target, cover, falloff, and reported geometry.
  A solid impact ends at that surface; a clear miss ends at weapon range. Preserve
  committed simultaneous shots, but credit a victim's death only once per tick.
- Add one bounded client effects presenter fed through the existing
  `game_manager._process_shot_results` seam. Validate external vectors and enums;
  ignore old results without geometry. Never raycast or infer a second outcome.
  Use depth-tested simple geometry and existing pixel effects with short lifetimes,
  a hard effect cap, and cleanup on map/role changes. Keep Compatibility and
  Forward+ behavior aligned. No new per-shot lights or renderer-specific compute.
- HUD feedback reads the shot's weapon even if its shooter vanished. Preserve the
  existing audio path; avoid doubled fire/hit sounds.
- `tools/playtest` counts every shot from its evidence. Attribute kills and 3D
  distances to the lethal result, with explicit fallback for older events lacking
  evidence. Snapshot/event ordering, trades, swaps, and respawns must not double
  count or carry a previous life's engagement forward.

## Research

Checked 2026-09-19 against official Godot stable documentation:
[ImmediateMesh](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html)
fits small changing geometry. Use
[StandardMaterial3D properties](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)
for unshaded, depth-tested effects.
[Decal nodes](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html)
exclude the Compatibility renderer, so this shared path uses meshes or Sprite3D.
Retain Godot 4.7.2 and the current Rust stack. No new dependency or paid generation.

## Acceptance and evidence

- [x] Deterministic tests prove fighter, side/top/floor cover, and range endpoints
  and normals, including parallel/boundary cases and nearest-surface selection.
- [x] Trades retain both shots; multiple same-tick hits cannot award duplicate
  kills. Current and legacy wire shapes round-trip.
- [x] Observer tests prove shot, weapon, kill, and distance accounting independent
  of the live roster; real-wire reports have consistent shot/kill totals.
- [x] Client tests prove malformed data rejection, bounded effects, expiry,
  duplicate-tick handling, teardown, and HUD weapon selection.
- [x] Acknowledged shot strips show actual impacts and their expiry. Inspect both
  renderer tours and refresh current screenshots.
- [x] Workspace checks, 90 percent unfiltered coverage, Godot harnesses, repeated
  CPU benchmark, and live agent smoke pass. Update protocol, roadmap, and plans.

## Verification receipt

Rust 1.98.1 on Windows: 579 passing tests, one existing ignored vector-generation
test, warnings-denied workspace Clippy, formatting, release build, and dependency
license/bans/source checks pass. Unfiltered workspace line coverage is 95.21
percent. All 14 Godot harnesses pass, including malformed geometry, expiry,
same-tick replay rejection, session cleanup, and zero-damage HUD behavior.

Both 21-state live tours pass with inspected contact sheets, acknowledged full-size
rail-impact frames, and timed strips. Windows 11, Ryzen 7 7840U/Radeon 780M,
Godot 4.7.2, OpenGL 3.3 Compatibility and Vulkan 1.4 Forward+. In both strips the
local floor impact is active in six of twelve samples and gone at the end. The
eye-aligned rail path projects onto the reticle; these captures primarily prove
impact placement and decay, not third-person beam readability under every angle.
Effects use one depth-tested mesh, at most 128 active shots, and no per-shot lights.
Nine published stills are refreshed. This is not cross-vendor GPU certification.

The four-agent real-wire smoke completes in 26.45 s: ten frags, first at 5.05 s,
longest gap 10.7 s, zero spawn deaths. It now records 20 shots, 20 physical hits,
ten rail shots and ten flechette shots, with ten flechette finishers. A separate
six-agent mixed reflex/planner run completes in 33.6 s: 15 frags, first at 3.1 s,
longest gap 5.5 s, one spawn death. Both pass the configured thresholds. These
small deterministic-agent samples establish accounting and basic liveness, not
weapon balance. Historical measurements that omitted dead shooters need new runs.

### Offline CPU receipt

Same Windows CPU, Rust release profile, seed 42, 12,000 ticks plus complete-trace
repeat per case. Serial runs after rendered tours, no sockets. Every trace hash
agrees and no measured step exceeds 50 ms. Scope is session plus serialization,
excluding hashing, recording, networking, and rendering. Do not infer online
capacity or GPU performance from this table.

| Bots | Map | Session p99 ms | Encode p99 ms | Total p99 ms | Total max ms |
|---:|---|---:|---:|---:|---:|
| 16 | Arena Duel | 0.024575 | 0.017407 | 0.038911 | 0.2858 |
| 64 | Reclamation Gulch | 0.069631 | 0.029695 | 0.094207 | 1.0584 |
| 128 | Tripoint Works | 0.163839 | 0.077823 | 0.221183 | 1.3050 |

The saved v0.16.0 trace still verifies against its original SHA-256 after the
additive protocol change. Local receipts: `.agents/impact-*.log`,
`.agents/playtest/impact*.json`, `.agents/bench/impact-*.json`, and
`.agents/qa/impact-release` / `impact-vulkan`. Durable evidence is the tests,
published captures, this receipt, and the integration CI result.

Remaining: animated target reactions, registered weapon animation, authored
encounters, richer surface impact variation, and rendered performance measurement.
This increment does not complete the game's art or gunfeel pass.
