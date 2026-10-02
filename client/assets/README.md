# client/assets - fragr Godot pack (sprites-as-code v2)

RGBA pixel sprites. Import: **Nearest**, mipmaps **off**. Use base sizes (32/64/16).

## Import settings

All PNG assets are configured with `.import` files for pixel-perfect rendering:
- Filter mode: Nearest (0) - no blurring/smoothing
- Mipmaps: disabled - prevents mipmap blurring at distance
- Compression: mode 0 (lossless or uncompressed)
- detect_3d/compress_to: 0 - preserves quality for 3D billboard sprites

When adding new assets, ensure import settings match existing .import files.

## weapons, pickups and HUD icons (2026-10-02 art pass)

`client/scripts/weapon_art.gd` (`WeaponArt`) is the one table that names these.
Prompts, request IDs, costs and hashes: `art-pass-20261002-manifest.json`.

- `weapons/viewmodels/` - first-person idle, fire and cycle frames; see its README
- `weapons/pickups/` - side profiles at one texel density: world pickups and the
  gun a fighter holds (`pistol`, `rifle`, `shotgun`, `railgun`, `sniper`)
- `weapons/48/shiv.png` - the Shiv pickup and held icon
- `weapons/sniper/scope_overlay.png` - 360 px square scope plate with a
  transparent aperture, from `tools/bake_scope_overlay.gd`
- `pickups/` - `medkit`, `armor`, `bullets`, `shells`, `cells`, `grenades`
- `hud/` - `health` and `armor` vitals icons, drawn at twice their size
- `weapons/32/_future/` - rocket_tube, shock_pistol, gravity_baton (do not wire)

## characters/64
- `cyanex_idle.png` `kragge_idle.png` - skin labels
- `*_idle_0..3.png` + `*_idle_strip.png` - 4-frame idle bob
- `fighters_idle_sheet.png`

## tiles/16
- `floor` `wall` `hazard` `spawn_a` `spawn_b` + `tileset_16x80.png`

## vfx/32
- `muzzle_flash.png` `rail_beam_tip.png`

## ui
- `boot_splash.png` is the approved `docs/fragr-logo-refined.png`, baked with
  `godot --headless --path client --script ../tools/bake_boot_splash.gd` from the
  repo root. The bake preserves decoded pixels. Engine startup uses aspect-fit
  scaling and nearest filtering; regenerate from the source when branding changes.
- `on_air.png` `contested_frequency.png` `hangar_candy.png` `chrome-strip.png` - full plates
- `on_air_badge.png` `contested_frequency_badge.png` `hangar_candy_badge.png` `chrome_strip_hud.png` - HUD crops (nearest)
- Contested Frequency / Hangar Candy / ON AIR broadcast grit. Dull, not neon.

## factions/free_coalition

- [Rattlesnake banner](factions/free_coalition/README.md): 1536 by 1024 source,
  inspected and imported; not placed in a current map. Its manifest records the
  prompt and preparation. Small decals require a reviewed size-specific bake.

Boomer-arena. No Doom IP.
