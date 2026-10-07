# Distinct venue wall materials

Status: **implemented**, local material selection and renderer checks,
2026-10-07. Bounded continuation of the existing environment texture
library, authorized by the current asset-build instructions and wall-art request.

The island's maintained salt-worn plaster, painted harbour boards and ribbed
working metal need a different material history from a custody tender's cold
pressure wall. Existing Earth, Low Water, lunar and civilian Carrier materials
remain registered by venue. Doors, signs and damage marks stay separate so
repeating textures cannot imply a usable door or unreadable route.

Produce four candidates through the native image tool. Exact price preflight and
a $2.50 prepaid ceiling precede generation. The previous four vehicle references
reserved $2.486 from Nick's reported $10.71, leaving an estimated $8.224 before
this batch. No new cash, top-ups or automatic overages are authorized.

Reduce selected candidates to 128-square palette tiles, repair periodic edges,
inspect repeated samples and then inspect actual wall lighting. Use the existing
EnvironmentTextures cache and surface shader. Keep floor values quiet, glass
transparent and surface texel density consistent. Materials are not collision.
Record request receipts, source hashes and selected output hashes. A completed
request is only a source candidate until the rendered review passes.

The four wall requests completed at a $2.480 estimate. Nick subsequently
reported **$5.86 remaining**, which supersedes the estimated account remainder.
Two quiet island ground candidates are priced at $1.240 total, with a separate
$1.25 ceiling inside that balance: coastal sand and low groundcover. This fixes
the visible generic terrain while keeping the wall library focused on buildings.

Both ground requests completed at the quoted $1.240 estimate, leaving an
estimated **$4.62** from the latest reported balance. There is no verified live
account balance receipt for that remainder. All six requests have durable
native receipts; no new cash or automatic top-up was used.

The first strict project-palette reduction failed review: pale plaster became
one flat value and painted boards acquired bright isolated pixels. Those
outputs were rejected. The selected 128-square tiles instead use muted venue
colors quantized to 24 steps per channel, with paired periodic edges. Repeated
samples were inspected for all six tiles. Runtime manifests retain source and
output hashes; texture imports use nearest filtering without mipmaps. The
existing shader and texture cache register the four wall tiles and two ground
tiles.

Actual Compatibility/OpenGL renderer checks pass for Earth, Low Water, lunar
port, lunar town, Right of Search and Holdfast. They verify bounded storage,
periodic edges, shared cache, distinct walking surfaces, preserved glass and
real response to a changed light. The tender test uses its selected enamel,
not another surface. Close views of the island plaster, boards and steel and
the ground/water composition were inspected at ordinary eye height. The scene
layout and landscaping remain a development blockout; these checks accept the
material increment, not finished island art.

The selected [island views](../evidence/island-art-20261007/receipt.json) retain
their production map and image hashes. The
[tender enamel sample](../evidence/screens/tender-pressure-tile-20261007.png)
shows the actual material under a controlled light, not a completed room.

The rendered check also exposed a fixture error: duplicating a material
materializes unset shader defaults, while a fresh material returns null for
those values. The comparison now applies the same duplication to both sides.
No runtime material values were changed to satisfy it. Evidence and rejected
attempt logs remain under `.agents/environment-tiles-final-20261007.log` and
the dated water/art inspection directory.
