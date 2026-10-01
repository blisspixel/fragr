# M03 server prototype

**Status:** implemented locally, 2026-09-30, integration tracked under
[`m03-scheduled-service-prototype.md`](m03-scheduled-service-prototype.md).

The later [M04 prototype](m04-notice-to-vacate-prototype.md) supersedes this
plan's initial live capability 24, rules revision 2 and save version 4 contracts.
The later [M05 prototype](m05-no-forwarding-address-prototype.md) requires
capability 26 and rules revision 3 for current authored missions; compatible
historical saves upgrade explicitly to version 6. Earlier receipts below retain
the versions actually tested.

## Goal and architecture

Build Scheduled Service through the existing authoritative mission, combat,
encounter, navigation and companion seams. Add strict M03 authoring and wire
facts, a registered shoot objective, optional automatic car liberation and a
deliberate shared locomotive departure. The map is a development prototype,
not finished campaign acceptance.

Mast damage uses resolved participant pellet impacts against the registered
transmitter solid after its defenders clear. Prepare intact and fallen worlds
before readiness. Optional cars change presentation facts, not collision worlds.
Latch follows the existing companion control path. Readiness, retry and physical
Actions remain the only control door; MCP receives no new combat tool.

## Ownership and protocol

Own `protocol/mission.rs`, M03 authored and runtime map support, mission runtime
and shared controller, minimal resolved-impact/companion hooks, encounter reset
integration and dedicated tests. Coordination owns global MapInfo envelope,
capability 24, save version/migrations, launch, client and documentation index.
Map and client lanes consume the agreed strict schema. M01/M02 authored bytes
and existing enemy difficulty timing remain unchanged.

## Verification and success criteria

Prove genuine pod impacts, cover/body occlusion, pre-clear refusal, optional-car
independence, readiness, explicit all-party departure, consumed early presses,
retry reset and agent navigation/aim/fire through seeded ticks. Validate both
worlds and reject invalid references, approaches and routes before admission.
Run focused tests and server Clippy, then defer coordinated full checks and
rendered captures to the parent plan. Record failures and results here.

## Spend and non-goals

Planned and actual external spend: $0. No new runtime, dependencies, paid assets,
cloud, driveable train, M04 gameplay or fresh-player acceptance claim.

## Work record

- Read current campaign contract, accepted level 3 treatment, mission runtime,
  authored loader, shared control and save promotion seams before implementation.
- Added capability-24 mission facts and strict authoring with at most four cars,
  one registered pod and exactly two prepared collision/navigation worlds. Mast
  shutdown preserves solid indices and content identity, changes the actual
  world and switches the schedule board to its cancellation state.
- Resolved pellets retain internal solid identity. Only an active participant's
  actual pod-face impact can damage its 40 HP after the mast encounter clears.
  Existing fighter damage, enemy timing and campaign rules revision 2 remain.
- Added automatically liberated cars gated by their own cleared encounter and
  a living ready participant approaching. Captives walk grounded held-to-safe
  segments; released identities are exposed for the durable completion outcome.
  Optional liberation never blocks deliberate all-party train departure.
- Reused Latch's bounded support and following controller. Mission readiness,
  physical Actions and mission continues remain the existing control doors.
- Shared mission controllers bind Shoot and Use to authored geometry, reject
  progress rewind and off-segment captive facts, and stop stale Shoot intent
  between fallen MapInfo and its subsequent mission observation.
- `cargo test -p fragr-server --lib tests::m03 --locked -- --nocapture` passed
  all 11 focused tests. Evidence includes actual cover and friendly-body
  interception, pre-clear refusal, invalid impact identity/face refusal, optional
  liberation and walking, reset, final-fight and whole-party departure gates,
  strict wire facts, shared-controller navigation/aim/fire, both bundled worlds,
  and real-socket capability 23 refusal plus capability 24 geometry ordering
  for humans, agents and spectators.
- `cargo clippy -p fragr-server --all-targets --locked -- -D warnings` passed.
  M01/M02 map bytes have no working-tree changes. Full checks and rendered input
  evidence belong to the integration plan; fresh-player and difficulty
  acceptance remain open. External spend remains $0.
