# Passenger Manifest crew departure and transit

Status: planned, 2026-10-04. Isolated from frozen Repeater PR 358 at
`3991bf90`. No implementation, wire revision, save revision, paid request or
rendering is claimed. This is a bounded prerequisite inside the existing M10
campaign rung, not another global build order.

Nick accepted released eligible crew finishing boarding during a short
authoritative departure transition while the player moves on. There is no
escort wait. Release, feet aboard at confirmation and later transit arrival
remain separate facts. Historical missing crew outcomes stay unknown.

## Existing authority and missing boundary

`mission/m09.rs::advance_m09` already requires the actual ordered objectives,
fresh physical Use and all ready living participants inside the hatch region.
It captures the actual finite player exit and marks the mission Departed and
the solo run Complete. Preserve those gates unchanged.

`advance_m09_crew` uses supported movement and shared living contact, and only
runs while InProgress. Each current `M09CrewState.aboard` comes from actual
feet inside the open hatch's boarding region. After departure it stops; merely
setting that flag true would invent a berth arrival. The accepted old route's
zero-aboard receipt must remain exact.

`campaign_run_document` retains earlier outcomes and the actual exit through
the existing locked writer, but has no M09 crew outcome. `promote_next` supports
only through M09; completed M09 honestly awaits unplayable Common Carrier.
There is no existing post-departure transit state to reuse without an explicit
new private contract. M10 geometry and readiness cannot be asserted built.

## Smallest implementation checkpoint

First capture and persist an immutable M09 departure receipt, without changing
current live mission facts or claiming transit finished. Capture the actual
present roster and released IDs from M09 progress, and the subset whose real
feet are aboard at accepted confirmation. Copy this receipt at the same
accepted transition as the finite exit; later ticks, optional crew movement
and document retries cannot resample or rewrite it.

Proposed private outcome:

- `Recorded`: canonical present/released crew IDs, actual aboard-at-departure
  subset, and explicit pending transit. Validate unique bounded IDs and order,
  aboard subset of released, all mandatory released crew, and the accepted
  Edda/Splice eligibility against recorded earlier outcomes.
- `HistoricalUnrecorded`: absence of historical M09 facts, produced only by a
  legitimate strict old-document upgrade for an actually completed M09.
  Never generate synthetic zero-aboard or assumed released sets.

Present and released need not be separate serialized lists if one validated
immutable canonical roster plus the mandatory release gate proves the same
fact without redundancy. Review the exact shape before coding. Native new
completed M09 requires Recorded; earlier stages must refuse any M09 outcome.

This first checkpoint adds no wire field, so M09's current strict facts and
capability requirement can remain unchanged. Any later emitted transit fact
needs its own reviewed capability for every role before delivery, with
MapInfo-before-facts and strict client validation. Do not allocate a number
silently or change Repeater's capability 35 contract.

## Actual transit completion checkpoint

Complete the accepted short transition at the canonical M09-to-M10 handoff,
once that destination and its real entry are implemented. The same locked
promotion transaction retains the departure receipt and records a distinct
transit-completed aboard set for actually released eligible crew. The M10
presenter can then place those actual arrivals in its inhabited ship context.
This is a mission transition, not teleporting live berth bodies or making
players wait for a fifty-second walking route.

No new companion tool, save path, client authority or story-dismissal callback
may grant arrival. The known transition completes once; failed writes, reopen
and repeated promotion cannot duplicate crew or refill health/ammunition.
The future Episode III continue refill remains exactly once and belongs to
M10 promotion, not this capture checkpoint. M10 retry anchors its actual entry
and already-completed transit, without rerunning departure or another refill.

HistoricalUnrecorded stays unknown through that handoff and retry. Do not
reconstruct an old crew receipt from later room markers or known M04/M05
eligibility alone. Any unconditional pilot story staging needs an explicit
authored appearance rule, without relabeling unknown rescue/transit history.
Optional missing crew never gate the living player's completion.

## Strict storage review

The foundation prepares save version 11. Adding the private M09 outcome needs
a separately reviewed next version and an exact strict v11 reader, preserving
strict v10 and earlier readers and original-byte archives. This plan reserves
no number. Legitimate v10/v11 completed M09 upgrades become
HistoricalUnrecorded; old earlier stages retain no M09 outcome. Older formats
that never supported playable M09 cannot forge such a completion.

The native new writer cannot use unknown as an escape from validating an
actual new departure. Forged roster, duplicate IDs, impossible optional cast,
aboard-without-release, earlier-stage outcomes and unbuilt transit-completed
shapes must refuse. Old readers refuse new fields in old versions. Keep real
HP, armor, gun ownership/selection, Bullets and independent grenade/mine
counts exact, with no format-driven refill and no Repeater forged into ≤M09.

## Acceptance and owned seams

Own narrow private M09 transition capture, the solo recovery/run-file outcome,
strict legacy/store migration and focused inline tests. No changes to frozen
PR 358, global roadmap/index/catalog, M09 geometry, encounter roster, optional
charge challenge, present crew movement or physical Use are needed.

Before claiming the capture checkpoint:

1. Actual GameState completion with zero/some/all real crew feet aboard and
   all four Edda/Splice eligibility rosters. Reject incomplete, stale Use,
   partly ready/dead party and held crew. Preserve every ordinary guard gate.
2. Capture once, then mutate live presentation/feet and prove the departure
   receipt and exact finite exit do not change on later document generation.
3. Save, reopen and repeat under the real writer lock; exact v10/v11 byte
   archives, historical unknowns, forged fields and earlier-stage refusal.
   Failed pre-replacement write preserves the original document.
4. Matching private native, focused local-child lifecycle and relevant complete
   native/client checks. No additional route rendering is claimed for a
   persistence-only change; final M10 transition needs actual played evidence.

Before claiming accepted boarding implemented, also prove actual M10 promotion,
short transition/readiness, interrupted/repeated handoff, known/unknown retry,
no escort delay, no refill/duplication and truthful destination crew presence.
The capture checkpoint alone cannot satisfy those later gates.
