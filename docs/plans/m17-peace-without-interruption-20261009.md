# Peace Without Interruption development graybox

Status: **in flight**, 2026-10-09. Spend: $0. This is the first geometry pass for
level 17. It is not a connected mission, and it does not change the campaign
contract in [CAMPAIGN.md](../CAMPAIGN.md) or the level text in
[CAMPAIGN-MISSIONS.md](../CAMPAIGN-MISSIONS.md) and
[m09](../campaign/m09-peace-without-interruption.md).

## Goal

Stand up a walkable Forever Office graybox on the accepted level 17 route so
later encounter, weapon, and capture work has rooms to land in. The map is
development only.

## Non-goals

No new story. No Denial weapon, Voss capture rules, boss, connected mission,
save promotion, or menu entry. No transmitter, no single switch, and no claim
that one building holds every institution on Earth, the Moon, and Mars.

## Lore route

[Level 17](../CAMPAIGN-MISSIONS.md#level-17-peace-without-interruption) keeps
these facts:

- Coordinated uprisings are already breaking regional enforcement. The player
  reaches the local command center. Allies make the wider victory possible.
- Chancellor Voss is captured alive. Her composure breaks, colder and quieter,
  not louder. She does not shout in German. The historical echo is the room,
  the seals, the forms, and the screen behind her.
- The wipe later interrupts the promised reckoning. Her later fate stays
  unconfirmed.
- Route: civic approach (level 16's transit is the previous level), occupied
  public hall, administration ring, command galleries, assembly chamber. One
  flank bypasses a frontal kill lane and opens the exit used after the
  confrontation.
- [CAMPAIGN.md](../CAMPAIGN.md) names Denial as the level 17 lesson. That
  weapon does not exist.

The [level 17 design](../campaign/m09-peace-without-interruption.md#level-17-design-twenty-level-expansion)
still owns the longer interior: security core, secured chamber, liberated
hall, three doors, the outer service stair, and the proposed Registrar
Kessel scene. This pass does not replace that design.

## Graybox

`server/maps/test/m17_forever_office_development.json`

- Version 1. Map id 1017. Name: Peace Without Interruption (development).
- Equipment discovery. LF line endings. No mission key, including no `m13`
  gate key. `campaign_mission_id` stays empty.
- Landmarks: `civic_approach`, `occupied_public_hall`,
  `administration_ring`, `command_galleries`, `assembly_chamber`, plus
  `frontal_kill_lane`, `flank_bypass`, `north_wrap`, and `later_exit`.
- The street is walled by office masses and two piers, not an open parade.
  The occupied hall has benches and a rostrum. The administration ring is a
  loop around a records core. The command galleries are the west rooms north
  of that loop. The assembly chamber landmark is the open floor where Voss would
  be confronted later. She is not an actor.
- The frontal kill lane is the straight hall-to-chamber corridor. The flank
  leaves the hall west, through the ring and galleries, then a west passage
  and the north wrap, and that wrap opens `later_exit`. The same flank also
  enters the chamber from the west. The chamber's east door meets that exit.
  The exit does not open back onto the civic street.
- A records sign faces the ring. The chamber's north wall carries a union
  seal and a terminal. That terminal is the screen behind the confrontation
  point. No slogan text and no German.
- Encounters use existing kinds only: Clerk, Sweeper, Heavy Sweeper, Turret,
  Auditor, and Enforcer. Discovery supplies are an ordinary flechette, bullets,
  health, and armor.
- The integration test reads an empty mission state through `GameState`.
  `campaign_mission_id` stays crate-private. No wire, save, or menu field was added.

## What stays unbuilt

- Denial, including its plinth, charges, refill rule, and any stand-in gun.
- Voss capture rules, boss AI, surrender staging, and the proposed line.
- A connected mission, mission id, save promotion, and menu entry.
- The raised galleries, outer service stair, security-core seal, destructible
  local defenses, and the three mission doors.
- Registrar Kessel, allied actors, the liberated hall scene, subtitles, par,
  and mastery.

## Verification

`server/tests/m17_development.rs` loads the file, requires map id 1017,
`campaign_mission_id` none, the route landmarks, and complete routes for the
flank and the kill lane. A cleared-encounter walk follows that route with
ordinary movement. Geometry fixes belong in the map, not in a weaker loader.

```
cargo fmt -p fragr-server
cargo test -p fragr-server --locked --test m17_development -- --test-threads=1
```

## Spend and safety

Implementation cost is $0. No new assets, dependencies, or hosting changes.
The graybox does not certify a finished level 17.
