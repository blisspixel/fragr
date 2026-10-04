# Bound played capture pitch to the authoritative limit

Status: **implemented**, 2026-10-04. Combined integration remains pending.

## Problem and scope

`QaTour._set_aim_pitch` assigns and waits for a raw angle. Its derived
`look_at` angle can exceed the 85-degree server limit when the human is
standing beside a floor supply. Camera output and the server correctly clamp
the sent angle, so the helper waits for an impossible acknowledgement.
The final Latch art route recorded two such failures; exact historical desired
and observed angles were not logged. Replay is required to confirm causality.

Normalize the helper's target once to the existing `ServerYaw.PITCH_LIMIT`.
Preserve the five-second deadline, 0.001 acknowledgement tolerance, declared
`expect_pitch` assertions, server math and human gameplay. Include desired and
observed angles in future failure diagnostics. No protocol, map, authority,
equipment, timing or asset changes belong here.

## Verification

Exercise the real setter with local-human snapshot fixtures at both vertical
extremes, exact limits and ordinary angles. Verify the actual camera target
agrees with accepted pitch. Preserve existing native and client pitch tests.
Run focused checker tests and the whole-client gate. Then replay the same
24-state supply-aware M02 route without changing its bytes, assertions,
difficulty, actor outcomes or finite resources. Retain every earlier failure.
Source regression and full played-route acceptance are separate results.

## Spend and integration

Local work costs $0. No external asset call, cloud action or new dependency.
Integrate through the same short-lived combined branch; fresh CI remains
required before main changes. This plan adds no second build order.

## Actual evidence

The real setter regression exercises both vertical extremes, exact limits
and ordinary angles, the actual camera input and the local human's snapshot
despite a decoy other participant. Focused checks pass. Removing only the
normalization line makes both vertical extremes fail with the unchanged
0.001 tolerance and no script errors or leaked test resources.

The archived 24-state M02 route was replayed with identical manifest bytes,
native, map and finite supplies. The near-floor pitch acknowledgement now
passes. The route then correctly rejects actual participant death during
crossfire; it is not a completed mission. Full receipts and retained failures
remain separate from this checker correction in the
[Latch plan](latch-live-mesh.md).

## Main integration

The implemented slice ships with the combined main integration of
[PR #348](https://github.com/blisspixel/fragr/pull/348).
[Combined evidence](../evidence/game-buildout-20261004.md) records local checks;
fresh implementation and desktop-package CI remain required before publication.
Wider acceptance limits recorded above remain open.
