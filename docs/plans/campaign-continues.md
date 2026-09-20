# Solo campaign runs and continues

Status: implemented and locally verified, 2026-09-20. Bounded increment of #195.
Integration: [PR #200](https://github.com/blisspixel/fragr/pull/200), CI and release
pending. Local verification below is not cross-platform CI evidence.

## Contract

Implement the limited mission-start retries in [the campaign contract](../CAMPAIGN.md#runs-and-continues)
for M01. A new solo run has three continues, an initial tuning value. Death waits
for an explicit continue while allowance remains; death with none ends the run.
Completing the mission ends this prototype successfully. No revival, companion
control, mid-mission checkpoint or new paid dependency.

Local Single Player uses this mode. Dedicated authored hosts opt in with
`--campaign-run`; existing four-seat development hosts and arcade respawns retain
their behavior. One human or external agent owns the run's only combat seat.
Spectators can follow it but cannot spend continues. Leaving ends that run; a new
connection cannot refill the allowance or reclaim the seat. Reconnection identity
and persistent saves remain separate work, explicitly reported in the UI/docs.

## Implementation

- Keep run identity, allowance, status and mission-entry capture under `mission/`.
  Use the encounter lifecycle for one coherent reset, not another simulator.
- Snapshot entry position, health/armor, selected weapon and inventory once before
  play. Restore only durable equipment fields; clear unfinished reload/input and
  keep inventory revisions, input sequence and simulation clocks monotonic.
- Continue commands include run ID, mission ID and attempt. Admit only the owner
  in the waiting state, once per death. Restore original geometry, pickups,
  encounters and objective state; retain readiness so the intro does not replay.
- Freeze simulation outcomes during death choice and terminal states. A fatal
  frame cannot also complete the mission. Leave, repeated commands and stale input
  cannot resurrect the player or award duplicate completion.
- Add a validated optional run field to mission state. Development-host messages
  keep their existing shape. Solo mode requires a newer gameplay capability;
  update all consumers deliberately. MCP exposes an explicit slow continue tool.
- Present remaining allowance and a localized retro death choice. Require released
  input before a new press can continue; keyboard/controller use the same path.
  Spectators see the outcome without actionable controls.

Disk saves, cross-mission carry, achievements and final difficulty balance are
non-goals for this increment. The in-memory entry capture is not persistence.

## Verification

Prove exactly three retries, exhaustion, stale/duplicate/wrong-owner commands,
disconnect/seat reuse, invalid wire state, original entry gear and supply claims,
opened-gate rollback, cleared enemies returning, monotonic observations and
unchanged arcade/mixed-party regressions. Exercise the real M01 route across a
death and successful retry. Inspect the rendered death/retry/end UI, refresh the
public tour and run the repository checks before integration.

Primary references checked 2026-09-20: [Serde field attributes](https://serde.rs/field-attrs.html)
for optional versioned fields and [Godot input handling](https://docs.godotengine.org/en/stable/classes/class_input.html)
for discrete presses. Existing pinned dependencies suffice; no stack migration.

## Implementation evidence

Solo runs now use gameplay capability 7, with unchanged capability 6 development
parties and legacy arcade admission. The local bootstrap remains version 2;
its gameplay field advances to 7. Entry capture and restore live in
`mission/recovery.rs`; the existing encounter lifecycle resets the world.
Human UI and MCP receive the same authoritative run state. The optional MCP
`mission_continue` tool never treats a successful send as server acceptance.

The real client exposed two integration defects. Neutral blocked input was still
sending the death camera angle during restoration; it now omits aim and waits
for the restored snapshot. An admission error could disappear when Godot retired
text on the same poll as a close frame; the server now also supplies its stable
code in a policy-close reason and bounds the closing handshake. The client uses
one error mapping for both paths. Relevant primary references checked 2026-09-20:
[WebSocket closing](https://docs.rs/tungstenite/latest/tungstenite/protocol/struct.WebSocket.html#method.close)
and [Godot close reasons](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html#class-websocketpeer-method-get-close-reason).
The existing pinned transport compiled and passed the real client check; no
dependency upgrade was required. Exhaustion and completion also retain their
outcome after the owner leaves, ready for later result recording.

The seeded Rust M01 controller completes after one combat death and an injected
fatal outcome after record recovery. Both failed attempts remain charged:
attempt 3 completes with one continue. The routes, weapons, fights and interactions
use ordinary shared controllers; only the second fatal outcome is injected.
The first naive stationary controller exhausted its allowance. The improved
probe prioritizes visible targets and sidesteps; this is test-driving evidence,
not a claim that every supplied agent policy now plays the campaign well.

`test_campaign_recovery.gd` separately walks a real local Severe run into Clerk
fire four times. Fresh Enter presses spend exactly three continues. It checks
position, fists, facing, readiness and exhaustion and closes its owned child.
Controller A, held-input rejection, duplicate presses, spectators and malformed
state have focused client checks. Local lifecycle tests confirm a second client
cannot reclaim the lifetime seat and unrelated listeners survive cleanup.

The 14-state Standard rendered M01 tour confirms all twenty named guard deaths,
record recovery, departure and `run.status=complete` with all three continues.
Inspected captures: `.agents/qa/continues-m01/`; seven recovery captures under
`.agents/continues-recovery/`. The public 22-state tour was regenerated with
`--publish`; ten stills, motion strips, menus and gameplay were inspected.
These are Windows OpenGL/AMD Radeon 780M observations. This increment does not
establish new Vulkan, NVIDIA, Linux-renderer or macOS-renderer evidence.

## Verification receipt

Run against the working tree based on `b572396`, Rust 1.98.1 and Godot 4.7.2.
Logs are under `.agents/continues-*`; source/tests and CI remain the durable checks.

| Check | Result |
|---|---|
| Workspace fmt, strict Clippy, tests | Pass; 721 tests, two existing ignored tests |
| Unfiltered workspace line coverage | 95.63%, unchanged 90% floor |
| Workspace release build | Pass |
| License, ban and source checks | Pass |
| Godot import, parse and harnesses | Pass; all 28 harnesses |
| Checker fault injection | All ten scenarios pass |
| Four-agent smoke | Pass; seven frags, zero spawn deaths |
| Mixed network roster | Six maps pass unchanged assertions; table below |
| Rendered evidence | Solo complete route, all retries/exhaustion and refreshed public tour pass |

The first coverage run exposed geometry construction inside a two-second socket
deadline in the existing four-reader test. Preparation now precedes that deadline;
the same delivery bound and readiness assertions remain. The rerun passes.

CPU gate: 16 bots, 1200 ticks, map 1, seed 42, release build, Ryzen 7 7840U,
Windows. This is one local gate observation, not a throughput or speedup claim.

| Scope | p99 ms | Maximum ms | Over 50 ms budget | Repeat hash |
|---|---:|---:|---:|---|
| Offline session plus encoding | 0.754 | 1.177 | 0 | Identical |

Mixed reflex/planner agents and a spectator, one round per map:

| Map | Seed | Fighters | Frags | First frag s | Longest gap s | Spawn deaths |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 67 | 2 | 6 | 10.35 | 11.70 | 0 |
| 2 | 42 | 6 | 29 | 6.25 | 6.25 | 0 |
| 3 | 19 | 6 | 21 | 3.00 | 5.30 | 3 |
| 4 | 42 | 8 | 33 | 2.95 | 5.20 | 2 |
| 5 | 42 | 12 | 49 | 2.95 | 3.40 | 3 |
| 6 | 42 | 16 | 72 | 3.25 | 3.25 | 1 |

Spawn-death counts remain visible despite passing the existing thresholds.
No map, difficulty or art acceptance follows from a green roster.

## Remaining work

M01 still needs final character art, secrets, supply/pacing balance and fresh-player
review. The wider twelve-mission campaign, disk saves, reconnect and cross-mission
carry are unbuilt. The new player-record/statistics scope is bounded in
[#199](https://github.com/blisspixel/fragr/issues/199) and
[benchmark-and-stats.md](benchmark-and-stats.md): authoritative counters first,
then local records and optional factual commentary. No stats, achievement or
earned-cosmetic implementation is claimed by the recovery increment. Spend: $0.
