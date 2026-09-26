# M08: The Weight of Permission

**Status:** proposed, unbuilt. Mars before the wipe. Target 12-16 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#level-13-the-weight-of-permission).

## Story and cast

With communities committed, the coalition attacks industrial custody and launch
works needed to repair and supply its fleet. This is one part of a wider action;
allies seize other sites. Mara coordinates real contributions. Tern identifies
transport requirements. Latch insists workers are invited to help after release,
not transferred to a new owner. Renn can identify control dependencies.

Patterns from lunar cargo rerouting recur. The protagonists isolate an exposed
path while preserving local services. They now have reason to suspect a larger
intelligence, not knowledge of an imminent wipe or a reliable timetable.

## Industrial plan

Service entrance -> foundry edge -> machine hall -> freight galleries -> launch
works. A maintenance ring connects the service entrance, upper gallery and
worker release area. The launch objective is visible through industrial windows.

| Area | Construction and function | Encounter |
|---|---|---|
| Foundry edge | Heat shielding, pouring machinery visible behind barriers | Moving threats and a safe alternative to hazard crossings |
| Machine hall | Dense machines, overhead services and broad work lanes | Mixed squads with meaningful short-range flanks |
| Upper galleries | Cross-floor views and two ordinary stairs | Priority support targets, exposed supply choice |
| Worker quarters | Restraint frames and a nearby secured room | Optional worker release, no walking-escort chore |
| Freight loop | Cargo path with functional bends and alcoves | Recovery then counterattack through known space |
| Launch works | Large but bounded gantries, berms and service rooms | Walker crest, different firing angles and accessible resupply |

No environment hazard requires jumping through a tiny timing window to finish.
Hazards have a visible cycle and bypass. Platforms have real support and headroom.

The launch works is a deliberate increase in battlefield scale after the earlier
indoor missions. Freight buildings, gantry supports and terrain divide local
positions; service interiors provide flanks and recovery. The player can read
the next useful destination from each position. Prove the infantry route before
integrating the planned drivable vehicle. Do not enlarge gaps simply to justify it.

## Vehicle showcase

This is the first proposed combined-arms campaign landmark. A captured armed
utility rover, the jeep in [vehicles](../plans/vehicles.md) built when M08 is
next, connects the freight depot, bermed launch approach and main gantry.
Its mounted weapon helps break an exposed defense, while service interiors and
trenches let infantry flank that same position. The rover circuit is open
ground; nothing has to be unlocked. The Walker remains defeatable if
the rover is lost; scarce vehicle ammunition cannot become a mandatory key.

Broad stairs and catwalks climb from the machine hall to the gallery, with a
view across the machinery on the way. No lifts to call, levers or timed waits.

Vehicle and moving-lift systems are unbuilt. Prototype server authority, safe
occupancy and dismounts, collision, aim, damage, spectator views and agent actions
before authoring a fleet. Then playtest rover and infantry approaches, vehicle
loss, mission retry and mixed threats. The goal is a compact battle with distinct
positions and choices, not an empty map crossed at driving speed.

## Weapons and boss

The Article Blade appears as a risky close-range opportunity before an encounter
that suits it. It is optional against the Walker. Guaranteed ordinary weapons,
a Rocket Launcher with a short supply of rockets before the exterior crest,
and movement suffice. Splash stops at cover. The walker stays defeatable if
those rockets are already spent. Do not make a melee pickup bait into
an unavoidable instant-death stomp.

Walker phases: telegraphed area attack, relocation, exposed recovery and supporting
units entering from visible lanes. Terrain gives more than one viable response.
Health is tuned after movement and attack readability work. The player is fighting
machinery and coordinated defenders, not waiting out invulnerability cutscenes.

Secrets: protected Cells cache reached through the service ring; armor on a
gallery reachable by a clearly readable optional jump; spare Blade/sidearm supply
for a depleted inventory. Never make the last secret necessary to afford the boss.

## State and exit

`works_entered` -> `machine_hall_cleared` -> `walker_disabled` ->
`fleet_supply_ready`, each by winning a fight or arriving. Optional worker
rescue is distinct from taking the factory.
Completion shows allied crews working voluntarily and transports becoming usable.

A continue restarts the mission, including the Walker, supporting units and
entry resources. Keep the approach compact. Measure repeated failures
for causes such as unreadable cues or empty ammo, not just player damage totals.

Mastery hooks, planned, not built: a par time on the result, the rover circuit
as the runner's line to the gantry, and best clear time in the service record.

## Presentation and allies

Forge light, dust, heat distortion kept behind readable silhouettes, and red-rock
industrial architecture. Tern can make a dry joke about liberation arriving with
an unpaid repair invoice. A concise departure panel acknowledges preparation and
elapsed travel before the coalition's return to Earth.

Allied workers and fighters act autonomously; no tactical controls are required.
Test boss target changes, ally loss, solo counters, mission restart and worker
states. Record frame times during the actual largest
fight on named hardware; a quiet static view is not the performance evidence.

## Level 13 design (twenty-level expansion)

**Status:** planned, accepted 2026-09-25. In the
[twenty-level expansion](../plans/campaign-expansion.md) this mission splits:
the foundry on foot is level 13, and the exterior launch works with the jeep
and the Walker become [level 14](l14-launch-authority.md). The Article Blade
moves to [level 15](l15-civic-pressure-valve.md). [Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| III Common Cause | The Martian foundry | Rocket Launcher | 11 min | 4:30 | 1 |

**Premise.** The works that can arm and repair free communities are still Union
property, run by bots and a few human overseers. The coalition takes them in
several places at once; this is ours. Latch insists the workers be asked, not
freed like cargo and handed to a new owner. The rerouting rhythm from the
depot runs through the foundry's control systems, and you cut one exposed path
without cutting the water and air the town depends on.

**Hook.** Industrial hell in bright forge light, and the first rocket.

**Teaches.** The Rocket Launcher, requisitioned, according to its pallet, as
office supplies. It waits in the freight office before the freight loop.
Across the loop, on a lower platform far from you, a Sweeper squad clusters
around a stalled cart: one rocket, splash falling off with distance and
stopping at cover. Rockets are their own ammunition, scarce, and the level
gives enough to learn and not enough to waste.

**Shape.**
1. **Arrival.** The service entrance. The great ladle glows through every
   window, and the heat shimmer stays behind readable silhouettes.
2. **First fight.** The foundry edge: Clerks and Sweepers among hazard
   machinery whose cycles are visible, with a bypass beside every crossing.
3. **Escalation.** The machine hall: mixed squads, a Heavy Sweeper, two
   Notaries in the high roof, short-range flanks between machines.
4. **Breath.** The worker quarters: restraint frames on a bot workforce, and
   one human overseer who drops his baton. Latch asks the workers what they
   want. Some come with you, some walk out the other way, and one says no and
   keeps working, and Latch lets them.
5. **Set piece.** The Rocket Launcher lesson, then the freight loop
   counterattack through space you already know: an Assessor over the loop,
   Sweeper squads at both ends, an Enforcer charging along the rails.
6. **Turn.** Renn points at the relay the rhythm runs through, bolted beside
   the town's armored water feed. Shoot the relay; the feed cannot be hurt and
   stays on. One shot after a fight, not a puzzle.
7. **Climax.** The ladle hall's upper galleries: a pour in progress, the
   gallery supports under Union fire positions, Clerks and a Heavy on the far
   gallery.
8. **Exit.** The freight lift, the level's one door. It climbs into daylight
   and the launch works.

**Landmarks and sightlines.** The great ladle and its pour, glowing through
every window. The upper galleries overlook the route you took below. The
freight lift's shaft light at the far end of the hall.

**Doors.** One: the freight lift, the exit.

**Secrets.**
- A Cells cache through the service ring, the six on a slag-stained pipe.
- Gallery armor reached by a readable jump from a crane rail, the six on the
  rail's end stop.
- A foreman's locker, the six inside the lid: Rockets and Shells.

**Brief.** Assisted: free the worker quarters. Standard adds: clear the upper
gallery's supports. Severe adds: take no hazard damage.

**Par and the runner's line.** 4:30. The upper galleries all the way, dropping
to the freight loop only for the counterattack.

**Story in play.** Page in: "The Martian foundry, three days later. The
habitats voted, and this time the vote came with trucks. The works that can arm
free communities are still Union property. Take the works." Latch's line in the
quarters: "Ask them. Don't free them like freight." The foundry PA keeps
announcing shift quotas to a shift that has left.

**Humor.** The Rocket Launcher's pallet: *Office supplies. Qty 1.* The safety
board: *Days without an unscheduled retirement: 0.*

**The moment.** The first rocket across the freight loop, and the pallet it came
on.
