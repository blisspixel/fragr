# Display resolution and portable graphics quality

Status: implemented, integration tracked in
[#202](https://github.com/blisspixel/fragr/pull/202), 2026-09-20. Spend: $0.

Fullscreen is already the saved and project default. Extend the shared retro
settings panel with real resolution and quality choices, keeping the server
independent of renderer behavior and keeping pixel materials crisp.

## Contract

- Fullscreen uses the current desktop mode. A selected 3D resolution changes the
  world buffer, preserves display aspect ratio and leaves menu text sharp. Native
  remains the default. Windowed resolution changes the window, bounded to the
  current screen's usable area. Do not change the OS display mode or require
  exclusive fullscreen.
- Quality presets: Performance (no multisampling, smaller shadow atlas), Balanced
  (2x multisampling, normal shadows), High (4x multisampling, larger shadows and
  restrained ambient occlusion where supported). Nearest material filtering,
  gameplay visibility, authoritative geometry and authored ambient light remain.
- Optional FSR1/FSR2 upscaling only on Forward+. Preserve the chosen preference
  when using another renderer, but explain and apply the standard fallback. FSR2
  supplies its own temporal antialiasing; do not stack MSAA on it.
- Use `FragrSettings` validation and persistence. One presentation helper owns
  resolution math, renderer capabilities and quality application. Apply in boot
  and match scenes, after map environment replacement and window resize.
- No renderer restart machinery, new dependency, hardware ray tracing, automatic
  quality benchmark or hardware performance promise in this increment.

## Current research

Checked 2026-09-20 against Godot 4.7:
[renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html),
[resolution scaling](https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html),
[Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html).
Forward+ supports Vulkan, Direct3D 12 and Metal; Compatibility is OpenGL. MSAA is
available across renderers; FSR2 requires Forward+. Resolve capabilities by the
active renderer, never a GPU vendor string. Verify installed APIs and rendered
behavior rather than inferring support from headless setters.

[AMD's FSR documentation](https://gpuopen.com/fidelityfx-superresolution-2/)
now recommends newer SDK generations for new integrations. This change uses
Godot's built-in FSR1/FSR2 support, not a claim to the latest standalone SDK.
An SDK upgrade requires a separate renderer integration and portability review.

[Vulkan ray-tracing plumbing](https://github.com/godotengine/godot/pull/99119)
provides low-level acceleration structures and pipelines. It is not a complete
scene-lighting mode. A later RT experiment needs scene integration, denoising,
motion and memory measurements, failure recovery and a portable fallback before
any player-facing promise. Existing GI is not to be mislabeled RTX.

## Verification and acceptance

Preset values use MSAA Off/2x/4x and 1024/2048/4096 directional and positional
shadow atlases. High uses SSAO radius 1.0 and intensity 0.6 on Forward+ and
Compatibility; Mobile retains multisampling and shadows. The installed API and
[Environment reference](https://docs.godotengine.org/en/4.7/classes/class_environment.html#class-environment-property-ssao-enabled)
confirm the current Compatibility support. Native pixel textures are unchanged;
reconstructing a smaller world buffer can still soften their final image.

The settings menu reports effective resolution when the requested choice exceeds
the display. Fullscreen resolution choices follow the current screen's aspect
ratio. Windowed choices use 16:9 and fit the usable area; Automatic keeps a manually
resized window. This avoids unsupported exclusive display-mode switches.

Prove malformed-value fallback, saved choices, Cancel, real viewport and
environment changes, FSR capability fallback and aspect-preserving bounded
resolution math. Inspect display/graphics menus and live indoor/outdoor scenes
under OpenGL and Forward+ on available hardware. Verify fullscreen and windowed
transitions without taking ownership of the desktop pointer. Run all client
checks and desktop CI; refresh the published tour. Record actual hardware and
limitations. Cross-platform compilation is not proof of every GPU combination.

## Local results

- All 31 client harnesses pass through `tools/godot_check.sh`, including actual
  settings validation, save/cancel, scene replacement and local server lifecycle.
  The check caught a detached shot-effects fixture without preferences; initialize
  that fixture and apply environment quality separately from viewport settings.
  All ten `tools/test_godot_check.sh` fault-detection scenarios also pass.
- `test_render_quality.gd` passes with a real OpenGL and Vulkan window on Windows,
  AMD Radeon 780M. It checks fullscreen/windowed transitions, usable-screen bounds,
  live world scaling and pointer release. No saved player preferences are changed.
- The published 24-state tour passes; display/graphics panels and gallery inspected.
  A six-state Vulkan arena comparison and nine-state M01 comparisons on both
  renderers pass. M01 defeats a Clerk and two Sweepers through ordinary input before
  inspecting the indoor scene. Timed strips confirm real server movement while
  FSR2 is selected, with native detail restored afterwards.
- Forward+ receipts show 720/1080 scale, FSR1/FSR2 modes, and disabled MSAA with
  FSR2. OpenGL receipts show the same scale with standard reconstruction and 4x
  MSAA. Performance/Balanced/High produce Off/2x/4x at native resolution.
- An earlier M01 strip correctly failed because the player did not move. Input,
  blocking and acknowledgement diagnostics were added; the following Vulkan and
  OpenGL runs moved normally. The original cause is not established, and the
  rejected static strip is not motion evidence. Preserve the distance assertion.

Receipts: `.agents/display-godot-reviewed.log`, `.agents/display-real-*.log`,
`.agents/qa/display-release-20260920/`, `.agents/qa/display-vulkan-20260920/`,
`.agents/qa/display-m01-vulkan-diagnostic-20260920/` and
`.agents/qa/display-m01-opengl-verified-20260920/`. These are renderer correctness
and visual checks, not FPS benchmarks or proof on Nvidia, macOS or other GPUs.
FSR can soften moving pixel art; native remains the default. Current rooms and
characters remain development art. Green cross-platform CI gates integration.
