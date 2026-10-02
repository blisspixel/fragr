# M06 Port of Entry prototype

**Status:** in flight, 2026-10-01. Research and contracts are agreed; implementation
has started from passing main `74520b4`. No M06 acceptance or release is claimed.
The [full build order](../ROADMAP.md#full-build-order-2026-09-27) owns sequencing;
this file defines its next bounded mission increment after M05's gate.
**Spend:** $0 new cash charges. The separately priced
[M06 audio batch](m06-audio-batch.md) generated four jobs using 252 included
credits. The separate requested shotgun refresh consumes another 30 included
credits, bringing the ongoing round to 975 credits and a conservative $5 audio
equivalent reserve. The owner confirmed $14.40 in current image API credits;
six bounded image requests downloaded at a combined $0.274 reservation:
$0.114 for possessions and $0.160 for two story key images.
Confirmed image billing remains unreconciled and the prior uncertain $0.107
reservation stays preserved. No top-up, overage or cloud submission ran.

## Goal and accepted direction

Build a playable lunar cargo port through the existing authoritative mission,
encounter, inventory and local-run seams. Introduce the found Railgun, then the
flankable Turret, and make entry into Episode II refill the run's continues
exactly once. Retain the Earth choices and exact carried equipment, including
Grenades and the distinction between freed and actually evacuated workers.

The accepted direction is [level 6 in the Port of Entry brief](../campaign/m04-port-of-entry.md#level-6-design-twenty-level-expansion),
[the mission treatment](../CAMPAIGN-MISSIONS.md#level-6-port-of-entry),
[Moon appearance](../design/moon.md), [character continuity](../design/characters.md)
and [voice](../lore/voice.md). The older first section of the brief belongs to
the superseded ten-mission split: the crater cut and Sniper Rifle move to level
7, the Enforcer to level 9. They are not extra M06 requirements.

The accepted route is dock service bay, freight hall, customs split and transit
tunnel toward the lunar town. Earth over the gantry, inhabited spaces behind
pressure glass, the depot tower and Tern's impounded ship establish a settled
Moon and the next destinations. Tern stays with the ship and passengers; Latch
can assist through cleared spaces. Preserve actual retained choices rather than
silently placing every previously freed person aboard the ship.

The full brief targets eleven minutes, a 4:30 par, three secrets and one dock
bulkhead that is already open and never closes. Difficulty brief acceptance,
fresh-player timing and named character performances remain separate from a
bounded automated authoring gate. The choices below are implementation
recommendations, not new canon or evidence that those targets are met.

## Recommended bounded map and fights

Use one compact static map, recommended ID 1006 and half extent about 48 metres,
with an approximately sixty-metre cargo sightline folded beside shorter routes.
Keep ordinary support, stairs, head clearance and the shared walking navigation.
The port has real interior ceilings and pressure shells. Inspection desks and
cargo islands break shorter fights into readable angles; a service bypass and
crane walkway reconnect at customs. Neither route becomes a mandatory jump.

| Proposed encounter ID | Ordinary beat | Proposed roster |
|---|---|---|
| `freight_ingress` | Initial cargo islands and short flank | 2 Clerks, 2 Sweepers |
| `rail_lane` | One unaware distant Sweeper after Railgun discovery | 1 Sweeper |
| `loading_heavy` | Known Heavy returns at the loading threshold | 1 Heavy Sweeper |
| `turret_intro` | Observe sweep and charge from real cover, then flank | 1 Turret |
| `customs_hold` | Two galleries and central declaration desk | 4 Clerks, 3 Sweepers |
| `exit_watch` | Final exit crest with separate retreat space | 2 Clerks, 1 Heavy Sweeper, 1 Turret |
| `service_branch` | Optional prisoner-route marker after a local clear | 2 Clerks, 1 Sweeper |

This recommends 18 required guards and three optional guards. The first customs
Turret is isolated for its introduction, then remains the already-cleared member
of the brief's eight-guard customs set piece. Do not add a third Turret. Confirm
the compact roster against authored sightlines and actual play before freezing
map bytes; these counts do not establish final encounter balance.

Future required groups remain absent until their predecessors clear, reusing
M04/M05 staging. The optional branch has its own prerequisite and does not become
the predecessor of a required group. Use physical thresholds and occluding
layout to keep the lone Turret lesson separate from the following mixed fight.
Leave a supported retreat behind every lesson: automated phase capture must not
idle inside the next trigger as happened during M05 iteration.

Guarantee the Railgun in the confiscation cage before its lane. The existing
pickup grants ten Cells; the accepted separate ten-Cell supply can remain beside
it, with both ordinary claims recorded honestly. Rifle and Shotgun routes stay
usable. Provide finite Cells before the gallery and final Turret, plus visible
health/armor recovery outside future activation thresholds. Preserve no carry
cap and no automatic weapon discard or switch on empty ammunition.

Three optional detours follow the accepted brief: pressure-maintenance armor
and Cells with a registered small `/6` clue; crane-overlook armor and a real
customs angle; duty-free kiosk Shells and a medkit with another readable `/6`.
Place grants within normal claim reach on supported accessible surfaces. A
full-health medkit may remain unclaimed; never manufacture damage to claim it.

## Existing behavior and source gaps

The source checked on 2026-09-30 already gives the Railgun 80 damage, a 60-metre
range and one Cell per shot. The distant Sweeper has 80 HP. Measure the actual
eye-to-hit-volume ray against that range, with margin for ordinary standing and
aim, rather than assuming a sixty-metre floor-center distance guarantees a hit.
Recommend roughly 58-59 metres for the verified firing stance, keeping the brief's
long-lane intent without changing weapon range, damage or global spread. Test an
ordinary aimed shot and nearby imperfect aim; an ideal ray is not a teaching gate.

The existing Turret has 100 HP, a fixed body, authored head sweep, front-only
acquisition, 28-metre engagement range and immediate loss of its target when
sight breaks. Standard charge lasts 26 ticks, with one Rail shot. A Rail hit is
80 damage, not a one-shot Turret kill; its existing heavy-hit stagger and two-hit
budget matter. Reuse these timings and behaviors without a rules revision.
Author real cover that cancels the charge and a supported rear flank. Tests must
distinguish the head's current sweep from its initial authored yaw.

`inspection_glass` already renders a ballistic transparent solid, but current
authoring restricts it to M02. The port's safe windows therefore require a
bounded server and client validation extension permitting the same registered
surface on M06 solids. Test real bullet and grenade occlusion, opaque-body
registration, rendering and M02 preservation. A cosmetic transparent plane must
not imply ballistic cover. Pressure equipment remains scenery, without secret
airlock, vacuum, low-gravity or body-specific damage rules.

The baseline saves knew `port_of_entry` only as the unbuilt destination after M05.
That baseline had no M06 mission enum, map, controller, local child or episode refill.
Its v6 outcome checks attached M05 rescue only to that pending edge;
they must expand deliberately to preserve it throughout M06 and later retries.
Local prediction and remote participant presentation exist, but their existence
does not establish compensated remote-network sixty-metre fights. This increment
proves a local authored lane; any network quality claim needs the measurements
and baseline in [TRANSPORT.md](../TRANSPORT.md), not a silent transport rewrite.

## Architecture and proposed wire contract

Recommend new `protocol/m06.rs`, `maps/authored/m06.rs`, `mission/m06.rs` and
`mission/controller/m06.rs`, with bounded glue in their current owners. The
authoritative map remains JSON in `server/maps/`; client world presentation uses
validated MapInfo, never a second copy of authored geometry. Preserve M01-M05
bytes and M05's live tram contract. M06 has no moving gameplay collider and needs
no additional gate world: its only accepted bulkhead starts open and stays open.

Recommended wire boundary is capability 27 for the newly introduced mission and
pressure-window admission, with campaign rules revision 3 unchanged. Determine
retirement of existing live readers from the final shared shape: reject older
roles before initial state whenever new mandatory fields require it, and retain
explicit full-arsenal arcade compatibility. The implementation now advertises
capability 27, requires it only for M06, and retains capability 26 admission for
earlier authored missions. Every client, adapter, brain and playtest reader is
updated through the shared shapes; initial MapInfo-before-state ordering remains
required.

Recommend mutually exclusive `m06` geometry and mission facts, matching current
strict boundaries. Geometry contains six ordered required Arrival objectives,
one registered transit departure Use target and boarding region, a supported
companion start, and an optional service-region marker bound to its encounter.
Frozen objective IDs are `freight_cleared`, `rail_lane_cleared`,
`loading_cleared`, `turret_cleared`, `customs_cleared`, `exit_cleared`, then
`party_departed`. Freeze exact IDs before implementing readers or QA manifests.

Facts carry the completed prefix, current objective, optional
`prisoner_route_marked` boolean and immutable earlier outcome context. Represent
prior M05 context as explicit released and evacuated worker ID lists, with the
registered identities and strict subset rule retained. Do not infer ship
passengers from freed bodies or introduce NPC arrival timing as a departure gate.
The marker becomes true only after the optional encounter clear and actual
active party presence at the registered marker. It records a later route choice,
not a new required campaign control or invented rescue.

### Implementation ownership and frozen boundary

The parallel lanes are [core](m06-core-prototype.md),
[map](m06-map-prototype.md) and [client](m06-client-prototype.md). Integration owns
durable v7 saves, strict v6 upgrades, local Rust launch, admission, shared agent
readers, documentation, verification and publication. File ownership is separate;
global builds and native renderer checks are serialized during convergence.

`M06MapGeometry` has `objectives`, `service`, `departure`, `boarding` and
`companion_start`. `service` is an Arrival `MissionObjective` named
`prisoner_route_marked`. `M06ObjectiveState` has `completed`, optional `current`,
`prisoner_route_marked`, `carried_recall_cars`, `carried_patients`,
`carried_photos`, `carried_released_workers` and `carried_evacuated_workers`.
These outcome arrays retain legitimate historical order, with strict unique
registered workers and an evacuated subset. M06 envelopes are mutually exclusive
with earlier mission envelopes. The new client advertises capability 27; only
M06 admission requires 27 while existing authored missions retain 26. Rules stay
at revision 3. No weapon spread, Turret timing or movement math change is planned.

The separate fixed-body Turret sprite oscillation will be reviewed against its
authoritative head yaw. A centered long Rail shot can still miss due to ordinary
spread; seeded shot evidence must preserve that behavior and an accessible
walking alternative. Dormant guards are stationary before activation, so this
increment will not claim a patrol that the source does not implement.

Shared departure still requires the living ready party at boarding and a fresh
aimed Use. Retry restores the complete M06 entry, guards, supplies, objective and
local ally state while keeping completed earlier outcomes. Controllers require
matching fresh map and mission facts, use actual physical cover, and retain the
existing bounded navigation budget. No per-tick topology construction.

## Strict saves and the episode boundary

Recommend run version 7 because v6 explicitly rejects playable M06 and has no
M06 optional outcome. Keep a strict historical v6 reader beside v2-v5 readers,
without widening old structs with defaults. Validate original shape, registered
stages, rules and exact original content hash before upgrade. v2-v5 remain
explicit historical formats with zero Grenades only after validation. v6 already
has a required zero-through-six Grenade count: preserve it exactly, never reset
it or accept missing/invented old equipment fields. Preserve exact-byte archives
and failure-safe locked replacement through the current store seam.

On the single validated completed-M05-to-M06 promotion, carry run ID, bound body,
HP, armor, all weapons, ammunition, Grenades, selection, difficulty and all prior
outcomes. Clear only old-map personal supply claims. Refill remaining and
level-start continues to three because M06 starts Episode II. That refill belongs
to atomic promotion, not migration alone, preview, readiness, reopening an entry,
retry, Practice, or M05 completion. A completed M05 exit with zero continues can
enter Episode II; failed or abandoned M05 cannot bypass its terminal state.

Retain recall-car, patient, photograph and M05 released/evacuated outcomes through
every M06 entry, pending continue, retry, failure, abandonment and completion.
Recommend `m06_outcome:{prisoner_route_marked:bool}` exactly at completed M06's
pending `declared_goods` edge, retained onward for level 8. Do not make the optional
branch mandatory by prototype difficulty. Existing M01-M05 saves must continue
to load at their original stages; a forged v6 playable M06 remains invalid.
Test promotion retries reuse one exact archive and cannot repeatedly refill.
Never rewind process ticks, input sequences, inventory revisions or records.

## Presentation and spend

Carry the same retro pixel density and issued Union bodies into pale dust,
dark basalt and weathered pressure shells, with hard exterior shade and readable
interior utility light. Earth, the depot tower and the impound berth orient the
player; a gray warehouse or a black sky alone does not establish the Moon.
Use practical seals, dust traps, maintenance marks, family possessions and
contained civilian water where its purpose is visible. Keep decorative masses
and any tug movement outside playable geometry. Substantial cover remains real
solids. Inspect glass sorting, shadow fill, lamps and actor silhouettes at both
local firing distances and the long Rail lane.

Use existing localized text and ScenePlayer fallback for elapsed-time framing.
Any Tern wave or impound movement needs its own inspected presentation evidence;
a static ship must be captioned as a static landmark. Missing named character
performance remains a visible acceptance gap. Neutral narration is not Tern,
Mara, Latch or Voss's final casting. No new recorded speech, provider choice,
character canon or unrestricted generation follows from this plan. The bounded
[M06 audio batch](m06-audio-batch.md) owns the four approved neutral jobs. Before any future
asset batch, check actual remaining credits and price the exact bounded operation
within the authorized cash cap; record credits separately from cash and never
enable top-ups or overages. No new dependency, engine pin or provider API is needed.

## Verification and completion bar

Focused seeded tests must cover ordinary Rail discovery, finite Cell use, the
distant Sweeper hit and missed/covered/out-of-range shots; Turret idle sweep,
tracking, full charge, real shot, sight cancellation, rear flank and heavy-hit
interruption; ordered groups and optional branch independence; actual ordinary
stairs, both customs routes and each supply/landmark's reachable supported feet.
The bypass remains usable with ordinary Rifle/Shotgun combat when the Rail is
unclaimed or empty. Difficulty briefing conditions need separate resolved facts
before claiming the accepted rear-sweep kill or no-bypass Severe challenge.

Test strict malformed wire fields, stale facts, map replacement, participant
readiness, spectator ordering, multi-participant departure, explicit retry and
the marker's reset. Save tests use actual historical bytes and a completed v6
M05 exit with spent Grenades and mixed released/evacuated outcomes. Prove exact
carry, once-only three-continue refill, all terminal states, old-reader rejection,
wrong mission refusal, content mismatch, writer contention and injected archive
or replacement failure. Run real isolated local children, including repeated
resume, held-input release barriers and Practice save preservation.

Then run all relevant repository Rust/client checks, coverage, release build,
licensing, arena regression playtests, benchmark and soak. Add an ordinary-input
M06 tour and shared-movement preflight before publishing it. Capture the actual
quiet arrival, one-shot Rail lesson, Turret sweep/charge/shot and cancellation,
rear flank, optional marker, all three clues, finite supplies and shared exit.
Inspect readable stills and real motion. Accurate-aim clear, phase receipts and
nonblank images remain distinct from fresh-player fun, eleven-minute pacing,
4:30 mastery, full briefs and finished character/story production.

Implementation is complete only after the local mission, strict M05-to-M06 carry
and once-only episode refill, ordinary route and both teaching beats pass their
own recorded gates. Record failures and root causes without weakening guards,
timings, phase requirements, health or coverage. Root owns indexing and the sole
roadmap sequence; this plan creates no parallel next-work queue.

## Integration receipts (2026-10-01)

The implementation now uses the frozen M06 envelopes and six ordered objectives,
capability 27 only for M06, strict v7 saves and actual retained M05 equipment.
The completed historical v6 M05 fixture has zero remaining continues, spent
Grenades and an evacuated subset of released workers. Store tests prove read-only
preview, writer contention, failure-safe replacement, one exact-byte archive,
single episode refill and unchanged already-spent reopening. Actual retry tests
restore the M06 entry without rewinding tick, input sequence or inventory revisions.
The real local-process fixture is included in the full workspace gate.

Final static map SHA256 is
`627e9bcecaa231fdc3a5df8297ac872e975b41c31b7ae872d4a4ce1c25e4a9a5`:
74 solids, 22 finite supplies and 21 guards. The 25-state authoring manifest has
144 ordinary walking segments after the landmark framing correction. Focused
Rust checks pass 18/18 on the initial 142 segments; the final framing preflight
passes 3/3 on all 144 segments and handoffs. Initial preflight found a locker-cutting route and
a genuine crane stair access defect. The map now has an open stair entrance and
a supported ground aisle; the route uses the actual locker aisle and broad stair
centre. Guard counts, supplies, Rail range, weapon spread and Turret timing did
not change. M01-M05 map bytes remain unchanged.

The broad Rust gate also exposed an old socket fixture that assumed the newest
capability applied to every Discovery map. Its corrected test explicitly rejects
pre-26 readers and admits both 26 and 27 for human, agent and spectator roles on
the older authored map. This preserves the intended compatibility boundary.
The pre-contact workspace clippy and dependency licenses/bans/sources pass.
The completed baseline below predates the subsequent living-body contact
increment; final matching server, client and visual gates must include that
source before acceptance.
Receipts live under `.agents/m06-buildout-20261001/`.

Initial API image-credit research could not verify the balance through the
available account session. Official billing documentation distinguishes API
dollars from website credits. That research ran no image generation or account
change. Nick subsequently reported a current $14.40 balance and explicitly
requested a [bounded lunar art batch](m06-lunar-art-batch.md); the original
offline Moon art remains available. The exact neutral audio batch settled at 252
included credits and zero new cash charges. Actual decoded playback, captions,
looping, completion and fallback checks pass; listening and final character
casting remain separate review evidence.

### CPU regression measurement

Windows x86_64 release, 16 available logical processors, Arena Duel, seed 42,
16 bots (17 simulated fighters), 1200 ticks, no connected clients. Scope is
session plus snapshot encoding, not rendering or M06 remote-network performance.

| Tick p50 ms | Tick p99 ms | Tick maximum ms | Ticks over 50 ms | Deterministic rerun | Budget gate |
|---|---|---|---|---|---|
| 0.086 | 0.721 | 3.585 | 0 | pass | pass |

Command: `cargo run -p fragr-server --release --locked -- --bench 16
--bench-ticks 1200 --bench-check --bench-assert --seed 42`.
Full receipt: `.agents/m06-buildout-20261001/benchmark.log`.

### Completed engineering gates

These are the completed pre-contact baseline, not final verification of the
subsequent [living-body contact increment](actor-body-contact.md), new art or
shotgun integration. The recorded counts and measurements remain historical
receipts; final current-source checks and inspected tours are still required.

`workspace-tests-rerun.log`: 1226 passing workspace tests, zero failures and
three existing ignored tests. `fmt.log` and `clippy-final.log`: clean.
`coverage.log`: unfiltered workspace line coverage 94.12 percent against the
unchanged 90 percent floor. `release-build.log`: full workspace release build
passes. `deny.log`: licenses, bans and sources pass.

Local Docker 29.8.0 checks used a unique owned Compose project after confirming
no prior containers or listener. Build, UID/GID 10001, read-only root filesystem,
no-new-privileges, legal notices, healthy Compose state and host `/status`
(`kind:arena`, `health.status:ok`) pass. A real four-bot match logged two frags.
Cleanup removed only that project's container and network; its final process
listing is empty. Receipts: `container-*.log`. No cloud credentials or apply.

The matching binary passes the real client `test_m06_local` gate, including
Practice isolation, actual historical v6 promotion, held-fire release before
readiness, exact two Grenades/body/HP/ammo and retained outcomes, one exact-byte
archive and reopening a spent M06 entry without refill or arrival replay.
The initial final-reopen fixture failed because Godot's parsed numeric atoms
reserialized as decimals, correctly rejected by Rust's integer schema. The
fixture now changes one exact validated allowance field in the actual compact
writer bytes. Production validation, deadlines and carry assertions are intact.
Final clean receipt: `client-m06-local-actual-compact-fixture.log`.

| Local release soak | Bots | Agent fighters | Spectators | Samples | Actual cadence | Lifetime tick p99 ms | Max ms | RSS MiB start/end/max |
|---|---|---|---|---|---|---|---|---|
| 120 seconds, rotating arena maps | 4 | 4 | 2 | 9 | 20.00 Hz | 0.72 | 6.40 | 38.3 / 38.9 / 39.0 |

The ordinary release binary ran the same soak flags as CI. Receipts are
`soak.log`, `soak.server.log` and `soak.ndjson`. This proves the measured local
roster, not large-server scale, remote-machine behavior or GPU performance.

The current release harness binary passes the CI-equivalent FFA, TDM,
rail-only, TDM licence-to-kill, CTF route and contested CTF flags. The route-only
CLI deliberately rejects `--assert`; the initial orchestration included it and
was corrected to the documented route command. No assertion was weakened.
The corrected route passes its own socket proof. The contested run records two
takes, one combat drop, one return and one capture at the capture limit.
Receipts: `playtest-*.log` and `playtest-*.json`.

All six mixed-agent map cases use the roster wrapper's same maps, seeds,
Reflex/Planner tiers and thresholds, with the already built matching binary
to serialize Windows executable writes. Reports remain independent of the M06
authoring tour. The two post-opening spawn deaths remain visible in the data.

| Arena map | Agent fighters | Frags | Spawn deaths | Opening spawn deaths | Gate |
|---|---|---|---|---|---|
| 1 | 2 | 5 | 0 | 0 | pass |
| 2 | 6 | 31 | 0 | 0 | pass |
| 3 | 6 | 28 | 0 | 0 | pass |
| 4 | 8 | 31 | 1 | 0 | pass |
| 5 | 12 | 46 | 0 | 0 | pass |
| 6 | 16 | 48 | 1 | 0 | pass |

Exact receipts: `roster-map1.json` through `roster-map6.json` and their logs.
Independent read-only final review found no consequential save, admission,
staging, controller, optional-service or departure defect. Source tests that
place participants or clear guards are unit evidence, separate from the pending
ordinary-input rendered mission tour.

Independent capture review found the impound still's original camera ray hit
its own opaque signpost. A QA-only supported gallery stance now has audited
clear rays to the ship and depot through the actual ballistic glass. The tour
still visits both observation anchors and its next walk starts at that real
endpoint. Map content is unchanged. `map-window-preflight.log` and
`map-window-rays.log` retain the final framing evidence.

The same review identified an evidence gap: aggregate enemy shot counts and
phase files alone cannot distinguish cancelled Turret charge from ordinary
post-shot recovery. The QA lane now adds a bounded named-actor temporal receipt
through the original charge deadline: visible windup, early short recovery,
unchanged enemy HP, living participant within sight range behind real cover,
and no resolved shot from that Turret in that cycle. Production combat and
timings stay unchanged. Normal firing, heavy-hit interruption, stale facts and
unrelated shots must not satisfy this gate. Pure failure-path tests and the
actual rendered lesson are required before cancellation is claimed.

The corrected observer also requires the previous consecutive Windup snapshot
to show blocked sight while the participant remains alive and in range. Enemy
intent consumes that prior movement state; cover appearing only in the Recovery
snapshot cannot establish why the charge stopped. Focused regressions reject
that false positive, range-loss cancellation and ambiguous extra participants.
The third actual tour records a valid cycle: clear Windup at 3103, blocked
Windup at 3108, twelve-tick Recovery at 3109, unchanged Turret HP, and no named
resolved shot through original deadline 3129, verified at 3130. An earlier
ordinary firing cycle is separately observed and deliberately rejected as a
cancellation candidate.

That tour remains incomplete: the driver climbs all six gallery treads, then
oversteers sideways off the supported platform while keeping aim on the Turret.
The old projection threshold selected a diagonal for a course only fourteen
degrees from forward. The owning QA lane corrected this with nearest-eight
direction quantization and a focused regression; server movement, map geometry
and required rear-flank death gates remain unchanged. Receipts and partial
captures remain under `.agents/qa/m06-port-third/`.

The original Earth disk was inspected as an indistinct repeated-oval texture.
Its existing local source baker now draws recognizable continents, blue ocean,
broken curved cloud bands and a terminator. The tour looks at the actual planet
center rather than an elevated point above it. The inspected frame shows Earth
through the freight window beneath the gantry crossbeam; it does not claim Earth
above that beam. The crew-quarters frame shows provisional residents, storage,
meal bowls, a child's drawing and the labelled recycling tray behind real glass.
Neither still establishes final character performances or ambient activity.

### Fourth tour and outstanding clean gate

The fourth ordinary-input tour under `.agents/qa/m06-port-fourth/` completed
all 25 states, all 21 named guards, the optional prisoner marker and actual
party departure. It recorded zero deaths and HP loss, with 90 armor lost.
Its actual resolved participant Rail shot measured 52.8996 metres at tick
1278, distinct from the authored 58.25-metre initial spacing and seeded test.
The named Turret cancellation retained blocked, living, in-range Windup at
3074, twelve-tick Recovery at 3075 ending 3087, unchanged Turret HP and no
named shot through the original deadline 3085, verified at 3086.

The wrapper failed with two shutdown texture-leak errors, so completed gameplay
is not a clean mission PASS. A focused reproducer established a pending sky
resource lifetime race when replacing environments before the first rendered
frame. The bounded one-frame retention fix preserves immediate world changes
and passes isolated rendered and headless regressions. Final clean whole-mission
capture remains pending after contact, art and audio source freeze and a
matching release build. Fresh-player teaching, all difficulties, eleven-minute
pacing, 4:30 par, final casting and listening acceptance remain open. M06 is
still in flight and no release 0.66 is claimed.
