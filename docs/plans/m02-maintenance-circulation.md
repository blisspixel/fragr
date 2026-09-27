# M02 maintenance circulation

**Status:** in flight, 2026-09-27. This follows the [optional side ward](m02-side-ward.md)
in draft #276 and belongs to the accepted [Persons Unknown brief](../campaign/m02-persons-unknown.md).
It does not complete the level.

## Goal and why

Give M02 a real runner's line and a real return loop. After learning the lone
Crawler's tell, a player can choose the visible pack landing or a service route
that rejoins at the antechamber. After Latch is released, the east side ward
can be entered from one side of the processing floor and exited through another.
Both choices should change the approach to an encounter, rather than adding a
dead-end secret or a second door puzzle.

The old brief says an antechamber-to-floor passage skips the stair's second
landing. In the current map the antechamber follows that landing. A literal
pre-release connection into the processing floor would also bypass the one
release-controlled shutter and reverse the Latch reunion. Correct the route
wording to a fork after the first Crawler that rejoins at the antechamber. Keep
the ward and shutter as the only path into the floor.

## Boundaries

- Keep the Shotgun guard room and the lone Crawler on the obvious first route.
  Preserve the ward fight, Latch's required release Use, the shared shutter,
  floor fight and dock objective. The pack landing may be bypassed by a player
  who notices the service route; its encounter remains live on the direct path.
- Keep the one-door, one-Use contract. Add static traversable geometry and an
  un-gated return opening. Do not add a mission objective, wire field or
  gameplay capability for a route choice.
- Preserve the optional status of the side ward. A main-route clear must not
  depend on its guards, captive animation or Latch navigation. Released is not
  evacuated; an actual evacuation state waits for server-owned actor movement.
- No new enemy type, final art batch, paid API call or cloud resource. External
  spend for this slice is $0 within the current $20 build allowance.

## Architecture and map design

`server/maps/m02-persons-unknown.json` owns all blocking walls, platforms,
stairs, surfaces, trigger regions and supplies. Reuse its existing authored
world and navigation; no client-only collision. The initial candidate fork is
near the lower switchback after `crawler_first` (around x -12, z -27). The
existing pack trigger spans x -14.8 to -11.8, z -29 to -22.5 and y 0 to 0.6;
a ground-level fork at x -12 would wake that encounter. Begin the branch east
of its x edge, or raise the player's feet above its y edge before entering.
A full-body-width maintenance passage remains above the `crawler_pack` trigger
until it passes the trigger's north edge, then descends in walkable steps and
rejoins the antechamber near x -14, z -22. Exact dimensions are determined by
the shared movement and route tests, not by the sketch alone. The direct
landing stays readable as the main fight route. Do not hide the only intended
route behind an unmarked wall.

The side-ward loop uses a roughly three-metre ground-level opening in the
floor's east wall near the conveyor, north of the existing side-ward entrance.
The width leaves a usable centerline between the pawn radius and side-ward
cover for Latch as well as the player. It rejoins the same floor, upstream of
the dock. Move decorations hosted on any split wall to
a valid remaining face. Preserve side-ward sightlines and cover. Neither return
opening may let a player enter the floor before `companion_released` raises
`ward_exit_shutter`.

The topology should make sense in the facility: a narrow maintenance bypass
around a dangerous stair landing and a service return around processing
machinery. The Union captives remain people in custody, not rewards. Sign and
light cues should distinguish the service route from the direct descent while
keeping the Crawler's sound cue readable.

## Build and verification

1. Establish current loaded-map reachability and first-person direct-route
   frames. Add the service route and prove grounded traversal, adequate headroom,
   and a rejoin at the antechamber. Confirm the solo Crawler stays on the
   intended first route and the `crawler_pack` trigger stays untouched by the
   bypass, including immediately after the first Crawler dies while the player
   stands at the fork, but fires on the direct route.
2. Open the side ward's northern return into the processing floor. Prove both
   directions with the loaded navigation graph and real movement. Ensure the
   main floor-to-dock path still works with the optional guards alive.
3. Prove from the initial world that the floor, side ward and dock remain
   unreachable before Latch's release. Prove the opened world, Continue reset,
   late observer geometry and durable-run content hash behavior.
4. Run controlled human and agent routes at Standard and Severe, including a
   direct stair clear and a bypass. Capture and inspect first-person frames at
   the fork, service rejoin and side-ward return. Test muted cue and sign
   readability. These are authoring checks; retain the unsteered player gate.
5. Run the repository gates, including Rust formatting, Clippy, tests,
   benchmark, unfiltered 90 percent coverage, release build, license check,
   Godot checker, mixed-agent playtests, roster, soak, published tour and CI.
   Record actual results and any unrun check.

## Acceptance and handoff

- The route split offers a meaningful risk/time choice after the first Crawler.
  A player can identify both directions without reading English, and neither
  route requires a jump or a client-only prop.
- The pack encounter remains readable and testable on the direct path. Its
  trigger does not activate simply because a player walks above the bypass.
- The side ward is a loop with two useful approaches. A player can skip it and
  still depart, or clear it and return to the floor without backtracking
  through the same doorway.
- The ward exit shutter remains the sole boundary into the processing floor.
  Retry, late join, local run carry and the current direct M02 tours still work.
- Record the new authored map hash, measured fight routes, inspected captures,
  CI and remaining fresh-player questions here before requesting integration.

## Open review

The exact service stair geometry needs a live collision and encounter-trigger
probe. If a safe bypass cannot fit beside the current stair core while preserving
the solo Crawler lesson, revise the fork position in this plan before widening
the map. The treatment's armored checkpoint has no authored encounter yet; this
route slice does not invent one.
