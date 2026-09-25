# Spawn quality on maps 3 to 6

Status: **shipped** in #237 (v0.47.1).
Spend: $0. Checked 2026-09-24.

## Goal

Close the rung 10 map-quality gap: the six-map mixed-client roster passed its
assertions while reporting 3, 4, 3 and 1 spawn deaths on Directive 17, Sector
9, Reclamation Gulch and Tripoint Works. Find the cause per map, fix it at the
owning seam, add deterministic regressions, and tighten the playtest gate so
the gap cannot return silently.

Non-goals: HP, weapon damage, the one-second respawn shield, the respawn delay,
protocol shapes, a second spawn algorithm, or a map redesign.

## Definition

A spawn death is a frag whose victim spawned no more than
`SPAWN_DEATH_WINDOW_TICKS` (40 ticks, two seconds) earlier, counted in
`tools/playtest` from `RoundStart` (the opening) or `Respawn` events. The harness
now also reports `opening_spawn_deaths`, the subset whose spawn was the round
opening, and logs the victim's spawn point, the victim's and killer's last
positions, and whether the spawn was an opening, for every spawn death.

## Reproduction and root cause

The recorded counts reproduced on unchanged `main` (`0fd7174`): map 3 seed 19
gave 4 spawn deaths in 28 frags, map 4 seed 42 gave 4 in 44, map 5 seed 42 gave
3 in 53, map 6 seed 42 gave 1 in 53. Most died at tick 61 or 62 after a round
start at tick 40: two Rail hits, 80 damage each with a 20-tick cooldown, fired
by a fighter who could see them from the first active tick. Several were mutual
kills on the same tick.

Opening placement is deterministic. Warmup does not move fighters, and
`GameState::add_player` places each joiner through `select_spawn_angle`. A
placement diagnostic showed the roster openings already in each other's lanes:

| Map | Fighters | Firing lanes between opening fighters (old main) |
|---|---:|---|
| Directive 17 | 6 | 2, both 19.5 m |
| Sector 9 | 8 | 2, both 26.7 m |
| Reclamation Gulch | 12 | 4, 35.9 to 53.4 m |
| Tripoint Works | 16 | 0 (sorting bays from [#193](./tripoint-spawn-safety.md)) |

The selector was not the limit. Counting how many of the 64 ring slots can be
held at once with no lane between any two of them (greedy, within 70 m) gave 8
on Directive 17, 9 on Sector 9 and 10 on Reclamation Gulch, against rosters of
6, 8 and 12. Sequential placement cannot reach that bound, and Gulch cannot hold
12 at all. The maps lacked covered spawn capacity. Tripoint, with 16 pockets,
has 34.

A second, smaller defect was in selection: it counted a lane out to the 100 m
hitscan cap, although no weapon reaches past the rail's 60 m. A harmless 70 to
100 m lane therefore disqualified a far slot and sent a respawn to a closer
covered corner. In a sweep of two opponents on every pair of even spawn points,
this happened in 318 of 496 Directive 17 respawns and 64 of 496 on Sector 9.

Map 6's single opening death followed movement out of cover, not a static lane.

## Change

- `server/src/maps.rs`: the existing `spawn_pockets` builder now takes a phase
  and a block height. Directive 17, Sector 9 and Reclamation Gulch gain 16
  pockets on their spawn rings, matching Tripoint. Directive 17's pockets are
  turned half a step so its deck diagonals, health pads and deck-to-pit shot
  stay open, and stand 6.5 m so they still screen on a 3 m deck. Three pads that
  the new blocks covered moved just behind them: Sector 9's flechette
  (0, -60 to 0, -66) and Gulch's scatter and flechette (0, +-100 to 0, +-104).
  Covered capacity becomes 19, 19 and 25. `validate`, reachability and actual
  movement routes still pass for every pad and spawn.
- `server/src/sim.rs`: `select_spawn_angle` counts a lane only inside
  `SPAWN_THREAT_RANGE`, the rail's 60 m plus 10 m an opponent walks in the
  two-second window. The priority order (clear, fewer lanes, wider gap) is
  unchanged.
- `tools/playtest`: `opening_spawn_deaths` in the report and summary line,
  per-death positions in the log, and a new gate described below.

An earlier local experiment (unpushed commit `98d69e6` in another worktree)
preferred a separation distance before comparing lanes. It was not ported: its
own notes record that it failed the Gulch covered-respawn fixture and the Sector
9 bot test at 30 m and did worse on map 3 at 20 m, and once lanes are compared
first, a separation flag orders slots the same way the existing gap tiebreak
does.

## Regression tests

`server/src/tests/spawns.rs`:

- `every_playtest_roster_opens_screened_and_walkable`: each map's roster size
  from `tools/playtest_roster.sh` opens with no lane between any two fighters
  within `SPAWN_THREAT_RANGE`, no overlap, and a server-movement walk to the
  centre. It fails on old `main` geometry at Directive 17 (33.7 m lane with the
  new selector, 19.5 m with the old one).
- `a_respawn_takes_the_widest_slot_out_of_every_lane`: with two opponents on
  spawn points, a Directive 17 or Sector 9 respawn is out of both lanes and
  takes the widest such slot. It fails with the old 100 m lane count.
- `a_respawn_avoids_both_the_lane_and_the_corner_of_a_lone_opponent`: on every
  map, a respawn against one opponent on any spawn point is out of its lane and
  more than 32 m away.
- `threat_range_covers_every_weapon_and_the_safe_window`.

The Tripoint cover test, the Gulch covered-respawn fixture, map validation and
every bot behavior test are unchanged and pass.

## Playtest gate

`check_thresholds` now fails a run with more than one opening spawn death per
completed round. The Wilson rate ceiling is unchanged and still applies. One is
tolerated because a fighter can walk out of cover into a lane inside two
seconds, which old `main` showed on Tripoint. Ten of the sixteen baseline runs
below would fail this gate, including the map 3 and map 4 roster seeds; no run
of the fixed build would.

## Before and after

Local Windows network runs, `reflex,planner` mixed agents, frag limit 8, 60 s
limit, the roster sizes from `tools/playtest_roster.sh`. Seed 19 (map 3) and 42
(maps 4 to 6) are the roster seeds. Before is `0fd7174`; after is this change.
Four runs ran in parallel per batch. Network scheduling is not deterministic,
so these are samples, not rates.

| Map / seed | Fighters | Before: spawn deaths (opening) / frags | After: spawn deaths (opening) / frags |
|---|---:|---:|---:|
| 3 Directive 17 / 19 | 6 | 4 (4) / 22 | 0 (0) / 28 |
| 3 Directive 17 / 7 | 6 | 2 (1) / 24 | 1 (0) / 17 |
| 3 Directive 17 / 67 | 6 | 4 (4) / 31 | 0 (0) / 25 |
| 3 Directive 17 / 101 | 6 | 2 (2) / 26 | 0 (0) / 33 |
| 4 Sector 9 / 42 | 8 | 3 (2) / 33 | 1 (0) / 35 |
| 4 Sector 9 / 7 | 8 | 5 (3) / 34 | 0 (0) / 37 |
| 4 Sector 9 / 67 | 8 | 2 (1) / 38 | 2 (0) / 29 |
| 4 Sector 9 / 101 | 8 | 0 (0) / 34 | 0 (0) / 34 |
| 5 Reclamation Gulch / 42 | 12 | 2 (1) / 43 | 0 (0) / 50 |
| 5 Reclamation Gulch / 7 | 12 | 3 (3) / 55 | 0 (0) / 49 |
| 5 Reclamation Gulch / 67 | 12 | 4 (3) / 46 | 0 (0) / 47 |
| 5 Reclamation Gulch / 101 | 12 | 4 (2) / 47 | 0 (0) / 42 |
| 6 Tripoint Works / 42 | 16 | 1 (1) / 65 | 0 (0) / 67 |
| 6 Tripoint Works / 7 | 16 | 3 (2) / 71 | 0 (0) / 54 |
| 6 Tripoint Works / 67 | 16 | 5 (2) / 81 | 1 (0) / 61 |
| 6 Tripoint Works / 101 | 16 | 3 (1) / 60 | 2 (0) / 48 |
| **Total** | | **47 (32) / 710** | **7 (0) / 656** |

Opening deaths went from 32 to 0. The seven remaining are respawn deaths, and
the logged positions show the same shape in each: the fighter respawned in a
bay, walked 2 to 9 m out of it, and died 31 to 40 ticks after spawning to a
killer 10 to 32 m away at the moment of the kill. An earlier iteration logged
two Sector 9 fighters who killed each other, respawned on the same tick 21.6 m
apart behind separate bays, then walked into each other. These are movement
after a legal covered spawn, past the one-second shield, and remain open.

Reports and logs: `.agents/spawnq/m-base/`, `.agents/spawnq/m-final/`, with
earlier iterations beside them. The final roster run is listed under
Verification.

## Visual check

`FRAGR_QA_MAP=3`, `4` and `5` tours (24 states each) were captured under
`.agents/qa/spawnq-map{3,4,5b}/` and the overview and first-person stills were
inspected: the new bays render as the maps' existing crate stacks, on the ring,
with the pits, halls and gulch still open. The first map 5 attempt ended with a
Godot OpenGL texture leak report at shutdown after all 24 states; the repeat was
clean. The published tour uses Arena Duel, which did not change, so
`docs/screenshots` was not republished.

## Verification

Local Windows, Ryzen 7 7840U, logs under `.agents/verify-spawn/`:

- `cargo fmt --all -- --check`, strict Clippy, `cargo test --workspace --locked`
  (817 tests), the seed-42 16-bot release benchmark with `--bench-assert`, the
  release workspace build, `cargo deny check licenses bans sources` and the
  four-agent playtest smoke all pass.
- `bash tools/playtest_roster.sh` passes all six maps. Spawn deaths (opening) /
  frags: map 1: 0 (0) / 6, map 2: 2 (1) / 24, map 3: 0 (0) / 19, map 4: 0 (0) /
  34, map 5: 0 (0) / 50, map 6: 1 (0) / 66. Compliance Yard's opening death
  followed a 4 m walk out of an unexposed start, which is the case the one-death
  allowance exists for.
- After rebasing onto `bea7f85`, the workspace tests all pass and a second
  roster run passes with 0, 0, 0, 1, 0 and 0 spawn deaths (none at the opening)
  among 6, 25, 22, 37, 48 and 51 frags on maps 1 to 6.
- `cargo llvm-cov --workspace --locked` reports 93.86 percent of lines with
  every test passing. Two earlier coverage runs failed
  `fragr-brain` `bot::tests::failed_calls_fall_back_and_still_count` (and once
  `a_bad_key_switches_the_brain_off_after_one_call`), timing-sensitive tests
  under instrumentation. The first also fails under `cargo llvm-cov -p
  fragr-brain` on unchanged `main`, so it is not caused by this change.
- `tools/godot_check.sh` with Godot 4.7.2-stable passes.

## Remaining limits

- Respawn deaths still happen when two fighters respawn out of each other's
  lanes and then walk into each other. Selection judges positions at the spawn
  tick; it does not predict routes.
- Arena Duel and Compliance Yard were not changed. Their rosters open without
  lanes, but their covered capacity is 8 each.
- A larger roster than `tools/playtest_roster.sh` uses on a given map has not
  been measured.
