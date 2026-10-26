# Larak Lot surfaces and decals

Six class tiles and one decal atlas, all read at 16 texels per metre with
nearest sampling and no mipmaps.

| File | Class | Where |
|---|---|---|
| `deck.png` | deck | the top of every cast-concrete solid |
| `wall.png` | wall | tall concrete: the shell, columns, screens, soffits |
| `kerb.png` | kerb | ground boxes up to 1.6 m: deck edges and retaining faces, read from the tile's bottom rows in 1.5 m deck bands so the tyre rub sits at the foot |
| `shear.png` | shear | the four shear walls and the Low Ramp screen; also the beam and soffit of the raised steel decks |
| `ramp.png` | ramp | steel treads, steps, the Bridge and canopy tops, the pad kit's steel |
| `pit.png` | pit | the ground plane: the Pit floor |
| `decals.png` | atlas | oil, tyre skids and burns, scorch (the Rocket cradle's blast mark), betting slips and tickets, league spray tags; cells in `LarakLot.DECAL_CELLS` |

Each class tile is 64 x 64, a 4 m repeat, prepared by
`tools/prepare_surface_tiles.gd` in recipe mode from one Higgsfield seed
(`tools/spritegen/specs/d-larak-surfaces-*-20261025.json`, marketing-studio
image, medium 1k) native-reduced to 128 px by `fragr-spritegen reduce`. The
recipe, `tools/larak_surfaces_20261025.json`, locks each tile to a five-step
ramp of `docs/palette.json` keys and two-key blends (lore-gate P10, pending
Nick) by luminance rank, with one broad field step, so the classes stay quiet
and mid-valued behind fighters. `manifest.json` records every subject, the
shared style and negatives, and the raw, reduced and runtime hashes. Seventeen
seeds cost $1.209 estimate-held; the ledger is the asset round's.

`decals.png` is baked for $0 by `tools/bake_larak_decals.gd` from the palette
and a fixed seed; rebaking reproduces it. Tags are shapes, never letters.

`ArenaMaterials.larak_class` draws the classes through
`arena_surface.gdshader`'s tile-albedo mode, which adds only light and detail
(macro value drift, sector steps, contact shade). `test_larak_surfaces.gd`
holds every surface, part, decal and pad pool to the one density.
