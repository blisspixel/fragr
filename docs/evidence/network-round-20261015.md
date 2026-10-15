# October 15 live network checks

The composed working tree passed the eight `AGENTS.md` network scenarios, the
seven-map roster wrapper and the 120-second release soak. Local logs and JSON
reports are retained under `.agents/round-20261015/`. These checks use real
WebSocket clients and ordinary action traffic. They do not establish physical
LAN quality, public-host capacity, GPU performance or human enjoyment.

Release binaries were built from this round's working tree above `902ec8f`.
Embedded build metadata still names that base commit. The final subsequent
native change only corrects the Walker range's Host text and adds fixture/tests;
the focused Rust 1.97.1 Walker suite separately verifies that final source.

## Required scenarios

All eight commands passed with exit status zero: free-for-all, team deathmatch,
Rail-only, team Licence to Kill, CTF route smoke, contested CTF, Sabotage route
smoke and contested Sabotage. The Licence to Kill check uses the required six
frag, sixty-second configuration, recorded in `ci-tdm-licence-exact.json`.
An earlier shorter run remains separately retained and does not substitute for
the required configuration. These scenarios recorded zero spawn deaths.

Contested CTF recorded an actual take, drop, return and 11.6 carrier-seconds,
but no capture before the 0-0 time limit. Its pass establishes contested flag
interaction, not a successful capture or satisfactory match pacing. Sabotage's
route smoke recorded plant and defuse. Its contested match recorded a plant
and coalition elimination. These are bounded controller observations.

## Roster wrapper

`bash tools/playtest_roster.sh .agents/round-20261015/roster` passed all seven
map assertions. Mixed reflex/planner client counts and measured outcomes:

| Map | Clients | Frags | Seconds | Spawn deaths | Opening spawn deaths |
|---|---:|---:|---:|---:|---:|
| 1 | 2 | 6 | 61.95 | 0 | 0 |
| 2 | 6 | 29 | 61.95 | 0 | 0 |
| 3 | 6 | 24 | 54.60 | 0 | 0 |
| 4 | 8 | 37 | 56.20 | 6 | 0 |
| 5 | 12 | 50 | 61.90 | 0 | 0 |
| 6 | 16 | 66 | 53.40 | 3 | 1 |
| 7 | 16 | 69 | 55.00 | 0 | 0 |

Passing wrapper thresholds does not imply zero spawn deaths. Map 4 and map 6
retain the reported cases and positions in `roster-wrapper.log` and their
per-map reports; no spawn implementation changes were made in this check.

## Release soak

The required 120-second rotating-map soak used four agents, four server bots
and two spectators, sampled every fifteen seconds. `soak.ndjson` ends with
`passed: true`, no problems, nine samples and 2,400 measured ticks.

- Measured tick rate: 19.99984 Hz.
- Lifetime tick p99: 2.23 ms; maximum: 11.29 ms.
- Over-budget ticks, queue overflows and degraded samples: zero.
- RSS: 60.5 MiB initially, 62.1 MiB finally and at maximum.
- Mean outbound traffic: 58,736 bytes per client per second.

This is local release CPU/network evidence under the recorded small roster,
not evidence of large-server capacity or renderer performance.
