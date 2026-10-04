# Sniper Rifle offline source refinement

Status: **in flight**, 2026-10-04. No runtime selection or whole-arsenal claim.
The [bounded plan](../plans/sniper-source-refinement-20261004.md) preceded the
work. Local preparation and inspection use $0 in additional charges.

## Measured source and repair

The reviewed raw source is one fused mesh with 11,835 triangles, 13,792 vertices,
embedded source maps and no bones or clips. Raw SHA-256 is
`4a1d5a0e405410feb385514a6878cf0b9476c298fbcf3456d8674e4797998bcb`.
Connected-component analysis does not support claiming naturally independent
bolt parts. The scale is a provisional 1.18 m overall length, not a measured
real-world firearm specification.

| Original geometry disposition | Triangles |
| --- | ---: |
| Untouched outside four measured replacement masks | 8,993 |
| Fully replaced inside the masks | 2,501 |
| Clipped original faces | 341 |
| Total original faces | 11,835 |
| Retained fragments produced by the clipped faces | 559 |
| Actual prepared retained-source geometry | 9,552 |
| Separately authored bolt, guides, lips, liners, housings and lenses | 3,992 |
| Total prepared gun, excluding gloves and diagnostic flash | 13,544 |

The 38 original muzzle-cap faces belong to the untouched-topology group but
are moved inward 22 mm and colored as a recess. They are excluded from the
unchanged-position proof. The remaining 8,955 untouched Body triangles retain
their original position, UV and oriented winding multiset at quantization
grid 4,093. The actual imported candidate has zero missing triangle hashes.
Moving the UVs or reversing triangle winding fails the same test. Additional
clipped fragments are counted separately and are not passed off as untouched
original faces.

Prepared GLB SHA-256:
`859f136bdde598471ccdb418c24d2d25f84d1fe08dff181a76c1116e317db726`.
The adjacent preparation receipt binds the raw, tool, replacement masks,
retained multiset and authored mesh counts. Embedded maps are limited to 1K,
with nearest sampling, broad face paint, matte metal and walnut. Generated LOD
and geometry compression are disabled for this offline source.

## Physical and presentation checks

The authored bolt unlocks by sixty degrees, travels 65 mm and settles by
1.10 s, before the unchanged 1.60 s server cooldown. The fixed barrel, scope,
receiver repair, furniture and gloves stay fixed relative to the gun.
The actual sampled clearance test queries vertices, edge midpoints and face
centres against all fixed triangles, including the gloves: 2,717 surface
samples, 250,729 motion segments and a 10 ms interval. The accepted geometry
has zero crossings. A downward-displaced bolt fails the same query. This is
sampled evidence, not a continuous collision guarantee for arbitrary motion.

Actual triangle queries reach the muzzle recess, reject its surrounding lip,
and verify five radial scope rays stay clear until the same flat 6.5 mm glass
depth. Both hollow optical housings meet the retained scope tube, and each
lens perimeter meets its liner. A displaced lens fails the original depth
query. Gloves retain real wrist/palm and fore-end contact. The idle index
supports the upper guard/receiver with trigger discipline. During the firing
picture, its two unchanged-length segments rotate onto the specifically
measured lower blade, stay connected and release by 180 ms. The same contact
query rejects a finger displaced onto the receiver. All nineteen sampled
finger poses join the conservative bolt-clearance envelope.

The first broad fused bolt mask included stationary hardware. A narrower
partition still reported 290 crossings over 55,522 segments and showed jagged
joint fragments, so it was rejected. The subsequent repaired joint passed
source review but retained inward optical wedges; those views were also
rejected before the flat supported lens repair. The first pixel bakes failed
lower-column registration and flash readability. Original diagnostics remain
retained, and the candidate has not been selected to sidestep those gates.

The final source, studio and candidate harnesses exit 0 with clean error logs
and their own PASS markers. The source keeps an exact 241 by 180 held canvas
and 100 by 20 pickup canvas, hard alpha, no mipmaps, the original lower-column
112 gate and a readable flash. The real HUD covers the bottom edge through
720 sampled moving/firing frames over three resolutions. The normal scope
field of view, held-art hiding and release pass without changing production
textures. These are source and presentation checks, not a benchmark or a
campaign playthrough.

## Remaining acceptance

Same-camera ordinary played held/fire, pickup, wall approach and scope
comparison remain open. Any played proof must
retain actual discovery, eight starting Cells, one accepted shot spending one
Cell, real resolved trace, ordinary action release and exact texture cleanup.
The Rust server, six physical slots, ammunition policy and scope behavior
remain unchanged. Runtime selection, full client integration and desktop
package checks are separate later decisions.
