# Graphics options and modern lighting

**Status:** planned, 2026-10-02. Nick asked for this; it is not built.
**Spend:** $0. Local only.

## Goal

Two linked pieces of work:
- **A Doom-style graphics menu.** The presets stay, and every major cost and
  look decision behind them becomes an individual option.
- **An Ultra preset** that makes the pixel world look modern under real-time
  global illumination, reflections and volumetric light.

Boltgun is the reference: pixel textures and sprites lit by a modern renderer.
Nick's words on 2026-10-02: "I know its like boomer shooter... but we can still
make it look good like ray tracing or something", and "you know how doom and
things have like graphics settings... that kind of thing should work too."

## What exists

`render_quality.gd` owns three presets (Performance, Balanced, High), with MSAA
and SSAO steps, glow on authored fixtures, a shadow-size step, resolution and
world-buffer scale, FSR 1 and FSR 2 where the renderer supports them, world
pixel scale and palette dither. Settings validate in `settings.gd` and edit in
`settings_panel.gd` on the Graphics and Display pages.

## Ray tracing, checked 2026-10-02

The [Godot 4.7 release notes](https://godotengine.org/releases/4.7/) list no
ray-traced effects. 4.7 adds low-level Vulkan ray tracing plumbing for future
work, with no ray-traced GI or reflection toggle. The path-traced NVIDIA fork
requires RTX hardware and a fork of the engine, which breaks the pinned
mainline 4.7.2 and the vendor-neutral rule in AGENTS.md. Revisit when mainline
ships ray-traced effects.

What mainline 4.7 does offer on Forward+:
- SDFGI, real-time global illumination traced against signed distance fields.
  It needs no baking, so it works with geometry built at runtime from MapInfo.
- SSIL (screen-space indirect light) and SSR (screen-space reflections).
- Volumetric fog with light shafts.
- AreaLight3D, new in 4.7: rectangular area lights, suited to fluorescent
  panels, screens and light boxes.
- HDR output, new in 4.7.

Verify each against the 4.7 documentation before use; do not trust this list
from memory.

## Options to add

Each option is a validated setting with a renderer capability gate. The
Compatibility (OpenGL) renderer shows unsupported options disabled, with a
note, the way FSR is today.

| Option | Values |
|---|---|
| Preset | Performance, Balanced, High, Ultra, Custom. Editing any option switches to Custom. Choosing a preset rewrites the options. |
| Anti-aliasing | Off, FXAA, MSAA 2x, MSAA 4x, TAA. FSR 2 keeps owning its own AA when selected. |
| Shadows | Off, Low, Medium, High (atlas size, filter quality, distance) |
| Ambient occlusion | Off, SSAO Low, SSAO High |
| Indirect light | Off, SSIL |
| Global illumination | Off, SDFGI (Ultra) |
| Reflections | Off, SSR (wet floors, Low Water, polished metal, glass) |
| Volumetric fog | Off, On (light shafts in dark venues and the lunar port) |
| Bloom | Off, On (the existing fixture glow) |
| Brightness | Gamma slider, so dark rooms stay readable on any display |
| HDR output | Off, On, where the platform and display support it |
| Effects density | Particles and decals, Low or High |
| Render scale, upscaling, pixel scale, dither | Keep, regrouped on the page |

Not added: motion blur, film grain, chromatic aberration or depth of field.
They fight pixel readability, and the fun bar requires any fighter to read at
thirty metres.

## Constraints

- The pixel style is law. Textures keep nearest filtering and no mipmaps.
- Preserve authored ambient light and the actor-only view fill on visual
  layer 1; world geometry stays on layer 2.
- Reapply after map environment replacement and viewport resize, as
  `render_quality.gd` does today.
- **Migration:** existing `video/quality` values 0 to 2 keep meaning exactly
  what they do now. Ultra and Custom are new values. Old settings files load
  unchanged.
- Venue practical lights (`arena_sky.gd`) can opt into AreaLight3D on Ultra
  without changing authoritative geometry.
- Server authority is untouched. This is presentation only.

## Verification

- **Tests:**
  - Settings validation, migration and capability gating in `test_settings.gd`
    and `test_settings_panel.gd`.
  - A `render_quality` harness asserting each option reaches the environment,
    viewport and lights.
- **Rendered evidence:** extend `client/qa/graphics.json` with captures per
  preset in at least three venues:
  - The M01 interior.
  - M04 Low Water, with water and reflections.
  - M06's lunar port, with volumetric light.

  Inspect every still, under both Vulkan and OpenGL.
- **Performance:** measured with the [rendered showcase benchmark](showcase-benchmark.md),
  per preset on the development machine. Record a table in this plan. No
  hardware-support claim beyond the machines actually measured.

## Order

Land the option plumbing and Custom preset first, with no visual change at the
existing presets. Then Ultra's lighting, inspected per venue. Then the
benchmark's scenes, which measure the presets. One agent can carry all three in
sequence; each lands as its own PR.
