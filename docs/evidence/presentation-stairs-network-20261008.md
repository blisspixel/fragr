# Presentation and stair network verification

Status: **passed locally**, 2026-10-08. All sixteen fresh checks pass on copied
frozen executables. The runner verifies exact CI and roster parameters before
launch; assertions and thresholds are unchanged. No build runs during the matrix.

| Case | Exit | Wall seconds | Frags | Captures |
| --- | ---: | ---: | ---: | ---: |
| ci/ci | 0 | 31.82 | 8 | 0 |
| ci/ci-tdm | 0 | 38.31 | 10 | 0 |
| ci/ci-rail-only | 0 | 27.81 | 8 | 0 |
| ci/ci-tdm-licence | 0 | 23.56 | 8 | 0 |
| ci/ci-ctf-route | 0 | 61.11 | 0 | 1 |
| ci/ci-ctf | 0 | 182.01 | 17 | 0 |
| ci/ci-sabotage-route | 0 | 32.46 | 0 | 0 |
| ci/ci-sabotage | 0 | 26.63 | 2 | 0 |
| roster/map1-seed67 | 0 | 64.63 | 5 | 0 |
| roster/map2-seed42 | 0 | 62.98 | 33 | 0 |
| roster/map3-seed19 | 0 | 50.17 | 23 | 0 |
| roster/map4-seed42 | 0 | 62.02 | 38 | 0 |
| roster/map5-seed42 | 0 | 50.75 | 39 | 0 |
| roster/map6-seed42 | 0 | 59.01 | 72 | 0 |
| roster/map7-seed42 | 0 | 35.48 | 42 | 0 |

The dedicated CTF route proves one take and one capture. The contested CTF
case records seventeen frags, two takes, one drop, one return and zero captures,
ending at its time limit. Its passing assertions do not establish a contested
capture. The dedicated Sabotage route proves a plant and defuse; the contested
case plants and ends by elimination. Low Water's separate full match keeps its
own [evidence](low-water-sabotage-20261008.md).

The 120-second soak uses four rule bots, four agents and two reading spectators,
with map rotation and nine samples. It reports zero queue overflows, degraded
samples and tick-budget overruns. The owned native process retires. This is a
short Windows loopback check, separate from long-duration, physical LAN/WAN,
cross-platform, hardware-renderer, human-balance and population acceptance.

Server SHA-256: `3dabae6ba53355fa349b11d253c83fd45ae631b8091f8ce6226ae1b79617c7d4`.
Playtest SHA-256: `1384279d527c1e6098cfebb9e6739c5bbda788db809278b08963c513d50f9524`.
Ordinary cases use the harness's embedded authoritative server library; the
soak uses the copied standalone native server. Source and copied binaries stay
unchanged. Current native work remains an uncommitted development snapshot.

The [machine receipt](presentation-stairs-network-20261008.json) binds every
command, numeric exit, log, report, source file, copied executable and actual
soak verdict. Raw artifacts remain under
`.agents/presentation-stairs-composition-20261008/network/`. Earlier network
receipts retain their original identities. Spend is $0.

All 318 bound native source files are also retained byte for byte under
`.agents/presentation-stairs-composition-20261008/frozen-native-source/`.
The retention manifest in the machine receipt preserves this snapshot when
subsequent development changes the working tree.
