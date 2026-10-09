# Conquest objective coordination

**Status:** implemented, 2026-10-08. Bounded server behavior increment with local
verification in the [receipt](../evidence/conquest-coordination-20261008.md).
Repository composition, population, balance and human play acceptance remain open.
The later instrumented run exposed an overstrict defender-clear test assertion.
The bounded test-only correction below preserves its actual one-shot failure as
a regression. Complete native, unfiltered coverage, strict lint and formatting
now pass; rendered human acceptance remains separate.

The prior Conquest rule bot chose an ordinal among its own nearest three
sites. Each bot ordered that list independently, and dead or waiting teammates
still affected the ordinal. It had no shared assignment memory. A roster change
could redirect a bot that was already capturing, and a threatened owned site had
no priority over an empty neutral site.

Build one coordinated infantry objective pass for the existing five-site
Conquest match. Preserve the accepted eight-second capture and neutralization,
contest, decay, death debit, majority bleed and ending arithmetic. Preserve
ordinary Action control, sensed combat, physical movement, vehicle hulls and
Session's staggered limit of four navigation searches per tick.

## Implementation boundary

- Keep private assignment memory on GameState. Reset it with Conquest state,
  and compute it once from Session's existing controller slice before bot intent.
- Admit only living, active, attached contestants with a side and no vehicle
  seat, using the existing contact eligibility seam. Living humans, agents and
  exposed vehicle occupants continue to contribute ordinary site presence.
- Retain bots already contributing useful capture or defense. Fill threatened
  owned sites first, then active captures, other uncaptured sites and quiet
  guards. Existing useful incoming assignments win stable ties; new assignments
  use distance and the existing controller order. Additional bots do not change
  capture speed.
- Bound work by the player/controller roster and the fixed five sites. Do not
  add pairwise routing, path searches, a new player cap, protocol facts, client
  decisions, vehicle driving or another mode.
- Own server/src/sim/conquest.rs and its new coordination/test modules. Shared
  edits are the private field/default in sim.rs and one Session planning call.
  Root owns the plan index, README and ROADMAP.

## Verification before local completion

1. Regress the current nearest-list/ordinal failure with a bot already capturing
   while another teammate spawns or respawns, and a threatened owned site.
2. Verify eligible and ineligible participants, seated occupancy, stable ties,
   exhausted demand and assignment reset. Observe the complete 64-controller
   planning workload without claiming a new supported population limit.
3. Exercise real GameSession controller ticks and shared movement into sites,
   contest/defense, capture/neutralization, majority ticket bleed and an exact
   winner. Include ordinary roster admission/respawn and obstruction failure.
   Initial test positioning is a fixture, not evidence of crossing the island.
4. Run focused locked native tests and lints. Root composes wider gates after
   source freeze. A rendered human match and final map art/balance remain open.

## Limits

This work uses no paid service, new asset, dependency, transport or infrastructure.
It does not promote the Conquest prototype to final acceptance or change campaign
missions. Record exact passing checks and any narrower test evidence here after
implementation, retaining unresolved human play and final art gates.

## Local evidence

Twenty focused tests pass, including fourteen new coordination regressions and
the six retained Conquest checks. Both original selector failures were observed
before implementation. A three-bot Session match moves from bounded approach
fixtures, captures all five sites and exhausts the full opposing 200 tickets at
tick 2179, with Union retaining 200 and no deaths. A sensed defender fight resolves
two hits, neutralizes at tick 214 and captures at tick 374. A separate ordinary
withdrawal freezes an actual contest for thirty ticks, neutralizes at 225 and
captures at 385. A teammate's resolved death and ordinary sixty-tick respawn,
followed by new bot admission, preserve another bot's capture from progress 40
through 102. Parked hulls refuse an assigned capture for 200 ticks; opening one
fixture hull allows ordinary walking and capture.

The 64-controller planning fixture records 2131 counted planning steps on its
first pass and 2121 on each reordered subsequent pass, below the 2432-step
instrumented bound. It retains the same assignments and distributes 13, 13, 13,
13 and 12 bots. These counts cover site candidate, retention and comparison
steps, not all CPU instructions or networking. Production planning is linear
in the roster with five fixed sites and at most 32 vehicle seat records. It
performs no navigation searches. This is an offline assignment fixture with
overlapping initial bodies, not a 64-player match or server population claim.

`cargo test -p fragr-server --lib --locked sim::conquest -- --nocapture` passes
all twenty tests. `cargo clippy -p fragr-server --lib --tests --locked -- -D warnings`
passes. Root owns the subsequent composed repository gates and documentation
index. No renderer or new release executable was used for these focused checks.

## Composed defender-clear investigation

Status: **implemented**, 2026-10-08. Spend: $0. Preserve the current release and
complete frozen source before any test repair. The complete bounded-concurrency
coverage run and an unchanged instrumented single-case diagnostic both fail
`sensed_ordinary_attacks_clear_a_defender_then_finish_both_capture_stages` at its
actual shots/death assertion. The single case takes 1.63 seconds and is not an
elapsed-deadline failure. The [diagnostic receipt](../evidence/conquest-combat-determinism-20261008.md)
retains this baseline and its limits.

The fixture seeds gameplay randomness but does not enable replay identities
before normal bot admission. The allocator therefore uses random UUIDs, while
bot observation timing and aim error depend on those UUIDs. Initial positioning
also retains spawn facing despite the sixty-degree sight cone and a planner
that can choose other sites. These are concrete scenario and reproducibility
concerns, not proof that identity normalization fixes the behavior.

After the complete failed run retires, add bounded test-only failure diagnostics
for the actual bot/defender identities, initial and current feet/facing, first
visible observation, sensed target, issued attacks, resolved hits, finite
ammunition, current objective order and site progress. Preserve a sampled failing
UUID and exact source/log receipts before changing fixture identity. Keep the
original 600-tick budget, actual shots and death, both full capture stages,
ticket debit and death count.

Use the existing replay allocator for a truly fixed-seed fixture, preserving
normal roster admission, body, team, weapon and controller paths. Do not select
a passing identity. Establish the visible-defender scenario the test claims,
regress any retained failing UUID and determine whether observation cadence or
aim can permanently prevent an ordinary stationary defender clear. Any
demonstrated production defect requires a concrete bounded patch scope and
causal original/fixed proof before native production changes. Keep routing,
combat, magazine, neutralization and capture rules intact.

Run the complete owning Conquest checks, default unfiltered native workspace,
unfiltered coverage with explicitly recorded concurrency, strict workspace lint
and formatting after the repair. Preserve every failed attempt. No protocol,
dependency, map, asset, paid-service or rules-version change is planned.

The captured failing identity is `b56644a2-130f-41d8-b221-8f37b87f0892`.
It starts facing the defender exactly, observes it immediately, receives the
correct Harbour order, deals exactly 100 effective HP damage with one actual
Scatter head hit, kills the defender and completes both site stages. The
additional `hits >= 2` assumption rejects this legitimate one-shot kill. No
controller defect is demonstrated by that failure. Reproduce this identity
through the allocator with the original assertion before correcting the check
to require actual damaging shots and death, exact effective record agreement
and the unchanged capture, ticket and death facts. Keep an explicit one-shot
head-kill regression alongside the default replay-ID scenario. The fixture's
manually active match must establish round 1 to expose its real private records;
its former round 0 explains the earlier diagnostic's missing record.

The bounded test-only correction passes all 21 owning checks, formatting and
strict workspace lint. The general scenario uses the default replay identity;
the captured failing identity remains a separate one-shot regression. Both
require exact measured effective loss, validated owner/victim records, live
damage agreement, real shots and death, and both full 160-tick site stages.
The complete default-concurrency native workspace passes 1,952 cases with zero
failures, four existing ignored cases and zero filtered tests. Unfiltered
coverage also passes all 1,952 cases at 93.29% lines above the unchanged 90%
threshold, with explicitly recorded two-test concurrency. Every test, existing
ignore and actual wire/runner deadline is retained. Regions are 92.79% and
functions 91.52%; the instrumented server library passes in 415.31 seconds.
All earlier failed
runs and diagnostic limitations remain bound by the receipt. Production source
and the retained release executable are unchanged.
