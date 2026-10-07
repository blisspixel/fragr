# Island water rendering

Status: **in flight**. Research checked 2026-10-06. Local implementation has an
inspected renderer measurement; 64-player match performance is not established.

The intended look is calm, working coastal water: muted teal depth, pale foam,
pixel-sized wave accents and readable boat wakes. Repaired docks, civilian
transport and salt-worn materials belong to the same inhabited world as the
campaign. The retro surface treatment does not lower the animation, lighting,
readability or performance bar.

## Research and decision

[Godot GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html)
identifies fragment cost, texture reads, draw calls and overlapping transparency
as important costs. Reusing one opaque material lets water participate in normal
depth rejection. A map-load depth texture supplies coastal color and foam without
sampling the screen or rendering another camera.

[Godot screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
documents the required screen copy and the absence of transparent objects in the
3D screen texture. Refraction and planar reflections are therefore deferred until
measured evidence justifies their cost and visual tradeoffs.

[GPU Gems water modeling](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models)
explains bounded sums of waves and analytic surface derivatives. The local shader
uses that general mathematical approach with independent original parameters,
world-space pixel bands and distance fading. It uses portable shader operations;
no vendor-specific rendering path is required.

## Implemented bounds under review

- Five registered water patches plus four decorative horizon strips share one
  opaque material and one 512 x 512 R8 coast texture, 256 KiB before driver overhead.
- Depth is rasterized from authoritative solids once when the map changes.
- Water has two broad wave phases. Balanced and High add a fine ripple and 4.5 cm
  visual displacement. The simulation surface remains the registered flat level.
- Performance, Balanced and High cap nearby boat wakes at 2, 4 and 8. Only moving
  boats within 180 m qualify. Selection updates at 10 Hz; shader motion remains
  continuous. The current fleet contains two boats.
- Foam, depth color and distant detail fading remain on every preset. There are
  no water shadow maps, additional reflection cameras or per-player fluid grids.
- Server swimming and hull support use registered water regions. Cosmetic waves
  never move a player, change a shot or alter boarding eligibility.

## Acceptance still required

Inspect shore, swimming, turning boats and a low aircraft pass in motion on the
actual renderer. Verify shore return, wave seams, horizon stability, readable
occupants, wake removal and quality changes. Compare identical camera sweeps
with water enabled and disabled, with 0 and 64 visible animated participants.
Record hardware, renderer, resolution, preset, draw counts and frame-time
percentiles. Repeat server tick and network delivery measurements with 64 actual
fighters separately. A 64-socket run containing spectators is not that evidence.

The initial measurement target is under 1 ms incremental water frame cost at
1280 x 720 on the available integrated GPU, subject to actual measurement. This
is a budget target, not a claim. Renderer support and one GPU result do not prove
other platforms or a 64-player production server.

## Initial renderer evidence

The clean October 6 Compatibility/OpenGL pass used an AMD Radeon 780M at
1280 x 720, no V-Sync or frame cap. Production MapInfo, the actual pawn presenters
and two moving boat presenters ran a repeatable camera sweep. Each case discarded
60 warmup frames and retained 180 frames. The table describes 64 animated body
presenters, not 64 connected players or a server load test.

| Preset | Water | GPU median ms | GPU p95 ms | Frame p95 ms | Maximum draw calls |
|---|---|---:|---:|---:|---:|
| Performance | Off | 0.647 | 1.220 | 2.671 | 168 |
| Performance | On | 0.808 | 1.268 | 2.520 | 176 |
| Balanced | Off | 1.126 | 1.910 | 2.951 | 168 |
| Balanced | On | 1.149 | 1.841 | 2.827 | 176 |
| High | Off | 1.410 | 2.148 | 3.313 | 168 |
| High | On | 1.420 | 2.602 | 3.224 | 176 |

The observed median difference is below the initial budget, but tail variance
and the short sequence prevent a broad performance conclusion. Later art and
gameplay changes require another composed measurement. GPU timing comes from
the viewport's measured render time, enabled explicitly, as specified in
[RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu).
Raw zero-body and 64-body results, hardware and MapInfo fingerprint are retained
in [measurement.json](../evidence/water-20261006/measurement.json); the inspected
[shore view](../evidence/water-20261006/shore-high.png) records this development
layout before the subsequent wall and terrain art pass. The island still needs
landscape and encounter dressing. The earlier run with missing optional solid
bottom handling is rejected as final evidence; its private logs are retained.
