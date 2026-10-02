# QA Turret peek timing

Status: implemented, focused headless gates and actual rendered capture passed.
Final full client checks, CI and release pending.
Updated 2026-10-01.

The final material capture reached the strict Turret cancellation gate but did
not prove it. The second charge began at tick 3052 after ordinary movement had
already placed the participant behind registered cover. Recovery at tick 3053
lasted the genuine twelve ticks, but the observer correctly refused a charge
whose first emitted Windup snapshot was blocked. A static walking loop depends
on render timing to expose the clear-to-blocked transition.

## Bounded ordinary-input correction

Retain the existing initial front sweep and its resolved first shot and Firing
requirements. Append a clear peek at [0, 0, 12] and a retreat to [0, 0, 10] before
the existing supported stair route. The participant walks normally to the peek,
waits there for an accepted live clear Windup, retreats using ordinary movement,
and waits at the covered point until the existing observer proves cancellation
through the original charge deadline plus one tick. An already proven
cancellation permits normal progression through both ordinary waypoints.

Use an optional `turret_peek` object containing integer `peek_index` and
`cover_index`, referencing adjacent existing approach-route positions. The M06
specimen uses indices 4 and 5. Reject extra fields, noninteger or negative
indices, out-of-range indices, nonadjacent positions, missing or invalid routes,
and use without `expect_turret_cover_cancel: true` and its matching named
`approach_focus`. Every other specimen keeps the existing route behavior.

At a reached referenced point, retain focus-camera updates but do not advance
the approach index until its observer condition passes. Keep the ordinary
anchor while holding, then refresh it through the existing arrival path when
advancing. Before arrival, the existing movement and defense selection stays
unchanged. An unfinished approach cannot fire. No special position, tick,
health, inventory or outcome changes are allowed.

Expose only read-only observer queries for an already proven cancellation and
an active accepted clear Windup. The latter must refer to the latest consecutive
snapshot of the same living named actor and cycle, with unchanged HP, in range,
clear center sight and no resolved shot. Require at least twelve ticks remaining
before its original deadline so a nearly completed charge cannot trigger the
retreat. These queries never create or complete a candidate. Preserve every
existing observer assertion, including clear phase-start evidence, the prior
blocked consecutive Windup snapshot, real twelve-tick Recovery, exact original
deadline, unchanged HP, no named resolved shots and one participant body.

## Geometry evidence

The independent actual-map slab review checked every solid in the frozen
Port of Entry definition. From the intro Turret feet [-18.5, 3, 16], with eye
height 1.6 and participant center height 0.9, the peek has clear center sight.
The retreat point is blocked by `charge_cover`, solid 62, at x -10 to -7,
z 10 to 13, height 3. Both points are inside the existing 32-metre sight range.
At x zero the sight edge is approximately z 11.173913.

The complete two-metre walking segment has ground support at height zero and
no standing swept-volume solid or authored enemy start. At five metres per
second and twenty ticks per second the ideal retreat takes eight ticks, leaving
eighteen ticks of the normal twenty-six-tick charge. Focused tests must also
exercise the actual strict arrival radius and quantized ordinary controls,
rather than infer movement from this ideal calculation.

## Verification and handoff

Before implementation, the current M04 capture must close and the parent must
grant the serialized headless/import lease. Focused existing harnesses must
verify strict optional-schema parsing, actual clear/blocked map sight, ordinary
retreat and support, production approach holds and release, index bounds,
unchanged normal-route behavior and unfinished no-fire behavior. Observer
tests must retain all existing negative receipts and prove that read-only
queries cannot turn blocked-start, fired, stale, gapped or changed cycles into
success. Clean exit, clean error logs and each own PASS marker are required.

The ordinary rendered M06 tour must still prove all twenty-five states and
twenty-one guards, Windup, Firing, Dead, resolved first shot and the original
strict cover cancellation within its unchanged twenty-five-second combat
deadline. Parent owns the full client checker, inspected screenshots, protected
main CI and release. No paid calls or external spend are involved. The failed
receipt remains under `.agents/m06-material-wrap-20261001/` as diagnostic
history; no later success may be inferred before the actual wrapper closes.

## Implementation and focused evidence

The optional schema and read-only observer queries are implemented. The
production approach method retains camera focus and holds its existing index
and anchor at a reached peek or covered point until the relevant query passes.
It still walks normally before arrival. A cancellation already proved by the
initial sweep permits normal advance, and all unspecified routes retain the
previous approach behavior.

The actual-map harness checks every registered solid for the clear peek ray and
binds the covered ray to solid 62. Five starting offsets inside the unchanged
arrival disk retain clear sight and reach a blocked covered arrival in at most
nine ordinary ticks, with the shared actor-contact resolver and actual ground
support. This leaves at least three ticks within the twelve-tick minimum
remaining-charge rule. That rule refuses a charge with eleven ticks left.

Production control tests exercise a held idle peek, accepted clear charge,
ordinary unfinished retreat, held covered Recovery and release only after the
original deadline plus one tick. No held or unfinished point fires or creates
movement grants. Schema tests reject malformed types, extra keys, nonadjacent
or out-of-range references and missing observer/focus requirements. Observer
tests retain every existing rejection and additionally check blocked-start,
blocked-current, missing tick, shot, damage, death, range and changed-cycle
control hints. Queries cannot mutate retained evidence or use another tick.

Pinned headless `test_qa_combat`, `test_qa_turret`, `test_m06_mission` and
`test_m06_presentation` pass with clean logs and their own PASS markers. Both
changed QA source scripts parse cleanly, import is clean and `git diff --check`
passes. Receipts are under
`.agents/m06-buildout-20261001/qa-turret-peek-*.log`. Initial diagnostics retain
a corrected mixed-type schema comparison and a corrected JSON numeric fixture
comparison; an attempted nonexistent harness invocation is also retained and
is not counted as a passed check.

The map bytes remain SHA256
`627e9bcecaa231fdc3a5df8297ac872e975b41c31b7ae872d4a4ce1c25e4a9a5`.
All owned headless processes closed before returning the serialized lease.
The actual rendered cancellation receipt, full checker, CI and release are
still parent-owned gates. There were no provider calls or external charges.

## Actual peek and cancellation receipt

The `.agents/qa/m06-port-peek-final/` run passes all 25 states, all 21 named
guards and server-confirmed transit departure, with exit 0 and a clean engine
log. The named intro Turret has visible Windup at tick 3064 and unchanged
100 HP. Ordinary retreat puts the participant behind registered cover during
Windup at tick 3067, the exact snapshot used by the next AI decision. Recovery
begins at tick 3068 and ends at 3080, its real twelve-tick cancellation interval,
before the original charge deadline 3090. The observer retains unchanged
Turret HP and no registered shot through tick 3091. These same-cycle facts
prove the causal clear-to-covered cancellation, not merely a successful route.

The same probe also retains the actual first resolved attack and captured
Firing at tick 3018; later ordinary rear-flank shots defeat the Turret, with
Dead captured at tick 3310. No phase, tick, HP, position or outcome was forced.
Actual attempt records report zero deaths, 25 HP lost, 125 armor lost and two
secret claims, with all three locations visited. The prior blocked-start
cancellation refusal remains a failed diagnostic, not a successful receipt.
The M04 eighth 23-state/28-guard tour also passes with the current shared helper;
its separate authored-route and target corrections are documented in
`m04-capture-patient-detour.md`.

## Current workspace verification

Root's final serialized `cargo fmt --all -- --check` and workspace Clippy
with warnings denied pass. `cargo test --workspace --locked` passes 1,244
tests with three existing ignored tests and no failures. Exact receipts are
`.agents/m06-buildout-20261001/final-fmt.log`, `final-clippy.log` and
`final-workspace-tests.log`. The rendered tour receipts prove their recorded
helper/assets and server hashes; they do not claim a newly rebuilt release
binary. Coverage is running, and the final matching release rebuild, broad
serialized Godot checker, CI and release are still pending. No shipped claim
or fresh-player acceptance follows from these bounded authoring gates.
