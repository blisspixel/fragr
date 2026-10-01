# CTF attacker blockers

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. **Spend:** $0.

## Goal and scope

The contested four-agent CTF sample places a planner and reflex fighter on each
side. Stable callsign election makes the planners defenders. Only the planner
policy currently fights a visible close blocker, leaving both reflex attackers
unarmed in practice as they approach the opposing defenders. The observed
sample ended at the time limit without an attacker firing, flag take or capture.

Share the existing visible-blocker combat interruption across normal noncarrier
tiers. Preserve the original carrier objective priority, RouteProbe behavior,
defender election, maps, spawns, weapons, transport and authoritative outcomes.
This is a harness policy correction, not a server combat change or a new control
channel. No dependency, paid operation or release publication is needed.

## Verification

Focused tests must show reflex and planner firing at a visible nearby blocker,
resuming the flag route after the blocker leaves, preserving the unopposed
RouteProbe, and prioritizing carrying a flag over that interruption. Run the
playtest crate tests and lint, followed by the exact existing contested map 4
command with a distinct report. Do not lower any assertion or acceptance gate.
Record actual results and remaining limitations below. Debug builds avoid
replacing the release executables owned by active client checks.

## Evidence

The shared blocker branch now applies to both ordinary noncarrier tiers. Tests
cover both firing and route resumption, plus carrier priority and RouteProbe
behavior. The role-election fixture puts opposing sides outside local combat
range so its unchanged assertions continue to test election independently.

`cargo test -p fragr-playtest --locked` passed 72 library tests and five CLI
tests. `cargo clippy -p fragr-playtest --all-targets --locked -- -D warnings`
passed. The final focused blocker test also passed after the carried-flag
fixture was made internally consistent. Logs are
`.agents/m04-buildout-20260930/ctf-blockers-tests.log`,
`ctf-blockers-clippy.log` and `ctf-blockers-focused.log`.

The exact contested command passed with exit 0:

```text
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 1 --time-limit-seconds 180 --max-seconds 240 --assert --ctf-contested --report .agents/playtest/m04-ci-ctf-blockers.json
```

| Observed metric | Previous sample | Corrected sample |
|---|---:|---:|
| Simulated seconds | 181.9 | 136.25 |
| Frags | 12 | 9 |
| Reflex firing ticks, summed | 0 | 17 |
| Flag takes | 0 | 2 |
| Drops | 0 | 1 |
| Returns | 0 | 1 |
| Captures | 0 | 1 |
| Carrier seconds | 0 | 40.6 |
| Opening spawn deaths | 0 | 0 |
| Ending | Time limit | Capture limit |

Reports: `.agents/playtest/m04-ci-ctf.json` and
`.agents/playtest/m04-ci-ctf-blockers.json`. The corrected sample ended with
Coalition 1, Union 0; both reflex fighters fired and scored. This proves the
previously failing contested configuration can take and capture under combat.
It is one seed, map and mixed-tier roster, not general CTF balance acceptance.
No map, spawn, weapon or gate was changed. Source is frozen for the parent's
final workspace verification; no release executable was replaced.
