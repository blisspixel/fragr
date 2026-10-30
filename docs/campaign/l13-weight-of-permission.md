# Level 13: The Weight of Permission

**Appearance anchor for level 13:** A working Martian foundry: dark frames, material handling and controlled production; fighters and red tells separate from rust terrain.
Shared [world direction](../design/mars.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Historical eight-mission brief:** superseded by the level 13 design below and
the separate level 14 brief. The original combined mission was not built.
Mars before the wipe. Original target 12-16 minutes.
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

Vehicle and moving-lift systems were unbuilt when this superseded proposal was
written. The current Level 13 lift and Level 14 jeep are implemented separately.
The original proposal called for prototyping server authority, safe
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

**Status:** implemented as a connected development mission, 2026-10-13.
[The round plan](../plans/m13-connected-round-20261013.md) records verified
behavior and the remaining final-art, first-player pacing and difficulty gates.
The design was accepted 2026-09-25. In the
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

## Foundry appearance pass

The connected Level 13 is the foundry and ridden freight lift, not the combined
foundry/launch-works proposal at the top of this document. The launch works and
Walker belong to Level 14. Existing Rocket teaching, worker choices, hazard
cycle, utility relay and lift outcomes remain server-owned.

`M13Dressing` separates the machine hall, furnace, freight floor, maintenance
ring, worker quarters and dispatch office. Worn neutral steel and muted safety
paint replace the pale repeated enamel. Roof ribs and overhead service pipes
explain the hall's scale; hanging work lights, operating aprons and handling
lanes frame the existing machines. Head spindles, vents, bolted plates and
controls dress their existing bodies. The modelled lathes and freight hoist
remain in their authoritative volumes. The furnace keeps its protected amber
process light, distinct from Union red attack tells. Personal cloths and pinned
cards do not imply that restrained workers have been released.

The immutable-layout guard excludes changed/custom geometry, and `ArenaCover`
keeps one dressing on resends. Small foundation-top patches receive local work
light without changing collision. No signs, hazards or objectives are added.
`client/qa/m13-golden.json` covers nine eye-height art views, and the existing
`m13_weight_of_permission.json` tour keeps route and lift evidence separate.
`test_mars_dressing.gd` covers lifecycle, geometry and light-layer invariants.
The layout pass below closes the roof strips and replaces the primitive machine
blocks.

## Foundry layout pass

Wave 18 recomposed the existing route around its gallery and maintenance
loop without changing a fight, fact, gate or supply.

**Implemented (server geometry, `m13_geometry_tests.rs`).**

- *Closed works.* The open yards beside the service entrance are sealed
  behind a full-height south hall wall and are no longer reachable. Clerestory
  walls close the step from hall roof to ladle roof, the ring's low roof and
  the entrance roof, and the ladle hall's side walls rise to its roof. The
  freight lift keeps its daylight shaft under a hood. A test samples every
  standing position for an open roof and every clerestory for a gap.
- *Service corridor.* A door in the entrance's west wall leads along a low
  corridor, with one valve bank for cover, into the ring's south end. The
  first fight can be taken head-on from the entrance or flanked from the
  ring's west door. Entering this way is still the first fact.
- *Maintenance stair flank.* The ring's north end climbs a walled stairwell
  to a landing on the west gallery, behind the front defenders and close to
  the Heavy on the back bridge. The front stairs remain the exposed duel with
  the marksman across the ladle. Tests prove the loop is walked both ways
  without jumping, the stairwell hides a climbing body from the marksman and
  the ladle floor, and standing on the flank early neither wakes the gallery
  fight nor completes a later fact.
- *Machine silhouettes with matching collision.* The lathes are bed,
  headstock, tailstock and rear guard: waist cover a shot clears, backed by
  cover that is not. The centre press and a new west press have a real window
  between bolster and ram. The furnace hood stands on posts over a glowing
  crucible; the hazard cycle belongs to a drop hammer frame; the west moulding
  machine carries a hopper. Four roof columns give the hall its rhythm.
- *Purposeful margins.* The east bay holds a casting conveyor through an
  annealing hood and coil stacks; the west bay a press and annealing pots; the
  freight floor ingot racks; the ladle floor slag pots.
- *Process and atmosphere.* The works is dark: a low warm floor, short
  neutral work lamps and amber process light pooled at the crucible, the
  furnace hearth, the annealing pot, the slag pots, the conveyor hood and the
  pour, with sparks at the crucible, pour and moulds. An overhead crane
  carries a teeming ladle over a new mould casting line in the formerly empty
  floor. Walls are ribbed steel under a dark grated roof deck, and gallery
  guards are a steel handrail with an open gap below it; kick plates and
  posts are fittings. Process light is amber, never Union red, and the actor
  fill keeps Union bodies readable in the shade. The service corridor carries
  the town's armoured water main to the ring's protected feed.
- *Route evidence.* The QA route fights the freight counterattack's ground
  defenders before the isolated Assessor; fighting only the hovering Assessor
  while five ground defenders closed killed the scripted player on main. The
  relay check failed when its one-frame shot never reached a server tick: the
  server reads fire as held state each tick, so the client now holds a fire
  tap until an Ack shows a tick consumed it (at most 150 ms). That also keeps
  a player's quick click from vanishing between ticks.

**Still open.** Fresh-player pacing and whether players find and use the
stair flank; bot and encounter tuning against the new cover and open
railings; the lathe headstocks still read as dark boxes from some angles; a
Standard-difficulty scripted route; the navigation build budget is close to
its limit, so further solids need measuring first; the full golden-slice
verdict.
