# Local human pawn prediction and reconciliation

Status: implemented in draft work, 2026-09-28. Branch: `feat/local-pawn-prediction`, stacked after [movement Ack v1](movement-ack-v1.md).

## Goal

Move only the local human body from the validated 20 Hz movement Ack and the mirrored `MoveStep.live_step`. Let a locally sent direction or jump affect the first-person camera without waiting for the next server snapshot. Each Ack restores the authoritative 3D body and replays a small number of speculative server ticks. Measure the actual correction and keep server authority.

## Design and boundaries

- The 120-per-second Action sequence is a sampled control stream, not a simulation step. The server selects the newest accepted continuous sample for each 20 Hz tick and latches jump taps. Client prediction therefore stores sampled Actions and advances at 20 Hz. An earlier jump tap survives a newer neutral Action until one step consumes the latch. If the newest selected Action itself still has `jump: true`, every later tick holds it true until a newer Action changes it. It never applies a 50 ms step per Action.
- A v1 Ack supplies `{tick,seq,movement}`. On each newer applied Ack, replace the baseline with its body and replay at most three later speculative ticks. Repeated Ack sequences on later ticks are valid. Keep the latest sampled direction until it changes, even after its sequence has been acknowledged. A delayed Ack may select an Action sent before this predictor began recording samples for the current replay epoch; accept its authoritative body as a baseline. If it selects an absent sequence at or after the first recorded Action, or the authoritative gap exceeds the bound, use snapshots until a fresh baseline arrives. Discard samples and speculative ticks on epoch changes, unapplied Acks, MapInfo, role/connection transitions, death, respawn and campaign retry. An automatic resume resets prediction when the old socket closes and again before new Actions on the replacement connection. Older or future Ack versions fall back to authoritative snapshots.
- Present the predicted body directly on the local pawn and first-person camera path. The camera bypasses its old positional snapshot lerp only while local prediction is active. Snap on discontinuities. Blend small corrections with a bounded visual offset; do not smooth a respawn or carry stale yaw into a new body. Other pawns continue to use their existing snapshot smoothing. Health, weapon, score and event feedback continue to come from snapshots.
- Use MapInfo's validated half extent and solids as the collision arena. Convert Ack world Y to the integrator's feet height by subtracting the server's 1.5 metre body reference, then restore it for presentation. The most recent Ack's effective speed carries forward speculatively; a speed rule change between Acks is corrected on the next Ack. Keep the replay history finite and stop prediction if the Ack lag or geometry is unsuitable. There is no new wire field, server outcome change, UDP, 60 Hz migration or prediction of combat.

## Verification and acceptance

- Godot harness covers coalesced samples, held movement, tapped and held jump, Ack correction, repeated sequence with newer tick, epoch/unapplied and missing or future body fallbacks, bounded history and wrap handling, collision, map and death resets.
- Pinned `tools/godot_check.sh` must import, parse and pass every harness. Run the real loopback client/server path if feasible, measuring correction magnitude and camera versus authoritative position. Headless timing and a synthetic route cannot establish human feel.
- Existing server tests and protocol remain valid. Update `docs/ROADMAP.md` sequence and this plan with exact evidence, unresolved defects and the next acceptance gate.

## Local evidence and limits

The pinned Godot 4.7.2 focused `test_local_prediction.gd`, `test_input_pacing.gd`, `test_vertical_aim.gd`, `test_player_body.gd` and `test_campaign_recovery.gd` harnesses passed. The new tests cover coalesced input and same-tick revision, held and latched jump, release after a second speculative tick and its Ack replay, a repeated selected sequence, sequence wrap, unknown sequence fallback, three-tick bound, map collision and reset, connection resume clearing, the camera's direct local follow path, snapshot health and weapon changes, and local movement feedback from predicted velocity. Temporary fallbacks retain correction measurements and increment a fallback counter; map and role boundaries clear both. The full `tools/godot_check.sh` passed after the independent review fixes, as did the final focused prediction harness. The release server build passed. `cargo fmt --all -- --check` and `git diff --check` passed.

The bot-free, no-round-events loopback movement tour used Godot 4.7.2 on an AMD Radeon 780M OpenGL renderer, a release server on port 6791, and `client/qa/movement.json`. All six live first-person states passed, including jump, both stair approaches, gantry crossing and ledge exit. The reviewed run recorded a 1.295 m jump peak and a 1.295 m eye rise; all six captured camera-eye gaps were 0.00 m at four-decimal precision. The contact sheet was inspected and had nonblank first-person world frames. Ignored artifacts are under `.agents/qa/prediction_movement_postreview/`.

The correction probe compares the predicted state and the Ack's authoritative state **for the same server tick**. It does not measure network RTT, input latency or motion-to-photon delay. These are separate live runs of the same route and options, not byte-for-byte replays:

| Local route | Matched Acks | Same-tick p50 | p95 | p99 | Maximum | Prediction fallbacks |
|---|---:|---:|---:|---:|---:|---:|
| Before pending-tick input revision | 646 | 0.00 m | 0.00 m | 0.25 m | 0.35 m | Not recorded |
| After pending-tick input revision, before review fixes | 651 | 0.00 m | 0.00 m | 0.00 m | 0.25 m | Not recorded |
| After jump, reconnect and measurement review fixes | 648 | 0.00 m | 0.00 m | 0.00 m | 0.00 m | 6 |

Zeros are rounded to four decimal places and mean the mirrored path usually matched on this straight, automated route. They do not imply zero input latency or human feel. The reviewed run also counted five `ack_timeout` and one `unknown_seq` fallback, all of which recovered to active prediction before the next captured state. The screenshot tour pauses and captures frames, so these counts do not isolate ordinary continuous-play behavior. Earlier runs reached 0.25 m and 0.35 m maximum corrections. An earlier p99 value of 0.25 m was **invalid** as a correction statistic: that probe compared the body at different ticks and counted ordinary authoritative time advancement as error. It was discarded and replaced by the same-tick runs above.

This rung has no human play review, two-machine latency or loss test, network-induced correction distribution, or 1.0 feel acceptance. Those remain the next gates, along with investigating capture-tour fallbacks in a continuous-play trace. The standard 32-state player-facing tour passed and refreshed 13 stills through `tools/qa_tour.sh --publish`; the contact sheet and first-person frame were inspected.

## Spend

Local work only, $0 external spend. No cloud apply or asset call.
