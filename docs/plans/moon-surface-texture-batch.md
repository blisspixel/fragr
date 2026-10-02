# Moon surface texture batch

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. Eight selected lunar tiles are integrated and the actual lunar material route passes.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).
Root recorded the initial eight-request $1.000 estimate before submission with an explicit $1.05 ceiling, then separately authorized two floor alternatives.

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

## Purpose and ownership

Create eight distinct original lunar materials for M06 and later lunar continuity, following the [Moon guide](../design/moon.md), [art bible](../ART_STORY_BIBLE.md) and [palette](../palette.json). Pressure shells, service decks and dry rock should explain their function at fighting distance. Personal repair surfaces remain warm and individual beside black/steel Union infrastructure with restrained red. Outdoor lunar surfaces stay dry.

This lane owns the two lunar generation specifications, reduced and processed source artwork under `client/art/environment/moon-surfaces-20261001/`, runtime copies under `client/assets/environment/moon/surfaces/`, the offline preparation source, provenance and this plan. Provider raw PNGs and request receipts stay ignored under `.agents/moon-surfaces-20261001/` and `.agents/moon-floor-alternatives-20261001/`. Root additionally assigned `m06_port.gd` existing seal, fabric and repair bindings, with focused checks in the existing M06 harnesses. Root owns shared `arena_materials.gd` and shader integration. Map data and geometry stay unchanged. Existing original bakes remain available as fallbacks. No new collision, mechanic, dependency, runtime API or character casting is introduced.

## Eight candidate surfaces

| Frame ID | Material read | Proposed existing presentation seam |
|---|---|---|
| moon_pressure_bone | Maintained pale pressure-rated enamel, broad seal seams | Existing lunar enamel pressure walls |
| moon_worn_deck | Dark worn load-bearing deck with quiet traction ribs | Existing floor/service deck material |
| moon_basalt | Dark fractured lunar basalt, irregular broad rock clusters | Existing exterior crater mesh |
| moon_regolith | Pale dry compacted mineral dust, sparse darker grit | Existing lunar concrete ground |
| moon_union_service | Issued black steel, repeated restrained red service strip | Existing Union service steel |
| moon_seal_rubber | Matte charcoal compressible gasket and fabric reinforcement | Existing window/door seal dressing |
| moon_civilian_fabric | Muted sage/bone weave with small individually stitched repairs | Existing sealed-room storage surfaces |
| moon_repair_plate | Uneven bone/rust replacement plates and broad practical fasteners | Existing maintained service inserts |

Each is a full opaque square albedo tile. No baked directional light, cast shadow, ambient occlusion, shiny highlight, lettering, labels, border or perspective. Broad forms and different value structures must survive reduction, rather than becoming eight gray noise variants. Keep clear regions behind fighters and attack tells.

## Price and spending boundary

Use the existing release `fragr-spritegen` price command against the exact eight assembled prompts. No generation POST is authorized by this plan alone. Root allocates the shared round ledger across all image lanes before generation and supplies this lane's explicit maximum. The current model's [official direct-image API](https://open.higgsfield.ai/models/marketing-studio/image/api-reference), checked 2026-10-01, supports square 2k output and `enhance_prompt:false`. Proposed quality is medium, subject to fresh exact estimates. No top-up, overage or cash purchase is enabled. Keep the earlier image reservations and billing uncertainty separate.

The candidate output directory and durable request ledger are separate from prior possession and story batches. An accepted uncertain request is recovered by its saved ID through the existing strict official-origin seam; it is not resubmitted automatically. No credentials or signed download links belong in public receipts.

## Reduction and acceptance

Reduce locally through the existing Rust reducer to 128-square exact-palette opaque PNGs, retaining raw dimensions and source hashes. Inspect each at native 128 pixels, nearest enlarged view, and a repeated 3-by-3 grid. Test horizontal and vertical boundaries for a visible seam. Generation is not evidence of seamlessness: reject edge patterns that cannot be repaired through a bounded original offline bake. Any local seam repair must operate periodically and preserve the center's material structure, with its source and output recorded.

After keeper selection, root grants the shared material integration seam. Bind only appropriate existing geometry and preserve nearest filtering, real directional light, authored pressure-glass authority and fallback assets. Inspect actual player-height lit wall/floor closeups and fighting-distance world views, not only a gallery sphere. Compare distinct material identities, texel density and target readability. One static preview does not prove environment quality or GPU performance.

## Evidence gates

- Exact estimates, prior root allocations and ten preserved generation receipts are complete.
- Native pixel, palette, exact opposite-edge and actual surface-scale inspection are complete.
- Eight keepers are selected and bound to existing materials and room surfaces.
- Pinned preparation and focused tests pass. The final actual gameplay tour and engine teardown pass; final broad checks and standard publication are root-owned.

Human fresh-player acceptance, subjective art preference, later lunar levels and provider billed-total reconciliation remain separate.

## Fresh price receipt

The exact existing release-tool price command completed with exit 0 on 2026-10-01. Each of the eight medium/2k square requests estimates **$0.125**, total **$1.000**. Nothing was generated and no generation reservation was incurred. Receipt: `.agents/moon-surfaces-20261001/price-medium.log`. These are current estimates rather than a billed-total claim. Root owns `arena_materials.gd` and the surface shader integration, preserving the existing vertical repair overlay; keeper delivery will include explicit venue/surface assignments and comparison against the original baked pressure/dust textures.

## Initial eight-request inspection

All eight exact requests were accepted and downloaded, with **$1.000 estimated reservations**, not confirmed provider billing. Strict polling-origin refusal was recovered only from each saved accepted request ID, through the existing documented official status origin. There were eight generation submissions, not duplicate replacements. Provider raw PNGs and the durable ledger remain ignored; public preparation retains their exact hashes and 128-pixel reduced source copies.

The paired-edge bake passes exact opposite-edge checks for all eight tiles. Its first run exposed asymmetric half-rounding at paired edge pixels; the correction assigns the same computed color to each outer pair, and the subsequent check passes without relaxing the seam assertion. Three-by-three repeats were inspected. Bone pressure plates, dark issued service panels, basalt fractures and rubber weave retain distinct visual structure. Existing personal possession assets remain unchanged.

The first deck candidate reads as machinery, not a walking tread, and is **not approved for floors**. The original regolith reduction is too peppery for an aiming background; its prepared derivative limits grit to sparse darkest coarse source regions. Root requested fresh price-only alternatives in `tools/spritegen/specs/moon-floor-alternatives.json`: flat traction deck and quiet dry regolith. These use new distinct frame IDs and a separate ledger, and require a new root allocation before submission. No additional request is authorized merely by the alternative specification.

Root recorded the fresh two-request **$0.250** estimate in the shared ledger before POST and authorized these exact alternatives with **$0.27** maximum. Combined lane estimates are $1.250 for ten distinct requests, within the root-owned aggregate allowance. Good floor alternatives may replace the selected runtime deck/regolith paths only after inspection, with their exact new source identity recorded. The original eight request receipts remain unchanged.

## Selected floor replacements and source freeze

All ten requests completed and downloaded. The flat traction alternative is quiet walking deck with long broad ribs and sparse wear, rather than the rejected machine-face pattern. The quiet regolith alternative has a pale field and separated grit clusters; it replaces both the noisy original and the temporary locally quieted derivative. Both were inspected as native 128-pixel reductions, full raw references and repeated three-by-three grids. No high-quality comparison or further generation was needed.

The explicit `FLOOR_KEEPERS` map in `tools/prepare_moon_surface_tiles.gd` selects these two new request identities onto the stable runtime paths `moon_worn_deck.png` and `moon_regolith.png`. Preparation uses the expanded shared palette, records its hash, preserves metadata-free 128-pixel reduced source copies and produces eight exact-palette opaque runtime tiles with nearest filtering and no mipmaps. All opposite edges match exactly after the paired eight-pixel repair. Receipt: `.agents/moon-surfaces-20261001/preparation-floor-keepers.log`, clean exit 0 and PASS. The original eight candidates and their reservations remain separate evidence in the manifest; the busy deck and noisy grit are not selected for floors.

| Runtime surface | Existing integration |
|---|---|
| pressure bone | Root lunar enamel walls |
| quiet regolith | Root lunar concrete ground |
| flat traction deck | Root horizontal service and lift surfaces |
| black/red issued service | Root vertical service steel |
| repair plate | Root vertical lift surfaces; existing room table support and recycling tray |
| seal rubber | Existing pressure window seal meshes |
| civilian fabric | Existing possessions bench, preserving its geometry |
| basalt | Existing bounded exterior crater meshes |

The existing three possessions, original pressure/dust bake files and missing-texture material fallback are retained. Tests extend the existing M06 files for selected room bindings, fallback, current palette/source freshness and exact tile edges; no new harness is added. Root's rendered contribution regression exposed the original opaque pressure/dust fallback hiding the new albedo; it now applies only when the tile layer is disabled. Actual lit player-height and in-game frames were reviewed after that correction. Native-pixel and seam inspection alone did not establish the world integration quality.

**Current spend:** ten accepted requests, **$1.250 estimated reservations**, provider billed total unconfirmed, $0 new cash. The original $1.05 and alternative $0.27 ceilings were separately authorized before submission. No top-up, overage or additional call is planned. Source lane freezes for root's final shared integration and verification.

### First actual material tour, retained failure

The new-material M06 tour in `.agents/qa/m06-port-textures-final/` captured 18 actual states before an ordinary customs walk failed below the raised crossing, wrapper exit 1. It is not a final PASS and its gallery was not published. Inspected fullsize frames show bone pressure walls/ceiling, black/red issued steel, quiet ground, textured exterior crater pieces and the inhabited room's preserved possessions under real lighting. The Turret lesson passed its existing causal cover-cancellation gate, with blocked Windup3217 preceding Recovery3218 and no shot through original deadline3239. This is partial material and gameplay evidence only.

The bounded [contact-aware QA dodge correction](qa-contact-safe-strafe.md) addresses a separately reproduced safety omission without changing maps or gameplay. A clean full actual rerun and final broad verification remain required before final publication. No further asset generation follows this failure.

### Earlier clean material tour, retained history

The unchanged 25-state route in `.agents/qa/m06-port-textures-second-final/` passes with all 21 named guards defeated, actual `party_departed`, wrapper exit 0 and no engine/script errors. The record reports zero deaths, 45 HP lost, 100 armor lost and one secret supply claim; all three secret locations were visited. Normal supplies restored health before departure. The resolved Rail kill at tick 1267 measures 52.662686m from actual trace origin to impact, distinct from authored initial spacing. Real Turret cover cancellation retains blocked Windup 3045 before Recovery 3046, a twelve-tick recovery and no registered shot through the original deadline 3069, verified at 3070 with unchanged 100 HP.

Fullsize Earth, inhabited crew room, Turret windup/firing, pressure-window ship/depot and departure frames were inspected. Bone panels, dark issued steel, quiet floors, coarse exterior basalt, seals and individual room possessions read under the actual world light. No new clipping or sky fragments were found. The twenty-frame Earth strip is a fixed camera landmark view with a passing provisional ally, not planet movement or continuous combat proof. Turret stills are observed phase captures, not a continuous motion sequence. Existing character bodies remain provisional.

The eight approved `docs/screenshots/m06_*.png` gallery files were refreshed from this earlier successful run, with source/destination hashes checked. The ignored source receipt is `.agents/moon-surfaces-20261001/tour-retry-source-receipt.json`; wrapper and CPU tile logs are `tour-retry-wrapper.log` and `tour-retry-earth-tiles.log` in that directory. The unchanged server SHA256 is `81DD76F47EBB00EBC80B92A4562DADD3D821C534E00B5C73DDDEE1D5552AFE3A`; map SHA256 remains `627e9bcecaa231fdc3a5df8297ac872e975b41c31b7ae872d4a4ce1c25e4a9a5`. Material checkpoint 054031c and exact loaded script/shader hashes are retained in the receipt.

This is Godot 4.7.2 Compatibility rendering on one Windows AMD Radeon 780M host at 1280x720. It does not establish other GPU performance, subjective audio quality, human fresh-player acceptance or difficulty acceptance. Owned server, Godot and CPU tile processes closed cleanly before lease handback. Root runs serialized final whole-client checks and current standard publication after both authored QA corrections freeze. No further paid call is planned; estimated reservations remain $1.250 with provider billing unconfirmed and $0 new cash.

### Earlier phase-aware peek capture, retained history

The ordinary-input route in `.agents/qa/m06-port-peek-final/` passes all 25
states and all 21 named guards, with actual `party_departed`, wrapper exit 0
and clean import, client and wrapper logs. The record reports zero deaths,
25 HP lost, 125 armor lost and two actual secret supply claims. Pressure
maintenance and duty-free supplies were claimed; all three secret locations,
including the crane overlook, were physically visited. The actual Rail kill
at tick 1281 measures 52.804014 metres from resolved origin to impact.

The unchanged strict observer proves clear initial Windup 3064, consecutive
blocked Windup 3067 and genuine twelve-tick Recovery starting 3068 and ending 3080.
Turret HP remains 100 and there is no registered shot through 3091, one tick
after the original charge deadline 3090. The ordinary initial sweep retains
the actual first shot at 3018 and captured Windup/Firing; the later supported
rear approach confirms the kill at 3310. The combat observation spans
2967 through 3326, within the unchanged 25-second gate. The bounded
[phase-aware peek](qa-turret-peek-timing.md) changes QA ordinary-input timing,
without modifying observer proof, map geometry or server outcomes.

All eight gallery files were inspected and refreshed at this checkpoint,
with matching source/destination hashes. The fixed Earth view retains twenty
actual frames, retiled without resizing; that sequence has no companion
crossing and does not show planet or ship movement. The Turret motion sheet
and 25-state contact sheet were also inspected. Existing character bodies and
coarse impounded ship/depot remain provisional, and authoring evidence does not
establish fresh-player teaching or difficulty acceptance.

Receipt: `.agents/qa/m06-port-peek-final/source-receipt.json`. It records exact
unchanged start/end script and shader hashes, unchanged map SHA256
`627e9bcecaa231fdc3a5df8297ac872e975b41c31b7ae872d4a4ce1c25e4a9a5`
and existing server SHA256
`81DD76F47EBB00EBC80B92A4562DADD3D821C534E00B5C73DDDEE1D5552AFE3A`.
The ignored wrapper preserves normal import, rendering, verdict and cleanup,
but replaces its build step with exact existing-byte verification. Its diff
and hash are retained; this was not a fresh server build or a
rebuilt-current-CTF capture. At this checkpoint, the later CTF-only source repair still required separate
matching-binary confirmation before final release. Both owned processes closed
before returning the lease. Provider reservations remain $1.250, billing is
unconfirmed and new cash charges remain zero.

### Final normal-wrapper capture and current gallery, 2026-10-02

The fresh unmodified normal wrapper in
`.agents/qa/final-m06-shipping-second/` builds the locked release server and
passes all 25 states, all 21 named guards across seven combat stages and actual
`party_departed`. Wrapper exit is 0; import, client and wrapper logs contain no
engine or script errors. The complete participant record at tick 5391 reports
zero deaths, zero HP lost, 75 armor lost, one actual secret claim, nineteen
Rifle kills and two Rail kills. All three secret locations were visited; a
location visit is not a claim. The actual resolved Rail hit at tick 1201 measures
51.991994 metres from origin [-28.737337, 1.6, -10.928136] to impact
[23.179518, 1.019579, -13.661393].

The strict Turret observer retains clear initial Windup 3005, consecutive blocked
Windup 3007 and genuine twelve-tick Recovery starting 3008 and ending 3020.
HP stays 100 with no registered shot through 3032, one tick beyond the original
deadline 3031. The ordinary initial sweep records Windup 2935 and the real first
shot/Firing at 2959; the later supported rear approach confirms Dead at 3249.
Combat samples span ticks 2908 through 3264 and 17807 milliseconds, within the
unchanged 25-second gate. No observer threshold or outcome was relaxed.

The preceding final attempt in `.agents/qa/final-m06-shipping/` is retained as
a three-state freight-walk failure, not a pass. The bounded
[quiet freight capture route](m06-freight-capture-route.md) changes only that
capture stage's ordinary waypoints and travel policy. Its actual-map regression
includes every dormant freight body, both identity orderings and five bounded
arrival offsets. The successful full capture follows the four revised legs
before the unchanged four-guard combat stage. The original failure did not
retain the final companion coordinates and does not establish a living-body
cause or CTF regression.

All eight current gallery files were inspected at full size and refreshed only
after the clean verdict, with matching source/destination hashes. The 25-state
contact sheet, actual Turret motion sheet and twenty-frame Earth sequence were
also inspected. The current fixed Earth view has no companion crossing and
does not show planet or ship movement. Pressure materials, inhabited-room
possessions, provisional character bodies and coarse static ship/depot remain
visible under actual world lighting. No new clipping or broken body facets were
found in the inspected sequence.

Receipt: `.agents/qa/final-m06-shipping-second/source-receipt.json`. The normal
locked release build took 2.10 seconds. Captured server SHA256 is
`D29AE5E4B0BC3456F370524F87873930A2A8B2C9C8B5DCA09726D7EBAC05BE8A`;
map SHA256 remains
`627e9bcecaa231fdc3a5df8297ac872e975b41c31b7ae872d4a4ce1c25e4a9a5`.
All retained source, shader, wrapper, map and binary hashes match before and
after. This confirms the matching current CTF/campaign build locally. Owned
server 5188 and Godot 26652 are absent after clean exit. CPU tiling used no
Godot process. The exclusive lease was returned before root's whole checker.
Evidence remains limited to this Windows AMD Radeon 780M Compatibility host,
not other GPUs, fresh-player teaching, difficulty or subjective audio acceptance.
Final broad verification, protected main CI and release remain separate gates.
Estimated reservations remain $1.250, billing unconfirmed and new cash zero.
