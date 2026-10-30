# Level design

A full FPS needs authored campaign places and purpose-built multiplayer maps.
Current arena layouts are useful foundations, not the spatial or visual bar.
[Campaign missions](CAMPAIGN-MISSIONS.md) own narrative purpose and sequence;
[MODES.md](MODES.md) owns multiplayer objectives and chronology.

## Maximum fun first

Every level is judged by its loop before its story or its look. The bar is the
best of the classics: simple to read, intensely fun to play. Each one gives
fragr a rule:

| Game | What it teaches | fragr rule |
|---|---|---|
| Doom and Doom II | Speed, no reloads, a monster mix that dictates the gun, ambushes sprung by a pickup, levels that loop back changed, secrets everywhere, an intermission tally against par | The enemy mix makes the player swap guns. Grabbing something can spring a trap. The way back is never empty. Every level ends on a tally. |
| GoldenEye 007 | Short objective lists, difficulty that adds objectives instead of health, hit reactions, alarms and reinforcements, par times worth chasing | Objectives are a few short verbs. Harder difficulties add optional objectives and tighter pars, not bullet sponges. Enemies react visibly when hit. |
| Counter-Strike | Few lanes, readable chokes, callouts, one life of tension, fast resets | Every fight space reads in seconds: where the threat comes from and where the flank is. |
| Early Call of Duty | Allies fighting beside you, a crescendo the level builds to, grenades both ways, always something happening | Each level builds to one climax people would talk about, and the world fights back loudly. |
| Battlefield 1942 | Sandbox objectives where unscripted moments happen | Give enemies room to flank and the player room to improvise; never only one solution. |

Checks for every campaign level brief and build:

1. **Fight early.** The first room teaches by fighting, not walking. Measure
   time to first combat contact on an ordinary route, and the longest stretch
   without a fight, a pickup or a reveal. One deliberate breath beat is allowed.
   Long empty walks are cut.
2. **One new toy.** Teach it safely, then remix it in the climax.
3. **Vary the shapes.** Use three to five encounter shapes per level, never two
   of the same in a row: ambush, crossfire, flank race, hold the point, horde
   push, long duel, boss.
4. **Weapon choice matters.** Distances and enemy mixes reward the right gun.
   Ammo and health pressure push swapping without starving the player.
5. **Secrets.** Two to four per level, with readable clues, rewarding early power.
6. **Story never blocks play.** Rescues, reveals and atmosphere happen while
   the player moves and fights. No escort fail states, no waiting on dialogue.
7. **End on a tally.** Kills, secrets, deaths and time against par, Doom's
   intermission in fragr's look, kept per difficulty in the service record.

If a brief reads complicated, simplify it: fewer systems, sharper fights.

## Size follows the crowd

Nick's rule, 2026-10-03: no giant, barren levels. A space is only as big as the
fighters who fill it.

- **Tight by default.** Campaign levels, duel and small-team maps follow Doom
  and GoldenEye: rooms, corridors, stairs and courtyards dense enough that
  fights keep colliding. Most fights happen inside about 40 m, so an enemy
  stays big on screen. Every space earns its size with a fight, a route choice,
  a pickup or secret, a landmark view, or one short breath beat.
- **Big only when it is full.** Open fields, canyons and long fronts belong to
  modes and levels with the population to fill them: 16 to 32 or more fighters,
  allies fighting beside the player, and vehicles that cross the space in
  seconds. That means Battlefield 1942 fronts, Halo's Blood Gulch, and the
  campaign's launch works and vehicle avenue (Levels 14 and 16). Agents and bots make that
  population possible on any server, labelled honestly as agents.
- **Long lanes are lessons, not travel.** A long sightline exists because a
  weapon needs it (the Rail, the Sniper Rifle), ends at an answerable position,
  and has cover within two seconds along it.
- **Measure emptiness.** The longest stretch without a fight, pickup or reveal
  is reported for every level and map ([Maximum fun first](#maximum-fun-first)),
  and the multiplayer [size table](plans/multiplayer-maps.md#1-size-by-player-count)
  sets crossing time by player count. A small map that takes more than 25
  seconds to cross is a big map with too few players in it.
- **Detail where it plays.** As Dust II's designer put it, trim goes "only
  exactly when needed, and not just as filler". Clutter that blocks movement
  or hides a fighter is a bug. Lived-in detail sits where it marks a route,
  names a place, or rewards a look.

## Start with purpose

Before geometry, write the place's ordinary function, the player's immediate
goal, what changed here, the encounter progression, and why its exit leads to
the next mission. Sketch a route graph and height section. Name the landmarks.
Do not start with a giant rectangle and distribute cover until it looks occupied.

Nick clarified on 2026-10-04 that wide spaces are fine when they make sense
for the lore. A lunar dome or ship hangar may have a large pressurized volume;
its shell, supports, loading routes and maintenance access should explain
that scale. Outdoor yards, streets, courtyards and terrain remain valid.
Distinguish the visible architectural volume from the route the player fights
through. Preserve useful openness, flanks and varied sightlines while making
rooms, infrastructure and transitions credible. Extra corridors or decorative
clutter cannot substitute for a believable place.

The eight-map multiplayer roster has uneven spatial quality. Larak Lot has
layered circulation; several other maps still have oversized open spaces,
repetitive cover and weak landmarks. The [Compliance Yard study](plans/authored-compliance-yard.md)
is deferred spatial research, not the campaign opening. Recall Notice owns
the campaign's intake-facility opening.

## Layout variety and current gaps

Keep several kinds of play across the roster. Compact room circuits, tactical
site approaches, looping campaign encounters and terrain-led vehicle fronts
need different geometry. A rectangular building can work well when its walls,
openings and floors create choices. A large footprint with scattered low cover
does not become a battlefield through scale alone.

The following is source and capture assessment, not a claim of human enjoyment
or balance. It identifies design work within the roadmap's sequence, not a
second implementation queue. Existing captures may predate current dressing;
authoritative geometry determines which routes actually exist.

| Multiplayer map | Preserve | Spatial work still needed |
|---|---|---|
| Larak Lot | Five walking levels, underpass, drops, stair returns and separated item routes | Keep this compact layered standard; judge actual route use and spawn fairness in play |
| Compliance Yard | Connected rooms, perimeter circulation and inspection gantry | Differentiate room shapes and purposes; stagger aligned doorways that currently share long firing lines; give exits different retreat destinations |
| Directive 17 | Exposed central pickup and reachable quadrant decks | Give its repeated stairs and square combat bowl distinct approaches and contested positions |
| Sector 9 | Central, side and perimeter routes; two Sabotage sites | Give the sites different local spaces and retake angles; shorten empty hall transit and distinguish rotations |
| Reclamation Gulch | Centre-versus-flank choice and compound approaches | Replace the impression of flat ground with slab ridges with purposeful terrain screening and connected local fights; it currently has no vehicle roster |
| Tripoint Works | Three identifiable compound destinations | Resolve its role before further dressing: the intended three-faction ownership system is absent, leaving a sparse compound field in ordinary matches |
| Holdfast Atoll | Horseshoe shore, Conquest points, roads and land/sea/air vehicles | Shape terrain and sheltered infantry connections around its existing fronts; its land remains broad flat panels |
| Low Water | Three bridges, a walk-under tram trench, four stair returns and two Sabotage sites | Differentiate clinic and depot approaches and retakes; break the trench's long firing line and the broad banks' repeated stall-and-screen pattern |

For compact multiplayer, use the interconnection and recognizable-room lessons
of GoldenEye. For objective play, use Counter-Strike's distinct approach and
rotation decisions. Holdfast is the existing combined-arms foundation for the
Battlefield 1942 lesson: geography organizes fronts and flanks. These are
design applications, not copies or claims that every reference suits every mode.

| Campaign levels | Spatial assessment and direction |
|---|---|
| 1 to 3 | Preserve Recall Notice's rejoining records routes, Persons Unknown's side ward and mezzanine, and Scheduled Service's ground/roof choices |
| 4 | Keep the court's vertical change; differentiate market circulation and approaches around repeated stalls |
| 5 | The implemented roof/workshop/tram chain needs a real maintenance loop and useful cross-connections; its old pre-split district-hub sketch is not built as this mission |
| 6 | Keep the Rail lesson and galleries; divide customs into working spaces with offset approaches and substantial sightline breaks |
| 7 | Preserve the town's bend and crater screening; vary the decisions along its mostly mandatory chain |
| 8 | Preserve stacked rings and staggered stairs; distinguish the spaces within each ring |
| 9 | A hull-side lane parallels the first gantry and a bow crossing parallels the north gantry; the arrival aisle under the raised office shows the hull. Judge route use in play; the arrival is a glimpse, not a full reveal |
| 10 and 11 | Preserve the Carrier's deck circuit and the tender's service route; differentiate repeated room thresholds while retaining the mine corridor's teaching purpose |
| 12 and 13 | Give habitat branches different tactical identities; compose the foundry around its real gallery/maintenance loop and reduce empty margins around repeated machine blocks |
| 14 | Preserve jeep, trench and berm choices; connect them at recognizable positions with sheltered infantry approaches |
| 15 and 16 | Review the stadium's empty upper apron and the boulevard's flat sequential flow; extra area and parallel walls alone do not create choices |
| 17 | Command-gallery height, two ordinary stairs, the outer service stair and the override-opened court stair are built; review the two-level gallery fight in rendered play and dress the floor as occupied command rooms |
| 18 to 20 | Preserve the overlook ascent, Planned Works' ground/roof alternatives and Local Exception's water crossings; test the broad opening and freight-yard fights for useful relocation |
| Still Here | Keep a calm, legible return through familiar places; improve inhabited landmarks and changed views without imposing combat complexity |

Doom and Doom II inform changing encounter spaces, loops and useful returns;
GoldenEye informs compact, recognizable objective interiors. Review the actual
weapon reach, encounter order and allowed inventory before changing a route.
An added flank must not accidentally skip required story or rescue facts.

## Rooms, routes, and readable height

Build meaningful rooms, courtyards, service passages, exterior cuts and overlooks.
Their proportions follow movement speed, enemy reach and useful weapon distances,
measured in the game. Use ceilings, facades, bends, topography, and depth to make
places substantial. An outdoor level still has boundaries and a reason to exist.

The campaign has substantial indoor missions, not outdoor arenas with occasional
doorways. Early facilities, archives and the ship emphasize connected interiors
in the spirit of Doom and GoldenEye. Selected later battles broaden toward
Battlefield 1942-style positions and flanks, while keeping useful buildings and
covered routes. The [mission treatment](CAMPAIGN-MISSIONS.md#shape-of-the-run)
owns that sequence. A large fight is several meaningful spaces connected by play,
not one uninterrupted field enlarged to suggest scale.

Main combat spaces usually offer a loop or more than one viable escape. Exits
should create different tactical options, not adjacent doors into the same kill
lane. Small dead-end secrets and brief controlled chokepoints can work; they
need a reward, a deliberate encounter, and a way back. No universal two-door
quota replaces playing the room.

Preview destinations through windows or overlooks, then reveal how to reach them.
Loops reconnect at memorable landmarks and open useful shortcuts. A return
route changes through objectives or enemies, not arbitrary respawning
in a corridor the player just cleared.

Verticality needs decisions: drop to a flank, climb for a precision lane, cross
an exposed gallery, shoot between floors. Stairs must be walkable without jump.
Essential traversal must work with actual collision, jump height and headroom.
The shared finite-solid contract supports stacked accessible rooms and ceilings.
Use the existing authoritative mission geometry seams, including M01's lift
gate and M13's moving lift. A cosmetic object cannot supply collision or logic;
new movement must have a validated server-owned lifecycle.

## Flow, doors and lifts

**A boomer shooter, not a door simulator.** Fights and flow come first
([pillar](VISION.md#easy-to-pick-up-deep-to-master)). Levels run through open
spaces, arenas, stairs and catwalks; progress is by fighting and arriving, and a
lift is just the exit. A level has at most three doors, never used as pacing. A
light switch-to-open is fine when the switch is next to its door and in view.
Never chains, keys, hunts or "gate opens when X" sequences. A room may seal
during a set-piece fight and open when it is won, sparingly. M01's built record
console, which stands away from its lift, is the one exception. Secrets can ask
for closer observation. M02 authoring enforces part of this: it rejects a
second required use switch and a door opener more than eight metres away.

**Readable without English.** Every label, prompt, objective line and sign is a
key in `client/i18n/*.po`; map data carries keys or registered kinds, never
English, and a missing key fails a harness instead of showing the raw key. Any
control or sealed room must read with the text hidden: a state lamp, a visible
link to what it affects, and a world change when it flips. Agents read the same
facts from legal prompts. Check it with before and after stills.

An exit lift should reveal a new space or end the mission; waiting for it must
not become filler. Moving geometry needs an explicit authoritative state and
collision path before animation. Verify standing on a lift, exit clearance,
retry reset, duplicate use and late observation. Human input and agent actions
operate the same controls.

## Combined-arms campaign landmarks

Launch Authority (Level 14) introduces the jeep and Continuance Walker around
the freight depot, bermed approach and launch gantry. Freedom of Movement
(Level 16) introduces the motorcycle. These are implemented development
missions; their pacing and human acceptance remain open. Level 8 is the
custody archive, not the vehicle showcase from an older campaign outline.

Vehicles should change routes and exposure while keeping useful buildings and
covered infantry connections. The player can park, leave and continue on foot.
Destroying or abandoning a vehicle must not strand the mission. Vehicle movement,
occupancy, damage and firing remain server-owned; entry/exit safety, controls,
spectating, agent operation and performance require separate evidence.

## Shared level kit

Godot supplies rendering; Rust owns movement, combat and mission state. Authored
JSON selects validated geometry, supplies, encounters, controls and registered
surface/decoration kinds. Build on these seams rather than adding mission-local
movement, enemy controllers or client-only blockers. See
[the map contract](../server/maps/README.md) for implemented fields and limits.

Reuse construction proportions, stair clearances, material scale, door language,
signs and faction equipment within each environment kit. The
[production kit table](CAMPAIGN-MISSIONS.md#art-and-sound-production-by-environment)
and [color bible](ART-COLOR.md) own location identity. Reuse makes places coherent;
room connectivity, silhouettes, combat problems and reveals make them distinct.
There is no prefab expander or general mission scripting system yet. Add either
only when repeated authored content demonstrates the need, with one validated
runtime representation and an inspectable expansion.

The classics are design references, not layouts to copy. A useful lesson from
[the original Dust 2 designer's account](https://www.johnsto.co.uk/design/making-dust2/)
is that entrances, connected routes and restrained visual cues make spaces
readable while retaining different fighting distances. For fragr, choose one
memorable spatial idea per mission and develop it through play. M01 uses public
intake below an administrative balcony, then branching records circulation.
Judge whether a player can remember the place and make decisions within it.

## Encounters with a rhythm

Each mission introduces or recombines a readable problem, builds intensity,
offers a memorable crest, and provides recovery. Vary that structure across
missions. A short calm inhabited area can establish stakes; persistent empty
walking is not atmosphere. Measure pacing per level, as in
[Maximum fun first](#maximum-fun-first), rather than placing an enemy quota in
every scene.

Teach one enemy tell in a forgiving setting, then combine roles. Crossfire,
flank pressure, priority support units, melee threats and scarce safe angles
create variety without inflated HP. Leave space to react to the tell.

Mix tight, medium, long and elevated fights across the campaign. Every mission
does not need every weapon to be equally good. It must remain completable with
its guaranteed inventory and supplies. Test the worst valid carried loadout,
not only a developer with every gun.

Items create choices. A valuable multiplayer pickup can expose its taker;
campaign supplies can also sit in believable stores or reward exploration.
Putting every best item on an uncovered central plinth becomes another formula.

## Secrets and objectives

A secret has a clue readable through geometry, material, lighting, sound with
caption support, or a relationship between spaces. Test whether attentive players
can infer it; do not require pixel hunting, random wall pressing or a wiki.

Short verb objective lines support what the world shows; they do not compensate
for an incomprehensible layout.

Plan one runner's line per level (planned, not built): a faster route that
rewards movement, aim and route knowledge against the mission's par time. It
never skips a required story beat or depends on clipping through collision.

Rescue objectives identify who needs help, the escape conditions, and any actual
deadline. Optional exploration cannot silently trigger an irreversible loss.
No required action needs two players or uninterrupted voice playback.

## Different jobs for different modes

| Use | Design requirement |
|---|---|
| Campaign | Place and route follow story; encounters escalate; exploration and local consequences persist |
| Co-op | Space for the target party, supplies and readable flanks; reconnect/drop-out cannot strand shared goals |
| Duel | Compact loops, item timing, useful height, protected spawns and fast rematches |
| Team/objective | Comparable useful approaches, defendable but breakable positions, coordinated flanks |
| Large battles | Connected local fights and clear destinations, not larger empty distances; foot play first |
| Survival | Repositioning and evolving pressure with readable recovery; no indefinitely dominant doorway |
| Aftermath variant | Recognizable original place, changed routes and ecology, distinct objectives and honest chronology |

Competitive rollouts are timed in both directions with current movement, not
assumed from an imported game's dimensions. Spawn checks include clearance,
enemy visibility, immediate access to equipment and escape, crowding, and actual
spawn deaths. One reachability assertion does not prove a spawn is fair.

Campaign locations can inspire multiplayer spaces, but removing the NPCs does not
automatically produce a good competitive map. Author and test their routes,
pickup clocks, spawn sets, objectives and player counts separately.

## Art and performance

Give every location a material family, light sources, ordinary-life props,
landmarks, and soundscape. Distinguish lunar pressure infrastructure from Mars
habitats and Earth civic buildings. Repeated modules should create believable
construction, not endless identical cubes.

Use original pixel surfaces, consistent texel scale, sculpted silhouettes and
directional light at the Boltgun production bar. Inspect enemies against their
actual backgrounds, effects while moving, and darkness from player height.
Sky and scenery establish geography while enclosed foreground spaces carry play.

Bound geometry, entities and effects against measured CPU/GPU budgets. Compare
renderer paths and record the machine. A CPU benchmark cannot prove an art-heavy
scene renders well, and one GPU does not prove every desktop target.

## Author, play, revise

1. Review the narrative or mode brief and route/height sketches.
2. Build validated data and a collision-correct graybox. Prove stairs, headroom,
   exits, doors, and required reachability with actual movement.
3. Place guaranteed equipment and encounters. Run solo and relevant mixed-client
   sessions with varied seeds, skill, inventory and population.
4. Observe route confusion, stalls, empty travel, dominant positions and spawn
   deaths. Fix causes, then repeat affected runs without weakening assertions.
5. Add complete art, animation and audio; inspect full first-person and spectator
   motion. Preserve gameplay clarity when dressing the space.
6. Ask fresh players to navigate and describe what happened. Record observations
   separately from mechanical results. Neither proves the other.
7. Publish current screenshots and honest receipts through the existing QA tour
   when implementation changes player-visible content.

Maps as JSON are a practical authoring path, not a substitute for this loop.
Navigation, geometry, encounter and visual evidence all matter.
