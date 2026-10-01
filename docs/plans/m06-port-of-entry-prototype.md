# M06 Port of Entry prototype

**Status:** planned, 2026-09-30. No M06 runtime, map or capture is implemented.
The [full build order](../ROADMAP.md#full-build-order-2026-09-27) owns sequencing;
this file defines its next bounded mission increment after M05's gate.
**Spend:** $0 planned new charges, no asset calls or cloud operation. The current
round has used 693 included audio credits, with $0 new cash charges and a
separate conservative $3 equivalent reserve. Those receipts grant no new batch.

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

Current saves know `port_of_entry` only as the unbuilt destination after M05.
There is no M06 mission enum, map, controller, local child or episode refill.
The v6 outcome checks currently attach M05 rescue only to that pending edge;
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
explicit full-arsenal arcade compatibility. This is a proposed increment, not
the current capability 26 contract. Update every client, adapter, brain and
playtest reader together and preserve initial MapInfo-before-state ordering.

Recommend mutually exclusive `m06` geometry and mission facts, matching current
strict boundaries. Geometry contains six ordered required Arrival objectives,
one registered transit departure Use target and boarding region, a supported
companion start, and an optional service-region marker bound to its encounter.
Candidate objective IDs are `freight_cleared`, `rail_lane_cleared`,
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
character canon or paid generation follows from this plan. Before any future
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
