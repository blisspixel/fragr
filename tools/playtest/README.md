# fragr-playtest

Scripted agents play fragr rounds and file a metrics report to catch stalled
rounds and combat regressions before rendered playtesting. The harness boots the
authoritative server on a free loopback port, connects agents over WebSocket,
and observes frags, gaps, spawn deaths, idle/stuck time, weapon use, and payload
sizes. These measurements support playtesting; they do not establish fun alone.

The guided campaign survey runs Recall Notice directly through the authoritative
session at 20 simulated ticks per second. It uses the shared mission navigator
and inventory controller with ordinary human actions, finite magazines, earned
pickups, real deaths and the three episode continues. No equipment or health is
granted during play. It needs no sockets, model, credentials or paid service.

```bash
cargo run -p fragr-playtest --release --locked -- --campaign-survey --survey-seeds 8 --seed 40 --max-seconds 600 --report .agents/playtest/campaign.json
```

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

Decisions and actions run at 20 Hz for every profile. Reaction delay limits
acquisition, not decision cadence. Continue is accepted immediately, with zero
simulated menu delay; dead/menu time is not included in the active stall metric.
The report records these assumptions rather than inventing human deliberation.

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

To reconstruct those four-second windows with the existing world, fighter and
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

By default a completed survey writes every failure and exits successfully.
`--assert` instead fails if **any** trial does not depart, after writing the
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
