# M02 Shotgun introduction

**Status:** implemented in [draft PR #268](https://github.com/blisspixel/fragr/pull/268), 2026-09-27. This bounded level 2 encounter slice follows
the accepted [Persons Unknown design](../campaign/m02-persons-unknown.md).

## Goal and reason

Place the guaranteed Shotgun before a short first fight with two Clerks in the
ward antechamber. The current graybox gives the weapon near the ward but waits
until the ward door to wake its first fight. That skips the intended close-range
lesson before the later mixed fights. Keep the route understandable without
dialogue or a secret pickup. Level 3 remains the Jammer's introduction.

## Scope

- Move the personal Shotgun grant and available Shells onto the entry line
  before the first encounter trigger. Place the backup Pistol at the ward
  approach so it cannot override the Shotgun on pickup. Use existing
  authoritative supply claims.
- Add a bounded two-Clerk guard-room encounter. The ward group waits until
  that encounter is complete; the floor and dock retain their order.
- Put recovery health on the processing floor's exit line, where the measured
  retry could otherwise fall just before the dock.
- Prove pickup, encounter order, all-fight departure, and wipe reset through
  the existing authored map and live-session tests.
- Update the M02 plan, accepted level brief and the roadmap's one build order
  with the exact development status and remaining work.

## Boundaries

This slice does not implement the Crawler, Latch actor, correction ward seal,
M01-to-M02 run carry, new wire capability, or finished M02 acceptance. It
does not declare that an accurate-aim automated clear proves a first player's
experience. No external API call or cloud resource is required. Spend: $0.

## Architecture and verification

The authored map changes only through `server/maps/m02-persons-unknown.json`.
`server/src/maps/authored/encounters.rs` validates placements and dependency
order. `server/src/encounters.rs` retains authority for waking groups. The
route test in `server/src/mission/m02/route_tests.rs` checks the sequence and
same-attempt outcome. No protocol or API shape changes.

Run focused M02 tests, then the workspace CI gates, headless Godot checks and
a current visual tour. Inspect the Shotgun pickup, first fight and subsequent
ward approach. A pass requires the guaranteed weapon before that first fight,
both Clerks defeated, no premature ward wake, and all later fights and reset
working. Record any remaining limitation here before review.

The current graybox descends the existing service stair before the Shotgun
pickup and guard-room fight. The accepted design puts the guard room above the
stair and the Crawler introduction on the descent. That spatial reorder and
the seated, weapons-down Clerk presentation are required before the full M02
introduction can be accepted. They belong to the next Crawler and route rung,
not to this bounded combat lesson.

## Progress

- 2026-09-27: Inspected current map, authored encounter order, route test and
  accepted level design. Baseline route departed after 1001 ticks with nine
  defeats and 80 HP (seed 67, accurate aim).
- The first trigger placement stalled the route before the ward. Moving the
  ward trigger onto the guard-room exit restored the ordered transition.
  A four-seed first-fight check then found seed 42 could shoot both Clerks
  before passing the weapon pad. The Shotgun and Shells now sit together on
  the stair landing, and seeds 1, 42, 67 and 99 claim both and fire the
  Shotgun before the first two defeats.
- Seed 67's full route changed with the earlier pickup. Both human and agent
  routes defeated eleven enemies and departed after 1066 ticks at 100 HP. The
  forced-wipe replay exposed a second-attempt death at the processing-floor
  exit. Moving the recovery medkit onto that line gives the same participant
  an attempt-2 departure with eleven defeats. The rendered tour then caught
  the landing Pistol overriding the Shotgun selection. The Pistol is now found
  on the ward approach. The final seed-67 human and agent routes depart after
  1251 ticks with eleven defeats and 100 HP; the attempt-2 replay departs
  without another wipe. These are accurate-aim authoring checks, not
  difficulty or fresh-player acceptance.
- Focused M02 route tests passed after the final claim and dependency checks.
  Workspace tests, format, clippy, release build, deterministic 16-bot
  benchmark and cargo deny passed. Unfiltered workspace line coverage was
  94.29 percent after the strengthened route checks. Godot 4.7.2 headless
  checks passed.
- Independent review found that the first two defeats, hit target, ward sleep
  and attempt-2 Shotgun use needed direct evidence. The route tests now verify
  both guard-room Clerk identities, a Shotgun hit on a Clerk, the weapon claim
  when that encounter activates, no ward wake before those defeats, and the
  same lesson again after a forced wipe. All four focused tests pass.
- The final nine-state M02 tour on the AMD Radeon 780M with Godot 4.7.2 and
  OpenGL Compatibility loaded map 1002, selected the Shotgun and 20 Shells
  at the landing, spent five Shells on the guard-room pair, then selected the
  Pistol at the ward. It fought the floor and dock and departed. Its
  `02_landing_loadout.png`, `04_guard_room_fight.png`,
  `guard_room_fight_combat.png`, `05_ward_fight.png` and contact sheet were
  inspected under `.agents/qa/m02-shotgun-final-verified/`. The visual
  sequence shows two distinct Clerks and a clean route. They stand beside a
  worktable, since a seated enemy pose does not exist yet. The general tour
  ran with `--publish` and its stills were inspected. The accurate-aim capture
  is not a fresh-player or difficulty review.
  Review stills: [Shotgun at the landing](../screenshots/m02-shotgun-landing.png)
  and [guard-room combat sequence](../screenshots/m02-guard-room-combat.png).
- The first final capture tried port 7680, already owned by a system listener.
  `qa_tour.sh` accepted that listener as readiness after its own server failed
  to bind. The wrapper now refuses an occupied port before launch. The
  occupied-port check returned the expected refusal, and the final capture
  succeeded on 17678.
- Mixed-client roster through 16 clients, the four standard/team/mutator
  playtests, a 120-second 20 Hz soak, and all verifier fault-injection cases
  passed. The final workspace tests passed (523 server-library tests, two
  ignored), and unfiltered workspace line coverage passed at 94.29 percent.
  Final formatting, clippy and shell syntax checks passed. No paid service
  or cloud resource was used.

## Next work and acceptance

Rebuild the beginning so the guard room precedes the service stair. Introduce
one Crawler with its sound, caption and low wind-up on the descent, then the
three-Crawler escalation. Add a seated Clerk pose and first-shot response;
the standing graybox is not final. Follow with Latch's authored rescue, M01
run carry, and a fresh-player review of route reading, difficulty and timing.
