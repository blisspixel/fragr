# First-person weapons

Prepared locally from the accepted art slice and weapon bake-off on 2026-09-19.
The source prompts and provider/model are in `tools/spritegen/specs/slice-01-look.json`
and `tools/spritegen/specs/weapons-viewmodel-bakeoff.json`. No new generation call.

Sources: `art/sprites/slice-01/wpn_flechette_0.png`,
`art/sprites/slice-01/wpn_scatter_0.png`, and
`art/sprites/weapons-paletted/px_rail_issued_0.png`.

Preparation: `fragr-spritegen reduce --input <source> --out
client/assets/weapons/viewmodels --height 180 --no-trim --matte e8e2d6`.
The explicit matte removes only edge-connected bone pixels, preserving enclosed
weapon highlights. Outputs are 241 by 180 RGBA PNGs, nearest filtered, no mipmaps.
Keep the full canvas for a consistent weapon/muzzle registration. Inspect at game
size after regeneration. These are idle faces, not completed animation sets.
