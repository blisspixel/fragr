# Art excellence

**Status:** in flight, 2026-10-03. Nick instructed continued asset production.
The October 3 production increment shipped in
[PR #337](https://github.com/blisspixel/fragr/pull/337) and
[v0.68.0](https://github.com/blisspixel/fragr/releases/tag/v0.68.0). Full roster,
environmental-kit and played quality acceptance remain open.
Build and inspect the first complete sample, then apply accepted sources and
materials across the roster, weapons and environments. Final quality remains
subject to played and rendered inspection.
**Spend:** $0 for local source work and evaluation. Every billed operation
needs its exact price and remaining allowance checked before it runs.
Nick first authorized $5.88, then reported a $100 API top-up and $105.88
available on 2026-10-03, authorizing that total for Higgsfield asset work.
This replaces the earlier $50 ceiling only for this scope. Keep priced,
bounded batches and reconciliation, with no automatic top-ups or overages.
The research below used $0. The separate production pass completed 151 image
requests: three initial quality references, 147 production sources and one
Latch correction attempt. Durable reservations total $93.365 of estimated
prepaid use, originally leaving an estimated $12.515 of the reported balance.
Nick subsequently reported $14.42 remaining in the API dashboard, implying a
$91.46 net balance decrease from $105.88. Preserve the original reservations
and record this aggregate reconciliation separately; individual request charges
are not independently verified. All jobs downloaded; none remain unresolved.
The [spend record](../../client/art/production-20261003/spend.json) and
[source manifest](../../client/art/production-20261003/manifest.json) preserve
the distinction. No other service or cloud operation was purchased.

## The bar

Nick, 2026-10-03: "just because its inspired by boomer shooter ... doesnt mean
the graphics and art assets need to be bad. we want excellent art assets and
models and maps", and "I want this to be exceptionally well made."

Retro is the art direction, not a quality ceiling. The reference set is the
modern boomer shooters that look excellent:
- Boltgun: detailed renders reduced by artists who control contrast and
  palette.
- Prodeus: fully 3D worlds, with enemies drawn from 3D models into eight
  rotational sprites that take dynamic light.
- Dusk and Ultrakill: low-poly 3D with strong silhouettes.
- Cultic: sprites under modern lighting.

Every asset is judged against those games at game scale, in motion, under
the venue's light.

Nick's later clarification sets a breakout-game ambition: the craft and
replay appeal of Counter-Strike's early rise, and Fortnite's immediate fun
for an audience that likes this style. Asset quantity cannot establish that
bar. Keep visual identity, attack readability, movement response, encounter
variety and repeated voluntary play in the acceptance review. Existing
automated routes prove recorded behavior; fresh-player and mixed-human LAN
sessions still decide whether the game is fun.

## Where fragr is today

Being honest about the gap:

| Area | Today | Gap |
|---|---|---|
| Characters | Selected stylized Clerk, Sweeper and Auditor sources supply directional sprites with paired view normals; selected civilian strip and weighted, screen-faced live Latch ship in v0.71.0 | Clerk revision ships in PR #346 and the cast increment in PR #348. Full M02 art route, Auditor range clear, wider roster conversion and played quality acceptance remain open |
| Weapons | Existing stylised viewmodels remain selected. Original Shotgun GLBs, separate pump/gloves and twelve coherent poses exist as candidates | First-person framing and hand anatomy need refinement before replacing the selected Shotgun; other guns need model conversion |
| Pickups and HUD | Object sprites and icons, after art pass 1 | Good direction |
| Maps | Selected venue tiles, wall bays, ceiling coffers, merged fixture housings, lit shallow water and Low Water river; M04 inhabited detail and roof enclosures, M06 workmanship and M04 residential frontage ship through PR #342, #344, #347 and #348 | Larger authored landmarks and full environmental kits remain open; ordinary M04 departure and roof-return evidence cover the selected enclosures |
| Lighting | Three presets with SSAO, glow, venue lights | Planned Ultra preset ([graphics options](graphics-options-and-lighting.md)) |

## Direction

1. **Characters from real models.** Replace primitive assemblies with
   sculpted, textured, rigged models (glTF) as the source of the existing bake.
   The current proposed path keeps eight directions, pose layout, feet
   registration and the Union palette. Bake normal maps beside the albedo
   so existing venue lighting describes the body's shape. A live mesh path
   must preserve server-driven phases, facing, resolved-shot response and
   feet registration too. The local trial decides which presentation reads
   best in play.
2. **Maps with architecture.** Build a modular kit per environment (Earth
   facility, Low Water, the lunar port, Mars, ships):
   - Trims, arches, columns, pipes, railings, consoles, door frames, lamps.
   - Signage, crates and machines as real meshes with pixel textures.
   - Decals.

   Set dressing has to play. It gives cover, marks landmarks and routes, or
   rewards a look ([size follows the crowd](../MAP-DESIGN.md#size-follows-the-crowd)).
   Collision stays in authoritative solids; detail meshes sit on top.
3. **Weapons from one source.** Render each viewmodel's frames from one model
   per gun, so fire, pump and future animations stay on-model. Or continue
   the stylised generated frames where they already meet the bar.
4. **Light it.** The Ultra preset, venue practical lights, and per-environment
   fog and atmosphere.
5. **Judge it in motion.** Every art change ships with tour stills and a
   motion strip at game scale, compared against the reference set, under
   at least two venues' light.

## Local quality trial

### Production brief, clarified 2026-10-03

Apply the [art bible](../ART_STORY_BIBLE.md),
[character contract](../design/characters.md) and
[weapon fiction](../lore/guns.md#campaign-equipment-direction). Latch is a
lean, roughly 1.8 metre civilian robot with a rectangular CRT-like screen
face, friendly expressions, one left-ear antenna and individual repairs.
Free people vary in body, clothing and gear; the Union repeats issued forms,
black plates, restrained red optics and compliance markings. Personhood is
clear even when characters' choices are morally complicated. The larger
intelligence is suggested through infrastructure and radio before its scale
is understood. Nick's follow-up fixes a loose campaign reference around 2070,
with Moon and Mars bases and restrained retro-futuristic charm. Use recognizable
mechanical forms, repaired electronics and selected advanced equipment.

For the Shotgun sample, specify a coherent receiver, barrel, stock, grip,
pump travel and sling hardware, with plausible wear and personal maintenance.
Keep gun, hands and moving parts separately articulated. Existing ammunition
and fire/recovery timing stay authoritative; a pump animation cannot invent
a reload requirement. For the recurring Union enemy, equipment must reveal
its actual role and permit a clear attack pose, rather than adding generic
armor decoration. The M01 room must show institutional use through structural
forms, fixtures and signs, with cover and routes matching the server.

A generated reference or mesh is a source candidate. Acceptance requires
coherent geometry and materials, inspected articulation, stable identity
across poses, a correct engine import and a played quality comparison.
Do not replace a provisional asset merely because a new file exists.

### Current implementation cut

Author reusable 3D mesh sources in GDScript and export GLB files with named
moving parts. Start with the Shotgun's receiver, barrel, magazine tube,
pump, stock and hands. Bake a coherent animation strip from that one source
and evaluate it before integration through the existing `WeaponArt` and HUD timing. Use shaped
surfaces, mechanical details and restrained pixel materials, not a scaled box
or another unrelated generated frame for each pose.

Build a reusable facility kit on authoritative M01 surfaces, with inset
frames, trims, fixtures and service panels. Keep detail inside registered
solids where it would otherwise appear to block movement or shots. Extend
the existing character source and bake seam with model-backed articulation
and surface lighting, preserving its directional layout and server timing.

Adapt `tools/spritegen` with an explicit negative-language override for
reference/material work. Existing specs must retain byte-identical prompts
and request identities. Keep its existing locked reservations and price gate.
Price the full high-quality material/reference batch before submission;
inspect every output and retain request, source and output hashes. Exported
models, materials and generated animation remain offline packaged assets.

Acceptance evidence includes engine imports, animation registration and
existing HUD/character contracts, rendered sample captures, frame timing on
the inspected renderer and the full regression gates. Record actual billed
usage separately from estimates and preserve any uncertain reservation.

The priced production batch supplied 4K design and material sources. The
[review library](../../client/art/production-20261003/README.md) records all
147 outputs, with 77 prepared 128-square material candidates and 26 explicit
runtime bindings. Broad lunar panels, fabric requests and two water outputs
miss their requested material use and stay unselected. Latch's generated antenna remains on the
wrong side, so the live model supplies that canonical anchor.

Nine original GLBs cover the Shotgun, its handed variant, articulated
Sweeper, Latch and five fixture types. Geometry comes from the local sources,
not the image API. The verified API route produces images; it does not
produce these GLBs. Merged runtime fixtures have at most three finish surfaces.
Wall and ceiling articulation stays inside the existing authoritative volumes;
upper walking faces remain flat. The normal atlas adds another resident texture
for the Sweeper, beyond its existing albedo memory, as calculated below.

### Played sample and verification

Local receipts live under `.agents/art-excellence-research/`. M01's nine-view
facility route, M04's final complete 23-state market route and M06's complete
25-state lunar route passed with ordinary inputs and recorded captures.
These are authoring and visual evidence, not fresh-player fun acceptance.
The first market capture showed excessive contrast in palette-reduced floor
pits; the horizontal concrete contribution was reduced separately from walls.
The final M01 and M04 routes and independently loaded Windows export resources
include that refinement. Standard tour stills were refreshed and inspected locally.
M04's current receipt is `qa-m04-final/manifest.json`; the earlier `qa-m04/`
receipt remains history.

The fixed M01 intake performance tour recorded 600 frames per setting on
Windows, Compatibility/OpenGL and the AMD Radeon 780M at a 1920x1080 window.
The table records native resolution results for that quiet view. It does not
establish peak campaign combat, another GPU or cross-platform performance.
World pixel variants have separate samples in the same receipt.

| Setting | Sample frames | Mean frame ms | p95 frame ms | GPU ms |
|---|---:|---:|---:|---:|
| Performance | 600 | 3.23 | 6.43 | 2.69 |
| Balanced | 600 | 5.59 | 8.66 | 5.01 |
| High | 600 | 8.14 | 12.97 | 7.33 |

Receipt: `.agents/art-excellence-research/qa-m01-perf/manifest.json`.
This sample predates the final horizontal floor contrast adjustment.

| Texture | Dimensions | Storage basis | Additional base memory |
|---|---|---|---:|
| Sweeper normal atlas | 2880 x 4000 | Calculated RGBA8, four bytes per texel, no mipmaps | 43.95 MiB |

This is a base texture calculation, not a process-memory measurement or the
compressed PNG's disk size.

Rust format, warning-denied workspace clippy, workspace tests, locked release
build, license/banned/source checks, deterministic benchmark and unfiltered
93.80 percent line coverage passed after the tool changes. The final whole-client
gate passes all 218 scripts and 99 harnesses after the carbine profile and Latch
shape checks were corrected. Rendered model, material, water, backdrop,
close-camera and animation checks pass on Compatibility/OpenGL. Model normals,
water and Latch close-camera checks also pass on Vulkan Forward+ on this laptop.
The Windows release export passes native installation and graphical boot;
the pinned editor independently loads its pack for two real Low Water states.
Individual logs live in `verification-production/` and `package/`. The
[production evidence](../evidence/art-production-20261003.md) links inspected
captures and separates implementation from full quality acceptance.

The sample must show the character at close combat distance and thirty
metres, its facing and attack tell, and its hit and death response. Show the
gun's rest, fire and recovery motion with consistent muzzle registration.
The room needs a distinct landmark, structural depth, readable cover and
lighting that leaves the enemy clear. Compare the sample under M01 facility
light and a contrasting venue's light, with stills and motion captures.

Compare model-backed directional sprites with live meshes where feasible.
The recommended trial is detailed source models with pixel characters and
animated model weapons using pixel textures. This is a recommendation;
the final representation remains Nick's choice, informed by the trial.

Keep simulation, collision, inventory and shot outcomes in their existing
server seams. Decorative detail must fit authoritative geometry; any change
to actual cover or walking space needs matching server geometry and route
verification. Use existing GDScript authoring and bake tools without adding
a scripting runtime or changing the engine pin.

Acceptance requires inspected animation and lighting, readable attack tells,
correct character and muzzle registration, and recorded frame time and
texture memory on the inspected renderer and hardware. Extend the existing
character and viewmodel harnesses where the trial changes their contracts,
then run the full repository checks before calling implementation complete.
Headless checks cannot establish final art quality or rendered performance.

## Research, checked 2026-10-03

### Available models and access limits

The connected Higgsfield catalog returned seventeen 3D entries, including
aliases: Meshy image and multi-image generation, separate rigging, Meshy 7,
Tripo H3.1 single-image and multiview, Hunyuan3D, and SAM object/body
reconstruction. Meshy and Tripo entries describe GLB output. Catalog schemas
expose mesh-density and texture controls; Meshy also exposes rigging and
animation. This verifies catalog discovery, not generation quality or access
through the existing API key.

The connected workspace balance returned 10 credits on a free plan. This is
separate from Nick's originally reported $5.88 API balance and later $105.88
API top-up balance. Higgsfield's
[API terms, section 9.1](https://open.higgsfield.ai/terms-of-service) explicitly
separate prepaid API units from consumer credits. Partner models may have
different promotional eligibility. No dollar conversion was assumed.

Both cost-only calls for Meshy 7 and Tripo H3.1 were rejected by the available
image estimator because they are 3D models. The current tool set exposes no
dedicated 3D submission or estimate tool. The browser runtime discovered no
available browser, so the signed-in developer console could not be inspected.
No exact Higgsfield 3D dollar price, API route or credit eligibility is proven.

The subsequent [API checker](higgsfield-pipeline.md#api-capability-checker-2026-10-03)
used the existing API key successfully for image estimates ($0.004 Soul,
$0.020 Marketing Studio). The two connected 3D identifiers returned 404 as
candidate API estimate names. An authoritative 3D route remains unresolved;
this result does not prove that the entire platform lacks 3D generation.

The official [model discovery guidance](https://docs.higgsfield.ai/docs/llms.txt)
says to use each model's console documentation and distinguish production
from preview. Absence from the shared OpenAPI file does not prove absence
from the service. Do not guess a generation route or use a paid submission
to discover its price. These access limits do not block local model work.

### Candidate production paths

| Path | Evidence | Recommended role |
|---|---|---|
| Meshy through Higgsfield, if API access and price are verified | Connected catalog exposes GLB, PBR maps, humanoid rigging and animation; upstream APIs document those operations | First humanoid character candidate, followed by inspected deformation and custom combat poses |
| Tripo H3.1 through Higgsfield, if access is verified | Connected catalog exposes GLB, face limits, geometry/texture quality and PBR | Alternative geometry candidate; compare on the same reference only if the budget permits |
| Original local meshes and articulated parts | Existing Godot rig, material, animation and bake seams are already in the repository | Guns, doors, railings, facility trims, machinery and deterministic moving parts |
| Local open-weight 3D generation | Hunyuan3D-2.1 documents large GPU-memory requirements and a CUDA-tested setup | Separate feasibility research, rather than the first production dependency on this laptop |

[Meshy's image API](https://docs.meshy.ai/en/api/image-to-3d) supports GLB,
PBR maps, canonical poses and remeshing. Its
[multiview API](https://docs.meshy.ai/en/api/multi-image-to-3d) accepts one to
four images of the same object. Additional images need consistent geometry;
independently invented views are not reliable measurements of a character.

The [rigging API](https://docs.meshy.ai/en/api/rigging) is intended for textured
standard bipeds with clear limbs. It documents failures for unsuitable
anatomy and untextured meshes. Keep held guns separate, test shoulders, hips,
elbows and wrists, and author the actual attack, pain and death poses. A stock
walk animation does not prove the combat animation contract. Latch's face,
antenna and repairs need explicit local treatment; machines need their own
joint arrangements.

The upstream [API price table](https://docs.meshy.ai/en/api/pricing) lists
textured Meshy 6/7.1 generation at 30 credits, rigging at 5 and animation at 3
per action. These are Meshy's own units, not a Higgsfield quote. Its
current image docs name Meshy 7.1 as latest, deprecate Meshy 7 and retire the
older lowpoly mode on October 30, 2026. The connected catalog still advertises
Meshy 7. Resolve that version difference before production; do not silently
send upstream parameters to a wrapper with a different schema.

### Laptop and local workflow

Read-only hardware inspection found a Ryzen 7 7840U (eight cores, sixteen
threads), Radeon 780M and 61.8 GiB usable system RAM. There is no NVIDIA
adapter in the inspected display-controller list. Blender was not on PATH
or in the checked standard installation directory; this was not a complete
disk inventory. The project's pinned Godot toolchain is present.

This is a plausible machine for modest asset editing, Godot rendering and
sprite baking, subject to an actual workload measurement. It is not proven
for heavy local generation. The official
[Hunyuan3D-2.1 repository](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1)
reports 10 GB VRAM for shape, 21 GB for texture and 29 GB for the combined
pipeline, with a tested CUDA setup. Shared system RAM alone does not establish
compatibility or speed on the Radeon.

Blender is an optional external editor for topology, UV and skin-weight
cleanup, after checking its [hardware requirements](https://www.blender.org/download/requirements/)
and an actual viewport trial. The repository's implementation and tooling
remain Rust and GDScript. Commit GLB exports so game builds do not require
Blender. Godot [recommends glTF 2.0](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)
and imports GLB with materials, skeletons and animation.

### Pilot recommendation and implementation seam

Use an existing reviewed Sweeper reference to evaluate one clearly articulated
humanoid model. Prefer a clean A-pose, separated limbs, quiet base color and
a separate rifle. Preserve original source detail, then prepare a runtime
version or directional bake. Start with a local Shotgun mesh with separate
pump and hand transforms, and a small M01 kit with a door frame, wall trim,
railing and service fixture. These are proposed sample subjects, not accepted
final assets.

Keep detailed source meshes even when the runtime uses pixel textures or
sprite bakes. Reduce albedo deliberately after inspecting the source. Normal,
roughness and metallic maps contain surface data and must not pass through
the albedo palette reducer. If the sprite path wins, bake view-aligned normals
and verify their direction under moving lights; a model's tangent-space normal
texture cannot simply be pasted into a billboard material.

`tools/spritegen` now accepts a root or per-frame explicit `negative` string.
Omitting it preserves the earlier prompt bytes and request identity; an empty
string adds no avoid list. Reference/material specs can therefore use their
own exclusions without the old sprite-only constraints. Offline tests verify
the default request identity, override inheritance and invalid types/sizes.
The downloader and palette reducer remain image-oriented. Reuse the cost gate, locked reservations,
polling and recovery instead of adding a second ledger, while adding explicit
reference-image and model-output handling. Download and validate GLB outputs,
retain source hashes and inspect the import before accepting them.

Only a priced operation can allocate the authorized $105.88. Keep each run at
or below the existing $5 tool ceiling and the combined asset effort within
$105.88, including unresolved reservations. Quote generation, texture, rigging and
animation separately. Purchase another attempt only after inspecting the
first; do not enable top-ups or assume a failed job was refunded.

### Distribution terms

Higgsfield's [output ownership guidance](https://higgsfield.ai/creator-hub/help-center/account/who-owns-my-generations-and-can-i-use-them-commercially)
permits commercial output use. Its API terms also describe partner-specific
conditions and preservation of applied provenance. Confirm the selected
model's terms before accepting files into the distributable library.

Meshy's [ownership guidance](https://help.meshy.ai/en/articles/10137554-what-is-the-ownership-of-the-generated-models)
distinguishes paid private ownership from free-plan CC BY 4.0 outputs.
Tripo's [commercial-use guidance](https://www.tripo3d.ai/help/privacy-policy/how-to-use-tripo-models-commercially)
also distinguishes free and paid rights. A platform's free credit balance
does not establish which upstream licence applies. Record distribution rights
and retain required legal notices. A commercial-use statement alone does not
establish permission to redistribute the raw model under the repository's
licence.

## Remaining production choices

The current authorized work uses original local meshes, model-backed directional
sprites and inspected image sources. These remaining choices can be evaluated
without stopping that production path.

1. **3D acquisition:** evaluate the existing authorized Higgsfield credit
   after verifying the model route, exact price and distribution terms.
   Another service remains an option if that route cannot supply a usable
   asset. Local M01 kit work can proceed before any purchase.
2. **Hero characters and weapons:** AI-assisted modelling plus local
   rigging, or commission a human 3D or pixel artist for the recurring cast
   (Latch, the Union line, the guns). Hero characters are where generators are
   weakest and players look longest.
3. **Presentation:** model-backed directional pixel characters with animated
   model weapons (recommended for evaluation), or live 3D characters and
   weapons with pixel textures. Judge lighting and readability in the trial;
   normal-map sprites are an upgrade to the existing lit enemy path.

## Verification

- Bake receipts and manifest entries for every asset (prompt or source,
  model, cost, hashes, licence), with no generator credit in assets or UI.
- Tour stills and motion strips per venue, inspected against the reference
  set.
- `tools/godot_check.sh` and the existing character harnesses: pose layout,
  feet registration and stale-bake rejection.
- Performance measured with the [rendered benchmark](showcase-benchmark.md)
  when models replace boxes.

## Delivery and playthrough, 2026-10-03

Nick requested a rendered playthrough and ongoing delivery through a temporary
branch, a passing PR, squash merge to main and desktop releases when player-visible
changes warrant them. This increment changes visible characters and environments,
so this production increment ships as v0.68.0 after passing implementation and
main CI, plus all three tagged desktop package checks.

The existing ordinary-input Low Water tour is the recording subject. A diagnostic
subclass samples rendered frames from the normal real-time client and retains the
Master bus audio; encoding produces a shareable MP4 with capture timestamps.
The initial movie-mode smoke passed, but its full route failed at the Notary
lesson after capture changed client timing. That failed attempt remains diagnostic
history and does not count as a completed playthrough. The final real-time recording
completed all 23 states with a clean log, confirmed departure and was inspected
before publication. The video, receipt and checksums are attached to
[v0.68.0](https://github.com/blisspixel/fragr/releases/tag/v0.68.0); the
[production evidence](../evidence/art-production-20261003.md#recorded-playthrough)
records outcomes and capture scope. Movie output is visual evidence, not a hardware frame-rate
measurement or fresh-player acceptance.

Use the existing CI and desktop packaging workflows. No paid generation, cloud
deployment or simulation changes are needed for this delivery. Preserve the local
Rust, client, rendered fixture and package receipts, verify the PR's final commit
checks before merge, then require main CI and all three tagged desktop packages.
Keep full art excellence in flight after this production increment ships.
Implementation delivery shipped in [PR #337](https://github.com/blisspixel/fragr/pull/337)
at `5dbbde8ae91516620d7fa907ce6f8f855eddd887`.
[Implementation CI](https://github.com/blisspixel/fragr/actions/runs/37149465221)
passes. Delivery requires [main CI](https://github.com/blisspixel/fragr/actions/runs/37151264695)
and [tagged packaging](https://github.com/blisspixel/fragr/actions/runs/37151297637)
to pass before publication.
An extra blank line was removed from the offline Shotgun source during closeout;
re-exporting updated its source hash while every GLB and rendered asset remained
byte-identical. The original local verification receipt remains dated evidence,
with the delivery receipts under `.agents/art-playthrough-20261003/`.

## Remaining production allowance, 2026-10-03

Nick asked for the approximate cost of good art across the full game and whether
another service is needed. The following is a planning estimate, not approved
spend or a provider quote. It assumes reuse across the twelve proposed campaign
environment kits, shared body variants and local model cleanup. It excludes hired
artists, development compute and runtime hosting.

| Remaining production work | Estimated additional allowance |
|---|---|
| Reusable environment kits, props and materials | $200-$400 |
| Remaining character and weapon assets, including 3D trials | $150-$300 |
| Skies, story art, decals and effects | $100-$200 |
| Rejected attempts and corrections | $50-$100 |
| Total | $500-$1,000 |

The completed image batch reserved about $0.62 per high-resolution request;
those requests produced sources, not a finished roster or twelve complete kits.
The proposed allowances include iteration and remain uncertain until accepted
assets establish a usable-output rate. A $500 planning target can be reviewed in
$50-$100 production batches, each composed of tool runs within the existing
$5 ceiling. No $500-$1,000 allowance has been approved. Existing sources support
continued local integration without another deposit.

Higgsfield's verified API supplies images and ElevenLabs supplies audio. A
dedicated Meshy API account is recommended for a small enemy, weapon and prop
pilot, followed by cleanup and in-game acceptance. It is not required for local
mesh work. The [official API overview](https://www.meshy.ai/api), checked
2026-10-03, says Pro or above is required for API access; verify purchased API
credit and its dollar conversion before submitting anything. The
[upstream pricing table](https://docs.meshy.ai/en/api/pricing) separates models,
rigging and animation. Existing Higgsfield credit is not a proven way to fund
those operations; additional purchases retain their written spend-approval gate.
More generation alone does not establish visual quality: modeling, motion,
lighting, populated rooms and played comparison remain the production work.

### Meshy account check

Nick subsequently selected Premium for fragr ($40 per month, $20 for the first
month) and configured the `meshy` credential entry in the ignored `.env`.
The [documented balance endpoint](https://docs.meshy.ai/en/api/balance) returned
HTTP 200 and 3,100 available API credits on 2026-10-03. A one-off read-only check
accepted his entry; it submitted no generation jobs and recorded no credential.
Receipt: `.agents/art-playthrough-20261003/meshy-api-check-20261003.json`.
The [plan guide](https://help.meshy.ai/en/articles/12062933-which-meshy-plan-is-right-for-you-free-vs-pro-vs-premium-vs-ultra)
lists API access on all paid individual tiers. Premium supplies production
capacity; its subscription tier does not establish model quality. The provider's
pages disagree on Ultra's allowance, so no Ultra credit count is assumed.

The [native pilot](meshy-pipeline.md) now proves generation, rigging, bounded
downloads and rendered Godot imports for an enemy, weapon and environmental prop.
It includes a second Shotgun topology candidate, seven GLBs total and visible
walking/running motion. [Evidence](../evidence/meshy-pilot-20261003.md) records
125 net credits consumed, 15 held for a refused request and its final API balance
of 2,975. All 140 reserved credits remain within the pilot's 150-credit allowance
and existing $5 run ceiling. No additional purchases or top-ups were enabled.
The pipeline reuses the current image references, dotenv, locked request ledger
and artifact writes, with live credit checks before each paid stage. The native
pipeline shipped in PR #339 after full CI passed.

The [Clerk presentation](clerk-model-presentation.md) shipped on main in PR #340
after full CI and bounded M01/M02 routes. Its compact skin supplies authored
combat, reactions, seated posture and death, with canon charcoal cloth and paired
normals. A subsequent unarmed correction adds physical forward follow-through.
The [Shotgun preparation](shotgun-model-presentation.md) proves its separate pump
and attached support glove; first-person selection remains open. The generator
still needs cleanup and placement at game scale. Broader played art acceptance
remains open. Preserve required legal notices and paid-plan
output rights when preparing public model sources. The existing v0.68.0
playthrough shows the prior integrated art, not this new pilot.

Nick subsequently rejected photographic human treatment and clarified that the
Union's black/red signature belongs to outfits and issued equipment, not every
wall. The [new stylized Clerk revision](union-field-uniform.md) starts from a
new full-body reference and replaces the source face, cap, uniform and plates.
It consumed 40 existing credits for the model and inspected rig. Its directional
poses, actual moving-light check, clean guard-room replay and full local client
gate pass; [PR #346](https://github.com/blisspixel/fragr/pull/346) owns integration.
The final free checker reports 2,905 available credits and the unchanged
15-credit hold. Net locally tracked consumption is 165; another 30-credit account
decrease has no local production receipt. These stages made no new cash purchase.

The [Low Water detail](m04-inhabited-world-polish.md) and
[lunar port workmanship](m06-world-workmanship.md) passes shipped in PR #344 and
#342, with clean 26-state and 28-state ordinary-input routes and passing full
implementation CI. Their captures also identify the next architectural gaps:
M04's missing clinic/workshop roofs and thin domestic frontage, and M06's broad
empty freight/customs deck. Finite local detail does not close whole-map art
acceptance. Civilian plaster, timber and personal possessions, and lunar
pressure-shell finishes, remain place-specific.
