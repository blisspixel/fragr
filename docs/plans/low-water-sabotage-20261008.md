# Low Water Sabotage

Status: implemented locally, 2026-10-08. This is the second original Sabotage venue in
the existing multiplayer buildout. Spend: $0.

The [source-bound evidence](../evidence/low-water-sabotage-20261008.md) records
69 walking routes, both-site finite combat/use checks, two completed rule-bot
matches, the ordinary ten-socket side-swapped match and eight inspected renderer
states. Integration, human balance, LAN and final-art gates remain open.

## Goal and source findings

Build a compact original ten-fighter Low Water town with Clinic Steps and Tram
Stop as its two plant sites. The accepted map roster describes homes, a clinic,
repair market and tram trench. The current M04 town is a separate campaign map
with ordered encounters, a clinic shutter and roof departure. It does not contain
the multiplayer trench. Do not rename M04 or reuse its mission identity.

Use the existing built-in builder and validation convention with stable map id
8, `Low Water`. Keep Sector 9 unchanged. This work supplies playable geometry,
mode layout, host selection and evidence. It does not establish human enjoyment,
finished art, ranked play, hosted capacity or campaign completion.

## Layout and architecture

Use an 84 m square town, with three north-south choices through the clinic side,
market and depot side. Street floor is 3 m over the tram trench's base floor.
Three short bridges cross the trench; stairs at both ends connect both street
banks without jumps. Original building shells, stalls and service walls interrupt
spawn sightlines and create useful approach and retake alternatives. Preserve
the civilian warm plaster, ceramic and service-steel material kits.

The Union checkpoint musters north, the coalition south. Both sites lie on the
north street bank, Clinic Steps west and Tram Stop east. This keeps the district's
west/east identities while giving defenders an earlier arrival at either site.
Each site has its bridge/street approach, a trench-stair flank and a defender
rotation. The market clock explains the middle. No civilian, campaign gate,
water hazard, vehicle or destructible objective is implied.

`maps/low_water.rs` owns geometry, surfaces, sites, side spawns, muster zones,
stages, approaches and clear hold spots. The built-in runtime shares the same
arena and navigation for every role. Replace the rule bots' Sector 9 coordinate
heuristic with explicit layout-owned approach routing, preserving its exact
existing predicate for Sector 9. Reuse held Use, charge contact, authoritative
damage, shared navigation and the wire objective controller. Do not change round
arithmetic, timings, admission, inventory, combat or the four-search Session
budget.

Register map 8 in the existing roster and CLI. Extend the desktop five-per-side
host selector and ready validation to accept Sector 9 or Low Water. Reuse the
existing Sabotage map/state, HUD and markers with exact Low Water venue
registration. Reserve gameplay floor 45 for Low Water through the integration
owner; do not silently admit a client that cannot present the venue contract.
No new protocol shape, transport, dependency, paid asset or save format belongs
to this increment.

The existing site prop and event words are specific to Sector 9's frame/server.
Derive Low Water's registered Clinic Steps/Tram Stop wording and small control
props from the current site's callout, preserving Sector 9's default art and
labels. This is presentation of accepted site facts, never client outcome logic.

## Verification

- Validate the original arena, surfaces, origin, ordinary spawn support, every
  site disk, ten side slots, muster boundaries, hidden starts, stage and hold
  spots. Prove routes with the shared navigator and actual authoritative
  movement, including both sides, each plant site, all trench stairs and bridges,
  supply claims and retakes. Record timings and limitations rather than infer
  equal balance from symmetry.
- Exercise actual finite Tack five-per-side admission and start equipment,
  ordinary walking, held plant and defuse, cancelled work, a resolved carrier
  death, charge drop/grace/recovery, both sites, side swap and match ending.
  Geometry fixtures may place an initial route walker, but played objective
  proofs must use ordinary inputs and the real state machine.
- Retain a full ten-fighter seeded native match with finite equipment and no
  weakened Sector 9 survey/CI assertions. Run ordinary WebSocket clients through
  live MapInfo, validated loadout, plant and defuse and a whole side-swapped
  match. Keep scripted mechanics separate from unscripted combat balance.
- Verify client host settings, ready shape, picker, surface registration and
  Sabotage presentation. Coordinate native builds and renderer ownership before
  running them. Fresh rendered evidence and human play are separate gates.
- Keep failed attempts, commands, source hashes and measured outcomes under
  `.agents/low-water-sabotage-20261008/`, with a public evidence summary when the
  implemented scope is ready. Preserve existing CI thresholds and historical
  evidence unchanged.

## Acceptance and limits

The final combined client check exposed an older host-menu assertion that still
expects Sector 9 alone. The actual host validator and selector now support
Sector 9 and Low Water. Update the harness to verify both exact map identities,
retain Sector 9 as the default and exercise selection without changing the
existing launch/readiness assertions. Retain the failed complete check, require
the focused host-menu check and rerun the whole client suite before integration.

The local implementation is complete when map 8 can be selected and hosted,
both sites and retakes are reachable, finite ten-fighter rules run to a match
ending, ordinary sockets prove charge handling and use, and focused checks pass.
Integration, packages, other-platform execution, two-machine LAN, actual human
side-swapped play and voluntary rematches remain distinct acceptance gates.
Root owns the shared roadmap and index updates. No commit, publication, cash
charge, generation, top-up or overage is part of this work.
