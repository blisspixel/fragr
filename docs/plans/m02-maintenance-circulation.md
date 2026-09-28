# M02 maintenance circulation

**Status:** implemented in [draft #277](https://github.com/blisspixel/fragr/pull/277),
2026-09-27. This follows the [optional side ward](m02-side-ward.md) in draft
#276 and belongs to the accepted [Persons Unknown brief](../campaign/m02-persons-unknown.md).
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
world and navigation; no client-only collision. The fork begins near the lower
switchback after `crawler_first` (x -12, z -27). Shortening the old screen
opens a grounded west passage around the pack landing; an offset screen marks
its north edge. The revised direct-lane trigger spans x -13.5 to -11.8,
z -26 to -22.5, y 0 to 3. A second trigger strip spans the west landing
approach at x -18.5 to -14, z -28 to -27.2, y 0 to 3. It closes a gap that
would let a player walk or jump into the pack without waking it. The bypass
passes north of that strip
and rejoins the antechamber near x -14, z -22. Loaded navigation, live body
integration into the landing with and without a jump, and a first-person bypass
with an idle-pack
assertion verify both boundaries. The direct landing stays readable as the
main fight route. Do not hide the service choice behind an unmarked wall.

The side-ward loop uses a roughly three-metre ground-level opening in the
floor's east wall near the conveyor, north of the existing side-ward entrance.
The width leaves a usable centerline between the pawn radius and side-ward
cover for Latch as well as the player. It rejoins the same floor, upstream of
the dock. Move decorations hosted on any split wall to a valid remaining face.
Preserve side-ward sightlines and cover. Neither return
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
  trigger does not activate when a player uses the grounded bypass.
- The side ward is a loop with two useful approaches. A player can skip it and
  still depart, or clear it and return to the floor without backtracking
  through the same doorway.
- The ward exit shutter remains the sole boundary into the processing floor.
  Retry, late join, local run carry and the current direct M02 tours still work.
- Record the new authored map hash, measured fight routes, inspected captures,
  CI and remaining fresh-player questions here before requesting integration.

The revised authored map SHA-256 is
`79e1922314f078cd5524ab030ddd677c35f05a23860f3ab3002fc6af8b1b015f`.
Older saved M02 map bytes require New Run and remain archived by the existing
content-hash migration path.

## Rendered review

The Standard first-person maintenance tour completed 25 of 25 states with
ordinary movement and combat, checked all four pack actors were still idle
after the cut and ward fight, then departed. The direct-route side-ward tour
completed 24 of 24 states after its old waypoints were corrected for the new
geometry. The 17-state Latch motion tour passed on the direct route, including
its sampled companion escape. The regular published tour completed 32 of 32
states. Full-resolution frames were inspected on Godot 4.7.2-stable, OpenGL,
AMD Radeon 780M:

- [Service fork](../screenshots/m02_maintenance_fork.png): the player can choose
  the open service cut or approach the visible pack landing after the first
  Crawler. This frame does not show whether the pack has activated; the live
  encounter test establishes that fact.
- [Antechamber rejoin](../screenshots/m02_maintenance_rejoin.png): the bypass
  returns to the normal ward approach without a jump.
- [Northern side-ward return](../screenshots/m02_side_ward_north_return.png):
  the second opening leads back onto the processing floor, past machinery.

The route and room remain graybox. The scripted tour proves traversal and
state order, not fresh-player discovery or fight balance.

One rerun reset during Latch's handoff because the tour's general combat probe
selected a dormant pack actor while clearing the ward, which woke the skipped
encounter. The maintenance tour now restricts that stage to its three named
ward guards and checks that the pack stays idle afterward. This constrains the
evidence run to the intended service route; a player can still choose to wake
the pack by shooting into it.

## Verification record

- `cargo fmt --all -- --check`, workspace Clippy with warnings denied,
  `cargo test --workspace --locked`, the release build, `cargo deny check
  licenses bans sources`, and the deterministic 16-bot benchmark passed.
- Unfiltered workspace line coverage passed the 90 percent floor at 93.79
  percent after the jump-height correction. The focused M02 tests passed 47
  of 47, including walking and jumping through the new strip. Full workspace
  tests passed under coverage after that change.
- Four named mixed-agent playtests and the six-map 2/6/6/8/12/16 roster sweep
  passed. These arena checks do not establish M02 fight balance.
- `tools/godot_check.sh` and `tools/test_godot_check.sh` passed after the
  tour's new idle-pack assertion. The 120-second rotating-map soak passed:
  20.00 Hz, 0.59 ms lifetime p99 tick time, 38.8 MiB peak resident memory,
  and nine healthy samples with four agents, four bots and two spectators.
  This local arena soak is not a cloud-host or M02 capacity claim. PR CI remains.
- No external API or cloud charge was made. This slice spent $0.
- The final base-main CI run `36360807672` passed all six jobs on head
  `2f13df5`. Release packaging run `36360807677` passed on that head too.

## Open review

The loaded route, live encounter-state probe and scripted first-person walk
pass for the ground passage. Unsteered play still needs to prove the fork's
readability and the Crawler lesson. If those fail, revise the fork before
widening the map. The treatment's armored checkpoint has no authored encounter;
this route slice does not invent one.
