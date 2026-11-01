# Graphics tiers and auto settings

**Status:** built in wave 22 (2026-11-01): five tiers, the tuner, the in-match
governor, the Deck profile, the Compatibility trial and both docs pages
([GRAPHICS.md](../GRAPHICS.md), [BENCHMARK.md](../BENCHMARK.md#tiers-and-auto-settings)).
Proven by logic harnesses and inspected captures only. Not done: every
hardware-matrix row and gate measurement, the venue factor table, per-venue
volumetric fog and SSR (no venue opts in yet), SDFGI, the export shader baker,
a finer pixel target for large displays, and every Deck fact marked unverified.
The audit below describes the build before tiers.
**Spend:** $0. Local only, no telemetry, no service.
**Owner:** one lane carries tiers, the tuner, the governor and both docs pages end to end, and plays the build on every machine it claims.

## Goal

fragr runs on NVIDIA, AMD, Intel and Apple Silicon across Windows, Linux and
macOS, holds a steady frame rate on a weak machine, and looks its best on a
strong one, without the player touching a menu. Before 1.0:

- **Floor.** On a weak machine the lowest settings hold a 1% low of 60 fps or
  more at 1280x720 output.
- **Ceiling.** On a strong machine the auto settings pick the highest quality
  and 3D resolution that still hold a 1% low at the player's target (60 by
  default; 90, 120, 144 or the display's refresh by choice).
- **Steam Deck.** A steady 40 fps in the Deck's 40 Hz mode at 1280x800 on
  auto-chosen settings, legible HUD and menus at 800p, full controller play,
  with a 60 fps profile where it holds (see Steam Deck below).
- **Reference iGPU gate.** The existing 1.0 bar in `docs/ROADMAP.md` (line
  232): 1% low at or above 60 fps at 1080p on a reference integrated GPU, no
  frame over 50 ms after warmup. Proposed reference: Radeon 780M.

The pixel look is part of the art. Integer world-pixel upscaling, nearest
filtering and the optional value dither are art settings, not performance
knobs the tuner may quietly spend.

## What exists (audit, 2026-10-31, branch wave20-loop)

### Presets and options

- Three presets in `client/scripts/render_quality.gd`, set by
  `video/quality` 0 Performance, 1 Balanced, 2 High (`settings.gd:26`,
  validated to `[0, 1, 2]` at `settings.gd:200`).
  - MSAA: off, 2x, 4x (`render_quality.gd:104-109`); off whenever FSR 2 owns
    anti-aliasing (`:105`).
  - Positional shadow atlas 1024, 2048, 4096, and the directional atlas set
    to the same size (`:110-111`).
  - SSAO off, Low, Medium with fixed radius, intensity and half-size sampler
    (`:119-129`). Gated by `supports_ao`, true on Forward+ and Compatibility
    (`:22-23`), which matches 4.6 adding SSAO to Compatibility.
  - Glow on from Balanced, only where the venue authored an intensity
    (`:124`).
  - Practical fixture shadows on from Balanced; omni lights use dual
    paraboloid on Balanced where the renderer has it, cube otherwise
    (`:135-149`). Island water takes the quality value directly
    (`island_water.gd:72-75`).
  - `preset_features` (`:43-58`) prints what a preset changes; the benchmark
    Details reuse it.
- Resolution: `RESOLUTION_HEIGHTS` 0 (native), 720, 900, 1080, 1440, 2160
  (`:5`); `render_scale` divides by output height and clamps to 0.1..1.0
  (`:60-63`). Fullscreen is the default (`settings.gd:20`) and native height
  is the default (`settings.gd:25`).
- Upscaling: Standard (bilinear), FSR 1, FSR 2 (`settings.gd:27`,
  `render_quality.gd:98-103`); FSR is Forward+ only (`:19-20`) and the
  Graphics page disables it with a note elsewhere (`settings_panel.gd:123-129`).
- Pixel look: `PIXEL_TARGETS` 0 off, 540 Fine, 360 Medium, 270 Chunky world
  lines (`render_quality.gd:9`); the factor is the nearest whole number for
  the output (`:70-73`); a factor above 1 forces `SCALING_3D_MODE_NEAREST`
  and a scale of at most 1/factor, and replaces FSR (`:93-97`). Default Fine
  (`settings.gd:34`). Fine is 2x at 1080p, but `roundi(1440 / 540) = 3`, so
  1440p renders 480 world lines, fewer than 1080p; 2160p renders 540; 800p
  (Steam Deck) and 720p render natively.
- Dither: an ordered 4x4 Bayer value dither on a canvas layer under the HUD,
  aligned to the world pixel grid, default off (`render_quality.gd:153-176`,
  `client/assets/shaders/value_dither.gdshader`, `settings.gd:35`).
- Display page: window mode, resolution, FOV, frame cap
  0/30/60/90/120/144/165/240/360 (`settings_panel.gd:479-487`), V-Sync toggle
  (`settings.gd:349-351`, default off), FPS counter with frame time and 1% low
  (`settings.gd:24`). `Engine.max_fps` applies the cap (`settings.gd:331`).
- The planned options menu and Ultra tier
  (`docs/plans/graphics-options-and-lighting.md`) are not built: Custom
  preset, AA choice, shadow levels, SSIL, SDFGI, SSR, volumetric fog,
  gamma, HDR output, effects density.

### Lighting

- `client/scripts/arena_sky.gd` owns one `Preset` per venue (about 28, lines
  131 to 788): procedural sky, flat ambient colour (deliberately not sky
  ambient, `:807-822`), depth fog plus thin height haze (`:828-833`), Filmic
  tonemap and adjustments (`:837-842`), small authored glow (`:844-861`), key,
  fill and ember lamps (`:870-895`), and an actor-only view fill with no shadow
  (`:898-920`). Quality-dependent work stays in `render_quality.gd`.

### Project settings

- `client/project.godot:235-239`: `rendering_method="forward_plus"`,
  `limits/opengl/max_lights_per_object=16`, ETC2/ASTC import. No
  `rendering_device/driver.*` key, so Windows uses the setting's literal
  default (Vulkan) and the 4.4+ automatic fallbacks (Vulkan to D3D12 to
  OpenGL 3) are at their defaults (true). No MSAA, TAA, scaling or shadow
  project defaults are set; runtime code owns them. Stretch mode
  `canvas_items`, aspect `expand`, design size 1920x1080 (`:26-31`).
- No export shader baker is configured (`client/export_presets.cfg` has no
  shader or bake keys).

### Benchmark and frame stats

- `client/scripts/benchmark_run.gd`: records 28 s of a local ten-bot Larak
  Lot match (`CAPTURE_SECONDS`, `:18`), stops the host, then for each preset
  replays the same snapshots on a time-based orbit camera with 8 s warm-up and
  20 s scored (`:16-17`). V-Sync and the cap are off while measuring
  (`:88-97`). Intervals come from `Time.get_ticks_usec()` per drawn frame
  (`:276-287`). It fails cleanly on resize, stalls or load timeouts
  (`:250-274`). Reports carry adapter, vendor, API version, engine, renderer
  and driver (`:411-416`) and a compatibility key (`:434-455`).
- `client/scripts/frame_stats.gd`: mean, percentiles, three 1% low and 0.1%
  low definitions, frames at or over 33 and 50 ms, stutter count
  (`:17-77`). The player-facing 1% low is `low_1_count_fps`
  (`benchmark_results.gd:170`).
- `docs/BENCHMARK.md:967-1043` documents the player benchmark contract; the
  stutter traces (`:1045-1090`) already read
  `viewport_get_measured_render_time_cpu/gpu` and pipeline compilations.
- Results so far, Radeon 780M (Ryzen 7 7840U):
  - Windows, Compatibility (OpenGL 3.3), 1280x720, ten-bot replay
    (`docs/evidence/benchmark-preset-comparison-20261006.md:17-27`): average
    567.9 / 384.4 / 383.9 fps and 1% low 100.1 / 87.4 / 85.9 fps for
    Performance / Balanced / High.
  - Windows, OpenGL, 1920x1080, look pass increment 1
    (`docs/plans/look-pass-boomer.md:121-139`): GPU 2.4 to 8.0 ms across
    presets and views; M01 intake High 8.83 ms mean, 13.74 ms p95.
  - Linux, Vulkan and OpenGL, 1920x1080, Balanced GPU ms 8.3 to 16.1
    (`look-pass-boomer.md:234-248`) under heavy host load; the plan itself
    says those runs cannot resolve a 10 percent change.
  - No other GPU, no Forward+ player benchmark result, no Steam Deck, no
    Apple, NVIDIA or Intel result exists.

### Auto-detection

- None. The adapter name is read only for display and reports
  (`boot_menu.gd:1073`, `benchmark_run.gd:415`, `game_manager.gd:1883`,
  `qa_tour.gd:3649`). Nothing recommends or applies settings from hardware or
  measurement.

### Renderer coverage in practice

- Capture tooling defaults to Compatibility: `tools/qa_tour.sh:181` uses
  `FRAGR_RENDER_DRIVER:-opengl3`, and `qa_watch.sh`, `capture_tip_screenshots.sh`
  and `capture_jammer_dish_proof.sh` force `opengl3`. Shipped players run
  Forward+. Most inspected stills are therefore from the renderer players do
  not get by default.
- Every shader in `client/assets/shaders/` and `client/art/` is spatial with
  forward render modes, or canvas; the only screen read is the dither's
  `hint_screen_texture` (canvas). None reads `hint_normal_roughness_texture`
  or uses CompositorEffects, so the Compatibility renderer can draw them all
  (the look pass captured both renderers).

### Steam Deck readiness

- Gamepad bindings exist (`input_bindings.gd`) and `menu_focus.gd` gives one
  focus target across mouse, keyboard and pad.
- Text: design canvas 1920x1080 with `canvas_items`/`expand`, so at 1280x800
  the UI scale is min(1280/1920, 800/1080) = 0.667. `MenuTheme.BODY` 24
  becomes 16 px; the smallest literal found, 16 (`m19_works.gd:928,939`),
  becomes 10.7 px, above Valve's 9 px minimum and below its 12 px
  recommendation. HUD style sizes were not fully audited.
- No on-screen keyboard path, no Deck detection, no 16:10 capture state.

## Godot 4.7.2 facts the design rests on

Verified against the 4.7.2-stable class reference and 4.7 manual (Sources).

- **Renderers.** Forward+ (default), Mobile, Compatibility. The method and the
  RenderingDevice driver are read at startup; there is no runtime setter.
  Switching takes an override file (`override.cfg` beside the binary, or
  `application/config/project_settings_override` pointing at `user://`) and a
  restart (`OS.set_restart_on_exit()` or `OS.create_instance()`).
  `--rendering-method`, `--rendering-driver` and `--gpu-index` exist on the
  command line.
- **Fallback.** Since 4.4, `rendering_device/fallback_to_opengl3` (default
  true) starts Compatibility when Vulkan, D3D12 and Metal all fail, instead of
  an alert. `fallback_to_vulkan` and `fallback_to_d3d12` cover the other
  directions. Read the outcome with `get_current_rendering_method()` and
  `get_current_rendering_driver_name()`.
- **Drivers.** Linux: Vulkan only. macOS: Metal on Apple Silicon (native
  since 4.4; Metal 4 on macOS 26+), Vulkan through MoltenVK on Intel Macs.
  Windows: Vulkan or D3D12; new 4.6+ projects default to D3D12, but fragr's
  project has no key and runs Vulkan. Godot's own pages disagree on D3D12
  maturity and an open issue reports D3D12 far slower than Vulkan, so keep
  Vulkan on Windows unless measured otherwise.
- **Minimums.** Forward+ and Mobile need Vulkan 1.0, D3D12 feature level
  12_0 or Metal 3 (for example Intel HD 510). Compatibility needs OpenGL 3.3
  or D3D11 through ANGLE (for example Intel HD 2500).
- **Compatibility lacks:** SSIL, SDFGI, VoxelGI, SSR, volumetric fog, TAA,
  FSR 1 and 2, FXAA and SMAA, decals, debanding, Adaptive and Mailbox V-Sync,
  PCSS, the normal-roughness buffer, CompositorEffects, MSAA 2D; it has an
  RGBA8 colour buffer and 24-bit depth, its own glow with the Screen blend
  only, multipass shadowed lights, 8 omni plus 8 spot per mesh by default
  (fragr sets 16) and 32 renderable lights per frame, and refuses dual
  paraboloid omni shadows (already handled). It keeps SSAO (4.6+), MSAA 3D,
  glow, depth and height fog, LightmapGI rendering, screen and depth textures
  in shaders, and nearest 3D scaling (both renderers captured in the look
  pass).
- **Scaling modes 4.7:** Bilinear, FSR (1.0), FSR2 (2.2; native TAA at scale
  1.0), MetalFX Spatial and Temporal (Metal only), Nearest (new in 4.7). No
  FSR 3, DLSS or XeSS. Only Bilinear supersamples above 1.0.
- **Anti-aliasing:** MSAA 2x, 4x, 8x; screen-space FXAA or SMAA (SMAA since
  4.5; not Compatibility); TAA Forward+ only and still ghosts on particles and
  skinned meshes.
- **Shadows:** directional and positional atlas sizes and soft filter quality
  are settable at runtime (`directional_soft_shadow_filter_set_quality`,
  `positional_soft_shadow_filter_set_quality`).
- **Other runtime knobs:** `Viewport.mesh_lod_threshold`,
  `use_occlusion_culling` (root viewport needs the project setting, read at
  startup), `use_debanding`, `screen_space_aa`, `use_taa`.
- **GPU identity:** `get_video_adapter_name/vendor/api_version`;
  `get_video_adapter_type()` returns integrated, discrete, virtual or CPU on
  RenderingDevice and always OTHER on OpenGL; `OS.get_video_adapter_driver_info()`
  on Windows and Linux only; `OS.get_processor_name/count`, `get_memory_info`.
  **No API reports total VRAM** (`RD.get_device_total_memory` reports usage,
  debug Vulkan only). Usage: `get_rendering_info(RENDERING_INFO_VIDEO_MEM_USED)`.
- **Frame timing:** `viewport_set_measure_render_time` then
  `viewport_get_measured_render_time_cpu/gpu` plus
  `get_frame_setup_time_cpu`; the docs say these hold under V-Sync or a cap,
  but a capped GPU drops clocks so GPU time rises. `Performance.TIME_FPS`
  updates once a second and is not a frame-time source.
  `PIPELINE_COMPILATIONS_DRAW` counts in-frame pipeline compiles (stutter).
- **Shader stutter:** 4.4 ubershaders stand in while specialised pipelines
  compile; 4.5's export shader baker precompiles at export; the pipeline cache
  key changes with GPU and driver.
- **Display:** `screen_get_refresh_rate` (returns -1 on an invalid screen),
  `window_get_current_screen`, `get_screen_count`, `screen_get_size`. V-Sync
  modes Disabled, Enabled, Adaptive, Mailbox; Compatibility only Enabled. With
  VRR, cap slightly below refresh (`r - r*r/3600`, per the `Engine.max_fps`
  docs).
- **Power:** Godot 4.x has **no battery or power-state API** (Godot 3's
  `OS.get_power_state` is gone). GDScript can read Linux
  `/sys/class/power_supply` with `FileAccess`; Windows and macOS have no
  GDScript-only path.

## How shipped games tune (and what fragr takes)

- **Hardware lookup.** Cyberpunk 2077 suggests a preset from the detected
  GPU at first launch; NVIDIA's GeForce Experience applied database settings
  from test farms keyed on CPU, GPU and resolution. Fast and silent, but only
  as good as the table, and stale for new or unusual hardware.
- **Synthetic index.** Unreal's Scalability runs a short CPU and GPU
  synthetic benchmark, scores against a reference of 100 and maps the index
  through thresholds to quality levels. Cheap, but synthetic work is not the
  game's work.
- **Measured play.** AMD Game Advisor watches at least 180 s of real play and
  recommends changes; HYPR-RX keeps monitoring. Accurate, slow.
- **Runtime governors.** Doom Eternal's dynamic resolution holds a target
  frame rate and budgets textures against VRAM; Unity Adaptive Performance
  steps scalers (LOD, resolution, frame rate, MSAA, shadow cascades) lowest
  visual cost first, with thermal state as an input. Fortnite offers a
  Performance Mode for low-end machines. Counter-Strike 2 and Valorant
  auto-detection have no primary source we could find; Valorant's published
  floor is 30 fps on Intel HD 4000.
- **fragr takes:** a small lookup table only as the starting guess; a short
  measured search on the game's own replayed scene as the decision; a gentle
  in-match governor as the safety valve; every manual choice sticks.

## Design

### Principles

1. **Measure, do not guess.** Hardware names seed the search; the measured
   replay decides.
2. **One art, many costs.** Tiers add or remove depth (shadows, contact
   shading, indirect light, volumetric light, reflections). They never change
   the ambient floor, palette, fog colour or density, faction colours, sign
   budget or silhouette readability. Union red reads at every tier.
3. **The pixel grid is the player's.** The tuner never changes the world
   pixel choice or dither without saying so, never steps resolution
   fractionally under a pixel look, and never changes the grid mid-match.
4. **Manual wins.** Any option the player sets is pinned and the tuner works
   around it.
5. **Say why in plain words.** Every automatic choice shows what it picked,
   what it measured and what limited it.

### (a) Tiers

Five tiers replace the three presets (`video/quality` 0..4; no migration
before 1.0: an old value outside the new meaning resets to auto with a note).
Low, Medium and High equal today's Performance, Balanced and High exactly, so
existing measurements still describe them.

| Tier | Renderer | AA | Shadows (dir / positional atlas, filter) | Practical shadows | AO | Indirect, GI | Glow | Volumetric fog | SSR | Water | Effects budget |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Potato | Compatibility or Forward+ | none | 1024 / 512, hard (filter 0) | off; practical range trimmed, fade at 24 m | off | none | off | off | off | 0 | 25%: particles, decals, shell casings, impact lights capped |
| Low (today Performance) | either | none | 1024 / 1024, engine default | off | off | none | off | off | off | 0 | 50% |
| Medium (today Balanced) | either | MSAA 2x | 2048 / 2048 | on, dual paraboloid (cube on Compatibility) | SSAO low, half size | none | on (authored) | off | off | 1 | 100% |
| High (today High) | either | MSAA 4x | 4096 / 4096 | on, cube | SSAO medium | none | on | off | off | 2 | 100% |
| Ultra | Forward+ only | MSAA 4x | 4096 / 4096, soft high, longer distance | on, cube, longer fade | SSAO high | SSIL medium; SDFGI per venue only after a look pass | on | on in authored venues | on in water and polished venues | 2 | 100%, longer decal life |

Cost evidence today: Low to High spans about 2.3 to 5.4 GPU ms on the 780M
at 1080p in Arena Duel under OpenGL and 2.8 to 8.0 ms in the M01 intake
(`look-pass-boomer.md`); the 720p Compatibility replay drops the 1% low from
100 to 86 fps between Low and High. Potato and Ultra costs are unmeasured;
the first PR measures each feature's increment on the 780M in one process,
alternating, the way the glow change was measured (`look-pass-boomer.md:250-256`),
and records a table. Ultra features are expected to be the expensive ones
(volumetric fog, SSIL, SDFGI); none ships in Ultra without a measured cost
and an inspected still per venue.

MSAA under a pixel look smooths the edges of the coarse grid, which softens
the chunky silhouette slightly. Whether Medium and High keep MSAA when world
pixels are on is a look decision for Nick, made from captures.

Effects budget is new plumbing: one `effects_budget` scale read by the VFX
owners (shot effects, decals, fire, particles) and an impact-light cap.
`Viewport.mesh_lod_threshold` stays at its default except Potato (2.0) once
measured; occlusion culling stays off until a venue shows CPU-bound draw
counts.

### Resolution axis

- **Output** stays native fullscreen by default so HUD and menus are sharp;
  the tuner never lowers output resolution except on the floor path below.
- **3D resolution** is the axis the tuner searches, and its steps depend on
  the pixel look:
  - Pixel look on (default Fine): steps are whole factors only. At 1080p
    Fine is 2x (540 lines); the next coarser legal step is 3x (360 lines,
    Medium). The tuner may suggest the coarser step, never apply it silently.
  - Pixel look off: render scale steps 1.0, 0.83, 0.67, 0.5 with FSR 1 (or
    MetalFX Spatial on Metal) or FSR 2 where the renderer has it; on a strong
    machine Bilinear 1.25 or 1.5 supersampling is the top step.
- **Finer pixel targets on big displays.** Because the factor rounds, 1440p
  Fine renders 480 lines and 2160p 540. A strong machine could carry a finer
  grid (for example a 720-line target: 2x at 1440p, 3x at 2160p) and keep the
  look. Whether to add that target is an art call for Nick; the tuner would
  only offer it.

### (b) Auto-tune

**When it runs**

- First launch, after the boot menu appears, as a visible card: "Tuning
  graphics for this computer. About 90 seconds. Skip". Not silent: it starts a
  local host and loads the GPU, and a fan spinning up unexplained is worse
  than a card. Skip applies the lookup guess and offers the tune later.
- On demand: Benchmark page, "Auto settings" button, beside the existing
  current-preset and compare runs.
- When the **hardware fingerprint** changes: adapter name, vendor, driver
  name and version (`OS.get_video_adapter_driver_info`), API version,
  renderer and driver, OS, display server, current screen's size and refresh,
  CPU name and count, physical memory. A change offers a re-tune on the boot
  menu; it does not run unasked.
- When a build changes rendering cost: a `RENDER_COST_REVISION` constant in
  `render_quality.gd`, bumped by any PR that changes tier contents, shaders,
  the benchmark scene or a venue's lighting cost (the same discipline as
  `WORKLOAD_ID`). A changed revision marks the saved choice stale and offers a
  re-tune.

**Steps**

1. **Identify.** Read the fingerprint. Detect Steam Deck (below), Apple
   Silicon (`metal` driver), Compatibility fallback, integrated versus
   discrete (RenderingDevice only).
2. **Seed.** A small table in `res://` (vendor, device type, known names such
   as Deck, Apple M1/M2, Intel UHD and Iris Xe, 780M) gives a starting tier
   and a predicted margin. It is a guess, never the result. Unknown hardware
   starts at Medium.
3. **Record.** Start the owned local host with ten bots on the benchmark
   venue and record 16 s of snapshots (today's `BenchmarkCapture`, shorter).
   Keep the host running during scoring, as in real solo and campaign play,
   so the CPU cost of a local server is in the measurement (the player
   benchmark stops it; the tuner must not, or a 4-core machine will pass a
   scene it cannot play).
4. **Warm up.** For each candidate: apply it, then wait until
   `PIPELINE_COMPILATIONS_DRAW` has been zero for 1 s (at most 6 s), so shader
   compilation is not scored. V-Sync and the cap are off.
5. **Measure.** Score 8 s per candidate with whole-frame intervals as today,
   plus per-frame `viewport_get_measured_render_time_gpu` and `_cpu` and
   `get_frame_setup_time_cpu`. Pass if `low_1_count_fps >= target x 1.10`
   and no frame at or over 50 ms. The 10 percent headroom covers venues
   heavier than the benchmark scene (see the venue factor below) and heat.
6. **Search the tier ladder.** Step from the seed: up while passing, down
   while failing; use the GPU time to skip (if GPU time is under 40 percent of
   the frame budget at a pass, try two tiers up). Usually 3 or 4 candidates.
7. **Detect the bottleneck.** If GPU time is well under the frame interval
   at a failing candidate, the machine is CPU or presentation bound: stop
   lowering graphics, keep the highest tier that measured the same, and say so
   ("limited by the processor; lower graphics would not help").
8. **Search the resolution axis** within the tier found: pixel look off,
   render scale up while passing (strong machines) or down while failing;
   pixel look on, at most one suggestion of the next coarser factor if Low
   still fails.
9. **Floor path.** If Low fails at native output: try Potato; then, at
   1280x720 output, Potato; then propose the Compatibility renderer (written
   to the override file, applied on restart, with the measured reason) if
   Forward+ Potato still fails and the machine is not CPU bound. Compatibility
   is offered only when it measures better on that machine.
10. **Confirm.** Re-measure the chosen candidate for 12 s. If the two
    windows differ by more than 10 percent, take the lower, mark the result
    "variable" and, on a battery or integrated machine, drop one tier unless
    the lower still passes with headroom.
11. **Apply and report.** Save the choice, its figures, fingerprint, render
    cost revision and date. Show one card.

Time: load about 10 s, record 16 s, four candidates at about 14 s, confirm
about 14 s: roughly 90 s. A candidate within 5 percent of the threshold gets
one extra 8 s window (at most two per run).

**Venue factor.** Larak Lot's orbit is not every venue's worst view. The
`qa_tour` `frame_sample` route measures each venue's heaviest authored view
against the benchmark scene on the 780M; the ratio table ships in `res://`.
The tuner uses the largest factor as headroom only when a venue factor
exceeds 1.10, and the in-match governor handles the rest.

**Thermal and variance.** Laptops and handhelds slow down after minutes, not
seconds. The tuner cannot wait that long, so:

- the confirm window and the 10 percent headroom absorb short drift;
- the in-match governor (below) watches real play;
- after the first 15 minutes of play on a new fingerprint, if the rolling 1%
  low fell below target for most windows, the result screen offers "Tune
  again" with the measured numbers.

**In-match governor (safety valve).** Rolling 1% low over 30 s windows of
real play. Three failing windows in a row step down one item at the next safe
point (death, respawn, round end, mission checkpoint), in order of least
visible first: volumetric fog, SSIL, SSR, SSAO quality, practical shadow
distance, effects budget, MSAA. It never changes the pixel grid, output
resolution or renderer mid-match, never steps up mid-match, and never touches
a pinned option. A step shows one level, untilted line in the HUD notice area
("Graphics lowered: volumetric fog off to hold 60") and is undone at the next
session or re-tune. Pixel look off: an optional dynamic render scale on
Forward+ may hold the target between 0.67 and 1.0 with hysteresis; never with
a pixel look.

**What the player sees.** One card in plain words, for example:

> Auto settings: High, Fine pixels, 60 fps target.
> Measured 1% low 84 fps (Medium 112, Ultra 51).
> Limited by the graphics chip. Ultra would drop below 60 in busy fights.
> Radeon 780M, Vulkan, 1920x1080, 120 Hz. Tuned 31 October 2026.

The same text, figures and candidate table go into the JSON report beside the
existing benchmark results.

**Manual overrides stick.** `video/auto` (on by default) plus a pinned set:
changing any option from the menu pins it and marks the tier "Custom (auto
around your choices)". The tuner and governor only move unpinned options.
"Reset to auto" clears pins. Choosing a tier by hand pins the tier; the
tuner then only tunes resolution if that is unpinned. Settings stay per
device, never synced.

**Targets and displays.**

- Target choices: 60 (default), 90, 120, 144, "Display refresh". The
  "Display refresh" target reads `screen_get_refresh_rate` of the window's
  current screen. If V-Sync is off and the display is faster than the
  target, an Auto frame cap equal to the target is offered (VRR displays:
  `r - r*r/3600`).
- Multiple monitors: the fingerprint includes the current screen's size and
  refresh. Moving the window to a different screen keeps the settings and
  shows "Tuned for another display" on the Graphics page with a Tune button.
- High refresh: the tuner measures uncapped, so a 144 target on a 60 Hz panel
  is allowed (latency) but labelled.

**Battery.** No cross-platform API exists. Linux (including the Deck) reads
`/sys/class/power_supply/*/online` and `status` with `FileAccess`; Windows
and macOS report "unknown". On battery: the tuner warns that results on
battery are lower, and stores which power state the tune ran on; the Deck
profile uses it to pick 40 or 60 (below). No native code is added (GDScript
only).

### (c) Vendors, operating systems and the fallback renderer

- **Windows.** Vulkan stays the driver (no `driver.windows` key; D3D12 only
  if a measured matrix shows it ahead, given the open slowdown report).
  Hybrid Intel plus NVIDIA laptops have open wrong-GPU and freeze reports:
  log the chosen adapter in the tune card and document `--gpu-index`. NVIDIA
  and AMD control panel overrides (forced FXAA, sharpening) change the image;
  the player page names them.
- **Linux.** Vulkan through Mesa RADV (AMD) and ANV (Intel) or the NVIDIA
  proprietary driver; Compatibility through radeonsi, iris or NVIDIA GL. No
  RADV or ANV specific 4.7 issue was found. X11 (XWayland) showed repeatable
  stalls that native Wayland did not (`docs/BENCHMARK.md:1026-1034`), so the
  display server stays in the fingerprint and the player page recommends
  Wayland where available.
- **macOS.** Metal on Apple Silicon; MoltenVK on Intel Macs, where TAA is
  known slow and GPU time is unreliable on Intel iGPUs. Pixel look off on
  Metal: offer MetalFX Spatial in place of FSR 1; MetalFX Temporal and FSR 2
  never run with a pixel look.
- **Shader stutter.** Turn on the export shader baker for release builds
  and keep the warm-up gate on `PIPELINE_COMPILATIONS_DRAW`. Verify the export
  setting name against the 4.7 export docs before adding it.
- **Compatibility as the weak-GPU renderer.** Feasible: every fragr shader
  already draws there and the 780M measured comfortably above 60 at 720p on
  it. What breaks or changes:
  - FSR 1 and 2, MetalFX, TAA, FXAA, SMAA: unavailable (FSR already gated).
  - Ultra entirely (SSIL, SDFGI, SSR, volumetric fog).
  - Dual paraboloid omni shadows refused (already handled); shadowed lights
    draw in extra passes, so practical shadows cost more there.
  - 16 lights per object (fragr's setting) and 32 per frame; dense practical
    rooms may drop lights.
  - RGBA8 colour buffer and a different glow: bloom shape and banding differ,
    so glow thresholds need their own captures.
  - Adaptive and Mailbox V-Sync unavailable.
  - `get_video_adapter_type()` returns OTHER, so the seed table keys on
    names.
  - Decals as nodes are unavailable (fragr's decals are a spatial shader,
    unaffected).
- **Capture parity.** Because inspected stills mostly come from
  `opengl3`, add Forward+ (`--rendering-driver vulkan`) to the tour runs that
  gate a tier, and inspect both.

### (d) What looking great means for fragr

Boltgun is the reference: pixel surfaces under modern light.

- Light with shape: 4096 atlases and soft filtering so cover and fixtures
  throw clean shadows that stay pixel-sharp at the world grid; longer
  practical shadow distance so a hall reads in depth.
- Contact and bounce: SSAO high grounds props; SSIL lets a sodium lamp tint
  the floor and walls around it, which suits the authored practical lights.
- Volumetric fog only where the venue earns it: light shafts in dark
  facilities, the lunar port and the Mars foundry; authored per venue in
  `arena_sky.gd` presets with the same fog colour and density as other tiers
  so a low tier never reveals a different room.
- SSR on water and polished floors (Low Water, harbour, wet yards).
- Glow stays small and authored (three tight levels); Ultra never widens it.
- Higher 3D resolution with the grid kept: a finer pixel target on large
  displays, if Nick approves it.
- Particles and decals at full budget; longer impact decal life.
- SDFGI and AreaLight3D only per venue after a look pass shows they help
  and the cost is measured.

**Consistency rule.** A tier contact sheet per venue (Potato to Ultra, same
pose, both renderers where they apply) is inspected before any tier change
merges. The check: same ambient floor, same fog, same faction colours, every
fighter readable at 30 m, no new sign or text, no tilted text.

### (e) Steam Deck

**Hardware.** Zen 2, 4 cores and 8 threads; RDNA 2 GPU, 8 CUs up to
1.6 GHz (about 1.6 TFLOPS FP32); 16 GB LPDDR5 shared; 4 to 15 W; LCD
1280x800 at 60 Hz; OLED 1280x800 HDR up to 90 Hz with faster memory. The 780M
has 12 newer RDNA 3 CUs at higher clocks, 8 Zen 4 cores and more memory
bandwidth, so the Deck is several times slower in GPU and CPU terms; exact
ratio unmeasured.

**Path.** The native Linux x86_64 build on SteamOS through Vulkan (Mesa
RADV), which Valve recommends for performance and battery; Proton is not
needed. Ship inside the Steam Linux Runtime the store selects (verify the
current runtime on the partner site at release time).

**Recognising a Deck.** Without Steamworks (not integrated, and a native
SDK would not be GDScript): Linux, a 1280x800 internal panel, and the RADV
adapter name. The name strings ("AMD Custom GPU 0405" LCD, "0932" OLED) and
the `SteamDeck=1` environment variable are commonly cited but **not verified**;
confirm on a real Deck before shipping the detector. If Steamworks is
integrated later, `ISteamUtils::IsRunningOnSteamHardware()` (the old
`IsSteamRunningOnSteamDeck` is deprecated) replaces the heuristic.

**Target recommendation.** Keep Nick's provisional gate and tighten how it
is measured:

- **Gate: 40 fps steady at 1280x800 in 40 Hz mode on auto settings, judged
  as an uncapped 1% low of at least 44 fps (10 percent headroom) on the
  tuner's replay with the local host running, and a capped 40 fps play
  session with 1% low at or above 36 and no frame over 50 ms after warmup.**
  Why: Valve's Verified bar is 30 fps at 800p by default, so 40 clears it
  with margin; Valve's own SteamOS 3.2 notes framed 40 Hz with a 40 fps limit
  as the balance of smoothness, quality and battery (every frame is new, 25 ms
  each); 60 Hz with a 40 cap judders (frames held for 1 or 2 refreshes), so 40
  only works paired with 40 Hz; and battery tests put 40 at 40 Hz close to 30
  fps battery life while 60 fps costs most. fragr's simulation is a 20 Hz
  server tick, so 40 fps rendering does not change outcomes, only feel.
- **60 fps profile (stretch):** offered and chosen when the measured
  uncapped 1% low is at least 66 at the Deck profile's settings, on AC power,
  or whenever the player chooses it. On battery the default stays 40 unless
  the player picked 60.
- **OLED:** 45 fps at 90 Hz is an even half-refresh; treat it like 40 at 40
  Hz when the panel reports 90 Hz.
- **How the tuner picks:** read refresh; read power state; measure. If the
  panel is at 40 Hz (or 90), cap 40 (or 45) with V-Sync. If the panel is at
  60 Hz and 60 does not hold, cap 40 and show "Set Refresh Rate to 40 Hz in
  the Quick Access menu for steady motion". The game cannot set the Deck's
  refresh or TDP; the Quick Access frame limiter and TDP limit override the
  game, so the tune card says which it measured under. How gamescope's limiter
  interacts with `Engine.max_fps` and V-Sync, and whether
  `screen_get_refresh_rate` reports the 40 Hz mode, are **not verified**: test
  on the device.
- **Deck profile settings to measure first:** Forward+ Vulkan; Low or
  Medium tier; pixel look is the hard question, because Fine renders natively
  at 800p (factor 1, 1280x800) and Medium renders 640x400 (factor 2). Measure
  both; Nick picks the look. Ultra is never chosen on a Deck.

**Verified-style checklist.** Full controller play with default config,
Deck glyphs when the pad is in use, no keyboard or mouse glyphs, smallest
text at least 9 px (aim 12) at 1280x800 (audit `HudStyle` and every literal
size under 18 at the 0.667 scale), 16:10 layout with `expand` checked in
captures, controller-only text entry (callsign) via a built-in pad keyboard,
no launcher, defaults that work with no warnings, suspend and resume
mid-match and mid-mission (the client must survive a long frame gap and a
dropped socket and resume through the existing resume token path).

**Measuring.** Only a real Deck counts as Deck evidence. On this Linux
machine we can approximate parts, none of them performance:

- Can do here: 1280x800 window captures for legibility and 16:10 layout,
  controller-only play, the Deck detector with a spoofed adapter string in a
  test, battery reading from `/sys` on this laptop, refresh-cap logic,
  `taskset` to four threads to sanity check CPU headroom of the local host.
- Not equivalent: forcing the 780M's lowest clock
  (`power_dpm_force_performance_level`, root, and this is a shared machine)
  still leaves RDNA 3, 12 CUs, Zen 4 and faster memory; frame rates there say
  nothing reliable about a Deck. Gamescope is not installed here, and nested
  gamescope would still not be a Deck.

### (f) Measurement plan and the 1.0 gate

**Gates before 1.0** (each a measured table in this plan, never prose):

| Gate | Machine | Output | Settings | Pass |
|---|---|---|---|---|
| Floor | weak machine (Intel UHD 620 or Iris Xe class, or GTX 750 Ti / 1050 class) | 1280x720 | Potato, Forward+ (Compatibility if the tuner picks it) | 1% low at or above 60, no frame over 50 ms after warmup |
| Reference iGPU (ROADMAP) | Radeon 780M | 1920x1080 | auto | 1% low at or above 60, no frame over 50 ms after warmup |
| Steam Deck | Deck LCD (OLED if available) | 1280x800 | auto, 40 Hz | as in Steam Deck above |
| Ceiling | modern discrete NVIDIA and AMD | native up to 2160p | auto at 60 and at 144 | tuner picks Ultra or High and the chosen settings hold the target in a real 15 min session |
| Tuner correctness | every matrix machine | native | auto | chosen settings hold target in a 15 min real session on three venues (benchmark venue, heaviest interior, heaviest exterior); manual pins survive a re-tune; re-tune is offered after a driver change |

**Hardware matrix.**

| Machine | OS and driver | Who runs it | Status |
|---|---|---|---|
| Radeon 780M (this host) | Linux, Vulkan RADV and OpenGL radeonsi; Wayland and X11 | here, automated | partly measured |
| Radeon 780M | Windows 11, Vulkan and OpenGL (D3D12 one row) | Nick's Windows host | Compatibility 720p measured |
| Intel UHD 620 or Iris Xe | Windows and Linux (ANV, iris) | needs a machine | none |
| Old NVIDIA GTX (750 Ti, 960 or 1050) | Windows, Linux proprietary | needs a machine | none |
| Modern NVIDIA (RTX 30 or 40) | Windows, Linux proprietary | needs a machine | none |
| Modern AMD discrete (RDNA 3 or 4) | Windows, Linux RADV | needs a machine | none |
| Apple M1 and M2 | macOS, Metal | needs a machine | none |
| Intel Mac (optional) | macOS, MoltenVK | needs a machine | none |
| Steam Deck LCD (OLED optional) | SteamOS, RADV, native build | needs a Deck | none |

**Automation possible on this Linux machine:**

- Tuner search logic, fingerprint changes, pin handling, report text and the
  governor's step order as headless GDScript harnesses with fake measurement
  feeds (`client/scripts/test_auto_tune.gd`, registered with the existing
  checker). Deterministic, in CI.
- Real tuner runs on the 780M under Vulkan and OpenGL, Wayland and X11, via
  a `qa_auto_tune.gd` scripted route like `qa_benchmark.gd`, writing the
  report; repeat five times for variance.
- Forced fallback: start with an empty Vulkan ICD list
  (`VK_ICD_FILENAMES` pointing at nothing) and assert the game comes up in
  Compatibility and the tuner adapts. Software Vulkan (lavapipe), if
  installed, for correctness only.
- Venue factor table from `qa_tour` `frame_sample` on every venue.
- Tier contact sheets through `tools/qa_tour.sh` on both drivers.
- Frame rates are never a CI gate; CI runs the logic.

**Needs other machines:** every other row of the matrix. A tester runs
Benchmark, then Auto settings, then Copy summary, and pastes into a GitHub
issue template (no telemetry); the summary already carries adapter, driver,
renderer and settings. Compare only results whose compatibility keys match.

## Implementation outline

- `render_quality.gd`: tiers as one data table (the single owner `apply`,
  `apply_environment`, `apply_practicals` and `preset_features` read), new
  shadow filter, SSIL, SSR, volumetric fog and effects budget, Compatibility
  gates, `RENDER_COST_REVISION`.
- `hardware_profile.gd` (new): fingerprint, seed table, Deck and Apple
  detection, Linux power state.
- `auto_tune.gd` (new): the search over `BenchmarkRun` and `FrameStats`
  with a short workload id and the local host kept running; GPU and CPU time
  capture shared with the stutter trace code.
- `frame_governor.gd` (new): in-match rolling windows and safe-point steps.
- `settings.gd`: `video/quality` 0..4, `video/auto`, `video/target_fps`,
  `video/pinned`, `video/tune` record; one current schema, no migration.
- `settings_panel.gd`: tier list with Custom, target, Auto toggle, Tune
  button, per-option rows from the options plan, renderer choice with restart.
- Boot menu first-launch card and Benchmark page button.
- Tests: `test_auto_tune.gd`, extended `test_settings.gd`,
  `test_render_quality` assertions per tier, governor harness.

Order: tiers as data with no visual change at Low, Medium, High; Potato and
measurement table; tuner with logic harness; governor; Ultra per venue with
contact sheets; Deck profile on a real Deck; matrix runs; docs pages.

## Docs outline

### Player page: `docs/GRAPHICS.md` (linked from README and the Graphics page)

1. Auto settings in one paragraph: what runs on first launch, how long, how
   to skip, how to run it again.
2. What the benchmark does: the replayed fight, warm-up, what 1% low means,
   why V-Sync is off while measuring, what is saved and where.
3. Your target: 60 by default; 90, 120, 144 or display refresh; frame cap
   and V-Sync advice; VRR.
4. Tiers: one line each, Potato to Ultra, with what you see and what it costs
   (from the measured table).
5. Each option: what it changes on screen, its cost on the reference
   machine, and which renderer has it.
6. World pixels and dither: the art choice, why the tuner leaves it alone,
   what Fine means at 720p, 1080p, 1440p, 4K and 800p.
7. Your choices stick: pins, Custom, Reset to auto.
8. In-match adjustments: what the governor may lower and how to turn it off.
9. Laptops and battery; multiple monitors; high refresh.
10. Steam Deck: the 40 Hz recommendation, the 60 profile, Quick Access
    settings, suspend.
11. Old or unsupported GPUs: the Compatibility renderer, what it lacks, how
    to switch, `--rendering-driver` and `--gpu-index`.
12. Driver tips: control panel overrides, Wayland on Linux, hybrid laptops.
13. Reporting a result: Copy summary and the issue template.

### Developer section: `docs/BENCHMARK.md`, "Tiers and auto settings"

1. Tier table as code defines it, and the rule that `preset_features`
   prints from the same data.
2. Art consistency rule and the contact sheet check.
3. Tuner contract: triggers, fingerprint fields, steps, thresholds,
   headroom, time budget, confirm rule, CPU-bound rule, floor path.
4. Governor contract: windows, safe points, step order, limits.
5. Report fields added to schema 3 (or schema 4), compatibility keys.
6. `RENDER_COST_REVISION` and `WORKLOAD_ID` bump rules.
7. Venue factor table: how it is measured and regenerated.
8. Renderer support matrix and fallback behaviour, with the Godot sources.
9. Measurement method for a feature's cost (one process, alternating).
10. Hardware matrix with results tables, dated, per machine.
11. Steam Deck detection and verification steps on device.
12. What is not evidence: headless checks, clock-capped 780M runs, single
    runs.

## Risks

- **Scene representativeness.** Larak Lot's orbit may understate the
  heaviest venues and real first-person fights; mitigated by the venue factor
  and governor, but a wrong factor means a wrong tier.
- **Thermal and power.** A 90 s tune on a cool laptop overestimates; no
  battery API off Linux; the Deck's TDP and limiter are outside our control.
- **Variance.** 8 s windows at 60 fps hold about 480 frames, so the 1% low
  is about five frames; repeat windows and headroom are required, and small
  differences stay noise.
- **CPU-bound machines.** The local server and bots share the CPU in solo
  play; measuring without them (as the player benchmark does) would pass
  machines that cannot play.
- **Compatibility differs in look.** RGBA8 buffer, different glow and fewer
  lights per object; tier stills must be inspected on both renderers.
- **Renderer switch needs a restart** and an override file; a bad override
  must be recoverable (start once without it after a failed boot).
- **Unverified Deck facts:** adapter strings, environment variables,
  gamescope limiter interaction, refresh reporting, suspend behaviour.
- **Driver issues:** D3D12 slowdown, hybrid GPU selection, MoltenVK TAA,
  AMD MSAA 2x artifacts on Windows Vulkan, Polaris MSAA plus SSAO artifacts.
- **Hardware coverage.** Only the 780M is on hand; every other claim waits
  for a measured row.
- **Pixel look tension on big screens and the Deck.** Rounding makes 1440p
  coarser than 1080p and the Deck native at Fine; both need Nick's call.

## Sources

Godot 4.7.2-stable class reference (raw XML at the tag):

- ProjectSettings: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/ProjectSettings.xml
- RenderingServer: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/RenderingServer.xml
- RenderingDevice: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/RenderingDevice.xml
- Viewport: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Viewport.xml
- Environment: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Environment.xml
- Performance: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Performance.xml
- OS: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/OS.xml
- DisplayServer: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/DisplayServer.xml
- Engine: https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml
- Command line flags: https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp

Godot 4.7 manual and release notes:

- Renderers: https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
- Internal rendering architecture: https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html
- System requirements: https://docs.godotengine.org/en/4.7/about/system_requirements.html
- Resolution scaling: https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html
- Troubleshooting: https://docs.godotengine.org/en/4.7/tutorials/troubleshooting.html
- Releases: https://godotengine.org/releases/4.3/, https://godotengine.org/releases/4.4/, https://godotengine.org/releases/4.5/, https://godotengine.org/releases/4.6/, https://godotengine.org/releases/4.7/
- SSAO in Compatibility: https://github.com/godotengine/godot/pull/112451
- Issues: D3D12 tracker https://github.com/godotengine/godot/issues/95775; D3D12 slower than Vulkan https://github.com/godotengine/godot/issues/123125; MoltenVK TAA https://github.com/godotengine/godot/issues/92254; Metal fence timeout https://github.com/godotengine/godot/issues/119436; macOS Intel GPU time https://github.com/godotengine/godot/issues/51371; AMD Windows MSAA 2x https://github.com/godotengine/godot/issues/108602; Polaris MSAA plus SSAO https://github.com/godotengine/godot/issues/61415; Intel iGPU mip bug https://github.com/godotengine/godot/issues/85348; hybrid GPU laptops https://github.com/godotengine/godot/issues/88502 and https://github.com/godotengine/godot/issues/78267; NVIDIA driver freeze https://github.com/godotengine/godot/issues/116414

Steam Deck:

- Specifications: https://www.steamdeck.com/en/tech/deck and https://www.steamdeck.com/en/tech
- Compatibility review criteria: https://partner.steamgames.com/doc/steamdeck/compat
- Recommendations: https://partner.steamgames.com/doc/steamdeck/recommendations
- ISteamUtils (hardware detection, gamepad text input): https://partner.steamgames.com/doc/api/ISteamUtils
- Linux platform and runtime: https://partner.steamgames.com/doc/store/application/platforms/linux
- SteamOS 3.2 refresh rate setting (secondary reports of Valve's notes): https://www.thefpsreview.com/2022/04/28/steam-deck-gets-experimental-support-for-changing-in-game-screen-refresh-rate-can-greatly-improve-battery-life/ and https://m.gsmarena.com/steamos_32_update_adds_refresh_rate_settings_quieter_fan_curve_to_the_steam_deck-amp-54457.php
- 40 Hz battery test (secondary): https://www.techspot.com/news/94275-youtuber-boosts-steam-deck-battery-life-capping-display.html

Shipped tuning approaches:

- Unreal Scalability and SynthBenchmark (secondary): https://tomlooman.com/unreal-engine-optimal-graphics-settings/
- Unity Adaptive Performance: https://docs.unity3d.com/Manual/adaptive-performance/scalers-introduction.html and https://docs.unity3d.com/Packages/com.unity.adaptiveperformance@2.0/manual/user-guide.html
- AMD Game Advisor and HYPR-RX: https://www.amd.com/en/resources/support-articles/faqs/DH3-029.html and https://www.amd.com/en/resources/support-articles/faqs/DH3-028.html
- NVIDIA GeForce Experience (historical): https://hothardware.com/news/nvidias-new-geforce-experience-app-aims-to-simplify-game-settings-get-you-playing-faster
- Fortnite Performance Mode: https://www.epicgames.com/help/c-202300000001628/c-c-202300000001704/a202300000013270
- Doom Eternal dynamic resolution and VRAM budget (secondary): https://www.techspot.com/article/1999-vram-explained and https://rog.asus.com/us/articles/rog-ally/doom-eternal-on-the-rog-ally-performance-guide--best-settings
- Cyberpunk 2077 hardware preset (review): https://guru3d.com/review/cyberpunk-2077-pc-graphics-perf-benchmark-review/page-3
- Ghost of Tsushima PC upscalers: https://www.nixxes.com/games/ghost-of-tsushima-directors-cut/
- Valorant requirements: https://www.pcgamer.com/valorant-system-requirements/

Not verified for 4.7 or on device: Nearest scaling's renderer coverage in
the docs (fragr's own captures show it on Forward+ and Compatibility), Deck
adapter strings and environment variables, gamescope limiter interaction,
Counter-Strike 2 and Valorant auto-detection, Ghost of Tsushima dynamic
resolution, the current GeForce Experience pipeline, the export shader
baker's setting name.
