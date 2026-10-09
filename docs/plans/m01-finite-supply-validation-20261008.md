# Recall Notice finite-supply validation

Status: implemented, 2026-10-08, local evidence recorded. Bounded automated acceptance work for
[#195](https://github.com/blisspixel/fragr/issues/195) and
[#197](https://github.com/blisspixel/fragr/issues/197).

## Scope

Extend the existing ordinary `GameSession` M01 walkthrough with explicit tier
selection and periodic resolved misses. Run Assisted, Standard and Severe on
both public stairs/file stacks and maintenance/east bypass, without optional
health, armor or the secret Shiv. Human rows arm the current magazine contract
and use actual rising-edge reload input. Agent rows retain their finite single
ammunition count. Keep the existing route, supply and departure assertions.

| Matrix | Rows | Required evidence |
| --- | ---: | --- |
| Three tiers, two routes, human and agent | 12 | Every fourth resolved ranged attack deliberately misses during combat, spends a real round, deals no damage and strikes ordinary collision; actual departure, finite ammo remaining, guard identities and untouched optional stocks. |
| Real enemy death and continue | Three tiers | Stand through an actual taught guard attack, spend a real continue, restore fists and entry body/stock, preserve ticks and tier, reject duplicate requests. |
| Exhaustion | Three tiers | Four ordinary enemy-caused deaths, exactly three successful continues, final failed status with no resurrection or further continue. |

The existing recovery and durable run-file regressions continue to establish
exact saved entry restoration and reload persistence. The new rows add actual
enemy decisions and deaths on the committed map. Log attack, deliberate-miss,
kill, tick, damage and remaining-ammunition measurements. Retain failures.

## Architecture and limits

Own `server/src/tests/m01.rs` only for backward-compatible driver options and
a focused child test module in `server/src/tests/m01_acceptance.rs`. Reuse
the committed source map, shared navigation, combat, inventory and mission
continue entry points. Do not edit `mission.rs`, HP, damage, ammunition,
geometry, tiers, persistence formats, protocol or checker thresholds.

These deterministic controls test authored supply margin at a declared miss
rate. They do not establish fresh-player aim, route comprehension, final art,
fun, pacing or final difficulty balance. Supply contention remains separately
covered by existing party tests and is not inferred from solo rows.

## Verification and spend

Run the focused matrix, all existing M01 regressions and the existing recovery
and durable entry tests. Format and warnings-denied Clippy cover changed native
tests. Composed coverage and full repository gates remain separate. No renderer
is needed without a reproduced geometry defect. Spend is $0, with no external
service or asset generation.

## Local result

All twelve declared miss rows depart without a death or optional cache, with
107 to 139 bullets remaining. Every fourth actual ranged attack resolves as
an ordinary solid miss with zero damage and an exact one-round pool decrement.
Human rows perform real reload input; agent rows retain their finite count.
All three recovery rows complete four enemy-caused deaths, three explicit
continues, exact entry restoration and final exhaustion. Duplicate requests,
tick monotonicity and inventory revision assertions pass.

The focused M01 suite passes 19 tests, shared recovery passes six, and
warnings-denied server library/tests Clippy passes. The
[evidence and receipt](../evidence/m01-finite-supply-validation-20261008.md)
retain all rows, the documented seed and failed driver profiles. Integration
and the human, final art, contention and multi-seed acceptance gates remain
separate. No production or source-map change was needed.
