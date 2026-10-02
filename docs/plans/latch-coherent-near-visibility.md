# Latch coherent near visibility

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. Inspected close-rig visibility, distant opacity and world shadows pass.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

An actual Low Water windup capture shows disconnected beige and black polygons
above the market. Its following motion frames reveal the nearby live Latch
figure. The current live-only shader discards each fragment within a 0.7-metre
view-depth plane. A plane passing through the faceted head can retain separate
far faces while removing their connecting geometry. The existing raster test
checks one close torso pixel and one upward view; it does not cover the observed
intermediate distance and offset transition.

## Reproduce before changing runtime

Use the actual `LatchView` rig and current material connector in an isolated
Compatibility viewport. Sweep ordinary eye height, close horizontal distance,
camera offset and upward pitch. Retain original and current frames, measured
foreground bounds and a motion board under ignored diagnostics. Identify an
actual reproduced partial-head case before changing production code. No API,
cash charge, server mutation, position override in gameplay or rig redesign.

## Bounded repair

Keep the live-only opt-in and unchanged geometry, materials, ward tableau and
authoritative body. Replace independent close-surface visibility with a coherent
camera-relative near-figure transition. Use the actual render camera, preserve
ordinary opaque distant presentation and shadow behavior, and avoid changing
combat evidence or general particles. Confirm the exact threshold and shader
inputs from the reproduced actual rig rather than guessing from a still.

## Gates

The focused harness must retain existing material, geometry, connector,
restoration and ward checks. Add a genuine rendered transition regression for
the reproduced offset/upward camera, safe close aiming and visible distant full
rig. Inspect original and corrected motion boards and require clean logs, PASS
and owned-process cleanup. Parent owns the subsequent ordinary gameplay tours,
whole client checker, public screenshots, CI and release. A library raster proves
the visual seam, not gameplay completion or general GPU support.

## Actual cause and repair

The original actual-rig raster reproduces the disconnected faceted head and arm
pieces at eye height 1.6 metres, upward pitch 0.25 radians and horizontal camera
distance 0.75 metres. The unmodified rig has 16,528 foreground pixels; the former
depth-plane shader retains 1,346 isolated pixels. An offset upward view also
reproduces the fragments. The capture uses the same six-facet head and bone/steel
materials as the live chassis, rather than synthetic effect quads. No Notary or
shot-effect source changed.

The live material now uses one shared world torso anchor, 1.2 metres above the
figure's feet. The actual render camera supplies distance in the shader. The
whole figure clears within 1.1 metres of that anchor, gains ordered 4 by 4 pixel
coverage through the short transition, and stays fully opaque beyond 1.35
metres. A moving chassis refreshes its existing material anchors only when its
world position changes. Joint poses, geometry, the ward tableau and authoritative
body remain unchanged. The shadow pass keeps the complete opaque silhouette.
Godot's [spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
was checked 2026-10-01 for the actual camera transform and shadow-pass distinction.

## Evidence

All logs and diagnostic frames are retained under
`.agents/m06-buildout-20261001/`. The original 32-view distance, offset and pitch
sweep closed cleanly. The final 16-view regression checks zero intrusive close
pixels, monotonic coverage, identical coverage decisions across every chassis
part, unchanged projected silhouette, completely opaque distant figures at both
offsets, translated moving anchors and actual retained shadows on a lit floor.
The saved original and corrected motion boards and shadow frames were inspected
in the pinned Compatibility renderer on AMD Radeon 780M.

`latch-near-corrected-render-final.log` has both rendered and harness PASS markers,
exit 0 and empty stderr. Its owned process closed normally. A negative control
substituting the exact former shader into that same rig/harness fails the close
fragment and coherent-coverage gates with exit 1, retained in
`latch-near-original-negative.log` and its error log. The initial diagnostic
board-format error and initial overstrict fade-boundary fixture failure are also
retained; neither was completion evidence. Ordered coverage quantizes its end
states, so the final gate measures full-figure coherence and the actual visible
transition instead of assuming every nominal horizontal distance is partial.

Focused `test_latch_near_clip`, `test_actor_state` and `test_m02_ward` headless
harnesses all pass with clean logs. Parent owns ordinary Low Water and standard
tour confirmation, the whole client checker and shipping status.
