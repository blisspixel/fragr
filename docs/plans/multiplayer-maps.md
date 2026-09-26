# Plan: multiplayer maps and modes

**Status:** proposed (2026-09-24). Everything below is a proposal: no map, mode,
item or mutator in this file is built unless a line says so.
**Branch:** `docs/multiplayer-map-roster` for this plan; one `feat/mp-*` branch per map or mode.
**Spend:** $0. Graybox, playtest harness and tour stills are local.

## Goal

Build multiplayer maps people ask for by name: Doom and Quake loops, GoldenEye
couch chaos, Halo's compact towers and open canyons, and later Battlefield 1942
fronts with jeeps, bikes and jetpacks. Fights and flow first. A new player gets
a frag in their first minute; a veteran is still finding faster routes and
tighter item timings a year later.

This file owns three things: the rule sheet every fragr multiplayer map is built
against, the proposed roster, and the mode order.
[MAP-DESIGN.md](../MAP-DESIGN.md) owns general level craft;
[MODES.md](../MODES.md) owns what each mode is.

## Non-goals

- Copying any classic layout, name or asset. Principles only.
- Puzzles, keys, switch hunts, or doors used as pacing.
- Per-map gravity, destructible terrain, or vehicles beyond the jeep, motorcycle
  and jetpack in [vehicles.md](vehicles.md).
- A map that exists only in this file. Each map gets its own plan when it is next.
- Changing the build order. This work sits in Phase 4 of the
  [roadmap](../ROADMAP.md), after the exposed-server rung.

## What the classics actually did

Researched 2026-09-24. Sources are listed at the end.

- **Doom II and Dwango.** MAP01 put the best guns next to the start and the
  fight in the middle corridors. Dwango's map packs were rated by veterans
  after repeated four-player sessions, and they mixed sizes on purpose, because
  newcomers liked room to breathe and experts wanted small arenas "for maximum
  conflict". Lesson: a roster needs both, and fun is measured by playing, not
  by drawing.
- **Quake DM3 and DM6.** DM3 spreads named item zones (RL, YA, Quad, Mound, RA)
  across a base big enough for teams. DM6 is a two-floor figure eight with one
  red armour, one green armour and one rocket pack; that scarcity makes
  control a skill while the small size still lets a rusher win. Romero noticed
  players turn right at a fork, and top players used that to steer opponents.
  Lesson: few big items, named places, and one clear loop.
- **Quake 3.** Armour 25 s, health 35 s, Mega 35 s, Quad 120 s with its first
  appearance about 45 s in, weapons 5 s in free-for-all and 30 s in teams (all
  from the released source). Spawns pick at random from the farthest half, so
  they are safe without being predictable. Q3DM6 wraps two high wings around a
  central pad with more than two ways to most spots; Q3DM17 floats the best
  items on exposed platforms so taking one is a public act. Lesson: fixed clocks
  turn a map into a schedule, and exposure is how an item is paid for.
- **Unreal Tournament.** Facing Worlds is two tall towers across a long open
  middle, built tall so sniping becomes the subject; its lifts became
  teleporters because bots could not use lifts. Deck16 is a vertical industrial
  deck with a power weapon above the elevator. Lesson: one gimmick per map, and
  anything bots cannot use is broken.
- **GoldenEye.** Multiplayer was a late add-on, cut from single-player levels,
  and still became the couch game of its decade. The fun came from rooms and
  corridors dense enough that four people on one screen kept colliding, and
  from rule twists: Licence to Kill (one hit kills), The Man with the Golden Gun
  (one fixed one-shot gun, kill the holder to take it), You Only Live Twice (two
  lives), flag tag (the carrier cannot shoot), and fourteen weapon sets
  including slappers only. Oddjob, shorter than everyone and so harder to hit,
  started arguments its designers later called disrespectful to players.
  Lesson: mutators are cheap content, and every fighter must present the same
  target.
- **Halo.** Blood Gulch is two bases, an open rolling field and cliff flanks,
  with the sniper on the cliffs and rockets mid-field; its hills hide a walker
  at range. Lockout, Chris Carney's smallest map, started as a 1v1 and is rooms
  joined by bridges on three levels: close fights below, room clearing across
  the bridges, tower-to-tower range on top. All vertical movement is at the
  edges, so you see where someone went but not which floor they reached.
  Carney's rules: decide the player count and modes first, give every hard
  point three or more ways in, never place a power weapon where it is ideal to
  use, and make jumps clearly makeable or clearly impossible.
- **Battlefield 1942.** Conquest bleeds tickets from whoever holds fewer flags,
  faster as the gap grows. Wake Island is a horseshoe: the front moves by force
  or by flanking up the other leg, with long shots across the water. El Alamein
  gives ground vehicles two narrow passes through a ridge; bases spawn seven
  vehicles, outposts two. Stalingrad is infantry first, two vehicles per base,
  rubble and sniper towers. Omaha is an assault that stops bleeding only when
  the bunkers fall. Lesson: flags are placed to create lanes with different
  jobs, and vehicles are flow control, not decoration.
- **General practice.** Good maps overlay two or three big loops with a few
  small ones; too many paths make a guessing map (Jim Brown's GDC talk found
  players love maps with only two or three real routes). Comfortable fights
  stay inside about 40 m so an enemy stays big on screen. Halo 3 weights spawns
  away from enemies and recent deaths.

## Rule sheet

Measure in seconds, not metres. Current movement: top speed 5 m/s, a step of
0.6 m, a jump about 1.1 m high and 3 m long. [Gunfeel](gunfeel.md) proposes 6.5
m/s; if it lands, every metre figure below scales by 1.3 and the seconds stand.
Weapon reach today: Scatter 12 m, Tack 30 m, Flechette 40 m, Rail 60 m.

### 1. Size by player count

| Tier | Players | Footprint | Farthest two points | Spawn to first contact | Main loop lap |
|---|---|---|---|---|---|
| Small | 2 to 8 | 40 to 80 m | 25 s or less | 3 to 6 s | 20 to 40 s |
| Medium | 8 to 16 | 100 to 160 m | 45 s or less | 8 to 12 s | 45 to 75 s |
| Large | 16 to 32 | 300 to 500 m | vehicles cross in 30 s | 15 s on foot to the nearest site | sites 80 to 150 m apart |

A small map that takes longer than 25 s to cross is a medium map with too few
players in it. That is the single biggest fault in the current roster.

### 2. Loops, not rooms

- Two or three big loops overlaid with a few short ones. More routes than that
  turn contact into guessing.
- Every room has at least two exits facing different ways. Every place worth
  holding has three or more ways in.
- No dead ends, except a secret with a reward and a way back.
- Nobody should need to turn 180 degrees to find the way on.

### 3. Sightline budget

| Band | Distance | Weapon | Share of floor, small map |
|---|---|---|---|
| Close | under 12 m | Scatter, fists | about 40 percent |
| Mid | 12 to 40 m | Tack, Flechette | about 45 percent |
| Long | 40 to 60 m | Rail | one to three lanes |

- On a small map nothing is longer than 60 m. A line beyond every weapon is
  dead space that only makes walking longer.
- Every long lane ends at an exposed position, so the sniper can be answered.
- On medium maps an open crossing always has cover within 10 m (two seconds).
- Lines over 60 m appear only on large maps, over open ground that vehicles
  are meant to cross.

### 4. Height

- Small maps use three levels: floor, about 3 m, about 6 m. Medium maps add a
  bridge or catwalk over the busiest space. Solids with bottoms (authored maps
  already support them) make bridges and stacked decks possible.
- Falling is fast, climbing is slow. One-way drops are good; they make routes
  predictable in a way teams can plan around.
- Every raised face shows its ramp within 10 m. Directive 17's first version
  pinned agents against a riser for forty seconds; a wall with no visible
  answer is a map bug.
- No main route needs a jump. Optional jumps are either clearly makeable (a
  flat gap of 2.5 m or less) or clearly impossible (4.5 m or more).
- Corridors at least 3 m wide, doorways at least 4 m.

### 5. Items and clocks

| Item | Respawn | Status |
|---|---|---|
| Weapon, free-for-all | 12 s | built |
| Weapon, team modes | 30 s | proposed |
| Health pad (+40) | 15 s | built |
| Armour pad (+25) | 15 s today, 25 s proposed | built |
| Heavy plate (large armour) | 35 s | proposed |
| Surplus (health over maximum, drains back) | 35 s | proposed |
| Overtime (power item: triple damage for 20 s) | 120 s, first at 45 s, announced | proposed |

- At most one power item per small map and one per side's reach on medium maps.
- The best item sits on the worst ground: exposed to a lane, to fire from
  above, or at the bottom of something. Never where it is ideal to use.
- Health sits on escape routes. Each armour is exposed to one lane.
- The Tack pad is within two seconds of every spawn
  ([every life starts empty](../MODES.md#every-life-starts-empty)).
- Two big items 30 to 50 s of walking apart, so timing both is a plan.
- Spectators see item clocks. Players learn them by ear: every big item has a
  respawn sound audible across the map.

### 6. Spawns

- At least 1.5 spawn points per maximum player.
- Pick at random from the far half, then refuse any point inside an enemy lane
  within rail reach plus two seconds of walking (the shipped
  `SPAWN_THREAT_RANGE`). Never in sight of the power item. Never facing a wall.
- Team spawns fill the back third of a side and move with control of the map,
  so holding a power room pushes the enemy's spawns away rather than onto you.
- Gate: the playtest's existing one opening spawn death per round.

### 7. Landmarks, callouts and light

- Every space is named for what it is: Pit, Bridge, Kitchen, Crane. Eight to
  fifteen callouts on a small map. The name is painted in the world through
  keyed text, and a shape makes it readable with text hidden.
- One landmark is visible from at least three spaces, so a player always knows
  which way is home.
- Each zone has its own material and light colour. Mirrored team maps mirror
  function, not paint: the Union end is black and red, the coalition end bone,
  leather and ember.
- Bright and clear. A fighter reads against every background at 30 m. Floors
  and walls stay mid-value so black Union armour and bone coalition armour both
  stand out. No dark corner hides a body.

### 8. Doors, lifts and gimmicks

- Small maps have no doors. No map has more than three, and none sits on a main
  route. An open frame is a doorway, not a door.
- One gimmick per map: a lightwell, an elevator, a pipe. Everything else serves it.
- Lifts, jump pads and teleporters are unbuilt engine work. A map that needs one
  says so and waits for it.

### 9. Humans, agents and bots

- Same rules for everyone. An agent joins through MCP, reads the same `MapInfo`,
  and plays the same seat. Rule bots fill a server up to a per-mode count and
  leave as people arrive.
- Every map ships callout regions (proposed `MapInfo` field) so agents, bots and
  the Host all say "rail's up on the Bridge" with the same words.
- Every route a map needs is proven with shared movement and navigation, not
  with a flood fill alone. Large maps also ship drive lanes.
- Lanes from [fair-play](fair-play.md) apply: a server says whether it is
  humans only, mixed or agents only.

### 10. Measured before it is called good

The harness already reports these; a map passes with, at its target count:

- first frag under 8 s on small maps, under 15 s on medium;
- at least 12 frags a minute with six fighters on a small map (Arena Duel does
  23, Compliance Yard does 3.8);
- at least 20 percent of kills in each of two distance bands;
- no more than one opening spawn death per round;
- no agent stall over 10 s.

Then humans play it. A green report is not fun; it is the right to find out.

## The six current maps

Measured frags a minute are from [map-roster-2026](map-roster-2026.md), six
agents. Crossing times are corner to corner at 5 m/s.

| Map | Extent | Crossing | Frags/min | Verdict |
|---|---|---|---|---|
| Arena Duel | 140 m | 40 s | 23.0 | **Keep, tighten** |
| Compliance Yard | 110 m | 31 s | 3.8 | **Retire**, replaced by Area Kitchen |
| Directive 17 Substation | 150 m | 42 s | 15.3 | **Rework** smaller, with a bridge |
| Sector 9 Transit Hall | 200 m | 57 s | 14.1 | **Rework** as the first team map |
| Reclamation Gulch | 280 m | 79 s | 6.4 | **Rework** smaller for team play |
| Tripoint Works | 320 m | 91 s | 9.0 | **Rework** for its mode; out of free-for-all rotation |

- **Arena Duel** works. The hub inside the gantry ring gives a middle worth
  fighting into, and it is the CI and Episode 0 map. Its faults: eight-fold
  symmetry leaves nothing to call out, and everything beyond the spawn rim is
  dead floor.
- **Compliance Yard** is nine identical rooms, eighteen doorways and a 19 m
  perimeter corridor. That is the guessing map the research warns about:
  contact is luck and nobody can say where they are.
- **Directive 17** has the best idea in the roster: the prize at the bottom of
  a bowl. At 150 m the decks are 40 m slabs of nothing, and the pit is too far
  from most of the rim to feel watched.
- **Sector 9** has named places and a measured rollout: both halls reach Mid
  Doors in about five seconds. It is too big for free-for-all and the right
  bones for teams.
- **Reclamation Gulch** crosses 180 m of open ground at 5 m/s. The rail reaches
  60 m, so most of the gulch is beyond every weapon: a walk, not a fight. Blood
  Gulch works because of vehicles, and this one has none yet.
- **Tripoint Works** is built for a three-sided mode that does not exist. As
  free-for-all it is 91 s from corner to corner.

## The roster

Twenty maps would be a list; sixteen is a roster. Seven small, six medium,
three large. Places come from [the gazetteer](../lore/gazetteer.md): league
venues for free-for-all, campaign places for team play, where the Union (black
and red) holds ground the free coalition wants back.

### Small maps: 2 to 8 players, deathmatch and duel

#### 1. Arena Duel (keep, tighten)

- **Place:** a municipal assembly floor certified for use as an arena.
- **Players and modes:** 2 to 4. Duel, deathmatch, every mutator.
- **Layout and loop:** unchanged rosette: hub, broken gantry ring, spokes. Pull
  the spawn rim from 42 m to 30 m and bring the outer walls in, taking the
  extent from 140 m to about 85 m and corner to corner under 25 s.
- **Signature:** the Dais, the north gantry, with the rail and nothing to hide behind.
- **Landmark and callouts:** give the four gantry segments four faces: Dais
  (north), Press Rail (east), Vote Board (south), Gallery (west). Hub, Spokes,
  Rim.
- **Items:** rail on the Dais; armour in the Hub; health off the Press Rail and
  Gallery; Tack beside every spawn.
- **From:** Doom II MAP01 (start fast, fight in the middle) and Q3DM17
  (the prize is a public act).

#### 2. Larak Lot (new)

- **Place:** the Perimeter's five-level parking structure, whose ramp goes one
  level further down than the sign admits.
- **Players and modes:** 4 to 8. Deathmatch.
- **Layout and loop:** a split-level car park 48 by 32 m. East and west
  half-decks sit 1.5 m apart and climb in a double helix; one full lap climbs a
  storey. Two stair towers at opposite corners are the fast way up. A lightwell
  8 m square runs through every deck. Three loops: the ramps (slow, covered by
  parked vans), the towers (fast, blind corners), the well (fastest, down only).
- **Signature:** the Lightwell. Shoot between floors, or drop five storeys onto
  the bottom deck in two seconds.
- **Landmark and callouts:** level numbers painted three metres tall on every
  deck, the roof sign visible from the well. Roof, Well, Minus One, Tower A,
  Tower B, Booths, Vans.
- **Items:** Heavy plate on the Roof, open to the sky and the well. Rail on
  Minus One at the bottom of the well, where everyone above can look down on
  you. Scatter in the towers, Flechette on mid ramps, health at the pay booths.
- **From:** Deck16 (vertical industrial decks), DM6 (a figure eight on
  stacked floors), Lockout (vertical movement at the edges).
- **Replaces:** nothing. When it ships, Episode 0 stops calling Arena Duel
  Larak Lot, per the gazetteer's rule that a name matches its geometry.

#### 3. East-West Pipe (new)

- **Place:** the pipe that carried something classified between two wings.
  Both wings were sealed; the pipe stayed open.
- **Players and modes:** 2 to 4. Duel, 2v2 team deathmatch.
- **Layout and loop:** two mirrored two-level wings 24 m square, joined by the
  Pipe: 60 m straight, exactly rail reach, 5 m wide, with two valve alcoves at
  its thirds. Beneath and beside it run two bent service crawls, 70 m each and
  scatter range, meeting at a crossover under the Pipe's midpoint where one
  stair climbs into it. Each wing has three ways in.
- **Signature:** the Pipe. Stepping into it is a duel with whoever holds the
  far end.
- **Landmark and callouts:** the Pipe lit in bands end to end, so range reads
  at a glance. East, West, Pipe, Valve One, Valve Two, North Crawl, South
  Crawl, Cross.
- **Items:** rail at the Cross stair head, inside the Pipe's midpoint and open
  to both ends. Armour on each wing's upper floor. Surplus under the Cross.
- **From:** Facing Worlds (two ends and one lane that makes range the
  subject) and DM6 (the crawls close the figure eight).

#### 4. Area Kitchen (new, replaces Compliance Yard)

- **Place:** the squat beige facility where the break room appears three times
  on one floor.
- **Players and modes:** 2 to 6, best at 4. Deathmatch and the GoldenEye
  mutators; this is the couch map.
- **Layout and loop:** one storey 60 by 50 m with a mezzanine. An open-plan
  office of 2 m cubicle walls sits in the middle, ringed by a corridor. Three
  break rooms hang off the ring, each with two exits, so every chase is a
  choice. A glass manager's office overlooks the cubicles at 2.8 m with a
  stair at each end. A 40 m archive hall is the only long line. A loading
  dock closes the far loop.
- **Signature:** the three kitchens, identical in furniture and told apart by
  their fridge lights.
- **Landmark and callouts:** Red Kitchen, Green Kitchen, Yellow Kitchen, Cubes,
  Glass Office, Archive Hall, Dock, Ring.
- **Items:** a health pad at each fridge. Armour in the Glass Office, seen
  through the glass from every cubicle. Rail at the end of the Archive Hall.
  Scatter in the Cubes.
- **From:** GoldenEye Facility and Complex (dense rooms and corridors, no dead
  ends, four people constantly colliding) and Temple (hide-and-seek rooms).

#### 5. Directive 17 Substation (rework)

- **Place:** a decommissioned transformer bowl, decks still numbered.
- **Players and modes:** 4 to 8. Deathmatch.
- **Layout and loop:** shrink from 150 m to about 84 m. Four quadrant decks at
  3 m around a pit, three ramps up each inner face as now, ground cable runs
  on the axes. New: a catwalk bridge at 5 m across the pit, reached by stairs
  from two opposite decks.
- **Signature:** the bridge over the pit.
- **Landmark and callouts:** transformer numbers painted on each deck. T1 to
  T4, Pit, Bridge, Cable Runs.
- **Items:** Heavy plate on the pit floor, rail on the bridge midpoint. Both
  are in view of all four decks. Health on the decks, weapons on the cable
  runs.
- **From:** Q3DM17 (the prize is exposed, height is the subject).

#### 6. Dulce Elevator (new, waits for a moving lift)

- **Place:** the multi-level box with a slow platform between floors that plays
  terribly and that everyone loves.
- **Players and modes:** 2 to 6. Duel and deathmatch.
- **Layout and loop:** four corner rooms on three floors (0, 3, 6 m) around a
  10 m open shaft. Bridges run from each room to the shaft rim. Stairs sit in
  the corners, so all climbing except the car happens at the edges. The car
  cycles floor to floor on a fixed, visible, audible 12 s loop.
- **Signature:** the Car. The armour rides it, claimable only aboard, in the
  middle of the shaft where every room can see it.
- **Landmark and callouts:** Car, Top, Under, the four corner rooms by lamp
  colour, Bridges.
- **Items:** armour on the Car, rail in the top room over the shaft, scatter
  in Under.
- **From:** Lockout (three floors that fight differently; you see where they
  went, not which floor) and Deck16 (the prize above the elevator).
- **Needs:** a cycling lift on the authoritative solid seam that bots and
  agents can ride. Until then it is not built.

#### 7. Chemtrail Alley (new)

- **Place:** a rooftop block of ductwork and HVAC over a service alley. The
  contrail overhead does not move with the wind.
- **Players and modes:** 4 to 8. Deathmatch.
- **Layout and loop:** two rows of roofs at 3, 5 and 7 m either side of an
  alley at street level, 70 by 50 m. Plank bridges link some roofs; others are
  2.5 m gaps for a running jump. Fire escapes climb from the alley. Ducts 1.8 m
  high make a waist-deep maze on the roofs.
- **Signature:** the roof jumps: a runner's line across the whole block that
  skips every stair.
- **Landmark and callouts:** the Water Tower, 9 m, visible from everywhere.
  Tower, Alley, Fire Escape, Big Duct, Billboard, North Roofs, South Roofs.
- **Items:** rail on the Water Tower, up an exposed spiral stair. Heavy plate
  in the Alley under the fire escapes: drop fast, climb slow. Health in the
  HVAC huts.
- **From:** Q3DM6 (two raised wings around a centre, more than two ways to most
  spots) and Carney's bonus jumps that reward movement skill.

### Medium maps: 8 to 16 players, team modes

#### 8. Sector 9 Transit Hall (rework, first team map)

- **Place:** a freight interchange.
- **Players and modes:** 8 to 12. Team deathmatch, Control.
- **Layout and loop:** keep the figure eight, the three doors each way, the
  perimeter service loop and the five second rollout to Mid Doors. Shrink from
  200 m to about 150 m. Add an upper concourse bridge crossing over Mid, so the
  map's hottest point has a second level. Give the halls identities: East is
  cold storage in blue light, West is parcel sort in yellow.
- **Signature:** Mid Doors under the concourse bridge.
- **Landmark and callouts:** the departure board over Mid. Mid, Mid Doors,
  Bridge, East Hall, West Hall, Deck, Service.
- **Items:** mirrored per hall: a rail on each hall's deck, scatter by each
  side's doors. Overtime on the bridge midpoint.
- **From:** Dust II (three routes, a measured first contact) and DM3 (named
  item zones built for teams).

#### 9. Low Water (new)

- **Place:** the coalition's home district: homes, clinic, repair market, tram
  trench. Before the wipe, with Union checkpoints; an aftermath variant later.
- **Players and modes:** 8 to 16. Team deathmatch, Control (three sites),
  Custody.
- **Layout and loop:** 160 by 120 m between the Clinic yard (coalition end) and
  the Tram Depot checkpoint (Union end). Three lanes: the Roofs (long, rail
  lines of 50 to 60 m), Market Street (mid, stalls and awnings), and the Tram
  Trench, sunk 3 m below the street, close range and the fastest way through.
  Stairs and fire escapes cross between lanes every 30 m or so.
- **Signature:** the Trench, running the length of the map under three street
  bridges.
- **Landmark and callouts:** the Market Clock. Clinic, Depot, Clock, Stalls,
  Trench, Bridge One to Three, Roofs.
- **Items:** Overtime at the Clock. A rail on the roofs above each end's third.
  Scatter in the Trench. Control sites at Clinic Steps, Market Clock and Tram
  Stop.
- **From:** Dust II (three lanes with different jobs) and Stalingrad
  (infantry first, tall buildings as sniper nests).

#### 10. Common Carrier (new)

- **Place:** the commandeered transport: passenger, cargo, repair and command
  decks.
- **Players and modes:** 8 to 12. Team deathmatch, Custody with the core in the
  hold.
- **Layout and loop:** 150 by 40 m on three decks (0, 4, 8 m). Bow (passenger)
  and stern (repair) mirror each other in function. A spine corridor runs the
  length of the middle deck. The cargo hold fills the centre from keel to top
  deck: container stacks, a gantry crane, catwalks across. The command deck
  looks down into the hold through glass. Port and starboard service passages
  close the loops. Hatches are open frames.
- **Signature:** the Hold, a three-storey room you fight across and through.
- **Landmark and callouts:** the Crane. Hold, Crane, Spine, Bow, Stern, Bridge,
  Port, Starboard, Catwalks.
- **Items:** Overtime in the crane cab, open to every catwalk. A rail at each
  end of the Spine. Armour on the catwalks.
- **From:** Facing Worlds (symmetric ends, a middle worth crossing), Lockout
  (bridges between rooms) and GoldenEye Caves (walkways over a drop).

#### 11. Reclamation Gulch (rework)

- **Place:** a materials recovery site between two weighbridge stations.
- **Players and modes:** 8 to 16. Team deathmatch, Custody. A jeep variant is a
  candidate test bed when vehicles exist.
- **Layout and loop:** shrink from 280 m to about 190 by 120 m, and the open ground
  from 180 m to about 110 m (22 s on foot). Roll it: berms of 1 to 2 m that hide
  a walker at 40 m, so the middle can be crossed in two-second hops. Keep the
  compounds, their walkways, the flank ridges and the knoll.
- **Signature:** the Knoll with the rail and no cover within 20 m.
- **Landmark and callouts:** the Crusher on one ridge and the Conveyor on the
  other. Knoll, Crusher Ridge, Conveyor Ridge, Gate, Walkway, Weighbridge.
- **Items:** rail on the Knoll. Armour inside each compound on the walkway.
  Health on the ridges.
- **From:** Blood Gulch (two bases, a field worth a rifle, flanks worth a rush,
  hills that hide).

#### 12. Custody Archive (new)

- **Place:** the lunar port's custody archive, with pressure galleries and
  captive workshops. Earth hangs in the windows.
- **Players and modes:** 8 to 12. Control (a moving single hill), team
  deathmatch.
- **Layout and loop:** 120 m. A two-level domed rotunda holds the archive
  stacks at the centre. A ring gallery circles it with windows onto the crater;
  its curve caps every line at about 30 m without a single crate. Four spoke
  galleries run out to four workshops; the teams hold opposite pairs.
- **Signature:** the curved gallery, where the next fighter always appears from
  around the bend.
- **Landmark and callouts:** Earth through the dome. Dome, Upper Dome, Ring,
  and the workshops Press, Loom, Kiln, Crate.
- **Items:** Overtime on the Upper Dome. Rails in the spoke galleries, the only
  straight lines. The hill starts in the Dome and hops to a workshop each
  minute.
- **From:** Halo's Chill Out (holding the power room pushes enemy spawns away)
  and the Arena Duel rosette at team scale.

#### 13. Tripoint Works (rework, for its own mode)

- **Place:** a reclamation plant where three jurisdictions meet: the Union's
  gridded compound, the coalition's scavenged one, the Inheritance's unmarked
  drum.
- **Players and modes:** 9 to 15, three sides. The three-cornered mode only;
  out of free-for-all rotation.
- **Layout and loop:** keep the trefoil, three capture yards and the unholdable
  plaza. Shrink from 320 m to about 200 m by bringing the compounds from 118 m
  to 75 m from the centre.
- **Signature:** the Plaza, which everyone crosses and nobody keeps.
- **Items and callouts:** as built, plus a callout per compound and yard.
- **From:** the three-way problem itself: whoever leads gets attacked by both.
- **Needs:** sides, three spawn sets, zone state and scoring (the list in
  [map-roster-2026](map-roster-2026.md)).

### Large maps: 16 to 32 players, conquest-lite with vehicles (later)

Each is fun on foot first. Vehicles spawn at team bases on timers, abandoned
ones return after 30 s, and no site needs a vehicle to take
([vehicles.md](vehicles.md) rung 5).

One site flavor recurs across this combined-arms tier: a pirate radio mast,
captured like any other site, its call sign switching to whichever side holds
it. This is the one place radio touches a mode, and only as one objective
skin among several, never a mode of its own; radio stays a small optional
flavor, the way it already is everywhere else in the game.

#### 14. Launch Works (new)

- **Place:** the Martian habitat's launch works, the M08 place: freight depot,
  bermed approach, launch gantry. Authored separately from the mission.
- **Players and modes:** 16 to 32. Conquest-lite.
- **Layout and loop:** 450 by 300 m. Five sites: the coalition's habitat edge
  and the Union's gantry yard as uncapturable homes, then Freight Depot, Berm
  Cut and Greenhouse Row between them. A long berm splits the map, and ground
  vehicles cross it at two cuts only. Infantry move through depot sheds and
  greenhouse rows under cover.
- **Vehicle lanes:** jeeps on the service road and through the depot yard;
  motorcycles on the pipeline track; jetpacks at the greenhouses for roof lines.
- **Signature and landmark:** the Gantry, 30 m tall and visible from
  everywhere, with a rail nest on top whose view the berm blocks.
- **From:** El Alamein (a ridge with two vehicle passes; homes spawn more
  vehicles than outposts) and conquest ticket bleed.

#### 15. Diego Far (new)

- **Place:** the outdoor range with high walls, dust and glare, named after a
  base that officially does not exist.
- **Players and modes:** 16 to 32. Conquest-lite, the Union defending.
- **Layout and loop:** 480 by 380 m, a horseshoe of range compounds around a
  dry drainage basin. The Union starts holding all five sites: Gate, Motor
  Pool, Tower Range, Firing Line, Bunker Tip. The coalition lands at an
  uncapturable staging point across the basin's open end.
- **Vehicle lanes:** jeeps on the ring road; motorcycles across the basin,
  which is open, fast and watched by every rail on the rim.
- **Signature and landmark:** the Basin, crossed in a few seconds by bike or not
  at all on foot, under the range tower.
- **From:** Wake Island (a horseshoe where the front moves by force or by
  flanking up the other leg, with long shots across the open middle). Glare is
  sound and colour, never a blinding screen.

#### 16. Waterworks (new)

- **Place:** the Earth recovery district's changed streets and waterworks, the
  M10 place, during or after the wipe.
- **Players and modes:** 16 to 24. Conquest-lite, infantry first.
- **Layout and loop:** 380 by 300 m of streets, filter beds and roofs. Five
  sites: Pump House, Filter Beds, Tram Bridge, Water Tower, Relief Market.
  Rubble keeps jeeps to two avenues.
- **Vehicle lanes:** jetpacks everywhere, the map's reason to exist, for roof
  and tower lines; motorcycles in the streets; two jeeps per home at most.
- **Signature and landmark:** the Water Tower, a site you take from the air.
- **From:** Stalingrad (dense ruins, sniper towers, vehicles held back by
  rubble) and Lockout's floors that fight differently, stretched to a district.

## Modes, in build order

[MODES.md](../MODES.md) defines each mode. This is the order, with what each
needs from the engine.

| # | Mode | Maps | Needs | Agents and bots |
|---|---|---|---|---|
| 1 | Scrap free-for-all (built) | Small | Item clock table, Tack by spawns, callout regions | Bots fill to a count; agents read callouts |
| 2 | Duel | Arena Duel, East-West Pipe, Dulce Elevator | 1v1 admission, spectator queue, fast rematch | An agent can queue and duel like anyone |
| 3 | Mutators | Every map | A named rule set per server, shown in `round_state` | Agents read the rule set before joining |
| 4 | Team deathmatch | Sector 9 first | Sides on the wire, team spawns, team score, 30 s weapons | Balance counts humans and agents alike; bots fill the short side |
| 5 | Control | Sector 9, Low Water, Custody Archive | Zone state on the wire, one moving hill, then three sites | Zones appear in `observe` |
| 6 | Custody | Low Water, Common Carrier, Gulch | A carried objective, carrier cannot shoot | The core's callouts reach agents as events |
| 7 | Three-cornered | Tripoint Works | Three sides, zone unlocks | Same seats, three sides |
| 8 | Conquest-lite | Launch Works, Diego Far, Waterworks | Vehicles, tickets, spawn at held sites | Agents drive on authored lanes |

The mutator set, all proposed and all cheap on the current rules:

- **Licence to Kill:** every hit kills.
- **Golden Rail:** one gold rail on the map, one shot kills, the carrier glows
  and is announced; kill the carrier to take it.
- **Rail Only:** everyone spawns with a rail and unlimited cells, no pickups.
- **Scatter Only** and **Fists Only.**
- **Two Lives:** two lives each, last fighter standing.
- **Open Weights:** everything loaded, no pickups, no respawns (the existing
  clan arena).

Maps for Sabotage, one of the two flagship modes in
[replayability.md](replayability.md#the-flagship-rescue-and-sabotage), which
needs two sites and asymmetric spawns: Sector 9 Transit Hall first (three
routes and a measured rollout), then Low Water (Clinic Steps and Tram Stop as
sites, the Trench as the fast route) and Common Carrier (bow and stern sites,
the Hold as mid). Custody Archive can host it with two workshops as sites. The
one-site 2v2 cut suits East-West Pipe (site at the Cross) and Area Kitchen
(site in the Glass Office). Reclamation Gulch, Tripoint Works and the large
maps do not suit it.

Rescue, the other flagship mode, needs a holding cell and one exit rather than
two sites; the current roster has no purpose-built map for that smaller,
asymmetric shape yet. Until one exists, a small Sabotage map can prototype it
by treating one site as the holding cell and the attacker yard as the exit.

Mutators come before team deathmatch because they turn every existing map into
new play for almost no engine work.

## Architecture impact

| Area | Change |
|---|---|
| `server/src/maps.rs`, `maps/runtime.rs` | New maps as validated data through the one runtime map path; built-in builders gain solid bottoms for bridges |
| `server/src/sim.rs` | Item clock table, proposed item kinds, sides, zones, mutator rule sets |
| `server/src/protocol.rs` | Callout regions in `MapInfo`; side and zone state; mutator name in round state. Additive, documented in `docs/protocol.md` |
| `agent-adapter` | `round_state` reports mode and mutator; tool shapes stay |
| `tools/playtest` | Kill distance bands and stall time as gates per map |
| `client` | Callout signs through keyed text, team colours, item respawn sounds |

## Verification

Per map: `validate` and reachability tests, a navigation route proof for every
item and spawn, `tools/playtest_roster.sh` at the map's target count against the
numbers in rule 10, a tour with three fixed poses plus a first-person pass, and
a recorded human session. Per mode: deterministic tests for scoring, spawns and
end conditions, and a mixed human, agent and bot session.

## Success criteria

- [ ] Arena Duel tightened, with four named gantry faces, under 25 s across.
- [ ] Area Kitchen replaces Compliance Yard and beats 12 frags a minute at six.
- [ ] Every small map meets rule 10 at its target count.
- [ ] Duel and the mutator set playable by humans, agents and bots together.
- [ ] Team deathmatch on Sector 9, then Control and Custody on medium maps.
- [ ] One large map fun on foot before any vehicle spawns on it.

## Sources

Checked 2026-09-24.

- Quake 3 item and spawn code: [g_items.c](https://github.com/ioquake/ioq3/blob/main/code/game/g_items.c),
  [g_main.c](https://github.com/ioquake/ioq3/blob/main/code/game/g_main.c),
  [g_client.c](https://github.com/ioquake/ioq3/blob/main/code/game/g_client.c).
- [Church of Quake item timings](https://churchofquake.com/wiki/items/);
  [Quake items](https://strategywiki.org/wiki/Quake/Weapons_and_Items).
- [DM3](https://quake.fandom.com/wiki/DM3:_The_Abandoned_Base),
  [DM3 notes](https://www.quaketerminus.com/quakebible/maps-dm3.htm),
  [DM6](https://www.quakeworld.nu/wiki/Dm6),
  [DM6 on Liquipedia](https://liquipedia.net/arenafps/Dm6/QuakeWorld),
  [Q3DM6](https://quake.fandom.com/wiki/Q3DM6:_The_Camping_Grounds),
  [Q3DM17](https://quake.fandom.com/wiki/Q3DM17:_The_Longest_Yard).
- [Doom II MAP01](https://doomwiki.org/wiki/MAP01:_Entryway_(Doom_II)),
  [Dwango5](https://doomwiki.org/wiki/Dwango5).
- [Deck16](https://unreal.fandom.com/wiki/DM-Deck16II),
  [CTF-Face](https://unrealarchive.org/wikis/the-liandri-archives/CTF-Face.html),
  [Facing Worlds](https://en.wikipedia.org/wiki/Facing_Worlds).
- GoldenEye: [multiplayer origins](https://mcvuk.com/development-news/how-did-goldeneyes-multiplayer-grow-from-a-single-paragraph-of-a-10-page-design-document/),
  [overview and modes](https://en.wikipedia.org/wiki/GoldenEye_007),
  [weapon sets](https://goldeneye.fandom.com/wiki/Multiplayer_Weapon_Sets),
  [level ranking](https://screenrant.com/goldeneye-007-multiplayer-levels-all-ranked-worst-best/).
- Halo: [Blood Gulch](https://www.halopedia.org/Blood_Gulch),
  [Lockout](https://www.halopedia.org/Lockout),
  [Bungie map design article](https://www.jmeiners.com/shamans/papers/art/bungie_map_design.pdf),
  [Halo 2 respawn times](http://nikon.bungie.org/misc/h2respawntimes.html),
  [Halo 3 spawn system](http://halo.bungie.org/misc/fyrewulff_spawnsystem/),
  [Chill Out study](https://book.leveldesignbook.com/studies/mp/chill-out).
- Battlefield 1942: [Conquest](https://battlefield.fandom.com/wiki/Conquest),
  [Wake Island](https://www.bf1942.online/wiki/maps/wake-island),
  [El Alamein](https://www.bf1942.online/wiki/maps/el-alamein),
  [Stalingrad](https://www.bf1942.online/wiki/maps/stalingrad),
  [Omaha Beach](https://www.bf1942.online/wiki/maps/omaha-beach).
- Theory: [the architecture of flow](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow),
  [good FPS map design](https://critpoints.net/2018/02/18/good-fps-map-design/),
  [The Illusion of Choice, GDC 2016](https://www.gdcvault.com/play/1023142/Level-Design-Workshop-The-Illusion),
  [Level Design Book metrics](https://book.leveldesignbook.com/process/blockout/metrics),
  [multiplayer post-mortem](https://medium.com/@nesterenkodmitry96/level-design-post-mortem-lessons-from-creating-multiplayer-aa-fps-bd8cd378ef8d),
  [the language of arena level design](https://www.plusforward.net/post/21433/The-Language-of-Arena-FPS-Level-Design/).
