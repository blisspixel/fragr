# Replayable movement Ack v1

Status: implemented in draft PR #286, 2026-09-28. Branch: `feat/movement-ack-v1`, stacked after the [live movement step](live-movement-step.md). The implementation began from that branch at `95641bd`.

## Goal

Give a future human client a validated, complete 3D baseline for each server movement tick. Keep the existing WebSocket Action and Ack root fields compatible. Define how one server tick selects the latest sampled Action and consumes a latched jump. This rung does not move the local Godot pawn from prediction.

## Contract

The server processes Action commands in its game loop. One active 20 Hz tick uses the latest continuous Action applied before `GameState.tick`; it can reuse the same Action on later ticks. Weapon choice persists until a tick consumes it, and any jump press since the last active movement step is latched. The effective jump bit is `pending_action.jump || jump_requested` at movement integration. It is a request to the integrator, not proof of takeoff. An Action `seq` identifies a sent sample, while Ack `tick` identifies the server step. Multiple sequences can be skipped, and one sequence can appear in several consecutive Acks.

The root Ack `{seq,tick,x,z,yaw,pitch}` remains. An optional `movement` object at schema version 1 adds `{version,epoch,applied,y,vx,vy,vz,effective_speed,jump_input}`. Position `y` uses the same world reference as `Snapshot.players[].y`, while `vx/vy/vz` are post-collision units per second. `effective_speed` is the speed selected for that step before collision. `jump_input` is the OR-latched request passed to the integrator. `applied` is false when the tick did not run a movement step for that pawn. It is also false if the fighter dies later in the tick, so that a dead pawn cannot be replayed. A false value still carries the final authoritative pose but speed and jump are zero/false.

`epoch` increases whenever the body or its input ownership changes discontinuously: initial pawn creation, `clear_input` on drop or mission reset, respawn, campaign continue, and round/map transitions. A client discards replay history at an epoch change or on MapInfo, reconnect, role change, death, or an unapplied tick. Tick, input sequence and inventory revision never rewind.

Clearing input leaves the last acknowledged sequence as historical context. The first active tick in the new epoch may report `applied: true` with that old sequence while stepping neutral input. The epoch, not the sequence alone, tells a future predictor to discard pre-reset Actions; the old sequence does not mean its Action ran again.

For numbered human Actions, reject a duplicate or stale `seq` before changing continuous input or latching jump, interaction, or weapon choice. Use u32 wrapping half-range ordering. The server accepts `4294967295` to `0`; the Godot client wraps from `4294967295` to `1` to keep zero reserved as its unsent initial value. The diagnostic Ack probe interrupts its measurement if a capture crosses that wrap, because its bounded sample window uses ordinary integer ordering. Gameplay input continues. Unnumbered legacy Actions retain current behavior. A resumed pawn retains the last accepted sequence; an older numbered sample cannot replace it.

## Compatibility

The new object is additive on a server-to-client message. An old client can ignore it; a new client receiving an old Ack without it stays on authoritative snapshot presentation. No global gameplay-version increase is required for this outbound-only change. Godot validates `movement.version == 1`, finite bounded numbers, exact integer ticks and epochs (JSON may parse integer tokens as floats), monotonic ticks, and epoch resets before exposing an Ack for later replay. A future Action field needs separate advertised negotiation because the current Action parser rejects unknown fields.

## Verification

- Rust old/new Ack JSON round trips and legacy Action compatibility.
- Coalesced numbered Actions: last continuous sample wins; earlier jump tap is consumed once; repeated held sample yields distinct applied ticks; stale/duplicate and u32 wrap tests. The Godot sender wraps within u32 and the probe marks a crossing capture interrupted.
- Full 3D Ack matches the post-tick live step, including blocked-axis velocity and compliance speed. Warmup, death, respawn, map/round change, drop/resume and campaign continue boundaries reset appropriately.
- The first active tick after input reset keeps the old sequence only as history and carries the new epoch with neutral movement.
- Existing MapInfo/Snapshot-before-Ack queue order preserved.
- Godot headless parser tests for finite exact numbers, all required fields, old Ack fallback, duplicate sequence on newer tick, stale tick and epoch reset. The Action-to-Ack baseline probe still reads the unchanged root fields.
- Focused Rust and Godot checks; record exact results before handoff.

## Spend and scope

Local code and tests only, $0 external spend. No prediction rendering, UDP, tick-rate change, cloud apply, or merge. Existing coverage floor remains. Document any epoch boundary that cannot be resolved from source rather than guessing.

## Evidence and handoff

Local verification on 2026-09-28, pending exact-head CI:

- `cargo test -p fragr-server --locked --quiet`: 530 unit tests passed, 3 ignored; all following integration groups passed. Coalescing, stale and duplicate input, u32 wrap, dead/respawn/round epochs, old/new wire JSON, and campaign continue have direct assertions.
- A focused test of the first active tick after input reset passed after the independent review identified the historical-sequence wording edge. It asserts a new epoch, neutral motion and the old sequence as context.
- `cargo check --workspace --all-targets --locked`, `cargo clippy -p fragr-server --all-targets --locked -- -D warnings`, `cargo fmt --all -- --check`, `cargo build -p fragr-server --release --locked`, and `git diff --check`: passed.
- Pinned Godot 4.7.2 `tools/godot_check.sh`: import, parse and all harnesses passed. Direct `test_movement_ack.gd`, `test_input_ack_probe.gd` and `test_input_pacing.gd` harnesses also passed. The Ack parser accepts the small Rust f32 rounding excess at yaw near 2 pi; it still rejects a value outside the facing range.
- The `effective_speed` parser bound of 5 units per second covers all humans in the current sim: `encounters::gait` is 1.0 for campaign participants and arcade fighters, and the compliance rule can only reduce speed. Enemy gait values do not produce human Acks.
- No external API, cloud or paid calls were made. The live Godot pawn still uses authoritative snapshots. Replay, correction policy and latency feel testing remain the next rung.
- Unfiltered workspace coverage passed at 93.58 percent, above the 90 percent floor. This run preceded the extra reset test, which changed no production code. Independent review found no blocking regression in sequence order, wrap, epoch transitions, delivery order or Godot validation.
