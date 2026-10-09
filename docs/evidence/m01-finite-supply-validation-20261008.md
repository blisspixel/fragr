# Recall Notice finite-supply evidence

Local verification, 2026-10-08. The [bounded plan](../plans/m01-finite-supply-validation-20261008.md)
extends the existing walkthrough on the committed M01 map. The
[machine-readable receipt](m01-finite-supply-validation-20261008.json) binds
source and test hashes to all twelve route measurements and three recovery rows.
No production runtime, map, supply, HP, damage or difficulty rule changed.

## Declared miss matrix

Each run uses actual `GameSession::tick_messages`, including enemy decisions,
shared collision and normal shot resolution, with combat seed 67. Every fourth
resolved ranged attack is aimed into the ordinary ceiling while fighting.
The test verifies a solid impact, zero actor damage and exactly one real
round spent from the total ammunition pool, accounting for any same-tick
authored supply gain. Remaining shots use accurate target aim and normal spread;
the declared misses are not a claim of measured human accuracy.

Human rows arm the current finite magazine contract and send rising-edge
reload actions. Agent rows retain their finite single ammunition count.
Ordinary strafing keeps one direction through a committed tell, with a shared
collision forecast choosing a clear side. No controller grants a body pose,
health, armor or ammunition. All rows depart with zero deaths and no secrets.

| Tier | Control | Route | Attacks | Deliberate misses | Final HP | Bullets left |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Assisted | Human | Public stairs/stacks | 149 | 37 | 100 | 121 |
| Assisted | Human | Maintenance/bypass | 110 | 27 | 100 | 130 |
| Assisted | Agent | Public stairs/stacks | 138 | 34 | 100 | 132 |
| Assisted | Agent | Maintenance/bypass | 121 | 30 | 100 | 119 |
| Standard | Human | Public stairs/stacks | 134 | 33 | 100 | 136 |
| Standard | Human | Maintenance/bypass | 109 | 27 | 95 | 131 |
| Standard | Agent | Public stairs/stacks | 131 | 32 | 100 | 139 |
| Standard | Agent | Maintenance/bypass | 133 | 33 | 100 | 107 |
| Severe | Human | Public stairs/stacks | 143 | 35 | 90 | 127 |
| Severe | Human | Maintenance/bypass | 102 | 25 | 75 | 138 |
| Severe | Agent | Public stairs/stacks | 138 | 34 | 100 | 132 |
| Severe | Agent | Maintenance/bypass | 130 | 32 | 60 | 110 |

Public rows defeat 19 guards. The east bypass defeats 16, leaving all four
file-stack guards alive and all three stack supplies unclaimed. Every row
leaves the optional bay medkit, overlook armor and secret Shiv untouched.
Ordinary route supplies remain finite and useful. Final HP includes actual
authored health claims; the receipt separately retains cumulative HP and armor
lost, resolved enemy attacks, reload presses and simulation ticks.

## Death, continue and exhaustion

A separate committed-map run on each tier walks into the taught Clerk's room,
spends a found round overhead, stays exposed and dies to the guard's actual
resolved killing shot. No death is staged by writing HP. Each tier repeats
four enemy-caused deaths, successfully spends exactly three explicit continues
and ends failed on the fourth death.

After each successful continue, assertions compare the exact captured entry
position, facing, HP, armor, weapon, ammunition, loaded magazines and personal
claims. Authored stock is restored, the lift world is closed, the attempt
increases, ticks never rewind and the inventory revision advances. Duplicate
requests cannot spend twice. Exhausted players stay dead through a further
100 ticks and cannot continue again.

| Tier | Enemy-caused deaths | Continues spent | Final state | Simulation ticks |
| --- | ---: | ---: | --- | ---: |
| Assisted | 4 | 3 | Failed, exhausted | 1,488 |
| Standard | 4 | 3 | Failed, exhausted | 1,084 |
| Severe | 4 | 3 | Failed, exhausted | 956 |

## Verification and limits

The focused M01 suite passes 19 tests, including both new matrices, existing
ordinary routes, the separate 30-wasted-round bypass, optional supply and
secret lifecycle, authored navigation, wire admission and durable M01 exit
carry. The shared recovery suite passes all six tests, retaining exact saved
entry and observer monotonicity coverage. Formatting and warnings-denied
Clippy for the server library and tests pass.

```text
cargo test -p fragr-server --lib --locked tests::m01 -- --nocapture
cargo test -p fragr-server --locked mission::recovery::tests -- --nocapture
cargo clippy -p fragr-server --lib --tests --locked -- -D warnings
```

Failed driver profiles remain in `.agents/launch-authority-20261008`. The first
miss profile failed a Severe human clear. A fixed-period dodge then failed a
Standard bypass by reversing through committed fire. The final controller
retains the miss rate and combat rules, choosing a direction once per tell.
No supply quantity, health, damage, encounter timing or checker threshold was
changed to make the rows pass.

This establishes a declared automated supply margin and real recovery on one
documented combat seed. It does not establish fresh-player aim, comprehension,
fun, pacing, final tier balance, multi-seed coverage or supply contention.
Current art and rendered mission acceptance remain separate. The
[composition receipt](development-composition-20261008.md) records full
workspace, coverage and client gates separately. New spend is $0.
