# QA approach arrival ordering

Status: implemented, focused headless gates passed, ordinary rendered routes
and full client checks pending. Updated 2026-10-01.

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
