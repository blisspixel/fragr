# Prepared model sources

## Sweeper and Auditor

`sweeper.glb` and `auditor.glb` are the October 4 prepared issued bodies,
with 24-bone skins, retained walking clips and embedded 1024-pixel PBR maps.
Their role sources share the Clerk's bounded loader and pose mathematics,
but keep separate cached scenes, silhouettes, hands and equipment.

The Sweeper uses two-handed rifle poses, recoil, recovery, unarmed strikes
and supported collapse. Its horizontal presentation calibration makes the
bot visibly broader than the Clerk while retaining height and fixed feet;
gameplay collision is unchanged. The Auditor carries a frontal shield with
two registered repair lamps, an upper-back cable and raised-hand channel
emitter. Both bake the existing 55-pose, eight-direction layout with exact
matching albedo/normal cells. Runtime uses those atlases, not these GLBs.
The earlier rigid Sweeper export remains a separate library asset.

Source, gait, equipment, channel and atlas gates pass locally. Played evidence
and remaining gates live in the [Sweeper plan](../../../../docs/plans/sweeper-stylized-source.md)
and [Auditor evidence](../../../../docs/evidence/auditor-source-20261004.md).
The full custody development-range clear remains open.

The same preparer produced Latch, but its actual live mesh is packaged at
`client/assets/models/latch_stylized.glb`, outside this offline directory.
The [Latch plan](../../../../docs/plans/latch-live-mesh.md) distinguishes
packaging, actual skin/gesture checks and mission-route acceptance.

## Free human

`free_human.glb` is the October 4 hatless civilian revision. It retains a
24-bone skin, a walking clip and embedded 1024-pixel PBR maps. The pose sampler
removes horizontal root travel when it uses the clip for the runtime strip.
Its SHA-256 is
`94f09896185df36697307e990ebce85fa7871c356be96394cac0a3dd83cd5dff`.
The measured unrigged candidate has 12,330 triangles. It uses an angular
painted face, short informal hair, a rust utility jacket, teal casual layer,
patched work trousers and practical shoes. The source is unarmed and carries
no gameplay collision. The [civilian revision receipt](../../../../docs/evidence/free-human-civilian-20261004.md)
retains its source and inspection history.

Preparation reuses `tools/prepare_clerk_source.gd` with its retained walking
GLB, output path and `FreeHuman` as the optional third argument. The preparer
retains non-Clerk colors, skin and gait, removes optional software metadata,
and preserves legal copyright. The import preset keeps images embedded.
`../free_human_source.gd` shares the existing pose cache, walking sampler and
arm solver while keeping the human's separate source identity and relaxed
empty-hand stance. `../../characters/player_bake.gd` renders the existing
eight-cell selectable strip with explicit studio illumination. This offline
source is excluded from desktop packages; the identical compact GLB is packaged
at `client/assets/models/free_human_live.glb` for the live player body.

Focused source and live-body boundary harnesses pass. Inspected bake views
show the civilian and issued bodies at the same camera scale. Whole-cast,
venue-light and fresh-player acceptance remain open under the
[cast plan](../../../../docs/plans/cast-model-buildout-20261004.md).

## Tern and Edda

`tern.glb` and `edda.glb` retain their distinct named civilian identities,
24-bone skins and original walking keys. Their prepared SHA-256 values are
`0f8bfd1c99b1d7c1172eaaa76203d28234a1d3f3db793f6f81bc6b5740fa993f`
and `cbf1e1e16329da194fdf058f308676e72bfefb357faeea915fc3d9500d57ea40`.
The [Tern preparation](../../../../docs/evidence/tern-source-preparation-20261008.md)
and [Edda repair](../../../../docs/plans/edda-live-repair-20261008.md) preserve
original source, legal metadata and the separately measured skin corrections.
Identical packaged copies at `assets/models/tern_live.glb` and
`assets/models/edda_live.glb` supply current eligible M09 and M10 appearances.
Splice's selected `assets/models/splice_live.glb` uses rigid articulated regions,
with source and provisional gait gates in the [mechanical plan](../../../../docs/plans/splice-mechanical-source-20261008.md).

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
