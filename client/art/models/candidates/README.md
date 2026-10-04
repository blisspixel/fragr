# Prepared model sources

## Clerk

`clerk.glb` is the stylized black-and-red humanoid revision from October 3.
It retains a 24-bone skin and one in-place walking clip. Angular painted facial
planes, a black high-collar uniform, dark steel plates, peaked service cap and
clear red issue band replace the previous photographic human direction.
The raw walking GLB remains in the ignored production archive, SHA-256
`bfbd2374e73d95dbac71ab4ecddc11b9b9cab66c5cf3fdb486ba75368dd3d845`.
The prepared source SHA-256 is
`166a6eab7a203f1e80fb089fc6dc2d39c37f72e2e77b09a234c9d15c22e4cf14`.
The paid pilot, request parameters and account reconciliation are recorded in
[`docs/evidence/meshy-pilot-20261003.md`](../../../../docs/evidence/meshy-pilot-20261003.md).

Preparation uses `tools/prepare_clerk_source.gd` with the raw walking GLB and
an output path as its two user arguments. It embeds 1024-pixel PBR maps, retains
skin and gait, removes optional software metadata and preserves legal copyright.
The new reference already has the Union's black/red outfit signature. The
preparer's legacy green-cloth conversion leaves its painted face, black uniform,
steel and red marks intact. No additional paid generation is needed to reproduce
preparation from the retained source. The revision's model and rig used 40 existing
credits under the [bounded plan](../../../../docs/plans/union-field-uniform.md).

`../clerk_source.gd` supplies the authored combat, unarmed, seated and collapse
poses. `../../characters/bake.gd` bakes the existing eight-direction layout and
paired view normals. The bake receipt hashes the prepared GLB and pose source.
Both source geometry and these scripts are offline art, excluded from desktop
exports. Runtime uses the committed sprite and normal atlases, not a live
generation service or the source animation player.

This accepts one human source for further presentation work. It does not finish
the remaining cast, weapons, environmental kit or campaign.

## Shotgun production candidate

`shotgun.glb` prepares the reviewed controlled-topology weapon, raw SHA-256
`6f7078f594262c23de7d599868285ac7e62046a100dace5c934a53c0f1a96f22`.
`tools/prepare_shotgun_source.gd` requires that exact raw GLB and the output path.
It separates the independently verified 1,496-triangle fore-end from the body,
retains all 12,853 triangles and existing UVs, embeds 1K maps and preserves legal
notices. The prepared source is about 4.5 MB and has two mesh pieces.

`../shotgun_imported_source.gd` attaches authored hands and reuses the existing
recoil and pump cadence. The support glove shares the pump node; the barrel and
muzzle remain fixed in weapon space. `tools/preview_shotgun_source.gd` renders
twelve frames into a supplied local output directory with a real framebuffer.
The mechanical and map-budget harness passes. Framing and hand refinement remain
in flight under [`shotgun-model-presentation.md`](../../../../docs/plans/shotgun-model-presentation.md).

This source is excluded offline art. It does not replace the selected weapon
viewmodels, prove final first-person quality or establish a finished weapon set.
