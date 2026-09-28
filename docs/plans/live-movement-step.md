# Live movement step for prediction

Status: implemented locally, 2026-09-28; awaiting integration review. This is the first bounded rung after the measured human Action-to-Ack baseline. The implementation branch is `feat/live-movement-step`.

## Goal

Make the existing 20 Hz authoritative movement rule a named pure function with a matching GDScript function and cross-language golden vectors. Prove that the live `GameState.tick` path still produces the same 3D position and vertical speed. This gives later prediction work an executable rule to replay.

## Non-goals

- No client prediction, visual correction, new Ack fields, or transport change in this rung.
- No change to movement speed, acceleration, collision, jumping, combat, server tick rate, or existing 60 Hz accelerated golden vectors.
- No cloud resource, paid call, or public deployment.

## Architecture and contract

`server/src/movement.rs::live_step` will take the current body state, one selected movement input, the current fixed server `dt`, and the authoritative arena. It will set horizontal velocity immediately from the normalized directional wish, then call the existing 3D `integrate`. The `GameState.tick_active` caller remains responsible for selecting the newest Action, latching jump, setting client yaw, applying compliance speed, and adding `PLAYER_FLOOR_Y` to feet height. Its role and gameplay decisions do not move into the pure step.

`client/scripts/movement.gd::live_step` will mirror the pure rule. A distinct `client/golden/live_move_vectors.json` will exercise the 20 Hz path. The existing `move_vectors.json` remains the accelerated 60 Hz model. Goldens are behavior evidence, not proof that prediction is enabled.

The Action and Ack wire shapes remain unchanged. Later work must define server-step replay and complete 3D Ack state before positioning the local pawn from this mirror. A client Action sequence is not a movement-step ID because the server coalesces multiple samples per tick and latches jump across them.

## Verification

- Rust golden generation/check for flat movement, stopping, diagonal yaw, wall slide, stair/deck transitions, jump, ceiling contact, and compliance slowdown.
- A `GameState.tick` equivalence test using the pure live step on the same immutable arena, including feet-to-world y conversion.
- Godot headless golden check for all recorded 3D fields with a stated float tolerance; register it in the existing checker if a separate harness is used.
- Focused Rust and Godot checks, then `cargo fmt --all -- --check`; record exact results here before handoff.

## Spend and safety

Local code and tests only, $0 external spend. Use the draft PR workflow for integration review; do not merge or deploy without written approval. Preserve the existing coverage floor and the production WebSocket path.

## Success criteria

- Live movement goes through the new pure Rust function with no intentional outcome change.
- Godot and Rust agree on the 20 Hz live golden cases, including vertical and collision states.
- At least one full `GameState.tick` case matches the pure function.
- Documentation distinguishes this executable mirror from live client prediction.

## Evidence and handoff

- `cargo fmt --all -- --check`: passed.
- `cargo clippy -p fragr-server --all-targets --locked -- -D warnings`: passed.
- `cargo test -p fragr-server --locked`: passed before the final two behavior assertions, with 524 library tests passed and 3 ignored, plus binary and integration suites. The new focused assertions passed after that run.
- `cargo test -p fragr-server --locked live_golden_vectors_match_this_model`: passed.
- `cargo test -p fragr-server --locked live_golden_cases_exercise_the_claimed_behaviors`: passed. The initial assertion guessed the blocked axis in the wall-slide case incorrectly; inspection showed the actual slide blocks Z, and the corrected assertion passed.
- `cargo test -p fragr-server --locked live_step_preserves_the_previous_inline_velocity_formula`: passed for flat movement, collision, compliance speed and jump.
- `cargo test -p fragr-server --locked live_step_matches_one_authoritative_tick_with_jump_and_compliance`: passed, including a jump tap latched before the selected continuous Action.
- Godot 4.7.2-stable `--headless --path client --import`: exited 0. The direct `test_move_golden.gd` harness passed, 37 cases and 1,330 recorded states across both models.
- `git diff --check`: passed. No external spend, commit, push, PR, or deploy.

The remaining integration gate is parent review and the full repository CI set. This rung does not define a client input-to-server-tick contract, add authoritative `y`/`vy` to Ack, or place the local pawn from the mirror. These are required before live prediction can be claimed.
