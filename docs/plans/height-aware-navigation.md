# Height-aware fighter navigation

Status: implemented and locally verified, 2026-09-19. GitHub integration pending.
Branch: `feat/height-aware-navigation`. Spend: $0.

## Integration follow-up

CI run 35478232410 failed the six-map wire matrix: Directive 17 seed 19 had a
planner stationary for 19 seconds at (17.7, 44.3); Reclamation Gulch seed 42 had
seven spawn deaths among 33 frags. Local passes did not establish reliability.
Reproduce the geometry and spawn conditions deterministically, retain the
existing thresholds, then repeat both cases and the complete matrix. Investigate
navigation recovery at the edge of a descended stair and exposure at otherwise
well-separated spawn positions. Do not conceal either problem with invulnerability
changes, weaker sampling, or another blind CI retry.

The local repeat also failed: map 3 stalled for 25.1 seconds at (44.3, 13.8),
and map 5 recorded six spawn deaths in 26 frags. Deterministic regressions now
cover both stair coordinates in all four quadrants through shared movement and
actual server players, plus a captured Gulch roster where an exposed widest gap
lost to an available covered compound. Navigation reuses movement's outward
escape rule but still rejects a start inside a solid. Spawns rank occupancy,
exposed chest/eye sightlines within the server hitscan cap, then clearance;
active-match joins use that same selector. Shield and frustration limits stay.

CI did not retain failed playtest JSON. Add narrowly scoped report/log artifacts
on failure as well as success, with seven-day retention. The official
[upload action](https://github.com/actions/upload-artifact) release v7.0.1 and its
hidden-file handling were checked 2026-09-19; only named playtest outputs are
included, never the rest of `.agents/`.

The corrected local matrix passes all six maps with unchanged assertions. The
longest stationary interval is 0.55 seconds. Receipts are in
`.agents/playtest/roster-ci-fix/`; results still include spawn deaths and do not
establish balanced play at arbitrary populations:

| Map / seed | Clients | Duration s | Frags | Spawn deaths | Longest stall s |
|---|---:|---:|---:|---:|---:|
| Arena Duel / 67 | 2 | 61.90 | 5 | 1 | 0.45 |
| Compliance Yard / 42 | 6 | 53.60 | 32 | 0 | 0.40 |
| Directive 17 / 19 | 6 | 49.35 | 22 | 0 | 0.10 |
| Sector 9 / 42 | 8 | 48.65 | 34 | 2 | 0.40 |
| Reclamation Gulch / 42 | 12 | 49.35 | 47 | 7 | 0.55 |
| Tripoint Works / 42 | 16 | 45.75 | 72 | 4 | 0.40 |

After the fixes, 594 workspace tests pass, with the existing ignored generator.
Formatting, warnings-denied Clippy, release builds, dependency license/bans/source
checks, all seventeen Godot harnesses, and the verifier's failure-injection cases
pass. Unfiltered workspace line coverage remains 95.47 percent. Two weapon-test
fixtures now set their intended ground height explicitly instead of inheriting
the height of a changing spawn position; their combat assertions are unchanged.

The new spawn selector adds measured CPU cost. The same host, seed, release
profile and 12,000-tick cases as the earlier table below now produce:

| Bots | Map | Session p99 ms | Encode p99 ms | Total p99 ms | Total max ms |
|---:|---|---:|---:|---:|---:|
| 16 | Arena Duel | 0.622591 | 0.014847 | 0.622591 | 2.1070 |
| 64 | Reclamation Gulch | 1.572863 | 0.038911 | 1.638399 | 3.4568 |
| 128 | Tripoint Works | 4.718591 | 0.110591 | 4.718591 | 9.2505 |

Every complete-trace repeat matches; no measured step exceeds 50 ms. These are
serial offline samples, not network-capacity or stable performance comparisons.
Receipts: `.agents/bench/navigation-ci-fix-*.json`. The current 21-state OpenGL
tour passes, with the contact sheet inspected and nine stills refreshed at
`.agents/qa/navigation-ci-fix/`. Earlier renderer and native-pointer evidence
below predates this navigation/spawn follow-up; no client code changed here.

## Problem and scope

Map reachability tests prove that routes exist, but controllers do not follow
them. On the v0.20.0 baseline, six mixed agents on Directive 17, seed 42, spend
long stretches against deck faces. The 61.9-second real-wire run produces twelve
frags and zero spawn deaths, yet five fighters fail the existing stuck threshold.
The longest stalls are 35.1, 29.4, and 21.0 seconds. A nearby staircase does not
help a controller that only walks toward its opponent and alternates strafing.

Build one reusable, bounded route implementation for the current heightfield.
Apply it to rule bots and the local controllers used by playtests and the decision
brain. Preserve the shared action channel, server authority, personality/range
choices in clear combat, and current frustration thresholds. Correct broken
movement and authored stair entrances where physical traversal exposes them.
This does not add overhangs, jumping routes, moving platforms, or a complete enemy
behavior system. It makes existing walkable maps usable by current fighters.

The live walkthrough also exposed a first-person presentation defect: upward
weapon bob lifts the cut-off sprite base above the viewport. Keep the sprite
overlapping the bottom edge through the full motion cycle, including swaps and
resizes, and drive walking bob from observed movement rather than an idle clock.
Verify all three weapon faces in motion, not only stationary screenshots.

Validation must extend beyond Arena Duel: run mixed network agents on all six
maps, inspect alternate-map rendering, and exercise the implemented enemy and
session lifecycles. Keep missing co-op, modes, and enemy archetypes marked planned;
passing an arena smoke does not prove them.

The expanded real-wire matrix found overlapping initial spawns beyond eight
fighters. Twelve clients on Reclamation Gulch and sixteen on Tripoint Works fail
the existing spawn-death threshold. A deterministic sixteen-join test reproduces
fighter zero/eight overlap. Reuse the existing clearance-based spawn selection
when a preferred join slot is occupied, then repeat the same cases without
changing thresholds. No new invulnerability rule or damage adjustment.

A subsequent desktop report found cursor confinement surviving a closed game
window. Release the current OS clip, centralize match mouse ownership, release on
focus loss/window close/tree exit, and keep automation capture-free. Exercise the
lifecycle and verify the actual desktop clip after rendered process shutdown.

## Architecture and research

Use `server/src/navigation.rs` with the existing `movement::Arena`, `Solid`,
`STEP_UP`, and fighter radius. Share it through `fragr-server`, as with combat
geometry. No second client collision authority or separate map representation.
Build static topology at map load, cache routes per controller, and invalidate
them on map replacement, respawn, blocked progress, or changed destinations.
Keep graph allocation, search work, and replan frequency bounded. Invalid or
oversized external geometry must fail before allocation.

Checked 2026-09-19: Rust's
[priority queue documentation](https://doc.rust-lang.org/stable/std/collections/binary_heap/index.html)
provides stable ordering and shortest-path primitives. The original
[A* guide](https://www.redblobgames.com/pathfinding/a-star/introduction.html)
separates graph search from the movement meaning of an edge. Verify that meaning
against actual movement; sightlines alone do not establish walkability.
[Recast/Detour](https://recastnav.com/) is appropriate for richer mesh navigation,
but a C++ navigation subsystem is not justified for this bounded Rust heightfield.
Retain the established stack and use the standard priority queue.

Do not rebuild topology per tick, retain a full search workspace per fighter,
teleport to route points, aim through cover, or hide a failed route as success.
Directed drops and staircase ascent need explicit tests. Benchmark construction,
queries, and 16/64/128-fighter ticks before accepting the chosen representation.

## Acceptance

- [x] Deterministic routes around cover and up a nearby staircase survive actual
  movement integration, including thin barriers, clearance, bounds, and drops.
- [x] Invalid maps/coordinates, unreachable destinations, and exhausted search
  budgets produce explicit bounded outcomes.
- [x] All six maps retain reachable spawn/pad routes; Arena Duel's crossed inner
  stair entrances are repaired after a reproduced player report.
- [x] Rule bots, playtest policies, and the brain reuse the same route seam and
  clear it across map/session/life changes. No paid provider is needed.
- [x] Repeat the exact six-agent Directive 17 baseline with existing assertions;
  check ordinary arena liveness and more than one seed.
- [x] Formatting, lints, tests, coverage, release build, dependency policy, CPU
  repeat/budget checks, Godot checks, and inspected live captures pass.
- [x] Update canonical guidance, map/controller docs, roadmap, and evidence.

Baseline command, verified against the actual CLI:

```bash
cargo run -p fragr-playtest --release --locked -- --agents 6 --tiers reflex,planner --map 3 --seed 42 --rounds 1 --frag-limit 8 --time-limit-seconds 60 --max-seconds 75 --assert --report .agents/playtest/navigation-baseline-map3.json
```

Baseline receipt: `.agents/navigation-baseline-map3.log` and the report above.
The old two-map CLI help text is stale; the parser accepts all six map IDs.

## Implementation findings

Actual route-following tests uncovered a lower-level movement defect: on leaving
a deck, gravity lowers the feet before the body clears the radius-inflated edge.
The next move treats that existing overlap as a new wall hit, permanently pinning
horizontal motion. The old fall test checked landing, but only required any
forward movement. Strengthen it to require continued travel. Allow an already
overlapping body to move outward through a nearest face, never farther inward.
Apply the rule in shared Rust movement, authoritative sim movement, and its
GDScript mirror, then regenerate and inspect golden vectors. This is a necessary
collision fix, not permission to teleport a stuck controller or weaken assertions.

Coverage exposed an async startup defect: repeated topology construction blocked
short brain sessions before meaningful play. Identical geometry now shares an
immutable `Arc`, through an eight-entry weak cache that retains no unused maps.
Construction is serialized and runs through `spawn_blocking` at async boundaries.
Server readiness follows topology setup. The existing brain timing and behavior
assertions remain intact. Tokio's [bounded blocking-work guidance](https://docs.rs/tokio/latest/tokio/task/fn.spawn_blocking.html)
was checked on 2026-09-19. Blocking workers cannot be forcibly cancelled, so map
validation and construction limits remain necessary.

The graph uses one-metre cell centres, directed drops, and swept clearance for
height transitions. Search expands at most 16,384 nodes, with at most four eligible
rule-bot searches per tick and a twenty-tick per-controller cooldown. Waypoint
following uses ordinary actions. The old playtest direction-cycling recovery is
removed. Invalid external geometry fails the agent session and reaches the
harness caller instead of becoming a misleading successful report. Shutdown now
wakes agents waiting on a quiet socket, with a cancellation test, instead of
silently abandoning their tasks. No wire shape, paid provider, or dependency changes.

### Reported jump and stair failure

The user identified first-person jitter against a stair during the walkthrough.
Two deterministic authoritative-player tests reproduced distinct problems:

- Jump press/release packets inside one tick lost the press. Retain the press for
  one tick separately from the held state. The client also retains a sub-frame
  key event. Airborne/dead ticks consume the retained press; they do not bank a
  future jump. Controller A now jumps without also firing.
- Arena Duel's perpendicular inner flights crossed at their entrances. The side
  of a taller tread blocked a straight approach. Turn the inner north and south
  approaches into a pinwheel with the existing east/west flights.
- Even after that geometry fix, reference-height subtraction could put feet a few
  floating-point units below a fractional tread. The server lost its supporting
  floor and refused the next riser. Shared Rust/GDScript grounding and support
  queries now use a 0.1 mm contact tolerance, with above/below golden cases.

The route suite now drives both shared movement and actual `GameState` players
to every pad and from every clear sampled spawn on all six maps. The former alone
did not exercise reference-height conversion. New future movement claims require
both. `client/qa/movement.json` adds a bot-free first-person tour using actual
Space events and ordinary walk input, with server positions and camera heights.
No pose teleport or collision bypass is available to that tour.

## Local gameplay evidence

Windows 11, release build, 20 Hz, unchanged playtest frustration thresholds.
Directive 17 uses six mixed reflex/planner agents, frag limit 8, sixty-second
round limit. Arena Duel uses the four-agent CI configuration. Zero spawn deaths
in every run below. These small real-wire samples establish liveness and recovery,
not weapon balance or network capacity.

| Build | Map / seed | Duration s | Frags | First frag s | Longest frag gap s | Longest stall s | Assertions |
|---|---|---:|---:|---:|---:|---:|---|
| v0.20.0 baseline | Directive 17 / 42 | 61.9 | 12 | 6.3 | 20.25 | 35.15 | Fail, five stuck fighters |
| Collision fix only | Directive 17 / 42 | 61.9 | 24 | 6.35 | 9.4 | 1.0 | Pass |
| Shared routes | Directive 17 / 42 | 49.15 | 25 | 4.2 | 4.95 | 0.05 | Pass |
| Shared routes | Directive 17 / 7 | 61.9 | 30 | 5.35 | 5.55 | 0.7 | Pass |
| Shared routes | Arena Duel / 1 | 24.0 | 8 | 4.35 | 10.5 | 0.4 | Pass |

These are intermediate investigation receipts, before the reported stair/jump
fixes. Final-build measurements follow after verification.

Deterministic tests drive the actual `Navigator` through `movement::step` from
the centre to every pickup on all six maps, and from each clear sixteen-sample
spawn-ring position back to the centre. Separate cases prove stair detours,
one-way drops, thin barriers, clearance, invalid maps/points, partial routes,
search cooldowns, target loss, and session reset. New golden vectors cover all
four ledge faces; the previous fall case now continues beyond the deck edge.

### Offline CPU receipt

Ryzen 7 7840U, Rust 1.98.1 release, seed 42, 12,000 ticks plus complete-trace
repeat per case. Serial runs, no sockets or rendering. Every full trace hash
matches, with no measured step over 50 ms. Session and serialization only;
construction, hashing, recording, networking, and GPU work are outside this table.

| Bots | Map | Session p99 ms | Encode p99 ms | Total p99 ms | Total max ms |
|---:|---|---:|---:|---:|---:|
| 16 | Arena Duel | 0.278527 | 0.013823 | 0.294911 | 1.4121 |
| 64 | Reclamation Gulch | 0.753663 | 0.059391 | 0.786431 | 2.3094 |
| 128 | Tripoint Works | 1.572863 | 0.163839 | 1.703935 | 3.2610 |

Local receipts: `.agents/navigation-*.log`, `.agents/playtest/navigation*.json`,
and `.agents/bench/navigation-release-*.json`. This table includes the final
geometry, grounding, and crowded-spawn changes. The saved v0.16.0 trace still
verifies against its original hash.

Construction observed during the release traversal test, one sample per map,
before queries and outside the tick. These are setup timings, not latency
percentiles or a network capacity claim:

| Map | Nodes | Solids | Construction ms |
|---|---:|---:|---:|
| Arena Duel | 19,600 | 92 | 15.35 |
| Compliance Yard | 12,100 | 71 | 6.02 |
| Directive 17 | 22,500 | 160 | 32.29 |
| Sector 9 | 40,000 | 50 | 11.37 |
| Reclamation Gulch | 78,400 | 103 | 48.85 |
| Tripoint Works | 102,400 | 139 | 90.17 |

## Final verification receipt

Rust 1.98.1 on Windows: 592 tests pass, with one existing ignored golden-vector
generator. Workspace formatting, warnings-denied Clippy, release build, dependency
license/bans/source checks, and all seventeen Godot harnesses pass. Unfiltered
workspace line coverage is 95.47 percent. Only the existing
ledge-fall golden case changes; six new cases cover four exit faces and fractional
stair contact from above/below. No thresholds or assertions were relaxed. The
wire-handshake test prepares topology before its unchanged two-second network
timers; cold construction is measured separately above.

Both renderer paths pass the 21-state combat/menu tour and the six-state movement
tour with inspected contact sheets, impact frames, and jump captures. Host:
Windows 11, Radeon 780M, Godot 4.7.2, OpenGL 3.3 Compatibility and Vulkan 1.4
Forward+. The short Space tap peaks at 1.295 m in both runs; the eye rises 1.187 m
and 1.180 m respectively. Both outer and inner stair ascents reach 2.6 m without
jumping. Inspection of samples within each ascending flight finds no downward
feet or eye movement. The approach between flights deliberately crosses a low
tread and is not part of that monotonic-ascent claim. The ledge exit lands and
continues. Nine current screenshots are refreshed from the combat tour.

The first movement tour correctly failed when the normal timed boss killed its
player. `--no-round-events` now provides explicit quiet arena practice and is
incompatible with campaign mode. The movement tour requests it; ordinary combat
and the main screenshot tour retain their bosses and timed rules. Receipts:
`.agents/qa/navigation-final`, `navigation-vulkan-final`, `movement-opengl-final`,
and `movement-vulkan-final`. This is local renderer evidence, not NVIDIA, Intel,
Linux GPU, or Mac GPU validation.

A separate thirty-second free brain smoke receives 600 snapshots, sends 599
actions, makes eighty local decisions, and records four frags and one death.
Remote calls and spend are zero. Receipts: `.agents/navigation-brain-final.log`
and its authoritative server log.

Final real-wire checks, zero spawn deaths, existing assertions all pass:

| Map / seed | Agents | Duration s | Frags | First frag s | Longest gap s | Longest stall s |
|---|---:|---:|---:|---:|---:|---:|
| Arena Duel / 1 | 4 reflex | 21.4 | 8 | 4.30 | 9.45 | 0.05 |
| Directive 17 / 42 | 6 mixed | 35.6 | 16 | 4.15 | 6.95 | 0.05 |
| Directive 17 / 7 | 6 mixed | 40.4 | 17 | 5.15 | 5.85 | 0.50 |

The adapter's minimal scripted example still supplies its own straight-line
intent. MCP callers control their actions; this change does not silently replace
an external agent's decisions with navigation. Rich jump routes, moving geometry,
authored enemy tactics, and a complete campaign remain separate work.

Canon clarification accompanies this milestone: `lore/belief.md` owns the gradual
loss of plausible deniability and the singularity's competing religious meanings.
The campaign points to that premise without claiming implementation. The art bible
preserves the approved worn rock-title wordmark, meatbags and agents, and looming
singularity. Existing logo art and frozen audio strings are unchanged.

## Expanded roster and presentation review

Weapon bob now follows rendered fighter movement, including spectator eyes, and
settles at rest. All three full-canvas weapon sprites overlap the viewport bottom
through walking, recoil, swaps, and resize. A regression harness samples the real
texture alpha at the bottom pixel; the live weapon manifest captures each stride.
Godot's [TextureRect contract](https://docs.godotengine.org/en/stable/classes/class_texturerect.html)
was checked on 2026-09-19. No sprite repaint or paid generation was needed.

`server/src/tests/roster.rs` now proves human and agent movement/jumps observed by
a spectator, human input acknowledgement, independent disconnect, and fresh-seat
rejoin on every map over actual sockets. A separate seeded production-session
test runs eight rule fighters plus the timed Compliance boss for 120 simulated
seconds per map. Aggressive, Defensive, Flanker, Balanced, and Compliance each
move, fire, and land hits on all six maps. These are existing controller behaviors,
not five completed campaign enemy archetypes. Existing NODS/Auditor progression
tests remain simulation tests, not evidence of a full played campaign.

The mouse owner now handles focused gameplay, overlays, focus loss, window close,
and scene teardown. Closing cannot recapture on a later focus/frame callback.
Headless checks and automated tours never capture the desktop. Camera following
continues with a visible pointer; gameplay input stops on real focus loss. The
tour fails and releases immediately if any path attempts capture. Lifecycle
regressions are in `test_mouse_capture.gd`. The current desktop clip was reset and
checked against the OS virtual-screen rectangle after the report.

The opt-in native-window probe `client/scripts/qa_pointer.gd` also passes capture,
focus loss/resume, menu release, close-latch, replacement-match, and scene-exit
checks on OpenGL. The OS cursor clip matches the full virtual screen after the
process exits, before the cleanup fallback runs. The final capture-free OpenGL
combat and movement tours pass, and their contact sheets were inspected:
`.agents/qa/navigation-pointer-release` and `movement-pointer-release`.
The final capture-free Vulkan combat tour also passes with its contact sheet
inspected at `.agents/qa/navigation-pointer-vulkan`.

The initial crowded-join regression failed on fighter zero/eight overlap. Join
now checks occupancy and reuses the respawn clearance selector, with 64 bounded
ring candidates because Reclamation Gulch does not have sixteen valid positions
on the old coarser sample. The final sixteen-join test passes on all maps. In the
same 12/16-client cases, observed spawn deaths fall from 10/52 and 15/54 frags to
5/53 and 6/54. Both pass the unchanged sample-aware threshold. This is a local
comparison, not a claim of balanced spawns at every population.

`tools/playtest_roster.sh` preserves the mixed-client six-map matrix in Linux CI.
The alternate-map visual manifest captures overview, observed eyes, and a human
joining and firing against eight rule bots. OpenGL teardown errors on the two
large maps exposed capture shutdown before renderer resource cleanup. The tour
now frees its live scene and drains render frames before exit; reruns pass with
clean logs. No error filter was weakened.

The final mixed-client matrix passes on Windows with unchanged assertions:

| Map / seed | Clients | Duration s | Frags | First frag s | Longest gap s | Spawn deaths | Longest stall s |
|---|---:|---:|---:|---:|---:|---:|---:|
| Arena Duel / 67 | 2 | 61.90 | 6 | 3.35 | 12.10 | 1 | 0.25 |
| Compliance Yard / 42 | 6 | 61.90 | 34 | 4.10 | 4.60 | 2 | 0.40 |
| Directive 17 / 19 | 6 | 58.95 | 28 | 3.95 | 5.50 | 0 | 0.75 |
| Sector 9 / 42 | 8 | 61.90 | 42 | 1.95 | 5.20 | 1 | 0.40 |
| Reclamation Gulch / 42 | 12 | 55.00 | 48 | 2.75 | 4.35 | 3 | 0.05 |
| Tripoint Works / 42 | 16 | 30.25 | 46 | 2.95 | 2.95 | 8 | 0.30 |

Receipts: `.agents/playtest/roster-final/`. The spawn-death gate uses a Wilson
lower confidence bound; passing does not mean each observed raw rate is below
ten percent. Wire scheduling varies between runs even with a fixed seed.

The inspected captures also fail the higher design bar: large open floors,
repetitive structures, and weak landmarks remain. The
[`authored-compliance-yard.md`](authored-compliance-yard.md) study records those
spatial problems, but is deferred while Nick and the campaign review settle the
story before selecting maps. Passing these checks does not make layouts finished.
