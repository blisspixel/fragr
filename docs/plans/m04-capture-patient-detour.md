# M04 capture route around released patients

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. The ordinary-input clinic/court capture passes; optional patient endpoint arrival remains unclaimed.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** $0. No provider calls.

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

## Goal and ownership

Restore the ordinary-input M04 texture capture after living civilian contact
made the existing clinic corridor shortcut impassable. Own only
`client/qa/m04-market.json` and `client/scripts/test_m04_town.gd`. The existing
map, bodies, movement, encounter timings, shared combat helper and renderer
remain owned by their current lanes.

## Failure and architecture

The `.agents/qa/m04-textures-final` run completed 13 of 23 states, then failed
walking to `[-19,0,0.75]` at `[-18.61106,0,2.92126]`. It is failed evidence,
not a complete current gallery. All owned processes exited and its recorded
source hashes remained unchanged.

The released authored patients finish at `[-18,0,2]` and `[-18,0,6]`.
The old north-south route passes through their real body clearance. Use the
open western corridor at x=-19.75 to pass both people, then turn toward the
repair supplies and ordinary service stair. Correct the corresponding optional
combat search leg as well, so it does not retain the same blocked fallback.

No wire, authority, collision, map, spawn, supply or outcome changes are needed.
Keep all 23 states, 28 required guards, phase and claim checks, existing
movement deadlines, clinic release and deliberate roof departure. Preserve
every M01-M06 map byte.

## Verification

Load the actual authored map and capture manifest in the existing town harness.
Derive both clinic worlds and patient endpoint bodies from those files, using
the delivered MapInfo collision shape, ordinary `MoveStep.live_step` and the
shared `ActorContact.resolve`. Prove the old straight leg is blocked, the new
polyline reaches each waypoint, feet remain supported, and accepted positions
retain at least the summed body radii. Test recovery from the actual failed
pose as well as the declared northern entry.

Run the focused pinned headless town harness with clean logs and its PASS
marker. Freeze the manifest and test before the next exclusive rendered lease.
Only a complete inspected rerun can refresh the current M04 gallery. Record
remaining presentation gaps honestly. This is capture and authoring evidence,
not fresh-player or full mission acceptance.

## Focused receipt

Pinned headless `test_m04_town.gd` passed cleanly with exit 0 and its PASS
marker in `.agents/m06-buildout-20261001/client-m04-patient-detour-final.log`.
The former x=-18 northbound repair leg stops at z=1, exactly one summed body
radius before the first patient. The new repair, market-search and service-stair
routes pass both clinic worlds with real support and nonpenetration assertions;
the recorded failure pose also reaches the detour entry. `git diff --check`
passed. No import or rendered process was launched for this focused check.

The complete rendered rerun and selected-gallery refresh remain pending the
exclusive runtime handoff. The original 13-state failure remains preserved.

## Exposed mixed-fight capture handoff

The `.agents/qa/m04-textures-second-final` rerun failed after six states:
the player died during 1.167 seconds of combat travel at the first mixed-stage
walk. The solo lesson still shows 100 HP and 5 armor. The next group's bodies
are visible in that still, but no region-dispatch log precedes the death.
Combat travel may shoot newly placed dormant guards before completing its
approach; the failed output does not retain an exact hit/feet trace sufficient
to attribute the initial alarm. No claim that a region crossing was proved.

Keep the lesson observation and combat search near `[5,0,-15]`, south of the
next encounter's z=-9 threshold. Preserve the health/ammunition visits during
the next stage's ordinary walking route, with combat travel disabled until its
safe `[5,0,-10]` stance. The existing combat observer then follows the short
ordinary approach to `[5,0,-8]` and conducts the unchanged five-guard fight.
The existing helper can evade real committed attacks during that approach;
no hidden activation, invulnerability, damage or timing changes are needed.
Its 25-second fight deadline and 15-second per-walk deadline stay unchanged.

The new stance uses real ground east of the notice-board collision host,
outside the high western stair footprint. Test ordinary access, real visibility
to the lesson body and the mixed drone, and the safe versus entered encounter
regions against the actual authored data. The live near-rendering fix removed
the previously inspected beige/black facets from both actual solo windup and
firing stills, but this failed run still cannot refresh a complete gallery.

The revised actual-map focused check passed cleanly with exit 0 and its PASS
marker in `.agents/m06-buildout-20261001/client-m04-safe-handoff-final.log`.
Both clinic worlds retain supported access to every revised ordinary waypoint,
the lesson stance has real line of sight to its actual drone, all quiet approach
endpoints remain outside the mixed activation region, and the observer's final
short approach enters that region with a clear shot to the eastern Notary.
The patient detour and original blocked-leg regression continue to pass.
This proves geometry and route intent; live survival remains a rendered gate.

The `.agents/qa/m04-textures-third-final` run passed the revised mixed handoff,
clinic and both market fights, then failed after 13 states on the repair return
north. It reached the earlier failed southern waypoint, but stopped at
`[-19.79004,0,1.385258]` heading back to `[-19.75,0,8.5]`. This is outside
the stationary patients' summed-radius clearance, so their endpoint fixture
does not explain this new refusal. A following companion in the reversed lane
is plausible, but no authoritative body trace was saved to prove that cause.

Remove the redundant southern excursion from the repair stage. The clinic
approach was already visited earlier and contains no required repair supply.
Walk directly from the market's northern entry through `[-19.75,0,10]`,
`[-19.75,0,8.5]` and `[-18,0,8.5]` to the unchanged finite bench pickups.
Keep the actual failed-pose recovery regression, both-world body clearance and
every stage/guard/phase/claim/deadline. Preserve both failed 13-state receipts.
An optional ignored snapshot observer may retain bounded actual living-body
positions during the next route without changing game authority or input.

## Court approach and finite supplies

The fourth rerun passed 17 states, including the repair detour, Shotgun claim
and awning armor secret, then died during 1.391 seconds of early court combat
travel. Its bounded authoritative snapshot trace establishes the handoff:
all eight court guards remain idle while the player waits at approximately
`[0.07,0,14.96]`; the struck Sweeper enters Hit and the others enter Windup
while the player is still south of the court's z=18 activation region. The
following combined firing reduces HP from 100 to 80 to 10 before death.
The trace is retained under `.agents/qa/m04-textures-fourth-final`.

Disable combat travel for the court approach. The existing south wall ends
at x=-8, and the activation region begins at x=-7. Ordinary x=-7.25 feet
clear the wall with the normal 0.5 radius while staying outside the region.
Enter the west court supply lane through that gap, collect the unchanged
shells, bullets and armor at x=-8/-10/-12, z=20, then let the combat observer
walk from x=-12 through x=-8 to x=-6, z=20. That last leg genuinely enters
the court region. The armor adds its authored finite amount before combat;
no health, body, pickup or enemy changes are made. Revisit the existing
x=-6 health pad before the balcony probe so actual post-fight need can consume
it normally. All six ground/drone and both balcony deaths remain required.

The focused actual-map regression must check the entire supported route in
both clinic worlds, quiet feet outside the court region, genuine final entry,
real combat sightlines and normal proximity to each finite supply. Preserve
the original 15-second walk and 25-second combat bounds and all 23 states.

The focused town harness passed cleanly with exit 0 and its PASS marker in
`.agents/m06-buildout-20261001/client-m04-court-approach-final.log`.
Both prepared clinic worlds support every revised court waypoint, the west
supply preparation remains outside the actual activation region, all three
finite supply positions are visited, and the short final entry has a real shot
line to the western Notary. Prior lesson and patient regressions still pass.
Live survival and full gallery refresh remain pending.

## Committed-attack approach ordering

The fifth run failed after six states. Actual snapshot samples show the mixed
approach reaching `[5.002,0,-8.501]` before its five guards enter Windup.
The committed-defense branch then moves the player away from the unfinished
waypoint while firing stays disabled; the real companion remains 2.34-4.00m
away throughout the final 25 ticks. This is not an observed ally collision.
The run entered the fight at 55 HP: the notice fight had left 30 HP and the
existing board medkit supplied 25. The solo Notary cost no further HP in this
run. The notice loss occurred after reaching the initial approach, so it must
not be attributed to unrecorded precombat idle damage.

The shared helper lane owns acknowledging already reached approach waypoints
before choosing committed-defense input. Its unchanged arrival thresholds are
horizontal distance below 0.5m and vertical difference below 0.2m. Shorten the
authored observer endpoints to 0.75m inside their regions: street `[5,0,-8.25]`,
court `[-6.25,0,20]`, and notice `[-5,0,-23.25]`. The entire horizontal arrival
disk then stays inside each region. The notice's final exposed walk becomes
the existing combat observer's ordinary approach so firing/control can begin
earlier, while its original southern waypoints and search remain available.
No threshold, guard, phase, damage, supply or deadline changes are made.

Test the supported routes and explicit arrival-disk region margin using actual
authored definitions. Geometry tests alone do not prove live region activation;
the next trace must record that event and the unchanged encounter clear.
No further headless/import/render process starts until the shared helper lane
returns its exclusive lease.

## Western mixed-fight stance

The sixth run failed after six completed states. The notice and solo Notary
probes both finished with 100 HP; the notice used the finite arrival armor.
The mixed observer completed its approach, fired 16 shots and confirmed three
of five guards before `advance_sweeper_a` killed the human. Snapshot ticks
1405-1420 show nearly unchanged feet `[5.992,0,-9.327]` and Latch about 1.01m
away. Earlier samples already show ordinary movement constrained near this
same eastern lane. This is actual tangent body contact, unlike the fifth run's
unfinished approach, although distance alone does not identify every blocked
input. The shutdown has texture-leak errors and is failed evidence. It does
not refresh the public gallery.

Use the existing western service treads as a quiet approach: preserve the
board health and ammunition visits, walk around their south end, then climb
only the first three half-metre treads to `[-16,1.5,-11]`. The combat observer
walks and drops normally to `[-16,0,-8.25]`. This is an ordinary drop, not a
jump or a relocated camera. It avoids crossing the west Sweeper's one-metre
body clearance and avoids a diagonal ground shortcut through the stair solids.
The west Sweeper is about 2m from the intended fighting stance; the eastern
Sweeper is about 34m away. Those are geometric preparation facts, not a claim
that the live controller will defeat them in that order. All five named
required deaths remain necessary. No phase, target eligibility, health,
supply, weapon, difficulty, timer or arrival tolerance changes are made.

Extend the actual-map regression to the supported treads, ordinary falling
approach, arrival disk, real west-Sweeper shot line and body separation.
Record the next actual region entry, targets, movement and survival before
claiming this strategy works. The sixth failure and source hashes remain
under `.agents/qa/m04-textures-sixth-final`. All owned processes exited.

The western drop preflight passes ordinary movement, physical entry, body
separation and timely vertical arrival, but rejects the proposed immediate
west-drone shot line. The real southwest awning blocks that high ray from
the ground stance. Retain that physical shelter rather than claim an exposed
shot. Prove the actual nearest west-Sweeper shot line there, then prove the
existing first search waypoint `[0,0,-8]` reaches a clear shot line to the
west drone after the ground threats are cleared. This is existing cover and
ordinary search, not a new collision exemption or a removed required target.

## All eight court attackers stay eligible

The seventh run completed 17 states, including all five mixed guards, both
market waves, the patient detour, strict repair claims and the awning secret.
The normal court supply approach claimed finite armor and entered physically.
Its ground probe killed five of the six required ground/drone guards before
`court_clerk_a` killed the human. Both balcony Clerks were live and attacking,
but `target_required_only` excluded them from that probe. The cached helper
summary said alive; the authoritative log records death and attempt reset.
The run and shutdown are failed evidence and no public gallery was replaced.

Move both named Clerk requirements into the existing court fight, requiring
all eight actual court guards with the same required-only targeting, 25-second
combat deadline and ordinary evasion. This permits defence against every real
attacker without changing authority or enemy behavior. Keep the next named
balcony state as ordinary court movement and physical objective confirmation,
with the exact six-objective completed prefix. It must not demand fresh deaths
for already defeated Clerks: the shared probe deliberately excludes actors
already dead at its start. Its finite health visit and existing walk remain.
No required guard is removed. The capture still has 23 states and exactly 28
unique named required deaths, including both court Clerks and the final roof
use gate. Add a regression comparing these names with the actual authored
roster and verifying the exact all-eight court gate and later objective check.
The shared helper lane owns its separate frozen ordering correction. No
headless/import/runtime command starts while that lane holds its lease.

## Final verified receipt

The eighth run, `.agents/qa/m04-textures-eighth-final`, passed all 23 states
with exit 0 and a clean engine log. The actual server recorded all 28 human
kills, every required encounter, optional clinic opening and patient release,
and the deliberate roof departure. The exact ordered six-objective prefix
was checked before the exit. No source hashes changed during the run and all
owned server/client processes exited before the runtime lease was returned.
The seven earlier failed captures remain diagnostic evidence.

| Actual attempt record | Result |
|---|---:|
| Attempt | 1 |
| Deaths | 0 |
| Required guard kills | 28 |
| HP lost | 85 |
| Armor lost | 150 |
| Secret claims | 3 |
| Notary crashes observed | 7 |

These are resolved participant-record counters, not inferred shot damage.
All three secret locations were visited and their ordinary pickups actually
claimed in this run. The meal-table medkit restored missing health after the
court fight; no artificial damage was used to make that pickup consumable.
The court probe required and defeated all eight named attackers, including
both balcony Clerks, under its original deadline. The subsequent ground walk
confirmed the objective instead of creating a second death receipt.

Focused `test_m04_town` passed cleanly at
`.agents/m06-buildout-20261001/client-m04-eight-court-final.log`. It checks
actual-map movement and body clearance in both clinic worlds, the blocked old
patient leg, ordinary replacement routes and stairs, real drop/entry timing,
existing cover and search sightlines, all 28 unique authored guard names,
the all-eight court probe and its later physical objective confirmation.
This is bounded authoring evidence; fresh-player and difficulty acceptance
remain separate campaign gates.

The recorded map hash remains
`79babb3e38678f021a6719c49d2cf321f50c6946efec7843bbf9ffe221faaaa5`.
The final QA manifest hash is
`b30db3930a0e53b330a03f40221f6cc36c9c8c7d23015516b2395b63775cc0c0`.
Exact shared helper, material, shader and server hashes are retained in the
run's `source-start.json`, with unchanged-source and process cleanup facts
in `source-end.json`.

All ten existing M04 gallery filenames were refreshed from inspected eighth
run images. The live solo Notary Windup/Firing frames and combat motion board
show the actual resolved tell, launch and crash. The motion board also shows
coherent close companion coverage; the earlier detached beige/black facets
are absent from these inspected views. The clinic sign and patched plaster,
market water/detail, awning pickup, court height and actual ESC-bound departure
were inspected individually and on the complete contact sheet.

The patient strip establishes grounded release and bounded walking, not both
people reaching their final endpoints. At departure, `edda_team_a` is at
`[-18,0,2]` and `edda_team_b` remains at `[-19,0,2]`, waiting one metre behind
the first person. Resolving that optional route queue is further polish; no
NPC arrival timer gates the roof exit. No map, body exemption, server outcome,
health grant, encounter timing or movement tolerance changed in this repair.

## Historical workspace checkpoint (2026-10-02, before final gates)

The following receipt records that checkpoint. Current merged integration and
completed local gates are recorded above; publication receipts are tracked in
[release closeout](m06-release-closeout.md).

Root's final serialized `cargo fmt --all -- --check` and workspace Clippy
with warnings denied pass. `cargo test --workspace --locked` passes 1,244
tests with three existing ignored tests and no failures. Exact receipts are
`.agents/m06-buildout-20261001/final-fmt.log`, `final-clippy.log` and
`final-workspace-tests.log`. The rendered tour receipts prove their recorded
helper/assets and server hashes; they do not claim a newly rebuilt release
binary. Coverage is running, and the final matching release rebuild, broad
serialized Godot checker, CI and release are still pending. No shipped claim
or fresh-player acceptance follows from these bounded authoring gates.
