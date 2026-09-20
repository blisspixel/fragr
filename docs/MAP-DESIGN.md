# Level design

A full FPS needs authored campaign places and purpose-built multiplayer maps.
Current arena layouts are useful foundations, not the spatial or visual bar.
[Campaign missions](CAMPAIGN-MISSIONS.md) own narrative purpose and sequence;
[MODES.md](MODES.md) owns multiplayer objectives and chronology.

## Start with purpose

Before geometry, write the place's ordinary function, the player's immediate
goal, what changed here, the encounter progression, and why its exit leads to
the next mission. Sketch a route graph and height section. Name the landmarks.
Do not start with a giant rectangle and distribute cover until it looks occupied.

The current six arenas still have oversized open spaces, repetitive cover and
weak landmarks. The [Compliance Yard study](plans/authored-compliance-yard.md)
is deferred spatial research, not the campaign opening. The first campaign
graybox follows M01's intake-facility story.

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
route changes through objectives, enemies or access, not arbitrary respawning
in a corridor the player just cleared.

Verticality needs decisions: drop to a flank, climb for a precision lane, cross
an exposed gallery, shoot between floors. Stairs must be walkable without jump.
Essential traversal must work with actual collision, jump height and headroom.
The shared finite-solid contract supports stacked accessible rooms and ceilings.
M01's lift gate has two validated, precomputed states. General moving lifts and
doors remain unbuilt; a cosmetic object cannot supply their collision or logic.

## Controls, doors and lifts

Simple physical interactions are part of the campaign, not puzzle difficulty.
Show the door or machine before its control, make the control readable through
shape and light as well as color, and show the result in the world. A local switch
can open a shutter, release a captive, lower a freight lift or reconnect a useful
shortcut. Avoid mandatory code entry, tiny hidden buttons, long switch hunts and
repeated trips through cleared corridors. Secrets can ask for closer observation.

Teach a safe control before using the same visual language under combat pressure.
An elevator should reveal a new space or change a fighting angle; waiting for it
must not become filler. The intended first set is M01's transfer access and lift,
M02's correction-cell releases, M04's dock freight lift and M06's cargo bulkheads.
Each belongs to the place's ordinary function and the player's immediate goal.

Extend the existing server-owned use, mission and map boundaries. Moving geometry
needs an explicit authoritative state and collision path before animation. Verify
blocked-door behavior, standing on a lift, exit clearance, retry reset, duplicate
use and late observation. Human input and agent actions operate the same controls;
rendering a moving door alone does not establish a usable door system.

## One combined-arms campaign landmark

M08's launch works is the planned vehicle showcase. Build a memorable chain of
freight depot, bermed approach and launch gantry, with occupied buildings and
covered infantry connections. A captured utility rover with a mounted weapon is
the first proposed drivable vehicle. It changes routes and firing positions rather
than turning the mission into a compulsory turret ride. Infantry can open a
vehicle shortcut from inside a service building; vehicle fire can relieve a
defended approach. The player can park, leave it and continue on foot.

Prove the infantry layout first, then integrate and tune the vehicle encounter.
Destroying or abandoning the rover must not strand the mission. Vehicle movement,
occupancy, damage and firing remain server-owned; entry/exit safety, controls,
spectating, agent operation and performance need evidence before release. This
capability is planned, not present in the current engine. Aircraft and a broad
vehicle roster are not prerequisites for this first combined-arms mission.

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
walking is not atmosphere. Avoid a mandatory enemy within an arbitrary number
of seconds in every scene.

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

Essential keys and controls identify their door or machinery through shape,
label and color together. Show the effect. Short objective text supports what
the world shows; it does not compensate for an incomprehensible layout.

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
