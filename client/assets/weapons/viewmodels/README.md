# First-person weapons

One coherent set from the 2026-10-02 art pass
([plan](../../../../docs/plans/art-pass-20261002.md)). Every hand wears the same
worn brown leather work glove with a rust-brown jacket cuff, and every gun shows
a drawn fire frame with its own muzzle flash. `WeaponArt`
(`client/scripts/weapon_art.gd`) is the only table that names these files.

| Weapon (wire id) | Rest | Shot | After the shot |
|---|---|---|---|
| Fists (`Fists`) | `fists_idle.png`, split into two arms by `MeleeView` | | |
| Shiv (`Shiv`) | `shiv_idle.png`, thrust by the HUD | | |
| Pistol (`Tack`) | `pistol_idle.png` | `pistol_fire.png` | |
| Rifle (`Flechette`) | `rifle_idle.png` | `rifle_fire.png` | |
| Shotgun (`Scatter`) | `shotgun_idle.png` | `shotgun_fire.png` | `shotgun_pump.png`, 0.18 to 0.44 s |
| Railgun (`Rail`) | `railgun_idle.png` | `railgun_fire.png` | |
| Sniper Rifle (`Sniper`, Level 7) | `sniper_idle.png` | `sniper_fire.png` | |
| Grenade throw | `grenade_ready.png`, then `grenade_throw.png` while the gun dips | | |

Each idle is an edit of the 2026-09-19 raw idle for that gun, so the camera and
framing carried over; each fire frame is an edit of its own approved idle. All
frames are 241 by 180 RGBA on the full 4:3 canvas (`--no-trim`), palette-locked
to `docs/palette.json`, so a gun's frames register without offsets. The fire
frame shows for 0.08 s; the HUD's kick translation still applies on top.

Preparation: `fragr-spritegen reduce --input <raw> --out <dir> --height 180
--no-trim --palette docs/palette.json --key ff00ff`. Prompts, request IDs,
estimated costs and hashes are in `../../art-pass-20261002-manifest.json`; the
specs are `tools/spritegen/specs/art-pass-20261002-*.json`. Nearest filter, no
mipmaps. The Shiv's 48 pixel icon still comes from `client/art/weapons/` through
`tools/bake_shiv.gd`.
