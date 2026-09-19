# Arena surface pass

Status: in flight, 2026-09-19. Branch: `feat/arena-surface-pass`.
Part of `local-excellence.md`; visual stages continue in `look-pass-boomer.md`.
Spend: $0, authored shaders and geometry, existing fonts and assets.

## Goal and scope

The inspected v0.15.0 tour shows an almost entirely tan blockout. Give existing
arenas readable industrial surfaces, deliberate color grouping, and a believable
backdrop, with a focused first pass on Arena Duel. Keep combat silhouettes clear.
The game should have chunky pixel detail, dark steel, rust, bone markings, and
restrained faction accents. Menus, world, and weapons must belong to the same game.

This pass does not declare the maps finished. Authored campaign layouts, enemies,
animation, interactions, encounter pacing, and full 3D aim remain separate work.
No paid generation, new rendering dependency, or server geometry change.

The first rendered inspection also exposed distance-based sprite enlargement in
fighter eye views. That makes opponents appear above cover they are actually
behind. Restrict the existing enlargement to spectator overview/chase, with an
actual pawn/camera harness. Keep normal scale for human and spectator eye views.

## Architecture

- `ArenaCover` remains the only builder for `MapInfo` collision surfaces. Exact
  solid bounds and heights must survive the art pass.
- Extend the existing spatial material with world-aligned pixel detail. Centralize
  palette/material choices and reuse materials within a map. No second terrain path.
- Scenery may sit outside the playable boundary. Surface markings must not imply
  climbable platforms or cover that the server does not implement.
- Keep the existing `WorldEnvironment` and sky seam. Avoid a second environment.
- Reconcile the art bible with the current product direction, retaining locked
  logos, palette, original silhouettes, and frozen audio vocabulary.

## Research and verification

Godot 4.7 spatial shader built-ins and `Label3D` depth/filter behavior checked
2026-09-19 against the official
[shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
and [Label3D reference](https://docs.godotengine.org/en/4.7/classes/class_label3d.html).
Use ordinary material uniforms compatible with both local render paths; no
renderer-specific effects are needed for the surface pass.

- Geometry harness checks exact server solids, replacement, and map rotation.
- Godot import/parse/harness checks and clean renderer logs.
- Inspect first-person, overhead, and spectator captures from the live server.
- Run the full tour in OpenGL and Vulkan on the available Radeon 780M; publish
  current stills only after inspection. Other vendors still need direct evidence.
- Record limitations rather than substituting screenshot metrics for art judgment.

## Acceptance

- [x] Surfaces read as industrial places, with distinct floor, cover, and walls.
- [x] World detail stays pixel-shaped and follows a consistent scale.
- [x] Foreground geometry still exactly follows server collision bounds.
- [x] Backdrop and landmark details improve orientation without false cover.
- [ ] Both rendered paths, geometry checks, and visual inspection pass.
- [ ] Art direction, roadmap, screenshots, and plan state match the implementation.

## Implementation and review

The existing shader now uses a 16-texel/metre grid for framed panels, recessed
vents, fasteners, clustered wear, lane paint, and hazard bands. Boundary panels
are larger than cover panels; horizontal decks omit wall vents. Four shared
materials per map replace individual allocations for every block.

`ArenaBackdrop` adds industrial silhouettes beyond the playable square and flat
wall identifiers. The geometry harness proves scenery meshes do not intersect
that square, solid dimensions stay exact, and replacing a map removes old meshes
immediately. First-person fighters retain normal scale; the actual pawn/camera
harness verifies that only the broadcast path applies the distance boost.

The art bible now reflects the full-game target and current lore while preserving
logo, palette, original-asset, and frozen-voice constraints. Early arena-only
instructions, obsolete workspace paths, and internal attribution labels are gone.

Godot 4.7.2 import/parse and all 11 harnesses passed locally. The first OpenGL
inspection prompted larger boundary panels, less bright framing, and the eye-view
scale correction. The final OpenGL tour passed all 15 states; the first-person
capture and world views were inspected, and current screenshots were refreshed.

Limitations: this is a reusable first surface pass, not finished level art.
Custom props, more material families, authored interiors, enemy animation, and
map-specific encounter layouts remain necessary. The tour is visual evidence,
not a GPU benchmark or a claim of NVIDIA/Intel/Mac rendering validation.
