# fragr-playtest

Scripted agents play fragr rounds and file a metrics report to catch stalled
rounds and combat regressions before rendered playtesting. The harness boots the
authoritative server on a free loopback port, connects agents over WebSocket,
and observes frags, gaps, spawn deaths, idle/stuck time, weapon use, and payload
sizes. These measurements support playtesting; they do not establish fun alone.

```bash
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --frag-limit 3 --time-limit-seconds 45 --assert --report .agents/playtest/run.json
bash tools/playtest_roster.sh
```

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
