# Conquest coordination, October 8

The existing five-site Conquest mode now plans rule-bot infantry objectives once
per Session controller pass. Bots already capturing or defending retain useful
onsite work. Incoming bots fill threatened owned sites, active captures, other
uncaptured sites and quiet guards in that order. Assignment memory survives
ordinary roster churn and resets with Conquest state. Dead, waiting, detached,
eliminated, spectator and non-contestant bodies do not receive assignments or
fill demand. Seated occupants still contribute capture presence, while rule
bots in seats receive no infantry driving or firing order.

The [owning plan](../plans/conquest-objective-coordination-20261008.md) was written
before code. The [machine receipt](conquest-coordination-20261008.json) binds the
five production/test source files and retained local logs. The original capture,
contest, neutralization, decay, ticket and ending arithmetic is unchanged.
Session's existing staggered limit of four searches remains unchanged; the
assignment planner performs none. Public standalone controller updates retain
a bounded local objective fallback.

Both targeted failures were observed before implementation: a waiting teammate's
ordinal redirected a bot standing at Airfield, and an empty neutral Airfield
preceded a threatened owned Harbour. The fixed suite passes twenty tests,
fourteen new and six retained. Focused strict native lints also pass.

| Actual Session check | Result |
|---|---|
| Three bots walk from authored-world approach fixtures, capture and bleed full tickets | End at tick 2179, five sites held, Union 200 to Coalition 0, Union winner, no deaths |
| Sensed ordinary attacks against a live defender, then both capture stages | Two resolved hits, neutral at 214, capture at 374, one opposing death and ticket debit |
| Ordinary entry contests an enemy-owned site, then the opponent walks away | Thirty ticks frozen, neutral at 225, capture at 385, no opposing death |
| Teammate death, ordinary respawn and fresh bot admission | Capturer progresses continuously from 40 through 102; shared resolved damage sets the death and sixty-tick respawn |
| Parked hull cage, then one fixture hull opens | No false capture for 200 ticks; subsequent ordinary walking captures the site |

The two-stage checks retain exactly 160 ticks between neutralization and
capture. Initial player positions, sides and the parked cage are controlled
fixtures. The death/respawn churn check calls shared resolved damage directly
and makes no shot or aim claim. The defender check separately observes actual
resolved shots. These cases prove authoritative behavior through ordinary
controller movement; they do not establish a human route across the island.

At 64 controllers, the offline planner examines 2131 counted candidate,
retention and comparison steps initially and 2121 after each controller-order
reversal, below the instrumented bound of 2432. Assignments remain unchanged
and site allocation is 13, 13, 13, 13 and 12. The fixed five-site passes and the
bounded seat scan add no path searches or pairwise route work. This fixture
has overlapping bodies and measures assignment complexity only. It establishes
neither networking capacity nor hardware frame rates.

Retained ignored logs are under `.agents/conquest-coordination-20261008/`.
The focused suite passes in 2.71 seconds after compilation, which is diagnostic
timing on this machine, not a performance threshold. Strict native linting
passes across the server library and test targets. No paid calls, assets,
dependencies, protocol changes, renderer or release build were needed.

Repository integration, a rendered human Conquest session, final map art,
population measurements and human balance/fun acceptance remain open. Vehicle
driving by bots remains separate work.
