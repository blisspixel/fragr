# Sector 9 external-agent objective roles

**Status:** implemented locally, 2026-09-28; integration and CI pending. Stacked after the [six-a-side pacing sample](ctf-six-a-side-pacing.md).

## Goal and evidence

The five default-rule, twelve-agent Sector 9 rounds in the pacing sample all reached the 180-second clock. Across those runs, 31 takes became three captures, with 26 drops and 441 frags. The external `fragr-playtest` policy currently orders every noncarrier home when an ally carries the enemy flag, and every noncarrier to the thief when the home flag is stolen. This can abandon both attack and support routes. Test whether one stable defender on each side improves objective conversion without changing authoritative game rules.

## Scope and decision

- Change only CTF goal selection in `tools/playtest/src/lib.rs::policy_action`. Choose one defender per side using the lowest callsign among living noncarriers on that side. A carrying or dead defender yields to the next eligible callsign. The harness assigns unique policy-and-index callsigns; the choice is independent of random player IDs and snapshot order.
- The carrier still returns to its own stand, or to its own dropped flag first. A dropped own flag remains the objective goal for every noncarrier when the existing Planner nearby-combat detour does not preempt it. Otherwise, the defender guards the home stand or pursues its stolen flag, while teammates continue toward the enemy flag. When a teammate has the enemy flag, those teammates follow its current position to support the return route instead of idling at home.
- Keep Planner's existing nearby combat detour. Do not edit server rule bots, scoring, flags, map geometry, wire types, client presentation, navigation, or non-CTF policies. This policy is a harness experiment, not a claim that an unsteered human or player-facing brain agent has these roles.

## Verification

Add focused tests with a six-per-side roster: exactly one stable defender per side, snapshot-order independence, attack goals for other noncarriers, carried and stolen flag states, dropped-home-flag recovery, and carrier return. Run focused Rust tests, formatting and Clippy. After the concurrent M02 checker finishes, rerun the same five socket observations with seeds 40 through 44, twelve alternating Reflex and Planner agents, map 4, one round, default capture limit three, 180-second clock, 190-second maximum. Store JSON under ignored `.agents/` and tabulate each run alongside the existing baseline: elapsed time, takes, drops, returns, captures, carrier seconds, frags, observer snapshot bytes per tick, final score, and round-end reason. Snapshot bytes are the one observer's full JSON payload, not a cloud egress measurement or a per-client throughput guarantee. The live socket sample is not an exact replay because player IDs and action timing vary. Repeated results cannot alone establish causality, balance or fun.

## Spend and success

All work runs locally. External spend is $0. No cloud or paid asset call. Success means the role contract passes focused tests and the paired five-seed table is recorded honestly, including regressions and timeouts. Keep human route readability, human-versus-agent balance and other CTF maps open regardless of this sample.

## Paired five-seed observation, 2026-09-28

Ran on the same Windows AMD Ryzen 7 7840U host as the [baseline](ctf-six-a-side-pacing.md), using the debug playtest binary built from this uncommitted branch based on `412966b`. The M02 Godot checker had completed before the live runs. Each after run used `target/debug/fragr-playtest.exe --agents 12 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 3 --time-limit-seconds 180 --max-seconds 190 --seed SEED --report .agents/playtest/ctf-roles-seed-SEED.json`. The baseline used the same options, with `ctf-pacing-seed-SEED.json` as its report path. The five after runs were serial; their full stdout and stderr are in `.agents/playtest/ctf-roles-seed-SEED.log`. All ten runs exited successfully and completed one round with the authoritative reason `Time limit reached`. The JSON reports and logs are ignored local diagnostics.

| Seed | Policy | Seconds | Takes | Drops | Returns | Captures | Carrier s | Frags | Observer bytes/tick | Final score Union:Coalition |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 40 | Before | 181.9 | 8 | 6 | 3 | 1 | 59.60 | 84 | 3,638 | 1:0 |
| 40 | Roles | 181.9 | 7 | 7 | 3 | 0 | 30.80 | 80 | 3,616 | 0:0 |
| 41 | Before | 181.9 | 6 | 4 | 3 | 1 | 51.80 | 87 | 3,613 | 1:0 |
| 41 | Roles | 181.9 | 3 | 2 | 1 | 1 | 35.25 | 82 | 3,612 | 1:0 |
| 42 | Before | 181.9 | 5 | 5 | 5 | 0 | 27.05 | 91 | 3,574 | 0:0 |
| 42 | Roles | 181.9 | 2 | 0 | 0 | 1 | 46.30 | 75 | 3,677 | 0:1 |
| 43 | Before | 181.9 | 9 | 8 | 5 | 1 | 64.65 | 77 | 3,671 | 0:1 |
| 43 | Roles | 181.9 | 2 | 1 | 0 | 1 | 29.45 | 80 | 3,620 | 1:0 |
| 44 | Before | 181.9 | 3 | 3 | 3 | 0 | 15.15 | 102 | 3,538 | 0:0 |
| 44 | Roles | 181.9 | 6 | 5 | 1 | 1 | 61.40 | 73 | 3,647 | 0:1 |

Across five rounds, the before policy had 31 takes, 26 drops, 19 returns, three captures, 218.25 carrier seconds and 441 frags. The role policy had 20 takes, 15 drops, five returns, four captures, 203.20 carrier seconds and 390 frags. Four role rounds scored at least once versus three before; seed 40 regressed from one capture to none. Every run still timed out with at most one capture, below the default three-capture limit. The observer payload ranged from 3,538 to 3,671 bytes per tick before and 3,612 to 3,677 after. It does not establish total server egress or small-host capacity.

**Decision:** keep the single-defender policy as a clearer external-agent objective assignment and a modest observed improvement in scored rounds and take-to-capture conversion. Do not call the default six-a-side pace solved: five live socket runs are too small and not exact replays, all rounds used the full clock, and one paired seed regressed. The unchanged Planner combat detour can still interrupt any objective goal, including dropped-flag recovery. A separate measured tactic or round-rule experiment, then human route and balance sessions, is needed before accepting the mode's pacing.

Verification on this branch: `cargo test -p fragr-playtest --lib ctf_ --locked` passed four focused tests; `cargo test -p fragr-playtest --lib --locked` passed all 64 tests; `cargo clippy -p fragr-playtest --all-targets --locked -- -D warnings`, `cargo build -p fragr-playtest --locked`, `cargo fmt --all -- --check`, and `git diff --check` passed. The five after socket runs exited 0 and wrote the reports above. Workspace-wide CI remains pending integration. No paid service or cloud resource was used.
