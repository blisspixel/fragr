# Level 20: Local Exception development

Status: **in flight**, 2026-10-09. First development geometry for the accepted
[level 20 brief](../campaign/l20-local-exception.md). This is not a mission,
not a scored survival gate, and not the multiplayer Wipe.

## Goal

Hold a readable waterfront while free-agent friends argue for one local
exception. The player keeps people alive on the pier. The reprieve, when it
exists, is credited in the fiction to the network built across the campaign,
not to a score, a mercy ranking, or a last-survivor duel. Surviving level 20
after levels 18 and 19 is what unlocks [Still Here](epilogue-still-here-20261009.md).
Rescue totals may later change the cited number and which faces return. They
never decide whether the level can be finished.

## What this pass builds

`server/maps/test/m20_local_exception_development.json` is a standalone
discovery map, version 1, map id 1020, name `Local Exception (development)`.
It has no mission key. `campaign_mission_id` stays empty, so the file does
not become a save stage, a menu entry, or an epilogue unlock.

The route is the accepted one: waterworks, freight pier, refuge approach,
then three short approaches that meet the pier.

| Place | Solid | Landmark |
|---|---|---|
| Waterworks | Tower, both sluices, valve house, pump house | `waterworks` |
| Waterworks approach | North and south cheeks | `approach_waterworks` |
| Freight pier | Pier edges, crane, harbour screen, crates, Edda's bollard | `freight_pier`, `eddas_lamp` |
| Freight yard approach | Yard walls | `approach_freight_yard` |
| Tram trench approach | Trench walls | `approach_tram_trench` |
| Refuge approach | Approach walls, the level 5 freight platform beside the crossing, closed refuge gate | `refuge_approach` |

The three approach landmarks sit on the pier mouths. The gate is a closed
solid in front of the player. Nothing past that gate is in this file. The
epilogue refuge is not authored here.

Pressure uses existing Sweeper and Heavy Sweeper identities only. Discovery
stocks on the pier are the existing flechette, shells, cells, health, and
armor. The valve-house stock is the existing rocket launcher, the brief's
secret, not a new weapon. The lamp armor is the existing armor secret on the
ground. The crane cab, and the jetpack route to it, are not built.

## Canon this pass keeps

Latch, Tern, and the other free agents are in the waterworks, off the pier,
asking the thing that took the Union's machines for one refuge. The player
is on the pier. The harbour screen is the place for the Inheritance's one
precise message. That message is not implemented. The reprieve, the machines
stopping at the refuge line, and Latch walking back are not implemented.
Tern's one line and Latch's "Held them. We're even." are not voiced here.

The separate [Wipe plan](wipe-survival.md) still owns the unbuilt campaign
clock and the unbuilt multiplayer wrapper. One living participant is enough
in that multiplayer exception. This development map is not that mode. It has
no seats, reinforcements, last-survivor win, or duel.

## Non-goals

- No Surveyor, Collector, or Paver kind. Surveyor is still the level's new
  lesson, and that enemy does not exist. No existing actor is renamed into it.
- No new weapon, vehicle, sentry, jetpack, clock, door, or mission id.
- No scored gate, rescue meter, hidden morality check, or battle-royale
  mercy duel. Survival is not a ranking of who deserved to live.
- No epilogue geometry, forecast fragment, or years-later walk in this file.
- No save promotion, menu entry, or campaign unlock.
- No edit to the plan index, the roadmap, or `AGENTS.md` in this pass.

## Verification

`server/tests/m20_development.rs` loads the file, requires map id 1020,
discovery equipment, LF line endings, an empty `campaign_mission_id`, and
walking routes from the entry to every route landmark. Each approach landmark
must also walk from the pier and stay within 14 metres of it. Geometry fixes
belong in the map. Do not weaken the loader to make a route pass.

A passing load does not establish the twelve-minute hold, fresh-player
readability, the Surveyor lesson, the reprieve, or a finished level 20.

## Still unbuilt

The Surveyor mark and its exposed observation phase. The waterworks crew
crossing as a release, not a kill count. The harbour message and the running
total of people this run actually freed. The twelve-minute clock, the last
six minutes, and the machines stopping at the refuge line. The one refuge
door. Finite sentries, jeep, motorcycle, and jetpack on this ground. Connected
entry from level 19. The epilogue unlock and the distinct exhaustion ending.
The shared Wipe director and its multiplayer rules.

## Spend

Implementation and the local test cost $0. No new assets.
