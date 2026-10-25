# October 23 playtest round

Status: **shipped** with Linux evidence, 2026-10-24: wave 1 in #457, wave 2
(with waves 3 to 5 folded in) in #471. Nick's Windows play is owed.
Coordinating plan for the work that follows
Nick's first Windows multiplayer playtest of v0.90.0. It sequences existing
issues into waves. It does not replace the roadmap's Full build order, which
names this round as its current rung.

## Goal

Make the shipped multiplayer experience hold up for a real human before more
campaign is stacked on it, then finish the campaign. Each wave fans out into
bounded branches, one per lane, and returns to a single reviewed `main` with
passing CI before the next wave starts.

## Waves

Bounded lanes carry their scope and evidence in the issue and the PR
description; a lane writes a plan file only if it grows into several PRs.

| Wave | Lanes and issues | Record |
|---|---|---|
| 1 | Death and respawn lifecycle, post-death residue (#441, #437 comment) | #450 in #457 |
| 1 | Top-HUD collisions and upright result text (#437) | #447 in #457 |
| 1 | Mixed-input menu focus, main and multiplayer menu structure (#435, #436) | #453 in #457 |
| 1 | Reload readability for ordinary weapons (#440) | #449 in #457 |
| 1 | Dedicated server operator output and Windows hosting (#438) | #446 in #457 |
| 1 | Stutter diagnosis slice (#434, second comment) | #452 in #457 (traces only; no fix claimed) |
| 1 | Issue closeout rule (#433), this plan, roadmap, agent guidance diet | this file, PR #443 |
| 2 | Benchmark UX (#439), music playback and controls (#442), FFA starting kit (#431 comment), 4 s FFA respawn, wave 1 leftovers | #458, #448, #467, #460 and more in #471 |
| 2+ | Asset round with the funded Higgsfield, Meshy and ElevenLabs credits | candidates made; Nick's picks and integration are the [roadmap's next steps](../ROADMAP.md#next-steps) |
| 3 | Golden slice and hero map: boot, menu, join, fight, die, respawn and result on one hero FFA map, plus campaign Level 1 | #464 and #461 in #471; awaits Nick's play |
| 4 | Level 19, Planned Works (#429), built to the golden-slice bar | #465 in #471; placeholder Paver |
| 5 | Level 20, Local Exception (#430), built to the golden-slice bar | #466 in #471; placeholder Surveyor and Paver; Still Here unbuilt |

Later, not in these waves: the remaining multiplayer excellence (#431) and
bot and enemy AI excellence (#432) scope, and #434 stages 2 to 6, which wait on
the wave 1 measurements.

## Decisions (Nick, 2026-10-23)

- **FFA respawn pacing:** 4 s fixed (80 ticks at 20 Hz) for free-for-all only,
  with a server-consistent countdown. Team, elimination, Sabotage and campaign
  timers stay unchanged. Lands in wave 2 after the #441 lifecycle fix makes the
  transition legible.
- **FFA starting kit:** Tack sidearm plus Fists. Stronger guns become map
  pickups that must be owned before selection. Weapon-only modes, Golden Rail
  and Slappers, custom host rules, campaign continuity and benchmark fixtures
  keep their own kits. Map supply coverage and bot pickup-seeking are part of
  the change, per the #431 comment.
- **No tilted text:** status, result and signature-moment text renders on a
  level baseline. `StampCard` keeps no text rotation in any motion setting; the
  stamp feel comes from border, weight, colour and settle, not angle (#437).
- **No backward save compatibility before 1.0** (2026-10-23): nobody plays yet.
  Collapse the run file to one current schema and delete the historical
  migrations and exact-byte archives. Older saves are refused with a clear
  message.
- **Build it fully and exceptionally well:** the golden slice comes first, from
  boot through menu, join, fight, die, respawn and result, on one hero FFA map
  and campaign Level 1. It sets the quality bar. Levels 19 and 20 and the rest
  of the campaign and modes are then built to that bar; nothing is cut.
- **Radio stays in proportion:** GTA-style in-game radio, several music
  stations plus a funny on-lore news and chat station. It gets good music and
  console-sensible controls, but it is not the plot, the Host's identity or the
  game's vocabulary: no "frequency" puns in Host calls, no "Contested
  Frequency" taglines.
- **Feel:** fast arena movement (Quake, UT, Doom speed, air control, rocket and
  dodge tricks) with CS-crisp stops and acceleration. Arena weapon accuracy:
  first shot on aim, visual kick and camera punch, small spread only on
  sustained automatic fire.
- **Art direction:** an ultra-modern boomer shooter in the Boltgun sense, in
  homage to Doom, Unreal, Counter-Strike, Battlefield 1942 and Halo. Lore and
  fun vibe come first. The character treatment is chosen from a side-by-side
  trial before the roster is converted.
- **Asset credits:** use the funded Higgsfield balance and the included Meshy
  and ElevenLabs credits fully, Meshy first because its monthly credits reset
  on 2026-11-03. Spend only on assets that will be integrated and visible.
  Existing AGENTS.md spend rules apply: live balances, exact prices, durable
  reservations, no purchases, renewals, top-ups or overages.

## Non-goals

Transport rewrites, lag compensation, new modes, cloud apply, and renaming the
round's lanes into a second build order.

## Verification

Each lane records its own evidence in its PR and issue closeout: the AGENTS.md checks for
what it touched, rendered captures inspected under `.agents/`, and Windows
rendered evidence listed as not run when it was not run (the round's lanes run
on a Linux host). One `tools/qa_tour.sh --publish` runs at the end of each wave
that changes what a player sees, so lanes do not fight over screenshots.

## Visual QA loop (every wave)

Headless checks do not see ugly. After each wave merges, rerun the full tour,
then have reviewers open every still and motion strip against the art bible and
the bar of current retro shooters. Each defect they file goes to a fix lane,
followed by recapture and another look, until a pass finds nothing. Stale stills
count as defects: on 2026-10-23 `tour_team_first_person_16x9.png` still showed a
September HUD. The published `tour_multiplayer_16x9.png` showed the #435
two-edge highlight that no check had flagged.

## Success criteria

- Every wave merges back to one green `main`, squash merged in a recorded order.
- Each closed issue carries a closeout note per the AGENTS.md rule from #433.
- A fresh Windows pass by Nick on the wave 1 build, recorded separately from
  the automated evidence.

## Status

- 2026-10-23: wave 1 lanes started from `e4cec37`.
- 2026-10-24: wave 1 merged as #457. Wave 2 integrated seventeen lane PRs
  as #471, which also carried the golden slice, Larak Lot and Episode V.
  Evidence is Linux only: Rust and Godot suites, coverage, playtest smokes
  and an inspected `tools/qa_tour.sh --publish`. Not run: Windows, macOS,
  real pads, packaged builds, soak and a human playtest. #471's open
  questions carry the per-lane follow-ups; the
  [roadmap's next steps](../ROADMAP.md#next-steps) carry the order of work.
- 2026-10-24: v0.91.0 released from #473. A follow-up integration (branches
  `wave3/*`) took four lanes into one PR: the Larak Lot prop models, #431's
  rocket jump, Custody Plate, Duel and podium rematch, #432's token-paced
  Union tells and Latch's cover, and #434 stage 2's encode-once fan-out. The
  Still Here lane did not deliver. Evidence is Linux only, as before.
