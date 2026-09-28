# M02 processing-floor roster and pacing

**Status:** planned, 2026-09-27. Follows the [optional captive evacuation draft](m02-side-ward-evacuation.md). This is a bounded encounter pass, not a claim that M02 is finished.

## Goal and reason

The [accepted M02 brief](../campaign/m02-persons-unknown.md) calls for four Sweepers, four Clerks and a final Crawler pair on the two-level processing floor. The bundled map currently fields two Clerks and two Sweepers there. The measured gantry route already leaves a scripted Severe player at 35 HP with ordinary supplies. Add the missing six enemies in readable stages, preserve the officer's upper priority position, and measure both difficulty routes before accepting the fight.

The player should recognize one fight crest with space to move and Latch helping, rather than ten dormant bodies waking in one instant. The floor's last clear remains the trigger for `dock_watch` and for the optional side-ward captives' departure. Never count the side-ward or dock guards as part of the ten.

## Scope and non-goals

- Author exactly four floor Clerks, four floor Sweepers and two final Crawlers. Reuse the existing kinds, movement, attacks, telegraphs, cover and strict authored-map schema.
- Stage the floor roster with bounded authored encounters. Preserve `floor_crew` as the final completion fact consumed by `dock_watch`, M02 evacuation and existing assertions. Earlier floor waves use their own encounter IDs and one-way `after` dependencies.
- Keep `side_ward_guards`, `dock_watch`, optional evacuation, Latch autonomy, M01 inventory carry, solo departure and Continue rules intact. No new objective, wire type, client authority or difficulty-exclusive encounter.
- Do not add the Jammer, a Notary fight, Mara's warning, a required captive rescue, a weapon or a new enemy kind. Those belong to later levels or separate passes.
- Visual finish, full cutscenes, dialogue and a fresh-player acceptance result are outside this slice.

## Architecture and authoring decisions

Use the existing `server/maps/m02-persons-unknown.json` encounter list and the server's authored `after` chain. Prepare three floor stages with a rising local threat: the upper officer and entry pressure, a machinery-crossing response, then the final two Crawlers with remaining support. Choose each trigger region from the grounded player route and the maintenance return. A player who clears from the gantry or side approach must still trigger the next stage on an ordinary path. No enemy may wake behind a closed shutter or block the only reachable way to the dock.

Validate every new feet position, support, route and sightline against the loaded map. The one-to-many encounter parser already bounds groups and validates earlier dependencies. Reuse it rather than adding a wave engine or a second mode-specific spawn system. Keep each group small enough that the published `floor_crew` completion means all ten floor enemies are defeated. If the strict `after` chain cannot meet the clear and replay gates without awkward trigger camping, revise the authored staging in this plan before changing the engine.

The optional captives begin their server-owned route only when `floor_crew` is complete. They wait before the live dock encounter, and the player can depart without their arrival. New floor waves must not alter those rules. Latch may assist but must never be required for an enemy kill, a route or mission departure.

## Build and verification

1. Record the current Standard and Severe scripted floor metrics from the preceding branch: health and armor at entry and exit, ordinary medkit claims, ammunition and shots, clear ticks, Latch damage and kills, and player route. Use the gantry plan's 35 HP Severe result as a prior observation, not a guaranteed baseline for a different route.
2. Add the three stages and six enemies. Extend authored-map tests to assert exact roster, officer elevation, grounded feet, ordered dependencies, reachable entry regions, and unchanged side-ward and dock rosters. Update the shared `ENEMIES` count from 18 to 24 only when the loaded map proves it.
3. Extend seeded live tests for both human and agent solo routes, Standard and Severe ordinary-health clears, wipe and Continue, Latch support without softlock, a direct dock departure, and the optional captive route after full floor clear. Include a failure path where the last stage has not cleared and neither dock activation nor captive evacuation may begin.
4. Run the first-person Standard and Severe tours through actual input and inspect enemy poses, cover, the last pair's tell, HP, shots, path and screenshots. Tune placement and the existing ordinary health support from measured failures, without secretly changing difficulty damage or adding an unearned pickup.
5. Run the full repository gates: Rust format, Clippy, tests, unfiltered 90 percent coverage, release benchmark, release build, deny, named playtests, six-map mixed roster, 120-second soak, Godot checks, published general tour and PR CI. Record the measurements and any unresolved fresh-player questions here.

## Acceptance and spend

- The bundled map fields the accepted ten floor enemies in readable stages. The two final Crawlers are heard or seen before their committed attack. A player can use both the main and maintenance approaches without a hidden trigger gap.
- Standard and Severe scripted clears survive with ordinary supplies and no secret claims. Record health, shots, time, Latch contribution and threat order for both. A scripted accurate-aim clear is authoring evidence, not proof that a new player will find the fight fair.
- Floor completion still starts the optional captives and permits dock activation. Clearing only the first two stages does neither. A solo player can depart after the dock fight whether the side ward was visited or not.
- No paid API call, cloud apply or external charge is required. The authorized external build allowance remains capped at $20 combined within the repository's $50 total.

## Evidence and handoff

Not yet measured on this branch. Record exact commands, results, route tables, screenshots, failures, corrections, remaining review, and the next build step here before opening the PR.
