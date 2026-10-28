# Level 3: Scheduled Service

**Appearance anchor for level 3:** Daylight rail logistics: cars, signal box and visible jamming mast; parallel working lanes make rescue and escape readable.
Shared [world direction](../design/earth.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** planned, accepted 2026-09-25, unbuilt. A new level in the
[twenty-level expansion](../plans/campaign-expansion.md); no ten-mission
counterpart. [Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| I Recall | Recall freight yard, the Perimeter's old rail | Jammer | 10 min | 4:00 | 0 |

**Golden-slice pass (wave 14).** `client/scripts/m03_dressing.gd` dresses the
built yard (`server/maps/m03-scheduled-service.json`) toward the Recall Notice
bar without words and without a single new body: every piece is flush paint,
ballast or sleepers, a face on an existing solid, a possession on an existing
top, an overhead run or scenery outside the play square, and the server's
solids are unchanged. The generic venue wall gives way to the yard's own: the
correction complex closes the south side in the same bone enamel and green band
as the ward, with Level 2's roller shutter stopped short of the floor behind the
arrival; precast panels with wire and unlit floodlight masts run east and west;
and a closed barred gate across both lines in the north shows the track running
on past open country to Low Water as a smudge on the horizon. Both lines get a
ballast bed, sleepers, tie plates, polished rail heads, platform coping and
ochre safety lines over a weathered cast-concrete slab. The six cars are issued
recall stock in green-grey with ribs, doors with a small red seal, bar-only
number plates, bogies, couplers, corrugated ends and roof walkways; the open
bays have plank floors, a restraint rail and one cold caged lamp. A bone
processing lane runs from the dock door into the first car's bay, and the three
cover crates are baggage carts carrying tagged bags in personal colours. The
departures board gains a frame, canopy, clock and a back of blank flaps. The
dispatcher's office has a roof, windows, a desk with timetable, telephone,
stamp and lamp, manifests on clipboards and a key board. The brakemen clad their
own hut in faded blue weatherboards with a timber lining: a kettle on a black
iron stove with embers and a circled six on its door, mugs and a hand of cards
on the table, coats on hooks and a brake wheel on the wall. The mast is a red
and bone banded lattice over the column, with two jamming dishes, a whip and a
beacon, so it reads from every point; when the server reports the shutdown it
is rebuilt as a lattice lying on the fallen column and pod. The signal box is
the platform's north end, with framed windows over a lever frame and a circled
six on the back steps; the gantry gets a hoist beam, trolley and hook above head
height; the locomotive gets engine-room grilles, three-axle bogies, handrails,
warm cab windows, headlamps and a chevroned buffer beam. The last car carries
the chalk 67 and a tally. `ArenaSky.freight_yard()` lowers the western sun so
the consist's shadows cross the lanes and adds the actor fill, and the
`earth_yard` materials lose their red paint (worn ochre, nothing emits), so red
stays on the Union's guards and the mast alone. Readable signs: six placements
(the schedule board, three TRANSFER stencils, the mast plate and the boarding
panel). `client/qa/m03-golden.json` frames every beat and
`m03-golden-guards.json` the loading crew against the dressed platform.
Still open: the fallen mast has a structural test (`test_m03_dressing.gd`) but
no inspected capture, because `m03-scheduled-service.json` stops at the roof
car, where its waypoint lies between the two freed captives (this also fails on
the wave 13 baseline); the brakemen's painted line and the 66/67 board listing;
the yard PA voice; fresh-player pacing and GPU performance.

**Premise.** The correction complex has its own rail spur, and a recall train
is marshalling on it for Low Water. A red mast over the yard jams every free
channel, so Mara cannot warn anyone. The only road home is the freight line.
The objective is the mast. The sealed cars are Latch's choice: they open each
one as soon as you clear its stretch, and you do not argue, because you have
seen the ward.

**Hook.** A daylight train yard, two lanes of track and a jamming mast to topple
while your friend opens every car you pass.

**Teaches.** The Jammer. The first one stands alone on a service platform one
track away, antenna folded. As you step onto the ballast its dish spreads and
glows, and a slow, bright interference ball crosses the tracks toward you,
visible the whole way. Sidestep it, then cross behind the coupled cars to reach
its exposed flank. It dies to the Rifle. After that, a Jammer is a priority
target that makes every other fight worse while it lives, never a circuit
puzzle.

**Shape.**
1. **Arrival.** The dock door from level 2 opens onto the yard in bright
   afternoon. The mast stands red over everything; the schedule board clacks
   through departures, one of them *RECALL, LOW WATER, ON TIME*. Latch: "Mara
   can't hear us. That mast."
2. **First fight.** Platform one: two Clerks and two Sweepers loading the first
   car. Clear them and Latch pulls the door. People climb out and walk to the
   yard office on their own.
3. **Escalation.** The first Jammer across the tracks, then a second on a car
   roof with three Sweepers below it. The two parallel lanes cross over the car
   roofs by ladders and under them between couplings; every crossover is a
   flank.
4. **Breath.** The brakemen's hut beside the points: a kettle still warm, a
   six on the stove door, the Brakemen's line painted over the window. Latch
   asks you what happened the morning they were taken; they do not remember it
   (**proposal**, see [story arc](story-arc.md#latchs-missing-morning-proposal)).
5. **Set piece.** The mast crest. A Jammer on the mast platform throws
   interference across both lanes while Sweepers hold the signal box beneath.
   The mast's transmitter pod glows red at the top, big and obvious. Kill the
   Jammer and shoot the pod off, and the mast leans, groans and falls across the
   tracks onto the signal box roof.
6. **Turn.** Every free channel opens at once. Mara's voice, ragged: "Low
   Water, this is Mara. Go now." The warning is out. The freed cars are
   already coupled; the recall train is now your train home.
7. **Climax.** Platform two to the locomotive: a last Union push from the yard
   office side, two Clerks, four Sweepers and a third Jammer on the gantry.
8. **Exit.** Board the locomotive. The train rolls out through the yard gate.
   The schedule board flips every departure to *CANCELLED*.

**Landmarks and sightlines.** The red mast, visible from every point, is also
the objective. The schedule board faces the platforms and reads without
English: every line turns from white to red when it cancels. The yard gate at
the far end shows open country and, on the horizon, a smudge that is Low Water.

**Doors.** None. Car doors are Latch's to open and never gate the route.

**Secrets.**
- A circled six on the brake wheel under the fourth car: armor and Shells.
- The one Floating 67 mark of Episode I: a car stenciled 67 at the end of a
  consist whose board lists 66. Inside, a chalk tally and the mark.
- A six on the signal box's back ladder: its roof, reached from a car roof by
  a readable jump, holds Bullets and a sightline over the mast crest.

**Brief.** Assisted: open the first car. Standard adds: open every car,
including the two on the side siding. Severe adds: kill the mast Jammer before
it fires a second pulse.

**Par and the runner's line.** 4:00. Up the first ladder and along the car
roofs of lane two, dropping only for the mast crest. It skips platform one's
cars, which is why the runner's line and a full Standard brief pull against
each other.

**Story in play.** Page in: "The freight yard on the complex's spur. Twenty
minutes later. A recall train is loading for Low Water, and a mast is jamming
every free channel. Mara cannot warn anyone. Take down the mast." Latch's barks
are about the cars ("Two more. Cover me."). The PA reads departures in a
cheerful recorded voice. The Inheritance's first, deniable sign: one departure
on the board that nobody scheduled, bound nowhere, on time.

**Humor.** The PA: "Recall service to Low Water departs on time. Delays are
regretted." When the mast falls: "All services cancelled. Cancellations are
regretted." Car stencils read *Persons in transfer. Keep upright.*

**The moment.** The mast coming down across the tracks onto the signal box,
and a second later Mara's voice on every channel at once.
