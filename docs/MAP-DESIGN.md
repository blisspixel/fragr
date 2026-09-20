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
Current heightfield geometry cannot represent stacked accessible rooms and
ceilings merely by rendering them; extend and verify the shared contract first.

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
