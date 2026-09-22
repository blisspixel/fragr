# Recall Notice: complete mission

Status: in flight, 2026-09-22. [Task #195](https://github.com/blisspixel/fragr/issues/195).
The active slice is the [full build order](../ROADMAP.md#full-build-order-2026-09-22). Routes, the balcony view of the lift, departure copy, the leave warning, and the published room stills shipped through v0.40.0. The objective card leaves after the introduction. The bypass is its own fight. The east route leaves all four file-stack guards alive. Secrets, disk saves, final art, and the fresh-player review stay open. The next rung is two readable enemies.
Baseline: v0.28.0, `e845236`. Its tree matches the final revision of #193, with all
five integration jobs passing. The three-enemy prototype is not a full mission.
Spend: local work first; the uncertain Clerk reference reservation remains held.

## Player outcome

Follow Latch's recall through a recognizable intake institution, recover weapons,
learn human guard and bot tells, choose a useful route through records, win a
mixed-threat fight at transfer control and leave with the correction destination.
M02 performs the rescue. No early Inheritance contact, mandatory radio, boss,
explosives or arbitrary extra key hunt. The institution's treatment of personal
lives as property supplies the environmental story. Suffering is not the joke.

Keep the approved introduction and safe Tack lesson. The current rooms support
the introduction, but the empty records/transfer half cannot carry the mission.
Build inhabited rooms and purposeful encounters, not a larger open arena.
The revised 8-10 minute and 20-30 enemy estimates are pacing hypotheses, not quotas.

## Room and encounter staging

```mermaid
flowchart LR
  A[Service frontage] --> B[Confiscation]
  B --> C[Intake hall and public stair]
  B --> E[Maintenance stair]
  C --> D[Records balcony]
  E --> D
  D --> R[Records reception]
  R --> S[File stacks]
  R --> P[Service bypass]
  S --> T[Sorting and dispatch]
  P --> T
  T --> F[Transfer control]
  F --> G[Custody lift]
```

- Frontage/confiscation/intake retain the first Clerk and pair of Sweepers. A
  retreat stays legible and neither stair requires jumping.
- Records reception is a smaller threshold beyond the balcony. Its counter and
  cabinets break incoming lanes before a new patrol reaches the player. The
  public and service approaches converge without bypassing safe weapon discovery.
- File stacks offer short aisles, cross-connections and a readable exit toward
  sorting. Their optional supplies justify entering; the bypass is a real choice,
  not a dead corridor. Avoid placing a new enemy in a visible region at activation.
- The service bypass trades the wider stacks' cover and supplies for a tighter
  approach. Both routes reach sorting from different angles and reconnect.
- Sorting combines the two taught threats across cover and distinct approaches.
  The next destination remains visible. Place a quiet record/evidence beat between
  fights; no exposition overlay while attacks continue.
- Transfer control provides the final crest, then the physical record and lift.
  Preserve Latch's destination, actual gate collision and shared boarding. No new
  mandatory wave after the earned exit.

Extend the existing north/west records footprint with real floors, walls and
ceilings. Preserve landmarks and original space identities where they remain
accurate. New collision, navigation and presentation derive from the same JSON.
Use registered Union materials and localized signs with practical lighting;
compare rooms in the rendered route, including distant enemy contrast.

## Equipment and retry

Encounter bodies must exist before players enter their sightlines. Prepare the
bounded authored roster when the first active party starts; entry regions wake
the existing guards rather than materializing new bodies. Preserve normal
dependency sequencing, but a directly attacked group must respond even if its
entry alarm has not fired. Dormant actors keep ordinary damage and corpse rules.
Prove stable identity, input inactivity before activation, attack response and
party reset, including split parties entering different routes.

Found introductory guns remain available to every participant. Shared campaign
consumables must be finite within a run; unlimited waiting beside an ammo pad
cannot replace the planned supply economy. Preserve arcade pad respawns. Keep
scarcity, pickup visibility and claims server-owned. Guarantee enough supply for
the main route plus misses. Preserve existing mixed-client supply regressions;
four-player campaign authoring is no longer a requirement for every level.

Replace timed solo campaign respawns with a limited-continue run. Death offers a
mission-start retry while allowance remains; death without allowance ends the run. Three
continues across the campaign is the initial balance proposal. Restore entry
equipment, health/armor, pickups, enemies, objectives and gates coherently, without
replaying the opening. No records checkpoint, teammate revival or buddy system.
Arcade respawns and existing multiplayer regressions remain unchanged.

Use one authoritative retry owner, integrating the existing encounter lifecycle.
Consume a continue exactly once; reject duplicate or stale retry requests. A
mission restart cannot duplicate rewards or erase earlier mission outcomes.
Define the explicit solo-run boundary before changing the current four-seat
development host, rather than silently changing its wire behavior.

Persistent saves require a versioned bounded format, content identity, validation,
atomic replacement and an explicit run identity. Save remaining continues without
refilling them on reload. Do not serialize arbitrary live state or claim
persistence from an in-memory mission-entry snapshot. Define
this boundary before implementation; no player-supplied filesystem paths.

## Architecture

`server/maps/m01-recall-notice.json` remains canonical. Reuse authored-map
validation, `encounters.rs`, `mission.rs`, `inventory.rs`, shared movement,
navigation and combat. Keep new run/continue concerns in a focused module when
needed. No parallel map loader, pathfinder, inventory or client authority.
Use existing typed wire state for compatible changes; revise capability and both
consumer boundaries deliberately if a new contract is necessary.

The provisional Clerk/Sweeper rigs remain the local art source. Final reference,
silhouette, pose and fresh-player encounter acceptance are tracked in #180.
Do not replace the unresolved paid reference with a duplicate request. Check
current price and quota before any approved batch; no overages or top-ups.

## Completion evidence

- [ ] Complete room sequence, both routes, optional rewards and a mixed crest.
- [ ] Measured guaranteed-route supplies, misses, contention and recovery.
- [ ] Mission-start retry, exactly-once continue use, run exhaustion and explicit save status.
- [ ] Solo runs with human/agent control, MCP and spectator eyes; retain existing
  mixed-client regressions without claiming a complete co-op campaign.
- [ ] Deterministic loader, activation, sightline, movement and lifecycle checks.
- [ ] Inspected full-route motion, enemy tells/deaths and effects on available
  OpenGL/Vulkan paths, with hardware and platform limits recorded.
- [ ] Fresh-player route/story comprehension and fun review without steering.
- [ ] Strict Rust, coverage, Godot, verifier, all-map regressions and measured
  CPU checks; current public gallery; exact-revision integration CI.
- [ ] Current mission, framework, roadmap, protocol, asset and release records.

Green checks cannot establish fun, final art or a complete campaign. Record
failed runs and fixes, update the evidence here, and leave unfinished gates open.

## Local implementation checkpoint, 2026-09-20

The working draft expands the records wing with reception, stacks, bypass,
sorting and dispatch. Seven groups contain twenty guards. Campaign consumables
stay consumed until party reset; arcade supplies retain their timers. Enemy
bodies are prepared before entry, and hit/region alarms retain their identities.
The records-wing increment is implemented in
[#196](https://github.com/blisspixel/fragr/pull/196), which tracks integration and
release evidence. The complete-mission task remains open.

Normal-input simulation clears both routes for human and agent control. Current
screened-layout results use ordinary movement and accurately aimed shots, with
normal spread and finite supplies:

| Control and route | Ticks at 20 Hz | Shots | Guards defeated | Final HP |
|---|---:|---:|---:|---:|
| Human, public stairs/stacks | 1923 | 125 | 20 | 100 |
| Agent, public stairs/stacks | 1923 | 125 | 20 | 100 |
| Human, maintenance/bypass | 2041 | 157 | 20 | 100 |
| Agent, maintenance/bypass | 2041 | 157 | 20 | 100 |

Evidence: `.agents/m01-screened-sim.log`. This is not fresh-player duration or
difficulty acceptance. Earlier two- and four-participant objective runs
reach the shared lift, with three and four individual deaths respectively in
the recorded run. Supply contention and recovery still need tuning. The expanded
mission completion bound is separate from the small gate fixture's bound.

Strict Clippy passes locally. A regression now proves that a struck sentry's
hidden peers investigate the hit location and receive one later entry dispatch
without learning an unseen player's live position. Sightline tests screen future
guards from both stair approaches and transfer guards from dispatch. The full
workspace rerun caught an overbroad intake-count assertion, now replaced with
specific intake identities, and a two-second readiness-wire timeout. The latter
passes alone and in the subsequent complete workspace run without changes.
That run passes 709 tests with two existing ignored stress cases
(`.agents/m01-completion-workspace-tests-4.log`). Formatting and dependency
license/source/ban checks also pass. Unfiltered workspace line coverage is
95.80 percent on the final local run against the unchanged 90 percent floor;
release compilation passes.
Rendered attempts in `.agents/qa/m01-records-populated*` failed on furniture
waypoints, then on an attack-before-entry alarm that left guards waiting and
caused later deaths. These are failed evidence, not accepted captures. The alarm
fix now has a hidden-peer regression; subsequent rendered failures also exposed
cross-room kill accounting, unanswered attacks during scripted travel and the
driver's inability to aim at an exposed body above a low counter. Failed evidence
is retained in `.agents/qa/m01-records-{alarm,named,travel,screened}`. Later
`exposed` and `nearby` runs stayed alive but exposed a controller timing error:
intentional stationary fighting consumed the walking deadline. Opt-in travel
now has separate 15-second movement and 25-second combat limits per waypoint,
records both durations, and ignores distant targets until they are approached.
Required named guards, movement arrival and no-death assertions remain intact.

The subsequent `.agents/qa/m01-records-bounded` OpenGL run passes all 14 states,
confirms all twenty named guards, recovers the transfer record and completes
departure without a participant death. Both walking and combat time remain
recorded per waypoint. The contact sheet and full reception/stacks stills were
inspected on Windows, AMD Radeon 780M. Connected interiors and cover are visible;
repetitive surface treatment, provisional characters and weak room-specific
visual identity remain art work. This accurate controller run is not human
difficulty or final pacing acceptance.

The Vulkan run (`.agents/qa/m01-records-vulkan`) also passes all fourteen states,
twenty guards and departure without death. Its contact sheet was inspected on
the same AMD host. The five-state attack-tell tour deliberately observes both
enemy types firing before returning fire; its motion sheets show the Clerk's
shot, bot bursts, hit reactions and collapses. These are renderer checks on one
Windows GPU, not certification of other vendors or platforms.

The visual combat helper tracks named deaths across rooms and corpse cleanup,
detects omitted respawning participants, fights during opt-in travel and can aim
at exposed parts of the real body without firing through solid cover. Failed
full-route states end the run after saving evidence. The records tour covers the
expanded route. A malformed single waypoint stopped the maintenance tour;
checking every bundled manifest caught the same defect in two other focused
tours. Their data is corrected, and launch now rejects invalid walking shapes
before playing. The five-state maintenance, eight-state stair and nine-state
facility tours pass with inspected contact sheets under
`.agents/qa/{m01-maintenance,m01,m01-facility}-records-fixed/`.
At that increment, limited continues, persistent saves, secrets, final art and
fresh-player acceptance remained open. The subsequent
[solo recovery increment](campaign-continues.md) implements three explicit
mission-start continues, entry restoration and exhaustion with real-client and
complete-route evidence. Disk saves, supply balance, secrets, final art and
fresh-player review remain. [Player records](benchmark-and-stats.md) are tracked
in #199; earned cosmetics remain under #197.

The 21-state release gallery and shot/impact strips were regenerated, inspected
and published from `.agents/qa/m01-records-gallery`. All 27 headless Godot
harnesses and eight verifier fault scenarios pass. The four-agent smoke passes
with seven frags and no spawn deaths. The six-map roster also passes unchanged
assertions, mixing reflex and planner agents with a spectator. Rust wire tests
separately exercise human and agent roles in shared campaign sessions.

| Arena map | Seed | Fighters | Frags | Spawn deaths |
|---|---:|---:|---:|---:|
| 1 | 67 | 2 | 6 | 0 |
| 2 | 42 | 6 | 28 | 0 |
| 3 | 19 | 6 | 21 | 3 |
| 4 | 42 | 8 | 39 | 3 |
| 5 | 42 | 12 | 35 | 2 |
| 6 | 42 | 16 | 55 | 3 |

Reports: `.agents/playtest/m01-completion-roster/`. Passing thresholds does not
erase the remaining spawn deaths or establish finished arena balance.

CPU benchmark, Ryzen 7 7840U, Windows x86_64 release, session plus JSON encoding:

| Map | Rule bots | Ticks | Seed | p99 tick ms | Maximum tick ms | Repeated trace |
|---|---:|---:|---:|---:|---:|---|
| Arena Duel | 16 | 1,200 | 42 | 0.623 | 1.143 | Identical |

Report: `.agents/m01-completion-bench16.json`. The unchanged budget assertions
pass. This CPU sample does not measure network capacity or rendering performance.

The first integration revision passed all five jobs. The later waypoint-check
revision exposed a coverage-only adapter timing failure, retained in
`.agents/m01-records-ci-failure.log`: its continuous-snapshot fixture started the
two-second cadence deadline before the controller had prepared navigation.
Preparation uses a blocking worker and a shared construction cache, so concurrent
map loads could consume that window. The fixture now confirms an initial valid
action, then requires three more actions under the same 200 Hz snapshot stream
and two-second deadline. Its existing four-second overall bound and malformed
replacement rejection remain. This distinguishes setup from action starvation;
it does not establish a faster topology builder. Final integration is tracked
on #196.

The corrected fixture passes the full workspace coverage run. A deliberate
temporary mutation resetting the action timer on every snapshot fails with the
expected starvation assertion. The original source was restored byte-for-byte
and passes again. Receipts: `.agents/adapter-action-clock-{mutation,restored}.log`
and `.agents/m01-completion-coverage-final.log`. No deadline or threshold changed.

The map uses a reception privacy partition and a narrower transfer entry to
separate later threats from earlier approaches. All collision, navigation and
rendering still derive from the same authored solids. The loader caught unusable
clearances during iteration; those were widened, not exempted from validation.
Shared kit practice and distinct enemy combinations are recorded in
`../MAP-DESIGN.md` and `../ENEMIES.md`. Requested difficulty tiers and achievement
cosmetics are bounded in [difficulty and rewards](difficulty-and-rewards.md).
That follow-up implements new-run timing profiles first; persistence and earned
rewards remain planned. The records-wing evidence above predates that increment
and uses the original Standard timing.

Reviewed [character references](../../client/art/characters/references/README.md)
are saved with hashes and receipts. The Clerk dashboard preview was recovered
without resubmission; its original and API polling identity remain unavailable.
The separate Sweeper original was recovered using its saved request ID. Dashboard
charges total $0.184769, against two $0.107 estimates; billing showed $14.51
remaining with top-up off. Both backgrounds are opaque checkerboards. These are
reference candidates, not production sprites. Godot loaded both successfully.

## Bypass miss budget, 2026-09-21

`bypass_clear_still_departs_after_wasted_rounds_without_stack_supplies` takes the
maintenance approach, fires one Flechette magazine (30 rounds) into the bypass
ceiling, and still departs. Every wasted round is a solid impact from inside
`bypass_watch`. `stacks_darts`, `stacks_armor`, and `stacks_medkit` stay
available. Seed 67, human control. The test stays east of the file stacks. After the sightline screens below,
the same command measured:

| Ticks | HP | Armor | Defeats | Shots | Wasted | Darts magazine | Darts reserve |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1698 | 100 | 10 | 16 | 116 | 30 | 8 | 90 |

Command: `cargo test -p fragr-server --locked bypass_clear_still_departs_after_wasted_rounds_without_stack_supplies`.
`cargo fmt -p fragr-server` and `cargo clippy -p fragr-server --locked --all-targets -- -D warnings`
pass. This is a seeded miss budget, not a fresh-player gate or a finished
mission. The earlier 2090-tick, 20-defeat count walked the west side of
sorting and is not this route.

## East sightline, 2026-09-21

`east_bypass_departs_with_all_stack_guards_alive` takes the maintenance
approach, stays east of the file stacks, departs, and never sees or kills
`stacks_clerk`, `archive_clerk`, `stacks_sweeper`, or `archive_sweeper`.
`stacks_darts`, `stacks_armor`, and `stacks_medkit` stay available. Seed 67,
human control.

| Ticks | HP | Armor | Defeats | Shots |
|---:|---:|---:|---:|---:|
| 1639 | 80 | 0 | 16 | 101 |

The records approach around (-18.5, 10.7) was shooting `stacks_sweeper`
through the stacks doorway. `files_a_return` closes that lane and leaves the
cross-aisle at z=23.5 walkable. Closing only that lane made the same approach
die at the reception threshold after eight defeats, because the walker no
longer paused there and instead cleared sorting through the open bypass.
`reception_counter_screen` blocks that threshold gallery. `bypass_north_screen`
hides `dispatch_clerk_east` from the bypass mouth so the ceiling-waste stand
is not flanked. `stacks_north_screen` hides `archive_sweeper` from east
sorting. A wider stacks screen, out to x=-37.1, made `stacks_cross_aisle`
unreachable and was not kept. Moving `stacks_sweeper` onto the nearby cabinet
remains rejected for the same eight-defeat death.

`m01_main_and_maintenance_approaches_clear_with_discovered_equipment` and
`later_guards_are_screened_from_the_previous_encounter_approach` still pass.
The maintenance route that also walks west sorting still defeats the stack
guards. That is not the east proof. This is a seeded sightline, not a
fresh-player gate or a finished mission. Tour stills were not regenerated.

## Balcony sightline, 2026-09-21

`office_front_sill` replaces the full seal in the opening between the records
deck and transfer control. The sill runs from y=3 to y=5. The header still
starts at y=6.5, which leaves the view the level plan reserved. The solid stays
inside the old seal, so it does not add a new walking obstacle.

`records_balcony_sees_the_lift_sign_but_not_the_transfer_guards` loads the
authored map. Feet (-4, 3, 9) stand on the records deck and see the lift sign.
The route from `records_balcony` to that stand stays on the deck. The route
onward to `records_reception` does not enter the transfer office. A half-metre
grid of standing deck positions has no line of sight to `transfer_clerk`,
`transfer_sweeper_west`, or `transfer_sweeper_east` at 0.2, half height, or
full height.

The three kept route proofs pass on this geometry.
`east_bypass_departs_with_all_stack_guards_alive` matches the east sightline
above: 1639 ticks, 80 hp, 0 armor, 16 defeats, 101 shots. Both
discovered-equipment approaches still depart, and agent control matches human
control:

| Approach | Ticks | HP | Defeats | Shots |
|---|---:|---:|---:|---:|
| Public stairs | 1765 | 100 | 19 | 92 |
| Maintenance | 1833 | 100 | 20 | 117 |

`m01_routes_use_ordinary_actions_through_the_live_session` also passes. Commands:
`cargo test -p fragr-server --locked --lib records_balcony_sees_the_lift_sign_but_not_the_transfer_guards`,
then the same runner for `m01_routes_use_ordinary_actions_through_the_live_session`,
`east_bypass_departs_with_all_stack_guards_alive`, and
`m01_main_and_maintenance_approaches_clear_with_discovered_equipment`. This is a
seeded sightline, not a fresh-player gate or a finished mission. Route stills
were not regenerated.

## Honest end of run, 2026-09-21

`MISSION_DEPARTED` states the correction ward and that this mission ends
here. It does not say the prototype is complete or that the next mission is
in development. The boot menu still carries the development-mission label.
`PauseMenu.local_campaign` is set only when `GameManager` boots in campaign
mode. That menu says leaving abandons the run and does not refill continues.
Every other match keeps the live-match note.

`test_mission.gd` and `test_frontend.gd` passed headless on Godot 4.7.2.
Room materials and inspected balcony stills remain open on this rung.

## Registered room floors, 2026-09-21

Reception stays bone enamel over green records tile. The file-stack walls
are service steel on that same tile. Sorting stands on concrete. Dispatch
stands on service steel. The lift face stays the lift panel. No solid moved.
`recall_notice_rooms_do_not_share_one_floor` passes with the route and
reachability tests. Inspected stills are still required before calling the
rooms visually accepted.
