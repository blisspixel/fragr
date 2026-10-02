# Earth surface tiles

Eight selected opaque 128-square albedo tiles for the existing Earth venues. The
[batch plan](../../../../docs/plans/earth-surface-texture-batch.md) records the
scope and allocation. `manifest.json` records exact prompts, parameters, source
hashes, reservations and keeper decisions. Large 2048-square originals and request
ledgers remain in ignored local storage, with a backup under
`art/raw/earth-surfaces-20261001/`. No raw originals enter the game package.

The eight medium candidates were selected after palette reduction and repeated
tile inspection. Two low exploration and two high comparisons remain rejected
source experiments. The high plaster became nearly flat bone; the high plate's
large diagonal wear repeated more conspicuously. Higher request quality did not
improve these final-scale candidates.

`processed/` holds the selected source tiles; identical runtime copies live under
`client/assets/environment/earth/`. `review/` contains 3 by 3 repeats. Files use the
current canonical palette, full opacity, nearest sampling and no mipmaps. A
eight-metre repeat matches the current shader's 16 texels per metre. Distant
backdrop roof meshes use their existing standard UV mapping rather than this
world-projected density. Depth-derived normal maps are not
included. Workshop patches are deliberately stronger than the other fields and
need restrained vertical material strength. Roof tar is intended for horizontal
roof surfaces, never all walls.

Preparation uses the existing area reducer without trimming, then
`tools/prepare_earth_tiles.gd` blends only eight-pixel opposite-edge bands. A final
pass through the existing CIE Lab palette reducer follows. The preparation tool's
`--verify` mode then checks unchanged 128-square images for full opacity, exact
canonical colors and matching opposite edges. Final edge mean and maximum are
zero for all eight selected tiles. This numerical gate accompanies visual repeat
inspection; it does not establish in-play lighting or actor readability.

Root owns the separate full-tile shader layer and venue mapping. Existing repair
overlays, world lighting and authoritative geometry stay intact. Clean import,
material checks and inspected rendered venue views remain integration gates.

Twelve accepted and downloaded requests reserved an estimated $1.937, within the
explicit exploration, medium and comparison caps. Provider billing remains
unreconciled. No new cash purchase, duplicate generation, top-up or overage was
introduced.
