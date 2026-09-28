# M02 processing-floor roster and pacing

**Status:** implemented, 2026-09-27. Follows the [optional captive evacuation draft](m02-side-ward-evacuation.md). This is a bounded encounter pass, not a claim that M02 is finished.

## Goal and reason

The [accepted M02 brief](../campaign/m02-persons-unknown.md) calls for four Sweepers, four Clerks and a final Crawler pair on the two-level processing floor. Before this pass, the bundled map fielded two Clerks and two Sweepers there. The measured gantry route left a scripted Severe player at 35 HP with ordinary supplies. Add the missing six enemies in readable stages, preserve the officer's upper priority position, and measure both difficulty routes before accepting the fight.

The player should recognize one fight crest with space to move and Latch helping, rather than ten dormant bodies waking in one instant. The floor's last clear remains the trigger for `dock_watch` and for the optional side-ward captives' departure. Never count the side-ward or dock guards as part of the ten.

## Scope and non-goals

- Author exactly four floor Clerks, four floor Sweepers and two final Crawlers. Reuse the existing kinds, movement, attacks, telegraphs, cover and strict authored-map schema.
- Stage the floor roster with bounded authored encounters. Preserve `floor_crew` as the final completion fact consumed by `dock_watch`, M02 evacuation and existing assertions. Earlier floor waves use their own encounter IDs and one-way `after` dependencies.
- Keep `side_ward_guards`, `dock_watch`, optional evacuation, Latch autonomy, M01 inventory carry, solo departure and Continue rules intact. No new objective, wire type, client authority or difficulty-exclusive encounter.
- Do not add the Jammer, a Notary fight, Mara's warning, a required captive rescue, a weapon or a new enemy kind. Those belong to later levels or separate passes.
- Visual finish, full cutscenes, dialogue and a fresh-player acceptance result are outside this slice.

## Architecture and authoring decisions

Use the existing `server/maps/m02-persons-unknown.json` encounter list and the server's authored `after` chain. Prepare three floor stages with a rising local threat: the upper officer and entry pressure, a machinery-crossing response, then the final two Crawlers. Choose each trigger region from the grounded player route and the maintenance return. A player who clears from the gantry or side approach must still trigger the next stage on an ordinary path. No enemy may wake behind a closed shutter or block the only reachable way to the dock.

The `after` chain gates region activation, but dormant enemies already have bodies and can be damaged by a deliberate long shot. That hit may wake their group early. Treat these as soft spatial stages, not invulnerable scripted waves. Test ordinary main, gantry and side-return sightlines, early-hit behavior and full-clear accounting. If placement exposes an unfair early crossfire, move bodies behind real cover or adjust the authored approach before changing global combat rules.

The optional side-ward return now places a 35 HP medkit and 50 armor near the restrained civilians. These are ordinary contested pickups, reachable only by taking the branch. An initial Severe scripted attempt without them died at the return opening after 18 defeats. The same route with health alone still died after 19 defeats. Health plus armor gave a single-attempt clear, so both pickups are part of this encounter's present balance, not decoration. Their silhouettes and pickup affordance still need first-person review.

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

The current authored map has 24 enemies overall: 4 Clerks, 4 Sweepers and 2 Crawlers on the processing floor, plus 14 elsewhere. A map-load test checks the exact floor roster and group dependencies. A live synthetic test proves that a long shot can wake a later group without completing the floor or activating the dock. The optional side-ward test now clears all three floor stages and both dock guards before departing with the side ward untouched.

| Scripted accurate-aim route | Difficulty | One attempt | Defeats | End HP | End armor | Player shots | Enemy shots | Latch damage | Ticks |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Human and agent, optional room | Standard | yes | 24 | 100 | 0 | 125 | 54 | 120 | 1788 |
| Human, optional room | Severe | yes | 24 | 80 | 0 | 147 | 52 | 20 | 2036 |

These are deterministic authoring routes, not fresh-player clears. They include ordinary medkits and armor; neither uses a hidden claim, cheats, or a paid service. The route test now approaches distant enemies when its weapon has no line to fire and ignores post-shutter combat targets until Latch's release. That keeps the scripted driver aligned with the actual mission boundary.

`cargo fmt --all -- --check`, workspace Clippy with warnings denied, workspace tests (575 server library tests passed, 2 ignored), release workspace build, and `cargo deny check licenses bans sources` passed. The first M02 Standard first-person tour cleared all ten floor enemies but timed out on one dock guard. A second tour used an ordinary no-combat walk into the crossfire and died. A third advanced under combat control, killed two crossfire enemies, then failed its 25-second stage deadline and died. The fourth reverted to a cover-based fight, cleared the floor again and reached the dock, where a screenshot showed the tour forcing the Tack with zero ammunition while 22 Shotgun shells were stocked. The fifth uses the stocked Shotgun and passes all 29 first-person states: all three floor stages, the optional side ward, both captives at the dock, and departure. Four inspected stills are in [the roster capture](../screenshots/m02-floor-roster/README.md). The combat sheets show all three floor groups from a safe cover position but do not yet prove close-range readability of the final Crawler pair.

The remaining acceptance work is an unsteered player review of floor threat recognition, the final pair's cue and leap from ordinary distance, the side-ward return under pressure, and Standard and Severe balance without scripted aim. The present script can win from cover and the Rust Severe route can win through the optional branch, but neither result substitutes for that review. Keep M02 in development status.

The final local workspace coverage check passes at 94.58 percent of unfiltered lines. `tools/godot_check.sh` and `tools/test_godot_check.sh` pass, including the M02 harnesses and the checker failure cases. The deterministic release benchmark with 16 bots, 1200 ticks and seed 42 reports 0.623 ms p99 tick time, zero ticks over budget and trace hash `75d2234b3b3c6cad213e66e1791e7f92d4de37e1afee221403b4b033059bbb4e`. This is a Windows CPU benchmark, not a cloud capacity claim. All four named multiplayer smoke tests pass with no opening spawn death in those rounds. The six-map mixed roster passes its 2/6/6/8/12/16 client rounds across all maps, with zero spawn deaths. The 120-second soak passes at 20 Hz with four bots, four agents and two spectators: lifetime p99 tick time 0.56 ms, peak RSS 38.5 MiB, 50,517 outbound and 2,411 inbound bytes per client per second. The published general tour captured 32 states with a clean exit; its contact sheet was inspected, and unchanged Arena Duel stills were restored to avoid unrelated image churn. These are local measurements, not public capacity claims.
