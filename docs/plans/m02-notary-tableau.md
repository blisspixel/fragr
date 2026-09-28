# M02 Notary observation tableau

**Status:** in flight, 2026-09-28. Based on the stacked M02 natural-entry head `e9d3a5f`. Local development cost $0.

## Goal and reason

The accepted level 2 Persons Unknown brief calls for one Notary photographing captive agents beyond the observation glass, out of reach. The current map has no Notary and the level 4 Notice to Vacate owns its first fight. Build a legible, enclosed, noncombat preview that adds surveillance to M02's opening without redirecting the player from Latch, the Shotgun or the Crawler lesson.

## Scope

- Author a small, high inspection bay beside the correction ward in the server map. A registered transparent surface renders the same solid that blocks movement and shots. The bay remains outside the playable route; the primary gallery entry can see the pane and drone through its existing window. Preserve the gallery sightline to Latch and the lower sill that prevents a shortcut.
- Add one source-owned Notary visual with the canonical black box under two ducted fans, dim red optic and issued seal. Its small scan across the captive ward suggests observation without an invented attack or capture event. No attack flare, combat shutter click, triple burst, shadow tell, enemy actor, health, reward or mission event enters M02.
- Keep the tableau under the M02 presentation owner, keyed by the same map and mission identity. Rebuild cleanly on map changes; keep one passive figure through release, retry and late join because freeing Latch does not establish the fate of every captive. It cannot become a target in the shared action channel.
- Correct stale `M03` and `M07` drone plan labels to level 4 Notice to Vacate and level 12 Terms of Cooperation, including the plan index. The current twenty-level campaign table and accepted mission briefs own placement.

## Architecture and protocol

`server/maps/m02-persons-unknown.json` owns every collision and shot surface. Add a registered `inspection_glass` map presentation surface in `server/src/protocol.rs`, mirror its validation in `client/scripts/map_geometry.gd`, and render it through `client/scripts/arena_cover.gd` and `arena_materials.gd`. It remains an ordinary `Solid` for Rust movement and combat; only presentation changes. The surface is a registered enum value, never a client-supplied shader path. Strict older readers reject unknown surfaces, so M02 requires gameplay capability 22; previous M02 capability 21 clients receive `unsupported_gameplay` before MapInfo. `docs/protocol.md`, local readiness and the adapter reader reflect this contract.

Godot 4.7 documentation checked 2026-09-28 confirms `BaseMaterial3D.TRANSPARENCY_ALPHA` and `albedo_color`, with known sorting and shadow limitations. Use one bounded pane, not multiple overlapping translucent layers; inspect Compatibility, and keep depth testing. The authoritative solid must coincide with its visible pane, so a shot visibly terminates on glass instead of passing through it. [Godot 4.7 BaseMaterial3D](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html), [Standard Material 3D](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html).

The Notary visual belongs in a reusable runtime source component used by `client/scripts/m02_ward.gd`. A later level 4 combat renderer may derive its sprite source from the same silhouette; this draft must not claim the combat role is implemented. Captive status, Latch release and map transitions remain server-owned facts.

## Evidence and rejection gate

- Rust tests: from the primary standing eye, the line to the Notary intersects the named glass solid while the line to Latch remains clear; a server ray hits glass before the visual's position; movement and navigation cannot enter the bay; no new campaign enemy or encounter exists. Preserve the primary entry's blocked guard rays and all four gallery spawns' Shotgun/stair paths.
- M02 seeded route tests: Shotgun claim before the first guard wake, both Crawler cues in order, wipe/reset, solo human and agent departure, and Severe side-ward supplies. A new solid is unfinished if any authored route becomes unreachable.
- Godot tests: strict new surface validation, transparent render material, one map-only tableau, held/released and retry/late-join states, no actor duplication or UI objective. The first-person QA route must capture an unforced primary entry, a natural gallery approach, and a brief motion strip at 1280 by 720. Inspect real pixels and a combat shot at the pane. If the pane appears as an invisible wall, the shot crosses it, or the Notary reads as an attack cue, reject the candidate.
- Run format, Clippy, workspace tests and headless Godot checks. Record actual commands, results, renderer and remaining human comprehension limits. Do not call M02 finished or the Notary combat-ready from this pass.

No paid services or cloud resources are needed for this sprint. The change
stays a draft until its exact head passes CI and the stacked review is ready.

## Local result and open acceptance

The sealed bay, registered pane and passive visual are implemented in this
draft branch. The bay is unreachable by navigation and body collision.
The M02 capability boundary is 22; a capability 21 client is rejected before
a seat, while a capability 22 client joins. The Shotgun route, first Crawler
cue, later Crawler pack, retry and side-ward routes retain their seeded checks.
An ordinary live Shotgun claim and resolved shot trace end on the named glass
face, with no Notary combat target.

[Native frames and motion strip](../screenshots/m02-notary-tableau/README.md)
show a tinted, physical pane from the unforced primary spawn and ordinary
gallery positions. The figure remains a small peripheral surveillance
glimpse. A modest size increase and shift toward the pane improved its
twin-duct silhouette, but the fans and optic do not read reliably in these
1280x720 stills.
Two pale backing trials read as floating slabs through the glass, and a
concrete wall face darkened the figure, so all three were rejected. A fresh
player still needs to identify the figure in motion; this work does not prove
that recognition or complete the level 2 mission. The original gallery also
exposes the ward Sweeper from a nearer ordinary position. That sightline is
present at the same position on the parent map and was not changed here.

Verification on 2026-09-28: `cargo fmt --all -- --check`, focused pane
geometry and exact Shotgun trace tests, full workspace tests and Clippy, full
Godot checker, native five-state QA, and the full 32-state player-facing tour
on the AMD Radeon 780M Compatibility renderer. The unfiltered workspace line
coverage check passed at 93.79 percent before the final test-only ShotTrace
assertion. Do not infer human comprehension from automated passes.
