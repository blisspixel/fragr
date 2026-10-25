# First-person weapons

The drawn set from the 2026-10-02 art pass
([plan](../../../../docs/plans/art-pass-20261002.md)). Every hand wears the same
worn brown leather work glove with a rust-brown jacket cuff, and every gun shows
a drawn fire frame with its own muzzle flash. `WeaponArt`
(`client/scripts/weapon_art.gd`) is the only table that names these files.

| Weapon (wire id) | Rest | Shot | After the shot |
|---|---|---|---|
| Fists (`Fists`) | `fists_idle.png`, split into two arms by `MeleeView` | | |
| Shiv (`Shiv`) | `shiv_idle.png`, thrust by the HUD | | |
| Pistol (`Tack`) | modelled: `../tack/idle.png` | `../tack/fire.png` | `../tack/recover_0..1`, reload `reload_0..6`, raise `draw_0..2` |
| Rifle (`Flechette`) | `rifle_idle.png` | `rifle_fire.png` | `../flechette/recover_0..1` (smoke and spent case) |
| Shotgun (`Scatter`) | modelled double: `../scatter/idle.png` | `../scatter/fire.png` | recover, break-open reload `reload_0..5`, raise |
| Railgun (`Rail`) | modelled: `../rail/idle.png` | `../rail/fire.png` | coils dark then recharging, cell-swap reload `reload_0..6`, raise |
| Sniper Rifle (`Sniper`, Level 7) | `sniper_idle.png` | `sniper_fire.png` | |
| Rocket Launcher (`Rocket`) | `rocket_idle.png` | `rocket_fire.png` | |
| Article Blade (`Article Blade`) | `article_blade_idle.png` | `article_blade_swing.png`, 0.0 to 0.18 s | |
| Grenade throw | `grenade_ready.png`, then `grenade_throw.png` while the gun dips | | |

Each idle is an edit of the 2026-09-19 raw idle for that gun, so the camera and
framing carried over; each fire frame is an edit of its own approved idle. All
frames are 241 by 180 RGBA on the full 4:3 canvas (`--no-trim`), palette-locked
to `docs/palette.json`, so a gun's frames register without offsets. The fire
frame shows for 0.08 s; the HUD's kick translation still applies on top.

Preparation: `fragr-spritegen reduce --input <raw> --out <dir> --height 180
--no-trim --palette docs/palette.json --key ff00ff`. Prompts, request IDs,
estimated costs and hashes are in `../../art-pass-20261002-manifest.json`; the
specs are `tools/spritegen/specs/art-pass-20261002-*.json`. The Rifle's two
frames were redrawn in the second art pass in the Pistol's flat grey-green
enamel, with the same framing (`../../art-pass-2-20261002-manifest.json`).
Nearest filter, no mipmaps. The Shiv's 48 pixel icon still comes from
`client/art/weapons/` through `tools/bake_shiv.gd`.

The modelled Pistol, Shotgun and Railgun share a wider 384 by 240 canvas,
shown at the same two reference pixels a texel, so a held pistol spans about a
quarter of the screen. Rebuild them on a GPU display after any model change:

```sh
godot --path client --rendering-driver vulkan --windowed \
  --script ../tools/bake_viewmodels.gd
```

The HUD lowers the old gun and raises the new one on a switch (the modelled
guns through their `draw` frames, the drawn ones by sliding), lags the gun
behind the look, dips it on landing and tints it with the light at the gun.
