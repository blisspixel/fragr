# Vehicle-aware multiplayer spawn safety

Status: **implemented locally**, 2026-10-08. This is a bounded refinement under rung 1
of the [full build order](../ROADMAP.md#full-build-order).

## Outcome and scope

Joining and respawning fighters must use the current vehicle collision world.
A parked jeep, boat or aircraft can occupy a fixed spawn bay. Its hull also
changes the firing lanes that determine the safer bay. The existing selector
only reads static map solids and can place a fighter inside that hull.

Reuse the shared placement selector for admission and respawn. Keep the current
team halves, cover-first scoring, shields, equipment restoration and ordinary
random sequence when no vehicle changes a choice. Count only eligible living
bodies as occupancy and threats, and respect their vertical span. Burning and
destroyed hulls remain obstacles for exactly as long as ordinary walking keeps
them. No vehicle physics, map geometry, scoring or wire change is included.

## Architecture and bounded fallback

Keep placement in `server/src/sim/spawn.rs`, using `current_arena`, authoritative
vehicle hulls and actor eligibility. Prefer the established fixed bays. If every
bay in the side's half is blocked by a hull, try bounded supported positions
within six metres of those bays and score them by the same occupancy, exposure
and clearance criteria. A map with fixed bays for the side never falls back to
the opposite half. A map with no bays for that side retains its existing policy
of considering all fixed bays.
If no such position fits, retain the fighter in the existing zero-health
respawn wait and retry on the next authoritative tick. Admission still retains
its allocated seat, without presenting an overlapping live pawn. Vehicle
boarding and seat switches use shared actor eligibility, so a waiting actor
cannot acquire control even if another caller retains positive health.

The waiting path must preserve input ordering, inventory revisions, scores and
continuous ticks. It must not emit a respawn event or grant a new shield until
an actual placement succeeds. There is no second queue, timer or network field.

## Verification and success

- Reproduce the parked-hull admission and respawn overlap before the change.
- Prove clear fixed bays are preferred; hulls of all three kinds, including
  burning and destroyed hulls, exclude intersecting placements.
- Prove same-side supported fallback and bounded waiting with a completely
  obstructed half; clearing the obstruction must permit ordinary respawn.
- Prove current hulls participate in actual shot-cover ranking, while aircraft
  above a standing body do not block the ground spawn.
- Retain the existing spawn roster, route and seeded regression checks.
- Run focused Rust tests and the owning lints; composed workspace and client
  verification belong to the composed integration. Same-machine checks do not
  establish human balance, physical LAN behavior or server population capacity.

## Spend and limits

$0. No paid service, new dependency, cloud operation or asset production.
Human match feel and two-machine LAN acceptance remain open.

## Local evidence, October 8

`cargo test -p fragr-server --locked --lib sim::spawn --no-fail-fast` passes
all nine focused tests. The nine admission and respawn combinations cover each
vehicle kind alive, burning and as a retained wreck. The tests also exercise
same-side supported alternatives, a fully obstructed side retaining an admitted
seat, three refused placement ticks followed by a successful ordinary respawn,
unchanged input sequence and inventory while waiting, exactly one respawn event,
overhead aircraft, vertical body clearance, actual hull cover and seeded random
sequence preservation. An independent review found the old vehicle ingress
filter accepted positive-health respawn waiters. Admission and refused placement
now use the existing zero-health waiting invariant, without recording a death;
the ingress guard independently checks shared eligibility. A regression sends
ordinary interact, drive and fire input from both human and agent waiters with
retained positive health and proves neither can take a seat, move the jeep or
fire before placement succeeds. The raw focused log is retained under
`.agents/vehicle-aware-spawns-20261008/`.

The existing spawn suite initially found a real regression: eight Directive 17
fixed bays sit at stair edges and intentionally use the ordinary step allowance.
An exact feet-height static check excluded them, reducing one available
99.5-metre gap to 98.9 metres. Fixed bays now retain that established step
allowance while separately rejecting every standing-body vehicle intersection.
New offset samples still require exact standing clearance and support. The
existing widest-covered-bay regression passes after the correction, and the
focused suite includes a permanent stair-edge check. The prior full spawn run's
other seven tests passed, including 500 shuffled arrival orders on each of the
seven multiplayer venues. The final composed workspace run must repeat the
whole suite together.

Focused formatting and patch-whitespace checks pass. No renderer, human-match,
physical-LAN or release claim follows from these native placement checks. Full
workspace gates and integration belong to the current composed buildout.

The [dated native and network receipt](../evidence/vehicle-aware-spawns-20261008.md)
records the final nine-case proof, the earlier fifteen-case network regression
scope, the affected final sixteen-agent Holdfast rerun and the final guarded
external-server soak. The latter retains four bots, four agents and two
spectators across nine samples over 120 seconds at 20.00 Hz, with no degraded
sample or queue overflow. Artifact hashes separate the earlier and final
executable compositions. Human match and two-machine acceptance remain open.

The [composed verification receipt](../evidence/development-composition-20261008.md)
records the combined workspace, coverage and rendered gates as they complete.
Its status, retained corrections and artifact bindings determine composed
acceptance; the bounded checks above keep their stated scope.

### Same-machine soak measurement

This Windows x86-64 run uses the final guarded server and harness hashes in the
dated receipt above. It starts on Arena Duel, enables map rotation and uses seed
1. Percentiles measure the native tick handler, not network or input latency.
Working set comes from the native process, reported by `tasklist`.

| Measurement | Result |
|---|---|
| Population throughout all samples | Four server bots, four live agents, two live spectators |
| Measured duration and samples | 120 seconds, nine samples at 15-second intervals; 122-second wall time |
| Tick range and measured cadence | 34 to 2,434; 20.00 Hz |
| Initial tick-handler window p50 / p95 / p99 | 0.19 / 0.82 / 0.85 ms |
| Final tick-handler window p50 / p95 / p99 | 0.29 / 0.52 / 0.82 ms |
| Final lifetime tick-handler p99 / maximum | 0.82 / 6.04 ms |
| Degraded samples / queue overflows | Zero / zero |
| Native working set, first / last / peak | 59.4 / 60.7 / 60.9 MiB |
| Mean traffic per client, outgoing / incoming | 56,855 / 2,353 bytes per second |

The unchanged soak assertions pass. The raw samples, command log and native
server log remain in `.agents/parallel-build-20261008/multiplayer/final-soak.*`.
This bounded local check establishes neither physical LAN behavior, rendered
frame rates nor a larger population limit.
