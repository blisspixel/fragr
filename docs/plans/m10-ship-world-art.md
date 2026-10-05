# Common Carrier ship furnishing

Status: in flight, 2026-10-05. This isolated art lane starts from prototype
`b0e6eb91`, with the prototype's remote and final composed played gates still
open. It belongs to the existing campaign rung. It does not change mission
authority, carry, actors, difficulty or the 28-state combat route.

## Source-true problem

The inspected actual route-v5 cabin, service, freight, command and departure
frames show a structurally readable pressure hull with repeated slab equipment,
a box-like bed, bare controls and few ordinary possessions. Spacious cargo
handling remains useful. The next improvement should explain how people live
and maintain this repaired transport, not fill walking aisles with arbitrary
objects. Distinct Edda/Splice source work and Repeater art are separate lanes.

The ship remains original, stylized and approximately 2070: warm bone shells,
worn gunmetal, restrained rust and green maintenance fittings, pixel paint,
practical warm lamps and limited navigation cyan. Civilian equipment has mixed
repair histories. Black/red belongs to the invading Union, not every fixture.

## Existing sources and exact reuse

Use the three compact prepared sources already in
`client/art/world-props/candidates/`: `air-scrubber.glb`, `water-pump.glb` and
`community-radio.glb`. Their canonical offline preparation is
`tools/prepare_world_prop_sources.gd`. Preserve their actual legal metadata,
original receipts and embedded textures. Reuse their existing preparation;
do not regenerate these models or quietly recolor the source into new identities.

The repair workbench has no prepared artifact. Its inspected raw source is
`art/raw/meshy-pilot-20261003/repair-workbench-stylized-v1-ultra-0.glb`, SHA256
`37c149f3b6c402a349e283f4e49ab3baded27bfba5932a86b058556dc8537682`.
It has 10,567 triangles, 14,872 vertices, one fixed mesh and embedded 4K paint.
The reviewed reference and dimensions are in
`docs/screenshots/civilian-first-sources-20261004/receipt.json`.
Extend the existing preparation seam with a bounded workbench specification.
Preserve every retained source face, UV, winding, finite normal and legal
notice; record uniform scale, actual worktop height, source bounds and grounded
supports. Nominal worktop height is 0.88 to 0.95 m, subject to the actual host
geometry below. No new paid source is required for this increment.

## Intended use and physical boundary

| Place and existing host | Source and function | Physical constraint |
|---|---|---|
| Lower service `service_power_bank`, x 2.8..4.8, z 0..2.5, feet 2 | Scrubber equipment and authored connected intake casing explain working life support | Prepared scrubber is about 1.21 x 1.65 x 1.21 m. Its dressing must remain within the existing opaque equipment envelope; retain a believable casing around any otherwise invisible solid |
| Aft service `service_coolant_bank`, x -4.8..-3, z 9.3..11, feet 2 | Pump, its four actual grounded mounts and contained return plumbing explain recycling/thermal maintenance | Prepared pump is 1.20 x 0.64 x 0.48 m. Keep the existing blocked volume visibly enclosed rather than removing its shell while leaving invisible cover |
| Passenger `passenger_repair_bench`, x 4.5..7.3, z -9.8..-8.6, feet 4.8 | Actual repair workbench, restrained tool storage and charging detail replace the generic work slab | Existing top is 0.85 m above deck, below nominal source target. First measure source worktop and fit. Do not raise it or remove collision merely for art; report any incompatible height/width before a separately tested map amendment |
| Upper `command_console`, x 1.5..3.5, z -16.8..-16, feet 7.6 | Compact community radio, useful display and locally wired controls show Tern's working station | Prepared radio is 0.38 x 0.37 x 0.18 m. Small mounted trim is not new combat cover or an interactable objective. Retain visible support and never imply a new control or remote-authority rule |
| Passenger galley and bunk area | Local reusable brackets, a proper bunk silhouette, tied bags and ordinary personal detail | Existing hull, beds, counter, routes, crew feet and supplies stay fixed. Small craft is scoped to accepted hosts; request a new source only if local craft cannot meet the visual bar |

Exact placements remain candidates until measured source/host fit and viewed
in the real room. Source vertices cannot extend a large walk-blocking object
beyond authoritative collision. Any retained invisible broad solid must gain
a corresponding opaque casing. Do not fake empty space with a source model
inside an invisible crate. Preserve body headroom, all supply feet, shot lanes,
stair access and actor contact. All objectives, pickups, crew feet, stairs and
guard definitions stay unchanged. The initially proposed unchanged collision
has been superseded by the authorized narrow workbench decomposition below;
other geometry stays unchanged. The new authored hash and actual route are
independent acceptance gates.

## Owning implementation seams

Add a bounded packaged ship-furnishing presenter through the existing M10
accepted-map configuration and teardown. Reuse registered surfaces and host
geometry. Validate the exact venue and physical host bounds before attaching
details. No extra mission facts, wire fields or client outcome authority.
Coordinate any selective solid-view dressing in `arena_cover.gd`; other venues
must retain their existing source and rendering. Avoid hiding the entire hull
or equipment bank to show a smaller source.

Runtime sources belong under `client/assets/` and helpers under
`client/scripts/`. Offline `client/art/` is excluded from desktop packages.
Embedded images retain nearest filtering and restrained finish. The presenter
has bounded instances, world visual layer 2, real venue lighting and complete
map replacement/scene teardown. It does not preload actor-only fill or new
runtime services. Preserve matching packaged copyright notices.

## Acceptance before selection

1. Independent source proof compares retained raw/prepared face areas, UVs,
   winding and normals, verifies finite attributes, worktop dimensions and
   actual mount support. Retain rejected preparations and exact fingerprints.
2. Actual accepted-map tests assert source/host bounds, supported feet,
   bounded instance counts, venue-only selection, malformed-map refusal and
   map replacement cleanup. Prove all existing M10 body/shot cover and route
   gates remain equal; representative asset presence alone is insufficient.
3. Export and actual install checks load the real packaged helper, meshes and
   embedded textures, without offline source paths. Complete focused source,
   material, presentation and lifecycle checks must pass error-clean.
4. Obtain one serialized hardware slot for full-size cabin, service and command
   views in actual light, with an unchanged ordinary route if runtime dressing
   could obscure supplies or enemies. Inspect grounded models, readable mixed
   materials, visible cover, control purpose, silhouette and useful space.
   Record source/map/native hashes and retire owned processes.
5. Compose only reviewed source, then run the matching complete client checker
   and exact-head CI/packages before main selection. New shot-body integration
   and prototype's final played gate remain independently required.

The pass is complete only when the actual inhabited room views are accepted.
It does not close named casting, Repeater discovery, story or fresh-player fun.

## First source checkpoint

The workbench is prepared offline at a measured 0.90 m worktop height. Actual
export/reimport retains all 10,567 source triangles, face area, winding and UVs;
four bottom quadrants are supported without added pads. Its whole bounding
box is 1.8153 x 1.13595 x 1.0396 m. Normal packing introduces a measured maximum
direction drift of 0.0002434; the new independent orientation check bounds this
at 0.0005 and rejects a 0.01-radian rotation and complete reversal. Existing
position/UV/winding and support gates retain their original strictness.

The helper's default operation still prepares only its original three sources;
their resulting GLBs compare byte-for-byte equal to the existing candidates.
The bench requires an explicit exact selector; an unknown selector refuses
before creating any model. All positive preparation/proof runs exit numeric
zero with clean logs and PASS markers. A first placement of a material branch
caused a retained parse failure and was corrected. The initial overly precise
normal comparison failures are retained with measured import drift; they do
not change any previously existing acceptance threshold.

Only the offline candidate is added. Runtime/host reconciliation, actual room
lighting, packaged availability and played selection remain open. Details:
[workbench source evidence](../evidence/m10-workbench-preparation-20261005.md).

## Authorized physical furnishing increment

The measured 1.815 m bench cannot truthfully replace the old 2.8 m solid by
just hiding its visible slab. Narrowly decompose that one authoritative host
around its actual cabinet, worktop and rear-rack shape. Keep the working
surface near 0.90 m, physically supported, with the true knee opening visible
and accurate for shots. The standing player still cannot walk through a
0.90 m-high tabletop; the opening does not imply a new crouch mechanic.
Measured support parts remain separately counted within the existing
128-solid ceiling. Preserve every other object, objective, supply, crew foot,
stair, encounter and difficulty fact. No combat or arrival assertion changes.

Before regenerating source, correct the authoring generator's stale return
platform endpoints. The accepted map already joins west at -3.450000286 m and
east at 3.450000048 m on both heights; the generator still recreates the old
0.10/0.20 m gaps. Prove regeneration retains these exact supported joins and
that the physical-art delta is confined to the measured bench decomposition.
Archive old map/hash, generate a fresh content hash and matching private
native, and validate owned save fixtures against the new map. Do not mutate
the frozen prototype PR to make the old capture look current.

Require actual body/ray tests for the tabletop, cabinets and knee opening,
supported access around the source, all four recorded optional-crew rosters
and historical unknown. The unchanged literal route and actual full 28-state
combat/departure must pass on matching source before art selection. Final
composed shot-body blocking remains a required prerequisite. Hardware work
uses a serialized parent lease and owned process retirement.

The corrected generator emits all 112 actual native solids and all other map
facts unchanged. Its JSON writer shortens the last decimal digits of four
platform coordinates; independently parsed server f32 values are exactly equal.
The repeat proof retains both hashes and those four representation differences.
The original accepted map bytes are restored until the actual bench geometry
increment, so this tool repair alone does not change any content hash or save.
