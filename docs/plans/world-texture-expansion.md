# World texture expansion

**Status:** in flight, 2026-10-01. Supports the current M06 integration and
release in the [full build order](../ROADMAP.md#full-build-order-2026-09-27).

## Goal and scope

Give Earth and the Moon distinct, carefully maintained material histories at
gameplay scale. Build a separate Mars material library for later authored levels;
this does not make a Mars mission playable. Follow the [art bible](../ART_STORY_BIBLE.md),
[world guides](../design/README.md) and palette. Warm personal repairs remain
different from institutional bone, dark steel and restrained warning red.

Three independent lanes prepare Earth, lunar and Mars candidates through the
existing developer-only image pipeline. Price each complete request spec before
submission. Inspect reduced palette tiles, repeated seams and actual rendered
surfaces. Promote selected assets only, retaining request receipts and source
hashes. No runtime generation, new service, dependency or authoring language.

## Integration

Reuse `ArenaMaterials` and the existing world-space surface shader. Add an
explicit opaque tiled albedo layer, separate from the existing vertical repair
overlay. Preserve procedural joints, warnings, grounded wear, lighting and
nearest filtering. Venue and surface select registered local textures; existing
collision and navigation remain untouched. Earth and Moon keep separate sets.
Future-only Mars textures receive an honest library preview and provenance.

Root owns shared shader/material changes and the overall spend ledger. Each
asset lane owns separate specs, output directories, durable request ledgers and
texture files. Never retry an uncertain generation POST or discard reservations.

## Spend

Nick requests additional existing-credit generation and reports $14.27 remaining
on 2026-10-01. This is an owner report, not an API balance measurement. The round
has $14.619 remaining after existing conservative reservations before this batch.
Reserve at most $5 combined for this batch, including exploration and promotion,
inside the approved $20 development round and $50 total. Exact live estimates and
explicit per-run caps are required before submission. No top-ups or overages.
Record accepted requests, estimated reservations and any verified billing
separately. Existing uncertain $0.107 remains reserved. New cash charges stay $0.

## Acceptance

- Selected files load locally, are palette-quantized and have repeat-safe edges.
- Check scale, value separation and repetition in a tile sheet and rendered room.
- Existing warning strips, repair overlays and glass retain their behavior.
- Earth and Moon mapping is explicit; future Mars work is labelled future-only.
- Full client checks and inspected affected tours pass before release.
- Publish prompts, model, format, reductions and hashes without authorship credits.
- Update the roadmap, budget receipt and release description with actual results.

## Completed generation and integration

Twenty-seven requests completed and downloaded, selecting twenty-one tiles:
eight [Earth](earth-surface-texture-batch.md), eight
[Moon](moon-surface-texture-batch.md) and five
[future offworld library](offworld-material-batch.md) textures. The two low and
two high Earth comparisons were rejected. Two additional Moon requests replaced
an overly mechanical floor and a noisy dust candidate. The larger quality setting
did not produce the best Earth keepers.

Exact retained estimates total $3.811: Earth $1.937, Moon $1.250 and offworld
$0.624, under the $5 aggregate ceiling. Each request has one accepted and one
downloaded receipt. Billing remains unconfirmed, and new cash purchases are $0.
The ongoing round now reserves $4.085 for new image requests, $0.107 for the
earlier uncertainty and $5 conservatively for included audio, leaving $10.808 of
the approved round after those holds. No billing or top-up setting changed.

The selected opaque 128-square images match opposite edges and the expanded
canonical palette. Two muted diffuse dust swatches prevent dry clay collapsing
into a single rust value. Earth and Moon have distinct wall and walking-floor
assignments on the shared 16-texel/metre world grid, repeating every eight metres.
Low Water's patched service and lift tiles use a restrained 0.35 blend; ordinary
mapped tiles use 0.55. Existing vertical repair overlays and procedural warning
marks remain. The old opaque Moon material is a missing-tile fallback, rather
than an overlay that hides the selected new albedo.

Scrapyard map 1 and authored Earth M01-M05 use the appropriate registered
materials. Legacy arenas 2-6 retain their earlier materials. Existing outside
town roofs use the tar tile with ordinary mesh UVs; existing lunar crater rims
use the basalt tile without fabricated panel markings. Ship and depot metal are
not replaced with rock. Pressure seals and civilian storage/tray supports use
the selected fabric, rubber and repair textures. These changes add no geometry,
collision, cover, navigation, resource or liquid behavior.

## Rendered evidence

The real Compatibility renderer passes the player-height lit/dim wall-and-floor
regression for institutional Earth, Low Water and the Moon. Separate assertions
require visible changes on both walls and floors, actual directional-light
response, retained repairs and glass isolation. Manual review caught and fixed
the opaque lunar fallback hiding new issued-steel walls; the initial diagnostic
is retained. Corrected black service walls and distinct worn decks were inspected.
The future-only Mars board was also inspected and is archived as
`docs/screenshots/world_materials_mars_library.png`.

Receipts: `.agents/world-textures-render-corrected.log`,
`.agents/world-textures-request-audit.json` and the three lane receipts. Scope is
Godot 4.7.2-stable, Windows/OpenGL Compatibility/AMD Radeon 780M. These are local
material and rendering checks, not fresh-player acceptance or GPU benchmarks.
Full client checks, actual affected tours and release integration remain pending.
