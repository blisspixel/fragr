# M01 facility detail

Status: **shipped**, 2026-09-20, #182 and v0.25.0, within
[task #180](https://github.com/blisspixel/fragr/issues/180). The scoped detail pass
has local visual/verification evidence and green integration CI. Final environment
art and fresh-player pacing remain open in the parent task.
The initial intake geometry and encounters existed, but anonymous slabs did not communicate
the confiscation, records and transfer spaces in the mission brief.

## Outcome

Give the safe entry, property bay, intake hall, maintenance route, records balcony
and prisoner lift distinct landmarks. Issued lockers, equipment panels, signs,
practical light and an absurd complaint notice establish a functioning Union
facility. No Inheritance contact or premature Latch rescue. Keep combat readable.

## Architecture and limits

- Extend `MapPresentation` with optional bounded face decorations. Authoring
  references a solid's stable ID; the wire uses its validated index. Face, centre,
  size and registered kind describe a thin panel attached to that solid. No
  scripts, URLs, model paths, arbitrary text or external resources in map data.
- One shared Rust validator owns finite dimensions, face bounds, the total panel
  limit and the smaller light limit. Every map-info consumer uses it. Mirror the
  boundary in `MapGeometry` and test both. Geometry and combat remain unchanged.
- Old payloads omit the optional field. Older clients already ignore additional
  presentation fields and can retain base surfaces. The new visual metadata does
  not change gameplay capability or collision geometry versions.
- A focused client builder called by `ArenaCover` owns registered panel styles,
  face transforms, labels and lights. Panels stay on their host face. Anything
  substantial enough to block a body or shot must be an authoritative solid.
- New sign copy uses stable keys in Godot's existing translation mechanism and
  an English gettext catalog. This starts world-text localization; it does not claim
  the menus, campaign scenes, additional languages or locale selection are done.
- Use original procedural pixel panels and existing licensed fonts. Union bone,
  green, steel and restrained red remain canonical. No paid generation.

## Verification and completion

Reject unknown kinds/hosts, nonfinite values, oversized/out-of-face rectangles,
excess panels/lights and malformed wire data. Prove all six face transforms and
localized label bounds with headless checks. Prove old map compatibility and
unchanged navigation/combat. Inspect close signs, both routes, practical lighting,
enemy contrast and both graphics backends through the live server. Refresh the
general gallery, retain coverage and CI gates, and record evidence before calling
the detail pass complete. Objectives, interactive terminals, extraction, saves
and full mission population remain separate work.

Current official [translation configuration](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html),
[gettext catalogs](https://docs.godotengine.org/en/stable/tutorials/i18n/localization_using_gettext.html)
and [Label3D](https://docs.godotengine.org/en/stable/classes/class_label3d.html)
were checked on 2026-09-20. Imported catalogs require project registration and a
fallback language. Text must remain separate from decorative pixels. A first-import
check rejected CSV's missing generated translation resource; the source-readable
gettext catalog avoids that bootstrap dependency and preserves the repository's
rule that generated translation binaries remain ignored.

## Implementation and local evidence, 2026-09-20

The M01 document now has 30 face details, including eight fill lights. Solid IDs
resolve to validated wire indices. Optional metadata preserves old map messages;
it changes no collision solid, supply, spawn, encounter or navigation route.
The MCP adapter preserves these details in observations and rejects malformed
replacements without overwriting its previous map. The brain and playtest clients
stop before acting on an invalid panel host.

`ArenaCover` delegates panels to `arena_decoration.gd`. `map_decoration.gd` mirrors
the Rust boundary and defines the six face transforms. `world_sign.gd` measures
translated glyphs and fits them within their panels. The English PO catalog loads
before any import cache exists. This is an initial world-text seam, not completed
localization of menus, objectives or cutscenes.

The first rendered comparison exposed inconsistent OpenGL/Vulkan color handling.
Palette uniforms now use `source_color`, matching the existing world materials.
This was a real visual finding; the initial captures are superseded by the final
pair. See the official [shader language reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html),
checked 2026-09-20. The fixtures are bounded shadowless fill; they do not establish
a renderer benchmark or final lighting quality.

Local Rust verification passes: strict Clippy, workspace release build, 667 tests
with two existing ignores, and 95.72 percent unfiltered line coverage. The 90
percent floor remains intact. All 23 Godot harnesses pass, including malformed
panel data, bounds, both budgets, six face orientations, map rotation and actual
text geometry under a longer runtime translation. The checker failure-injection
suite and dependency license, source and ban checks pass. No new dependencies or
paid requests were used.

The 16-fighter, 1200-tick seeded determinism/budget gate and four-client live
smoke pass. The unchanged six-map mixed-client assertions also pass:

| Map / seed | Clients | Frags | Spawn deaths |
|---|---:|---:|---:|
| Arena Duel / 67 | 2 | 6 | 0 |
| Compliance Yard / 42 | 6 | 26 | 1 |
| Directive 17 / 19 | 6 | 27 | 3 |
| Sector 9 / 42 | 8 | 29 | 4 |
| Reclamation Gulch / 42 | 12 | 46 | 2 |
| Tripoint Works / 42 | 16 | 79 | 10 |

Reports: `.agents/playtest/facility-roster/`. Spawn deaths remain a multiplayer
quality gap despite passing the existing statistical gate, as recorded in
[opening spawns](opening-spawns.md). This cosmetic change does not claim to
improve that rate or establish public-server capacity.

The twelve-state facility tour walks both stairs, defeats the three introductory
enemies and inspects the signs, desk, lift and service spaces. Final captures are
`.agents/qa/m01-facility-final-gl/` and `.agents/qa/m01-facility-final-vk/`, on
Windows/AMD Radeon 780M. Both final contact sheets, close sign views and enemy
contrast were inspected. [Dated prototype captures](../screenshots/prototypes/README.md)
preserve the entry and twelve-state sheet. The 21-state general tour was refreshed
at `.agents/qa/m01-facility-regression/`; its contact sheet and both shot strips
were inspected. No NVIDIA or macOS rendered evidence follows.

Remaining scope: reviewed character production, fuller encounters and room
detail, authoritative terminal interaction, mission objectives, extraction,
checkpoints, opening scenes and fresh-player pacing. The complaint notice targets
the confiscation procedure. It does not make correction or captive suffering a
punchline, expose the Inheritance early or turn optional radio into the story.
