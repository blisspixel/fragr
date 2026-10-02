# Lunar port art batch

**Status:** in flight, 2026-10-01. Child of [M06 prototype](m06-port-of-entry-prototype.md). Initial generation cap: $1.50 equivalent. Entire batch cap: $3 equivalent from existing credits, with no top-up or overage.

## Purpose and ownership

Improve the inhabited pressure room and useful port detail through a small inspected raster batch. The [Moon guide](../design/moon.md), [art bible](../ART_STORY_BIBLE.md), [generation contract](../ART-GENERATION-SPEC.md), [palette](../palette.json) and [people and agents](../lore/people-and-agents.md) own continuity. Free people keep distinct possessions inside the ordered port. No new named-character design, performance, faction canon or animation roster is introduced.

This lane owns generation specifications and candidate source/processed artwork under `client/art/environment/moon-batch-20261001/`, plus ignored request receipts under `.agents/m06-lunar-art-20261001/`. The client lane owns existing Moon textures, bake sources and presenters. Integration waits until the active rendered tour releases its source window, and remains a separate inspected choice. Authored collision, maps, enemy rules and routes remain unchanged.

## Staged candidates

Generate four square albedo candidates: a child's Earth drawing for the existing family-room page; an individually patched civilian textile for inaccessible storage or table dressing; a matte worn pressure-shell repair insert; and a small personal meal-cloth pattern for the sealed room. The drawing must read as a child's possession rather than a celestial photograph. Industrial detail must stay quiet behind enemy silhouettes. No lettering, logos, insignia, baked lighting, glossy highlights or implied new blocking props. Unique inserts do not claim seamless tiling.

Direct requests use the existing `marketing-studio/image` endpoint with `enhance_prompt:false`, square 2k output and initial low quality, subject to exact live pricing. Parameters are checked against the [official model reference](https://open.higgsfield.ai/models/marketing-studio/image/api-reference) on 2026-10-01. No provider pin or new dependency is introduced. The existing Rust tool prices the exact assembled requests before generation, writes a reservation before each submission, and retains uncertain requests rather than buying replacements. The API estimate is a reservation, not a final billing receipt.

After initial inspection, promote only useful keepers within the remaining $3 ceiling, with fresh exact pricing. Prepare candidates through the existing local reducer at 128 pixels for paper/textile and 256 pixels for a pressure insert, using `docs/palette.json`, hard alpha and nearest previews. Record original dimensions and exact reduction ratio. No normal-map or seamless-tile acceptance is claimed for these flat ornamental albedos. Reject poor silhouettes, faux photographic shading, noisy detail or continuity drift rather than spending automatically to fill the allowance.

## Spend boundary

Nick reported a current Higgsfield balance of $14.40 on 2026-10-01 and explicitly authorized more needed art. Retain the historical uncertain $0.107 request reservation and the development round's current conservative $5 audio equivalent reserve (975 included credits consumed). This batch fits beneath the combined $20 round and $50 total ceilings; the $3 batch cap is an additional ceiling, not a fresh allowance. No account, billing, subscription, top-up or overage settings change. The existing ignored credential is read only by the approved developer tool and never copied or printed.

Use the already-built `target/release/fragr-spritegen.exe`, avoiding Cargo or release replacement during the client's actual tour. Keep prompt/model/parameters, request identity, reservation and download state in the existing durable ledger. Preserve uncertain submission state; no invented refunds or automatic retry. Public candidate manifest records source, preparation, format and actual keeper decisions without account information or signed download URLs.

## Verification and handoff

Inspect each raw candidate and its palette-reduced preview beside the current lunar room and Earth assets. Record exact estimates and completed request IDs separately from confirmed billed usage. A downloaded candidate is not an accepted runtime asset. Root and client select useful keepers, preserve nearest filtering and real world light, then inspect actual lit placement after integration. No scenery-only collision promise or player runtime API call is added.

## Initial receipt

The existing Rust price command estimated four low/2k square requests at $0.029 (drawing), $0.028 (patched textile), $0.028 (pressure insert) and $0.029 (meal cloth), total **$0.114**. Generation used the explicit $1.50 ceiling and downloaded all four 2048-square PNGs. Each accepted response returned polling metadata rejected by the strict official-origin boundary. The saved accepted request IDs were attached through the existing recovery command to the [documented status endpoint](https://open.higgsfield.ai/models/higgsfield/genjutsu/restyle/v1.0/api-reference), checked 2026-10-01; each same request then polled and downloaded without another generation POST. No transport validation was relaxed, no uncertain ID was guessed, and no duplicate submission or refund was assumed. Ledger and exact command logs are under `.agents/m06-lunar-art-20261001/`.

Raw inspection and preliminary 64-square reduction established broad readability. Final candidate paper and textile images use the planned **128-square** target, exact 16:1 reduction, with nearest previews for inspection. They contain seven, six and five exact palette colors respectively; all pixels are opaque. The pressure insert has a separate **256-square** review at exact 8:1 reduction, but is not selected: its quiet hull language overlaps the current port materials and lacks a necessary new slot. No promotion is justified merely to consume the allowance.

Three selected keepers, metadata-free source re-encodes, reduced images and provenance are under `client/art/environment/moon-batch-20261001/`. Runtime copies under `client/assets/environment/moon/possessions/` bind the drawing to the existing family page, patched textile to existing storage possessions, and meal cloth flush to the sealed-room table. The original baked Moon assets and drawing fallback remain intact.

The client reported clean import, focused headless and rendered checks. Independent inspection of `.agents/m06-buildout-20261001/moon-possessions-isolated.png` confirms the recognizable paper globe, patched storage surfaces and table cloth under actual room lighting with the existing residents. This is an isolated presenter preview. Final in-play capture and complete checks remain pending after the living-body contact work; no fresh-player or full mission acceptance is claimed.

**Spend:** $0.114 in new request reservations, all completed and downloaded. Provider billing has not been independently reconciled, so this is not an exact billed-total claim. No top-up, new cash purchase or overage setting was enabled. Retain the prior $0.107 uncertainty and the separate audio/shotgun reserves. Remaining batch allowance is a ceiling, not work to spend automatically.

The later [story-key-image batch](m06-story-key-images.md) reserves another
$0.160 for two requests. Combined new image reservations are $0.274 for six
accepted requests, with provider billing still unconfirmed and $0 new cash
charges. This plan's four-request $0.114 receipt remains separate.
