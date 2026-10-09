# Live buildout network verification, 2026-10-08

Status: **passed locally**. This is a fresh local run against copied frozen native executables. No build or paid call ran during verification. Historical network evidence remains unchanged.

Eight exact CI cases and the seven exact roster rows ran with the existing assertions and thresholds. The runner checked their parameters against the current CI and wrapper source before launch. Only executable and output locations differ. Ordinary cases use real loopback sockets and the harness embedded server library; the two-minute soak launches the copied native server.

| Case | Exit | Elapsed seconds | Frags | Captures | Longest observed stall seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| ci/ci | 0 | 31.91 | 8 | 0 | 0.05 |
| ci/ci-tdm | 0 | 30.7 | 10 | 0 | 0.55 |
| ci/ci-rail-only | 0 | 31.51 | 9 | 0 | 0.55 |
| ci/ci-tdm-licence | 0 | 25.27 | 10 | 0 | 0.05 |
| ci/ci-ctf-route | 0 | 61.1 | 0 | 1 | 0.05 |
| ci/ci-ctf | 0 | 182.02 | 12 | 0 | 0.9 |
| ci/ci-sabotage-route | 0 | 32.45 | 0 | 0 | 6 |
| ci/ci-sabotage | 0 | 26.66 | 3 | 0 | 3.05 |
| roster/map1-seed67 | 0 | 62 | 5 | 0 | 0.5 |
| roster/map2-seed42 | 0 | 62 | 30 | 0 | 0.55 |
| roster/map3-seed19 | 0 | 44.83 | 21 | 0 | 0.3 |
| roster/map4-seed42 | 0 | 62 | 33 | 0 | 0.55 |
| roster/map5-seed42 | 0 | 33.93 | 27 | 0 | 0.45 |
| roster/map6-seed42 | 0 | 60.7 | 74 | 0 | 0.5 |
| roster/map7-seed42 | 0 | 58.91 | 69 | 0 | 0.55 |

Objective scope: the dedicated CTF route case resolved 1 flag take and 1 capture. The fresh contested CTF case resolved 12 frags, 0 flag takes and 0 captures, ending with 'Time limit reached'. Its passing existing assertions do not imply a contested capture. The dedicated Sabotage route separately proves a plant and defuse; contested Sabotage retains its actual event counts and round end in the receipt.

Soak: 120 seconds, 4 rule bots, 4 agents and 2 reading spectators, sampled every 15 seconds with map rotation. Verdict: True. The receipt retains observed maps, the complete anonymous summary, native log and process exit code.

Frozen executable SHA-256:

- fragr-server.exe: `149b6711eb120fea228c6b4bd39f2d19657cae00095dd9fa60a310b6b2ddaf61`.
- fragr-playtest.exe: `35d386017ea10cc96acc8aeb6a3dd9d11d159bacaa9cffa9f98551378531bf82`.

The [machine receipt](live-buildout-network-20261008.json) binds every log, report, process code, wall duration, source snapshot and copied executable by SHA-256. Raw evidence is retained under `.agents/live-buildout-20261008/network/`. Source and copied executable hashes remained unchanged throughout the run.

Scope: local Windows loopback networking. Same-machine tick measurements may overlap composed client checks, so they do not establish isolated CPU performance, capacity, hardware renderer performance, physical LAN, WAN, cross-platform support or long-duration stability. This run does not establish fresh-player fun, final balance, final art, connected missions or multiplayer character appearance.
