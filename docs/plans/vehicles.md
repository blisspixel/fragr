# Vehicles: jeep, motorcycle, jetpack

**Status:** planned, 2026-09-24. Design and staging only; nothing here is built.
**Spend:** $0. Meshes, textures and sounds come from in-repo tools and the
approved audio pipeline within existing credits.

## When

Vehicles are built only when the campaign reaches the mission that needs one.
Much of the game is built without them. No vehicle rung is in the near-term
sequence and none of this blocks Act I (M01 to M03), M04 to M07, or the
controls work in rung 7 of the [full build order](../ROADMAP.md#full-build-order-2026-09-22).

| Rung | Starts when | First use |
|---|---|---|
| 1. Vehicle seam and jeep | M08 is the next mission in rung 8 | M08 launch works |
| 2. Motorcycle | M09 is next | M09 transit approach |
| 3. Jetpack | M10 is next | M10 changed streets and waterworks |
| 4. Campaign placement | Inside each of rungs 1 to 3, same mission cycle | M08, M09, M10 |
| 5. Multiplayer vehicle map | Phase 4, after team deathmatch | Conquest-lite |

Each rung also needs buttery-controls stage 3 (prediction and reconciliation),
which rung 7 ships before M04, so the dependency is met by the time M08 is
next. If a mission's plan drops its vehicle, that rung waits for the next
mission or for rung 5.

## Goal

Battlefield 1942 feel on fragr's rules: walk up, press Use, drive; hop in the
gun seat; jump a berm; bail out and keep fighting. Vehicles open routes and
firing positions. They never turn a mission into a compulsory ride, and losing
one never strands the player.

## Non-goals

- Simulation physics: suspension, gears, tire models, damage per part.
- Aircraft, tanks, boats or a roster beyond these three.
- Destructible terrain, vehicle customization or persistent vehicle unlocks.
- A second action channel for driving. Humans and agents use the same `Action`.
- Predicting anyone else's vehicle. Other vehicles are interpolated.

## The three

**Jeep.** Two seats: driver and gunner. The gunner's mounted gun is a heat
gun, not an ammunition pool, so vehicle ammo can never become a mandatory key;
overheating has a visible glow and a captioned hiss. Proposed: top speed about
16 m/s, 400 HP, occupants exposed above the doors. A solo player can park and
switch to the gun, the way it was always done in 1942. An autonomous ally may
take the free seat on its own; it is never required. M08's captured utility
rover is this jeep in coalition paint.

**Motorcycle.** One seat. Proposed: top speed about 20 m/s, quick acceleration,
120 HP, rider fully exposed, a hop on Jump. The rider does not fire in rung 2;
a forward-cone sidearm is a later decision on playtest evidence.

**Jetpack.** A personal movement item carried in inventory, not a seat and not
a vehicle entity. Hold Jump in the air to thrust. Proposed: three seconds of
fuel, refilling after half a second on the ground; thrust slightly stronger
than gravity; better air control while thrusting; a hard ceiling from the map.
The wearer can shoot. A visible flame and hiss tell enemies and players where
the flyer is, and a fuel gauge sits in the HUD.

## Architecture

**Server.** A new `server/src/vehicles.rs` owns vehicle entities, seats and
`vehicle_step`, called from the `sim.rs` tick before pawn movement. Occupied
pawns skip `movement::integrate`; their position follows the seat. Seat
actions route through the existing per-player `Action`:

- Driver: `forward` and `back` are throttle and brake-reverse, `left` and
  `right` steer, `jump` is the handbrake (jeep) or hop (motorcycle). The
  driver's yaw and pitch are free look within a cone and do not steer.
- Gunner: yaw and pitch aim the mounted gun; `fire` fires it.
- `interact` enters the nearest free seat within 2 m or exits. A new optional
  `seat` field switches seats; switching takes half a second.

**Physics, arcade.** One speed scalar, steering rate that falls with speed,
strong grip with a small drift, gravity when a wheel leaves the support height,
and landings that keep momentum. Ground height comes from the map's
`support_height`; collision uses three circles along the body with the
existing `blocks_motion` tests. A wall hit stops or deflects the vehicle and
damages it above a speed threshold. A flipped vehicle rights itself after two
seconds.

**Jetpack in movement.** Thrust is a change to the shared movement contract,
so `movement.rs`, `client/scripts/movement.gd` and
`client/golden/move_vectors.json` change together, with new golden vectors for
thrust, fuel and ceiling. Fuel is inventory state in `server/src/inventory.rs`.

**Prediction.** The driven vehicle is predicted like the local pawn:
`vehicle_step` has a GDScript mirror and its own golden vectors
(`client/golden/vehicle_vectors.json`). Reconciliation reuses the stage 3
correction blend. Every other vehicle is interpolated.

**Entry and exit safety.** Exit samples standing positions around the vehicle
with `blocked_body_at`; if none is free, the exit is refused with a short
notice rather than ejecting into a wall. Entry and exit are refused above a
low speed. At zero HP the vehicle burns for two seconds with smoke and a
countdown sound, occupants are ejected to safe points, then it explodes
through the shared server splash seam.

## Collision and damage

- Hitscan hits the vehicle's body box or an exposed occupant; exposed zones
  are part of the vehicle definition, not guessed by the client.
- Splash and rockets are strong against vehicles; the Arc is not
  special. Numbers are tuned per rung.
- Run-over damage scales with speed above about 6 m/s and applies only to
  hostile actors under the existing `hostile` rule. Allies, civilians and
  teammates are pushed aside, never killed.
- Vehicle against vehicle damages both by closing speed.

## Vehicles as targets

Union enemies target occupants and the vehicle under their normal sight and
hearing rules. Notaries and Assessors are natural jeep-gunner targets, and
Clerks and Sweepers take cover from an approaching jeep instead of standing in
the road. Empty vehicles are not targeted unless they block a route.

## Agents

Snapshots gain a vehicle list (id, kind, position, yaw, speed, HP, seat
occupants, burning) and each `PlayerState` gains an optional vehicle and seat.
The brain's local controller drives by steering toward the next point on a
route at tick rate; the decision model only chooses "enter", "drive to",
"gun" or "exit" at its normal few decisions per second. Maps that allow driving
author drive lanes, validated against solids like walking routes. MCP tool
schemas keep their shape; `act` documents the `seat` field.

## Client presentation

Low-poly meshes with pixel textures and nearest filtering, built from the same
kind of in-repo primitives as `client/art/characters/geometry.gd`, consistent
with the [look pass](look-pass-boomer.md). Sprites are wrong for something a
player sits inside and circles around. Coalition vehicles wear bone, leather
and ember with scraped-off Union plates; Union vehicles are black and red.
Driver view is first person with a chunky dashboard; a chase camera is a
presentation toggle. Engine loops pitch with speed. Spectator cameras follow
vehicles. HUD: vehicle HP, gun heat, seat, and jetpack fuel.

## Campaign fit

- **M08 jeep.** The rover circuit across depot, berm and gantry, as the M08 plan
  already describes. Infantry routes are proven first; the Walker stays
  defeatable if the jeep is lost.
- **M09 motorcycle.** A run down the civic transit approach from the coalition
  staging point to the foothold, past checkpoints under Notary patrols. The
  transit station is the foot route if the bike is lost. No timer, no escort.
- **M10 jetpack.** Coalition gear in the evacuation concourse. It opens roof and
  waterworks lines over Paver work strips during the changed-streets phase. The
  ground route always works.
- **Moon and Mars.** No per-map gravity is assumed. If one is added later, the
  jetpack is where it is felt first, and it changes movement goldens.

No vehicle adds a door. Each mission keeps at most three.

## Multiplayer

Rung 5 is one vehicle map after team deathmatch exists (Phase 4 bigger modes):
16 to 32 fighters, jeeps and motorcycles at team bases on respawn timers,
jetpacks as map pickups, and conquest-lite: three control sites and ticket
bleed, per [Frontline objectives](../MODES.md#frontline-objectives). The map
must be fun on foot first. Abandoned vehicles return to base after 30 seconds.

## Verification per rung

- Deterministic tests: enter, exit, seat switch, refused unsafe exit, speed
  limits, wall stop, run-over only on hostiles, burn and eject, explosion
  through splash, continue reset, golden vectors in both languages.
- A seeded agent drives the test map lap and guns a target through the live
  session. A human drives it in the Godot client with a recorded correction
  metric.
- Tour stills and motion for entry, driving, gunning, jetpack flight and a
  wreck. Bench run with vehicles active.
- Each campaign placement: the mission clears with the vehicle, without it,
  and after losing it.

## Success

Getting in and driving takes no explanation. The driven vehicle shows no
visible correction on a LAN. An agent can drive and gun on the same wire. No
mission is ever lost because a vehicle was lost.
