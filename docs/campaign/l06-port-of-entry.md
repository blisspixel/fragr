# Level 6: Port of Entry

**Appearance anchor for level 6:** Lunar cargo entry: pale dust, dark basalt, worn pressure shells and controlled thresholds; practical interior light balances exposed shade.
Shared [world direction](../design/moon.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** proposed, unbuilt. Moon before the wipe. Target 8-12 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#level-6-port-of-entry).

## Story and cast

A text transition acknowledges travel time and changing conditions on Earth.
Tern brings the party to a controlled lunar port. Latch needs a route to the
custody depot; Mara coordinates with local contacts without becoming omniscient.
The port serves established communities. Workers and families are visible through
safe glass, with ordinary schedules and possessions alongside Union restrictions.

The objective is getting in, not conquering the whole Moon. Tern remains with the
transport; Latch assists only through spaces the player actually clears.

## Route and place

Dock service bay -> freight hall -> customs split -> shielded crater cut ->
archive entrance. Customs has an interior maintenance bypass; the crater cut loops
back above the freight hall for a useful overview and resupply.

The port is open cargo floor, galleries and stairs; no airlock cycling or
pressure puzzles. Pressure glass and bulkheads are scenery, not doors to open.

| Space | Shape and purpose | Fight or story beat |
|---|---|---|
| Dock bay | Thick pressure bulkhead, cargo bay, crew facilities | Safe arrival and explanation of the next link |
| Freight hall | Cargo lanes broken by tall handling structures | Sweeper/human pairs, lateral movement and a short flank |
| Customs split | Two galleries overlooking a central inspection desk | First deliberate Railgun lane; ordinary weapons use the service bypass |
| Service branch | Pipes and broad maintenance stair | Optional fight that marks a prisoner route for M05 |
| Crater cut | Short exterior protected by berms and structural shielding | Elite Enforcer introduced with room to dodge, clear environmental protection |
| Archive entrance | A lower freight approach and an upper administrative deck | Reconverging routes, one shared mission exit |

Earth is a landmark, not the whole backdrop. Show dust control, seals, pressure
glass and buried habitation. Combat does not require a spaceflight system or
unimplemented low gravity. Any later movement variant needs explicit tests.

## Encounters and equipment

Guarantee the Railgun before the customs lane and enough Cells to learn it. The Rifle
and Shotgun retain roles along cargo and service routes. The Sniper Rifle is
found on the crater cut, after that Railgun lesson, with a few shots to learn a
slower scoped hit. Customs can be cleared without it. Enforcer commitment
and recovery are visible; the first charge never starts offscreen beside a spawn.
The Turret is introduced here. Turrets protect positions the player can flank, not every long sightline.

Secrets: pressure-maintenance cache and an upper cargo overlook with armor. The
optional service-branch fight marks a prisoner route that helps in M05; missing
it locks nothing away.

## State and scenes

`port_entered` -> `customs_cleared` -> `depot_entered`, by fighting and arriving.
Optional `prisoner_route_marked`. A continue restarts at the dock with entry state.

Mastery hooks, planned, not built: a par time on the result, the customs
maintenance bypass as the runner's line, and best clear time in the service record.
Body choice does not exempt agents from environmental limits while humans die;
equipment and shared rules determine exposure protection.

Opening uses a short arrival panel or restrained in-engine view, with text
establishing location and elapsed time. No lore lecture on lunar colonization.
Humor: a port declaration requires reporting how much Earth dust one imported.

## Allies and acceptance

Test both approach routes, rail-free completion, autonomous allies,
mission-start retry and spectator view changes.
Verify that the archive entrance and the port's inhabited purpose are readable.

## Level 6 design (twenty-level expansion)

**Status:** planned, accepted 2026-09-25. In the
[twenty-level expansion](../plans/campaign-expansion.md) this mission splits:
the dock, freight hall and customs become level 6, and the lunar town and
crater cut become [level 7](l07-declared-goods.md). The Railgun and Turret
stay here; the Sniper Rifle and Enforcer move out. [Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| II Custody | Lunar port: dock bay, freight hall, customs | Railgun; Turret | 11 min | 4:30 | 1 |

**Premise.** Three days out, Tern brings the ship in on an honest flight plan,
and the port declares it impounded before the engines cool. Tern sets the
party down through the cargo lock before customs boards; Tern and the
passengers stay with the ship. The Moon is a lived-in place with families
behind safe glass and a Union that owns every arrival. Get through customs
without surrendering anyone.

**Hook.** Step out of the dock bay into the quiet of the Moon with Earth over
the gantry, then take customs apart with a Railgun down its own inspection
lane.

**Teaches.** The Railgun, then the Turret. The Railgun sits in the freight
hall's confiscation cage, tagged for destruction, with ten Cells beside it.
Beyond the cage runs one long cargo lane with a single Sweeper patrolling its
far end, sixty metres away and unaware: one shot, one kill, the rail beam
hanging in the air. The Turret waits on the customs gallery: its head sweeps a
readable arc, it tracks, it charges red for over a second, then fires one rail
shot. Break sight to cancel the charge, and flank behind the sweep.

**Shape.**
1. **Arrival.** The dock bay, then the pressure bulkhead, already open. The
   freight hall's long window: Earth above the gantry, cargo cranes, and
   quiet. This is the level's Unreal moment; give it ten seconds of nothing.
2. **First fight.** The freight hall's cargo lanes: Sweeper and Clerk pairs
   among tall handling structures, a short flank behind the stacks.
3. **Escalation.** The Railgun lesson, then a Heavy Sweeper through the
   hall's loading gate, the first time a known heavy returns in a new place.
4. **Breath.** The service branch: family quarters behind pressure glass, a
   child's drawing of Earth taped to the inside. Optional fight here marks a
   prisoner route into level 8.
5. **Set piece.** Customs: two galleries over a central inspection desk, a
   deliberate long lane across it, and the Turret on the flankable gallery.
   Four Clerks at the desks, three Sweepers in the queue lanes, one Turret.
6. **Turn.** Through the customs glass, a tug drags Tern's ship past toward
   the impound berth, Tern at the cockpit window lifting one hand. Beyond it,
   across the crater, the custody depot's radial tower.
7. **Climax.** The customs exit crest: a second Turret over the exit hall,
   Clerks behind the declaration booths, a Heavy Sweeper coming through the
   inspection gate.
8. **Exit.** The transit tunnel toward the lunar town.

**Landmarks and sightlines.** Earth over the freight gantry. The depot tower
through the customs glass, which is level 8. Tern's ship in the impound
cradle, which is level 9. The level shows you the rest of the episode.

**Doors.** One: the dock pressure bulkhead, open on arrival and never closing.

**Secrets.**
- The pressure-maintenance cache, a six stenciled small on a valve wheel:
  armor and Cells.
- The upper cargo overlook, reached by the crane walkway: armor and a Railgun
  angle into customs.
- The duty-free kiosk of *tax-exempt compliance goods*, a six scratched on its
  shutter: Shells and a medkit.

**Brief.** Assisted: clear the service branch (marks a prisoner route for
level 8). Standard adds: kill the Turret from behind its sweep. Severe adds:
clear customs without the maintenance bypass.

**Par and the runner's line.** 4:30. Crane walkway over the freight hall,
maintenance bypass around customs, gallery rail to the exit.

**Story in play.** Page in: "The Moon, three days out. The port declared
Tern's ship impounded before the engines were cold. Tern put us out through
the cargo lock and stayed with the passengers. Our neighbours are across the
crater. Get through customs." Voss's welcome loop plays on the customs
screens, warm and entirely in English. Tern, on a short-range channel, once:
"They're very polite. I hate it."

**Humor.** The declaration form asks how much Earth dust you imported, in
grams. The customs PA: "Welcome to the Moon. You are being processed."

**The moment.** Tern's wave through the customs glass as the tug drags the
ship away, and then the Turret waking up.

## Golden-slice dressing (wave 14)

`client/scripts/m06_dressing.gd` raises the built route toward the Recall
Notice bar without a new body: every piece is a wall fitting, flush paint, a
small possession against a wall or on a top, an overhead run or scenery outside
the shell, and the server's solids are unchanged. `M06Dressing.restyle` gives
each solid view a surface by use. The pressure shell is bone-grey with dark
seams and one faded ochre band; ceilings are dark ribbed steel; the bulkhead,
confiscation cage and gallery stairs are issued dark steel with plates one step
lighter. The freight lanes, which read as Union black with glowing red stripes
behind every guard, are now rows of separate containers in practical, varied,
mid-value paint, so a black-and-red guard stands out against them. No solid's
paint emits light, so red stays the Union attack tell and nothing glows cyan.
The pressure glass is neutral rather than blue, and the floor is laid in tiles
so each keeps its own lights in the Compatibility renderer. Outside the glass a
lit lunar apron of pale dust and dark basalt carries containers, a container on
the gantry's cable, pad lights, rock and the tug's tow tracks to the impound
cradle. `ArenaSky.port_of_entry()` lowers the ambient floor and the key so the
hard light stays outside and the halls are shaped by high-bay pools, warm work
lamps and the actor fill.

The story is told in objects. In the dock the crew's own pressure suits hang
by the ship-side cargo lock, each patched in its owner's colour, over a dust
trap with grey dust tracked in across the sill; the crew lockers carry
stickers. The freight hall has a gantry crane on runway rails with its hook
block over the south aisle, painted handling lanes and wheel-worn dust. The
confiscation cage has a mesh roof and mesh on its lane walls, and keeps a case,
a duffel, a guitar case and a stack of hand-painted body panels, each with a
small red destruction tag, under one hard light on the Railgun. The loading bay
has its outer roller door stopped short of the floor with light and dust under
it. The service corridor has pipe runs and a valve wheel, and the family room
keeps planters by the glass. Customs has painted queue lanes and stand-here
marks, hard pools over the desks with stamped forms, stamps, desk lamps and
trays of confiscated personal things, two tall black banners with an original
red seal high on the north wall, and the Chancellor's welcome loop on two
hanging screens: a pixel picture of the podium, banners and a crowd's raised
hands, with no words. The duty-free kiosk shelves rows of identical grey
compliance goods with the same small red seal, above its scratched six. The
transit end wall shows a dark tunnel mouth with receding lamps.

**Signs.** Six readable signs, each placed once: the dust declaration form
(`EARTH DUST: ___ GRAMS`), `CONFISCATED` on the cage, `FREIGHT HALL` under the
Earth window (shortened from a six-word handling instruction), `IMPOUND` and
`CUSTODY DEPOT` at the customs glass, and `TRANSIT / LUNAR TOWN` at the exit.
The three secret sixes are the circled-six mark, not words; the declaration
and scale screens are pictograms. The dressing adds no words.

`client/qa/m06-golden.json` frames every beat on the route from a spectator
camera; `m06-golden-guards.json` frames the four freight guards, the only
guards placed before their encounter wakes, against the freight paint. Later
groups and both Turrets appear only through the combat route in
`client/qa/m06_port_of_entry.json`. Still open: the tug, Tern's
wave and the ship's provisional box hull; the window gantry and depot tower,
which are plain shared backdrop boxes; the Voss welcome loop's voice and motion;
fresh-player pacing and GPU performance.

## Combat readability in the dressed hall (wave 16)

`client/qa/m06_combat_review.gd` runs the ordinary-input route above
(`FRAGR_QA_SCRIPT=res://qa/m06_combat_review.gd` with `tools/qa_tour.sh`) and,
from the player's own view, photographs each Turret and Heavy Sweeper at rest
and past 80 percent of its windup, and every Railgun beam at three ages, each
with a pixel-scale crop. Observations only; the route and its gates are the
tour's. On seed 42 the whole route passed to the transit departure.

- **Turret body.** Both Turrets read as a dark issued mass against the bone
  customs walls; against the dark ceiling the one-texel rim and the optic carry
  the head. Seen from behind on the gallery at arm's length the back plates
  read dark slate, one step above the body, as the livery asks.
- **Optics at the top of a windup.** The Turret and Heavy sheets paint their
  lamps about three times brighter than the issued optic, so a driven tell
  clipped red and kept raising green: the Turret's charge read salmon (about
  `#DB7969` in the hall). For those two sheets only (`EnemyView.BRIGHT_LAMP_KINDS`),
  `union_sprite.gdshader` now holds each lamp to the issued optic's level in its
  own hue and swells it with a deeper red; the same charge reads `#D8241F`.
  Every other Union sheet keeps its light as painted: in the tell lineup the
  Clerk, Enforcer, Sweeper, Auditor and Redactor are pixel-identical to `main`
  at rest and through the tell.
- **Railgun.** The beam's near-white core and pale cyan edge read against the
  bone walls, the dark ceiling and the containers, from the player's gun and
  from a Turret's near miss; its spiral is visible to its fade. A beam stays
  where it was fired, so a strafing shooter sees its start drift off the held
  gun; that is the world-space trail, not a registration fault.
- **Heavy Sweeper.** The loading and exit Heavies read black with red lamps
  against the bone walls in both halls.

The free local agent (`fragr-brain play --provider local`, seed 42, Standard)
cleared every group and departed in about 85 seconds with full observations;
that is authoring evidence. `fragr-playtest --campaign-survey` has no Level 6
scenario, so there is no limited-perception survey of this level yet.
