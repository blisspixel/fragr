# Campaign encounter variation

Status: planned, 2026-09-22; reviewed against main 2026-09-26. Human playtests
remain a later acceptance gate.
The [roadmap](../ROADMAP.md#full-build-order-2026-09-22) owns sequencing.
[CAMPAIGN.md](../CAMPAIGN.md) already lets difficulty change authored enemy mixes;
[replayability](replayability.md) owns why players come back overall.

## Goal

Make authored missions replayable without turning their story, routes or combat
lessons into a random arena. A saved seed must reproduce the same valid encounter
layout, and a different new-run seed may choose different, authored guard positions
or optional patrols. Difficulty can select a bounded composition after its supply
and route consequences are proved. Keep first-time threats and required weapons
predictable enough to teach.

## First increment

Add a small set of named alternate standing positions to selected later M01
guards. Keep each guard's identity and kind stable, and keep the intake lesson
fixed. Select one position from the authored choices using the run seed and the
guard's stable authoring ID. Do not consume the combat RNG, so join order and
unrelated shots cannot change the layout. A mission-start continue keeps the
same layout; a new run with another seed can change it. Log the chosen variant
without revealing unseen locations to clients. The durable run file
([campaign-run-file.md](campaign-run-file.md)) stores no seed today, so this
increment adds a layout seed to it under a new document version and derives the
same choice on restart.

Validate every candidate before readiness: finite coordinates, standing
clearance, reachable intent routes, encounter entry sightline isolation and
enough playable separation from participants. Retain bounded candidate counts
and the existing total actor/navigation limits. Reject a bad authored map rather
than falling back silently to the first position. Only validated selected bodies
enter the simulation; no client chooses a spawn or outcome.

Difficulty-based extras follow this position-only fixture. If Assisted removes a
guard or Severe adds one, the change must have explicit IDs, authored supply and
miss budgets, no required-route softlock and a new
`CAMPAIGN_RULES_REVISION`. Never increase difficulty by hiding attacks, granting
unbounded health or making the safe first lesson lethal. A visible choice of
enemy kind must use authored placements and preserve each kind's readable tell.

## Architecture and protocol

`maps/authored/encounters.rs` validates the candidate data;
`server/src/encounters.rs` selects one deterministic placement when the bounded
roster is created. `GameState` takes the layout seed from the run file, not
from the combat RNG. The selected actor remains an ordinary authoritative sim body.
No new action or wire control is needed for position variation. Difficulty
composition changes the campaign rules revision and client validation in the
same increment, with the run-file compatibility decision recorded before
changing persisted files.

## Automated and rendered acceptance

- Strict loader failures cover invalid, blocked, unreachable, premature-visible
  and over-budget candidate layouts. Every registered mission variant is prepared
  and checked, not just the selected seed.
- Different documented seeds select at least two distinct valid layouts. The
  same seed survives retry and owned-process save/restart, independent of join
  order and unrelated RNG draws. Seed and selection appear in local receipts.
- Delayed imperfect-aim human and agent controllers clear both M01 routes on
  each selected layout, including the no-secret finite-supply path. The test
  checks enemy identities, damage, actual misses and objective completion.
- A rendered first-person tour records the alternate fights and visible tells.
  Automated controls are functional and presentation evidence, not a substitute
  for later fresh-player judgment.
- Before count or kind varies by difficulty, prove per-difficulty route,
  clearance, supply and difficulty budget behavior with seeded tests and
  inspected motion. Keep human comprehension and fun explicitly pending.

Spend: $0 for implementation and local tests. Optional Jev-controlled review
uses only `agents/brain`, the existing ledger, a $5 per-run limit and the
user-approved less-than-$20 aggregate validation ceiling. Check price, quota and
remaining task spend before a paid run; no paid calls run in CI. No cloud apply or
asset generation is part of this plan.
