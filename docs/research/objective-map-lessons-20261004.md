# Objective map lessons for fragr

**Status:** researched, 2026-10-04. This is a design recommendation and source
audit, not acceptance of new competitive maps. No paid services or new runtime
dependencies. Sources were opened on the date above. Historical changes below
describe their specific releases, not the current competitive map pool.

## Primary evidence

These accounts explain design choices. They do not establish a universal best
map or prove that transferring a layout to another game's rules will work.

| Reference | Reported design facts | Lesson to test in fragr (inference) |
|---|---|---|
| [Dust, its original designer's account](https://www.johnsto.co.uk/design/making-dust/) | The central hall deliberately interrupted end-to-end visibility. Spawn-to-contact running times were measured. The second objective moved after feedback because defusal was being mistaken for capture the flag. A later defender spawn advance overcorrected balance and was reverted. An underpass shortcut was rejected because it would devalue the original route. | Objective ownership, first contact and rotation opportunity must be tested together. A shorter route can erase another route's purpose. Spawn adjustments require played evidence for both sides. |
| [Dust 2, its original designer's account](https://www.johnsto.co.uk/design/making-dust2/) | Architectural entrances compartmentalized areas and interrupted sightlines. Roads helped navigation; trim was deliberately restrained. The design retained concise connectivity and included both close encounters and long weapon opportunities. Bomb and spawn locations changed with feedback. | Build a small understandable decision graph and different useful range jobs. Architecture should frame each decision; extra detail should strengthen that graph rather than create indistinct hiding places. |
| [Valve's Inferno revision](https://www.counter-strike.net/inferno/) | Goals included visibility, group movement and feedback-driven gameplay changes. Site A had too many strong defender positions and poor background separation. A dark bedroom became a simpler cubby, a vehicle traversal was simplified, and spawn gained another exit. | Five fighters need space to stage, separate and clear positions deliberately. Removing an unreadable alcove can retain a strong defensive role while reducing guessing. |
| [Valve's Train revision](https://www.counter-strike.net/reintroducing_train) | The revision addressed overlapping lines of fire when clearing a site, added safer attack gathering space, reduced a sniper position, and made a defender expose more body at a raised position. Targets used stronger color than subdued surroundings. Large color fields supported player visibility; texture density and model silhouettes received deliberate attention. | A machinery-rich venue can look excellent while using quiet backgrounds. Retakes need an ordered clearing sequence. Long lanes require exposed, contestable firing positions and lateral shelter, rather than many simultaneous hidden angles. |
| [Valve's Nuke revision](https://www.counter-strike.net/reintroducing_nuke/) | The overhaul explicitly adjusted rotations between stacked sites, restricted defender rafters, changed site target placement to reduce exposure from above, and added attack options outside. The inter-site vent path changed shape to lengthen traversal. | Stacked architecture is a timing commitment. A vertical connector needs a specific tactical cost and a legible destination. High-ground power must be limited by exposure and alternate approaches. |
| [Valve's Dust II visual revision](https://www.counter-strike.net/dust2/) | Goals combined modern visuals, player readability and movement around cover. Dark backgrounds and unnecessary obstructions were removed; vehicles and window traversal became simpler and more predictable. | Better assets must improve silhouettes, physical truth and readable movement. Visual fidelity does not require collision clutter or distance-dependent cover. |

The Valve Developer Community level-design and mapper-reference pages could
not be retrieved in this research pass. No SDK-specific instructions, engine
visibility claims or unverified unit conversions are taken from those pages.
The readable first-party revision pages above provide the applicable evidence.

## Actual fragr contract

The local source audit uses main `a6407616` plus the additive multiplayer map
registration work. `server/src/maps.rs::sector_9_sabotage` is the only built
Sabotage layout. The larger Low Water and Custody Archive entries in
`docs/plans/multiplayer-maps.md` are proposed venues, not working objective
maps. Campaign room layouts cannot be assumed fair when reused for five versus
five.

`server/src/rules/sabotage.rs` defaults to 10 seconds muster, 105 seconds live,
3 seconds plant, 35 seconds charge and 6 seconds defuse. Actual resolved damage
or movement interrupts held objective actions. Elimination before a plant is
an outcome, while killing all attackers after planting does not replace the
defender's defuse job. `server/src/sim/sabotage.rs` gives late live joiners the
next round, avoiding an extra mid-round life. The strict ten-seat cap and a
standalone elimination mode remain planned work; balanced five-per-side
baseline evidence does not prove those admission rules.

`server/src/movement.rs::TOP_SPEED` is 5 m/s, step height 0.6 m and standing
body height 1.8 m. Walkable objective approaches use the shared authoritative
movement and navigation, including physical body contacts. Weapon pickups,
single counts per ammunition type and no reload/shop economy remain the game
contract. Do not import a shopping phase, penetration rules, flashbang
assumptions or crouch routes while copying someone else's timing diagrams.
Surviving equipment carry, discovery pickups and personal spawn Tack pads are
already Sabotage rules, with weapon-only mutators handled separately.

Community hosting uses the existing dedicated process and access lists.
`server/src/access.rs` on current root source already supports timed IP/CIDR
bans with UTC expiry. Expiring moderation is not a reason to invent account
identity, a hosted matchmaking service or a map-specific access system.

Mixed human and agent rosters are a first-class target. Controller, physical
body and faction are separate canonical facts: sides are readable through
issued identity, not a claim that conscious agents are less legitimate players.
Map acceptance needs human comprehension and actual agent navigation, supply
claims, site selection and retakes on the same authoritative action channel.
Strong aim or reaction speed is not evidence of cheating. Optional host rules
can define a room without forcing human-only ranked play or an account service.
Non-invasive host moderation should act on clear repeated hard abuse, not agent
strength; map design must not invent an aim-based automatic-ban policy.
The playtest planner's wrong-floor supply arrival was a real limitation, now
addressed in a separate focused checkpoint, not evidence that objective agents
already play every proposed venue competently.

## Three original objective venues

All dimensions and timing windows below are starting hypotheses, not measured
acceptance. The same sites can later support elimination staging, but the
round mode must not turn every deathmatch arena into a good objective map.

| Venue | Decision graph and range jobs | Staging, rotation and retake | Distinct place and risk |
|---|---|---|---|
| Sector 9 Transit Hall, built | Mid Doors supplies immediate information and a faster contested crossing. North and South Mid carry deliberate flank commits to A Frame and B Server. The service corridor is the slow outer escape. Aim for close entrance checks, medium freight clearance and a small number of long deck lines. | Existing protected attack stages sit behind the hall doors. Site anchors should cover separate approaches, not one impregnable mutual crossfire. Defenders must choose whether to rotate through the exposed centre or a slower covered hall; attackers who take the site gain different post-plant holds. | An inspection and freight interchange: frame, registry machine and sort deck. Current geometry is large for ten fighters and its central crossing can dominate the slow lanes; measure rather than assert fairness. |
| Low Water, proposed objective cut | Clinic Steps and Tram Stop are separated targets. Market/Clock is contested mid information. Trench is a close-range commitment with discrete bridge exits; roofs offer selected longer lines with ordinary stairs. Routes need not all connect to every site directly. | Clinic/service court and depot work bay provide separate attack gathering space and safe five-person starts. Market control enables a faster but exposed rotation; a sheltered domestic/service route stays slower. Each site needs two differently angled retake entries and a plant shelter that cannot cover both from one position. | Inhabited repaired community: plaster, awnings, clinic, water repair, tram infrastructure and personal possessions. The proposed 160 by 120 m footprint may be too diffuse for five versus five; use an objective-specific playable cut and keep distant homes as coherent scenery. Trench height complicates arrival and objective validation. |
| Custody Archive, proposed objective cut | Select two workshop targets on different spokes around the archive. Curved Ring provides repeated medium checks; a limited straight spoke permits a long weapon job. Upper Dome is an information/rotation position with exposure, rather than a view of every entrance and both targets. | Separate pressure-gallery approaches provide gathering rooms. Ring control creates a lateral choice; an enclosed lower service connection supplies the slower safe rotation. Workshop plant cover should break one dangerous angle while retaining an actual clearable defuse approach. Retakes can combine a spoke and ring entrance instead of funneling through one door. | Lunar custody architecture: pressure seams, broad enamel, captive work equipment and Earth views. Curves shorten sightlines through structure. Do not turn a four-spoke rotunda into four equally useful guessing routes or automatically stack the two sites just to imitate a precedent. |

## Audit of the built Sector 9 layout

`sector_9()` currently has a 200 by 200 m playable square around a 160 by 160 m
building. West/East partitions at x=-26/+26 have doors at z=-58/0/+58. Sites
are at [-38,0,-27] and [-38,0,27], each radius 3 m. Defender spawn data has six
slots between x=-56 and -50; attacker data has six between x=31 and 35.
That is enough authored choices for five bodies, but is not proof of a strict
five-seat policy or safe simultaneous starts.

The two sites are 54 m apart: 10.8 seconds is only a straight-line lower bound
at top speed, before physical cover and turning. The closest shown attack
spawn to either site has a Euclidean lower bound of roughly 14 seconds.
Reaching the x=26 partition from x=31 takes at least one second before any
door alignment; x=-50 to the x=-26 defence partition takes at least 4.8.
These different jobs are not evidence of an attacker advantage. Measure
actual first-contact sightlines, safe site setup and complete legal routes.
The deathmatch comment about contact after five seconds is not a measurement
of these Sabotage spawns or an acceptance target.

The built attack stages near [-33,0,+/-60] deliberately hide gathering from
site anchors. Six authored holds around each site give bots useful options;
they do not imply twelve simultaneous defenders or twelve required checking
angles. Site A's deck, B's freight cover, the 60 m weapon reach limit, and the
cost of moving through Mid need a played ten-fighter comparison. Preserve
existing shared geometry until an objective-specific change has its own plan.

## Concrete layout rules and acceptance receipts

These are proposed rules derived from the research and current game facts.

1. Give each route a job: quick exposed information, a committed close push,
   or a longer staged approach. Begin with 6-12 m entrance checks, 15-30 m
   primary exchanges and selected 35-50 m long lines. These are design ranges,
   not changes to actual weapon reach. Do not lengthen damage recovery or HP
   to compensate for illegible cover or a low number of opportunities.
2. Measure all five actual starts separately. Initial target: defenders get
   1-3 seconds to establish a site hold before a direct attack arrives; early
   contested information arrives around 6-10 seconds. Do not permit a clear
   shot into any enemy spawn or force a fresh fighter through a teammate.
   Physical routes, supply detours and body queuing must be included.
3. Start with a contested inter-site rotation around 7-12 seconds and a safer
   alternative around 12-18 seconds. Compare both directions and both sides.
   The 35-second charge leaves 29 seconds before an uninterrupted defuse must
   begin, so a far-side defender needs time to rotate, clear and commit. A
   sub-second site transfer removes fake and commitment decisions.
4. Five bodies need a genuine staging pocket and at least two practical
   dispersal paths from muster. Personal starter supply claims must complete
   for all five without a global pickup race or another fighter trapping the
   carrier. Record each arrival and held progress with real ticks.
5. Plant cover breaks a dangerous angle but leaves an exposed departure or
   a contestable retake path. Test every permitted plant location for physical
   standing clearance, reachable charge, two-way sightline meaning and actual
   interrupted plant/defuse. Include floor-height checks under upper sites.
6. A retake should reveal positions in a deliberate sequence. Avoid an exit
   simultaneously exposed to many hidden heights. Keep a long hold's shooter
   visibly exposed, and provide a flank that costs time instead of a magic
   drop directly behind both targets.
7. Name callouts for useful places and heights. Use A Frame/B Server and
   Clock/Clinic/Depot/Ring/workshop identities, with upper/lower labels where
   necessary. Preserve quiet, lit backgrounds behind dark uniforms and
   recognizable issued black/red equipment. Municipal and domestic walls
   retain their own palette; pixel surfaces do not justify unreadable noise.
8. Every cover silhouette agrees with authoritative solids. Essential cover,
   lamps and objective markers are present before active play, persist across
   moving camera peeks and graphics presets, and cast no false hit/movement
   implication. Retain failed walks and error logs; inspect moving frames as
   well as stills. Unit tests cannot certify subjective visibility or GPU
   performance.
9. For each venue record all 25 opposing spawn-pair exposure tests, all ten
   routes to each target, alternate rotations, supported supplies and charge
   retrieval. Run seeded real 5v5 matches with actual deaths, plants, defuses,
   interruptions and side swaps. Add human attack/defence/retake review before
   claiming competitive balance. Test late join and reconnect without an
   extra life or accidental eleventh fighter once the seat-cap work lands.

The recommendation is to tune the working Sector 9 objective contract first,
then build Low Water's civic approach and Custody Archive's pressure-gallery
approach as genuinely different decisions. Their full arena footprints and
campaign versions can coexist, but do not establish the objective cut's fun
bar by themselves. No copied map geometry, characters, textures or branding
is required to use these design lessons.
