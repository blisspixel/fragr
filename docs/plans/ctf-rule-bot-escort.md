# Sector 9 rule-bot escort

**Status:** implemented, [draft #299](https://github.com/blisspixel/fragr/pull/299), 2026-09-29. The measured follow-up to the [external-agent defender roles](ctf-external-agent-roles.md).

## Goal and why

Twelve external agents on Sector 9 still finish on the 180-second clock, with at most one capture in a round. That population fights anything visible inside 12 metres, and every non-defender paths onto a carried flag. Repeating the experiment inside the harness does not tell us whether the bots a person plays against can finish a six-a-side flag round.

Server rule bots already finish a two-a-side, first-capture round. This change gives a side of at least three rule bots one defender and one escort. The carrier runs the flag home and does not shoot. The defender keeps the shipped 1.5 metre intercept and is the only bot who recovers a dropped friendly flag. The escort trails four metres behind the carrier, away from home, and may use that same contact shot only while beside the carrier with a clear sight line. Attackers stay on the enemy flag. A side of two bots keeps today's goals, so the four-bot seed survey stays the regression gate.

## Scope

- Change only the capture-the-flag arm of `BotController::intent` in `server/src/sim.rs`.
- Election follows `state.bots` order. Eligible means that team, alive, not respawning, not detached, and not carrying the enemy flag. The first eligible bot defends. The second escorts only while a living teammate carries the enemy flag.
- The escort holds six metres short of its own stand when the carrier is that close, so it does not stand in the 2.5 metre touch.
- Shots use the existing turn buttons. Nothing writes `action.yaw` at an enemy. Contact stays 1.5 metres. No wider chase.
- Do not edit `tools/playtest` goal selection, the brain agent, flag rules, the 20 second return, the capture limit, map geometry, the wire, or the client.

## Verification and spend

Focused tests in `server/src/tests/modes.rs` cover home-flag election, one escort during a carry, a dead or carrying defender yielding the seat, a dropped friendly flag that does not pull the attackers, escort contact that does not become a detour, a carrier who goes home instead of chasing the thief, and the frozen two-bot goal. `ctf_four_rule_bots_finish_a_scored_round_on_seed_42` and `ctf_rule_bot_seed_survey` stay as they are.

The twelve-bot measurement runs seeds 40 through 44 in the tick loop: twelve rule bots, capture limit 3, 180 seconds, replay ids. Flag touches sort by id, so a random id is not a replay. If no seed reaches the limit, the five rows are the result and the intercept stays at 1.5 metres. Exact frag totals are not a CI assert: one long match can differ by a frag across hosts.

External spend is $0. No cloud resource and no paid asset call. The 2026-09-29 allowance of $20, inside the repository's $50 cap, is not used.

## Result

Windows debug, two matching runs, 2026-09-29. Twelve rule bots, capture limit 3, 180 seconds, seeds 40 through 44, replay ids:

| Seed | Captures | Drops | Frags | Reason |
|---|---|---|---|---|
| 40 | 2 | 4 | 5 | Time limit reached |
| 41 | 2 | 4 | 4 | Time limit reached |
| 42 | 2 | 5 | 5 | Time limit reached |
| 43 | 1 | 3 | 3 | Time limit reached |
| 44 | 2 | 4 | 4 | Time limit reached |

No seed reached the capture limit. Every seed still scored, dropped a flag and recorded a frag. The 1.5 metre intercept stays. An earlier sample without replay ids moved between runs, including one pass through the limit, because overlapping touches follow id order. That sample is not the result.

The Linux full suite on the first draft changed seed 40 to 2 captures, 4 frags and 4 drops, still on the time limit. The capture count held and the frag count did not, so the table stays in this plan and is not a cross-platform assert. The same tree passed the six role tests, `ctf_rule_bot_roster_has_one_defender_per_side`, `ctf_four_rule_bots_finish_a_scored_round_on_seed_42` and `ctf_rule_bot_seed_survey`.

## Success

The role tests pass, the two-bot survey still passes, and the twelve-bot table is recorded honestly. A bot capture is not a human or spectator verdict. The carried flag's world label still uses the home words. That label is the next presentation change, and it is not part of this policy.
