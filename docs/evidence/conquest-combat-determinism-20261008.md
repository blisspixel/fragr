# Conquest composed defender-clear diagnostic

2026-10-08. Test-only correction verified locally; final native gates pass.
Spend: $0. The owning
[plan](../plans/conquest-objective-coordination-20261008.md) records the bounded
diagnostic and repair contract before source changes.

The renewed default-concurrency native workspace passes 1,951 cases with zero
failures and four existing ignored cases. The later complete instrumented run
with two concurrent tests stops with a different Conquest failure after the
three earlier readiness cases pass unchanged. Its server library records 1,350
passes, one failure and three existing ignored cases in 571.95 seconds. No final
coverage percentage was established by that failed invocation.

An unchanged existing instrumented test executable independently reproduces the
Conquest failure in 1.63 seconds, exit 101. Its assertion at
`server/src/sim/conquest/coordination_tests.rs:518` requires actual sensed shots
to kill the opposing body with at least two hits within the existing 600
simulated ticks. It fails before the later capture-stage assertions. Its diagnostic profiles are written
outside the complete coverage collector. The original test does not log the
actual bot UUID, aim, sensed target or shot totals, so their values in this
failed invocation remain unknown.

The fixture seeds the gameplay RNG before `spawn_bots` but leaves the entity
allocator on random UUIDs. Sensed observation cadence and aim error both depend
on UUID halves. Positioning also retains initial spawn facing despite the
sixty-degree sight cone. The existing CTF seeded fixture explicitly enables
replay identities before admission. These establish scenario and reproducibility
concerns. They do not establish a production controller defect.

The baseline invocations use unchanged native production and test source.
The first test-only diagnostic incorrectly
required a private participant record while the fixture's manually active match
still had round number 0 and stopped in that diagnostic. The corrected
diagnostic reads the authoritative process board counters instead. That failed attempt remains
retained as `conquest-failure-diagnostics-second.log` under the same local
receipt directory and does not replace the original defender-clear failure.
Full frozen native source is retained separately at
`.agents/presentation-stairs-composition-20261008/frozen-native-source/receipt.json`,
SHA-256 `c92327388ac0d582f4d30fd55415761f5d9d5850d91846bbd127ef64100a4c59`.
The release server remains `3dabae6ba53355fa349b11d253c83fd45ae631b8091f8ce6226ae1b79617c7d4`.

The original diagnostic executable is retained at
`.agents/stair-architecture-20261008/bin/fragr-server-coverage-conquest-baseline.exe`, SHA-256
`b6d37796624e8536aeb0c3636489825450467a1e0a70ad68691574dc855a8a95`.
The unchanged test source SHA-256 is
`9067e47a853e196295e47c93f39388da20aa81d8c08416709759dd14979fb601`.
The retained local diagnostic log is
`.agents/stair-architecture-20261008/conquest-unchanged-instrumented-diagnostic-first.log`,
SHA-256 `7ec0fb05b0a657ac3c021c3135e59ac0e5da780b4e35474843610812f392e992`.

The sampled failing UUID is `b56644a2-130f-41d8-b221-8f37b87f0892`. Its initial
yaw is exactly pi toward the defender, it observes that defender immediately,
and its correct Harbour order produces one actual Scatter head attack removing
100 HP, a resolved kill, neutralization at tick 202 and capture at tick 362.
Tickets are 200/199 and the defender has one death. The failure is the extra
`hits >= 2` assumption rejecting a legitimate one-shot kill. The exact captured
identity reproduces this same rejection through the allocator after establishing
round 1 and real private records. Source and complete failure output remain in
`conquest-retained-identity-original-guard.rs` and
`conquest-retained-identity-original-guard-fourth.log`, with log SHA-256
`b957d2609c9070c38d0a9d02c74945a3a3d7c6600216f94f58c63a526baa4bb2`.
No permanent aiming, sensing or controller failure is demonstrated.

The test-only correction fixes replay identities before ordinary admission,
establishes round 1 and explicit facing, requires an actual damaging resolved
shot and killed fact, and retains the original 600-tick budget, capture stages,
ticket debit and death count. It compares measured effective loss with validated
owner/victim private records and the live damage total. Both site stages now
also have explicit exact 160-tick checks. The captured UUID has a separate
one-shot head-kill regression with exactly 100 effective HP.

The first corrected owning run passes twenty cases and fails one new measurement
check: internal post-death HP can be negative, so unclamped subtraction counted
overkill as 130 removed HP. This was a diagnostic mistake, not evidence of extra
healing or a game defect. Its source and full log remain retained. The corrected
measurement clamps living HP endpoints and includes actual same-tick gained
health/armor pickup amounts. It never derives effective loss from raw shot
damage. All 21 owning Conquest checks pass, including the retained one-shot
identity and general replay-ID scenario. Formatting and strict workspace lint
pass against the final test source. The complete default-concurrency workspace
passes 1,952 cases with zero failures, four existing ignored cases and zero
filtered tests across 35 targets. Its server library passes 1,352 cases in
232.62 seconds. Complete unfiltered coverage also passes all 1,952 cases, with
zero failures, four existing ignored cases and zero filtered tests. Its
instrumented server library passes in 415.31 seconds. The command
`cargo llvm-cov --workspace --locked --fail-under-lines 90 -- --test-threads=2`
records 93.29% lines, 92.79% regions and 91.52% functions. The 90% line threshold,
all tests, existing ignores and actual wire/runner deadlines stay unchanged.
Two-test concurrency is explicitly separate from default native concurrency and
establishes no performance claim. No runtime production
source, release executable, map, rule, protocol, dependency or deadline changed.

The companion [receipt](conquest-combat-determinism-20261008.json) binds the exact
original, diagnostic and corrected sources, executables and logs. The corrected
test source is retained as an overlay on the complete frozen native source.
These fixtures do not establish rendered human acceptance or a new supported
server population.
