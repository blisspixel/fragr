# M01 failure timeline

Status: **implemented**. Local evidence below; integration review remains.

## Goal

Make free campaign playtest failures diagnosable from the authoritative wire. A
bounded, ignored per-attempt timeline should show where the fighter went, what
changed in health and ammunition, which visible guard interrupted the route,
and whether the record or lift progressed. Hit damage is raw server shot damage,
not effective HP loss. Replay the known incomplete Standard
seed 1 and Severe seed 42 cases, correct one demonstrated local-controller
defect, and retain the Standard seed 67 clear as a regression check.

## Scope and seams

Use `agents/brain`'s existing validated MissionClient, snapshot, loadout,
record, and event messages. `tools/qa_watch.sh` writes its free local trace
under the same ignored `.agents/watch/` directory as the first-person frames.
An explicit `play` trace path also allows headless runs. Sample at most once
per second, keep a fixed record bound, and group records by server attempt.
Positions are authoritative; any room label is derived from current authored
geometry and marked approximate. The trace is observation only and must not
alter server outcomes, the action cadence, provider requests, or spend.

No protocol changes, extra gameplay authority, player-facing telemetry, new
runtime language, or paid calls. No human acceptance claim follows from a
controller clear.

## Verification and success

- Test trace bounds, attempt transitions, and omission of unrelated players'
  private facts. Test a real controller correction at the owning seam.
- Run free local Standard seed 1, Severe seed 42, and Standard seed 67 with
  fixed agent names and time limits. Inspect phase, room or position, health,
  magazine, recent damage, target, pickups, deaths, route movement, and the
  authoritative final receipt. Name any remaining stalls and deaths.
- Run focused tests and the workspace checks relevant to changed paths.
  Watch validation pairs camera identity with the same participant's receipt.

Success is a bounded replay artifact, one evidence-backed correction with a
regression test, and a candid account of which seeded runs still fail. The
fresh-player mission gate remains open until human acceptance near 1.0.

## Spend

Local rules and headless/watch runs cost $0. No provider or asset generation
is part of this change.

## Initial replay evidence, 2026-09-23

Raw receipts are ignored under `.agents/m01/` in the isolated worktree. These
are local-rule runs through the live authored server at 20 Hz, with $0 spend.
The trace records server ticks and mission messages, so a terminal phase is
distinguishable from the agent's elapsed timer.

| Difficulty, seed, name | Limit | Latest server state | Chronology |
|---|---:|---|---|
| Standard, 1, WatchAgent-Standard1 | 150 s | Complete at tick 856, attempt 1, 0 deaths, 12 kills | Pistol at tick 140, bypass darts at 507, dispatch medkit at 665, record at 767, departure at 856. Minimum sampled HP 50. |
| Standard, 1, WatchAgent-67595 | 150 s | Complete at tick 2247, attempt 3, 2 deaths, 28 kills | Exact name from the earlier incomplete watch. Death decisions at ticks 982 and 1490, then record at 2161 and departure at 2247. Previous branch watch with the same name had still been playing at 150 s, so seed and name alone have not made live outcomes deterministic. |
| Severe, 42, CampaignProbe | 150 s | Failed at tick 2492, attempt 4, 4 deaths, 22 kills | Each attempt reached the bypass darts and then died during `find_transfer` near sorting, around x -18 to -30 and z 31. The first attempt fell to 5 HP at tick 819, 25 m from the record; later attempts reached 10, 10, and -20 HP near 14 to 21 m. Objective distance dropped from 57 m each time, so this is combat pressure on the sorting approach, not a stationary route stall. |

The trace has no room name on the wire. "Near sorting" above is an inference
from the authored map coordinates and is not an authoritative room field. The
first Severe trace had no record of intent before navigation rewrote aim into
waypoint yaw; the follow-up trace adds both the original target and the final
navigation flag to decide whether combat pursuit pulls the fighter off route.

The follow-up Severe seed 42 run with the same CampaignProbe name completed on
attempt 1 at tick 1417, 14 kills and 0 deaths. From ticks 626 to 846 it
alternated around x -29 to -32, z 38, while objective distance stayed 27 to
30 m. In 14 one-second samples, six had a guard target, eight had none, and
navigation was active in all 14. This supports investigating combat versus
objective replanning, but the run ultimately cleared. It does not justify a
new engagement distance, enemy balance change, or claimed deterministic fix.

One controller lifecycle defect is unambiguous: the first Severe run sent
actions and repeated dead-position samples for more than 25 seconds after the
server said `failed`; successful runs did the same after `complete`. The bot
now stops issuing actions on those two terminal statuses and drains incoming
messages for a matching final participant record, bounded at two seconds.
The regular run limit cannot interrupt that drain. If no matching record
arrives, `terminal_record_complete` is false and the counts must be treated
as incomplete. The watch verifier rejects a terminal receipt without that
record. A delayed-record test supplies a stale active record, waits more than
the former 500 ms grace, then supplies the matching terminal record; the
timeout path is also tested. A validated `continue` state still requests a
retry. Standard seed 67 with CampaignProbe then completed on attempt 1 at
tick 1413, 14 kills and 0 deaths, in 67.92 seconds despite a 120-second cap.
Its trace ends with the `departed`/`complete` message and has no repeated
post-terminal samples. This checks the controller lifecycle and preserves an
M01 clear; it does not prove survival across seeds or fresh-player quality.

The 25-second `qa_watch.sh` smoke passed with eight first-person frames, a
verified brain/watch UUID, 500 actions, five kills, no deaths, `find_transfer`
still playing, and $0 spend. Its new `timeline.json` has 32 bounded points,
zero dropped and the same UUID. The final frame shows the agent's Pistol and
objective card in the provisional intake art; this capture does not establish
finished visual quality or a mission clear.

After the matching-record drain change, a fresh Standard seed 67
CampaignProbe watch completed at tick 1537 on attempt 1, with 14 kills,
0 deaths, `terminal_record_complete: true`, and $0 spend. Eight first-person
frames matched the brain participant, the trace ended at `departed`/`complete`
with 89 points and none dropped, and the paired receipt passed. A copy of
that receipt with `terminal_record_complete: false` made the Godot verifier
exit 1 with the expected missing-final-record error.

`cargo fmt --all -- --check`, full workspace tests, workspace clippy with
warnings denied, all Godot headless checks, and unfiltered workspace
coverage at 94.26 percent passed on the rebased branch. Focused brain tests
passed 84 library and 7 CLI tests. `bash -n tools/qa_watch.sh` and
`git diff --check` passed. The server's 16-bot release benchmark assertion,
`cargo deny check licenses bans sources`, the four-agent local playtest,
and the six-map 2/6/6/8/12/16 roster passed. The roster recorded spawn-death
evidence on maps 3 through 6; this trace change does not alter spawn rules.
The
first brain test invocation collided with a stale test-only pending file in
shared Windows Temp; a rerun with task-specific `TMP` and `TEMP` under ignored
`.agents/` passed. No pending receipt was removed or treated as spend. The
CI result remains an integration check; this branch changes brain diagnostics
and its watch wrapper only.
