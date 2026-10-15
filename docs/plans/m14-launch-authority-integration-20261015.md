# Launch Authority combined-arms integration

Status: **planned**, 2026-10-15. Implementation starts after the
[Walker foundation](walker-foundation-20261015.md) passes its composed gates.
The Roadmap's existing campaign rung owns sequencing. This is its next bounded
implementation plan, not a parallel campaign order.

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
Connected M14 requires the next available capability, provisionally 49, for all
roles. `MapInfo.m14` owns exact ordered objectives, the jeep placement, support
groups, final control and fallen-world registration. `MissionState.m14` owns
completed/current objective, introduced support stage, machine-fallen receipt,
final squad completion and challenge receipts. Existing `Snapshot.walker`
continues to own combat pose, health, warnings and shells. No duplicate Walker
health or timers belong in mission facts.

Required progress is arrival, depot defense, approach secured, Walker disabled,
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
