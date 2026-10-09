# Level 18: All Systems Normal development graybox

Status: **in flight**. Spend: $0. This file does not turn level 18 into the
multiplayer Wipe mode. The shared Wipe plan stays a later dependency. Story
stays in the accepted level 18 text.

## Lore route

[Level 18](../CAMPAIGN-MISSIONS.md#level-18-all-systems-normal) and the
[level 18 design](../campaign/m10-all-systems-normal.md#level-18-design-twenty-level-expansion)
own the scene. Episode V begins as recognizable recovery after the Office fell.
Six weeks later the problem of the day is a tram part across town. The square
is bright, the stalls are rebuilt, a tram is stalled, and Union bots that were
never freed still work under a human supervisor. Then ordinary things fail.
Local restoration machines treat occupied space as work. Nobody in the scene
knows the planetary scale yet.

The route is four beats:

1. Populated transit square.
2. Disrupted clinic route, with the direct street closed.
3. Maintenance escape, the service flank and sheltered passage.
4. Overhead view of the district, including a second district in the same pattern.

Free companions stay themselves. Union bots switching together into Inheritance
control is a later rule, not this graybox. The Collector is the level's new
lesson and does not exist yet.

## Graybox

`server/maps/test/m18_recovery_development.json` is a development map, not a
mission. Map id 1018. Name: `All Systems Normal (development)`. Document
version 1. Equipment policy discovery. LF line endings only. No mission key
and no `m13` key. `campaign_mission_id` stays empty.

Solids and landmarks follow the four beats:

| Beat | Landmark | Solids |
| --- | --- | --- |
| Populated transit square | `transit_square` | Stalled tram, two market stalls, aid van, repair post. Arrival is here. No encounter covers the arrival. |
| Disrupted clinic route | `clinic_route` | Clinic block and sign, barricade across the direct street. The landmark stands south of the barricade. |
| Maintenance escape | `maintenance_escape` | Service passage, mouth posts and lintel, twelve service treads and cheeks west of the barricade. |
| Overhead view | `district_overlook` | Deck, pump house, parapet, skyline tower, two distant district blocks. The tower face is visible from the square. |

After the square, three existing hostiles stand on the disrupted route and in
the passage: two Sweepers and one Heavy Sweeper. They are ordinary authored
bodies, not a boss, not a Collector, and not an Inheritance control switch.
Contested secret stocks are armor and a medkit by the van, shells by the tram,
and cells by the pump house. No weapon is placed.

`server/tests/m18_development.rs` loads the file through `AuthoredMap::read`,
checks map id 1018, an empty mission state, the four landmarks, and
return routes for landmarks, stocks, and enemy feet. An unpopulated walk
covers the square, the clinic street, the passage, the stair, and the deck
without a jump. The loader was not relaxed.

The integration test reads an empty mission state through `GameState`.
`campaign_mission_id` stays crate-private. No mission id was added.

## Unbuilt

- Collector body, tell, exposed phase, and the limits of destroying it
- Union bots switching together into Inheritance control, while free companions remain themselves
- Human supervisor, clinic queue, service door, and any scripted rupture
- Skippable scale montage
- Connected mission, clock, objectives, and continues
- Save promotion
- Menu entry
- Wipe director, sentries, vehicles, and multiplayer Wipe

## Verification

`cargo fmt -p fragr-server` completed with exit 0.

`cargo test -p fragr-server --locked --test m18_development -- --test-threads=1`
passed 2 tests: `recovery_development_reads_without_a_mission` and
`recovery_route_walks_the_four_beats_without_a_jump`.

A passing graybox is not a finished level 18. Fresh-player play, the ten-minute
clock, and the unbuilt rows above remain open.
