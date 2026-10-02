# CTF seeded body order

**Status:** implemented, updated 2026-10-02. Focused and full Rust gates and matching release wire smokes pass; final client verification, CI and release integration remain pending. Bounded deterministic test repair, retained identity-order coverage and contact-range flag-carrier defense. No generic navigation, contact solver, random stream, map or match-rule change is authorized by this plan.

## Observed failure

Checkpoint `d41c2b6` Windows CI job 110724699015 fails `ctf_rule_bot_seed_survey` with 13 completed rounds out of 16 against the unchanged minimum 14. The exact failed log is `.agents/m06-buildout-20261001/d41-windows-failed.log`. Server source is identical between the passing `054031c` checkpoint and `d41c2b6`; the latter changes presentation and capture code.

The survey seeds gameplay randomness but its `GameSession::spawn_bots` creates random UUIDs through `new_entity_id`. Shared living-body resolution sorts by those identity keys. Consequently the same gameplay seed does not fix body projection order. A subsequent untouched local debug run passes, recorded in `ctf-current-debug-survey.log`; that observation demonstrates varied setup rather than a repaired gate. CI is not retried merely to obtain a passing identity draw.

## Scope and ownership

Initial diagnostic ownership was `server/src/tests/modes.rs` and this plan. Following the reproduced carrier defect, current ownership also includes only the two-bot carrier interception predicate and adjacent role comments in `server/src/sim.rs`. Use the existing `GameState::use_replay_ids` seam before ordinary `spawn_bots` for the canonical fixture. Keep the production four-bot names, behaviors, body selection, team assignment and real session tick path. No change to production IDs or contact ordering is needed merely to stabilize the test.

Retain varied identity-order risk explicitly: declared ascending, reverse, within-side swap and side swap permutations each exercise all seeds 40 through 55. Use existing public roster, player admission and bot-controller APIs for construction, with identities assigned before admission. Allocate all four identities through `new_entity_id` first, then permute those allocated keys. Both canonical and varied fixtures must retain next allocation 5, distinct from every existing participant. Do not mutate already registered participant IDs or add a production configuration seam.

Each survey retains 120 seconds at 20 Hz, at least 14 completed scored rounds and at least 8 rounds with combat drops visible for at least 10 ticks. Outcomes retain captures, frags, drops, ended state and visible-drop ticks per seed and identity order. Repeated identical canonical setup must yield identical tuples. Any fixed-order failure remains an actionable controller/contact diagnostic; do not choose a convenient order, weaken a threshold, extend ticks or discard difficult seeds.

## Verification and coordination

Run focused debug tests with per-order/per-seed diagnostics after the rendered tour's CPU lease is free. No release executable replacement, Godot import, GPU capture or native game listener runs in this lane. Source-only tests preserve the failing CI receipt. Root controls broad Rust verification, CI and publication after source freezes.

If a deterministic case fails, first inspect actual body positions, ordinary actions, objective progress and contact support before proposing a production fix. Keep combat, scoring and map geometry authoritative. The final M06 capture lease is separate and resumes after its phase-aware QA helper freezes.

**Spend:** $0. No service calls or dependencies.

## Deterministic failure and bounded correction

The corrected four-order matrix retains every original gate. Canonical completes 15/16, reverse 16/16, within-side 13/16 and side-swap 16/16. All four orders show qualifying combat drops in 16/16 rounds. The identical canonical repeat matches all 16 outcome tuples. The within-side threshold still fails. The complete earlier-history diagnostic, `ctf-earlier-transition-diagnostic.log`, exits 101 after 175.11 seconds; it is failure evidence.

Timeout histories show moving mutual-flag chases, not stationary body traps. Within-side seeds 47, 49 and 51 return the Coalition flag at ticks 2267, 2134 and 2198 respectively, leaving too little ordinary travel time before tick 2400. The two-bot CTF branch sends an enemy-flag carrier toward its own flag thief but permits contact-range interception only for a defender who is not carrying. Thus the chasing carrier cannot attack that thief even when normally aimed and inside the existing 1.5 metre threshold.

Root authorized only the interception predicate and its comment in `server/src/sim.rs`, tests here and this plan. Permit the defender or actual enemy-flag carrier to defend against the same living own-flag thief. Preserve the existing distance, aim tolerance, spread, equipment, normal damage, flags, goals and movement. Prove an aimed carrying bot attacks its thief, a distant thief does not enable map-wide fire, and a teammate or unrelated opponent does not become a target. Record the regression failing before the correction, then rerun the entire unchanged four-order matrix and canonical repeat. Root owns final broad checks and the matching release rebuild after current rendered children close.

## Focused final receipts

The new contact-carrier regression fails before the predicate correction at `goal.combat`, recorded in `.agents/m06-buildout-20261001/ctf-carrier-defense-before.log`. After correction, `ctf-carrier-defense-after.log` passes, including actual normally resolved HP damage. The final fixture also checks the exact 1.5 metre exclusion boundary, a four metre thief, nearby teammate/unrelated opponent and a dropped own flag.

The complete focused CTF suite passes 24 tests with exit 0 and no failed tests in `.agents/m06-buildout-20261001/ctf-defense-and-order-final.log`. Its four-order matrix retains seeds 40 through 55, 2400 maximum ticks, at least 14 completed scored rounds and at least 8 rounds with ten visible combat-drop ticks. Exact canonical repeat assertions match all 16 complete outcome tuples. Allocation parity remains ID 5, distinct from all four players in every order.

| Fixed identity order | Completed scored rounds | Qualifying visible combat-drop rounds |
| --- | --- | --- |
| Canonical | 14/16 | 16/16 |
| Reverse | 15/16 | 16/16 |
| Within-side swap | 15/16 | 16/16 |
| Side swap | 16/16 | 16/16 |

The focused debug suite runs in 121.70 seconds on this host, after 14.76 seconds compilation. The survey is bounded to four complete fixtures plus one identical canonical repeat, 80 rounds total. Existing CI test steps have no explicit job timeout override. These are deterministic simulation and failure-boundary receipts, not fresh-player, renderer, production performance or universal random-identity acceptance. All owned debug test processes are closed. No release executable, Godot import, GPU session or native game listener was started in this lane.

## Interrupted first fixture diagnostic

The first explicit-order implementation assigned IDs 1 through 4 directly after enabling replay IDs, without advancing its allocator. Root review caught that a later allocation could alias a registered participant even though this CTF configuration does not currently allocate another actor. The owned debug run was stopped after partial matrix observations; `ctf-fixed-order-survey-first.log` is a diagnostic, not PASS evidence. The corrected shared fixture allocates all four keys through the existing allocator and verifies next-ID parity/disjointness on a separate unticked fixture for every order. The actual match's allocator remains unchanged by that assertion. No production code changed at that diagnostic checkpoint.

## Full Rust and release wire gates

The frozen source passes formatting, warning-denied workspace Clippy, all 1244
workspace tests (three existing ignored), 94.31 percent unfiltered line coverage
against the unchanged 90 percent floor, the workspace release build and
license/ban/source checks. The standalone 16-bot/1200-tick benchmark passes
determinism and budget assertions. Exact logs are the `final-*` receipts under
`.agents/m06-buildout-20261001/`; the [parent plan](m06-port-of-entry-prototype.md)
records the scoped CPU table and executable hash.

Both release CTF wire smokes pass. The route reaches one capture. The contested
four-agent sample reaches the capture limit with nine frags, two takes, one drop,
one return and one capture, under the original round and harness limits and
without opening spawn deaths. Reports are `.agents/playtest/final-ctf-route.json`
and `final-ctf-contested.json`. All owned processes close normally. This is
bounded local controller/wire evidence; four fixed identity orders do not prove
every random production identity order or human multiplayer acceptance.
