# Sabotage objective ownership, October 15

Scope: local native evidence on Linux x86-64, Rust 1.97.1, baseline `902ec8f`
plus the bounded [objective ownership change](../plans/sabotage-objective-ownership-20261015.md).
No paid operations. Integration and human match acceptance remain separate.

## Reproduced failure and repair

Before changing production behavior, four regression tests failed on the baseline:

- An idle human nearer a planted charge made the assigned bot decline defusing.
- An idle human nearer a loose charge sent the bot to its ordinary holding spot.
- A teammate passing closer made a bot abandon its actual ongoing defuse.
- A bot closer than an already working human attempted to take the same job.

The original failures are retained in
`.agents/sabotage-objective-ownership-20261015/before-isolated.log`.
The tests reach Sector 9 first, so this failure log does not independently prove
each condition on Low Water. The final passing tests exercise both venues.

The controller now selects a registered rule bot for unclaimed work and retains
an eligible participant's actual held defuse. Shared actor eligibility excludes
dead, detached, eliminated and waiting bodies. Spectators, other-side bodies and
campaign/boss actors cannot be assigned. Stable identity resolves distance ties.
The authoritative touch, held Use, interruption and round-result paths are unchanged.

## Native checks

`cargo +1.97.1 test -p fragr-server --locked --lib sabotage -- --nocapture`
passes all 50 matched tests, including six new behavior tests. The idle human and
external-agent cases run the real `GameSession` controller/navigation pass and
complete the normal six-second defuse. Other cases cover an actual plant and
charge pickup through ordinary actions, retained bot work, human/agent work and
release, ineligible/departed workers, empty controller rosters and reordered
distance ties. Both Sector 9 and Low Water are covered by the new tests.

`cargo +1.97.1 clippy -p fragr-server --all-targets --locked -- -D warnings`
passes. Scoped Rust formatting and patch whitespace checks pass. Logs and the
survey JSON remain under `.agents/sabotage-objective-ownership-20261015/`.

The existing release survey, with seeds 40 through 43 and eight rule bots,
passes its unchanged assertions:

```sh
cargo +1.97.1 run -p fragr-playtest --release --locked -- \
  --sabotage-survey --survey-seeds 4 --survey-bots 8 --seed 40 --assert \
  --report .agents/sabotage-objective-ownership-20261015/survey.json
```

| Sector 9, normal round clocks | Result |
|---|---:|
| Completed matches / total | 4 / 4 |
| Decided rounds | 24 |
| Plants / defuses / detonations | 13 / 4 / 1 |
| Attacker round wins | 10 of 24 |
| Mean / longest round | 70.9 / 102.5 seconds |
| Side swaps | 4 |

The survey is bots-only, runs without sockets and covers Sector 9 only. It proves
bounded completion and objective use, not human balance, physical LAN behavior,
network population capacity or renderer performance. The mixed-roster tests
above provide separate deterministic coverage on Low Water.

Checks used a detached baseline checkout to avoid transient Walker schema edits
in the concurrently developed campaign slice. The first fixture needed correction
because opening balance moved its intended carrier. An eligibility test initially
placed a wrong-side actor inside the existing close-enemy combat interruption;
moving that actor away isolated the intended eligibility condition. Neither issue
changed a gameplay assertion or relaxed the existing threat policy. A shared-tree
build encountered the concurrent incomplete schema constructors before isolation;
that failure is not a failure of the Sabotage behavior change.

## Research and design boundary

Primary sources were checked on October 15. Valve's
[AI systems presentation](https://cdn.cloudflare.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)
describes predictable bot decisions, teammate trust, and explicit continuation or
interruption of actions. Those established principles support preserving actual
work and testing observable team outcomes. They do not require a new AI framework.
The more recent GDC
[Adventure Director session](https://gdcvault.com/play/1035589/Game-AI-Summit-Growing-an)
describes combining orchestration with authored level control. Its public abstract
does not establish implementation details or justify expanding this patch into a
director. The concrete fragr defect and existing controller seam determine scope.

Coalition and Union remain existing competitive sides, independent of controller
role. No campaign lore, equipment identities, map geometry or public mode changes.
