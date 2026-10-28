# fragr-playtest

Scripted agents play fragr rounds and file a metrics report to catch stalled
rounds and combat regressions before rendered playtesting. The harness boots the
authoritative server on a free loopback port, connects agents over WebSocket,
and observes frags, gaps, spawn deaths, idle/stuck time, weapon use, and payload
sizes. These measurements support playtesting; they do not establish fun alone.

The guided campaign survey runs Recall Notice, its earned carry into a bounded M02 window, or M19's bounded teaching and market segments, through the authoritative
session at 20 simulated ticks per second. It uses the shared mission navigator
and inventory controller with ordinary human actions, finite magazines, earned
pickups, real deaths and the three episode continues. No equipment or health is
granted during play. It needs no sockets, model, credentials or paid service.

```bash
cargo run -p fragr-playtest --release --locked -- --campaign-survey --survey-seeds 8 --seed 40 --max-seconds 600 --report .agents/playtest/campaign.json
```

Select `--survey-mission m19-teaching` for Planned Works, ending after the
tram-street objective and before the market. This is a standalone discovery
entry with Fists, zero ammunition and three fresh continues, not an inherited
M18 run. Weapons, ammunition and the coalition jetpack must be earned through
ordinary pickups and Use. Navigation knows the published objective regions and
exact authored jetpack launch/landing points; this does not test discovering
the route or understanding the lesson without hints.

```bash
cargo run -p fragr-playtest --release --locked -- --campaign-survey --survey-mission m19-teaching --survey-seeds 4 --seed 40 --max-seconds 600 --report .agents/playtest/m19-teaching.json
```

Select `--survey-mission m19-market` to continue the same played prefix until
`market_strips` completes, before taking any action toward the water tanks.
There is no injected market kit, refill or objective skip. The market stage
begins when the public objective follows `tram_street`; this is not a claim
that market enemies first activate or become visible at that boundary.

```bash
cargo run -p fragr-playtest --release --locked -- --campaign-survey --survey-mission m19-market --survey-seeds 2 --seed 42 --max-seconds 600 --report .agents/playtest/m19-market.json
```

Select `--survey-mission m02-carry` to carry an earned Recall Notice departure
into Persons Unknown through the real run file. The M01 leg is the Recall
Notice trial itself, field for field, with the server's `DurableRun` writing
`run.json` after every step into a scratch directory. M02 opens only by
resuming that file, which promotes and loads the saved departure exactly as the
local child does. The same policy then plays 60 seconds of active M02 time
with the carried equipment, HP, armor and remaining continues. Both legs are
guided by public objectives and navigation geometry through the shared
`MissionClient`, as in the Recall Notice survey; M02 adds no harness-specific
route hints, grants or completion target. `--max-seconds` bounds the M01 leg
only. Unlike the local child, harness sessions number entities
deterministically and admit the participant directly instead of through a wire
join; the simulation seed is applied after the run file opens, as in the child,
and opening draws nothing from the simulation stream (the M01 leg stays
identical to the survey either way).

```bash
cargo run -p fragr-playtest --release --locked -- --campaign-survey --survey-mission m02-carry --survey-seeds 8 --seed 42 --max-seconds 600 --report .agents/playtest/m02-carry.json
```

Each M02 death ends its session with the pending Continue saved. A fresh
session reopens it from disk. A request dropped before delivery must leave the
file unchanged (`dropped_unchanged`). Stale mission, run and attempt requests
and a duplicate after acceptance go through the ordinary session command path;
each must be refused (`rejected`) and leave the file unchanged, and only the
accepted request may spend a continue. The restored
kit must equal the M02 entry kit live and again after reopening a copy of the
saved entry. Any violation fails the command. Exhaustion must save `failed`.
The dropped request models transport loss; the client's own retry latch is
covered by the Godot net client harness.

Every session opens with the trial seed, as the local child opens every
process with its one seed (default 1). The first attempt runs on that seed.
Each retry, accepted in the same session or reopened from the saved pending
Continue, runs on its own stream derived from that seed, the run id and the
attempt number (`fragr_server::mission::retry_seed`, #489). A deterministic
agent that reopens a death therefore meets a new fight instead of replaying
the old one tick for tick, and the same run and attempt always replay the
same fight; a test pins both. Recorded sessions use a fixed run id, so a
report still reproduces. Each segment records the seed of the stream it ran
on; aim phase keeps the trial seed.

Outcomes are `m01_exhausted` or `m01_timeout` (no M02 entry), `window_elapsed`
(alive when the window ends, after any retries), `exhausted` and `departed`.
`carry` holds the M01 trial, exit and entry kits, per-attempt `segments` with
their simulation seed, end position and ammunition at start and end, and `retries` with menu-preview receipts. M02
supplies can refill ammunition, so compare shots with the ammunition receipts
rather than reading net change as use. `review` is the first M02 fatal hit and
`first_kill_review` the first later M02 kill; render them as below. A
`window_elapsed` row is not an M02 clear.

Every seed runs three stress profiles on Assisted, Standard and Severe:

| Profile | Reaction | Horizontal view | Turn limit | Aim error amplitude |
|---|---|---|---|---|
| reference | 0 ms | 100 degrees | 360 degrees/s | 0 degrees |
| deliberate | 250 ms | 100 degrees | 180 degrees/s | 1 degree |
| hesitant | 450 ms | 90 degrees | 120 degrees/s | 2.5 degrees |

All profiles use a 48-unit sight limit and an 80-degree vertical view. Enemy
recognition needs continuous line of sight to chest or head; cover, leaving the
view and death reset the delay. Incoming shots can prompt a delayed turn toward
their published origin. Navigation knows public objective locations and map
geometry. The controller scans after kills, reacts to published attack tells
and takes short detours for visible supplies. It does not model reading,
route discovery, human learning, sound perception or the rendered HUD. These
profiles are synthetic constraints, not measured novice populations. Compare
game changes with the same evaluator revision and seed set; a controller change
requires a new baseline.

A body can stand where the shared navigation grid has no waypoint: a corridor
exactly two body widths across, its walls on whole metres, such as Recall
Notice's pocket behind the dispatch screen. A route from there now joins the
grid by a longer straight walk (up to six cells) instead of failing. Before
that, a tell sidestep into the pocket left seed 44 deliberate/Assisted standing
still for 488 s until the trial bound (#497); with only that navigation change
it departs at 119.8 s and no other trial of seeds 40 to 71 changes.

During M19's crossing, tram street and market, it also remembers up to 64 positions
seen after the reaction delay, for less than 30 seconds. Losing sight permits
an investigation of that last position through the shared navigator; it never
updates a hidden pose, injects a target or fires at a memory. Reaching that point,
expiry, an observed corpse or its own kill confirmation retires the memory.
Retry clears it. At an unfinished arrival, three seconds without progress
permits another sweep at the same turn limit. This explicit search model repairs
the stationary crossing stall; compare it with its own evaluator revision,
not as a change to enemy difficulty or a human learning model.

During the market objective, a stateless guard preserves the shared strip
escape instead of letting generic dodging, hearing or scanning replace it.
After the normal reload, aim and turn constraints, a grounded movement step
that would cross back into a currently perceived strip releases its movement
keys; aim and firing remain available. Projection uses the existing campaign
movement step and authored solids. It does not infer airborne velocity or
remember unseen hazards, and retirement or lost perception removes the veto.
This repairs the measured escape/pursuit oscillation in the market evaluator.
The teaching prefix is unchanged. Compare this explicit policy revision with
its retained baseline; improved clears do not establish a game balance change.

The shared mission controller's strip escape keeps the edge it chose while
the body stays on the same half of the same strip. Re-deciding every tick
beside a market stall corner reversed the escape each step and held a
recognized body inside until the strip worked; crossing the centre line
still decides afresh. Its regression replays that one strip; the second
strip live in the recorded case is not excluded as a contributor. This is a controller repair in
`server/src/mission/controller/m19.rs`, shared with the free local agent; it
changes no strip, damage or movement rule.

Select `--survey-mission m19-tanks` to continue the same earned market run to
the next authored objective, `water_tanks`, and stop as it completes, before
acting on the roof loop. The market completion receipt stays as a
non-terminal boundary; a death after it retries from the attempt start, so
the market is earned again. No kit, save or objective is added. This is a
standalone endpoint, not an inherited M19 clear or fresh-player acceptance.

```bash
cargo run -p fragr-playtest --release --locked -- --campaign-survey --survey-mission m19-tanks --survey-seeds 2 --seed 42 --max-seconds 600 --report .agents/playtest/m19-tanks.json
```

Decisions and actions run at 20 Hz for every profile. Reaction delay limits
acquisition, not decision cadence. Continue is accepted immediately, with zero
simulated menu delay; dead/menu time is not included in the active stall metric.
The report records these assumptions rather than inventing human deliberation.

Paver strips need continuous visibility for the same reaction delay. Visibility
uses fifteen interior floor samples, the profile's view and range, and solid
occlusion. The Paver itself need not be visible. Cover, disappearance, changed
geometry or a new preparation reset recognition; a continuous preparation-to-work
transition retains it. This sampling can miss a narrow visible sliver and does
not model light spill or sound. Authoritative strip timing and actual support
are recorded separately for diagnosis and never supplied as decision inputs.

`--survey-seeds` accepts 1 to 64 here (default 16); `--max-seconds` bounds each
trial, including retries, from 1 to 1800 simulated seconds (default 120).
Reports include the build/commit, profile values, all outcomes, continues,
contact distance/time, shots/hits, actual HP plus armor lost, inventory and
longest time without damage dealt, a new pickup, objective change or a newly
visited two-unit cell. This last metric detects lack of progress, not just lack
of motion. Shot records retain attempt, position, source and view-relative
bearing; nominal `resolved_damage_outside_view` can include overkill and must
not be treated as a fraction of actual HP lost. The first 256 incoming hits per
trial are retained, with `hits_omitted` counting any further entries. `review`
holds the last fatal-hit pre-frame of the first deliberate/Standard trial, if
one exists. `first_kill_review` holds the first kill of the first
reference/Assisted trial, even if that trial later fails. Each includes up to
80 consecutive pre-event snapshots, stopping at retry boundaries. They are
inspection data, never controller input or recordings of ordinary client play.

Campaign reports use schema 3. M19 adds objective receipts, flight fuel/burn and
supported-landing outcomes, Paver phase/recognition times, strip-hit and
interruption attempts, and supported/airborne fuel increases. An airborne
objective completion is not a safe landing. Teaching acceptance requires a
powered ascent beginning below the gallery and ending on its support in the
successful attempt; a small powered hop on the gallery does not qualify.
`teaching_reviews` retains up to eight seconds per flight, first preparation and
first work event in each recorded attempt and objective stage, including up to one second before
the event. These mechanic windows cover every profile and difficulty of the
first seed; the kill/fatal selection remains unchanged. An `active_stall`
window begins after ten active seconds without progress, retaining its measured
`active_stall_seconds`. Missing events
remain missing; windows never join retries or observation gaps.
An actual simultaneous pair of strips can produce a `paver_overlap` window;
the renderer requires that event to exist in its frames. Stage metadata keeps
the earlier street lesson distinct from market inspection. A captured overlap
means simultaneous owners, not necessarily intersecting floor rectangles or
perception of both strips. Recognition remains separately measured under the
same view, cover and reaction limits; a phase's `recognized_tick` is its first
recognized sample within that stage, which can follow initial acquisition.
Flight `ended_tick` and `to` are the last live sample, including for flights
closed later by death, retry, a missing pack or an observation gap.

The market report keeps every attempt, including deaths or timeouts before
market entry. Its boundary receipts contain the full own `LoadoutState`, HP,
armor and remaining continues. Ammo counts already include rounds loaded in
magazines; do not add them twice. `entered_market` and the per-attempt outcome
separate entry from completion. Public interruption and strip-damage flags
remain attempt-wide: only a newly observed false-to-true flag after entry has
market-stage timing. Prior-true flags and absent attributable evidence remain
`unknown`, not a claim that no event occurred. These receipts never feed the
controller and do not assign damage to a particular Paver.

Per-action `stage` facts separate those attempt-wide flags into steps. After
public market entry each decision records, once the action has been chosen:
contacts with authoritative strip rectangles (`moved_in`, `placed_on_body` or
`already_inside`, whether that strip was in the delayed observation, the guard
branch and other live strips), health plus armor lost to published shots by
shooter, unshot loss on steps ending inside a working strip (`strip_loss`, a
work-pulse inference, not a server hit count), remaining `unattributed_loss`,
ranged rounds at entry and the fatal step's cause. Several owners on one
strip hit means overlapping rectangles. The tanks endpoint records the same
facts after market completion as `continuation`. None of this feeds the
controller; the matched cohort report is byte-identical without the field.

To reconstruct those recorded windows with the existing world, fighter and
shot presenters (a real renderer is required):

```bash
"$GODOT_BIN" --path client --audio-driver Dummy --windowed --resolution 1280x720 --script ../tools/review_campaign.gd -- "$PWD/.agents/playtest/campaign.json" "$PWD/.agents/playtest/campaign-frames"
```

The tool writes numbered PNGs under `first_kill/` and `fatal_hit/` when those
events exist. View sequentially at 20 frames/second. A missing event produces no
window; an invalid report or failed image write fails the command. Require its
`campaign review: PASS` marker and clean error logs. This reconstruction omits
HUD, audio and input-to-display timing. It supports scene/tell inspection, not
those claims.

M19 mechanic windows use numbered event directories, and reconstruct the
recorded jetpack and work-strip state as well as fighters. Their observer data
can include an unseen strip, so a visible reconstruction is not evidence the
controller recognized it; consult the separate recognition timestamp.
The tanks endpoint adds a `tanks` stage with a `tanks_leg` window from market
completion and a `tanks_climb` window from the first rise above a metre; the
renderer requires that rise to exist in the climb's frames.

By default a completed survey writes every failure and exits successfully.
`--assert` instead fails if **any** trial misses its scenario's endpoint, after writing the
report. Timeouts and exhausted continues never count as clears. The current
stress matrix does not pass that strict all-clear gate; its failures are leads
for inspection, not proof that the game is unfair. Unit tests gate perception,
turning, actual completion, retry exhaustion, determinism and report failures.
CI retains a seed-42 matrix in its `playtest-reports` artifact without the
strict all-clear assertion. A successful job therefore means the evaluator ran
and its regression tests passed; consult the report for gameplay outcomes.

```bash
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --frag-limit 3 --time-limit-seconds 45 --assert --report .agents/playtest/run.json
bash tools/playtest_roster.sh
cargo run -p fragr-playtest --locked -- --fanout-matrix --fanout-seconds 10 --report .agents/fanout/matrix.json
```

The optional fanout matrix starts a fresh seed 42 server for each of twelve
local rosters: 4 or 16 active socket fighters and 1, 8, or 16 spectators on
Arena Duel and Tripoint Works. Each spectator consumes the live WebSocket
stream. The largest roster uses all 32 connections allowed from one loopback
address. The report records authoritative session and fanout enqueue timing samples,
outbound queue high water and overflows, watcher text payload bytes per second,
snapshot gaps, disconnects, and snapshot arrival spread among watchers for the
same tick. Payload bytes include all received text messages during the sample,
but exclude WebSocket framing and TCP overhead. Arrival spread is a relative
local delivery measure, not absolute server-to-client latency.
`--fanout-seconds` selects 2 to 120 measured seconds per row; 10 is the
default. Reports use schema 1. Keep the JSON and record the
host and revision when comparing results. This local matrix does not establish
Internet latency or public-server capacity.

`--soak` runs the real `fragr-server` binary (the one beside this tool, or
`--soak-server PATH`) as a child with `--soak-bots` rule bots, `--agents` reflex
agents and `--soak-spectators` reading spectators on loopback. Every
`--soak-sample-seconds` it writes one NDJSON line to `--soak-log` (default
`.agents/soak/soak.ndjson`, with the server log beside it) holding
`GET /status?clients=1` and the server's resident set from the OS
(`/proc/<pid>/status` on Linux, `tasklist` working set on Windows, `ps` on
macOS; `rss_unavailable` says why when it cannot). A `start` line records the
configuration, source commit and host; a `verdict` line ends the file. With
`--assert` it exits non-zero on a server exit, a missing status, a tick that did
not advance, a client or server connection count off the requested roster, any
`degraded` health sample (including `tick_rate_low`), a lifetime p99 at or above 50 ms, an outbound queue
overflow, or resident set growth past half the first sample or 64 MiB,
whichever is larger. The server is stopped through its own process handle.

```bash
cargo build -p fragr-server -p fragr-playtest --release --locked
target/release/fragr-playtest --soak --soak-seconds 3600 --soak-sample-seconds 60 --soak-bots 4 --agents 4 --soak-spectators 2 --soak-map-rotate --assert
```

CI runs the same command for 120 seconds with 15 second samples in its own
job. A local run of an hour or more belongs in
[`observability-soak.md`](../../docs/plans/observability-soak.md); a twenty-four
hour run is a release gate, not a CI step.

`--traffic` is the synthetic load. It starts the same local `fragr-server`
binary (or `--traffic-server PATH`) and connects plain fighters plus
read-only spectators. Each fighter sends movement and a held trigger at
`--traffic-hz` (default 60, the pace of a displayed client frame) and does
not pathfind. Spectators only read. One loopback address holds 32
connections. A roster up to 64 uses `127.0.0.2` and onward for the extra
clients. Linux and Windows already assign `127.0.0.0/8`. macOS assigns
only `127.0.0.1` until `ifconfig lo0 alias` adds the extra addresses, so
a roster past 32 on macOS needs those aliases. The process cap is 64 sockets. The report is
`.agents/traffic/report.json` unless `--report` names another file, and the
server log is written beside it. `--assert` fails when a client never
welcomes, drops during the window, the tick stalls, the status counts drift,
or the fighters send less than half the actions a steady rate would send.
Tick time and health are printed. A debug build can miss the 50 ms budget,
and this command does not by itself fill the measurement table.

```bash
cargo run -p fragr-playtest --locked -- --traffic --traffic-fighters 8 --traffic-spectators 4 --traffic-bots 4 --traffic-seconds 10 --assert
```

On the scripted-agent command at the top of this file, `--assert` exits non-zero when a frustration threshold is crossed: no round completed, an agent stuck (no movement and no fire during an active round) for more than five seconds, spawn deaths above ten percent of frags, or fewer than one frag per minute with four or more agents. It also fails when the sticky flechette, rail, or scatter clean-hit time to kill leaves the 0.5 to 1.2 second band (the #124 table). CI runs that command on every PR. Reports land under the gitignored `.agents/` directory; put the summary table for a change under test into that change's plan doc.

Use `--tiers reflex`, `--tiers planner`, or `--tiers reflex,planner` to deal
policies round robin. Both use shared 3D cover checks and the bounded heightfield
route controller exported by the server. The planner holds weapon range and seeks
useful pickups. Routes can use stairs and drops; jumping paths, overhangs, and
moving geometry are not implemented.

The roster wrapper runs mixed policies with 2, 6, 6, 8, 12, and 16 clients on
maps 1 through 6, retaining every report and failure. It runs in Linux CI. These
controlled arena rounds deliberately exclude timed bosses. Production-session
enemy behavior and mixed human/agent/spectator checks live in
`server/src/tests/roster.rs`; rendered inspection uses `client/qa/roster.json`.
Neither suite proves unimplemented co-op, campaign encounters, or objective modes.

Current shot evidence supplies weapon, 3D surface distance, and lethal identity
independently of the surviving roster. Trades count both shots, and a weapon swap
cannot rewrite the finisher. Legacy outcomes without evidence use available
snapshot data; a missing shooter is counted under `Unknown` rather than dropped.
Legacy distances are horizontal centre estimates. Do not compare those distances
directly with current traveled distances. Damage includes armour and overkill.

Keep seed, map, policies, duration, sample counts, and source revision with any
comparison. Small samples and perfect-aim agents are not a weapon-balance verdict.
The deeper workflow is in `../../docs/plans/agent-playtest-loop.md`.

Capture the flag runs on Arena Duel, Directive 17, and Sector 9. The two socket gates below stay on Sector 9. The controlled route runs one
unopposed joined fighter through ordinary navigation and server-owned flag
rules. It fails unless that fighter takes and carries the flag, the server
emits its matching capture event, the final score credits its side and the
round ends at the capture limit. The contested gate runs four mixed agents and
keeps the usual round, roster and frustration checks; it also requires combat,
authoritative flag state and a final capture score. A particular contested
match need not capture. Keep its flag outcomes in the report for pacing review.

```bash
cargo run -p fragr-playtest --locked -- --ctf-route-smoke --report .agents/playtest/ci-ctf-route.json
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 1 --time-limit-seconds 180 --max-seconds 240 --assert --ctf-contested --report .agents/playtest/ci-ctf.json
```

The ordinary CTF `--assert` still requires pickups and captures. The split
gates are described in
[`ctf-socket-smoke.md`](../../docs/plans/ctf-socket-smoke.md).
