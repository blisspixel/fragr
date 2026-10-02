# QA approach arrival ordering

Status: implemented, focused headless gates and actual M04/M06 routes passed.
Final full client checks, CI and release pending. Updated 2026-10-01.

The combat capture controller checked a committed attack before it called
`follow_route`. A participant already inside an approach waypoint can therefore
keep evading without acknowledging arrival. A final reached waypoint can leave
the no-fire approach gate active until the capture deadline.

## Bounded correction

Extract the existing pure waypoint arrival predicate. Preserve its exact strict
horizontal distance below 0.5 metres and vertical difference below 0.2 metres,
including conversion from server pawn reference height to feet. Acknowledge one
actually reached approach point before selecting committed defense, and refresh
the usual anchor at that point. An unfinished approach retains its existing
defense, focus, walking and no-fire behavior. A completed approach resumes the
existing normal target, observation, cadence and firing gates.

Reuse the actual approach control seam in the existing focused harness so a
reached point under a genuine committed target cannot remain in defense. Check
strict inside, boundary and outside horizontal/vertical values, route end, open
unfinished walking and unfinished committed defense. Keep actor-contact math,
evasion safety, required phases, 25-second deadline and all mission/map source
unchanged. No forced ticks, outcome grants, provider calls or external spend.

Focused pinned headless tests must pass with clean logs and own PASS markers.
Parent owns subsequent ordinary rendered campaign routes, the whole checker,
screenshots, CI and release. Root granted the sole headless/import lease for
this narrow correction; return it after source freeze and process cleanup.

## Correction and evidence

`waypoint_arrived` preserves the original Vector3 rounding and both strict
arrival thresholds. The production `approach_step` checks that predicate first,
uses `follow_route` to preserve focus-camera orientation, refreshes the anchor
and returns after acknowledging one point. Its unfinished branch retains the
existing committed-threat selection, no-fire defense and ordinary focused
walking. The caller permits its existing observation and fire-cadence gates
only after the returned approach index reaches the route end.

The existing harness uses a real visible Clerk windup and the production
approach control method with an engagement recorder. The reached final point
advances without a defensive call; an unreached point still defends with firing
disabled. Tests retain ordinary open walking, explicitly disabled tell evasion,
focus-camera orientation, one waypoint per frame, route end and empty-route
behavior. They distinguish exact horizontal and positive/negative height
boundaries, inside/outside values, horizontal length and pawn-reference-to-feet
conversion.

Pinned headless `test_qa_combat` and `test_qa_turret` pass with clean logs and
their PASS markers. `qa_combat.gd` also parses cleanly. Receipts are under
`.agents/m06-buildout-20261001/qa-approach-arrival-*.log`. No renderer, server,
inventory, collision, deadline, required-phase or tolerance change was made.
All owned processes closed before returning the serialized lease. The next
ordinary M04 route and final whole-client checker remain parent-owned gates.

## Current ordinary-input evidence

The M04 eighth run `.agents/qa/m04-textures-eighth-final/` passes all 23 states
and all 28 named guards through deliberate roof departure, clean exit 0.
Actual approach completion releases the existing combat gate; no waypoint
radius, damage, target requirement or deadline changed. The western stair/drop
and all-eight court capture strategy are separate authored-route corrections
recorded in `m04-capture-patient-detour.md`, not evidence that ordering alone
fixes every earlier failure. The final record has zero deaths, 85 HP lost,
150 armor lost and three ordinary secret claims.

The current `.agents/qa/m06-port-peek-final/` run passes all 25 states and
21 guards through actual departure. Its phase-aware ordinary peek/retreat
uses the same strict arrival predicate and retains both unfinished no-fire
behavior and the recorded Turret cancellation gate. No source or map outcome
was forced. Earlier incomplete route receipts remain failed history.

## Current workspace verification

Root's final serialized `cargo fmt --all -- --check` and workspace Clippy
with warnings denied pass. `cargo test --workspace --locked` passes 1,244
tests with three existing ignored tests and no failures. Exact receipts are
`.agents/m06-buildout-20261001/final-fmt.log`, `final-clippy.log` and
`final-workspace-tests.log`. The rendered tour receipts prove their recorded
helper/assets and server hashes; they do not claim a newly rebuilt release
binary. Coverage is running, and the final matching release rebuild, broad
serialized Godot checker, CI and release are still pending. No shipped claim
or fresh-player acceptance follows from these bounded authoring gates.
