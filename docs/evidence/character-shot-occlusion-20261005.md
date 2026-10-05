# Character shot occlusion, 2026-10-05

Status: in flight. This is development evidence for the isolated source based on
main `400595d0`. Main and packaged gameplay are unchanged at this checkpoint.

## Original failure and resolved-fact contract

The first five real-tick tests against the unchanged production source returned
101, with one pass and four failures. Mixed human/agent teammate obstruction
already passed. Latch, spawn shields and protected-body traveling pulses were
transparent; detached or eliminated player eligibility also disagreed with the
existing authoritative contact rule. The original failure receipt is retained
privately under `.agents/occlusion-checks/baseline.log`.

The candidate uses the existing contact eligibility and actual civilian feet.
Incoming immunity controls damage separately from obstruction. Every resolved
pellet stops at the nearest intersecting eligible body before farther players,
with closer world cover retaining priority. A first body at the exact weapon
range remains eligible when the previous impact is only Range. Neutral stops
produce the existing Fighter impact, hit false, no target identity, no target
health and zero damage. They gain no health or death system.

Traveling pulses consume their finite point on the same living bodies. A nearer
fighter can replace a farther neutral intersection, while a fighter behind the
neutral body cannot. Latch's finite support preflight includes eligible living
blockers, including shielded participants. Committed projectile ownership and
explosive self damage keep their existing lifecycle.

## Focused results and retained failures

The first corrected core passed seven tests. The existing traveling-shot suite
passed thirteen tests and the focused companion selection passed sixteen.
The expanded core then passed ten real-tick tests, covering all six gun families,
both companion firing directions, real Jammer fire, shields, mixed controller
roles and friendly-fire settings, inactive bodies, real M04 patients and shared
readiness. The neutral-impact client harness exited zero, had clean diagnostics
and passed its own marker. It proves a visible world impact and no damage marker.

Two intermediate direct-pulse tests failed because diagnostic feet placement
retained unrelated spawn facing. Setting explicit test facing corrected those
fixtures; ordinary Jammer fire already passed and production behavior was not
altered for the test. A subsequent invocation read incomplete shared neutral
registration files and failed compilation. Both receipts remain retained. These
are distinct from the original production penetration failures.

The final focused core passes fourteen real-tick tests, including an actual
zero-spread Shiv endpoint/outside control, a real M04 pulse lane with a Union
fighter in front of the neutral body and another participant behind it, and
the two M02 figure cases below. The initial front-fighter fixture incorrectly
expected damage to a friendly participant; replacing that fixture with the
actual Union Clerk retained the existing immunity rule. That failure is kept.
The private receipts are `m02-v2-shot_occlusion.log` and
`m02-v2-m02-tableau.log` under `.agents/occlusion-checks/`.

The unchanged traveling-shot suite passes thirteen tests, companion selection
passes sixteen and the grenade suite preserves shielded-owner self damage.
Denied-warning workspace Clippy and formatting pass. Full workspace, matching
client checks and the ordinary rendered witness were pending at source freeze.

The first complete workspace attempt retained one real consequence:
963 server tests passed, one failed and three were ignored. A shielded participant
now intersects the Notary's real burst, so the old photograph predicate counted
that protected target. The bounded follow-up restores the existing positive
spawn-shield exclusion only at the photograph fact boundary. The body stays
opaque and the burst remains real. Its existing target wire has hit true with
zero damage and unchanged HP; neutral contacts still have no target and hit
false. The owning test now observes actual emitted bursts, zero photographs,
zero participant damage and an untouched rear agent, retaining dry and invalid
target controls. `photo-preservation-v3.log` passes that real fixture. The first
full failure and later diagnostic fixture mistakes remain retained. The final
locked workspace suite on `d8ed5b14` passes: 964 server library tests, eighteen
server binary tests and all remaining workspace and documentation tests. The
three existing ignored server tests remain unchanged. Formatting,
denied-warning workspace Clippy and the matching release build also pass.
Receipts are `workspace-v5.log`, `fmt-v5.log`, `clippy-v5.log` and
`release-v5.log` under `.agents/occlusion-checks/`. The complete matching client
checker exits zero with clean errors and its aggregate PASS: 266 parsed scripts
and 126 passing harnesses. Its retained receipt is `full-client-v1.log`; the
frozen-source and native receipt is `full-client-source-v1.txt` in the same
directory. The only later changes are this evidence and its owning plan.

## Visible provisional figures

The companion and existing moving civilian contact owners are reused. Archive
registry and captive sprites, the lunar family window and the curfew resident
have a separate registration pass that derives shared body positions from
validated map panels and current mission facts. Its strict boundary, placement
goldens and client prediction are independent acceptance evidence.

The passive M02 Notary remains behind actual world cover. Its complete source
vertex radius, full yaw sweep and bob envelope fit the real sealed bay. The
owning native test partitions each boundary face at all actual solid edges to
prove complete face coverage, includes elevated and off-axis rays, and fails
when the real inspection glass is removed. It adds no airborne human capsule.

The second captive uses twelve shot-only boxes matching the existing figure's
actual source parts, including its 2.06 m top and rotated parent. The inherited
12 cm opening translation follows authoritative companion phase-start and
snapshot ticks. The shared source helper and committed goldens prove all twelve
actual rendered transforms at closed, half-open and open placement. These parts
do not become world cover, floors or twelve extra walking solids.

Before a real companion exists, the restrained Latch figure has the ordinary
neutral body envelope at the validated restraint frame. The first real
Releasing snapshot removes that figure and shows the actual stationary pawn at
its authoritative second-bay feet. The 240-tick phase, input and dialogue stay
unchanged. The owning native tests prove one spawn, exact body takeover and an
immune shot stop before a rear participant. The client Ward and new tableau
harnesses pass cleanly; the existing transition strip now requires the real
pawn visible during Releasing while retaining exact phase length and order.

The first M02 compile failed on private field access in diagnostic tests and is
retained as `m02-core-v1.log`. Tests now use RuntimeMap's real arena accessor.
An intermediate Clippy failure on test-only Notary measurement metadata is
retained; that field is now explicitly test-only. No warning policy was relaxed.

## Ordinary release witness and companion size audit

The ordinary M02 witness completed thirteen states with renderer exit zero,
clean error diagnostics, no timeout and confirmed owned-process cleanup. Its
first twelve states retain the canonical ward combat, equipment, walking, use
and release assertions. The last state uses a diagnostic observer camera and
twenty-four actual frames to observe the authoritative release. Releasing began
at tick 1032 and Following began at 1272, preserving the exact 240-tick phase.
This is a bounded release witness, not a full mission clear or an independently
aligned rear-target shot test.

The real pawn was visible and the old ward figure hidden during every observed
Releasing snapshot. It used `LatchView` and
`res://assets/models/latch_stylized.glb`, with one weighted source mesh, one
active normal material and no source Sprite3D. The packaged source SHA256 is
`8b1ec57399ec51a70617a42c9777a04347170d5ddf78dc54b67649b3f6992951`.
Following observations record actual changing authoritative and interpolated
positions, rather than a locally moved substitute.

A separate passive scale audit follows the actual skin's named bind poses,
weighted vertices and live parent transform. It measures a 1.799972 m chassis
height, with feet at floor zero and top about 1.80 m when the authoritative pawn
center is 1.5 m. The imported armature's 0.01 transform alone is not the rendered
size because the skin binds compensate it. The audit changes no model, camera
or scale. Its initial type and incomplete bind-mapping diagnostics remain
retained; the corrected audit is numeric zero with clean errors. The live model
has adult physical scale, but this does not establish accepted appearance.
The downward observer camera can reduce apparent stature, and the foreground
figure in state thirteen is the second captive, not a close-up of Latch.
State twelve shows the actual lean companion beside the restraint bay.

Private evidence is retained under `.agents/m02-shot-witness-first/`, including
`manifest.json`, `process-receipt.json`, `companion-body-source.json`,
`latch-scale-audit.json`, `12_latch_release.png` and the final transition strip.
The exact map SHA256 is
`313441acf6fe2026b9809872e79464c3f6bad0a7b04fc897de4507d68b2e3549`,
route SHA256 is
`e6e9f1a5da95281abaef3ef2ea0cd273a880d32530625e6a48a5baca45c0cf98`,
and matching immutable native SHA256 is
`e7bd9003795bb438e88f553d6fb1ac4ac9c44c33989ad4d737caf4abe23bae2b`.
No artwork overlay was used. Renderer 27780 and server 31452 were both retired.

No paid operations, weapon artwork selection, NPC deaths, damage thresholds or
campaign completion requirements change in this lane. Local source, native,
client and bounded release evidence pass. Final composed-source review,
exact-head CI and desktop packages remain required before publication.
