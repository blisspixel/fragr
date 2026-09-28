# Sector 9 carry episode evidence

**Status:** implemented, 2026-09-28. Stacked after [external-agent roles](ctf-external-agent-roles.md). Human and spectator CTF acceptance remains open in the [mode plan](capture-the-flag.md).

## Goal and why

The default six-a-side Sector 9 sample ended at the 180-second clock in all five baseline rounds and all five rounds with stable defender roles. The second policy produced 20 flag takes, 15 drops and four captures, but those totals cannot show where a carry failed. Measure each carry from the observer's authoritative flag events and snapshots before changing tactics, map geometry or round rules. This is a local agent diagnostic, not a human balance verdict.

## Scope and contract

- Extend `tools/playtest`'s existing observer and report. One carry begins at a server `taken` event and ends at its `dropped` or `captured` event, or a round end. Match the flag's team and carrier identity. Keep at most 256 episode records per observation; count omissions explicitly. Store aggregate observations per episode, never a copy of each snapshot.
- For each episode record observed carrier ticks, first and closest horizontal distance to the carrier's home stand, ticks while the carrier's own flag was away, and ticks within capture radius while that flag was away. A drop may be marked as a combat death only when a same-tick `frag` names that carrier. State unknown or missing evidence honestly.
- Preserve existing report fields, old JSON defaults, Rust/server authority, CTF wire and score rules, server and client behavior, and the existing agent policy. The shared navigator already steers the external agents around cover. Do not substitute a new pathfinder for this measurement.

## Verification and comparison

Add deterministic event and snapshot fold tests for capture, combat drop, noncombat drop, home-flag denial, round end, legacy report defaults, and the 256-episode bound. Run focused playtest tests, workspace formatting, Clippy and tests. Then rerun seeds 40 through 44 with twelve alternating Reflex and Planner agents, six per side, one Sector 9 round, the default three-capture limit and a 180-second clock. Use the same command shape as the [role sample](ctf-external-agent-roles.md), write reports under ignored `.agents/`, and record each seed, including failures, in this plan. The socket runs can vary because agent IDs and action timing are not replay-fixed. Comparing these runs to the earlier seed table is descriptive, not a controlled causal trial.

The decision is based on carry fates and progress: deaths before midfield suggest protection or route tactics; carriers reaching home while their flag is away suggest recovery coordination; long journeys with little progress suggest a route problem. A human and spectator session is still required for route clarity, readability and fun.

## Spend and success

External spend is $0. No paid API, cloud resource or Terraform apply. Success means bounded per-carry evidence appears in the report, tests cover its event order and missing-data paths, and the five live rounds are tabulated honestly. No change to the default CTF rule is justified solely by this small agent sample.

## Pre-review exploratory rounds, 2026-09-28

These first five rounds used a pre-review binary. Their table is retained as exploratory evidence; the corrected event identity and deadline gate is measured separately below. Ran the debug `fragr-playtest` binary on the Windows AMD Ryzen 7 7840U host, from this uncommitted branch based on `357ad1b`. Each seed used `target/debug/fragr-playtest.exe --agents 12 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 3 --time-limit-seconds 180 --max-seconds 190 --seed SEED --report .agents/playtest/ctf-carry-seed-SEED.json`. The five processes ran serially. JSON reports and console logs are ignored under `.agents/playtest/`. Every process exited 0 and its authoritative round ended at the time limit after 181.9 observed seconds. The reports recorded no omitted carry episodes.

| Seed | Takes | Drops | Combat drops | Returns | Captures | Carrier s | Own flag away ticks | Home blocked ticks | Frags | Final Union:Coalition |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 40 | 1 | 1 | 1 | 1 | 0 | 8.05 | 0 | 0 | 85 | 0:0 |
| 41 | 1 | 0 | 0 | 0 | 1 | 29.00 | 0 | 0 | 79 | 0:1 |
| 42 | 1 | 1 | 1 | 1 | 0 | 6.00 | 0 | 0 | 86 | 0:0 |
| 43 | 2 | 1 | 1 | 1 | 1 | 38.15 | 0 | 0 | 77 | 1:0 |
| 44 | 5 | 3 | 3 | 1 | 2 | 63.10 | 216 | 0 | 66 | 2:0 |
| **Total** | **10** | **6** | **6** | **4** | **4** | **144.30** | **216** | **0** | **393** | |

All six dropped carries matched a same-tick frag naming the carrier. Their closest observed distances to home were 100.3, 110.4, 97.3, 95.0, 121.4 and 118.7 world units. The home stand was about 140 units from an enemy stand, so these drops happened early in the return trip. The four captured carries each reached within about 2.6 units on a carried snapshot and then scored on a server tick. Seed 44 had 216 sampled ticks (10.8 seconds) during which a carrier's own flag was away, but no carrier was observed inside its own capture radius while blocked. The report does not diagnose why a fighter died, whether an escort would have saved it, or whether people can read the route.

The earlier role-policy sample on the same host had 20 takes, 15 drops and four captures across these seed numbers. This exploratory repeat had 10, six and four. The corrected run below supersedes this table for verification. The variation itself is useful evidence that these seed labels do not define exact live replays.

The server sends a snapshot before its same-tick events. The observer seeds a new episode from that compact snapshot, then samples future snapshots while the flag names the same carrier. A capture's final snapshot has already returned the flag home, so the closest recorded carried distance can remain just outside the 2.5-unit touch radius even for a scored carry. The combat-drop field proves a same-tick named frag, not the exact weapon or shot that caused the death.

## Corrected five-run measurement

An independent review found that a flag end event must match both flag and carrier, and that the observer must drain same-tick events after its maximum-tick snapshot. The implementation now keeps a mismatched prior episode as `incomplete`, counts unmatched end events, and drains until the next snapshot or a bounded one-second wait. Focused tests cover those boundaries, missing position evidence, and the 256-episode cap. The binary was rebuilt after these changes. The five corrected processes ran serially with the same flags above, writing `.agents/playtest/ctf-carry-final-seed-SEED.json` and corresponding `.log` files. All exited 0, completed one 181.9-second round, and ended by `Time limit reached`.

| Seed | Takes | Drops | Combat drops | Returns | Captures | Carry at clock | Carrier s | Own flag away ticks | Home blocked ticks | Frags | Final Union:Coalition |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 40 | 3 | 3 | 3 | 2 | 0 | 0 | 15.55 | 0 | 0 | 86 | 0:0 |
| 41 | 2 | 0 | 0 | 0 | 2 | 0 | 58.00 | 0 | 0 | 76 | 2:0 |
| 42 | 7 | 5 | 5 | 2 | 1 | 1 | 80.00 | 544 | 0 | 71 | 1:0 |
| 43 | 3 | 2 | 2 | 1 | 1 | 0 | 52.25 | 204 | 0 | 75 | 0:1 |
| 44 | 1 | 1 | 1 | 1 | 0 | 0 | 6.95 | 0 | 0 | 87 | 0:0 |
| **Total** | **16** | **11** | **11** | **6** | **4** | **1** | **212.75** | **748** | **0** | **395** | |

The 16 takes resolve into 11 combat drops, four captures and one still carried when the clock ended. No episode was omitted or had an unmatched end event. Dropped carriers' closest observed horizontal home distances ranged from 27.6 to 133.4 world units. The carrier at the clock had reached 10.9 units from home after 28.7 observed seconds. Own flags were away for 748 carrier-snapshot ticks across seeds 42 and 43, but no carrier was observed inside its own capture radius while blocked. The sample points to carrier survival and some late round timing as better next measurements than changing the home-flag requirement. It does not prove an escort tactic, a rule change, route readability, balance or fun. A human and spectator match remains the acceptance gate.

These five runs differed from both the earlier role-policy table and the pre-review sample despite the same seed numbers. Process-local IDs and live socket timing vary. No difference between the tables establishes a causal effect of the reporting change. The corrected table is the evidence for this implementation.

## Verification and handoff

The implementation branch `test/ctf-carry-episodes` is based on `357ad1b`.
No external service was used, and external spend was $0. The corrected sample
command above used the rebuilt debug binary, ran each seed serially, and
stored reports and logs under ignored `.agents/playtest/`.

- `cargo test -p fragr-playtest --lib ctf_carry --locked`: five tests passed.
- `cargo test -p fragr-playtest --lib observer_max_tick --locked`: one test passed.
- `cargo fmt --all -- --check`: passed.
- `cargo clippy --workspace --all-targets --locked -- -D warnings`: passed.
- `cargo test --workspace --locked`: passed, including 537 server library tests with two ignored.
- `cargo llvm-cov --workspace --locked --fail-under-lines 90`: passed at 93.58 percent unfiltered workspace line coverage (59,874 lines, 3,841 missed).

This diagnostic does not replace a human and spectator match. The next CTF acceptance step is to observe that match and record route clarity, flag state readability and fun before changing balance or extending the mode to other maps.
