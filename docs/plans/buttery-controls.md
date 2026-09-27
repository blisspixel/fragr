# Plan: buttery controls

**Status:** in flight (stage 1 shipped 2026-09-18)
**Branch:** `feat/controls-*` (one PR per stage below)
**Spend:** $0.

## Goal

The 1.0 bar in [`../ROADMAP.md`](../ROADMAP.md) asks for first-person movement and aim that feel buttery: client-side prediction with server reconciliation, interpolation on every other fighter, no rubber-banding on a LAN or a good connection, input latency under fifty milliseconds on a LAN, and all of it measured. This plan turns the research of 2026-09-18 into a design with numbers and a staged order.

## Non-goals

- Predicting other fighters, projectiles, or pickups. Only the local pawn is predicted.
- A new transport before the spike passes its thresholds. Stages 1 to 6 stay on WebSocket.
- Rewriting the playtest, brain, or adapter cadence; they consume the wire, they do not define it.

## Protocol changes

- Shipped stage 1: `Action` has absolute `yaw` and numbered `seq`; the server sends a separate unicast `ack` with the applied sequence, tick, x, z and yaw.
- Planned prediction stage: extend the authoritative acknowledgement and snapshot with the 3D position and velocity needed to replay the shared movement step.
- Planned tick migration: convert tick-count fields (`respawn_in`, cooldowns, `duration_ticks`, the 160-tick linger) to seconds or milliseconds, with the tick rate stated in `Welcome`.
- Each of these lands in `docs/protocol.md` in the same PR. The adapter reads the wire types from `fragr-server` (as the playtest harness and the brain do), so a wire change is edited once and the compiler finds every reader.

## Dependents of the tick change (stage 2)

Review every `*_TICKS` constant in `server/src/sim.rs` and `server/src/protocol.rs`, the adapter's speak cooldown mirror, the playtest harness's spawn-death window, the brain's 50 ms controller interval, and authored campaign timing. The current roadmap places this migration after Episode I and before the long Rail lane in level 6.

## Where we stand (from the code, not the docs)

- The server ticks at 20 Hz and every snapshot is the full JSON world (`server/src/run.rs`).
- `client/scripts/game_manager.gd` paces Action sends to at most 120 per second and keeps one-shot inputs latched until a send. The server's inbound budget is 256 messages per second per session.
- Client-owned yaw and numbered actions shipped. The separate `ack` is received by Godot, but Godot only stores the latest acknowledgement; live position prediction and reconciliation remain unbuilt.
- `server/src/movement.rs` and `client/scripts/movement.gd` share 3D golden vectors, including stairs, jumps and gravity. The live server still uses the authoritative integration path; the mirror is not wired into live client prediction.

## Design

1. **Client-owned yaw.** Every input carries an absolute yaw (f32). The server clamps only for sanity. Mouse motion is applied to the camera in the same frame it arrives and never waits on the network.
2. **Prediction and reconciliation for the local pawn only.** Inputs are numbered. The client applies each input locally at once and keeps the unacknowledged ones. The server returns the authoritative state plus the last processed sequence number; the client rewinds to that state and replays the unacknowledged inputs. Other fighters are never predicted.
3. **One move function, mirrored.** The existing Rust and GDScript steps include horizontal acceleration, 3D solids, step-up, jump and gravity, with shared golden vectors. The predicted step must use that mirror, not the Godot physics server. Compare live server integration against replay under the same inputs before choosing correction thresholds. Keep float tolerances explicit in both tests.
4. **Timeline interpolation for others.** A ring of tick-stamped states, rendered at server time minus 100 ms at 20 Hz snapshots (150 ms while on TCP, because one loss stalls the stream), 33 to 50 ms once snapshots run at 60 Hz. Extrapolate at most 100 ms, then freeze. The exponential lerp goes away.
5. **Lag compensation for hitscan.** The server rewinds targets by `clamp(RTT / 2 + interpolation delay, 0, 200 ms)` and keeps 250 ms of history. This matters even on a LAN: at 7 m/s a target moves 0.7 m during a 100 ms interpolation delay, more than a capsule radius.
6. **Sim at 60 Hz, snapshots at 20 Hz.** Input granularity would drop from 50 ms to 16.7 ms and the rewind history would become finer. Measure CPU and traffic before adopting this cadence. Convert tick constants to time units; snapshots and acknowledgements must carry the tick and 3D state needed by interpolation and replay.
7. **One input per client physics step after the tick migration.** The present cap is 120 sends per second from the rendered client. Stage 3 must define how sampled inputs, acknowledgement and replay relate to the authoritative 60 Hz movement step. Bound the replay window; do not resend unbounded history.
8. **Mouse feel in Godot 4.7.** Sum unscaled `screen_relative` motion while captured, apply it in the same frame, and never multiply it by delta or a viewport scale. Source units are 0.022 degrees per count at sensitivity 1, with a current default of 1.5. The player-settings pass persists that value and blocks input under overlays. This follows the official InputEventMouseMotion reference checked 2026-09-19. Camera interpolation and predicted-body positioning remain part of the movement work below.
9. **Gamepad look.** Radial deadzone 0.12 with rescale, response exponent 1.5 to 2, 250 degrees per second maximum yaw with a 0.25 s ramp in the outer five percent of the stick, aim friction at half speed inside a three degree cone around a fighter. Magnetism and snap later, if at all. These starting values are ours to tune, not sourced.
10. **Transport spike.** WebSocket JSON stays the control plane and the path for spectators and agents. Candidate A is a 12-byte header (sequence, ack, ack bits) over UDP with `PacketPeerUDP` on the client and `tokio::net::UdpSocket` on the server; candidate B is ENet through `ENetMultiplayerPeer` with a Rust binding still to be verified. WebTransport is not in Godot 4.7. Decide with the measurements below.

## Design detail (proposed)

The following is a design proposal. The movement model has evolved to 3D and
the client send cadence is now capped. Resolve the remaining wire and timing
choices against current source and measurements before implementing each stage.

### The movement model, written once in words

State per fighter: position `(x, y, z)` in units, velocity `(vx, vy, vz)` in units per second, yaw in radians in `[0, 2 pi)`. The fighter has a 0.5 unit horizontal radius and a 1.8 unit standing height. The shared step is:

1. Wish direction: forward, back, left, right bits combined into a unit vector in the yaw frame (the same trigonometry as today, normalised when non-zero).
2. Target horizontal velocity: wish direction times top speed. Top speed is 5.0, halved under the compliance slow.
3. Velocity approach: the pure step uses `v = v + (target - v) * min(1, dt / tau)` with `tau_accel = 0.06 s` and `tau_decel = 0.04 s`. The live server integration path currently applies horizontal velocity immediately. Stage 3 must reconcile that difference instead of assuming the pure step already predicts live play.
4. Move horizontally with the shared acceleration step. Apply a grounded jump and gravity to `y` and `vy`; resolve landing against the floor or the highest reachable deck.
5. Collide against the authoritative 3D solids and bounds, including step-up, clearance and horizontal sliding. Review `server/src/movement.rs` for the exact order; the golden vectors are the executable contract.
6. Yaw: take a valid absolute value from the input. `turn_left` and `turn_right` remain for agents whose input carries no yaw.

The pure step is mirrored in `server/src/movement.rs` and `client/scripts/movement.gd`, with no engine physics dependency. The live server currently calls `integrate`; stage 3 must prove the client replay matches that live path, including grounded and airborne transitions.

### Golden vectors

`client/golden/move_vectors.json` contains the shared Rust/GDScript cases. Rust generates and checks the vectors; `client/scripts/test_move_golden.gd`, run by `tools/godot_check.sh`, checks the GDScript mirror. Review changes to the vectors like code. The roster includes horizontal movement, stair and deck contact, jump, gravity and enclosed-space cases. Add replay cases with delayed or missing acknowledgements before claiming live prediction.

### Wire changes, exact

`Action` already has optional `seq` and `yaw`. A later stage proposes `view_tick` for lag compensation:

- `seq: u32` input sequence, increasing by one per input, wrapping. Absent means an unnumbered agent action.
- `yaw: f32` absolute yaw in radians. Present means client-owned yaw; the server normalises and stores it.
- `view_tick: u32` the server tick the client was rendering other fighters at when this input was sampled (for lag compensation). Absent means no rewind.

A separate unicast acknowledgement already reaches human clients every tick:

```json
{"type": "ack", "seq": 4123, "tick": 88210, "x": 12.25, "z": -3.5, "yaw": 1.4}
```

`seq` is the latest input applied to that fighter. Prediction needs an authoritative 3D state with velocity, including `y` and `vy`; design the exact `ack` extension and snapshot shape with `docs/protocol.md` and client validation in the same PR. The tick migration adds `tick_hz` and `snapshot_hz` to `Welcome`. Tick-count fields then move to time units with a documented compatibility window.

### Input cadence and bundling

Today the client samples its rendered input and sends at most 120 Actions per second; the 20 Hz server keeps the latest pending action. Stage 3 should sample and predict at the migrated movement cadence, number each step, and retain a bounded replay history. Before bundling several inputs in one message, specify and test server-side ordering, duplicate rejection, per-tick work limits and one-shot input handling. A dropped or duplicated bundle must not cause a second jump, Use or shot.

### Reconciliation

The client keeps a bounded ring of `(seq, input, state_after)`, including `y` and `vy`. On an acknowledgement carrying the complete authoritative movement state:

1. Find the ring entry for `ack.seq`. If missing (too old), snap to the ack state and clear the ring.
2. Error `e = ack.position - entry.state_after.position`.
3. Replay later inputs from the acknowledged state, and blend or snap the visual correction according to measured error. Check vertical error and grounded state as well as horizontal distance. Tune thresholds from recorded play, not the old 2D proposal.
4. Record `|e|` into the correction histogram reported on the status line and by the feel probes (p99 under 10 cm is the pass).

### Interpolation of other fighters

A ring of recent tick-stamped snapshots supports interpolation of other fighters in 3D. Estimate server time from observed arrivals; tune the render delay against measured jitter and loss on WebSocket before selecting a fixed buffer. Bound extrapolation and hold when data becomes stale. Preserve shortest-arc yaw interpolation. Replace the current presentation lerp only after the timeline path matches ground, stair, jump and death states.

### Lag compensation

The server keeps, per fighter, a bounded history of the complete 3D hit volume and facing needed by `server/src/combat.rs`, not only `(x, z)`. A fire input carrying a validated `view_tick` proposes a rewind no further than 200 ms. Without it (agents and old clients), no rewind. The historical states are used for the shot test without changing present authoritative state; tests cover elevated fighters, cover, stairs and a too-old view tick.

### Tick migration (stage 2)

The sim gets a movement step at 60 Hz and keeps combat, bots, pickups, and snapshots on every third step (20 Hz). All `*_TICKS` constants become `Duration` or seconds, converted once at the tick boundary: cooldowns, spawn shield, respawn, compliance slow, round timers, end delay, the speak cooldown mirror in the adapter, the playtest spawn-death window, and the brain's controller interval, which becomes "one per snapshot" rather than 50 ms. `Welcome` states `tick_hz` and `snapshot_hz`.

### Mouse and gamepad pipeline in the client

Mouse: sum `event.relative` in `_unhandled_input` (accumulated input stays on), apply yaw and pitch to the camera in the same `_process`, never multiplied by delta, transformed by the viewport's final transform when stretched. Sensitivity is stored as a Source-convention number (0.022 degrees per count at 1.0) and exposed in settings; the current 0.003 radians per count corresponds to about 7.8. `physics_jitter_fix` is 0. The camera's `physics_interpolation_mode` is off; its position comes from the predicted pawn state plus the visual offset.

Gamepad: radial deadzone 0.12 rescaled to a full range, exponent 1.8, yaw rate 250 degrees per second at full deflection with a 0.25 s ramp when the stick is beyond 0.95, aim friction at half rate while a fighter is inside a 3 degree cone. All five values live in one dictionary in `settings.gd` so the feel probes can sweep them.

### Order of stages, revised

1. **Shipped.** Client-owned yaw and numbered inputs on the 20 Hz sim; the `ack` message; turn bits kept for agents. The look axis no longer round-trips: the camera and the fighter's facing move on the frame the mouse moves, and the server takes the absolute value. Bundling several unacknowledged inputs per message comes with stage 3, when there is something to replay.
2. Tick migration: 60 Hz movement step, constants to seconds, `tick_hz` in `Welcome`.
3. The shared step in both languages with golden vectors, prediction and reconciliation, correction metrics on the status line.
4. Timeline interpolation for others with snapshot velocity; the lerp removed.
5. Lag compensation with `view_tick` and the bounded rewind.
6. Gamepad curves and aim friction from the settings dictionary.
7. A measured transport pilot after the WebSocket feel and bandwidth baseline. The older 2D `fragr-wire v1` sketch in `massive-arenas.md` is not the current 3D wire contract.

## Measurements

The benchmark mode prints these; the 1.0 release notes quote them.

- Transport, LAN: RTT p99 under 5 ms, jitter (p99 arrival delta) under 3 ms, zero loss. Public same-region: RTT p50 under 60 ms, p99 under 100 ms, loss under 1 percent. Under 20 KB/s down per client at eight players. Correction magnitude p99 under 10 cm.
- Feel: motion-to-photon under 50 ms at 60 Hz and under 35 ms at 144 Hz, measured with a phone at 240 frames per second filming mouse and screen or an Open-Source-LDAT build. Frame budget 6.9 ms at 144 Hz; p99 frame time under 1.5 times the median; no frame over twice the median during a sixty second bot match. Aiming measurably degrades from about 41 ms of local latency, and 4 to 12 ms of frame-time variance reads as less smooth, so those are the lines.
- Repeatable tests: a headless Godot harness injects mouse motion and asserts yaw changes in the same frame and the predicted body moves on the next tick; a Rust test asserts an input is acknowledged within one tick; a sixty second LAN run logs frame time, correction error, snapshot age, and RTT, and CI gates on the p99s.

## Staged PRs

The order is the revised one at the end of the design detail: yaw and numbered inputs, tick migration, the shared step with prediction, interpolation, lag compensation, gamepad, transport. Stage 3 needs the status line from playtest rung 3 for its correction metrics.

## Sources

Gabriel Gambetta's client-server series; Valve's Source multiplayer networking article; the Overwatch gameplay architecture and netcode talk (GDC 2017); Glenn Fiedler on snapshot interpolation, state synchronisation, UDP versus TCP, and floating point determinism; Riot on Valorant's 128 tick servers and peeker's advantage; the ioquake3 `sv_fps` default; Godot 4.7 docs on physics interpolation, Input, and the high polling rate mouse fix; Insomniac's aim assist talk (GDC 2013); the CHI 2015 latency and aiming study.

## Success criteria

- [x] Stage 1 shipped: yaw is client-owned and inputs are numbered, proven by the server tests (client yaw wins over the turn bits and steers the same tick, acks report the state the input produced, agents unchanged). The same-frame yaw harness lands with the QA tour's feel probes.
- [ ] Prediction with golden vectors passing in both languages.
- [ ] Others interpolate on a timeline; no lerp.
- [ ] 60 Hz sim; constants in seconds.
- [ ] Lag compensation bounded and tested.
- [ ] Gamepad response curve asserted by a headless harness at five stick magnitudes, and the aim friction cone by two.
- [ ] Transport decided with a benchmark table in this file.
