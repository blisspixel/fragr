# First-person weapons

Prepared locally from the accepted art slice and weapon bake-off on 2026-09-19.
The source prompts and provider/model are in `tools/spritegen/specs/slice-01-look.json`
and `tools/spritegen/specs/weapons-viewmodel-bakeoff.json`. No new generation call.

Sources: `art/sprites/slice-01/wpn_flechette_0.png`,
`art/sprites/slice-01/wpn_scatter_0.png`, and
`art/sprites/weapons-paletted/px_rail_issued_0.png`. M01 also uses
`art/sprites/slice-01/wpn_fists_0.png` and
`art/sprites/weapons-paletted/px_tack_issued_0.png`, prepared with the same command.

Preparation: `fragr-spritegen reduce --input <source> --out
client/assets/weapons/viewmodels --height 180 --no-trim --matte e8e2d6`.
The explicit matte removes only edge-connected bone pixels, preserving enclosed
weapon highlights. Outputs are 241 by 180 RGBA PNGs, nearest filtered, no mipmaps.
Keep the full canvas for a consistent weapon/muzzle registration. Inspect at game
size after regeneration. The client animates recoil; fists
use separately posed halves with alternating punches and anchored wrists. These
are single poses, not completed authored animation sets. Tack's small held/pickup
icon currently reuses the existing `32/_future/shock_pistol.png` placeholder;
a matching side profile remains asset work.

`wpn_shiv_0.png` (240 by 180) and its `../48/shiv.png` icon come from
`client/art/weapons/` through `tools/bake_shiv.gd`; prompts and hashes are in
that folder's manifest. Its gauntlet enters from the lower right, so the thrust
scales the sprite from a pivot on the bottom edge instead of lifting it.
