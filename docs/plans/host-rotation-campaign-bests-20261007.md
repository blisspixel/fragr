# Host rotation and campaign bests

Status: **implemented locally**, 2026-10-07. Bounded continuation of rungs 1, 2 and 5
in the [full build order](../ROADMAP.md#full-build-order).

## Goal

Let an attached dedicated-server operator inspect the current show and queue
a validated map/mode for the next show without removing connected players or
cutting short a Sabotage match. Give campaign players a local best-time
comparison against compatible completed missions already in their service
record. Reconcile README and active roadmap claims with the eleven connected
development missions on the current main revision.

## Scope and architecture

- Extend the existing venue desk with `shows`, `next` and `map <map> <mode>`.
  Prepare navigation off the tick before queuing a map. Reuse playlist
  validation, mode clocks, loadout refitting, round reset and MapInfo ordering.
  A queued show replaces an earlier choice. Invalid choices retain it.
  Manual choices end automatic rotation and repeat until another is queued;
  `next` follows the built-in night order on a playlist server.
- Derive bests from the existing bounded PlayerRecords history. Compare only
  completed human mission records with matching mission, map id, rules,
  difficulty, clock and exact locally launched server SHA-256. Campaign and
  development runs remain separate. Local history version 2 adds optional
  source provenance while retaining version 1 entries without inventing it.
  External and historical records remain readable but cannot claim a local
  best. Exclude the current identity from prior bests. Times measure the
  successful attempt's readiness-to-departure clock. Report ties and deltas
  at tick precision, including in the service record panel.
- No new wire shapes, campaign save format, persistence store, dependencies,
  runtime or service. Do not invent reviewed par times, rewards, global
  leaderboards, new missions or final-art acceptance.
- Preserve the combat and infrastructure changes present at task start.
  No cloud apply, publishing or release belongs to this local increment.

## Verification

Use deterministic tests for queuing, invalid map/mode pairs, retained input
sequences, connected rosters, MapInfo-before-snapshot, loadout/vehicle reset,
playlist continuation and Sabotage half/match boundaries. Exercise the actual
desk parser and process with a bounded local smoke. Client checks cover
history reload, incompatible records, timing absence, duplicate identity,
first completion, faster/slower/tied times and actual results presentation.
Run required workspace tests, lints, benchmark/playtest checks and full Godot
checks. Regenerate and inspect the visual tour and a result containing a real
compatible comparison. Record limitations and baseline failures explicitly.

## Spend

$0. Reuse current assets. The last recorded image balance is about $4.62
against Nick's reported balance, not an independently verified live balance.
The separate model account last reports 1,900 credits, 15 uncertain held and
1,885 usable. No generation is required by these changes.

## Acceptance and handoff

Implemented on `feat/host-rotation-campaign-bests`, based on main `e4df1a0b`
(v0.79.0), with the pre-existing combat and infrastructure work retained.
No merge, release or deployment is claimed.

| Check | Local result |
|---|---|
| Rust workspace | Formatting, warnings-denied clippy and all workspace tests pass. The final unfiltered coverage run passes 1,814 tests and reports 93.25% lines against the 90% floor. |
| Dependencies and benchmark | `cargo deny` licenses, bans and sources pass. Release workspace build and the deterministic 16-bot, 1,200-tick, seed-42 benchmark assertions pass. |
| Desk transitions | Seven focused state/session regressions plus parser/channel checks pass. Actual attached stdin queues Compliance Yard TDM after Arena Duel, retains four bots, rejects an invalid replacement and survives stdin EOF. |
| Client | Godot 4.7.2 checks pass 325 scripts and 149 harnesses; the verifier's failure-detection scenarios pass. Final focused results and best-history checks pass after matching displayed time precision. |
| Multiplayer | All eight CI-shaped mode cases pass, including real-socket objective routes and contested CTF/Sabotage. The exact seven-map mixed-roster cases pass, from two to sixteen agents. |
| Soak | Four bots, four agents and two spectators stay live across nine samples over 120 seconds. Measured tick rate is 20.00 Hz, with zero queue overflows or degraded samples. This is a bounded local regression, not larger-room acceptance. |
| Actual campaign comparison | Two separate owned Standard M01 processes complete all fourteen unchanged ordinary-input route states, each with twenty kills and zero deaths. Persisted history compares 2,857 ticks (2:22.85) with 2,784 (2:19.20), yielding a new best faster by 73 ticks (3.65 seconds), count two. |
| Rendered presentation | All 32 standard-tour states pass and fourteen stills are copied locally. Full-size inspection covers bodies, menus, weapons and strips. A separate ten-state menu capture supplies the selected Multiplayer still. Current result and Service Record presenters also replay the actual retained completion data and are inspected. |

Raw logs remain in `.agents/host-rotation-campaign-bests/`. The durable
[comparison receipt](../screenshots/campaign-bests-20261007.json) records
source/image hashes and bounded metrics. The
[gallery receipt](../screenshots/readme-20261007.json) distinguishes the
refreshed tour, focused menu and retained earlier intake capture.

The initial visual wrapper attempt encountered Windows' executable lock while
client checks owned the release server. The normal wrapper passed after those
checks retired. The combined tour's Multiplayer title clips in its captured
frame; the ordinary menu sequence with a real loopback probe, one recent host
and unchanged layout fits correctly. That capture anomaly remains recorded,
without claiming a general layout repair. The selected image uses the inspected
normal menu. Current time-precision images are explicitly presenter replays
of actual completion data, separate from the two actual gameplay routes.

Human match enjoyment, physical LAN, fresh-player campaign pacing, M12-M20,
reviewed par times and final art remain open gates in the full build order.
