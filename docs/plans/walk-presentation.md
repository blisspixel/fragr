# Walk presentation

Status: **implemented** in source, 2026-10-06. Not merged. Local human walking
was stepping the predicted body on the server tick, and the first-person
camera was reading the snapshot position, so the view held still and then
jumped. No protocol change. No tick-rate change. The night server does not
draw this. Godot 4.7.2 `test_local_prediction.gd` and
`test_spectator_camera.gd` passed. The full client checker was not re-run.

## Goal

While prediction is active, the first-person view moves every rendered frame
along the same movement step the 20 Hz replay will commit. Server ticks,
Acks and damage stay authoritative.

## Non-goals

No UDP transport, no higher server tick, no change to remote pawn buffering,
and no new wire field. Snapshot fallback keeps its solid-aware camera. A
respawn, map change or dropped prediction still snaps.

## Design

`presented_position()` with no clock still returns the committed tick pose,
which the existing harness locks. `presented_position(now)` advances a
presentation pose by the elapsed frame time through `MoveStep.live_step`,
capped at one tick, without appending a speculative step or consuming the
server jump latch. A disagreement larger than the existing snap distance
returns to the committed pose. The camera follows that rendered body while
prediction is active, and keeps the snapshot eye otherwise.

## Verification

`test_local_prediction.gd` and `test_spectator_camera.gd` on Godot 4.7.2.
Spend is $0.
