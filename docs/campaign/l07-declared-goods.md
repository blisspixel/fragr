# Level 7: Declared Goods

**Appearance anchor for level 7:** A lived lunar town under curfew, with habitation frontage and service paths framed by crater cuts.
Shared [world direction](../design/moon.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** accepted 2026-09-25; a playable development mission on main
(map 1007, `server/maps/m07_declared_goods.json`), dressed toward the golden
slice in wave 15 (below). Fresh-player acceptance is open. The second half of
[M04](l06-port-of-entry.md) in the
[twenty-level expansion](../plans/campaign-expansion.md): the lunar town and
the crater cut. [Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| II Custody | Buried habitation ring and the shielded crater cut | Sniper Rifle; Ranged Sweeper | 10 min | 4:00 | 0 |

**Premise.** The lunar town beside the port lives under curfew. Its people
work the depot's supply lines and know exactly what the depot does; the depot
registers people like them as declared goods. They will not fight, because
their families are on the register, but they will show you the way. Across the
town lies the crater cut, and at the end of it the depot where our neighbours
are held.

**Hook.** Walk a silent curfew street that lights up behind you, then win a
long-range duel across a crater.

**Teaches.** The Sniper Rifle, then the Ranged Sweeper. The Sniper Rifle
hangs in the rack of the curfew post in the town square, fed by Cells like the
Railgun, slower, tighter, with a scope. From the post's roof window you can see
across the cut to the depot rim, where a single Ranged Sweeper stands on a
platform: a distinct antenna silhouette, and a precision rifle it stops to
line up. It glints, holds, then fires. The window has a sill to drop behind.
Duck its shot, rise, and take it first.

**Shape.**
1. **Arrival.** The transit tunnel opens into the habitation ring, a curved
   street under a pressure dome. Shutters down. A curfew chime every thirty
   seconds. Every window dark.
2. **First fight.** A curfew patrol walking the ring: three Clerks, two
   Sweepers, close to middle distance around market stalls and stair wells.
3. **Escalation.** The market vault plaza under the dome: two Notaries on
   patrol at dome height and Clerks behind the vault's barriers.
4. **Breath.** A woman at a window taps the glass and points down a side
   street. Nobody speaks.
5. **Set piece.** The curfew post in the square: a small fortified office,
   four Clerks, a Turret over its gate. Clear it and, one by one, the town's
   lamps come on down the street toward the cut, lighting the route. Nobody
   comes out. They have shown you the way.
6. **Turn.** The Sniper Rifle lesson from the roof window, then the climb out
   of the town: at the top of the stair you stand above the port you fought
   through and can see the whole route behind you.
7. **Climax.** The crater cut. A bounded long-range duel against five Ranged
   Sweepers on the depot's rim platforms, while Sweepers advance up the cut
   between berms and radiation shielding. Close, and the Sweepers are a
   Shotgun problem; stay back, and the rim is a Sniper problem.
8. **Exit.** The depot's freight approach, into level 8.

**Landmarks and sightlines.** The depot's radial tower across the crater,
never out of sight once you leave the tunnel. The port behind and below from
the cut's top. The lamp line through the town, which is the route.

**Doors.** None.

**Secrets.**
- A family's hidden tool cache above the market vault, reached from a stall
  roof, the six painted inside a lamp shade: Cells and armor.
- The Floating 67 mark of Episode II: a child's chalk 67 on a dead-end alley
  wall under the curfew notice, with the mark behind a loose panel.
- A berm-top ledge in the cut, a readable jump from the second shield wall, a
  six on its marker post: Cells and a flank on the rim.

**Brief.** Assisted: clear the curfew post in the square. Standard adds: cross
the cut without losing armor. Severe adds: kill every rim Ranged Sweeper before
it fires.

**Par and the runner's line.** 4:00. Over the vault roofs, skipping the square
and its lamp moment, then the berm-top ledge across the cut.

**Story in play.** Page in: "The lunar town beside the port. Same shift. The
people here live under curfew; the depot across the crater registers people
like them as declared goods. Our neighbours are in there. Cross the town, then
the cut." Latch, as the lamps come on: "They're not joining. They're doing
this." Nobody in the town speaks a line.

**Humor.** The curfew PA: "Curfew is provided for your rest. Rest is
mandatory." A shop sign: *Closed by order. Open by appointment. Appointments
suspended.*

**The moment.** The lamps coming on down the curfew street, one window at a
time, after you clear the square.

## Golden-slice dressing (wave 15)

`client/scripts/m07_dressing.gd` raises the built route toward the Recall
Notice bar the way the port's dressing does, and reuses its helpers: every
piece is frontage, flush paint, a small possession against a wall or on a top,
a line overhead, scenery outside the playable square or practical light, and
the server's solids are unchanged. `M07Town` builds it with the rest of the
town, so a re-sent map rebuilds one dressed town. Its layout guard keys on
walls that never move (the town wall, the market vault, the post's rack and
window sill, both cut walls, the rim and the depot deck).

The town has its own face, not the port's. `M07Dressing.restyle_town` paints
each habitation block in its own faded colour (sage, terracotta, blue-grey,
ochre, lilac grey), all mid values so a black-and-red guard reads against any
of them; the curfew post and depot are issued steel one step lighter than a
Union body; the market vault is old riveted steel; the cut is grey regolith,
compacted berms, dark basalt walls and galvanised radiation shields with ochre
edges. The `service_steel` that painted the post, the shields and the ramp in
Union black with glowing red stripes is gone; no solid's paint emits light. The
town floor is paved in tiles and lunar ground surrounds the walls.
`ArenaSky.moon_town()` puts a low sun behind the town wall, so the streets lie
in long shade under the dome and the only hard light inside is the Union's:
cold curfew floods on brackets and the post's pools. Out in the cut the same
sun is hard light on dust, with a jagged crater rim beyond both walls and the
rim, and the port's side dropping low under Earth.

The story is told in objects. Every street face carries doors in household
colours, each with the same small red registration seal, a mat, a pot, boots or
a crate at the threshold and a dark lamp over it; dark windows with curtains
and window boxes; conduits, downpipes and a cornice; water tanks, vents and
masts on the roofs. Washing hangs over the ring street. The stalls are covered
for the night under roped tarps. The market's strongroom door is sealed by
order with a red strip and a tag, and the Union's barriers carry hazard paint.
Beside the lit window a neighbour keeps planters and a bicycle wheel; in the
dead-end alley a chalk hopscotch, a ball, a chalk sun and a row of figures
holding hands sit under the curfew notice and the 67. The square's planters
hold dry stalks. The post's face to the square has two tall black banners with
the original red seal, cold floods at its corners and painted stand-here marks
before the gate. Inside, the register: a wall of household cards, each a small
square portrait and a red stamp, over filing cabinets and a wall desk of forms
and stamps; the confiscated long arms lean tagged at the rack's ends beside a
crate of seized tools; upstairs a cot and a flask by the firing step. In the cut
the shields have hazard feet and ribs with dust drifted against them, a power
cable runs down the west wall and hauler tracks cross the floor. Each Ranged
Sweeper position on the rim is a lit stage: a deck plate, a rail behind, a cold
spot from a mast and a mid-grey blast screen behind the body, so the black
marksman and its glint read through the scope across the cut. The depot's
intake door is shut under chevrons between two sealed banners.

**Signs.** Seven readable signs, all placed before this wave: `CLOSED BY
ORDER` twice, `CURFEW / REMAIN INDOORS` three times (two kiosks and the alley),
`CONFISCATED` on the Sniper Rifle rack, and `FREIGHT INTAKE / DECLARED GOODS`
on the depot panel. The transit and port overlook plates are hidden; the chalk
67 and the two sixes are marks, not words. The dressing adds no words.

`client/qa/m07-golden.json` frames every beat on the route from a spectator
camera; `m07-golden-guards.json` frames the curfew patrol, the only guards
placed before their encounter wakes, against the frontage. The later groups,
the gate Turret and every Ranged Sweeper appear only through the combat route
in `client/qa/m07_declared_goods.json`, which still runs end to end to the
freight departure with the dressing in place. Still open: the crater rim is
flat-shaded ridge geometry rather than sculpted rock; the depot tower, dome and
port are plain shared backdrop shapes; the lamp line's moment needs a motion
capture judged against the dark street; the frontage repeats one door and
window kit; fresh-player pacing and GPU performance.
