# M01 crowd route recovery

**Status:** in flight, 2026-10-01. Bounded repair within the
[M06 integration](m06-port-of-entry-prototype.md); sequencing remains in the
[full build order](../ROADMAP.md#full-build-order-2026-09-27).
**Spend:** $0. No assets, dependencies, wire changes or external requests.

## Captured failure

The first [PR #317 CI run](https://github.com/blisspixel/fragr/actions/runs/36955029658)
at `e6f0e78` passes 749 server tests but fails the actual M01 shared-party
controller gate. Its four Standard participants remain alive in attempt one,
with one aboard the lift and three stalled at the upper northwest gallery.
The 4000-tick completion budget expires. The two-player Standard case passed
first; this is a navigation failure, not evidence of a difficulty or combat gate.
The retained log preserves the exact identities, positions and mission state:
`.agents/m06-buildout-20261001/github-pr-test-job.log`.

## Repair contract

Use the existing shared `Navigator`, ordinary movement and body-contact solver.
An occupied intermediate waypoint must not be skipped across a blocked world
leg. Observed crowd stalls must not be hidden by a forecast that freezes every
peer. Keep recovery bounded, grounded and subject to the same map and body rules.
Retain the final destination, campaign control channel and navigation budget.

Do not change map bytes, grant equipment, exempt contacts, teleport participants,
increase the completion budget or substitute favorable identities. Reproduce
the occupied corner and retained failing party through actual authored geometry,
then verify ordinary identity order variations and the existing strict campaign
and retry gates.

## Verification and closeout

- Focused regressions fail before the repair and pass afterwards.
- Actual M01 two/four-player Standard, Assisted, Severe and solo retry gates
  retain their completion and death assertions.
- Existing M02-M06 controller and multiplayer route checks remain intact.
- Formatting, warning-denied Clippy, workspace tests, unchanged unfiltered
  coverage floor and required CI checks pass on the final source.
- Refresh and inspect the published standard tour against the matching server.
  Update the parent plan, merge only passing CI and retain the failed receipt.

## Repair and cross-mission findings

The occupied-corner regression fails before the geometry guard. The retained
four-person scene also fails with that guard alone, demonstrating the separate
simultaneous-crowd stall. Recovery now observes six consecutive stationary
ticks independently of static route searches. Normal map-constrained wishes
are preserved; an unclipped wish is used only for an observed blocked-map crowd
stall. Candidate count, grounded forecasts and authoritative contacts remain
bounded through the existing seam.

The safe-corner guard exposed two incidental assumptions in the private M02
authoring driver. Its Severe route never approached the armor pad, despite
asserting a claim; its lesson could shoot a dormant stair pack before clearing
the lone Crawler. The diagnostic receipts retain both failures. The private
driver now requests an ordinary supported armor visit and explicitly follows
the first landing before targeting the later pack. Player runtime keeps its
ordinary ability to shoot later guards early. There are no grants, teleports,
synthetic damage, map changes or invulnerable enemies.

Both original aggregate budgets remain unchanged: 16000 ticks for the Severe
route and 12000 for the Crawler lesson. Existing two-cue origins/heights/timing,
24 defeats, attempt-one departure and actual finite stock consumption remain
asserted. New resolved-shot assertions also require lone-Crawler hits before
the pack cue, no early pack hits and real later pack hits. All 23 M02 checks
pass in `nav-final-m02-preserved-budgets.log`.

The eight Navigator checks pass, including the captured crowd's current feet
inside the lift while retaining support, world clearance and body separation.
The complete shared mission controller also passes its existing random two/four
Standard, two Assisted, two Severe and strict solo retry gates. A new full
MissionClient test rotates and reverses the retained identities without replacing
those original tests. The CTF survey retains its original completion and
combat-drop thresholds.

| Focused final source gate | Cases | Result |
|---|---|---|
| Navigator, including required corner and retained simultaneous crowd | 8 | pass |
| Mission controller, including the eight full retained-identity orders | 15 tests | pass |
| M02 routes and encounters, original aggregate budgets and assertions | 23 | pass |
| Contested CTF survey | 16 seeds, one test | pass under unchanged thresholds |

| Seeded actual M01 retained-identity replay | Orders | Minimum departure tick | Maximum departure tick |
|---|---|---|---|
| Four participants, Standard, existing enemy replay policy | 8 | 1079 | 1574 |

This is ordinary-input authoring and regression evidence, not fresh-player pacing
or remote-network acceptance. Receipts: `nav-final-controller.log`,
`nav-final-mission-orders.log`, `nav-final-m02-preserved-budgets.log` and
`nav-final-ctf-survey.log` under `.agents/m06-buildout-20261001/`.
Final local workspace verification passes 1243 tests (three existing ignored),
warning-denied Clippy, formatting, the release build and the unchanged 90 percent
floor with 94.31 percent unfiltered line coverage. The matching standard tour
passes all 32 states, publishes 13 stills and has clean engine logs. Inspected
bodies, menus and weapon motion show no concrete regression. The deterministic
16-bot, 1200-tick release benchmark retains trace
`fb75dd61f87fc2c0c64df3cc58fb86749f501e07359093909eacd97baea20c4e`.

| Quiet Windows CPU benchmark, Arena Duel, seed 42 | p50 ms | p99 ms | Maximum ms | Ticks over 50 ms |
|---|---|---|---|---|
| Final recovery source, 16 bots plus the benchmark participant | 0.172031 | 1.179647 | 1.7122 | 0 |

Receipts: `nav-final-workspace-tests.log`, `nav-final-clippy.log`,
`nav-final-coverage.log`, `nav-final-release-build.log`, `nav-final-bench.log`
and `client-standard-nav-final-source.json` under the same ignored directory.
Main integration and release remain pending. The additional texture batch does
not change movement or the benchmark source.
