# Environmental water foundation

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. External spend: $0.

## Goal and scope

Add original animated pixel water and useful ground detail to Low Water through
the existing map presenter. This is shallow water on the existing concrete
floor, not a swimming route. The current map has no authored basin, lower water
terrain or swimming authority. No wire, authored map bytes, collision, movement,
combat, dependency or release changes are needed.

This lane owns `arena_water.gd`, its spatial shader and focused harness,
`arena_cover.gd` integration, and this plan. Integration owns the plan index and
final tours. The water helper is reusable, but automatic venue placement is
limited to the registered map 1004 Low Water prototype and the validated map
1005 No Forwarding Address workshop, trench and freight patches. Each venue
retains its own bounded placement; other maps require explicit authoring.

## Registration and presentation

Inspecting the actual M04 solids and both prepared clinic worlds gives three
clear, flat cosmetic footprints: tram street center (5, -14), 3.5 by 2.2 metres;
market center (4, 11), 4.0 by 2.4 metres; court center (-8, 25), 5.0 by 3.0
metres. All planes lie at y=0.014, with irregular pixel edges and a shallow wet
shore. These occupy existing ground, never a solid footprint, awning, staircase,
clinic patient route, supply or departure control. Any current solid projected
into a footprint refuses that patch. Venue identification also requires the
registered notice board, market canvas and water tank landmarks. Unsupported or
malformed maps have no added water.

Each patch uses one opaque spatial shader with nearest world-space pixel cells,
stepped animation, directional ripples and crossing crest bands in the existing
blue-green Low Water palette. Discard only masks the outer puddle shape. Keep
ordinary depth tests; no alpha/refraction/screen-depth dependency or geometric
wave displacement. Flush drain grates, scattered paper and dark wet shores add
local ground detail without adding apparent cover or new walkable props.
Meshes remain on the existing world visual layer, with no collision nodes.

Godot 4.7 APIs checked 2026-09-30 against primary documentation:
[spatial shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
and [shading language](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html).
Use ordinary vertex world coordinates, source-color uniforms and opaque
fragment output supported by Compatibility. No version or renderer pin changes.

## Verification and success criteria

Headless checks prove venue registration, finite bounded patch dimensions,
solid rejection, no collision descendants, immutable input geometry, repeated
map rebuild cleanup, unsupported-map refusal and preserved world layers.
An isolated Compatibility SubViewport captures the real integrated ground at
two animation times and requires actual changed water pixels, readable shore
and drain detail, and normal depth occlusion. Inspect its frames and motion
strip before claiming a visible improvement. It never loads gameplay or captures
the desktop. Integration then imports catalogs/scripts, runs full checks and
refreshes ordinary M04 and standard tours when release ownership is free.

Do not infer swimming, physical water, universal venue coverage, GPU performance
or fresh-player quality from this cosmetic foundation. Final commands, captures
and limits will be recorded here.

## Work record

The helper, opaque shader, integrated live ArenaCover hook and focused harness
are implemented and source is frozen for final integration. All three placements
passed against the current 84-solid M04 authored geometry. Each patch has one
water plane, a flush seven-bar drain and two small damp paper surfaces, 11 meshes
total. Water has an irregular pixel shoreline and four restrained Low Water
colors. Animation advances eight times per second with a continuous periodic
32-second clock, without modifying any vertex or authoritative solid.

Pinned headless import passed cleanly, exit 0:
`.agents/environment-water-20260930/import-first.log`. Focused headless and
isolated Compatibility rendering both passed cleanly, exit 0:
`headless-final.log` and `rendered-final.log` in that directory. The raster check
used AMD Radeon 780M and actual ArenaCover with the authored geometry. Across
two fixed times, 1,632 pixels changed; opaque geometry correctly hid the water.
The first strip assembly had mismatched image formats and its log is retained
as failed evidence. The corrected final run uses the actual viewport format.

Inspected `water-street-00.png`, `water-street-02.png`,
`water-motion-strip.png` and `water-depth-occluded.png` show real blue-green
floor puddles, stepped moving crest patterns, dark wet edges and small drain
detail. The isolated camera looks down from 3.5 metres at the street patch;
this is shader and integrated geometry evidence, not an ordinary first-person
route or performance measurement. World depth and input geometry stay intact.
These earlier receipts cover M04. The M05 increment adds three separately
registered floor patches through the same helper and collision rejection.
Other venues have no automatic placement. The earlier full checker passed all
163 scripts and 76 harnesses in `.agents/m04-buildout-20260930/godot-verified.log`.
The actual 23-state M04 ninth tour passed; inspected market frames show these
patches in first-person play. The parent prototype plan records that receipt
and the remaining mission acceptance. External usage is $0.
