# Mission wire ordering verification

Status: shipped, 2026-09-20, [#189](https://github.com/blisspixel/fragr/pull/189),
v0.27.1. Task [#188](https://github.com/blisspixel/fragr/issues/188) is closed.

## Failure and scope

The post-merge Linux run for v0.27.0 failed the mixed-party mission test at
`human.await`: three map messages arrived instead of two. The five pre-merge
jobs passed. Session sends geometry on connection and on its first tick; a
connection admitted before that tick can legitimately receive the same closed
map twice. Packet count does not identify a geometry transition.

Prove the actual contract: every map matches the complete expected closed or
open geometry, progress follows matching geometry, exactly one closed-to-open
transition occurs, and both fighters and the late spectator observe departure.
Keep participants connected until the spectator has observed the result. Replace
scheduler assumptions with explicit phase coordination, not sleeps or retries.

## Implementation and verification

The stronger geometry-order check exposed a production race in a local workspace
run: net registers the connection for broadcasts before Session processes its
Connected command. A tick can therefore send Mission before the initial MapInfo.
Keep the connection out of broadcasts until its targeted initial map is queued.
Do this in the canonical ClientSession/send_unicasts/broadcast path, with no new
transport or client-side tolerance for out-of-order state.

No wire schema, dependency, runtime pin or spending changes. Exercise connection
before and after the first tick deterministically through Session, retaining
client validation. Also hold a real socket's Connected command while broadcasting
to reproduce the production race for human, agent and spectator roles.
Run the real WebSocket test repeatedly, then the workspace tests, formatting and
strict Clippy. CI must pass on Linux, Windows and macOS before merge. Existing
coverage, benchmark, multiplayer and Godot gates remain intact. Refresh and
inspect the gallery before releasing the runtime fix.

Update the local-entry plan and roadmap to its actual released status. The
campaign opening follows this repair under its own bounded plan. Runtime
implementation and verification require no paid calls.

## Evidence

The forced scheduling regression failed on the original server with a Mission
message preceding MapInfo. The fixed server passes it for humans, agents and
spectators. A separate delivery test proves that existing clients continue,
ordinary unicasts cannot enable broadcasts, and failed map sends stay pending.
Twelve consecutive live mixed-party runs pass. The test now compares full map
payloads, checks their order against every mission phase, and holds both fighters
until the late spectator observes shared departure. It still requires exactly
one closed-to-open world transition.

Local formatting, strict workspace Clippy, workspace tests, release build and
license/bans/source checks pass. The complete coverage run passes 691 tests with
two existing ignored generators and 95.80 percent unfiltered line coverage.
Receipts: `.agents/mission-wire-*.log`. All 26 Godot harnesses and all six verifier
fault-injection scenarios pass. The 21-state gallery was republished and inspected,
including the contact sheet, shot strips and full-size rail impact. The prior
intermittent exit warning did not recur; #186 remains open. All five pre-merge
CI jobs passed in run 35513809015; the merged tree matches that verified head.
All five main-branch integration jobs passed in run 35514384360.
No thresholds or runtime dependency versions changed.

The four-client smoke passes: 33.4 seconds, nine frags, zero spawn deaths. All six
mixed-client roster cases pass the existing assertions. Their spawn-death counts
remain visible; this is regression evidence, not proof of final map balance.

| Map / seed | Clients | Duration s | Frags | First frag s | Longest gap s | Spawn deaths |
|---|---:|---:|---:|---:|---:|---:|
| Arena Duel / 67 | 2 | 61.90 | 6 | 10.35 | 10.35 | 0 |
| Compliance Yard / 42 | 6 | 61.90 | 29 | 6.25 | 6.25 | 0 |
| Directive 17 / 19 | 6 | 61.05 | 28 | 2.95 | 5.70 | 4 |
| Sector 9 / 42 | 8 | 23.15 | 19 | 2.95 | 3.55 | 4 |
| Reclamation Gulch / 42 | 12 | 60.25 | 53 | 2.95 | 3.80 | 3 |
| Tripoint Works / 42 | 16 | 43.20 | 61 | 2.95 | 3.25 | 4 |

| CPU measurement | Result |
|---|---|
| Configuration | Windows release, 16 bots, 1200 ticks, seed 42 |
| Tick p99 / 50 ms budget | 0.655 ms / 1.31 percent |
| Ticks over budget | 0 |
| Determinism | Repeated trace agrees; hash unchanged from v0.27.0 |

Trace: `459243bbd70300ca9a014aed7f21b8ef1ee1d49fd9849e3feddf3eb78e7b50c4`.
No GPU, WAN or larger-server performance claim follows from this CPU result.

The existing Tokio 1.53.1 channel API was checked against its
[official documentation](https://docs.rs/tokio/1.53.1/tokio/sync/mpsc/index.html)
on 2026-09-20. Initialization and broadcast insertion use the same guarded client
queue; ordering does not depend on a delay or a new client acknowledgement.
