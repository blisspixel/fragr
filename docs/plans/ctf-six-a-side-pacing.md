# Sector 9 six-a-side pacing sample

**Status:** implemented in [draft PR #284](https://github.com/blisspixel/fragr/pull/284), 2026-09-28; full CI pending. Stacked after the [first CTF route](capture-the-flag.md). This is a measured agent check before changing objective policy or calling the mode balanced.

## Goal and why

Measure the default first-to-three capture rule on Sector 9 with twelve mixed Reflex and Planner agents, six per side. The CI smoke uses four agents and ends on one capture; earlier twelve-agent runs often stalled or scored once. Neither establishes whether the default 180-second round produces a useful objective arc under contention.

## Scope

- Extend the existing `fragr-playtest` report with `flag_drops` and `flag_returns` from the already typed flag events, plus the most recent authoritative round-end reason and capture score. Keep `flag_takes`, `captures`, `carrier_seconds`, frags and side roster counts. Add a focused fold test so these counts cannot silently drift from event semantics.
- Run five fixed-seed observations, 40 through 44, with `--agents 12 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 3 --time-limit-seconds 180`. Use a bounded `--max-seconds` that allows the round to finish and write each JSON report under ignored `.agents/`. The live socket runs can vary on repeat: process-local player IDs and asynchronous action timing are not replay-fixed. This measures the harness's external agent policy with zero server rule bots.
- Record each seed's match duration, takes, drops, returns, captures, carrier time, frags, completed round and final side score when observable. Preserve failed or scoreless runs as evidence; no selection of the nicest seed.

## Architecture and non-goals

This adds report fields only. It does not change game events, the wire, bot policy, map, tick rate, client UI, CI thresholds or the score rule. The harness reads server-owned events through its existing observation seam. A report count cannot establish why a carrier died or whether a person enjoyed the route. Sector 9 is a staged league scenario, so flags remain competition objects and never stand in for campaign captives.

## Verification and spend

Run the focused report test, formatting, Clippy and workspace tests, then the five real socket runs. Record command, source revision, host, results and interpretation here. Existing CI and coverage gates remain unchanged. No paid API, asset or cloud resource is needed; external spend is $0.

## Five-run baseline, 2026-09-28

Ran the debug `fragr-playtest` socket harness on Windows with an AMD Ryzen 7 7840U, using twelve external agents, alternating Reflex and Planner, six per side, zero server rule bots. Command for each seed: `target/debug/fragr-playtest.exe --agents 12 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 3 --time-limit-seconds 180 --max-seconds 190 --seed SEED --report .agents/playtest/ctf-pacing-seed-SEED.json`. Reports and console logs are ignored local diagnostics. The report implementation is in `cfb1a93`; the binary used the same code before a later test-only change and documentation edits.

| Seed | Seconds | Takes | Drops | Returns | Captures | Carrier seconds | Frags | Final score (Union:Coalition) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 40 | 181.9 | 8 | 6 | 3 | 1 | 59.6 | 84 | 1:0 |
| 41 | 181.9 | 6 | 4 | 3 | 1 | 51.8 | 87 | 1:0 |
| 42 | 181.9 | 5 | 5 | 5 | 0 | 27.1 | 91 | 0:0 |
| 43 | 181.9 | 9 | 8 | 5 | 1 | 64.7 | 77 | 0:1 |
| 44 | 181.9 | 3 | 3 | 3 | 0 | 15.2 | 102 | 0:0 |

All five completed one round with the authoritative reason `Time limit reached`; none reached the default three-capture limit. Together they recorded 31 takes, 26 drops, 19 returns, three captures and 441 frags. These are fixed-seed live observations, not exact replays. Repeated runs can vary because live player IDs and asynchronous action timing are not replay-fixed. The 12-agent roster demonstrates server admission and objective event flow on this Windows host, not small-host capacity, human balance, or a fun verdict.

The low conversion suggests a policy issue worth testing. The current external-agent policy sends every noncarrier teammate to a dropped or stolen own flag, and sends every noncarrier home when an ally carries the enemy flag. That can empty the attack route. First test a single stable defender per side, leaving the others on attack, with carrier and dropped-flag recovery priority preserved. Compare the same five fixed-seed observations before considering escort or Planner combat changes. The server rule-bot defender already has a separate gate and is outside this harness sample.

The focused report test passed and verifies all four flag event kinds, the two real server round-end reasons, the latest round's score, and old JSON defaults. `cargo fmt --all -- --check`, workspace Clippy with warnings denied, `cargo test --workspace --locked`, and `git diff --check` passed. The workspace test run included 537 passing server library tests with two ignored, 62 playtest library tests, and the other workspace suites. No paid call or cloud apply was made.

## Success and next decision

The sprint succeeds when all five default-rule results are tabulated honestly and the report accounts for every typed take, drop, return and capture event. If rounds repeatedly time out below three captures or carrier time is dominated by drops, use the event pattern to design explicit attacker, escort and defender priorities and rerun the same seeds. If the automated pacing is promising, test route clarity, spectator comprehension and balance with humans before acceptance.
