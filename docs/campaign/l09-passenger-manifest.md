# Level 9: Passenger Manifest

**Appearance anchor for level 9:** Lunar launch cradle and berth services; recognizable ship access makes reclaimed transport the destination.
Shared [world direction](../design/moon.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** accepted 2026-09-25; a playable development mission on main
(map 1009, `server/maps/m09_passenger_manifest.json`,
[prototype plan](../plans/m09-passenger-manifest-prototype.md)), dressed toward
the golden slice in wave 16 (below). Fresh-player and difficulty acceptance
are open. The Episode II finale in the
[twenty-level expansion](../plans/campaign-expansion.md).
[Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| II Custody | Lunar launch berth, the impound cradle | Enforcer | 10 min | 4:30 | 1 |

**Premise.** The car nobody sent stops under Tern's ship, still in its cradle,
still sealed with impound notices. Tern is held in the berth office with the
crew and the passengers from Earth, Edda and Splice among them if they were
saved. The freed people from the depot need passage, and the manifest lists
them as cargo. The Union's committed elites are coming to hold the berth.

**Hook.** Climb a spiral of catwalks around a grounded ship while armored
fanatics charge you along them, then leave with the hatch open.

**Teaches.** The Enforcer, the first committed human elite: powered black
armor, a red armband, and a charge. The first stands alone on a wide catwalk
landing outside the berth office. Its shoulders drop and its armor vents glow
red for the windup, it charges in a straight line with knockback, then stands
exposed in recovery. One side of the landing has no rail. Sidestep a charge at
the edge and it goes over. That is the lesson, and every Enforcer after this
level can be fought with the floor.

**Shape.**
1. **Arrival.** The freight car rolls into the berth's lower loading lane. The
   ship fills the view: *COMMON CARRIER* on the hull, Union seals on every
   hatch.
2. **First fight.** The loading lanes: Clerks and Sweepers among cargo, one
   Turret on the lower gantry covering the office stair.
3. **Escalation.** The Enforcer lesson on the office landing, then the berth
   office: two Clerks and the crew in restraints.
4. **Breath.** Tern freed, rubbing their wrists, already walking to the ship.
   The captives from the depot begin boarding on their own each time a level
   of the gantry is clear. Tern starts the cradle release, which takes as long
   as the climb takes.
5. **Set piece.** The spiral climb around the cradle, three gantry levels.
   Each has an Enforcer and a Sweeper pair; Notaries circle the hull at mid
   height. A long Railgun lane crosses the cradle to the control gallery.
6. **Turn.** At the top catwalk the cradle clamps begin to release. The Union
   counterattacks: two Enforcers charging along the upper catwalks at once,
   Clerks firing across the cradle from the control gallery.
7. **Climax.** The boarding hatch, the level's one door. Hold it while the
   engines light. The last Enforcer charges the hatch as the ship lifts.
8. **Exit.** The hatch closes. The ship listed as impounded leaves the Moon.

**Landmarks and sightlines.** The ship in its cradle, visible from every point,
growing as you climb. The control gallery across the cradle, the Union's high
ground. Earth through the berth roof as the doors open for launch.

**Doors.** One: the boarding hatch, the exit.

**Secrets.**
- The berth customs locker, the six scratched under its seal: armor and Cells.
- The cradle arm's maintenance cubby, a readable jump from the second gantry,
  a six on the cubby lid: Shells and two medkits.
- The impound clerk's cabinet in the control gallery, tagged *confiscated from
  vessel*, a six on the tag: three grenades and a Proximity Mine.

**Brief.** Assisted: clear the berth office and free Tern's crew. Standard
adds: stop the Enforcers before they reach the upper catwalk. Severe adds: kill
an Enforcer by baiting its charge off a catwalk.

**Par and the runner's line.** 4:30. The cradle-arm jump from the second
gantry to the fourth landing, skipping the third level's fight.

**Story in play.** Page in: "The launch berth. The car nobody sent stopped under
Tern's ship, still in its cradle, still sealed. Tern and the passengers are in
the berth office. Free Tern. Get everyone aboard." Tern's line when freed: "I'm
not a charity. I'm a common carrier. It's worse; I have to take everyone." The
page out closes Episode II: four days to Mars, and the transfer evidence under
Tern's bunk.

**Humor.** The manifest lists the passengers as *cargo (sentimental)*. The
hull notice: *This vessel is impounded. Removing this notice is an offence.*
Tern peels it off at the hatch as the ship lifts and keeps it.

**The moment.** An Enforcer charging the open hatch as the ship lifts, missing,
and carrying straight on off the gantry.

## As built

The development mission follows this shape with these differences: the arrival
lane sits under the receiving roof behind the office, so the ship is first
seen whole from the loading lane's east end and from the gantries rather than
filling the arrival view; the hatch opens by a re-sent map and the engines
light, but nothing lifts; and the cradle arm's maintenance cubby secret is not
built (the customs locker and the gallery cabinet secrets are).

## Golden-slice dressing (wave 16)

`client/scripts/m09_dressing.gd` raises the route toward the Recall Notice bar
the way the port's and the town's dressing do, and reuses their helpers: every
piece is flush paint, a fitting on a face, a small thing on a top or against a
wall, a line overhead or practical light, and the server's solids are
unchanged. Its layout guard keys on solids that never move (the west shell,
the office floor, the first gantry, the control gallery, the keel, the hatch
bridge and the boarding stack), never the boarding hatch. `M09Berth` keeps one
`M09Dressing` across the map the server re-sends when the hatch opens.

The berth has its own face, not the port's, the town's or the archive's: one
tall bone pressure hall with ribs and an ochre band, a steel roof around the
glazing with Earth and hard stars in it, and the ship in the middle.
`M09Dressing.restyle_berth` paints the Common Carrier as Tern's ship and as
the one the port already showed: gunmetal plate with darker ribs every three
metres and a dark belly, a bone pressure deck on top with a dark deckhouse and
a mast, the ember of Tern's shoulder panel as a stripe round the hull and the
nose, a framed windscreen with an instrument glow, engine bells on the
nacelles. The cradle is ochre steel with saddles, scorched plate under the
ship and a painted footprint. Gantries and stairs are grated steel a step
lighter than a Union body; the impound office is the berth's bone shell
outside and issued steel inside. Nothing on the ship is Union black and red
or matte off-white; no solid's paint emits light. The floor is deck plate in
tiles.

The story is in objects and light. Union seal tape crosses every hatch: the
crew door, the cargo door, the deck hatch and the boarding hatch's jambs, with
impound notices pasted on the plate. The passengers' bags sit tagged as cargo
on the freight, in the office where the clerk took them and at each gantry
landing as they climb. The office has a restraint rail with open shackles, a
seal banner, filing cabinets and the customs locker with a six scratched under
its seal; the gallery has the impound cabinet with its six, two banners and
cold floods trained on the hull. The freight car has bogies, a window band and
an amber destination lamp with nothing on it, under the closed freight lock it
came through. The office landing has a top rail on its three real guards and
none across the gap: torn stubs and ochre paint mark the drop. Every open
gantry edge is painted, not railed, because every one is a real drop.
`M09Berth` lights the passenger windows as the gantries are cleared, opens the
clamps and turns their lamps from amber to green when the cradle releases,
lights the engine throats for departure and drops the hatch's notice when it
opens. `ArenaSky.launch_berth()` sets a steep soft sun, warm lamps under the
gantry shelters and the Union's cold floods on the landing and the hull; the
actor fill keeps an Enforcer's black armour and red visor, armband and optics
readable from 6 metres on the landing to about 25 metres across the gallery.

**Signs.** Four readable signs: `COMMON CARRIER` on the hull's port side,
`BERTH CREW / RELEASE` and `COMMON CARRIER / DEPARTURE` on the two controls,
and `IMPOUNDED / REMOVING THIS NOTICE / IS AN OFFENCE` on the closed hatch.
The other notices are ruled paper and the two sixes are marks, not words.

`client/qa/m09-golden.json` frames every beat from a spectator camera;
`m09-golden-guards.json` frames the loading guards, clears them through the
ordinary route and frames the first Enforcer on the landing. The later
Enforcers appear through the combat route in
`client/qa/m09_passenger_manifest.json`, which runs end to end to the
departure with the dressing in place. Still open: the ship is still the
collision's boxes under its paint, with no hull curvature; the arrival view
does not show it; the roof does not open for launch; the human crew share one
body; motion review of the clamps and engines; fresh-player pacing and GPU
performance.
