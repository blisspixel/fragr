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
client checks and the ordinary rendered witness remain pending at source freeze.

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
full failure and later diagnostic fixture mistakes remain retained. Final full
workspace and matching client results are still pending.

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

No paid operations, weapon artwork selection, NPC deaths, damage thresholds or
campaign completion requirements change in this lane. Final exact-head CI and
desktop packages remain required before publication.
