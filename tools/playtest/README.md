# fragr-playtest

Scripted agents play fragr rounds and file a metrics report to catch stalled
rounds and combat regressions before rendered playtesting. The harness boots the
authoritative server on a free loopback port, connects agents over WebSocket,
and observes frags, gaps, spawn deaths, idle/stuck time, weapon use, and payload
sizes. These measurements support playtesting; they do not establish fun alone.

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

`--assert` exits non-zero when a frustration threshold is crossed: no round completed, an agent stuck (no movement and no fire during an active round) for more than five seconds, spawn deaths above ten percent of frags, or fewer than one frag per minute with four or more agents. It also fails when the sticky flechette, rail, or scatter clean-hit time to kill leaves the 0.5 to 1.2 second band (the #124 table). CI runs exactly that command on every PR. Reports land under the gitignored `.agents/` directory; put the summary table for a change under test into that change's plan doc.

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
