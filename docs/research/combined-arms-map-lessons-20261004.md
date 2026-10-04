# Combined-arms map lessons for fragr

Status: researched recommendations, 2026-10-04. No map, vehicle, mode, scale
limit or acceptance result is implemented by this document. This is a bounded
review within the existing multiplayer and campaign roadmap rungs. M09 and
its strict v10 carry remain separate work in flight.

## Recommendation

Build memorable combat districts connected by useful journeys. Choose the
mode and actual roster before fixing dimensions. Prove the infantry version
with every vehicle unavailable, then make each vehicle offer a faster, more
exposed option. Ten fighters on a 5v5 map and an initial trial of 24 total
fighters on a vehicle map are distinct targets. Neither proves the older
17-map roster's proposed 32-player formats or public-server scale.

Keep an original approximately 2070 world: black and red Union installations,
varied free civilian people and repaired autonomous agents, working freight,
water and launch infrastructure. Pixel surfaces can have strong composition,
good light and coherent architectural shells. References inform spatial
problems, never copied geometry, names, textures or fictional factions.

## What the primary sources establish

The following facts are deliberately narrower than a claim that these are
universally the best maps. The application column is our design inference.
No classic map was played or benchmarked during this research.

| Reference | Verified source fact | Application and risk for fragr |
|---|---|---|
| Wake Island | The producer describes a narrow horseshoe encouraging encounters, with land attacks and sea flanks. Attacker/defender ticket ratios, vehicle types and ship/control-point respawns contributed to balance. [Original-producer interview, EA](https://www.ea.com/games/battlefield/news/wake-island-now-and-then) | A legible front can move without making every player cross the entire island. A flank needs a place to land and fight, not merely an empty long road. Ticket tuning cannot repair an exposed spawn or an unreachable retake. |
| El Alamein | The original manual describes broad desert terrain and a ridge between home bases, with majority control-point ownership in head-on Conquest. [Original manual, printed page 13](https://eaassets-a.akamaihd.net/eahelp/manuals/battlefield-1942-manual_PC.pdf) | A berm can divide sightlines and create recognizable crossings. The source does not establish a precise two-pass layout here. Make vehicle passes and infantry bypasses purposeful, then measure their relative travel. |
| Omaha Beach | The manual describes cliff defenses and a bunker complex above the beach; assault victory requires attackers to take every control point. [Original manual, printed page 14](https://eaassets-a.akamaihd.net/eahelp/manuals/battlefield-1942-manual_PC.pdf) | Asymmetric progression can produce a memorable breach. Permanent elevated crossfire over the only entry is a failure. Provide protected staging, separate breach angles and a genuine defensive fallback. |
| Stalingrad | The manual locates combat around train facilities and identifies head-on Conquest. [Original manual, printed page 13](https://eaassets-a.akamaihd.net/eahelp/manuals/battlefield-1942-manual_PC.pdf) | A recognizable industrial district can organize close fights and capture fronts. This manual alone does not prove the roster plan's sniper-tower or rubble/vehicle restrictions; those are our proposals to test. |
| Blood Gulch | The official archival project uses a port of the original map as a vehicle/enemy development playground. [Halo archival team](https://www.halowaypoint.com/news/digsite-deep-dive) | Separate vehicle handling tests from full map balance. A transport should be enjoyable to steer, exit and counter before a giant map depends on it. The article does not prove a safe spawn system or a particular optimal player count. |
| Lockout | The designer describes connected isolated rooms, visible movement without exact destination knowledge, optional exposed shortcuts and different combat ranges across floors. Player count, modes and vehicle inclusion are early design choices. [Original Bungie design article, archived PDF](https://www.jmeiners.com/shamans/papers/art/bungie_map_design.pdf) | Use floors for different decisions, not extra square footage. Ordinary stairs must remain useful; a movement shortcut can reward mastery without becoming a mandatory item check. |
| Facing Worlds | The official 2014 design talk and its indexed slide deck explicitly use Facing Worlds to discuss negative space. [GDC session](https://www.gdcvault.com/play/1020169/The-Importance-of-Nothing-Using), [original slide deck](https://media.gdcvault.com/GDC2014/Presentations/Brown_Jim_Importance_Of_Nothing.pdf) | Treat a sparse, immediately legible contest as a contrast to the vehicle district. Empty visual space can communicate a meaningful exposure decision. It does not justify a long walk outside every weapon's reach. |

The Facing Worlds creator interview could not be read from its publisher in
this pass. The slide deck was downloaded privately, but its visual slides were
not inspected. No specific topology, popularity statistic, classic timing or
creator quotation is asserted from those unavailable materials. The contrast
above is a recommendation grounded in the verified talk topic.

The original Battlefield manual also says destroyed vehicles respawn at bases
or control points (printed page 29). That historical rule is not Wipe's finite
vehicle economy. Keep the two profiles explicit. The manual's historical
themes do not become fragr's art symbols or faction identities.

## Current source and plan constraints

This review reads the parent working plans on 2026-10-04 and runtime based on
main a6407616. [Multiplayer maps](../plans/multiplayer-maps.md) proposes Holdfast
Atoll at 500 by 350 metres, Launch Works at 450 by 300 and Waterworks at 380
by 300. Those sizes and their 16-32 actor ranges are proposals. They are not
fresh playable map evidence. [The Wipe design](../design/wipe-finale-and-mode.md)
proposes one 180 by 160 metre M20 district, four participants and 24 active
hostiles, bounded devices, vehicles and civilian proxies. That is a different
population budget from a 24-total-fighter PvP test.

Actual ordinary top speed is 5 m/s. Weapon ranges in
`server/src/protocol.rs::range_units` are Scatter 12 m, Tack 30 m, Flechette
40 m, Rail 60 m and Sniper 90 m. A 150 metre site link takes at least 30
unobstructed seconds on foot, before cover or fighting. A large rendered
landscape can therefore hide a very small usable combat graph. Do not infer
combat reach from the appearance of a distant muzzle flash.

Actual drivable vehicles, capture-site spawn rules and catastrophe control are
not established by the existing bounded tram, fixed Union Turret, authored
enemy encounters or current Sabotage rounds. Use their canonical seams when
the owning bounded work item begins. Preserve M14 jeep, M16 motorcycle and
M19 jetpack introductions.

## Concrete changes to the planned maps

All dimensions and timing bands below are initial hypotheses requiring play.
They are not new acceptance claims or a competing map queue.

| Planned place | Bounded layout improvement | Decision it creates | Failure to reject |
|---|---|---|---|
| Holdfast Atoll | First test three adjacent capture districts within the existing island concept, with protected home staging and a ground return. Keep the remaining distant districts inactive scenery until actual 24-fighter density supports them. Each active district has a coastal arrival, covered inland walk and road approach. Add two separate infantry routes into the airfield control; put neither route inside a pilot's uninterrupted firing lane. | Road transport is fast and visible; the shore flank sacrifices time and information for another attack angle. Taking the airfield changes available tools while a foot retake remains possible. | Owning the airfield also grants an untouchable aircraft, every counter weapon and the only forward spawn. A boat wreck strands passengers offshore. A spawn ship moves during a live contested round without a tested rule. |
| Launch Works | Keep the berm as the organizing landmark. Put Freight Depot and Greenhouse Row on alternate covered infantry approaches, with Berm Cut connecting them. Two vehicle crossings are recognizable funnels with room to turn or reverse, and an ordinary foot bypass survives either wreck. Put the gantry precision perch above only one approach, with stair access and a second-angle retake. | Take a quick road crossing under pressure, or spend more time through sheds to arrive with cover. Holding a cut gives information and a route, not the entire map. | Both crossings can be blocked by abandoned vehicles. One sniper sees all sites and both spawns. A 30 metre perch grants safety from a roster unable to reach or hit it. |
| Waterworks | Prototype the Pump House, Tram Bridge and Relief Market as one connected infantry district first. Filter Beds and Water Tower are expansions only after density proof. Add supported stairs and a ground return to every useful tower/roof; let the jetpack shorten a route or change entry height. Put distinct wet masonry, tram steel and tower silhouette on the three initial landmarks. | A jeep controls an exposed avenue, a bike relocates, and a foot player can cut through the pump rooms. A roof exposes a new angle while the stair return permits a retake. | The current phrase about taking Water Tower from the air becomes a mandatory jetpack key. Decorative water implies unimplemented traversal. Repeating similar ruins makes every respawn disorienting. |
| M20 Wipe | Keep the 180 by 160 metre six-district graph. Make the Sluice-Pump-Pier loop the guaranteed foot spine; Freight-Tower is an exposed optional supply loop and Tram-Pier a quick return. Give every supply room two exits and each sentry pad a visible approach plus a reachable side/rear counter. Mark physical ingress roads outside the refuge rather than spawning behind the player. | A defended flank buys time for another finite supply trip. Losing a vehicle or abandoning a dry sentry changes the next route without ending eligibility for reprieve. | One bunker covers every ingress and cache. The director materializes bodies to meet a quota, announces rounds, or interrupts catastrophe for shopping. A scenery collapse silently removes the only retreat. |

For Holdfast, a later transport/aircraft stage should start with one clearly
bounded stock choice per side, not an unrestricted vehicle roster. Review
respawn delay, stock depletion and denial separately for Conquest and assault.
An aircraft pilot must remain hittable under the accepted exposed-seat rule;
cover, anti-air placement and ground objectives give infantry actual counters.
Do not promise a tank/aircraft/anti-air triangle before those systems exist.

For M20, locally isolated mechanical controls and hardwired non-conscious
sentries retain their accepted canon. Repainting connected Union equipment
does not remove the takeover channel. Pressure arrives continuously through
reviewed routes with local visible and captioned tells. The 24-hostile cap is
a proposal to measure, never a reason to teleport or inflate hit points.
The roughly 400 people at the pier use server-owned aggregate survival facts
and a bounded number of walking proxies, not 400 combat/pathfinding bodies.

## Fronts, anchors and replay

PvP spawn anchors are behind a fight, not inside a capture radius. Losing a
site should withdraw its spawn eligibility atomically and leave a home anchor.
A recaptured site becomes eligible only after its declared secure condition;
do not reward a lone back-cap with an instant team appearing at its shoulder.
Publish nearby conflict/contested facts from the server. Spawn selection must
consider the real world stage, sightlines, contact clearance and hostile
positions. Never let a client choose a privileged safe position.

Back-caps can pull defenders off a dominant front, but the journey should be
discoverable: a landing, road or service passage with visible ingress and a
retake route. Start with three contested sites at 24 fighters and compare a
five-site variant in actual matches before expanding. A full island with
empty flags is not automatically strategic. Fixed-seat 5v5 elimination and
Sabotage need compact authored layouts and round-specific spawns; do not
force those formats onto an entire vehicle island.

In PvP, vary a small reviewed profile between rounds: active site set,
available vehicle stock or side assignment. Keep topology, critical exits,
weapon ranges and callouts stable within a live round. In Wipe, the accepted
scenario seed chooses bounded pressure routes, optional caches and prepared
events. Retry keeps the same entry seed; join/leave cannot reroll stock or
resources. Readable local warnings must precede any route-changing event.
Human rematches should test learning and counterplay, not only novelty.

## Cooperative combined arms is a separate profile

Nick's subsequent accepted direction adds cooperative combined arms, working
name Liberation, alongside competitive PvP and the separate Wipe catastrophe.
Humans and free agents collaborate against explicitly Union-controlled forces.
This does not make authored campaign missions mandatory co-op. The parent owns
the canonical mode proposal and ordering; this research adds layout implications
only. No new controller or runtime decision service is built here.

Use Launch Works and Holdfast Atoll as the first two candidate venues under
their vehicle prerequisites. Begin with four participants; an eight-participant
profile needs its own capacity and fun proof. Enemy population remains explicitly
bounded and measured. The 24-total-fighter PvP recommendation cannot silently
become 24 enemies plus unbounded allies in this profile.

Native bots can be allied fighters as well as enemies. Human, agent, native bot
and spectator are control roles, not fictional factions. An issued conscious
body's imposed control, a free agent's autonomy and current hostility require
explicit server-owned identity. Do not turn every robot into Union opposition,
infer a rescue from a cosmetic repaint, or call a bot-count increase a free
agent coalition. Paid decision services remain developer tools, outside the
ordinary tick and player-runtime requirement.

Adapt the same foot routes and counters to a finite assault: choose a depot
breach or shoreline landing, secure a real forward anchor, recover finite
vehicle stock, then advance through a defended objective. Supply, rescue,
release and actual evacuation remain separate facts. Captives and optional
allies cannot softlock a match through their walking speed. An anchor belongs
to the cooperative party only after the declared physical clear/use condition;
defenders and reinforcements enter through reviewed actual routes, without
appearing behind a player. Losing all vehicles leaves a supported infantry
retake and exit. Enemy quantity or hit-point inflation cannot substitute for
readable role combinations and counterplay.

Acceptance adds four-seat then independently eight-seat actual runs, humans
and agents on the same input door, an allied native bot, all optional allies
absent, blocked rescue paths, destroyed stock and a lost forward anchor.
Test watch/join/leave and parked resume without duplicating seat inventory,
rescues, stock or reinforcement allowance. Choose and review a bounded death,
reinforcement and late-join rule before implementing it; do not borrow campaign
continues or Wipe's proposed wrapper by implication. A mixed-role mechanical
run establishes authority and lifecycle, while human repeat sessions establish
whether a coordinated breach and vehicle escape are enjoyable.

## Acceptance protocol

These are proposed review gates inside the owning map/mode plan. Existing CI,
collision, difficulty and QA assertions remain intact.

1. Record a versioned map/mode/seed/roster/resource receipt. Check supported
   routes from every spawn to every required site, exit, supply and retake,
   with ordinary movement and actual current geometry. Repeat with every
   vehicle unavailable and bounded wreck positions. Agents use the same
   action/controller and navigation budget, never a teleport shortcut.
2. Measure spawn-to-first-meaningful-contact and site-to-site travel at 10
   fighters for 5v5 and 24 total fighters for the first large PvP trial.
   Proposed initial bands are 5-10 seconds to first contact for compact 5v5,
   and 10-25 seconds from a forward large-map anchor on foot. Report median,
   tails, empty journeys and actual deaths. Averages cannot hide one stranded
   spawn. Wipe measures time from seeing a threat to an actionable escape,
   and supply-loop exposure, rather than using PvP respawn targets.
3. Test opposed and contested ingress, losing every forward anchor, actual
   back-cap and retake, delayed join, parked resume and explicit leave.
   Refuse occupied/blocked seats and unsafe exits without granting ammo or
   moving actors through cover. Lost finite vehicles and sentries stay lost
   under the selected profile. A campaign retry restores its real entry,
   seed and allowance once through the canonical writer.
4. On Wipe, run no vehicle, no sentry, all optional allies absent, spent-stock
   and deliberately abandoned-defense cases. Every required route and local
   reprieve remains possible under its declared finite contract. Keep actual
   failures. Never weaken death, timing or departure gates for an art capture.
5. Measure preparation and steady authoritative ticks separately using the
   existing histograms and assertion thresholds at the full proposed roster.
   Inspect continuous first-use and warm route captures on actual hardware,
   including turning vehicles, roofs, water edges and corpse cleanup. Record
   renderer, resolution, percentiles, traffic and peak entity counts. Headless
   success does not prove GPU performance or public hosting capacity.
6. Before calling a map fun, play at least two side-swapped sets with ten
   actual humans for the 5v5 profile, and a 24-seat combined-arms session with
   its human/bot split explicitly recorded. Include newcomers and returning
   players. Ask players to name their location, describe two useful choices,
   explain a death and attempt the counter on a rematch. Observe whether they
   volunteer another match. Mixed bot tests establish mechanics and density,
   not an unqualified 24-human fun claim. Reduce scope if vehicles dominate,
   foot journeys become chores, or a single hold wins without retakes.

The next concrete deliverable is a played, readable blockout within the
existing order. More named map proposals or additional asset families do not
substitute for that evidence.
