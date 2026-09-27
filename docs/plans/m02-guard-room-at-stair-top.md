# M02 guard room at the stair top

**Status:** implemented locally, 2026-09-27. Stacked on the implemented
[Shotgun introduction](m02-shotgun-introduction.md) until its draft PR lands.

## Goal and reason

Make the first M02 fight follow the accepted level design: the player sees and
collects the Shotgun on the upper gallery, enters a small guard room with two
seated Clerks and weapons down, then descends the service stair. The baseline
graybox taught the gun after the descent, which put the future Crawler lesson
before the gun it is meant to reward. This change establishes the correct
route and a visible, readable opening posture before adding that enemy.

## Scope

- Move the guaranteed Shotgun, Shells, guard-room trigger, two Clerks and
  table to the top of the existing service stair. Keep the lower landing and
  ward route usable. The stair remains the next route segment.
- Author an optional seated opening posture for Clerks. The server sends it
  while dormant and clears it when their encounter wakes or one is hit. The
  client validates and renders it through the existing enemy atlas; no name or
  map-id special case chooses a pose.
- Prove both roles claim the gun before the encounter, both Clerks begin
  seated, the first two defeats are theirs, the ward waits, the full route
  departs, and a wipe restores the opening posture and supplies.
- Capture and inspect the actual upper-room, combat and stair sequence in
  Godot. Update the level brief, map guide, protocol and roadmap together.

## Architecture and wire

`server/maps/m02-persons-unknown.json` owns placement. Its optional `seated`
field is valid only for a Clerk. `server/src/encounters.rs` owns dormancy and
activation, and `encounters/enemy.rs` owns the transition from seated to
standing. `CampaignActor::Union` adds an optional `seated: true` only while
that posture is visible. This is gameplay capability 15, required by M02;
earlier campaign and arena contracts stay valid. `actor_state.gd` validates
the optional field and `enemy_animation.gd` selects a baked seated Clerk pose.
The seated body still uses the normal fighter hit cylinder; the chair and pose
keep its head inside that cylinder. A future Crawler needs its own low
collision and leap behavior, not this posture flag.

Capability 14 is being implemented for capture the flag on a separate branch.
This branch must be integrated with that contract before a capability-15 build
is released. A version 15 hello must understand every earlier shipped field.

## Boundaries and spend

The Crawler, Latch, sealed ward fight, M01 run carry, optional loop and final
fresh-player acceptance remain separate work. This change does not claim M02
is finished. It uses the in-repo character baker and requires no paid asset
call or cloud resource. External spend: $0.

## Verification and success

Run focused authored-map and route tests, then workspace format, Clippy,
tests, unfiltered coverage at or above 90 percent, release build and the
affected Godot harnesses. Run the M02 and general visual tours, inspect the
upper room, seating, combat and descent, and keep screenshots current. Check
map navigation after every new solid. The result passes when no first-fight
enemy or Shotgun pickup remains below the stair, the route works across seeds
and roles, the seated cue is rendered before activation and clears on wake,
and retry restores it. Treat accurate-aim clears as authoring evidence only.

## Progress

- 2026-09-27: Compared the accepted level 2 brief against the current map,
  encounter lifecycle, gameplay capability and atlas baker. The current
  guard-room fight sits below the service stair. The existing gallery deck
  can hold the fight before the stair without a second route or a new game
  system. Baseline branch is draft PR #268, with all six CI jobs green.
- 2026-09-27: Moved the Shotgun, Shells and guard encounter above the stair,
  added a table and two chairs, and shifted one spawn clear
  of the new room. Four seeded M02 route tests pass for human and agent
  participants, including wipe retry and restored seated posture. The
  development child rejects an older spectator and admits capability 15.
- 2026-09-27: Baked all four atlases from source with Godot 4.7.2 and saw
  `character_bake: PASS`. The first ten-state live M02 tour reached the dock,
  but review found that the gun auto-claimed at spawn and the room's solid
  table hid the seated pose. Moved the pickup into view beyond claim radius,
  moved Shells onto the approach, narrowed the wake trigger and changed the
  table to a slab with legs. The authored reachability check rejected taller
  colliding chair seats and a records cabinet, so both were left out. The
  seated rig now sits at the existing chair height. The eleven-state tour
  passed and its Shotgun, seated room and stair frames were inspected. The
  table now exposes the guards' lower bodies, but this remains a graybox cue,
  not a final presentation pass. See the [prototype captures](../screenshots/prototypes/README.md).
- 2026-09-27: Rebased the free-body bake manifest after the shared rig change.
  Final Rust workspace tests, formatting, Clippy, dependency policy and
  unfiltered coverage pass; coverage is 93.59 percent against the 90 percent
  floor. The release workspace build and deterministic 16-bot benchmark pass.
  Godot checks pass, including the M02 local-launch and mission harnesses. The
  asserted eleven-state M02 tour passes and its three saved stills were
  inspected. Four arena playtests and the six-map 2/6/6/8/12/16 roster matrix
  pass. Map 4 recorded one later spawn death and zero opening spawn deaths;
  the other roster runs recorded none. The rotating-map soak passes. The
  general 32-state tour passes and republishes its stills. Its contact sheet
  and the README's boot, multiplayer and watched-match frames were inspected.
  The README now uses the captured chase view, which shows the watched fight.

| Soak environment | Load | Duration and samples | Tick result | Lifetime p99 tick | Peak RSS | Evidence |
|---|---|---|---|---|---|---|
| Windows x86_64, release server | 4 bots, 4 agents, 2 spectators, map rotation | 120 s, 9 samples | 2,400 ticks at 20.00 Hz | 0.52 ms | 38.8 MiB | `.agents/soak/m02-final.ndjson` |

This is a local host measurement, not a remote-network or cloud capacity claim.

## Next work

- Review this stacked change after the Shotgun introduction PR. Integrate the
  separate capture-the-flag capability 14 branch before releasing a
  capability-15 build, then rerun the combined protocol and client checks.
- Build the Crawler descent and readable guard reaction, then Latch and M01 run
  carry. Keep M02 in development until the accepted opening view, gameplay
  route, retry and fresh-player gates pass.
- No paid asset call or cloud resource was used for this slice. External spend
  remains $0.
