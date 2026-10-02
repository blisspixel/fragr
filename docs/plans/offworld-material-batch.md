# Offworld material batch

Status: implemented material library, local pixel gates and inspected lit preview
passed, full client checks and release pending. Updated 2026-10-01.

Nick requested more textures across distinct worlds. This bounded batch supplies
five reusable pixel materials for Mars habitat and industrial work, following
the [Mars guide](../design/mars.md), [ship guide](../design/space.md),
[art bible](../ART_STORY_BIBLE.md) and shared [palette](../palette.json).
Mars missions remain unbuilt. A material preview does not prove a playable world.

## Materials and use

| ID | Material and readable purpose | Intended registration |
|---|---|---|
| mars_basalt | Dark fragmented volcanic stone, sparse iron-red dust in cracks | Mars exterior rock, future authored venues |
| mars_regolith | Quiet dusty rust terrain with compact wind-worn clusters | Mars exterior ground, future authored venues |
| offworld_pressure_habitat | Worn pale pressure cladding, repaired seals and restrained oxidation | Enclosed civilian habitat and appropriate existing industrial panels |
| offworld_mining_deck | Dark worn industrial deck plate, broad non-glowing tread and dust | Mining and freight walking surfaces where the existing activity fits |
| offworld_thermal_ceramic | Pale ceramic shielding with sparse chips and dark joints | Habitat and launch-service heat shielding, appropriate existing equipment panels |

Terrain and building skins have distinct value fields. Bone pressure skins and
dark structural frames protect silhouettes against dusty red ground. Wear shows
maintenance and life-support work, without new faction marks, text or canon.
Tiles contain no baked lighting, emission, liquid gameplay or collision promises.

## Exact operation and spend

Use the existing `target/release/fragr-spritegen.exe` binary and
`tools/spritegen/specs/offworld-materials-20261001.json`. Five independent direct
`marketing-studio/image` requests, square 2k, medium quality, enhancement disabled.
The official [model API reference](https://open.higgsfield.ai/models/marketing-studio/image/api-reference)
was checked 2026-10-01 for direct generation, dimensions and request behavior.
The live estimate endpoint supplied $0.624 for the complete exact medium batch
before generation. Root reserved that estimate and allocated a $0.65 ceiling
under the shared round allowance. The first request used that batch ceiling;
later individual requests used $0.13 ceilings, so their combined maximum stayed
under $0.65. No extra generation requests were submitted.

Output and request ledger are isolated under
`art/raw/offworld-materials-20261001`. Root owns the overall allowance and serial
round ledger. Price only first; report all IDs and total to root for allocation.
Generate once with an explicit cap from that allocation, using existing included
credits. No top-ups, overages, speculative replacement requests, new cash charge,
runtime API or CI network call. Preserve uncertain reservations and accepted IDs.

## Processing and gates

Inspect all originals before reduction. Reduce with the existing local palette
tool to 128 or 256 pixels, opaque square, nearest filtering, no mipmaps. Repair
tile boundaries locally through an original deterministic GDScript bake if
needed; preserve material-specific forms and inspect repeated 3 by 3 previews.
Record source/spec hashes, request IDs, estimated cost, output dimensions and
keeper hashes. Strip source metadata by local image re-encoding. Do not present
rejected candidates as shipped polish.

Godot processes require root's serialized lease. Inspect native-scale material
boards and repeated tiles, check actual image loading and clean process exit.
Root owns shared surface shader and material registration, including any existing
venue mapping. This lane also owns the explicit `OffworldMaterials` library,
focused keeper harness and offline material preview tool. The library uses cached
textures and separate lit, rough material instances without emission.
An inspected library preview is explicitly separate from a released Mars mission
or final in-world lighting acceptance. Current Rust runtime remains untouched.

## Evidence

An initial free low-quality estimate was $0.148 for five requests. No images
were submitted at that quality. The primary medium batch completed five requests
and downloaded all five original 2048-pixel images. Reserved estimate: $0.624;
confirmed billing: unknown; new cash charges: $0. Account credit allocation was
authorized from the existing owner-reported balance, not an API quota response.

| ID | Estimated USD | Retained request |
|---|---|---|
| mars_basalt | 0.124 | 61a4b52a-9e6b-444a-9a7c-cefe42e18a9d |
| mars_regolith | 0.125 | 4d3bce10-1c19-478d-af43-7a293a950b6f |
| offworld_pressure_habitat | 0.125 | 9812bf85-d627-489b-a90f-7312a10b1399 |
| offworld_mining_deck | 0.125 | 8d4df265-50e9-4cde-82f4-0f9e41542409 |
| offworld_thermal_ceramic | 0.125 | c3cd588e-8706-4a5d-a8fd-c581f8ff57b2 |

The returned polling metadata was refused by the existing origin validator.
Each exact accepted ID was attached through the documented keyless recovery
command and polled at the official origin. There was one generation POST per
material, no replacement POST, and no validator relaxation.

All original images, native keepers and 3 by 3 repeats were visually inspected.
An initial reduction flattened regolith because the shared palette lacked dusty
brown middle values. Root added `dust_rust` and `dust_light` to the canonical
palette; all five final keepers and retained small sources were reduced again
against that exact palette. Its SHA-256 is
`c97f60cb92a212166e1506ab1cb32f0705227e205b6ecb7fcd83701491f19da5`.
The native inspection preserves quiet material fields, broad fracture/panel
forms, restrained non-glowing dust and distinct dark/pale value roles.

Five opaque 128-pixel keepers pass exact palette membership and matching
opposite-boundary checks. Eight-pixel edge bands receive local seam repair;
unchanged interiors retain the original material forms. The existing reducer
restores the shared palette after that blend. The five RGBA tiles use 320 KiB
uncompressed without mipmaps. No normal or height map is claimed.

CPU verification and parsing logs are under
`.agents/m06-buildout-20261001/offworld-*.log`; measured pixel facts and repeated
boards are in `offworld-preview/`. Full prompts, request and content hashes are
in the public [asset manifest](../../client/assets/environment/offworld/manifest.json).
The 2k downloads and append-only ledger remain in the ignored local art backup;
small reduced sources and deterministic seam tooling are committed candidates.

The offline preview loaded all five imported keepers through their actual lit
materials in the pinned Compatibility renderer on AMD Radeon 780M. Its clean
exit and PASS marker are recorded in `offworld-lit-preview-final.log`; the owned
process closed normally. The inspected
[material board](../screenshots/world_materials_mars_library.png) shows separate
wall slabs and floors and explicitly labels Mars missions as unbuilt. It proves
the material preview, not gameplay or general hardware performance.

Root's full client checks and release remain pending. No Mars map or new gameplay
venue has been shipped.
