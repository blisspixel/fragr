# Prepared model sources

## Clerk

`clerk.glb` is the selected humanoid production source from the October 3 paid
model pilot. It retains the reviewed 24-bone skin and one in-place walking clip.
The raw walking GLB remains in the ignored production archive, SHA-256
`9e0f52db0dfff86fab95c8a65fbf8876aa8d32cc68a6bc928a582c47e526ded5`.
The paid pilot, request parameters and account reconciliation are recorded in
[`docs/evidence/meshy-pilot-20261003.md`](../../../../docs/evidence/meshy-pilot-20261003.md).

Preparation uses `tools/prepare_clerk_source.gd` with the raw walking GLB and
an output path as its two user arguments. It embeds 1024-pixel PBR maps, retains
skin and gait, removes optional software metadata and preserves legal copyright.
The green fabric is graded to the established charcoal Union cloth while keeping
face, bone plates, wear and red issue marks. No additional paid generation is
needed to reproduce this preparation.

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
