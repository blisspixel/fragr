# Native island and vehicle integration evidence

Local verification on 2026-10-06 and 2026-10-07. The initial checks precede M11;
the composed gates and final measurements below include it and the reviewed
island fixes. This is working-tree evidence, not a deployed release or a human
play acceptance.

## Functional gates

The composed Rust source passed `cargo check --locked --workspace --all-targets`
and `cargo clippy --locked --workspace --all-targets -- -D warnings`.
`cargo fmt --all` completed. The focused server filters passed: `conquest`
8 tests, `water` 12, `vehicle` 28, `net::outbound` 11 and `bot_senses` 12.
These filters overlap and must not be added into one total. The adapter's
`vehicle` filter passed two strict input and observation tests. The dedicated
binary's Conquest match-config test also passed, verifying its 600-second
clock and absence of frag, capture-count, boss and compliance-ping endings.

The unchanged seven-map roster behavior gate passed: every existing bot
personality moved, fired and hit. Conquest now shares delayed observation,
bounded turn speed and angular error while preserving capture destinations.
New water negatives reject nonfinite bounds, impossible depth, overlap,
inverted rectangles, excessive region counts and unknown fields. Adjacent
regions may share an edge.

Eighteen client vehicle golden vectors match native motion within 0.00088303;
six swimming vectors match within 0.00000057. Both remain below the unchanged
0.001 tolerance. Live client driving checks separately exercised Jeep and
boat entry, movement, braking, mounted fire and exit. Their detailed rendered
and socket receipts belong to the vehicle client evidence, not this CPU gate.

## Initial same-binary CPU comparison, 2026-10-06

Machine: AMD Ryzen 7 7840U, eight cores and sixteen logical processors,
Windows x86_64 build 26200, Balanced power plan. These are release builds.
The source is the shared working tree above base
`dff173655e828a811992b917ed51a473354a90eb`, with gameplay capability 41.
The measured executable SHA-256 is
`0a643e8921934d9bc7c2dd4c2a4292831a7025d90b42a69c7aa5c32ac4797b6a`.

Each sample uses the existing benchmark with 1,200 ticks, seed 42, a repeated
trace check and the unchanged budget assertion. No renderer, headless client
suite or build ran during the retained comparison. An earlier sample overlapped
a finishing headless client suite and is retained separately with the
`-concurrent-headless` suffix; it is not the table below.

| Map | Rule bots | Ending fighters | Mean tick ms | p99 tick ms | Max tick ms | Ticks over 50 ms |
|---|---:|---:|---:|---:|---:|---:|
| Arena Duel | 16 | 16 | 0.1683 | 0.6881 | 5.7636 | 0 |
| Arena Duel | 64 | 64 | 0.8065 | 3.2768 | 6.4545 | 0 |
| Holdfast Atoll | 16 | 17 | 0.2539 | 1.7695 | 3.9032 | 0 |
| Holdfast Atoll | 64 | 65 | 0.6912 | 2.8836 | 11.2722 | 0 |

All four repeated traces are identical. Holdfast's normal arcade boss accounts
for its extra fighter. These are actual rule bots sharing the ordinary session
tick, not spectator connections. The harness measures session work and JSON
encoding once per broadcast or targeted message. It excludes per-recipient
fanout, sockets, rendering and trace output. It uses ordinary FFA rules and
round transitions, not Conquest. The registered fleet is present but the bots
do not drive it. These results do not prove 64 network players, dense ongoing
combat on every tick, client frame rate or cross-machine capacity.

Reproduce from the same source and release build:

```text
cargo build --locked --release -p fragr-server --bin fragr-server
fragr-server --bench N --bench-ticks 1200 --map M --seed 42 --bench-check --bench-assert
```

Use `N` of 16 and 64, and `M` of 1 and 7. Local JSON reports and environment
metadata are under `.agents/native-quality-20261006/`. Later composed gates and
measurements follow below. Remote CI is a separate result.

## Composed review, 2026-10-07

After M11 was composed, the strict global-version fixtures were updated to
retain M11's capability floor of 38 while accepting the current 41. Remote mine
facts participate in the exhaustive outbound snapshot replacement decision;
armed, triggered and detonated facts remain ordered.

Review and actual movement tests found three physical seams requiring fixes:
actor-contact projection had omitted vehicle hulls and buoyant support, boarding
could cross low cover below an eye ray, and short local avoidance could stall
against the parked aircraft. These now use the same supported collision world,
a swept standing-body passage, and dynamic filtering of the existing bounded
route search. Runover overlap also uses the victim's actual stance height.
The client mirrors the contact world and retains each input's vehicle hulls.

The focused vehicle filter passes 38 tests, including the six swept boarding
cases, glancing actor contact beside a parked hull, touching swimmers, crouched
overflight and temporary obstacle routing. The seven-map test passes every
registered supply route and sixteen native spawn routes per map with the fleet
present. The desktop Host matrix accepts only an unmodified Holdfast Conquest
match and retains the ten-bot local limit. The refreshed server release and
production Holdfast map export both build successfully.

The dynamic route overlay retains cached topology, the existing expansion
limit and staggered search allowance. It does not create swimming navigation
surfaces: bots still use supported land routes. Full composed gate results follow below.

The composed `cargo fmt --all -- --check`, workspace all-target Clippy with
`-D warnings`, and `cargo test --workspace --locked` pass. The server library
reports 1,224 passed, zero failed and three intentionally ignored tests; the
native desktop-host subprocess integration reports seven passed. Full
workspace tests also exercise the adapter, decision controller, playtest tool,
asset-tool fake transports and shared integration tests. This was the first
composed pass; final coverage and roster results follow after the additional
boundary fixes below.
The freshly built release playtest executable passes all eight CI argument
sets: ordinary FFA, team deathmatch, Rail Only, team Licence to Kill, CTF route,
contested CTF, Sabotage route and contested Sabotage. Reports are retained under
`.agents/native-quality-20261006/sockets/`. The CTF route records an actual
capture. Its separate contested seed records a take, drop and return before
the time limit, with no capture claimed. The Sabotage route records a plant
and defuse; the contested seed records a plant and an elimination ending.
These are functional socket checks run beside other verification, not isolated
latency or capacity measurements.
The first broad gates then exposed two additional native boundary defects in
rendered/client checks: automatic Conquest was absent from the bot-policy
validator, and a respawn ACK could contain an unnormalized ring yaw. The
captured rejected ACK had yaw 7.0685835 on tick 156, with the expected advancing
epoch and unchanged input sequence. Canonical spawn facing now fixes the
source; the strict client validator remains unchanged. Eight automatic-fill
checks and four movement-ACK checks pass, including real Conquest population
replacement/refill and 32 consecutive respawns on every map.

The first added 16-client Holdfast roster failed the unchanged spawn limits
with 11 of 61 deaths inside the spawn window and two at the opening. Coastal
revetments now screen inward and parallel firing lanes while keeping wide
walking exits and ocean access. The deterministic seven-map spawn screen and
walking gate passes. Holdfast enumerates its sixteen physical bays exactly,
with a wrap/uniqueness test, instead of advertising 64 aliased candidates.
Navigation work accounting now charges only the two solid scans actually
possible for base-ground layers; raised layers retain six scans and the same
construction, node and geometry limits. Independent review confirmed this
bound. The final live roster and complete native gates were then repeated.
The repeated Holdfast 16-client match passes those same limits: 77 frags,
one spawn-window death, zero opening deaths and a first frag at 7.3 seconds.
Its report is `.agents/native-quality-20261006/holdfast-spawn-repeat.json`.
This played check complements the deterministic screening and walking proof;
it does not establish 64-player spawn quality. The final production MapInfo
export includes these physical revetments, and separate renderer evidence must
identify that layout. The combined release SHA-256 for this corrected source is
`79ea57258ed8aecb322b58d4a6cb94e48075eead600bae885e9d89ca15b7585a`.
The final composed ordinary workspace suite passes again after those fixes:
1,228 server-library tests pass, zero fail and three remain intentionally
ignored. Formatting and all-target Clippy pass. The complete seven-map
mixed-client roster also passes with its unchanged assertions; its latest
reports are under `.agents/native-quality-20261006/roster-verified/`.

| Map | Clients | Frags | Spawn-window deaths | Opening deaths |
|---|---:|---:|---:|---:|
| Arena Duel | 2 | 6 | 0 | 0 |
| Compliance Yard | 6 | 29 | 0 | 0 |
| Directive 17 | 6 | 23 | 0 | 0 |
| Sector 9 | 8 | 42 | 6 | 0 |
| Reclamation Gulch | 12 | 31 | 0 | 0 |
| Tripoint Works | 16 | 65 | 2 | 1 |
| Holdfast Atoll | 16 | 58 | 0 | 0 |

The existing spawn-frequency gate uses its confidence interval and also checks
opening deaths separately. A pass does not mean every venue has zero early
deaths. These are network-controlled reflex/planner fighters; the isolated CPU
benchmark and synthetic-input delivery test below measure different work.
The final unfiltered `cargo llvm-cov --workspace --locked --fail-under-lines 90`
passes at **93.26% workspace line coverage**, with 74,859 instrumented lines
and 5,047 missed lines. No files, modules or assertions were excluded to reach
the gate, and its 90% threshold remains unchanged. The earlier pre-correction
93.23% report is retained separately under the private diagnostic directory.

## Final quiet measurements, 2026-10-07

The final locked workspace release was measured after all native fixes above.
No renderer, compiler, test suite or other development workload ran during the
CPU matrix or subsequent traffic sample. The machine and Balanced power plan
are unchanged. The source is the composed working tree above
`0fbcd6ccc1c0ac6bfe64a53fee047c104ab9b199`, capability 41. The server executable
SHA-256 is `edbb8d0ca340b2712aea0ed5b9676ea13f59036636d22e1e4400fca24ebe7b0d`;
the playtest executable is
`004b989d1f9de1a6a8974e9eddd99fb77d5182b5733f20c70a3e791305ee4577`.
The [retained structured receipt](native-island-measurements-20261007.json)
contains exact commands, report hashes, environment and measurements.

Each CPU sample again runs 1,200 ticks with seed 42 and the unchanged assertion.
All four repeated traces match, with no ticks exceeding the 50 ms budget.

| Map | Rule bots | Ending fighters | Mean tick ms | p99 tick ms | Max tick ms |
|---|---:|---:|---:|---:|---:|
| Arena Duel | 16 | 16 | 0.1809 | 0.7209 | 9.1031 |
| Arena Duel | 64 | 64 | 0.8548 | 3.5389 | 7.4584 |
| Holdfast Atoll | 16 | 17 | 0.3471 | 2.0972 | 4.6728 |
| Holdfast Atoll | 64 | 64 | 1.0637 | 4.7186 | 10.4168 |

These retain the earlier CPU scope: ordinary FFA session work plus encoding,
without per-recipient delivery, sockets or rendering. The ending fighter count
includes a living arcade boss where present. Registered vehicles are in the
world but rule bots do not drive them. The new geometry and collision/route
checks are included; the earlier source's timing is historical evidence.

The separate loopback run uses 64 actual WebSocket connections admitted as
humans, with zero spectators and zero server bots. For 60 seconds each sends
fixed movement and fire at a requested 60 Hz. It passes the existing traffic
assertions without changing the harness limits.

| Delivery measurement | Result |
|---|---:|
| Connected fighters at start and end | 64 |
| Actions sent | 228,672 |
| Fighter snapshots received | 76,864 |
| Disconnects | 0 |
| Server ticks at start and end | 8 to 1,209 |
| Server p99 tick ms | 11.0100 |
| Aggregate received text bytes | 1,579,061,632 |
| Aggregate server outbound bytes/s | 26,125,306 |
| Final health | ok |

The harness stops its owned server cleanly. The full JSON stream uses about
24.91 MiB/s in aggregate on loopback; this is a measured bandwidth cost, not a
WAN capacity claim. Participants do not reload, pathfind or use vehicles.
Finite human magazines may empty early, so this is not evidence of sustained
64-fighter combat. It also does not establish human match balance, 64-player
spawn quality, client rendering performance or remote latency. This run does
not deliberately stall readers or measure how many snapshots coalesce.
Bounded reliable ordering, quiet-world replacement and slow-reader eviction
have separate deterministic and socket tests.
