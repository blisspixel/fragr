# Low Water environment asset batch

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. **Spend:** $0 actual. The initial image batch
has a $2 ceiling within the current $20 combined external development allowance.
No top-up, overage or uncertain request retry is authorized.

## Goal and style

Produce a small coherent set of Low Water material tiles: worn civilian plaster
and repaired workshop steel. They should replace generic repeated vent detail
with readable repair history while leaving authoritative geometry, collision,
mission maps and protocol unchanged. Water dressing belongs to the separate
[water foundation](environment-water-foundation.md).

The existing [art and story direction](../ART_STORY_BIBLE.md),
[color roles](../ART-COLOR.md), [palette](../palette.json) and
[Low Water brief](../campaign/l04-notice-to-vacate.md) own the look. Use broad
pixel clusters, bone plaster, dark steel, muted sage and restrained rust. Free
communities repair and repurpose; removed issued marks leave scars, not a new
uniform rebel insignia. No copied game artwork, new character facts, readable
generated text, medical emblem, warning-red flood or post-wipe regrowth.

## Pipeline and ownership

Use only `tools/spritegen` for generation and local palette reduction. The
two-frame spec lives in `tools/spritegen/specs/low-water-environment.json`.
Price the complete exact request for free before submission. Verify current
prepaid API dollars, top-up state and historical reservations separately from
website subscription credits. Generate only after those checks pass, with an
explicit cap no higher than $2. Retain every uncertain receipt.

Raw output and the locked request ledger remain under
`art/raw/low-water-environment-20260930/`; reviewed palette-reduced keepers and
provenance would live under `client/assets/environment/low_water/`. A dedicated
surface helper or shader hook requires coordination with the material owner.
This lane does not edit arena collision, backdrop, water or mission-map files.

The current balance boundary blocks paid generation. The authorized $0 fallback
is an original deterministic GDScript bake, using the existing offline image
pipeline convention. Two 128 by 128 RGBA overlays depict broad plaster repairs,
low waterline wear and sparse steel/enamel replacement patches. The baked palette
and source recipe are retained with the assets. Rejected legacy surface candidates
are not reused. No model-produced output is claimed.

The material owner delegated the optional `arena_materials.gd` and
`arena_surface.gdshader` detail hook for Low Water only. Shared cached textures,
nearest sampling, a fixed 16 texels/metre and a two-texture 128 KiB uncompressed
budget avoid per-solid allocations. Vertical authored concrete, enamel and
service faces receive detail; floors and other venues retain their existing
material behavior. Directional lighting, roughness and light-level variation
remain active. No extra meshes, collision or wire facts are added.

Interactive captures own presenter source until their explicit cleanup. New
baker and test files may be prepared during capture, but integration and asset
writes wait for that handoff. The focused harness checks venue isolation,
texture cache/filter/budget, native pixels and a lit rendered patch comparison.

## Verification and acceptance

Inspect original output and reduced tiles at native and enlarged pixel scale.
Reject baked checkerboards, accidental lettering, noisy photoreal wear, seams
that cannot repeat and motifs that obscure actors. Integrate only inspected
keepers; preserve nearest filtering and stable world texel scale. Run the
affected Godot checks and inspect a parent-coordinated rendered tour. A priced
spec is preparation, not completed or integrated artwork.

## Evidence

The API credential entry exists locally; no credential value was printed.
The prior account receipt records $14.51 with automatic top-up off on
2026-09-20, not a current balance. The Clerk's historical $0.107 reservation
remains preserved; its earlier dashboard charge was reconciled but polling
identity remains unresolved. It must never be resubmitted under a new ID.

Current official model schema was checked on 2026-09-30 through the
[model API reference](https://open.higgsfield.ai/models/marketing-studio/image/api-reference)
and [shared documentation index](https://docs.higgsfield.ai/docs/llms.txt).
Direct mode accepts the existing 2k, 1:1 request and omits image references;
prompt enhancement stays disabled. No documented prepaid account-balance
endpoint was found in those sources or the supplementary OpenAPI reference.

Browser discovery returned no connected browsers; the explicit Chrome selector
also reported unavailable. The read-only connector returned ten website credits
on a free plan. Those are not verified prepaid API dollars and do not satisfy
the balance requirement. Approved read-only Chrome diagnostics found the browser
installed and native host valid, but the required extension absent from the
selected profile. No browser configuration was changed.

The exact free price command passed on 2026-09-30:
`cargo run -p fragr-spritegen --locked -- price --spec tools/spritegen/specs/low-water-environment.json`.
Both 2k tiles were estimated at $0.028 each, $0.056 for the complete batch.
The log is `.agents/m04-buildout-20260930/environment-assets-price.log`.
No image-generation request has been submitted. Paid generation remains blocked
on a fresh prepaid API balance and top-up check; preparation is ready without
claiming completed artwork.

The original $0 fallback is implemented and integrated into the existing
Low Water material path. Both native overlays and Compatibility lit/dim wall
renders were inspected: broad unequal plaster repairs remain readable, waterline
wear stays low, steel repairs are sparse, and no text, emblems, noisy vents or
new world objects were introduced. The paid API batch remains prepared only.

| Verification | Actual result |
|---|---|
| Pinned Godot baker | PASS, two deterministic 128px RGBA overlays, manifest and native previews |
| Repeat bake | PASS, both PNG hashes unchanged on a second actual bake |
| Headless import and focused harness | PASS, clean logs, cached 128 KiB budget, venue/style isolation and nearest filter |
| Compatibility render, AMD Radeon 780M | PASS, plaster 5,174 changed pixels and steel 2,039; all changed pixels respond to reduced light |
| Horizontal floor comparison | Pixel-identical with detail enabled and disabled for both materials |
| Final integrated campaign capture | PASS, `.agents/qa/m04-market-ninth/manifest.json`; inspected repair surfaces retain light and shadows. Full mission acceptance remains open |

Logs are `environment-bake.log`, `environment-import.log`,
`environment-focused.log` and `environment-rendered.log` under
`.agents/m04-buildout-20260930/`. Inspected native and lit/dim images are under
`.agents/environment/`. The new `test_low_water_details.gd` follows the existing
full-checker harness convention. No release executable, map, protocol or
encounter changed in this lane.
