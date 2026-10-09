# Splice compact rigid source

Status: implemented locally for the prepared source, 2026-10-08. The ignored
compact artifact passes exact source preservation, actual native animation and
support checks, and the inspected source comparisons below. Live integration
remains in flight in the [owning plan](../plans/splice-mechanical-source-20261008.md).
The [machine receipt](splice-compact-source-20261008.json) binds actual artifacts,
frozen recipes, measurements, inspected originals and retained failures.
Zero requests, model credits or cash were consumed.

## Prepared artifact and actual engine checks

The 6,115,980-byte ignored `compact-third/splice-prepared.glb` has SHA-256
`002749ba040d15703605693563b6e1b1f1ceebe554ebb2a5e2461da2f1f48f98`.
It derives from the unchanged original source
`4560940190c9877b78885e3138c5e3628e9bfe906474ca14f54986931bbe19f1`
and the reviewed 17-region partition
`f2191a008a44537b821b80da5bdf181958f69890bf6b9d388a51e1d75ebeb7a8`.
Original position, normal, UV and winding payloads, all 16,602 original faces
and every non-image buffer payload remain unchanged. Added hierarchy, clips and
908 cap triangles are separate. Required legal metadata is preserved.

The native recipe copies source buffers directly rather than exporting decoded
original meshes. It resizes paint/normal from 4096 square and packed material
from 2048 square to three embedded 1024-square maps. Original paint is retained;
matte response uses metallic factor 0.08, roughness factor 1 and a nominal packed
green floor of 0.88. Native import confirms all map sizes, enabled normals,
nearest mipmap filtering and those factors. Eight-bit storage quantizes the
actual minimum green value to 224/255, approximately 0.8784314.

The actual GLB reloads in the pinned engine with its measured 17-pivot rigid
hierarchy, 28 cap meshes, and 129-key `calm` (4 s) and `walk` (2 s) clips.
The calm clip includes bounded screen/head turning. Root support translation
is baked from indexed original soles, with measured support keys and eight
joint-to-joint limb lengths retained. The right upper-leg and partial diagnostic
rack region share the complete stored attachment's transform. Independent grips,
tool motion and finger articulation remain open.

| Actual reloaded measurement | Result |
|---|---:|
| Off-grid calm / walk samples | 256 / 256 |
| Rest height | 1.79999995 m |
| Reversible rest error | 1.193e-7 m |
| Maximum supported sole error | 0.000214 m |
| Maximum original-surface difference from source adapter | 0.000312 m |
| Maximum imported cap local position difference | 3.502e-6 m |
| Maximum moving native cap rim error | 3.364e-6 m |
| Maximum moving native cap-center difference | 5.685e-7 m |
| Shared stored attachment transform drift | 0 |

Actual native triangle correspondence checks every imported cap triangle and
its source counterpart. Rim and center measurements use the actual imported
cap vertices through the sampled hierarchy, not only authoring pivots. The
measured native cap limits are 1e-5 m at the rim and 2e-5 m between centers.
The receipt also retains the earlier welded-witness measurements with their
narrower precision scope; those are not substituted for actual cap vertices.

Five actual failure controls reject a frozen clip at a moving phase, raised
exported root, detached exported rack, omitted exported cap and changed exported
cap vertex. The unchanged positive rest and quarter-phase controls pass.

## Original-frame review and retained failures

The owned comparison renderer returned numeric 0 with clean logs and retired.
It retained 40 static originals in 20 paired states and 96 timed exported-clip
frames on the local compatibility renderer at 1024 x 768. All 20 compact static
originals, six matching source originals and eight moving originals were
inspected at full size. A separate review inspected six selected original files;
its exact paths and hashes are bound separately. Neither review claims every
timed frame or establishes a frame-rate benchmark.

The inspected compact front/side/back silhouettes, walking extremes, calm turn,
dim joint close-ups and distant views keep the original shell, mechanical
detail, rust left forearm, magenta right wrist, horizontal screen and secured
right-side tools. The maps give the intended matte pixel surface response.
The supported gait and contained cap geometry agree with the source controls,
without the previously rejected sphere bulges.

Representative images below are byte-identical originals, with matching source
controls retained in the machine receipt:

| Control | Original |
|---|---|
| Compact rest | [Front](splice-compact-source-20261008/compact-rest-front.png) |
| Matching accepted source rest | [Source front](splice-compact-source-20261008/source-rest-front.png) |
| Compact walking side | [Side](splice-compact-source-20261008/compact-walk-side.png) |
| Compact walking back | [Back](splice-compact-source-20261008/compact-walk-back.png) |
| Dim front joints | [Front joints](splice-compact-source-20261008/compact-joints-front-dim.png) |
| Dim back joints | [Back joints](splice-compact-source-20261008/compact-joints-back-dim.png) |
| Distant dim control | [Distant](splice-compact-source-20261008/compact-distant-dim.png) |

Retained failures include the initial parser name collision, the next
preflight's incorrect assumption that all maps were 4096 square, and a stricter
native-cap string-bucket diagnostic. The latter found imported cap positions
differing by up to 3.502e-6 m and reversed native triangle index order. The full
cap dump and exported float comparison remain retained. The final check uses
per-triangle point correspondence and measures actual transformed errors.
The original artifact bytes were unchanged through this diagnostic correction.
Earlier rejected partitions and spherical closures remain in the separate
[source-candidate checkpoint](splice-mechanical-candidate-20261008.md).

## Remaining boundary

The rigid root, named pivots, original surface children, paired cap names,
measured lengths, support samples and clip durations form the local source
handoff. `SkinnedCharacter` requires a humanoid skeleton and does not accept this
artifact. A coordinated rigid presenter still needs actual live feet/gait and
lighting validation through the existing named civilian eligibility seam.
M05 actual evacuation, omitted/Unknown controls, ordinary workshop and later
crew routes, current-map captures, composed client/package checks and final
human/art acceptance remain required. All exported artifacts and proposed
runtime work stay in ignored diagnostics while production composition is
frozen; no production client, mission, support registry or native server file
changed for this source increment.
