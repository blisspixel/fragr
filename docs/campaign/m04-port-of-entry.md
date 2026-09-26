# M04: Port of Entry

**Status:** proposed, unbuilt. Moon before the wipe. Target 8-12 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#m04-port-of-entry).

## Story and cast

A text transition acknowledges travel time and changing conditions on Earth.
Tern brings the party to a controlled lunar port. Latch needs a route to the
custody depot; Mara coordinates with local contacts without becoming omniscient.
The port serves established communities. Workers and families are visible through
safe glass, with ordinary schedules and possessions alongside Union restrictions.

The objective is getting in, not conquering the whole Moon. Tern remains with the
transport; Latch assists only through spaces the player actually clears.

## Route and place

Dock service bay -> freight hall -> customs split -> shielded crater cut ->
archive entrance. Customs has an interior maintenance bypass; the crater cut loops
back above the freight hall for a useful overview and resupply.

The port is open cargo floor, galleries and stairs; no airlock cycling or
pressure puzzles. Pressure glass and bulkheads are scenery, not doors to open.

| Space | Shape and purpose | Fight or story beat |
|---|---|---|
| Dock bay | Thick pressure bulkhead, cargo bay, crew facilities | Safe arrival and explanation of the next link |
| Freight hall | Cargo lanes broken by tall handling structures | Sweeper/human pairs, lateral movement and a short flank |
| Customs split | Two galleries overlooking a central inspection desk | First deliberate Railgun lane; ordinary weapons use the service bypass |
| Service branch | Pipes and broad maintenance stair | Optional fight that marks a prisoner route for M05 |
| Crater cut | Short exterior protected by berms and structural shielding | Elite Enforcer introduced with room to dodge, clear environmental protection |
| Archive entrance | A lower freight approach and an upper administrative deck | Reconverging routes, one shared mission exit |

Earth is a landmark, not the whole backdrop. Show dust control, seals, pressure
glass and buried habitation. Combat does not require a spaceflight system or
unimplemented low gravity. Any later movement variant needs explicit tests.

## Encounters and equipment

Guarantee the Railgun before the customs lane and enough Cells to learn it. The Rifle
and Shotgun retain roles along cargo and service routes. The Sniper Rifle is
found on the crater cut, after that Railgun lesson, with a few shots to learn a
slower scoped hit. Customs can be cleared without it. Enforcer commitment
and recovery are visible; the first charge never starts offscreen beside a spawn.
The Turret is introduced here. Turrets protect positions the player can flank, not every long sightline.

Secrets: pressure-maintenance cache and an upper cargo overlook with armor. The
optional service-branch fight marks a prisoner route that helps in M05; missing
it locks nothing away.

## State and scenes

`port_entered` -> `customs_cleared` -> `depot_entered`, by fighting and arriving.
Optional `prisoner_route_marked`. A continue restarts at the dock with entry state.

Mastery hooks, planned, not built: a par time on the result, the customs
maintenance bypass as the runner's line, and best clear time in the service record.
Body choice does not exempt agents from environmental limits while humans die;
equipment and shared rules determine exposure protection.

Opening uses a short arrival panel or restrained in-engine view, with text
establishing location and elapsed time. No lore lecture on lunar colonization.
Humor: a port declaration requires reporting how much Earth dust one imported.

## Allies and acceptance

Test both approach routes, rail-free completion, autonomous allies,
mission-start retry and spectator view changes.
Verify that the archive entrance and the port's inhabited purpose are readable.
