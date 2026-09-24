# Plan: boomer shooter look pass

**Status:** in flight (2026-09-24). Stage 1 and the first lighting increment
are implemented on `feat/look-pass-lighting`; stages 2 to 5 remain planned.
**Branch:** `feat/look-pass-*` (one PR per stage below)
**Spend:** $0. Art is authored in-repo (pixel plates, palette, shaders). No paid assets.

Current implementation pass: [`arena-surface-pass.md`](arena-surface-pass.md).
Three idle weapon viewmodels and retro menus shipped in v0.15.0. The authored
surface shader is a deliberate alternative to the proposed atlas for the current
server-built boxes. Most stages below remain design targets, not implemented
behavior. `tools/spritegen` is the existing asset preparation pipeline; the
historical `tools/pixelforge` proposal below was never implemented.

## Goal

Make the tip look like a modern pixel-art boomer shooter instead of a textured graybox: a low internal resolution with nearest upscaling, surfaces limited to the locked palette with ordered dithering, fighters as readable eight-direction sprites with walk, fire, pain, and death frames, weapon view models with idle, fire, and bob frames, muzzle and impact frames, a HUD laid out on a grid, and level surfaces built from a coherent tile atlas with baked lighting and trim. Reference points and the reasons behind each choice are in `docs/DESIGN-REFERENCES.md` (Dusk, Amid Evil, Prodeus, Cultic, Nightmare Reaper rows) and the palette lock in `docs/ART_STORY_BIBLE.md`.

## Non-goals

- Photoreal or milsim rendering, post-process bloom floods, neon.
- New weapons or maps (this pass re-dresses what exists).
- Changing the wire protocol or the server. Presentation only.
- Doom or id lookalikes in sprites, weapons, or HUD.

## Stages (each a PR that passes the Godot CI job and ships regenerated tip screenshots)

1. **Render target and dither.** Godot 4.7's `Viewport.SCALING_3D_MODE_NEAREST` with `rendering/scaling_3d/scale` at 0.25 under the `canvas_items` stretch mode: the 3D pass renders at a quarter of the window (480 by 270 at 1080p), upscales by an exact integer with nearest filtering, and the HUD stays native. The renderer switches to Compatibility (OpenGL 3.3, low base cost, keeps depth fog, glow, and baked lighting; loses nothing a Doom look needs). An optional ordered-dither post shader (4 by 4 Bayer) on a `ColorRect` in a canvas layer below the HUD, reading the upscaled 3D buffer and indexing the threshold matrix by the screen position divided by the scale factor so the pattern aligns to the 3D pixel grid (2D is never rendered at low resolution), quantising to `docs/palette.json`, toggleable in the boot menu ("Pixel: on/off") and off in the tip capture harness until the stills are re-approved. Evidence: before and after stills, the far-cam harness still passes, frame time unchanged within noise.
2. **Surface atlas.** One 16 by 16 tile atlas per map family (floor, wall, trim, hazard, spawn, crate, pillar) in the locked palette with baked highlight and shadow rows; `StandardMaterial3D` with nearest filtering, no mipmaps, triplanar off, UV scaled so one tile is one metre. Arena Duel and Compliance Yard re-dressed as they stand (geometry is still hardcoded in the server); when the campaign moves geometry to `.map` files, both arenas are re-exported with the same atlas and texel constant. Evidence: stills from both maps, the palette validator in the art bible run over the atlas.
3. **Fighter sprites.** Eight facing directions per fighter (Cyanex and Kragge skins), frames for idle, walk (4), fire (2), pain (1), death (4), at 64 pixels; a `Sprite3D` billboard aligned to the camera with a normal map so lights hit it; direction chosen from the fighter's yaw relative to the camera; enemy tint forced per team colour. Evidence: a headless harness that resolves direction and frame from yaw and state; stills.
4. **Weapon view models and effects.** Flechette, Rail, and Scatter hand sprites with idle bob, fire (2 frames), and a reload beat; muzzle flash frames; impact sprites by surface; sprite gibs on overkill with the DENIED watermark. Evidence: stills, the existing fire-juice path still fires the HUD kick.
5. **HUD grid, sprites over text.** The screen is not a readout. Health, armour, ammo, weapon, and pickups read as sprites and icons the way Vampire Survivors and the boomer shooters do: a status face or bar, a weapon sprite with an ammo count in a pixel numeral, an icon for a pickup in view, station art for the radio card, and one line of text at most on screen at any moment outside menus and the killfeed. Text is for names in the killfeed, the Host line, and menus. All HUD elements sit on an 8 pixel grid with fixed regions: top left match state, top right killfeed, bottom left health and armour, bottom right weapon with the radio station card and track toast above it (the radio plan keeps the card out of the killfeed corner); no overlapping labels at 640 by 360; the ON AIR booth portrait replaces the mode label block. Evidence: a headless layout check that asserts no two HUD rectangles intersect, stills at 16:9 and 16:10.

## Research notes (2026-09-18)

- **Low resolution the 4.7 way.** `SCALING_3D_MODE_NEAREST` landed in 4.7 for all three renderers and is 3D only; the docs say to use a scale equal to one over an integer (0.5, 0.3333, 0.25, 0.2). 2D is never scaled, so the HUD stays crisp for free. `canvas_items` stretch is the 4.7 default. The older `SubViewportContainer` recipe with a fixed 480 by 270 base and `scale_mode = integer` gives a strict pixel grid for the HUD at the cost of black bars on odd window sizes; recipe one above is simpler and is the default, recipe two is the fallback if the HUD grid stage needs it. Never `viewport` stretch at low resolution (text gets downsampled), never bilinear (blur), never FSR (Forward Plus only). The engine default for stretch mode is still `disabled`; only projects created in 4.7 get `canvas_items` written in, so fragr sets it explicitly. Post shaders in recipe one run at native resolution over the upscaled buffer, hence the grid-aligned threshold above; recipe two is the path if a shader truly must run inside the low-res pass.
- **Renderer.** Compatibility lacks SDFGI, VoxelGI, volumetric fog, SSR, TAA, FSR2, CompositorEffects, and HDR 2D (it does keep SSAO, MSAA 3D, depth fog, glow, and lightmap rendering). None of the missing features serve this look. It runs on old integrated GPUs without Vulkan. Keep Mobile as a switch only if a CompositorEffect is ever needed.
- **Shaders.** Screen-reading shaders use `hint_screen_texture` with `filter_nearest` and `textureLod`; stacked effects need a `BackBufferCopy` between them. Order: posterise and dither inside the low-res pass, CRT or scanlines at native resolution after the upscale. Sources with permissive licences: Bayer dithering (CC0), retro post-processing with bit depth and 4 by 4 dither (CC0), dither gradient in the Obra Dinn style (MIT), PixelDither palette quantiser (MIT), the godot-color-dither collection (CC0 shaders), CRT Lottes (CC0), all on godotshaders.com or GitHub. The Obra Dinn devlog on stable dithering is the primary write-up.
- **Eight-direction billboards.** `Sprite3D` with `BILLBOARD_FIXED_Y`, `TEXTURE_FILTER_NEAREST` on every sprite (the default is linear with mipmaps), `ALPHA_CUT_DISCARD` to dodge transparency sorting, `shaded = false`. Frame from `wrapf(atan2(to_camera.x, to_camera.z) - yaw, -PI, PI)` divided into eight; store five directions and flip the other three, the Doom trick. Billboards face the camera when rendering shadows, so use a blob shadow sprite on the floor instead.
- **Weapon view models.** Under recipe one the view model is a `Sprite3D` child of the camera (no depth test, alpha cut, unshaded) so it shares the low-res pass and the dither; bob is a sine on speed, sway lerps toward the negated mouse delta, muzzle flash is a sheet frame plus a one-frame `OmniLight3D`. Lighting: unshaded sprites plus depth fog is the Doom look; arenas can go vertex-lit with the force-vertex-shading override; sector light through `vertex_color_use_as_albedo`.
- **Import and texel density.** Lossless import for pixel art, VRAM compression off even in 3D, mipmaps off, Detect 3D off. Filtering is per node in 4.x. One atlas with `region_rect` or `hframes` and `vframes`. There is no texel density feature; fix one constant (16 texels per metre, Doom's one texel per unit scaled) and keep it with `uv1_scale` or, once maps come from TrenchBroom, func_godot's inverse scale factor.
- **References.** bearlikelion's BoomerShooter (MIT, GDScript, 4.7 Forward Plus, not low-res), Zorochase's ultimate-retro-shader-collection (MIT, 4.2 to 4.7, PSX and N64 spatial shaders, billboard sprite shaders, dither on a container), psx_visuals_gd4 (MIT port). The Game Engine Black Book: DOOM covers sprite rotations and colormap light diminishing.
- **Asset production.** Decided in `art-pipeline.md`: generated through two pixel-art-native services (eight views, palette lock, seamless tiles) after written spend approval, or a local Apache 2.0 model at zero cost, then normalised by the Rust tool `tools/pixelforge` (nearest downscale, palette snap, outline, sheet packing, provenance strip, manifest) and touched up in Pixelorama (MIT, built in Godot). Stages 2 to 5 below consume those assets.

## Increment 1: lighting, atmosphere and stage 1 (2026-09-24)

Presentation only. No server, wire or map data changes; the eight strip lights
per map that the wire already allows are the fixtures.

**Re-verified against 4.7.2 (2026-09-24).** The local binary's own class
reference (`--doctool`) and the
[Viewport page](https://docs.godotengine.org/en/4.7/classes/class_viewport.html)
confirm `SCALING_3D_MODE_NEAREST` ("looks crisper than bilinear and has no
additional rendering cost"), `OmniLight3D.SHADOW_DUAL_PARABOLOID`,
`Light3D.light_cull_mask` and distance fade,
`RenderingServer.environment_set_ssao_quality`,
`viewport_get_measured_render_time_gpu/cpu`, filmic tonemap, adjustments and
glow. Two claims above did not hold up: the 4.7
[resolution scaling page](https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html)
does not document Nearest at all, so the "one over an integer" rule is ours,
enforced by `RenderQuality.pixel_factor`; and the Compatibility renderer
refuses paraboloid omni shadows at runtime ("not supported in the
Compatibility renderer"), which the first measurement run caught. The renderer
stays Forward+ by default; switching to Compatibility is not part of this
increment.

**What landed.**

- `arena_sky.gd` owns a light plan per venue. Recall Notice and the Persons
  Unknown ward (the `facility` preset) drop the flat 1.05 ambient to 0.36, turn
  the arena's sun down to a faint cool key, hide the arena scene's ember props
  and fill, and use a grey-green depth haze (0.024) instead of near-black fog so
  dark silhouettes separate from the far end of an aisle. Filmic tonemap, mild
  contrast and saturation adjustments, and glow are authored per venue. Arenas
  keep their sun, now a lower sodium key over a cooler 0.45 ambient with a
  warmer haze.
- Practical fixtures: each registered strip light is a strong, short pool
  (energy 6, range 14) in service-fluorescent white. Union seals gain a small
  red lamp (`on_air`) with no shadow map. Practicals cast shadows from Balanced
  up (paraboloid where the renderer supports it, cube on High and on
  Compatibility), drop their shadow past 24 m and fade out past 40 m.
- Readability: world geometry built from MapInfo renders on visual layer 2. A
  view-attached omni fill (energy 1.2, range 45 m, shallow falloff) lights
  layer 1 only: fighters, enemies, pickups and effects. A black-and-red enemy
  between fixtures keeps a lit front toward the player and the room does not
  flatten. The campaign combat strips (`*_combat.png` in the M01 and M02 tour
  folders) show every Clerk and Sweeper readable at its fight range, including
  the far end of the M02 processing floor. Those runs used today's enemy art;
  the black-and-red recolour PR should rerun the same strips.
- Surfaces (`arena_surface.gdshader`, `arena_materials.gd`): a stepped
  per-solid sector level (up to 14 percent darker, from the solid's own
  centre), a wall-base contact shade that also works on Performance where SSAO
  is off, service steel darkened to dark steel with an emissive `on_air`
  warning strip, and a thin emissive red pinline under the enamel band. Union
  spaces now read black and red against the institutional green.
- Quality (`render_quality.gd`): Balanced now adds low-quality SSAO and fixture
  glow; High uses medium SSAO. Performance gets neither; its only added work is
  the unshadowed practical pools. OpenGL per-object lights are raised to 16 so
  the single map floor sees every fixture.
- Stage 1: `video/pixel_scale` (Native, Fine 540 lines, Medium 360, Chunky 270;
  a whole-number nearest upscale chosen from the actual output) and
  `video/dither` (ordered 4 by 4 Bayer onto the world swatches of the palette,
  cyan and magenta accents excluded, aligned to the world pixel grid, on a
  canvas layer under the HUD and owned by the match scene so menus are never
  dithered). Both validate and persist through `settings.gd` and appear on the
  GRAPHICS page, whose labels now come from `client/i18n/world.en.po`. A world
  pixel choice replaces FSR while selected.
- **Default: Native, dither off.** At 1080p Fine keeps the large signs, but the
  intake's far sign and the floating pickup label break up; Medium also breaks
  the complaints notice. World text was authored for native resolution, so the
  pixel look stays opt-in until signs and labels are re-authored for a low-res
  grid.

**Frame time, this host.** Windows 11, AMD Radeon 780M (integrated), Godot
4.7.2, 1920 by 1080 window, VSync off, frame cap off, 600 frames per state
after 30 warm-up frames, measured by `frame_sample` in `qa_tour.gd` with
`client/qa/look-perf.json` (Arena Duel, five bots) and `client/qa/m01-perf.json`
(M01 intake, no bots). Mean and 95th percentile are wall time between drawn
frames; GPU is the renderer's own measurement. "Before" is `origin/main` at
0107197 with the same harness. Repeat runs of one build moved the mean by up to
1.5 ms, so read smaller differences as noise.

| Renderer | View | Before mean / p95 / GPU ms | After mean / p95 / GPU ms |
|---|---|---|---|
| OpenGL | Arena Duel overview, performance | 3.26 / 5.59 / 2.34 | 3.52 / 5.75 / 2.8 |
| OpenGL | Arena Duel overview, balanced | 3.36 / 5.81 / 2.71 | 5.41 / 7.37 / 4.7 |
| OpenGL | Arena Duel overview, high | 5.94 / 8.3 / 5.38 | 6.44 / 8.21 / 5.89 |
| OpenGL | Arena Duel first person, performance | 2.98 / 5.64 / 1.92 | 2.99 / 5.4 / 2.33 |
| OpenGL | Arena Duel first person, balanced | 3.55 / 6.34 / 2.58 | 4.52 / 6.51 / 4.0 |
| OpenGL | Arena Duel first person, high | 5.13 / 7.38 / 4.6 | 5.62 / 7.67 / 5.13 |
| OpenGL | M01 intake, performance | 5.03 / 10.66 / 2.78 | 5.07 / 10.64 / 3.38 |
| OpenGL | M01 intake, balanced | 5.04 / 10.35 / 3.48 | 8.83 / 14.59 / 7.36 |
| OpenGL | M01 intake, high | 7.4 / 12.99 / 6.29 | 9.48 / 14.47 / 8.28 |
| Vulkan | Arena Duel overview, performance | 4.66 / 6.89 / 3.25 | 4.42 / 6.4 / 3.1 |
| Vulkan | Arena Duel overview, balanced | 5.96 / 7.73 / 4.53 | 8.96 / 10.8 / 7.42 |
| Vulkan | Arena Duel overview, high | 9.04 / 10.61 / 7.53 | 9.9 / 11.52 / 8.74 |
| Vulkan | Arena Duel first person, performance | 4.95 / 8.05 / 3.04 | 3.99 / 6.09 / 2.73 |
| Vulkan | Arena Duel first person, balanced | 5.18 / 7.15 / 3.7 | 8.82 / 12.08 / 7.05 |
| Vulkan | Arena Duel first person, high | 8.09 / 9.76 / 6.66 | 9.41 / 11.08 / 7.95 |
| Vulkan | M01 intake, performance | 8.02 / 14.08 / 4.38 | 7.21 / 14.0 / 4.66 |
| Vulkan | M01 intake, balanced | 7.59 / 13.31 / 5.36 | 12.19 / 16.2 / 9.77 |
| Vulkan | M01 intake, high | 11.49 / 16.05 / 9.17 | 15.59 / 20.49 / 12.91 |
| OpenGL | M01 intake, balanced fine | n/a | 6.42 / 12.34 / 3.74 |
| OpenGL | M01 intake, balanced medium | n/a | 6.51 / 12.09 / 3.1 |
| OpenGL | M01 intake, balanced chunky | n/a | 6.36 / 11.67 / 2.76 |
| OpenGL | M01 intake, balanced medium dither | n/a | 7.21 / 12.55 / 4.09 |
| OpenGL | M01 intake, performance medium | n/a | 4.87 / 10.67 / 1.47 |
| Vulkan | M01 intake, balanced fine | n/a | 7.01 / 13.47 / 3.93 |
| Vulkan | M01 intake, balanced medium | n/a | 7.34 / 14.56 / 2.63 |
| Vulkan | M01 intake, balanced chunky | n/a | 6.96 / 15.35 / 2.14 |
| Vulkan | M01 intake, balanced medium dither | n/a | 7.72 / 16.3 / 3.45 |
| Vulkan | M01 intake, performance medium | n/a | 5.73 / 12.31 / 1.04 |

Performance stays cheap: its mean frame time is within noise of before, and its
GPU time rises by at most 0.6 ms (the unshadowed practical pools).
Balanced costs about 1.5 to 4.5 ms more GPU (SSAO, glow and, indoors, practical
shadow maps); High about 0.5 to 4 ms more. The world pixel choices cut
Balanced intake GPU time from 7.4 ms to 2.8 to 3.7 ms on OpenGL and from 9.8 ms
to 2.1 to 3.9 ms on Vulkan; the dither adds about 1 ms. Performance with Medium
pixels is the cheapest configuration measured (1.0 to 1.5 ms GPU). This is one
integrated GPU, not a hardware promise.

**Still weak.** Arenas improved least: they have no registered fixtures, so the
change there is colour, haze and shadow contrast rather than pools of light. The
bright enamel walls of M01 still tile visibly in large rooms; the sector steps
help at corridor scale, not across one long wall. Muzzle flash and impact light
belong to `shot_effects.gd`, which the weapons PR owns; the follow-up is a
short-lived `OmniLight3D` per acknowledged shot and impact in the practical
group so quality controls its shadow. The wall-base shade assumes three-metre
decks and paints a faint band at three metres on taller walls.

## Verification

- `tools/godot_check.sh` (import, parse, harnesses) on every stage.
- `tools/qa_tour.sh --publish` regenerated and inspected stills committed with each stage; `docs/screenshots/README.md` describes what is live.
- A frame-time note in the PR: 60 frames per second at 1280 by 720 on the reference machine with four bots, measured with the engine's monitor.

## Success criteria

- [ ] Stage 1 lands with the toggle and stills. Implemented in increment 1; the default stays Native until world text is re-authored for a low-res grid.
- [ ] Both maps re-dressed with the atlas.
- [ ] Fighters read at thirty metres: the far-cam harness asserts sprite height in pixels at 30 m, and a still shows direction and state.
- [ ] Every weapon is identifiable by its view model silhouette alone: a silhouette contact sheet of the three view models committed with the stills.
- [ ] No overlapping HUD elements in any tip still, and no still outside menus with more than one line of HUD text plus the killfeed.
