# M02 side-ward evacuation

**Status:** planned, 2026-09-27. Follows the [maintenance circulation draft](m02-maintenance-circulation.md) and the [optional side ward](m02-side-ward.md). This is one bounded M02 slice, not a level-completion claim.

## Goal and reason

Make the two side-ward captives' escape an observed world fact. The current side-ward guard-clear fact opens their restraints and moves their figures about 1.5 metres. It proves they are free of the bays, not that they reached safety. After the processing floor and dock route are safe, they should visibly leave by the new northern return, pass the machinery and reach the loading exit. The server records `evacuated` only after both arrive.

This must remain optional. The player can depart without entering the side ward or waiting for a captive. M02's required order remains `ward_reached`, `companion_released`, `party_departed`. No escort failure, timer, revive, score gate or second Use action. Latch is an autonomous ally, not a controller for the two captives. The captives remain unnamed here; their later fate is not decided by this slice.

## Current facts and seams

- `server/src/mission/m02.rs` derives `side_ward_secured` from completion of `side_ward_guards`. `M02Progress` holds attempt-local mission state. `reset_mission` replaces that progress on Continue.
- `client/scripts/m02_ward.gd` reads that fact and animates local figures a short distance. Their positions are presentation only. A late observer sees the settled freed pose, with no route or evacuation result.
- The server already owns the release shutter and the floor path. Draft #277 adds the side ward's north return. The conveyor blocks a direct floor crossing; the existing first-person tour walks around its north side to the dock.
- `GameState` stops active mission simulation on departure or freeze. An early departure must leave `evacuated` false. The durable local run file is a mission-entry checkpoint, not a mid-mission captive save.
- The current `floor_crew` has two Clerks and two Sweepers. The accepted brief proposes four of each plus a last Crawler pair. Expand that roster in a separate measured slice after evacuation is stable.

## Design

### Server route and state

Keep the two captives outside `Player` and `CampaignActor`. They never take a fighter slot, damage, ammunition, pickups, bot intent, score or spectator camera target. A small M02 controller in `server/src/mission/m02.rs` owns two fixed, anonymous captive identities and their feet positions for the current attempt.

Use an explicit progression such as `held`, `freeing`, `ready`, `moving`, `waiting`, `evacuated`. Guard clear begins the same visible self-release. Once `floor_crew` is complete, move both along an authored route from their side-ward bays through the northern opening and around the conveyor. Hold at a safe floor approach while `dock_watch` is active. Resume toward the dock when that encounter clears; set `evacuated` only after both reach a tested safe region. If movement cannot complete, preserve the last valid positions and report the problem, rather than flip the fact on a timer. Never wait for this controller in `party_departed`.

Prepare and validate two grounded routes against the loaded map before readiness. Use the shared server movement and body clearance, not client-only waypoints or teleporting. Show that both can pass each opening without clipping each other, the conveyor, the raised shutter or the dock cover. Choose the dock safe region from the authored geometry and test it against the actual player and enemy routes. Avoid a route that makes the captives cross an active dock firing lane.

Project a fixed two-person `M02EvacuationState` through `M02ObjectiveState`: phase, two bounded feet positions and `evacuated`. The server simulates at 20 Hz, but publish moving positions at a bounded cadence, initially 5 Hz, and publish phase changes immediately. The client interpolates between validated samples. A late observer gets the current authoritative state and world geometry before presentation. A retry reconstructs the initial held figures, then the same server route may replay. Once departed, positions and result freeze.

### Wire and client

This changes the M02 mission state for every role. Allocate gameplay capability 21 after `SIDE_WARD_GAMEPLAY_VERSION` 20; require it for M02 development and durable sessions while leaving M01 and arena compatibility intact. Update the single version seam in `server/src/protocol.rs`, M02 admission in `server/src/run.rs`, local child negotiation in `server/src/local.rs`, and the Godot and adapter callers. `agent-adapter` already imports `GAMEPLAY_VERSION` from the server crate; its README currently says 19 and needs correction.

Validate exact two-person identity, finite and bounded coordinates, allowed phase transitions, attempt-local monotonic progress, and `evacuated` implying side-ward guard clear and physical arrival. Reject malformed or backward state in Rust and `client/scripts/mission_state.gd`. Update `docs/protocol.md`, adapter observation examples and both-side tests in the same change. Do not add a second campaign command to MCP; `mission_ready` and `mission_continue` remain the campaign door.

Replace the side figures' free-running escape pose with a presentation of the server positions. The self-release beat can keep its local animation only until the authoritative route begins, with a clear handoff and no snap. Show both figures moving from the side ward to the dock in first person. They should remain readable without voice or translated text. Do not imply evacuation while they stand in the bay or on the processing floor.

### Story and difficulty boundary

The accepted mission brief's difficulty-specific `Brief` paragraph lists freeing the side ward, clearing the gantry and stopping the pack. Those are proposed challenge ideas, not active required objectives. The side ward stays optional on Assisted, Standard and Severe. Keep the Jammer and warning to Mara in level 3, and the Notary's first fight in level 4. Do not assign the two captives names or a later appearance here.

## Build order

1. Add the prepared route and a server test that walks both captive profiles from bay to dock with the loaded M02 world. Reject an unreachable or obstructed authored route before mission readiness. Prove the release shutter still gates player entry.
2. Add attempt-local server state and tick movement. Test guard clear, floor-clear wait, dock wait, safe arrival, early player departure, freeze, Continue, and late join. No timer may stand in for arrival.
3. Add capability 21 and the strict wire shape. Update Rust protocol, Godot validators, local launch, adapter documentation and same-wire tests.
4. Present the server state in `m02_ward.gd`, then run headless Godot checks and inspect a recorded motion strip. Update the first-person M02 tour to observe both people leaving, waiting safely, arriving and the server fact. Keep an ordinary direct-departure tour that skips them.
5. Run the full repository gates, including the unfiltered 90 percent coverage floor, 16-bot benchmark, mixed-agent rosters, 120-second soak, published general tour and PR CI. Record measured route time, capture frames, map hash, failures and corrections in this plan.

## Success and open review

- A spectator who joins mid-route sees the same two server positions and phase as the player. Continue restores the restraints; an early departure retains no false evacuated result.
- The optional route can complete through ordinary movement without player escort or extra Use. Both captives visibly arrive before `evacuated` becomes true. The objective chain and dock departure work if they never leave the room.
- Standard and Severe scripted runs pass without moving the difficulty balance target. An unsteered player still needs to tell whether the captives escaped and whether the service route is understandable with voice muted.
- New asset API spend is $0 for this slice. No cloud apply or paid model call is needed. The current combined external build allowance remains at most $20 and the repository total cap remains $50.

The remaining floor roster is a separate [M02 brief](../campaign/m02-persons-unknown.md) and balance pass. Do not call M02 finished after this slice: it still needs the staged floor roster, authored visual finish and fresh-player acceptance.
