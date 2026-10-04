# Union billboard shadow repair, 2026-10-04

Status: implemented, locally rendered and complete client passed. Integration
CI and package acceptance remain separate gates. Spend: $0.

## Defect and correction

Ordinary close-side approaches exposed diagonal dark bands across both the
selected Jammer and a prepared candidate. The custom fixed-Y billboard used
`INV_VIEW_MATRIX` for both camera-facing axes, including its light-camera shadow
draw. Its visible body and its shadow caster therefore used different planes.
The correction uses `MAIN_CAM_INV_VIEW_MATRIX` for those two axes, matching the
[pinned engine's fixed-Y material implementation, lines 1178-1187](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/resources/material.cpp).
The [upstream correction](https://github.com/godotengine/godot/pull/72638) explains
why the main camera must be retained in the shadow pass.

No atlas, normal map, model, light, camera, culling, collision, mission or combat
rule changed. Lighting, shadow reception, shadow casting, opaque alpha discard,
nearest sampling, silhouette edging, red identification and hit tint remain.
This repairs the shared Union sprite shader. It does not select the separately
prepared Jammer candidate or resolve the current M03 controller route failure.

## Ordinary played controls

The [original selected-body view](../screenshots/union-billboard-shadows-20261004/baseline-original-side.png)
and [main-camera control](../screenshots/union-billboard-shadows-20261004/baseline-maincamera-side.png)
use the same range map, ordinary-input route, controller, native server, camera
setup and selected atlas. The correction removes the bands while retaining the
venue's lit body tone. Normal network tick and contact timing differs between
runs, so these are matched scenarios rather than pixel-identical actor poses.

Four private controls covered the selected and candidate bodies, each with
shadow reception disabled separately and then with only the two main-camera
axes corrected. All four completed the same five states and nine arrivals,
real contact stops, return walk and finite equipment assertions. The receiver-off
controls identified the shadow path but are not the production solution.
The main-camera controls retained reception and casting. All four renderers
exited 0 with clean logs and owned server cleanup. Baseline renderer PIDs were
35424 and 19808; candidate PIDs were 35848 and 30460.

## Fixed-camera regression

`test_union_billboard_shadow.gd` uses the actual shader on a fixed-Y Sprite3D,
a uniform matte plate, an immutable side camera and a directional shadow light.
It constructs the old shader by reversing only the two camera-matrix references.
The old and corrected images are taken within one unchanged scene. A separate
casting-off control and an invisible shadow-only blocker test actual retained
casting and receiving.

| Check | Required | Measured |
| --- | --- | --- |
| Original interior plate luminance range | Above 0.06, reproduces defect | 0.351521 |
| Corrected interior plate luminance range | Below 0.035 | 0 |
| Floor pixels darkened by corrected body casting | Above 200 | 2,343 |
| Sprite-only samples darkened by external blocker | Above 100 | 525 |

The [original fixed camera](../screenshots/union-billboard-shadows-20261004/original-fixed-camera.png)
shows the misplaced diagonal self-shadow. The [corrected plate](../screenshots/union-billboard-shadows-20261004/corrected-fixed-camera.png)
is uniform, with its real floor shadow still visible. The
[casting-off control](../screenshots/union-billboard-shadows-20261004/casting-off-control.png)
removes that floor shadow, while the
[external blocker](../screenshots/union-billboard-shadows-20261004/receiver-blocker-present.png)
shades the corrected sprite itself. The simple fixture's floor is a test surface,
not a proposed venue finish.

The actual Compatibility renderer was the AMD Radeon 780M under the pinned
4.7.2-stable engine. Renderer 18452 exited 0 with all rendered gates passing,
clean error logs and no retained owned process. The
[receipt](../screenshots/union-billboard-shadows-20261004/receipt.json) records
shader, harness and image hashes. This is inspected hardware evidence for one
renderer, not a claim of every graphics platform.

The first fixture attempt, renderer 24692, exited 1 and remains retained
privately. Its directional light faced the plate's back, leaving both plate
ranges at 0 and the receiver test inconclusive. The floor-casting test passed.
Only the fixture light was corrected to face the tested side; every pixel gate
and the fixed old/new framing remained unchanged. No production light changed.

Headless import, parse and the new harness's boundary checks passed with clean
exit. The headless marker explicitly states that rendered pixel gates require a
framebuffer. The complete client checker parsed all 258 scripts and passed all
122 harnesses on source `8253dd6`, exited 0, and produced no error, failure or
leak lines. Its owned process 27436 ended. Local-launch checks used a private
verified native server with SHA-256
`8c48423259ade27627c4a3246f2b1eb79db3b0b1b6250222147d010c9afb33a6`;
the historical root binary was not overwritten.

Current main `621bd1b90e3b8fa4063215d9854745d60608dd95` was then merged
normally as `94b1e437b7131ee7e01070b8e0a64ea901a8b5b0`. Its additional
precision-reference documents and images change no runtime source. Final import
passed with exit 0 and clean logs. The actual captured shader and harness hashes
still match the final source. Integration CI and package gates remain pending;
the separate art candidate remains parked.
