# Union billboard shadow orientation

Status: Implemented, locally rendered. 2026-10-04. Spend: $0.
Base: main `53b5c0367122d2cd8a7d0eb34ad187cea32ffabc`.

## Defect and boundary

Ordinary close east approaches show diagonal shadow bands on both the selected
Jammer and an independently prepared candidate. Four private controls retained
normal movement, body contact, alpha, camera and lighting. Disabling reception
removed the bands; using the main camera for both fixed-Y billboard axes also
removed them while retaining reception and casting. The old and corrected
live-camera frames have slightly different normal tick/facing timing; they are
not pixel-identical captures.

The [pinned engine material implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/resources/material.cpp)
at lines 1178-1187 uses `MAIN_CAM_INV_VIEW_MATRIX` for fixed-Y billboards during
shadow passes. The current custom Union shader uses `INV_VIEW_MATRIX`, the
camera for the current draw pass, so its shadow draw faces the light camera.
The [upstream correction](https://github.com/godotengine/godot/pull/72638)
establishes the reason for retaining the scene camera in a shadow pass.

Own only this unique plan/evidence, two shader-axis replacements and a focused
regression harness. Preserve alpha discard, nearest sampling, silhouette edge,
normal-map support, lighting, receiving, casting, bounds and every game rule.
No source/atlas/candidate selection, camera relocation, culling workaround,
lighting compensation or map change. The separate failed current M03 ordinary
route remains open; this rendering repair is not a combat or mission fix.

## Implementation and acceptance

1. Replace only the two billboard-axis references with the pinned engine's
   main-camera matrix. Retain original shader bytes privately for a control.
2. Build a fixed-camera rendered fixture with broad flat painted sprite regions,
   side lighting and the real shader. Require a stable interior plate rather
   than accepting diagonal self-shadow bands. Verify the original shader fails
   that gate in the same fixed fixture.
3. Compare floor pixels with actual casting on/off, then sprite pixels with a
   real light-path blocker present/absent. Prove corrected casting and reception
   remain, rather than disabling both to conceal the defect. Use identical
   camera/geometry/body/material/light poses within these comparisons.
4. Headless runs validate the shader boundary and clearly distinguish it from
   rendered proof. Actual render requires clean exit, all pixel gates and
   explicit resource retirement. Preserve every failed fixture receipt.
5. Inspect full-size corrected fixture and retained ordinary controls. Merge
   current main before the final source freeze, run complete client checks and
   leave eight CI and package acceptance to the integration lane.

This branch is separate from the prepared Jammer art branch. Preserve its
accepted source and failed full-route evidence without promoting its atlas.

## Local evidence

The fixed-camera rendered fixture passes unchanged pixel gates: original plate
range 0.351521, corrected 0, 2,343 floor casting pixels and 525 sprite receiving
samples. Renderer 18452 exited 0 cleanly and retired. The first ambient-only
backside-light fixture failed and remains retained. Headless import, parse and
boundary checks passed; the complete client checker is in flight.
See [the evidence](../evidence/union-billboard-shadows-20261004.md) for controls,
framing, thresholds and the separate current M03 route limitation. Final
integration CI and package gates remain pending.
