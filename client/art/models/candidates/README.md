# Prepared Clerk source

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
