# Network regression evidence

Local Windows verification, 2026-10-08: all eight CI network cases, seven
mixed-roster cases and the two-minute native soak pass. One additional Gulch
smoke passes on the final release harness. The
[machine-readable receipt](network-regression-20261008.json) retains exact
arguments, executable and source hashes, each log/report hash and anonymous
soak measurements. Raw artifacts remain under
`.agents/open-issues-20261008/final-network/`.

The [CI arguments](../../.github/workflows/ci.yml) and all seven rows/flags from
[`playtest_roster.sh`](../../tools/playtest_roster.sh) run directly on private
executable copies, omitting only the wrapper's redundant build and changing
output paths. No cargo command, source edit or threshold change ran in this
verification. Ordinary cases use the harness's real-loopback server library;
the soak explicitly passes its copied native executable through `--soak-server`.

| Executed artifact | SHA-256 | Scope |
|---|---|---|
| Copied harness | `ba5678d41df41a724fcc4f689a0306e7c0ddf3a07cb113ca8b45535a33af0204` | Fifteen CI/roster cases and soak control. |
| Copied native server | `04d4c775f23a31a569c16a8218637daf20c112c512c2ed7ea0ea5c378c3ce1a0` | Two-minute soak child. |
| Final release harness | `d02756f41b91e9ab38697ba5bbeca81c9e4d39e18c90d63e579165a3be2c7962` | Additional twelve-agent Gulch seed-42 smoke only. |

The 254 hashed native/playtest source, map and contract files remain unchanged
through the checks. The final M01 twelve-row and actual-death acceptance work
changes test fixtures only, with no production change. The earlier and final
executable hashes remain distinct. The root composition owns subsequent native
workspace/tour artifacts and their benchmark evidence.

| Case | Agents | Rounds | Frags | Result |
|---|---:|---:|---:|---|
| CI free-for-all | 4 | 1 | 8 | Pass |
| CI team deathmatch | 4 | 1 | 9 | Pass |
| CI Rail only | 4 | 1 | 6 | Pass |
| CI team Licence to Kill | 4 | 1 | 9 | Pass |
| CI CTF capture route | 1 | 1 | 0 | Pass, scored capture |
| CI contested CTF | 4 | 1 | 11 | Pass, scored capture |
| CI Sabotage route | 2 | 1 | 0 | Pass, plant and defuse |
| CI contested Sabotage | 4 | 1 | 2 | Pass |
| Arena Duel, seed 67 | 2 | 1 | 5 | Pass |
| Compliance Yard, seed 42 | 6 | 1 | 29 | Pass |
| Directive 17, seed 19 | 6 | 1 | 21 | Pass |
| Sector 9, seed 42 | 8 | 1 | 34 | Pass |
| Reclamation Gulch, seed 42 | 12 | 1 | 35 | Pass |
| Tripoint Works, seed 42 | 16 | 1 | 70 | Pass |
| Holdfast Atoll, seed 42 | 16 | 1 | 77 | Pass |

The seven roster rows' longest observed stall is 0.55 seconds. All fifteen
cases have zero opening deaths. Compliance Yard reports two respawn-window
deaths and Sector 9 one; their unchanged checks pass. Objective route probes
retain their dedicated checkers, including intentional held interactions.
The additional final-harness Gulch smoke records one completed round, 46 frags,
a 0.55-second longest observed stall and zero opening or respawn-window deaths.
Asynchronous identities and admission order make repeated seeds distinct runs.

The soak uses the exact CI settings: 120 seconds, 15-second samples, four rule
bots, four agents, two spectators and map rotation. All nine samples retain
the expected agents/spectators and healthy status. Observed samples cover
Arena Duel and Compliance Yard; this is not a full seven-map soak.

| Same-machine soak measurement | Observed result |
|---|---|
| Measured interval and ticks | 120.013 seconds, ticks 41 through 2,441 |
| Tick rate | 19.9978 Hz |
| Handler window p99, start/end | 1.166 / 0.918 ms |
| Handler lifetime p99 / maximum | 0.950 / 1.932 ms |
| Handler over-budget steps | 0 |
| Queue overflows / degraded samples | 0 / 0 |
| Working set, start/end/maximum | 60.62 / 61.18 / 61.25 MiB, Windows `tasklist` |
| Mean bytes per client per second, out/in | 58,228 / 2,336 |

These are local functional and anonymous operator measurements in the shared
development session, not an isolated CPU benchmark, renderer measurement,
physical LAN/WAN proof, capacity ladder or long-duration durability result.
The native status reports an unknown build commit; the exact executable hash
binds its evidence. No network failure was discarded and no gate was weakened.
Dependency-advisory warnings belong to the separate dependency check. No
fresh-player, final balance, final art or complete-campaign acceptance follows.
New spend is $0, with no paid calls or external issue writes.
