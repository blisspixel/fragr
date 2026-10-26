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

- `weapons/tack/`, `weapons/scatter/`, `weapons/rail/` - the modelled Pistol,
  Shotgun and Railgun baked by `tools/bake_viewmodels.gd` from `scripts/gun_model.gd`:
  rest, `draw_0..2`, `fire`, `recover_0..1`, `reload_*`, the world/held `profile`
  and the 48x16 `kill` glyph
- `weapons/flechette/` - the Rifle's recovery frames and the shared drawn flash
  (`tools/bake_flechette_frames.gd`); `weapons/kill/` - kill glyphs for the
  drawn weapons (`tools/bake_kill_icons.gd`)
- `weapons/viewmodels/` - drawn first-person frames; see its README
- `weapons/pickups/` - side profiles at one texel density: world pickups and the
  gun a fighter holds (`rifle`, `sniper`, `rocket`, `article_blade`)
- `weapons/48/shiv.png` - the Shiv pickup and held icon
- `weapons/sniper/scope_overlay.png` - 360 px square scope plate with a
  transparent aperture, from `tools/bake_scope_overlay.gd`
- `pickups/` - `medkit`, `armor`, `bullets`, `shells`, `cells`, `grenades`
- `hud/` - `health` and `armor` vitals icons, drawn at twice their size


## tiles/16
- `floor` `wall` `hazard` `spawn_a` `spawn_b` + `tileset_16x80.png`

## vfx
- `32/muzzle_flash.png` - the first-person flash and the fallback third-person flash
- `shots/` - per-gun third-person muzzle flashes, `impacts.png` (six frames
  each for concrete, metal, flesh, synthetic, Railgun and melee) and
  `marks.png` (the pocks and dents a shot leaves)
- `blast/` - the ten-frame fireball, smoke, debris, two scorches, the rocket,
  grenade and canister skins, the rocket flame and a neutral wear mask

All of `shots/` and `blast/` is baked from code by
`godot --headless --path client --script ../tools/bake_shot_vfx.gd` from the
repo root; `ShotVfx` (`client/scripts/shot_vfx.gd`) owns the tables that use them.

## ui
- `boot_splash.png` is the approved `docs/fragr-logo-refined.png`, baked with
  `godot --headless --path client --script ../tools/bake_boot_splash.gd` from the
  repo root. The bake preserves decoded pixels. Engine startup uses aspect-fit
  scaling and nearest filtering; regenerate from the source when branding changes.
- `on_air.png` `contested_frequency.png` `hangar_candy.png` `chrome-strip.png` - broadcast plates (Contested Frequency, ON AIR and the Hangar Candy sponsor), kept as reference art for the radio's own UI. Dull, not neon. The match HUD carries no radio ident; its badge crops were removed.

## factions/free_coalition

- [Rattlesnake banner](factions/free_coalition/README.md): 1536 by 1024 source,
  inspected and imported; not placed in a current map. Its manifest records the
  prompt and preparation. Small decals require a reviewed size-specific bake.

Boomer-arena. No Doom IP.
