# Earth surface texture batch

**Status:** implemented, 2026-10-01. Prepared and independently inspected locally; shared integration checks remain pending under the [world texture expansion](world-texture-expansion.md) within the [M06 integration](m06-port-of-entry-prototype.md). Spend uses existing approved credits, with no top-up or overage.

## Purpose and boundaries

Make the existing Earth places materially distinct at ordinary fighting distance. Follow the [Earth guide](../design/earth.md), [art bible](../ART_STORY_BIBLE.md), [palette](../palette.json) and [generation contract](../ART-GENERATION-SPEC.md). The clinic is maintained civilian space; Low Water repairs express individual use; intake and correction repeat issued institutional forms. Freight and scrapyard surfaces weather through work rather than universal abandonment. No new faction marks, character canon or unreadable embedded signs are introduced.

This lane owns specifications, source provenance, local texture preparation and Earth assets. Root owns the shared material/shader integration. Maps, collision, enemy rules, route budgets, scene lighting and existing repair-overlay semantics stay unchanged. Sources are kept separately from runtime keepers; a downloaded image is not an accepted game asset.

## Bounded batch

| Candidate | Intended use | Value and detail |
|---|---|---|
| Oxidized salvage plate | Scrapyard steel and freight steel | Warm dark metal, localized dull rust, broad quiet fields |
| Yard cast concrete | Freight yard concrete | Warm grey, sparse shallow aggregate, low contrast |
| Intake green tile | Intake/correction enamel | Restrained issued green, regular small joints, clean work areas |
| Clinic bone plaster | Clinic and civilian enamel walls | Light bone, subtle broad repair and scuff clusters |
| Settlement terracotta plaster | Low Water civilian concrete walls | Mid-value muted clay, restrained maintenance patches |
| Workshop patched steel | Low Water service steel | Sage/steel, uneven replacement patches and sparse fasteners |
| Service dark tread | Workshop and issued steel floor | Dark neutral, subdued functional worn ribs |
| Roof tar patches | Settlement roof cover | Dark neutral, sparse broad patch boundaries, quiet wear |

Price two low-quality exploration candidates, eight medium candidates and two optional high-quality comparisons as separate exact specifications. Start with the two exploration images only after root allocates a cap. Inspect them at final scale before submitting medium work. Optional high comparisons need useful visible improvement and a separate allocation within the same batch limit; they are not an obligation to spend. Each request is square 2k direct generation with prompt enhancement disabled. The [official model reference](https://open.higgsfield.ai/models/marketing-studio/image/api-reference) was checked 2026-10-01. Live estimates, not historical prices, determine allocation.

## Preparation and acceptance

Ask for opaque orthographic albedo material fields, coarse readable pixel clusters, no perspective, lettering, insignia, directional shadow, ambient occlusion or specular highlight. This endpoint has no documented seamless switch. Seamless wording alone is insufficient: inspect wrapped repeats, reduce through the existing Rust palette reducer without trimming, and apply bounded edge preparation locally if required. Reject material that needs excessive repainting or repeats a conspicuous prop silhouette.

Runtime keepers target **128 by 128 pixels**, exact 16:1 reduction from 2048. The mapped world shader uses an eight-metre repeat on its existing 16 texels per metre grid. The earlier two-metre, 64-texel proposal was not the integrated runtime scale. Distant backdrop roofs retain their existing standard UV mapping rather than world-projected density. Use only canonical palette colors, fully opaque pixels, nearest filtering and no mipmaps. Keep a 256-square comparison only if it improves ordinary view readability at an explicitly matched repeat scale. Edge preparation must preserve broad material identity and include 3 by 3 repeat previews and numerical seam checks. This batch delivers albedo only; depth-derived normal production remains an unfinished part of the full generation contract.

Candidate IDs and model parameters live in `tools/spritegen/specs/earth-surfaces-20261001-*.json`. Provider output and reservation ledgers stay under `.agents/earth-surfaces-20261001/`, independently of other asset lanes, with an ignored local backup under `art/raw/earth-surfaces-20261001/`. Public selected 128-square sources, review repeats and provenance belong under `client/art/environment/earth-surfaces-20261001/`; runtime keepers belong under `client/assets/environment/earth/`. Large originals stay outside the public repository. The existing credential is read only by the approved Rust tool and is never copied or printed. Retain accepted request IDs and uncertain reservations; do not submit replacements to recover a missing response.

## Verification and integration

Inspect each source, palette reduction, native-size detail and tiled repeat. Record accepted/rejected reasons and exact reserved estimates separately from unreconciled provider billing. Root maps a small selected subset to the existing registered surfaces/venues, using a separate full tile layer that preserves old repair overlays. Keep material caching and original fallback behavior. Final acceptance requires clean import and headless checks plus inspected rendered views in scrapyard, institutional and Low Water rooms. Actual world light and actor readability decide keepers, not nonblank images or the number generated.

The owner reported a current $14.27 account balance. The round has a conservative $14.619 remaining allowance before these new lanes, with the historical uncertain image reservation and audio reserves retained. This plan does not authorize a new cash purchase, billing change or automatic retry. Exact allocation and receipts follow the price gate.

## Price-only receipt

The existing release tool priced the exact assembled requests on 2026-10-01. No generation was submitted. Two low exploration requests total $0.057; eight medium requests total $0.990; two optional high comparisons total $0.890. The recommended exploration-plus-medium allocation is $1.047. All twelve possible requests would total $1.937, before any price change. These are current estimates, not confirmed billed charges. Separate price receipts are under `.agents/earth-surfaces-20261001/price-*.log`.

Root reserved the full $1.937 before submission and authorized separate run caps of $0.06 exploration, $1.00 medium and $0.90 comparison. Execute all twelve priced candidates for an actual controlled quality comparison, then select only useful tiles. The official reference confirms direct generation, square 2k output and disabled preset enhancement; exact assembled payloads were accepted by the live estimate endpoint on 2026-10-01. No account or billing settings change.

## Completed candidate receipt

All twelve accepted requests completed and downloaded: two low, eight medium and two high, with exact ledger reservations of $0.057, $0.990 and $0.890 respectively. The $1.937 total is an estimated reservation, not an independently reconciled billing total. No duplicate generation POST, cash purchase, top-up or overage was introduced. Polling-origin metadata was rejected by the existing strict boundary; each exact saved Accepted ID was attached to the [documented official status endpoint](https://open.higgsfield.ai/models/higgsfield/genjutsu/restyle/v1.0/api-reference), checked 2026-10-01. The same request then completed without a replacement submission or validation relaxation.

All eight medium candidates won the final-scale selection. Low clinic plaster collapsed nearly into flat bone; medium retained readable small scuffs. The high plaster again lost almost all variation, and the high plate's larger diagonal wear repeated more conspicuously than the medium field. Reject all four comparison/exploration variants for runtime. A local reduced-palette experiment on the plate also lost useful variation, so final tiles use the full canonical palette, including the two diffuse dust swatches added during this batch.

The existing reducer prepared 128-square images by area averaging. `tools/prepare_earth_tiles.gd` applied an eight-pixel opposite-edge band, followed by the existing CIE Lab palette reducer. Its unchanged-image verification passed all eight final images: full opacity, canonical colors and exact matching opposite edges. Native previews and 3 by 3 repeated tiles were inspected. Workshop patches need restrained vertical service-steel strength; dense dark tar belongs only on explicitly horizontal roofs. Normal maps remain unbuilt.

Eight runtime PNGs occupy 18,112 bytes. Selected 128-square sources, repeat previews and the prompt/parameter/hash manifest are present in the public source directory. Large 2048-square originals, exact request ledgers and their backup stay ignored. Logs and the separate `spend-receipt.json` are under `.agents/earth-surfaces-20261001/`. Source pixels and preparation code are frozen. Shared material integration, clean import, whole-client checks and actual lit venue inspection remain root-owned gates.
