# Campaign polish pass, levels 1 to 6

**Status:** shipped in parts, 2026-10-02; stopped with the ranked open items below. Branches `feat/polish-m01-m06*`, landing in
several focused PRs.
**Spend:** $0. Local play, local decision rules (`fragr-brain --provider local`)
and the existing rendered tours only. No paid provider, asset API or cloud call.

## Goal

Levels 1 to 6 (Recall Notice through Port of Entry) are playable development
prototypes. Before Nick plays them, act as a relentless automated playtester:
find what makes them feel unfinished, buggy, confusing or flat, and fix the
root causes in the owning seams. Each fix is small and focused so progress
reaches `main` in several PRs.

## Non-goals

- New art, audio or generated assets. Sprites, viewmodels, textures and sound
  belong to their own lanes; findings there are reported, not replaced.
- Level 7, level 8, the Sniper Rifle, the Proximity Mine, the Auditor and the
  Sabotage multiplayer mode.
- Structural changes to `run_file.rs`, the save format, capability numbers or
  the wire protocol.
- Weakening any test, threshold, assertion or checker to make a route pass.
- Claiming fresh-player, difficulty or fun acceptance. Automated clears are
  authoring evidence; the uncoached player gates in the level plans stay open.

## Method

1. **Play.** Run each level on the live server with varied seeds, difficulties
   and bodies. Drive it with the free local decision rules through the shared
   mission controller, with the scripted first-person tours, and with
   spectators. Include sloppy play: death and continue, leave to menu and
   Continue Run, ignored optional routes.
2. **Look.** Run the per-level tours and the standard tour under the shared
   render lock and inspect every still: HUD coverage (target under 12 percent,
   at most one line of HUD text outside menus and the killfeed), objective
   legibility, enemy readability, dark or flat rooms, floating or clipping
   geometry, text overflow, stuck cameras, story page behaviour and the
   spectator camera rule.
3. **Measure.** Time to first fight, stalls and stuck detection, deaths per
   encounter, health and ammunition pressure, backtracking and objective time.
4. **Triage and fix.** Rank by player impact and fix causes: authored geometry,
   encounter pacing and placement, supply balance, objective cues, lighting,
   presenter bugs, menu flow, log errors and exit resource leaks (#186). A rule
   or route change gets a deterministic test; a presentation change gets
   refreshed, inspected stills.
5. Repeat until the remaining issues need a human judgement.

## Architecture impact

None planned. Fixes stay inside mission scripts, authored maps, encounters,
presenters, HUD, menus, controllers, lighting and decoration placement, through
the seams named in `AGENTS.md`.

## Verification

The full `AGENTS.md` list before each PR: formatting, warnings-denied Clippy,
workspace tests, coverage at or above 90 percent, the CPU bench, playtest
smokes, the six-map roster and `tools/godot_check.sh` under the render lock.

## Success criteria

- Every finding below has evidence, a fix or an explicit reason it stays open.
- Each landed fix has a deterministic test or refreshed inspected stills.
- Remaining items are ones automation cannot judge, phrased as specific things
  for a human playthrough to watch.

## Measurements

The free local-rules agent (`fragr-brain --provider local`) played each level's
own map file on a private server with `--campaign-run`, zero bots and a 420 to
900 second limit. It aims accurately and moves fast, so its clear times are far
below a person's and say nothing about pacing. Its deaths, stalls and
disconnects are mechanical findings. Cells read deaths, then seconds to a
departure; `fail` means all continues spent. M02 here starts from its practice
entry with fists, not a carried M01 loadout.

| Level | Standard 42, main | Severe 7, main | Assisted 1234, main | Standard 42, fixed | Severe 7, fixed | Assisted 1234, fixed |
|---|---|---|---|---|---|---|
| M01 | 0, 46 s | 0, 48 s | 0, 46 s | 0, 52 s | 0, 54 s | 0, 59 s |
| M02 | fail (ward guards) | fail | 3, last continue | 0, 57 s | 0, 68 s | 0, 76 s |
| M03 | stalled 900 s at 7 kills | stalled, 2 deaths | stalled at 5 kills | 0, 77 s | 0, 66 s | 0, 105 s |
| M04 | 1, 146 s | fail | 0, 75 s | 0, 69 s | 0, 68 s | 0, 74 s |
| M05 | 0, 60 s | disconnected | disconnected | 0, 60 s | 0, 59 s | 0, 81 s |
| M06 | fail (Railgun lane) | fail | fail | 0, 82 s | 0, 75 s | 0, 98 s |

Three more M03 seeds (Assisted 5, Severe 13, Standard 77) also depart, with
zero, two and one deaths. Spawn to first kill was under three seconds on every
level except M01 (five seconds): every level opens with a guard in view. A
spectator probe found the last M03 stall: alarmed train guards walked to the
far activation threshold, found nobody and idled there, 25 metres from the
waiting party.

## Findings

| # | Finding | Level | Evidence | Fix | Status |
|---|---|---|---|---|---|
| 1 | The grenade counter printed `4.0` and `6.0`, because JSON decodes every count as a float | 5 | Published `m05_paint_bay.png` and `m05_departure.png` | `equipment_hud.gd` prints the integer count; `test_equipment.gd` round-trips the stock through JSON | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 2 | A grenade claim wrote a bare `MEAT PROXY:` line, and every own pickup repeated the player's callsign | 1 to 6 | `m05_paint_bay.png` corner feed, `m01_balcony_16x9.png` | `hud.gd` names grenade claims and drops the callsign for a participant; spectators keep it; `test_combat_feed.gd` | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 3 | Grenade supplies floated a bare `PAD` label; armor read `+50 ARM`; world pickup words were not keyed | 4 to 6 | `m04_arrival.png`, source review | `weapon_pickup.gd` uses keyed `PICKUP_*` strings, names grenades, gives them a tint; `test_weapon_pickup.gd` | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 4 | The spawn control legend wrapped between a key and its word (`]` then `weapon`) | 1 to 6 | `m03_yard_arrival_16x9.png` legend crop | `hud.gd` keeps each key and word together; `test_combat_feed.gd` | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 5 | M01's objective card still showed title, tier, a blank line and `AWAITING BOARDING: <yourself>` in solo, up to eight lines | 1 | `.agents/qa/pol-m01-records/13_record_recovered.png` | `mission_hud.gd` uses the same run badge and objective lines as M02 to M06, lists only other party members; `test_mission.gd` | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 6 | Run and optional-route badges stayed on screen all mission, adding up to three lines of HUD text | 2 to 6 | `m04_court_balcony.png`, `m06_turret_windup.png` | Badges appear with the objective card, on a change and during recovery; `test_m03_mission.gd` | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 7 | After every departure the only way on was Esc, Leave, Single Player, Continue Run | 1 to 6 | Source: departed copy says `RETURN TO MENU`; boot menu needs a manual choice | A completed durable run offers `ENTER: CONTINUE THE RUN`; the boot menu starts Continue Run once the old child stops; `test_end_of_run_copy.gd`, `test_frontend.gd`, live `tools/test_m02_carry.sh` | shipped, [PR #320](https://github.com/blisspixel/fragr/pull/320) |
| 8 | The local-rules agent never answered a Sweeper firing from 20 to 24 metres and died at the Railgun lane on every tier | 6 | Standard, Severe and Assisted brain runs: four deaths to `rail_sweeper` and `exit_heavy` | `agents/brain` answers an awake guard out to its 32 metre sight range | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 9 | The agent ping-ponged between two idle roof guards for 15 minutes, routing round with the trigger released | 3 | Standard seed 42 brain timeline, 900 seconds at 7 kills | The agent holds and shoots a visible guard inside 75 percent of its weapon reach instead of routing past it | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 10 | A guard that chased the player, or the last alarmed guard of a group, idled where its trail ended, so the last required train guard was never found | 3 | Spectator probe: `train_clerk_a` idled at `[-11, 16.7]` after a chase in one run and at the far activation threshold `[10.1, 24.5]` in another; agents waited at the locomotive for minutes | A walking guard more than 8 metres from its post walks back once when its chase ends, or when its alarm search ends and it is the last of its group standing; other alarmed guards keep their authored dispatch; `lost_guard_walks_back_to_its_post_once_then_waits` | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 11 | M02 started with no health before the guard room and a three-Crawler pack that can land 75 damage at once; a low-health carry and every retry restart there | 2 | Brain timelines: 75 damage in 0.4 seconds at the pack; supply list has the first medkit after it | A 25 HP `gallery_medkit` beside the found Shotgun, on the spawn side of the guard room trigger; `bundled_gallery_offers_healing_before_the_first_guards_wake` | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 12 | Releasing the M05 workshop workers before the paint bay's arrival spot published a state that both the Godot and the Rust readers reject, closing the connection | 5 | Severe and Assisted agent runs ended `invalid M05 facts` at `Splice and workshop captives rescued`; the run was abandoned | The server gates the release on the paint bay lesson, matching the readers; `m05_skipped_arrival_spots_catch_up_and_rescue_stays_readable` | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 13 | M04, M05 and M06 advance only when someone stands on each fight's arrival spot after it is won. A room cleared from its doorway left the objective line stale and the departure unavailable until the player found that spot again | 4 to 6 | Agent timelines; M05 spots are 2 by 2 metres; the M06 Turret spot is on the west gallery | An arrival whose fight is won also counts once the next ordered fight wakes, or for the last one once someone reaches the boarding area; order and every reader invariant are unchanged; M05 and M06 regressions | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 14 | The local-rules agent waited at an objective forever when the group it needed had a guard idling out of sight | 3 | Assisted 1234 agent stood at the locomotive for six minutes with two train guards alive and idle at the far threshold | After 20 seconds standing still with nothing to shoot, the agent walks toward the nearest living Union body from the snapshot for up to 30 seconds; seeing a guard hands back to ordinary combat; `stalled_campaign_agent_goes_looking_for_the_nearest_hidden_guard` | shipped, [PR #326](https://github.com/blisspixel/fragr/pull/326) |
| 15 | The lunar port was not a closed hull: black space showed through slots between roofs, the freight hall opened south onto an unroofed yard, the dock opened east, the loading bay and service corridor opened north, and the exit hall and transit stood on an open platform. A player could walk out onto the surface around the whole building | 6 | `.agents/qa/pol-m06/` stills 11, 17, 23 and 24; a floor flood found 3,902 of 8,592 reachable square metres with no roof | Fourteen enamel walls and roof strips close the hull; the customs north wall sits one metre out so the corridor behind the declaration booths stays two metres wide; `authored_m06_port_is_a_closed_pressure_hull` fails on the old map | in progress, third PR |
| 16 | In M01 the ground under the reception threshold was open, so a player could walk from beneath the service landing through a 2.4 metre crawlspace under the records floors and out of the building | 1 | Ground flood and an ordinary movement probe from `[-14, 0, 8]` to `[-46, 0, 13.8]` | The threshold solid now reaches the ground; the pocket under the landing stays ordinary ground; `records_floors_have_no_crawlspace_out_of_the_facility` fails on the old map | in progress, third PR |
| 17 | The M05 tour stopped at `splice_release`: its last waypoint stood inside a held captive, which living-body contact now blocks | 5 | Art lane report; manifest waypoint `[-19, 0, 1.5]` equals `workshop_agent_a`'s held feet | The route enters the release area and steps clear of the workers' lanes; the release expectation is unchanged | in progress, third PR |
| 18 | `test_m05_presentation` failed once on macOS with 2 leaked instances and `grenade_blast.wav` still in use: the audio server still held a stopped blast playback when the harness quit | 5 | macOS job in CI run 37080486320; the same signature as #186 | The harness waits, with a three second bound, for the stopped voice's playback to be released, as `qa_tour.gd` already does on retirement | in progress, third PR |

## Open, ranked by player impact

Stopped on 2026-10-02 at Nick's request to reduce parallel work. These remain
open; none is in progress.

1. **Pacing, difficulty and fun need a person.** The accurate agent clears each
   level in one to two minutes against eight to twelve minute first-run
   targets, so its times say nothing about pacing. Watch for: where a first
   run stalls, whether the M02 Crawler pack and the M03 mast watch feel fair,
   and whether finite ammunition runs short with ordinary misses.
2. **Outdoor edges.** M03 and M04 stop at the invisible arena edge about six
   metres behind the spawn, with no wall or fence there. Needs a boundary
   design and art, not a collision tweak.
3. **Tour fights under machine load.** Under heavy shared load the M02
   graybox tour did not confirm `stair_crawler_pack_b`, the M03 tour did not
   confirm `platform_sweeper_b`, and the M05 tour lost the player at the
   workshop approach. Not reproduced on a quiet machine; the scripted routes
   may need sturdier combat timing.
4. **#186 exit leaks.** The signature (two instances, one WAV in use) matches
   a stopped sound still held by the audio server at quit. The M05 harness now
   waits for that release; `qa_tour.gd` already did. Kept open until repeated
   clean verbose exits are recorded.
5. **Agent ammunition.** On one M03 seed the local-rules agent spent all its
   Rifle rounds early and fought with fists until it found the Shotgun.
6. **Gallery refresh.** The standard tour was not republished after the HUD
   changes; the README stills do not show the changed lines.

## Handoff

- Shipped: findings 1 to 7 in [PR #320](https://github.com/blisspixel/fragr/pull/320),
  findings 8 to 14 in [PR #326](https://github.com/blisspixel/fragr/pull/326).
- Third PR: findings 15 to 18.
- A fresh worktree's first `--headless --import` crashed once in the Godot
  4.7.2 font importer; the second import succeeded. Engine behaviour, noted only.
- Scratch tools (not committed): a brain playtest runner and a read-only
  spectator probe that prints living Union actors.
