# Civilian Rifle source refinement evidence

Date: 2026-10-04. Status: **in flight**, offline source only. Runtime Rifle
art remains unchanged. This cut spends $0; the shared production receipt owns
the earlier 15-credit source.

## Source and physical mechanism

Reviewed raw SHA-256:
`5d53e8995a825b4e594c9b812759dcb070342bfddc73bd64ba351ea9a0576394`.
Prepared source SHA-256:
`a27602ecaaf138cc21dabea89ceb23fe3febc1755f9afd2d79af4f74bdc3372f`.
The preparation receipt binds the exact source and preparation script.

All 6,122 original triangles remain: Body 5,818, Bolt 216 and Trigger 88.
No new gun triangles are added. Bolt islands 5149 and 6173 include the actual
moving handle; trigger island 5719 moves within fixed guard island 5343.
Furniture, magazine, barrel and muzzle remain fixed within the recoiling gun.
The normalized source is 0.94 m long, faces -Z and embeds 1K maps. The source
import uses uncompressed embedded images and disables generated LOD. Actual
loaded material paths confirm it has no extracted texture dependency.

Charcoal, walnut and restrained sage values replace bright scratch patterns.
Nearest sampling, four-texel clusters, metallic 0.06, roughness 0.96 and normal
scale 0.20 are deliberate offline material choices. Visual quality cannot be
inferred from those numbers.

The presentation moves the bolt and handle 30 mm and pivots the trigger,
returning within 0.14 s, below the existing 0.20 s Rifle cooldown. Forty-one
sampled times prove fixed furniture, muzzle and glove transforms, actual
stroke and independent trigger motion. Invalid and settled times restore
rest without accumulated offsets. There is no magazine or reload mechanic.

## Contact and retained failures

The contact gate computes distance to the source mesh's actual triangle
surfaces. It tests the authored index fingertip against the trigger and the
support fingertip against the handguard, using their actual radii. This is
more specific than overlap with a whole-weapon bounding box.

The first contact helper produced a typed nested-array runtime error. That
log is retained despite the engine's zero exit code. The corrected helper
then rejected a support glove too far below the curved handguard. Raising
the glove to the actual surface passed without relaxing the radius. Final
`test_rifle_source.gd` completes with a clean log and its own PASS marker.
The source, receipt, embedded-map and mechanical assertions also pass.

Private logs are retained under `.agents/rifle-source-20261004/`, including
`test-refined-contact.log`, `test-refined-contact-fixed.log`,
`test-refined-contact-raised.log` and `test-refined-embedded.log`.
Only this source's untracked default-import sidecars were moved to the
private diagnostic directory after embedded-map validation.

## Remaining acceptance

Studio inspection, actual fingertip readability, bore/sight clearance and
held/pickup pixel framing remain open. Preserve the existing 241x180 held
and 80x19 pickup canvases. Candidate pixel, bottom registration and inherited
bob/fire/resize gates precede a matched ordinary gameplay comparison.
Runtime selection, full client checks, public CI and exported packages remain
separate later gates. No frame or unit test proves whole-arsenal completion,
campaign gameplay acceptance or hardware frame rate.

The first seven-pose offline studio completed with a clean PASS. Its held
framing was left-heavy and the support palm read as a hanging paddle, despite
the fingertip contact gate. That rejected frame set remains retained as
`studio-refined-first`. The next source keeps contact and physical dimensions,
turns the palm beneath the horizontal handguard and uses geometry-derived
receiver/sight plane contrast. The second clean studio reveals a wrist/palm
gap and an overly straight held view. Those frames remain retained in
`studio-refined-second`. The source now connects the wrist to the palm, and
actual surface-distance gates plus a separated-wrist negative control pass.
The next middle three-quarter camera awaits inspection. Unit contact is
useful evidence but does not replace a readable authored grip.
