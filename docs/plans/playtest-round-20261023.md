# October 23 playtest round

Status: **in flight**, 2026-10-23. Coordinating plan for the work that follows
Nick's first Windows multiplayer playtest of v0.90.0. It sequences existing
issues into waves. It does not replace the roadmap's Full build order, which
names this round as its current rung.

## Goal

Make the shipped multiplayer experience hold up for a real human before more
campaign is stacked on it, then finish the campaign. Each wave fans out into
bounded branches, one per lane, and returns to a single reviewed `main` with
passing CI before the next wave starts.

## Waves

| Wave | Lanes and issues | Plan |
|---|---|---|
| 1 | Death and respawn lifecycle, post-death residue (#441, #437 comment) | [ffa-death-lifecycle](ffa-death-lifecycle-20261023.md) |
| 1 | Top-HUD collisions and upright result text (#437) | [hud-layout-upright-results](hud-layout-upright-results-20261023.md) |
| 1 | Mixed-input menu focus, main and multiplayer menu structure (#435, #436) | [menu-focus-and-structure](menu-focus-and-structure-20261023.md) |
| 1 | Reload readability for ordinary weapons (#440) | [reload-readability](reload-readability-20261023.md) |
| 1 | Dedicated server operator output and Windows hosting (#438) | [operator-console-output](operator-console-output-20261023.md) |
| 1 | Stutter diagnosis slice (#434, second comment) | [stutter-diagnosis](stutter-diagnosis-20261023.md) |
| 1 | Issue closeout rule (#433), this plan, roadmap | this file |
| 2 | Benchmark UX (#439), music playback and controls (#442), FFA starting kit (#431 comment), 4 s FFA respawn, wave 1 leftovers | written at wave start |
| 2+ | Asset round with the funded Higgsfield, Meshy and ElevenLabs credits | [asset round](asset-round-20261023.md), written before any paid stage |
| 3 | Level 19, Planned Works (#429) | [brief](../campaign/l19-planned-works.md) |
| 4 | Level 20, Local Exception (#430) | [brief](../campaign/l20-local-exception.md) |

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
- **Asset credits:** use the funded Higgsfield balance and the included Meshy
  and ElevenLabs credits fully, Meshy first because its monthly credits reset
  on 2026-11-03. Spend only on assets that will be integrated and visible.
  Existing AGENTS.md spend rules apply: live balances, exact prices, durable
  reservations, no purchases, renewals, top-ups or overages.

## Non-goals

Transport rewrites, lag compensation, new modes, cloud apply, and renaming the
round's lanes into a second build order.

## Verification

Each lane records its own evidence in its plan and PR: the AGENTS.md checks for
what it touched, rendered captures inspected under `.agents/`, and Windows
rendered evidence listed as not run when it was not run (the round's lanes run
on a Linux host). One `tools/qa_tour.sh --publish` runs at the end of each wave
that changes what a player sees, so lanes do not fight over screenshots.

## Success criteria

- Every wave merges back to one green `main`, squash merged in a recorded order.
- Each closed issue carries a closeout note per the AGENTS.md rule from #433.
- A fresh Windows pass by Nick on the wave 1 build, recorded separately from
  the automated evidence.

## Status

- 2026-10-23: wave 1 lanes started from `e4cec37`.
