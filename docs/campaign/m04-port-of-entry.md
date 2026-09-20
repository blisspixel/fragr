# M04: Port of Entry

**Status:** proposed, unbuilt. Moon before the wipe. Target 8-12 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#m04-port-of-entry).

## Story and cast

A text transition acknowledges travel time and changing conditions on Earth.
Tern brings the party to a controlled lunar port. Latch needs a route to the
custody depot; Mara coordinates with local contacts without becoming omniscient.
The port serves established communities. Workers and families are visible through
safe glass, with ordinary schedules and possessions alongside Union restrictions.

The objective is access, not conquering the whole Moon. Tern remains with the
transport; Latch assists only through spaces the player actually clears.

## Route and place

Dock service bay -> freight hall -> customs split -> shielded crater cut ->
archive access. Customs has an interior maintenance bypass; the crater cut loops
back above the freight hall for a useful overview and resupply.

| Space | Shape and purpose | Fight or story beat |
|---|---|---|
| Dock bay | Thick pressure bulkhead, cargo airlock, crew facilities | Safe arrival and explanation of the next link |
| Freight hall | Cargo lanes broken by tall handling structures | Sweeper/human pairs, lateral movement and a short flank |
| Customs split | Two galleries overlooking a central inspection desk | First deliberate Rail lane; ordinary weapons use the service bypass |
| Service branch | Pipes, pressure controls and broad maintenance stair | Optional prisoner-transfer shortcut for M05 |
| Crater cut | Short exterior protected by berms and structural shielding | Elite Enforcer introduced with room to dodge, clear environmental protection |
| Archive entrance | A lower freight approach and upper administrative door | Reconverging routes, one shared mission exit |

Earth is a landmark, not the whole backdrop. Show dust control, seals, pressure
glass and buried habitation. Combat does not require a spaceflight system or
unimplemented low gravity. Any later movement variant needs explicit tests.

## Encounters and equipment

Guarantee Rail before the customs lane and enough Cores to learn it. Flechette
and Scatter retain roles along cargo and service routes. Enforcer commitment
and recovery are visible; the first charge never starts offscreen beside a spawn.
Turrets protect positions the player can flank, not every long sightline.

Secrets: pressure-maintenance cache, upper cargo overlook with armor, optional
transfer shortcut. The shortcut creates a tactical benefit in M05 but its absence
cannot lock captives away permanently.

## State and scenes

`port_entered` -> `archive_access_secured` -> `depot_entered`.
Optional `transfer_shortcut_open`. A continue restarts at the dock with entry state.
Body choice does not exempt agents from environmental limits while humans die;
equipment and shared rules determine exposure protection.

Opening uses a short arrival panel or restrained in-engine view, with text
establishing location and elapsed time. No lore lecture on lunar colonization.
Humor: a port declaration requires reporting how much Earth dust one imported.

## Allies and acceptance

Airlocks have safe occupancy rules for the player and autonomous allies. Required
items cannot be sealed out. Test both approach routes, rail-free completion,
ally occupancy, pressure transitions, mission-start retry and spectator view changes.
Verify that the archive entrance and the port's inhabited purpose are readable.
