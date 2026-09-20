# M01 transfer record and departure

Status: **shipped**, 2026-09-20, #184 and v0.26.0; closes
[#183](https://github.com/blisspixel/fragr/issues/183).
Builds on the intake encounter in #180/#182, released as v0.25.0. The transfer
desk, gate and departure pass local checks and all five hosted checks on Linux,
Windows and macOS. The full M01 remains unfinished.

## Player outcome

Find Latch's transfer record at the physical console, learn that they are being
held in the correction ward, open the custody lift route and deliberately depart.
M01 does not rescue Latch or reveal the Inheritance. Essential information uses
keyed text and works with radio muted and no voice asset. Reading optional detail
cannot hold up progression. Completion happens once on the authority.

## State and boundaries

- Add typed mission identity, phase and interaction kinds to the shared protocol.
  Phases are find-transfer, reach-lift and departed. A server-owned attempt ID
  distinguishes a party retry from stale presentation. New mission maps require
  gameplay capability 4; older encounter and arcade maps retain their contracts.
- A physical interaction uses ordinary player input, a live participant, finite
  range, aim and an unobstructed ray. Reuse the combat geometry. A short press
  survives the frame/tick boundary; held input must not repeatedly activate a
  target. F and gamepad B can use the interaction while playing; existing
  spectator camera controls retain their separate role.
- The transfer console derives its visible panel and use point from one validated
  authored face definition. No client-authored interaction IDs, arbitrary scripts,
  resource paths or localized strings in map data. Navigation gets a validated
  reachable approach point. The server decides prompts and legal transitions.
- The lift has a real closed solid. Precompute its closed/open geometry and
  navigation from one authored gate definition before readiness. Select an
  immutable map variant on the authority and publish MapInfo before the new
  shared `Mission` message and snapshot. Mission messages are sent on shared-state
  change and on join, independently of the 20 Hz snapshot. Do not rebuild
  navigation on the combat tick or maintain a second
  client-only door collider. The first gate transition is discrete; animated
  moving doors need a later explicit collision contract.
- Record discovery is shared and survives one participant leaving. Departure
  requires the record, every current participant alive and aboard the lift, and
  an explicit use press. Spectators and enemies never count as party members.
  Display who is still needed instead of silently ending another player's run.
- Reuse the existing single party-wipe/last-departure reset decision. Reset the
  record, gate, encounters and supplies together, once per failed attempt.
  Individual entry respawn remains provisional; this does not claim checkpoints,
  revive, reconnect identity, persistent saves or full co-op completion.
- Preserve the existing canonical action, snapshot, map, hostility, input and
  localization seams. Mission state is typed data, not an English-text parser or
  reuse of the legacy calibration episode's unrelated objective strings.

## Content and scope

Add the console and lift definitions to the actual M01 map. The objective starts
with finding the transfer record and then directs the party to the lift. The
record names Latch and the correction ward without inventing a successful rescue
or a remote radio briefing. Completed departure gives a clear result; it cannot
pretend to load an unbuilt M02. The remaining office encounter, secrets, full
mission population, opening scene and checkpoint lifecycle remain tracked work.

## Verification

- Reject malformed targets, invalid panel/gate references, obstructed use points,
  unreachable approaches, invalid exit regions, unsupported versions and content
  over budget before binding. Validate both geometry variants and prove the gate
  actually blocks then opens the intended route.
- Test press latching, held input, range, aim, walls, dead/NPC/spectator exclusion,
  simultaneous use, idempotence, party boarding, late arrival, disconnect,
  individual death, party wipe and reset. Test live protocol ordering and clients
  updating navigation when the same map ID changes geometry.
- Human, MCP/scripted and local decision clients consume the same mission state.
  Test older-client rejection only on mission maps. Do not infer completion from
  a client animation, local timer, score or map name.
- Run a real solo sequence and a mixed party sequence. Inspect the locked route,
  console prompt, translated record, opened gate, boarding feedback and departure
  in player and spectator views on available rendering backends. Test missing
  voice, muted radio, long text, pause/input ownership and late-state rehydration.
- Run the repository verification stack, preserve legacy arcade traces and
  multiplayer gates, refresh the gallery and record limitations before release.

No dependency or paid generation is required for this work. Current source and
the pinned engine's input, Label and translation APIs remain the implementation
basis; verify any new version-sensitive API against official documentation.

## Implementation and evidence, 2026-09-20

- `protocol/mission.rs` owns strict mission geometry/state types; `mission.rs`
  owns phase changes. `encounters.rs` remains the single owner of party reset.
  `maps/authored/mission.rs` prepares and validates both gate worlds. A finite
  18-degree use cone and 2.5-metre eye range select registered physical controls.
- `MissionClient` validates shared observation and supplies local mission control
  to scripted, decision and playtest agents. MCP exposes the same facts and use
  input. No paid decision is needed to walk, aim, use or wait for the party.
- Gameplay capability 4 gates mission admission. Tokio's existing owned
  semaphore permits reserve four participant seats across handshake and session
  lifetimes; spectators remain separate. Verified the
  [owned-permit API](https://docs.rs/tokio/latest/tokio/sync/struct.Semaphore.html#method.try_acquire_owned)
  and Godot's [input press/release behavior](https://docs.godotengine.org/en/stable/classes/class_inputevent.html#class-inputevent-method-is-action-pressed)
  against primary documentation on 2026-09-20. No dependency change.
- Server tests cover real closed/open routes, malformed authoring, tap/held use,
  range/aim/cover/liveness, whole-party boarding, individual departure/death,
  shared reset, late state and admission. A live human-role plus agent-role fixture
  walks, reads, boards and departs over WebSockets while a late spectator observes
  geometry before progress (`.agents/mission-wire.log`). This is a controlled
  fixture, not evidence of finished campaign co-op.
- Actual M01 public and maintenance routes complete combat plus both interactions
  with normal actions in both roles. The final seed-67 route measurements are
  below, from `.agents/mission-routes-integrate.log`. These scripted paths measure
  correctness, not a new player's mission duration or enjoyment.
- First OpenGL review completed 16 states and exposed the flat console's poor
  reading angle. The panel/use point moved together onto the front face.
  Corrected Vulkan and OpenGL reviews completed all 16 states, with short F
  presses reaching `reach_lift` and `departed`. Inspected the contact sheets and
  console closeups: `.agents/qa/m01-mission-vk/` and
  `.agents/qa/m01-mission-final-gl/`.
- Twenty-four client harnesses pass, including mission boundary validation,
  short Use input, release while blocked, spectator prompt exclusion and runtime
  locale refresh. Six shared face-point goldens keep physical use aligned with
  rendered panels. Final workspace checks pass 682 tests, with two existing
  opt-in artifact generators ignored. Unfiltered workspace line coverage is
  95.76 percent. Strict clippy, release build, license/bans/source checks and
  client-verifier failure injection also pass.

| Seed 67 route, human and agent roles | Ticks | Final HP | Shots |
|---|---:|---:|---:|
| Public hall, record, lift | 548 | 80 | 17 |
| Maintenance flank, record, lift | 864 | 100 | 22 |

The first real scripted/decision-client run exposed an optional-ammunition loop.
The shared inventory controller now lets a supplied fighter pursue its mission;
running dry still routes it to supplies. A regression covers both priorities and
the unchanged arena path. A two-participant actual-map test verifies discovery,
combat, respawn and shared departure through the same controller.

The corrected live run reached the record at tick 626 and departed at tick 705.
Both participants boarded; one died and respawned during combat. The local brain
used no remote calls and spent $0 for this run. Receipts:
`.agents/mission-agents-fixed-server.err`, `mission-observer.log`, and
`mission-local-fixed.log`. This is recovery through provisional entry respawn,
not proof of checkpoints or a finished companion system.

The 21-state release gallery was regenerated and inspected, including menus,
player/spectator views and the shot strip. It remains the separate arcade
regression gallery: `.agents/qa/mission-release-gallery/`. The four-agent network
smoke passes with 9 frags and no spawn deaths in 30.6 seconds. The six-map roster
is a separate check, not inferred from that smoke.

The final six-map mixed-client matrix passes unchanged gates:

| Map | Clients | Seed | Frags | Seconds | Spawn deaths |
|---|---:|---:|---:|---:|---:|
| Arena Duel | 2 | 67 | 6 | 61.90 | 0 |
| Compliance Yard | 6 | 42 | 27 | 61.90 | 0 |
| Directive 17 Substation | 6 | 19 | 28 | 58.80 | 2 |
| Sector 9 Transit Hall | 8 | 42 | 29 | 41.95 | 0 |
| Reclamation Gulch | 12 | 42 | 39 | 44.00 | 2 |
| Tripoint Works | 16 | 42 | 62 | 39.15 | 10 |

Reports: `.agents/playtest/mission-roster/`. Asynchronous timing can change combat
outcomes. Passing the gate does not make the observed spawn deaths acceptable
final balance; the larger maps still need layout and spawn-pressure refinement.
The final M01 OpenGL recapture, including the corrected exit instruction, is
`.agents/qa/m01-mission-release/`. Its console, result and contact sheet were
inspected and dated copies retained in `docs/screenshots/prototypes/`.

| Local release CPU check | Result |
|---|---|
| Host and workload | Windows x86_64, 16 rule bots, 1200 ticks, map 1, seed 42 |
| Session plus encoding p99 / maximum | 0.655 / 1.247 ms |
| Ticks exceeding the 50 ms budget | 0 |
| Repeat trace | Deterministic, matches the prior facility benchmark |

The trace SHA-256 is `459243bbd70300ca9a014aed7f21b8ef1ee1d49fd9849e3feddf3eb78e7b50c4`
in both `.agents/mission-bench-integrate.log` and `.agents/facility-bench.log`.
This is a local CPU regression check, not GPU, network-load or public-server
capacity evidence. Rendered evidence is Windows/AMD Radeon 780M; macOS/Linux
headless checks do not substitute for rendered hardware review.

Self-review checked authority, lifecycle ownership, boundary validation, physical
panel alignment, input release, agent resupply, lore and documentation status.
Integration: PR #184, commit `229ccf3db90c7232e0aaf3e049ffab7b878a9010`,
[v0.26.0](https://github.com/blisspixel/fragr/releases/tag/v0.26.0).
An additional four-agent live run reached the record at tick 780 and departure
at tick 863, observed by a Godot spectator with all four alive and aboard.
Two scripted and two local decision clients used no paid calls. Receipts:
`.agents/mission-four-server.err` and `.agents/mission-four-observer.log`.
Full art, office encounter, secrets, opening scene,
checkpoints, revive, reconnect, M02 transition and fresh-player fun review remain
outside this sequence increment.
