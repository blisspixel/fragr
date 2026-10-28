# Level 4: Notice to Vacate

**Appearance anchor for level 4:** Late-afternoon Low Water: homes, patched repair stalls, a calm clinic, shared table, drainage and tanks; packing and fighting share the same familiar district.
Shared [world direction](../design/earth.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** full mission acceptance in flight, accepted 2026-09-25. The
[playable prototype](../plans/m04-notice-to-vacate-prototype.md) is implemented
locally on 2026-09-30 with a verified ordinary-input clear. Fresh-player pacing,
runner and difficulty acceptance remain open. The market, clinic and court follow Scheduled Service in the
[twenty-level expansion](../plans/campaign-expansion.md). The old combined
district brief is historical. [Story arc](story-arc.md).

The golden-slice pass (wave 14) dresses the built route through
`client/scripts/m04_dressing.gd` toward the Recall Notice bar, without words
and without a single new body: every piece is flush paint or relief on a
registered face, a possession on an existing top or in a wall's own clearance,
or an overhead run, and the server's solids are unchanged. `ArenaSky.notice_to_vacate()`
gives the level its own late afternoon: a low warm sun from the south-west
throws long shadows across the square and leaves the court and the clinic side
of the market in cool shade, with a faint actor fill so black-and-red guards
read in it; the shared Low Water sky is unchanged. The four boundary walls
become rows of homes over shops in Low Water's plaster colours, shutters
pulled down for leaving, some windows boarded, washing and pots on the
balconies, and a tram portal where the rails leave the district. Setts replace
the poured slab across the square and market, the tram street is dark asphalt
with its rails, and the court is swept terracotta with a child's chalk squares.
Belongings wait on the tram stop seat and at the top of the roof stair; the
four stalls (noodles, radios, cloth, greens) are half packed into their own
crates under their lamps and festoon lights, the cover boxes and the awning
treads are stacked crates, and the repair bench has a tool board and a work
lamp. The notice board's back carries the neighbours' own pinned papers. The
clinic is bright and clean under four pendants: bone plaster over a sage dado,
a cork care board with a card per patient, curtains drawn back, IV stands,
shelves, the patients' drawings over the counter and Edda's satchels packed to
move; outside it has its own sage render, lit windows, a lamp over the shutter
and a painted hand holding a sprout. The tram wears its old terracotta and
cream with three test colours and the green already started; the workshop is
clad steel with a gantry crane on its roof as the street's landmark. The court
gets doors on every home, washing high over the yard, stools under the meal
table and a black Union field printer as the only Union object in it.
The tram's vote sign shows the open motion (`WORLD_M04_TRAM_MOTION`) until the
server's completed list carries `market_wave_a_cleared`, then the result;
`M04Town` keys it to that existing objective fact and decides nothing, and a
fresh attempt reopens the motion.
`client/qa/m04-golden.json` frames every beat and `m04-golden-guards.json` the
notice-board guards against the dressed square. Readable signs stay at six
(notice, clinic sign, water tank, tram vote, workshop, roof control), all
diegetic. Still open: the patient figures are borrowed player strips, the
Notary photograph in the printer tray, neighbours in the square, the stall
benches seen from behind, fresh-player pacing and GPU performance.

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| I Recall | Low Water: repair market, clinic, habitation court | Notary | 11 min | 4:30 | 1 |

**Premise.** Home, for an hour. Mara's warning went out, so Low Water knows.
Nobody agrees what to take. Neighbours argue over charging cables and whether
the tram should be painted before it is abandoned. Edda keeps the clinic open.
The coalition next door is still debating whether to send its trucks. Then the
Union's drones arrive over the awnings, and the sweep follows the photographs.

**Hook.** Defend the market you grew up in from the thing in the sky that is
taking your picture.

**Teaches.** The Notary, the first flying drone you can shoot. After the fight
at the notice board, one Notary drifts over the empty square alone: fan hum
first (captioned), then its shadow on the awnings, then the dim red optic. When
it sees you, the optic flares wide and bright and the shutter clicks; strafe
through the flash, or shoot it during the flash to spoil the shot. It hangs at
two storeys, never overhead, and the Rifle, Pistol and Shotgun all reach it.
It tumbles and crashes where its shadow was.

**Shape.**
1. **Arrival.** The tram stop at the market's edge, late afternoon light. A
   minute of home, not empty walking: people packing, the charging-cable
   argument, a vote on tram paint by raised hands, Edda's clinic sign over it
   all. You walk to the market board because everyone else is walking to it.
2. **First fight.** A Clerk pastes the notice to vacate on the board, two
   Sweepers behind her. The neighbours scatter. You do not.
3. **Escalation.** The first Notary alone, then the sweep's first wave: two
   Notaries over the stalls and Sweepers pushing in from the tram street.
4. **Breath.** The clinic. Edda needs the approach clear to move her patients;
   the shutter is the level's one door, its switch beside it. Inside it is
   bright and calm and full of people who cannot run.
5. **Set piece.** The market hold. Stalls are cover islands with a loop around
   them, the repair benches are the resupply, and the sweep comes from three
   sides: six Sweepers, three Clerks calling orders, two Notaries above, in two
   waves. Pushing forward through the stalls is safer than hiding under them.
6. **Turn.** Mara on the channel: the trucks are still being argued over. The
   market you were defending becomes the place you are leaving. New verb:
   "Get everyone up."
7. **Climax.** The habitation court: balconies on three sides, two Clerks and
   a Notary pair above, Sweepers in the yard, the roof stair on the far side.
   Clear it and the neighbours flow up the stair on their own.
8. **Exit.** The roof stair, into level 5.

**Landmarks and sightlines.** Edda's lit clinic sign over the market. The water
tanks on the roofs, seen from the square, where level 5 goes and level 19
returns. The tram workshop's gantry crane at the end of the street.

**Doors.** One: the clinic shutter, switch beside it and in view.

**Secrets.**
- The tram-paint locker, a six painted on it in three competing colours:
  spare Shells.
- A six on a noodle stall's awning pole: jump the awnings to a roof pocket with
  armor above the square.
- Under the court's shared meal table, the six carved into a leg: a medkit.
  Remember the table; it comes back in level 19 and in the epilogue.

**Brief.** Assisted: get Edda's team out. Standard adds: clear the habitation
court's balconies. Severe adds: no Notary completes a photograph.

**Par and the runner's line.** 4:30. Through the court early and over the
awnings, skipping the market's south stalls, which also skips the clinic.

**Story in play.** Page in: "Low Water. The same afternoon. Mara's warning got
through; the sweep is coming anyway, and the neighbours' trucks are still being
voted on. Home has an hour. Get people moving." Neighbour barks are ordinary
and overlapping, then short and scared. The notice on the board carries a
countersignature players will see again (**proposal**, the signature). On a
Union field printer in the court, the Notaries' photographs come out one by
one, and one of them is you, blurred mid-strafe (a stretch goal: a real frame
from the drone's view).

**Humor.** The tram paint vote carries mid-sweep. A neighbour announces it
through the gunfire: "Motion carried. Green." The notice reads *Vacate by
16:00. Belongings may be declared at intake.*

**The moment.** Finding your own photograph in the printer tray, filed.
