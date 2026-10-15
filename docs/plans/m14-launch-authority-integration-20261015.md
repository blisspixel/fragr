# Launch Authority combined-arms integration

Status: **implemented**, integration pending, 2026-10-15, on
`feat/launch-authority-20261015`. Final mission acceptance remains open below.
The [Walker foundation](walker-foundation-20261015.md) shipped in v0.84.0
through PR #403 with passing main and three tested desktop packages.
The Roadmap's existing campaign rung owns sequencing. This is its next bounded
implementation plan, not a parallel campaign order.

Native mission/map/combat, client/save integration, existing-asset presentation
and the separate Sector 9 spawn-exit refinement run in parallel. The composed
branch returns to passing main before another campaign increment begins.

Primary accessibility guidance was rechecked October 15 against
[Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/)
and [Xbox guideline 103](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/103).
Attack warnings retain distinct shapes and timing as well as colour; departure
uses readable text and geometry as well as the red-to-white pad-light change.
No engine, dependency or timing-rule upgrade belongs to this integration.

## Goal and non-goals

Join the already authored launch works, working jeep and new Walker owner into
the accepted [M14 brief](../campaign/l14-launch-authority.md), then connect M13's
completed lift departure to M14 and persist its actual outcome. The first boss
cycle teaches alone. Later support enters visibly. Infantry can complete after
declining or losing the jeep. Coalition departure, the gantry silhouette and
settlement cargo must establish why this battle matters.

No new vehicle physics, mission-only weapon authority, arbitrary enemy health
scaling, puzzle locks, mandatory driving, mandatory companion, new cloud service,
general moving navigation mesh or procedural battlefield is introduced. M15
remains pending until its own mission is implemented. Original development
fixtures remain launchable and historical save hashes remain closed history.

## Bounded implementation order

1. Create `server/maps/m14-launch-authority.json` from the inspected development
   source through its native authoring seam. Preserve depot, parked-gunner lesson,
   outer circuit, two supplied infantry flanks and visible gantry. Add the five
   registered Walker solids and conservative sweep. Candidate ground stations
   are `[8,0,26]`, `[9,0,31]`, `[7,0,36]`, subject to the strict load and driving
   checks. The existing `apron_low_cover` crosses that proposed sweep and must
   move to a useful flank, not vanish accidentally. Author a new source/hash;
   do not silently rewrite the historical standalone battlefield.
2. Add `maps/authored/m14.rs`, `mission/m14.rs` and `protocol/m14.rs` using the
   established mission owner. Register the captured jeep inside the mission
   definition, reusing `vehicle_placements` validation and boarding sweeps as
   M12 does. Prepare conservative navigation with both the parked hull and
   Walker sweep together, plus the post-disable world, before readiness.
3. Gate the existing Walker owner by accepted M14 progress. Replace the old
   apron practice group with the actual first solo boss lesson. Stage two
   dispatches a Sweeper squad and Notary pair from the pad road; stage three
   dispatches Enforcers from the gantry and requests the apron station. Actors
   start at visible authored ingress, move with shared controllers and never
   appear behind the participant. The first full warned attack and recovery
   occurs before any support. If accurate fire crosses both HP thresholds in
   one recovery, retain pending support transitions and introduce them in order
   without overlapping both new squads at once. Do not discard accepted damage
   or impose unexplained health locks to enforce staging.
4. After machine disable, finish committed shell travel safely and transition
   to the prepared fallen world. Send MapInfo before changed mission facts.
   The selected fallen hull must leave both infantry routes and the gantry
   control approach accessible. Disabled geometry and support eligibility are
   server facts, not an animated client assumption. Then dispatch the final
   gantry squad and accept fresh supported all-party Use at its control.
5. Add `mission/controller/m14.rs` through the existing shared controller.
   It walks the mandatory infantry route, reads actual Walker deadlines and
   translated joints, dodges the committed lane and uses existing finite
   equipment decisions. Mounted combat stays an optional ordinary seat action.
   Add client `m14_mission_state.gd`, `m14_launch.gd`, HUD words and the departure
   hook using existing scene manifests and the Voice bus.
6. Add connected promotion and exact historical migration through the current
   `run_file`, `legacy` and locked store owners. The next save format is expected
   to be version 18, checked against current source at implementation time.
   Promote completed M13 to M14 with no Episode III refill. Retry restores the
   actual M14 entry equipment and clean encounter/jeep/Walker state without
   rewinding process ticks, input sequence or inventory revision. Preserve all
   earlier outcomes and exact original-byte archives. Completed M14 records
   pending M15; do not apply Episode IV's refill until M15 promotion exists.

## Facts and compatibility

The foundation capability 48 remains sufficient for its standalone range.
Connected M14 requires capability 49 for all
roles. `MapInfo.m14` owns exact ordered objectives, the jeep placement,
final control and fallen-world registration. Authored encounter definitions
own support groups. `MissionState.m14` owns
completed/current objective, introduced support stage, machine-fallen receipt,
final squad completion and challenge receipts. Existing `Snapshot.walker`
continues to own combat pose, health, warnings and shells. No duplicate Walker
health or timers belong in mission facts.

Required progress is arrival, depot defense, road secured, approach secured, Walker disabled,
gantry secured and fresh shared departure. Driving and optional briefs never
gate departure. The Assisted brief records actual depot completion. Standard
also requires the original registered jeep to survive through Walker disable;
a destroyed then respawned jeep cannot erase loss. Severe records a wholly
on-foot Walker fight, conservatively requiring no participant seat occupancy
between activation and disable. Track these as resolved receipts rather than
inferring them from the final snapshot. Optional preserves retain the exact
fields used by records/rewards, not a second achievement system.

Initially retain the foundation's exact attack timing on all difficulties and
campaign rules revision 4. Difficulty-specific Walker timing is a separate
measured tuning change requiring a new shared rules revision and matching
client/save validation. Do not mix that tuning into a save migration casually.

## Lore, presentation and spend

Follow [Mars direction](../design/mars.md), the [art bible](../ART_STORY_BIBLE.md)
and existing voices. The Walker is Union equipment with no assumed personhood.
Machine decline never erases the distinction between captive agents, human
security and equipment. The same practical cargo seen in prior Mars work should
appear at departure. Mara's brief other-site reports and Tern's repair invoice
are bounded, optional presentation; text remains readable without audio and
missing media never blocks departure. Exterior red dust cannot swallow Union
silhouettes or warning shapes.

Implementation and acceptance reuse current assets at $0. Any later generated
Walker or launch-service asset follows the native funded-credit preflight and
reservation workflow after a live balance check. No purchase, renewal, automatic
top-up or overage is authorized by this plan.

## Success criteria and evidence limits

Prove all authored landmarks, supplies, enemy approaches, both infantry flanks,
jeep access and the outer circuit in intact, moving-conservative and fallen
worlds. Test actual first-cycle isolation, delayed support ordering, simultaneous
threshold crossings, dead-shooter committed damage, blocked relocation,
destroyed/abandoned jeep handling, late spectator hydration, party loss, fresh
departure, retry and exact save promotion. Ordinary finite-input routes must
finish with jeep present, absent and destroyed, plus a mounted Notary lesson
and a human magazine/reload route. Inspect the full fight in both supported
renderers and the transition out of Episode III.

Passing accurate automation is authoring evidence. Fresh-player understanding,
the fourteen-minute first-run target, all three difficulty judgments, polished
final art and the finished four-hour campaign remain separately recorded gates.
Mara's overlook report and distant other-site flares now follow the accepted
approach-clear transition, with focused lifecycle checks passing. Controlled
rendered inspection passes on both paths; one distant flare remains
occluded from the tested west approach. Ordinary trigger capture and final
overlook staging remain open, as recorded in the art plan. This nonblocking presenter cannot guarantee
report-before-stomp ordering if a participant already occupies the activation
area when the approach clears; it never delays authoritative combat.

## Local integration checks

The six focused save tests pass promotion with exact finite stock and no refill,
strict version-17 archives, refusal of forged future receipts, death/reopen/retry
and actual supported departure capture. The departure fixture arranges cleared
encounters to isolate persistence; it is not a route clear. The native route owns
combat evidence separately.

The client accepts native intact and fallen vectors and rejects stale facts,
early support, invalid ordered outcomes and changed retry geometry. Its retained
intact contract prevents a fallen-to-intact retry from replacing the original
Walker body or station path. Exact retry and a spectator joining after the fall
remain accepted. Focused frontend and M09/M10/M13 regressions pass.

Independent native review caught the M14 controller bypassing shared living-body
avoidance; its equipped branch now returns through the common steering owner.
Integration review also found readiness and continue MCP schemas still offering
only M01-M04 despite the runtime accepting later missions. Both now derive from
the typed built-stage list shared by save progression. New schema and actual
snapshot-observation tests cover the connected M14 path.

A final next-round seam review caught a separate existing MCP omission: its
weapon selector stopped at Arc and refused Rocket despite M13 and M14 ownership.
The tool schema and strict validator now derive native weapon wire IDs from
`WeaponType::ALL`. The actual tools/call regression fails before the correction
and passes afterwards for every supported selection, preserving fire and
rejecting unknown, wrong-case and non-string IDs. All 61 focused MCP tests and
the repeated composed native checks pass after this correction. It grants no equipment
and changes no authoritative combat rule.

A final independent read-only review found no further substantive blocker in
local preview/start/readiness, pending-M15 UI, admission and controller callers,
promotion/capture/retry, typed MCP schemas or map hydration. It confirmed the
capability-49 boundary, retained M13 resources without a refill and refusal of
pending M15. This is source review, not additional executed test evidence.

The [native receipt](../evidence/m14-native-20261015.md) records eleven focused
tests, including finite infantry clears with the original jeep present,
destroyed and absent. The human magazine route departs at 75 HP using navigation
rebuilt from MapInfo. That test supplies no equipment and skips no combat phase.
Independent review also added native/client refusal of pre-approach boss-cycle,
support and mounted-fight receipts, while retaining legitimate early jeep loss.

The actual owned-child M14 practice harness passes admission, arrival dismissal,
readiness, fourteen fitted lights, successive accepted snapshots and clean child
shutdown. The first whole-client run exposed old version-17 writer expectations
and a stale practice-selector count; those checks now require version 18 and
the M14 entry without changing historical input fixtures. The new M14 harness
also now checks snapshot cadence rather than expecting unchanged mission facts
to be broadcast each tick. The first failed logs are retained. The corrected
whole-client run passes import, 378 script parses and 180 harnesses. The final
composed check repeats all 559 checks after the capture helpers, terminal copy,
Mara presentation and shared ArenaCover fix, with a clean log and exit zero in
`.agents/launch-authority-20261015/godot-cover-final.log`.

The standard published tour passes all 32 states and archives fourteen current
stills, repeated after the final ArenaCover construction change in
`.agents/launch-authority-20261015/published-tour-cover-final/`. The contact sheet,
boot and multiplayer menus, shot strip and Rail impact strip were inspected.
It ran through isolated X11 and software llvmpipe;
this is renderer evidence, not a physical GPU benchmark. It is not the M14
combat route. The first rendered M14 attempts exposed unsafe capture dwell,
out-of-range engagement and stair-edge QA steering. Those historical failures
remain retained alongside the corrected ordinary-input clears below.

The complete OpenGL route now passes all thirteen states and actual supported
departure, ending at 100 HP with finite supplies remaining. Inspection exposed
the generic terminal's misleading pending-review text beneath the released-pad
sign. The registered M14 console now uses a specific departure label, verified
against intact and fallen native geometry and the existing decoration harness.
The two [actual-play stills](m14-art-integration-20261015.md) retain the Walker's
warning and fallen handoff; the latter still has final guards active. Vulkan
also reaches departure at 100 HP. Its two teardown diagnostics were reproduced
in a bounded fixture and traced to map geometry changing render layers after
scene attachment. ArenaCover now prepares geometry off-tree with final layers
before adoption. The exact failing fixture, intact/fallen/terminal views on
both renderers and focused shared-presenter checks pass cleanly. The standard
published tour and complete client check also pass after this shared change.

The first full native suite exposed a Sector 9 freight extension blocking a
Sabotage plant area and its hold approach. Shortening the two mirrored rows
restores those routes; all fifty Sabotage checks and nineteen spawn checks pass.
The corrected five-seed comparison and six inspected current-client views are
retained in the [Sector 9 receipt](../evidence/sector9-spawn-exits-20261015.md).
All eight required live network cases, the deterministic CPU benchmark and the
120-second mixed-client soak pass, with their limits recorded in the
[composed native receipt](../evidence/native-launch-authority-20261015.md).
The workspace run after the final MCP correction passes 2,100 tests, with five
intentional skips and no filtered tests. Final unfiltered line coverage passes
at 93.01%, above the existing 90% floor. Formatting, strict all-target Clippy and
the complete release workspace build also pass after that correction.
The seven-map roster and ordinary rendered M14 departures
pass. Publication remains in progress. Docker is installed but its daemon socket is inaccessible locally;
Terraform is absent. Their unchanged build/validation jobs still require CI.
No final mission, balance or hardware-performance claim follows from the
focused checks above.
