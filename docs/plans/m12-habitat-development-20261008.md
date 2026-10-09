# Terms of Cooperation habitat development level

Status: **implemented**, local verification 2026-10-08. Parallel development authorized by Nick.
This standalone practice map develops the accepted [level 12 habitat
brief](../campaign/m07-terms-of-cooperation.md#level-12-design-twenty-level-expansion).
It does not connect or unlock a campaign mission.

## Bounded slice

Build a pressure arrival hall, enclosed market cross-passages, a greenhouse
hub with two combat routes, a maintenance bay, a utility bypass and a
breached pumping court. The greenhouse frames and pump towers are visible
from the market. Sheltered rooms, cultivation-bed blockouts and short exterior
links establish the intended habitat layout. Crop art, pressure glazing and
acceptance of sealed habitation remain unfinished. Both flanks reconnect and remain
walkable without jumping. Finite weapons, ammunition, health and armor use
the existing discovery policy. Optional stocks do not supply a required gun.

Use established Clerks, Sweepers, Heavy Sweepers, Enforcers and Notaries
under their actual identities. The maintenance bay holds an established
Heavy Sweeper and ordinary guns. The intended Arc is unbuilt and no existing
gun is renamed to stand in for it. The Assessor, its canisters and falling
wreck are unbuilt, and an existing Notary is never presented as that drone. Shelter
door state, civilian rescues, damageable pumps, arriving aid and coalition
commitment remain separate work. No fixed ordinary prop establishes that
the aid has arrived.

## Architecture and protocol

The strict authored discovery schema owns all playable geometry, ordered
encounter definitions and supplies. The file is
`server/maps/test/m12_habitat_development.json`, named
`Terms of Cooperation (development)`, with map ID 1012. A deterministic
GDScript authoring helper reproduces it. Launch it through the existing
`--map-file` path. There is no new mission ID, readiness operation, objective
state, save promotion, wire type or campaign unlock. The existing registered
materials and neutral habitat lighting are reused. The parallel launch-works
presentation change owns explicit Mars venue registration.

## Verification and success criteria

The strict loader must accept the complete source and reject malformed
geometry and duplicate identities. Prove routes from arrival to every stock,
enemy approach and landmark, and back. Exercise both greenhouse flanks and
the utility bypass with ordinary server movement and no scene teleport.
Use resolved normal shots to clear the established groups with finite stock,
then prove the last participant leaving resets encounters and stocks, with
a fresh participant at the authored entry and no process-clock rewind.
Separately inspect a rendered route at ordinary player height.
Record which gates pass and retain failures. Automated clearing and visual
inspection do not establish fresh-player understanding, the target duration,
human fun, Assessor acceptance or a completed level 12 campaign mission.

## Spend and safety

Implementation costs $0. Reuse committed geometry, textures, audio and
actors. Do not call paid asset services, add dependencies, touch production
hosting or enable top-ups. Preserve existing dirty work and coordinate
shared builds and presentation files with the parallel level work.

## Local evidence

Seven native tests pass, including 90 route checks in both directions and a finite
human-magazine clear through the actual session and enemy controllers.
The ten-state rendered human route passes and all ten stills were inspected.
The [evidence](../evidence/m12-habitat-development-20261008.md) retains the
corrected direct-waypoint failure, distinct native/rendered damage counts,
hashes and unfinished art and mission acceptance. The bounded static slice
is implemented; connected mission and final appearance remain in flight.

The later unfiltered composition caught an obsolete unknown-actor fixture:
it used `assessor`, now a supported identity from the separate drone foundation.
The failure is at that identity assertion, after both geometry obstructions
were correctly refused. Replace only the obsolete identity with
`unsupported_habitat_actor`; keep blocked-bridge, sealed-utility and duplicate-ID
checks unchanged. The standalone source and its original receipts remain exact.
Repeat the complete seven-case integration before accepting this correction.
