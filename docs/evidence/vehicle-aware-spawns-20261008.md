# Vehicle-aware spawn checks, October 8

This records local native development evidence for
[vehicle-aware spawn safety](../plans/vehicle-aware-spawns-20261008.md).
It does not establish human balance, physical LAN behavior or a larger-room
population limit. The working source includes additional development changes;
these receipts bind the tested executables rather than claiming a release.

## Behavior and focused proof

Admission and respawn consider current authoritative vehicle hulls as both
occupancy and shot cover. A clear fixed bay takes priority over nearby offsets.
If a side's fixed bays are obstructed, supported alternatives within six metres
remain in that half. If none fits, the admitted seat waits at zero health using
the existing respawn timer. No death is recorded. A successful placement grants
the existing spawn shield and emits one respawn event.

The nine focused cases pass with:

```text
cargo test -p fragr-server --locked --lib sim::spawn --no-fail-fast
```

They cover all three vehicle kinds alive, burning and as retained wrecks;
admission and a real respawn tick; fixed-bay priority; supported same-side
alternatives; a completely obstructed side and later retry; preserved inventory,
input sequence and score while waiting; overhead aircraft; vertical body
clearance; hull cover; and seeded placement preservation. Ordinary interact,
drive and fire requests from waiting human and agent actors cannot take a seat,
move the jeep or fire, even if positive health is retained by another caller.

The existing widest-covered-bay regression also passes. Its first run exposed
a stair-edge compatibility error: an exact static feet-height check excluded
eight Directive 17 bays that use ordinary step clearance. The corrected fixed
bay check retains that allowance and separately rejects true vehicle-hull
intersection. New offset positions retain exact standing clearance and support.
The prior whole spawn-suite run's other seven cases passed, including 500
arrival-order shuffles on each multiplayer venue. The composed workspace gate
owns the final whole-suite rerun.

## Networked regression receipts

The release harness after the hull and stair-edge corrections, before the final
zero-health waiting and vehicle-ingress correction, passes all eight CI-shaped
cases and the seven-map mixed roster. The exact arguments come from
`.github/workflows/ci.yml` and `tools/playtest_roster.sh`; the executable was
called directly with a distinct report and log for every case.

| Cases | Result |
|---|---|
| FFA, TDM, Rail-only, TDM Licence to Kill | All four assertion sets pass |
| CTF route and contested Sector 9 | Both pass |
| Sabotage plant/defuse route and contested Sector 9 | Both pass |
| Seven-map mixed roster | All pass, with 2, 6, 6, 8, 12, 16 and 16 agents |
| Opening spawn deaths | Zero in all fifteen cases |

Individual respawn-window deaths are zero or one in those runs and remain
within the unchanged acceptance limits. These figures do not establish that
every respawn is safe during a moving match.

That earlier harness SHA-256 is
`24f9dc258821f68bbc8bd060cb79c4c13d8882e2832e25e252425df48c2fd489`.

After the final waiting and ingress correction, the refreshed harness passes
the affected Holdfast roster again: sixteen agents, one completed round,
forty-nine frags over 860 ticks (43 seconds), zero opening and zero
respawn-window deaths. Its command is:

```text
target/release/fragr-playtest.exe --map 7 --agents 16 --seed 42 --tiers reflex,planner --rounds 1 --frag-limit 8 --time-limit-seconds 60 --max-seconds 75 --assert
```

The final harness SHA-256 is
`513f292a66d5d7ff443cbe96f32159f8f9638baf090c61d003bdf0a07fa6d2fe`.
The matching final native server SHA-256 is
`987090f4cb2efd4dff7d2ac5742f21d6b79ecbfb208f1e9e23b513354c0b5af9`.

The final external-server soak passes the unchanged assertions with:

```text
target/release/fragr-playtest.exe --soak --soak-seconds 120 --soak-sample-seconds 15 --soak-bots 4 --agents 4 --soak-spectators 2 --soak-map-rotate --assert
```

The command explicitly selected the server executable hashed above and wrote
`final-soak.ndjson` alongside its native server log. All nine samples retain
four live agents and two live spectators, with four server bots. Ticks advance
from 34 to 2,434 over 120 seconds, measuring 20.00 Hz. All samples are healthy,
with zero queue overflows. Final lifetime tick-handler p99 is 0.82 ms, with a
6.04 ms maximum. Native working set starts at 59.4 MiB, ends at 60.7 MiB and
peaks at 60.9 MiB. These are same-machine native server measurements, with no
rendered frame-rate or physical-network claim.

Raw commands, reports, report hashes and logs remain under
`.agents/vehicle-aware-spawns-20261008/` and
`.agents/parallel-build-20261008/multiplayer/`. No paid service or new asset
production was used.

The [composed verification receipt](development-composition-20261008.md) records
combined workspace, coverage and rendered checks with their own status and
artifact bindings. The native and network receipts here retain their distinct
executable scopes.
