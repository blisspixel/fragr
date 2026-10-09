# Mars habitat, foundry and launch development slice

Status: **implemented**, local verification 2026-10-08. Nick authorized parallel character,
multiplayer and three-level development. This plan owns the missing standalone
foundry and a bounded consistency review of the existing habitat and launch maps.
It does not turn them into three connected campaign missions.

## Goal and scope

Follow the accepted [level 13 foundry brief](../campaign/m08-weight-of-permission.md#level-13-design-twenty-level-expansion)
between [Terms of Cooperation](m12-habitat-development-20261008.md) and
[Launch Authority](m14-vehicle-development-20261006.md). Build a service entrance,
protected foundry edge, machine hall with short flanks, worker-quarter blockout,
freight office and loop, maintenance ring, two ordinary stairs and upper ladle
galleries. A large supported ladle, shielded process machinery, cargo handling,
water-feed housing and freight-lift shaft establish the site's ordinary purpose.
The lift landing is a development destination only.

Use established actors under their actual identities in five ordered encounters,
with finite discovery weapons, ammunition, health and armor. Both the floor route
and the maintenance route must reconnect, reach required supplies and reach the
gallery through supported stairs without a mandatory jump. The great ladle and
lift shaft should remain useful visual landmarks. Retreat stocks must stay clear
of later activation regions until the player's explicit advance.

The Rocket Launcher is absent from the current weapon enum. Do not rename an
existing gun or claim its lesson. Rockets, Arc, Assessor, Worker release and
choice, damageable relay, protected live utilities, timed machinery hazards,
moving lift, new voice lines, connected departure, save promotion, vehicle combat
and the Walker remain outside this slice. Static forge surfaces are scenery,
not simulated heat or a hazard. No fresh-player, target-duration, final-art or
three-mission completion claim follows from automated clearing.

## Architecture and ownership

The deterministic `tools/author_foundry_development.gd` writes
`server/maps/test/m13_foundry_development.json`. The strict discovery schema owns
all playable solids, stocks, landmarks, supported actor placements and ordered
encounters. Map ID 1013 has the exact source name
`The Weight of Permission (development)` and half extent 58 metres. The planned
industrial footprint is approximately 80 by 108 metres, with ground-level work
lanes and a three-metre gallery rise. Launch through the existing `--map-file`.
No mission document, MissionID, readiness verb, wire shape, campaign unlock,
runtime authority or new dependency is added.

An explicit foundry venue reuses offline Mars textures and registered surfaces,
with dark frames, pale shielding, neutral work lights and bounded forge accents.
Existing habitat and launch preset values remain unchanged. Shared presentation
edits are coordinated with their current owners. Character and crew runtime are
owned by the parallel character lane.

New focused integration tests live in `server/tests/foundry_development.rs`,
avoiding the shared unit-test registration seam. The QA manifest and any direct
route mirror own only this level. Existing M12/M14 receipt hashes retain their
original scope; change either map only for a concrete discovered defect and
revalidate its affected gates before replacing evidence.

## Verification and acceptance

1. Reproduce identical authored bytes. Load through the strict boundary and
   reject malformed identity, support and route fixtures.
2. Prove every stock, guard approach and landmark reachable from arrival and
   back. Walk the floor, maintenance ring, both stairs and gallery loop using
   ordinary authoritative movement without body resets or scene teleports.
3. Clear all ordered groups through `GameSession::tick_messages` and resolved
   normal fire with finite human magazines and ordinary reloads. Count actual
   kills and enemy attacks. Require no death, no granted recovery, no explosive
   substitute and no secret required to afford completion.
4. Check useful stock claims and that pre-fight resupply remains outside the
   next group's region. Last-participant leave must reset stocks and encounters
   while a new participant starts at arrival without rewinding the process tick.
5. Mirror the actual QA straight segments through shared movement before a live
   rendered route. Inspect full-size world captures at ordinary player height,
   including stairs, foundry landmarks and both route choices. Record exact
   native, map, route and image hashes, actual outcome counts and exit logs.
6. Review habitat-to-foundry-to-launch narrative adjacency and physical route
   consistency. Keep any unimplemented connective mission work explicit.

Broad composed gates and renderer scheduling remain coordinated by the parent
lane. A focused pass is not silently substituted for a full repository gate.

## Spend

$0. Reuse current geometry, models, textures and audio. No generation service,
cash charge, credit use, top-up, cloud action or dependency change is authorized
by this plan. Preserve existing working-tree changes and do not commit.

## Local result

The bounded static foundry is implemented with 121 solids, 19 finite stocks,
22 established guards and five groups. Four native integration tests pass,
including 118 return routes, ordinary walking through both stairs and a finite
human-magazine fought clear through actual enemy controllers. The direct shared
movement mirror passes 77 QA waypoints. The first rendered route completes all
18 states and five fights with 22 kills, no death and clean exit logs. All 18
world originals were inspected. The [evidence](../evidence/m13-foundry-development-20261008.md)
and [receipt](../screenshots/m13-foundry-development-20261008.json) retain exact
source and executable hashes, separate native/rendered counts and unfinished
appearance and mission acceptance. M12/M14 source bytes are unchanged. Connected
campaign work remains in flight under each mission's own contract.
