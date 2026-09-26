# Flying Union drones

**Status:** planned, 2026-09-24. Design lives in
[ENEMIES.md](../ENEMIES.md#union-drones); this plan owns the build. Stage 1
starts with M03 in rung 7 of the
[full build order](../ROADMAP.md#full-build-order-2026-09-22), not before.
**Spend:** $0. Sprites come from the offline rig and bake, no paid generation.

## Goal

Two server-authoritative flying enemies on the existing campaign encounter
seam: the Notary patrol drone for M03 and the heavier Assessor for M07. A
player learns each one's tell, meets it at readable heights, shoots it down
with guns already carried, and watches it fall. Agents see and fight it through
the same wire.

## Non-goals

- Aircraft, player flight or flying vehicles. The jetpack belongs to
  [vehicles](vehicles.md).
- A general 3D navigation mesh or volumetric pathfinding.
- Swarms. Rooms hold at most two Notaries or one Assessor on Standard.
- Migrating the arena Compliance Drone. It keeps its behavior until a separate
  decision.
- Client prediction of enemies. The local pawn is the only predicted body, so
  hover movement needs no GDScript mirror.

## What exists

The arena Compliance Drone is a walking player body with `is_boss`, spawned at
2.2 m and pulled down by `movement::integrate` like any fighter. It gives spawn
and down events and a scaled billboard, not flight.

The campaign seam gives the rest: `EnemyController` in
`server/src/encounters/enemy.rs` with Idle, Moving, Windup, Firing, Recovery,
Hit and Dead; aim committed at the start of the windup; a hit that cancels a
pending shot; the per-difficulty `attack_timing` table; `CampaignActor::Union`
identity with `phase_started` and `phase_ends` on the wire;
`combat::line_of_sight` against solids; alarm and search memory; encounter reset
on a continue; shipped vertical aim and `ShotTrace`; and directional sprites in
`client/scripts/enemy_animation.gd` and `enemy_view.gd`.

## Design

**Hover body.** A drone is a sim body flagged airborne. While alive it skips
gravity. A small server-only `hover_step` in `movement.rs` moves a box volume
(Notary about 1.3 by 0.7 m, Assessor about 2.6 by 1.2 m) toward a steering
target at a capped speed, slides along solids, and clamps height to its band
above `Navigation::floor_below` and at least 1 m under `ceiling_height`. It
never leaves its authored hover volume. A gentle bob is presentation only.
Body `y` keeps the existing convention: `y - PLAYER_FLOOR_Y` is the underside.

**Air routing.** Fly straight when a swept volume check between the two points
is clear. Otherwise take the existing walking route for the floor below and
lift each waypoint to hover height, keeping only points with ceiling clearance.
Searches share Session's navigation budget and stagger like ground enemies. No
new graph.

**Positioning rules.** The steering target keeps horizontal distance to the
target at least equal to the height above it, stays within 28 m, and prefers
positions with line of sight both ways from the optic to the target's eye. A
drone with no such position inside its volume patrols; it never hides out of
reach, never heals, and never enters a volume no ordinary weapon can hit.

**Attack phases.** The Notary reuses the Sweeper's flow with its own timing row:
Windup (optic flare and shutter), Firing (three hitscan rounds on the committed
aim), Recovery (dim drift). The Assessor's Firing launches three canisters
through the shared server projectile seam that the Jammer and the rocket launcher need;
Recovery opens the vents, which the hit test reads as a full-damage face.

| Tier | Notary windup / recovery | Assessor windup / recovery |
|---|---|---|
| Assisted | 24 / 36 ticks (1.2 / 1.8 s) | 32 / 50 ticks |
| Standard | 16 / 26 ticks (0.8 / 1.3 s) | 24 / 40 ticks |
| Severe | 12 / 20 ticks (0.6 / 1.0 s) | 18 / 32 ticks |

Proposed numbers, tuned in play. Tiers change tells and room caps, never HP.
The half-second floor from the difficulty contract holds. New timing rows
require a new `CAMPAIGN_RULES_REVISION` and matching client validation.

**Hits and splash.** Add a raised box target beside `Ray::fighter` in
`combat.rs`, placed from the drone's underside, used by the same shot
resolution in `sim.rs`. Assessor plates halve bullet damage when the hit normal
faces the front or belly; the Arc and splash ignore plates. Splash, once the
projectile seam exists, measures to the nearest point of the volume and stops
at cover.

**Death and crash.** On death the body regains gravity, keeps a little of its
velocity with a server-owned tumble yaw, and stops on the floor below. The Dead
phase lasts until landing plus a short hold. The Notary wreck is harmless and
non-blocking. The Assessor wreck damages Union units within 1.5 m of the landing
point and never participants. A continue removes wrecks with the encounter.

## Protocol

- `EnemyKind` gains `notary` and `assessor`. `docs/protocol.md`,
  `actor_state.gd` validation and the adapter README change in the same PR.
- No new phase. Snapshot position already carries height.
- A crash event is added only if the tour shows clients cannot read landing
  from snapshots.
- Authored encounter JSON gains an optional `hover` block per drone: band,
  volume box and patrol points. `maps/authored/encounters.rs` rejects volumes
  outside bounds, clipping solids or ceilings, or with no standing position in
  the mission's reachable area that can see and hit the volume.

## Client

- A drone rig in `client/art/characters/rig.gd` from `geometry.gd` primitives:
  black body, ducts, red optic, red Office seal, and the Assessor's plates,
  launcher and vents. Faction colors follow the art bible's Union entry.
  `bake.gd` renders eight directions of hover (two bob frames), windup flare,
  fire, recovery, hit, tumble and wreck into `client/assets/characters/union/`
  with manifest hashes.
- `enemy_view.gd` registers the sprite at the underside, not the floor, and
  draws a floor shadow from a client raycast. The shadow is cosmetic; the
  server owns the landing point.
- Spatial fan hum loop, shutter click, Assessor countdown chirp and crash, all
  captioned, through the existing audio routing.

## Agents

Agents already receive position, kind, phase and `phase_ends` in snapshots.
The brain's local controller gains pitch in target selection and a strafe on a
drone windup, the same reaction it uses on the ground. `agents/brain` question
text names the new kinds. MCP tools and schemas are unchanged.

## Stages

1. **Notary on the server.** Hover step, air routing, positioning rules,
   timing rows, raised hit volume, fall and crash, authored `hover` validation.
   Seeded test room fixture.
2. **Notary presentation.** Rig, bake, shadow, audio, captions, tour states for
   patrol, flare, fire and crash.
3. **M03 placement.** Roof loop and tram trench encounters once the M03
   graybox exists, plus the M02 gallery sighting behind glass (non-combat).
4. **Assessor.** After the projectile seam ships. Plates, vents, canister
   volley, wreck damage, rig and bake, M07 greenhouse placement.

## Verification

- Deterministic tests in `server/src/tests.rs`: hover stays inside band and
  volume; no position directly above the target; no shot before the windup ends
  on every tier; a strafe during the flare evades the burst; a hit during the
  flare cancels it; line of sight required both ways; kill, fall, landing and
  harmless wreck; Assessor wreck damages Union units only; plates and vents;
  encounter reset on continue; validator rejects an unreachable perch.
- A seeded solo human and solo agent clear of the test room and of the M03
  placement through the live session, with the shared equipment controller.
- Godot headless checks with a drone harness; regenerated tour stills showing
  the flare and a crash, inspected in motion.
- Bench run unchanged within noise with two Notaries active.

## Success

A fresh viewer can point at a Notary, say when it is about to fire, and dodge
it; it is never smaller than a Clerk's torso on screen; nobody dies to a drone
they could not see or reach; and a scripted agent kills one with vertical aim
through the ordinary wire.
