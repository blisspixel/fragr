# Supported companion stand-off

Status: in flight. Spend: $0. Base: main `2399c00d`.

## Goal and evidence

Prevent Latch from closing the participant's available walking space while
preserving real character collision. The recorded M03 north exit freezes with
two released roof captives and Latch beside the participant. Removing only
Latch from the stationary-contact mirror permits the original goal in 41
ticks. The current follower targets exact participant feet with a 0.65 m
tolerance, inside the combined 1 m body clearance. Failed QA route evidence and
its four explicit bypass points remain historical facts, not gameplay fixes.

## Bounded implementation

Reuse `mission/m02/companion.rs` for M02, M03, M04, M06 and M07. Keep finite
support shots, threat eligibility, ranges, cooldown, mission phases and the
existing Session navigation search budget unchanged. Select supported local
stand-off candidates outside body clearance. When already close, select a
safe short retreat using actual static movement and current body contact;
otherwise hold if none is valid. Candidate count and forecast steps have
fixed bounds. Existing Navigator owns longer routes and cached search.

M02 retains its exact west-forward authored slot and 0.65 m tolerance when
that slot is supported and clear. Normalizing its offset and using the new
generic hold distance caused the first workspace run's retry to die and
restart a third attempt. That failed receipt is retained. The corrected
M02-specific path passes all 39 focused M02 tests, including the unchanged
24-guard second-attempt retry, ordinary human/agent departure and Severe route.

The change adds no protocol, save shape, rules revision, input type or new
configuration. No teleport, body noncollision, damage, speed, difficulty,
geometry, civilian route or new mission gate is allowed. No art promotion.
Idle, firing and release transitions must discard stale movement intent.

## Verification and acceptance

Prove a trapped participant/captive/companion fixture with actual Session and
GameState contact integration, including the original northbound walking
goal, all bodies retained and ordinary movement. Test supported raised floors,
corners, no valid retreat, distant following, held formation, active fighting
and release/frozen/no-leader resets. Check M02's ward return and M03/M04/M06/M07
mission suites. Run workspace tests, warning-denied Clippy, formatting and the
existing benchmark assertion. Build a new owned release native in a unique
private target with two build jobs. Only after those gates, request a rendered
full M03 ordinary route lease against the exact new native and current source.
All original goals, finite supplies, named guards and departure gates remain.
Root owns full CI, package acceptance, shared index and integration.

## Local checkpoint

Corrected source `d0bf6be9` passes formatting, warning-denied workspace Clippy,
all 1,463 workspace tests (917 server library tests, three existing ignored)
and the existing sixteen-bot benchmark assertions. The owned native hash is
`7e348dc7ec1ece5604fc0f76f35ae82d28d500b7900e64e0f76a6d7283b71c63`.
Its first rendered original-art M03 route completes all 21 states, 88 ordinary
walking arrivals, 22 named guards and actual departure, with zero deaths.
The north receipt retains both captive bodies and collidable Latch through
the original goal. All four historical bypass points and two restricted
combat-travel opt-ins remain explicitly recorded, with unchanged original
goals and outcome gates. [Evidence](../evidence/companion-stand-off-20261004.md)
retains the prior failures, finite resources and inspected frames. Full client
and integration gates remain pending; this plan stays in flight.
