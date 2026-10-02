# Campaign polish pass, levels 1 to 6

**Status:** in flight, 2026-10-02. Branch `feat/polish-m01-m06`, landing in
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

## Findings

| # | Finding | Level | Evidence | Fix | Status |
|---|---|---|---|---|---|
| 1 | The grenade counter printed `4.0` and `6.0`, because JSON decodes every count as a float | 5 | Published `m05_paint_bay.png` and `m05_departure.png` | `equipment_hud.gd` prints the integer count; `test_equipment.gd` round-trips the stock through JSON | fixed |
| 2 | A grenade claim wrote a bare `MEAT PROXY:` line, and every own pickup repeated the player's callsign | 1 to 6 | `m05_paint_bay.png` corner feed, `m01_balcony_16x9.png` | `hud.gd` names grenade claims and drops the callsign for a participant; spectators keep it; `test_combat_feed.gd` | fixed |
| 3 | Grenade supplies floated a bare `PAD` label; armor read `+50 ARM`; world pickup words were not keyed | 4 to 6 | `m04_arrival.png`, source review | `weapon_pickup.gd` uses keyed `PICKUP_*` strings, names grenades, gives them a tint; `test_weapon_pickup.gd` | fixed |
| 4 | The spawn control legend wrapped between a key and its word (`]` then `weapon`) | 1 to 6 | `m03_yard_arrival_16x9.png` legend crop | `hud.gd` keeps each key and word together; `test_combat_feed.gd` | fixed, M01 tour `.agents/qa/pol-m01-records/01_arrival.png` |
| 5 | M01's objective card still showed title, tier, a blank line and `AWAITING BOARDING: <yourself>` in solo, up to eight lines | 1 | `.agents/qa/pol-m01-records/13_record_recovered.png` | `mission_hud.gd` uses the same run badge and objective lines as M02 to M06, lists only other party members; `test_mission.gd` | fixed |
| 6 | Run and optional-route badges stayed on screen all mission, adding up to three lines of HUD text | 2 to 6 | `m04_court_balcony.png`, `m06_turret_windup.png` | Badges appear with the objective card, on a change and during recovery; `test_m03_mission.gd` | fixed |
| 7 | After every departure the only way on was Esc, Leave, Single Player, Continue Run | 1 to 6 | Source: departed copy says `RETURN TO MENU`; boot menu needs a manual choice | A completed durable run offers `ENTER: CONTINUE THE RUN`; the boot menu starts Continue Run once the old child stops; `test_end_of_run_copy.gd`, `test_frontend.gd`, live `tools/test_m02_carry.sh` | fixed |
| 8 | The local-rules agent never answered a Sweeper firing from 20 to 24 metres and died at the Railgun lane on every tier | 6 | Standard, Severe and Assisted brain runs: four deaths to `rail_sweeper` and `exit_heavy` | `agents/brain` answers an awake guard out to its 32 metre sight range | in progress, second PR: all three tiers cleared with zero deaths in a local run |
| 9 | The agent ping-ponged between two idle roof guards for 15 minutes, routing round with the trigger released | 3 | Standard seed 42 brain timeline, 900 seconds at 7 kills | The agent holds and shoots a visible guard inside 75 percent of its weapon reach instead of routing past it | in progress, second PR: Severe cleared with zero deaths in a local run |
| 10 | A guard that chased the player and lost sight idled where the trail ended, so the last required train guard was never found | 3 | Spectator probe: `train_clerk_a` stopped at `[-11, 16.7]`; Standard and Assisted agents waited at the locomotive for 6 minutes | A walking guard that chased a participant more than 8 metres from its post and lost them walks back once; alarm searches and short chases keep their authored behaviour; `lost_guard_walks_back_to_its_post_once_then_waits` | in progress, second PR: the first version (any lost trail) broke four seeded M02 routes; the narrowed rule passes all 758 server tests |
| 11 | M02 started with no health before the guard room and a three-Crawler pack that can land 75 damage at once; a low-health carry and every retry restart there | 2 | Brain timelines: 75 damage in 0.4 seconds at the pack; supply list has the first medkit after it | A 25 HP `gallery_medkit` beside the found Shotgun, on the spawn side of the guard room trigger; `bundled_gallery_offers_healing_before_the_first_guards_wake` | in progress, second PR |
| 12 | Releasing the M05 workshop workers before the paint bay's arrival spot published a state that both the Godot and the Rust readers reject, closing the connection | 5 | Severe and Assisted agent runs ended `invalid M05 facts` at `Splice and workshop captives rescued`; the run was abandoned | The server gates the release on the paint bay lesson, matching the readers; `m05_skipped_arrival_spots_catch_up_and_rescue_stays_readable` | in progress, second PR |
| 13 | M04, M05 and M06 advance only when someone stands on each fight's arrival spot after it is won. A room cleared from its doorway left the objective line stale and the departure unavailable until the player found that spot again | 4 to 6 | Agent timelines; M05 spots are 2 by 2 metres; the M06 Turret spot is on the west gallery | An arrival whose fight is won also counts once the next ordered fight wakes, or for the last one once someone reaches the boarding area; order and every reader invariant are unchanged; M05 and M06 regressions | in progress, second PR |

## Handoff

- First PR (findings 1 to 7, client only): HUD readability, pickup labels,
  quiet badges and continuing the run from a departure.
- Second PR in progress (findings 8 to 13): local-rules agent engagement,
  straggler guards, the M02 opening medkit, the M05 release that disconnected
  readers, and arrival spots that catch up once the party moves on. Worktree
  `C:\GitHubrpo2`, branch `feat/polish-agents`, stacked on the first PR.
- Scratch tools (not committed): a brain playtest runner and a read-only
  spectator probe that prints living Union actors.
