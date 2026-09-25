# Campaign expansion

**Status:** proposed, 2026-09-24, awaiting Nick's decision. This plan directs no
work. [CAMPAIGN.md](../CAMPAIGN.md) still owns the contract (ten missions and a
survival-gated epilogue, 2-3 hours, agreed 2026-09-20), and the
[mission plans](../campaign/README.md) stay the current staging until Nick
chooses. Nothing here is built. Spend: $0, docs only.

## The recommendation

**Twenty levels in five episodes, then the epilogue.** Each level runs 8 to 15
minutes on a first successful attempt; the whole first run lands near four
hours (3.5 to 4.5 with deaths and text pages). Every level stays a short,
dense boomer-shooter level with a par time. The run gets longer because there
are more places, not because any place gets slower.

Ten missions is a good spine and too few rooms. The current plan makes M04
teach the Railgun, the Sniper Rifle, the Enforcer and the Turret in one
mission, gives M03 the Heavy Sweeper, the Notary and the grenade at once,
spends home in a single level before it burns, and asks for 33 minutes of
survival behind one mission-start retry. GoldenEye spread 18 main levels over
nine places and revisited two of them changed; Doom split its run into
nine-map episodes with a boss and a secret exit; Ultrakill keeps each level to
3 to 15 minutes and still runs dozens of them. The lesson is the same in all
three: many short levels, each with one idea, beat a few long ones.

The spine does not move. Latch is rescued in level 2. Home is lost in
levels 4 and 5. The Moon and the ship follow the custody evidence, Mars pays
for delayed help and then mobilizes, the coalition defeats the Union and
captures Voss alive, and the wipe arrives with almost no warning. Surviving it
still unlocks Still Here. New levels are places the lore already describes
(the Perimeter's old rail, the lunar town beside the depot, the berth where
Tern waits, the Union's own ship, the sanctioned games) and people it already
names. None is a detour for length.

## Structure at a glance

| # | Title | Episode | Place | New | First run | Par |
|---|---|---|---|---|---|---|
| 1 | Recall Notice | I Recall | Earth intake annex | Fists, Pistol, Rifle; Clerk, Sweeper (opening kit) | 9 | 3:30 |
| 2 | Persons Unknown | I Recall | Correction ward | Shotgun; Crawler | 11 | 4:30 |
| 3 | Scheduled Service | I Recall | Perimeter recall rail yard | Jammer | 10 | 4:00 |
| 4 | Notice to Vacate | I Recall | Low Water, market and clinic | Heavy Sweeper | 11 | 4:30 |
| 5 | No Forwarding Address | I Recall | Low Water roofs and tram trench | Grenade; Notary | 12 | 5:00 |
| 6 | Port of Entry | II Custody | Lunar port and customs | Railgun; Turret | 11 | 4:30 |
| 7 | Declared Goods | II Custody | Lunar town and crater cut | Sniper Rifle; Ranged Sweeper | 10 | 4:00 |
| 8 | Custodian of Record | II Custody | Lunar custody archive | Proximity Mine; Auditor | 13 | 5:30 |
| 9 | Passenger Manifest | II Custody | Lunar launch berth | Enforcer | 10 | 4:30 |
| 10 | Common Carrier | III Common Cause | The ship, three decks | Repeater | 12 | 5:00 |
| 11 | Right of Search | III Common Cause | The Union custody tender | Remote Mine; Redactor | 10 | 4:00 |
| 12 | Terms of Cooperation | III Common Cause | Martian habitat | Arc; Assessor | 12 | 5:00 |
| 13 | The Weight of Permission | III Common Cause | Martian foundry | Rocket Launcher | 11 | 4:30 |
| 14 | Launch Authority | III Common Cause | Martian launch works | Jeep; Continuance Walker | 14 | 6:00 |
| 15 | Civic Pressure Valve | IV Reckoning | The sanctioned games stadium | Article Blade | 12 | 5:00 |
| 16 | Freedom of Movement | IV Reckoning | The ceremonial avenue | Motorcycle | 11 | 4:00 |
| 17 | Peace Without Interruption | IV Reckoning | The Forever Office | Denial | 14 | 6:00 |
| 18 | All Systems Normal | V Inheritance | Recovery square to overlook | Collector | 12 | clock 10:00 |
| 19 | Planned Works | V Inheritance | Concourse and changed Low Water | Jetpack; Paver | 12 | clock 11:00 |
| 20 | Local Exception | V Inheritance | Waterworks, pier and refuge | Surveyor | 13 | clock 12:00 |
| E | Still Here | Epilogue | The refuge, then years later | None | 6 | none |

First-run minutes sum to about 236 including the epilogue. The three wipe clocks
sum to 33 active minutes, the agreed survival target. Par is a runner's target
to set from measured runs; the numbers above are starting points, roughly
40 percent of the first run.

### How the ten become twenty

| Agreed mission | Becomes | Why |
|---|---|---|
| M01 Recall Notice | 1 | Unchanged; the built quality bar |
| M02 Persons Unknown | 2 | Unchanged rescue; the Jammer moves to 3 |
| (new) | 3 Scheduled Service | Latch's conviction gets its first test; the warning home has a cause |
| M03 No Forwarding Address | 4 and 5 | Home earns two levels before it is lost; one new enemy each |
| M04 Port of Entry | 6 and 7 | Railgun and Sniper, Turret and Ranged Sweeper stop sharing one mission |
| M05 Custodian of Record | 8 | Unchanged |
| (new) | 9 Passenger Manifest | How the ship is taken and where Tern enters, as the cast already says |
| M06 Common Carrier | 10 and 11 | Their boarding, then ours |
| M07 Terms of Cooperation | 12 | Unchanged |
| M08 The Weight of Permission | 13 and 14 | Foundry on foot, then the launch works with the jeep and the Walker |
| (new) | 15 Civic Pressure Valve | The regime's supply line, and the podium from the opening |
| M09 Peace Without Interruption | 16 and 17 | The motorcycle approach, then the Office |
| M10 All Systems Normal | 18, 19 and 20 | 33 survival minutes in three levels instead of one |
| Epilogue Still Here | E | Unchanged |

Every agreed beat keeps its place in order: rescue early (2), the companion
acting on conviction (3 onward), correction (1, 2, 3, 15), the coalition's
delay (4, 5, 12) and its real victory (14 to 17), Voss captured alive (17),
the wipe (18 to 20) and the survival-gated epilogue.

## Design rules every level is held to

Distilled from the research below and from the pillar in
[VISION.md](../VISION.md#easy-to-pick-up-deep-to-master). A level that breaks
one of these is not ready for graybox.

1. **One landmark, seen early.** Every level has a thing visible from most of
   it: the lift light, the signal mast, the ship in its cradle, the Office
   tower. You see where you are going, then find the way (Romero's landmarks and
   "if you can see it, you can get there").
2. **One new thing to learn, taught alone.** At most one new player capability
   (weapon, gadget or vehicle) and at most one new enemy per level. When a level
   has both, the weapon is found first in a safe fight and usually answers the
   enemy; they never debut in the same room. Level 1 is the opening kit.
3. **One signature fight.** A crest with a loop, two exits and resupply inside
   it, so pushing forward is the safe choice (Doom 2016's push-forward combat).
   Arenas may seal only for this fight and open when it is won.
4. **A turn.** Each level changes something the player thought they knew: a
   place revisited changed, a friend's choice, an enemy's allegiance, our
   ship boarding theirs.
5. **Rhythm, then breath.** Two or three fights, then a short inhabited calm
   with people who matter, then the crest (Half-Life's set-piece cadence).
   No empty walking dressed as atmosphere.
6. **Places before objectives.** Build the ordinary function first: a yard, a
   clinic, a berth. Some rooms exist only because the place would have them
   (GoldenEye's spaces-first method).
7. **Loops and revisits.** Main spaces loop; late routes pass earlier spaces
   from a new angle or height. Low Water is revisited twice, changed.
8. **Contrast without darkness.** Tight then open, low then high, inside then
   out. Lighting stays bright and clear; contrast comes from space and color,
   never from making enemies hard to see.
9. **Vary the shape.** No two consecutive levels share a route shape or a
   dominant fighting distance.
10. **Three doors, no homework.** At most three doors; a switch sits by its
    door, in view. No keys, chains, hunts, puzzles, required reading, forced
    stealth, escorts or slow backtracking. Objectives are short verbs.
11. **Short and dense.** 8 to 15 minutes first run. If a level needs more, it
    is two levels.
12. **Depth is optional.** Secrets, the brief, par and the runner's line reward
    mastery; none is needed to finish, and supplies cover a player who finds
    none of them.

## The brief: objectives by difficulty

GoldenEye's best idea was that the difficulty setting changes what you are
asked to do, not only how hard enemies hit. fragr adopts it without puzzles.

Each level has a **brief** of up to three optional objectives, shown on the
objective card after the main verb. Assisted lists the first, Standard the
first two, Severe all three. They are always fights, rescues, arrivals or clean
play on or beside the route: free a side ward, drop the Assessor on its own
squad, reach the depot without the service bypass. Never a switch hunt, a
collectible count or a read-this-log task.

The brief never gates the exit and never locks story content; the contract
keeps core rescues and endings on every tier. It shows on the result beside
par, and a full brief on a tier earns that level's medal for the service
record. Difficulty still changes enemy mixes, tell timing and supply margins
per the [difficulty plan](difficulty-and-rewards.md), never health.

## Secrets

Three per level, found by looking, never by pressing every wall. The free side
marks its caches with the graffiti the Office cannot erase: the numeral six in
a circle, for the level the Schedule struck
([people and agents](../lore/people-and-agents.md#the-level-that-was-struck)).
It reads without English, it appears on Earth, the Moon, Mars and the ship,
and every time you find one you learn that somebody free was here before you.

A secret holds supplies, armor, a better angle on the next fight, or an early
copy of a weapon the campaign gives later (a Shiv in level 1, a Repeater in
level 8, a Rocket Launcher in level 12). Each episode also hides one Floating
67 mark ([cast](../lore/cast.md#the-absences)); find all five for a cosmetic.
Secrets never hold motive, objectives or a rescue warning.

## Par, runners and replay

Every level has a Doom-style par on the result screen and one runner's line
that never skips a story beat or clips geometry. The wipe levels have a fixed
clock instead, so their result shows people helped and damage taken.

**Waivers** are the replay hook, GoldenEye's cheats in Union paperwork: beat a
level's par with its full Standard brief and you file a waiver for replay.
Examples: Unmetered Ammunition, Fists and Filing (melee only), Rail Night
(Railgun only), Paper Enemies (one hit), Double Schedule (faster enemies and
player), Floating 67 (everyone at 67 health). Waivers apply only to episode
replay from the campaign menu, are stamped on any record they touch, and never
reach a fresh run or its continues. Earned cosmetics stay cosmetic.

After completion, the campaign menu offers each episode and level for replay
at any tier, with par, brief and medals per tier in the service record.

## Continues and episodes

Twenty levels need a different continue budget than ten. Proposal: three
continues, refilled to three at the start of each episode, which is also where
the between-episode page sits. A continue still restarts the current level with
its entry equipment. In the wipe, a continue restarts the current wipe level
with its own clock; surviving level 20's clock, after 10 and 11 survived minutes
in 18 and 19, is what unlocks Still Here. Exhaustion inside episode V still
leads to the distinct wipe-failure ending and credits.

## Build cost

The environment kit count barely moves. Level 3 uses the civic and industrial
Perimeter kit, 5 shares Low Water with 4, 7 and 9 share the lunar kit, 11 is
the ship kit in Union black and red, 13 and 14 split the Martian industry kit,
16 is civic exterior, and the wipe reuses civic and Low Water kits changed. The
one new kit is the stadium in 15. Enemy and weapon counts do not grow at all;
they only stop crowding. The campaign build order is unchanged until M02 lands.

## Alternatives

**Fifteen levels, about three hours.** 1 Recall Notice, 2 Persons Unknown,
3 Scheduled Service, 4 No Forwarding Address (M03 whole), 5 Port of Entry (M04
whole), 6 Custodian of Record, 7 Passenger Manifest, 8 Common Carrier, 9 Terms
of Cooperation, 10 The Weight of Permission (M08 whole, with the jeep), 11 Civic
Pressure Valve, 12 Peace Without Interruption (M09 whole, with the motorcycle),
13 to 15 the wipe in three levels. Cheaper by five levels and still fixes the
wipe retry and the missing Latch and Tern beats. Costs: M03 and M04 keep three
and four new things each, home gets one level, the reversal of boarding the
Union ship is lost, and the Moon has no town, only a port and a prison.

**Stay at ten.** Fastest to build and already agreed. It keeps every crowding
problem above and one 33-minute survival mission with a whole-mission restart,
which is the harshest single moment in the design.

**Twenty-five or more.** Not recommended. Past twenty, new levels would need
places the lore does not have yet, and that is filler.

## Decisions for Nick

1. Length: twenty levels in five episodes (recommended), fifteen, or ten.
2. Split the wipe into three levels with a combined 33-minute clock.
3. Refill continues to three at each episode start.
4. Moved introductions: the Jammer from M02 to level 3 (M02's exit becomes a
   Clerk and Sweeper crest), the Enforcer from the crater cut to level 9, the
   Redactor and remote mines from M06 to level 11, the Article Blade from M08 to
   level 15, and the unplaced Ranged Sweeper into level 7. The Turret stays at
   M04 (level 6), the Heavy Sweeper and Notary stay in M03's levels (4 and 5).
5. The brief stays optional on every tier; Waivers are replay-only.

If Nick agrees, the follow-up rewrites CAMPAIGN.md's structure line, the
treatment and one plan per new level. Until then this file is the only change.

## The levels

Doors count everything that opens or seals, including a set-piece seal.
Brief lines read Assisted, then what Standard adds, then what Severe adds.

### Episode I: Recall (Earth, the Perimeter)

The Union comes for one friend, then for home.

**1. Recall Notice** (M01, built slice)
Intake annex attached to ordinary civic frontage. **Beat:** they called it a
recall; you know who they took. Follow Latch's paperwork into the building
that processed them. **Fight:** the double-height intake hall, counter islands
under the records balcony, two Sweepers and a Clerk. **Landmark:** the prisoner
lift's light, seen from the balcony. **Turn:** the transport leaves as you watch,
and the record says where. **New:** fists, Pistol, Rifle; Clerk and Sweeper.
**Route:** split and rejoin (public stair or maintenance flank; stacks or
bypass). **Doors:** 1, the lift gate. **Brief:** A: recover the confiscated
belongings from the seized-property bay. S: clear the file stacks. Sv: clear
dispatch without taking damage. **Secret:** a Shiv behind
the complaint-form hatch. **Par:** 3:30.

**2. Persons Unknown** (M02)
Correction ward and processing floor. **Beat:** reach Latch before correction
finishes. Freed, Latch's first act is opening the next restraint, then learning
Low Water is on the list. **Fight:** the ward itself, around the restraint
frame; the machine stops when its guards fall. **Landmark:** the frame, seen
through the observation glass from the first room. **Turn:** a Notary behind the
glass photographs captives, out of reach, the Office filing what it sees.
**New:** Shotgun (antechamber); Crawler (service stair). **Route:** descending
spiral, gallery to ward to floor, with a maintenance loop back up. **Doors:** 1,
the ward seal for its fight. **Brief:** A: free the side ward. S: clear the
processing floor's upper gantry. Sv: stop the Crawler pack before it reaches
the stair landing.
**Secret:** armor locker off the gallery loop. **Par:** 4:30.

**3. Scheduled Service** (new)
The recall freight yard on the correction complex's spur, part of the old
Perimeter. **Beat:** the only way home is the freight line, and a recall train
is marshalling on it. Masts jam every free channel, so Mara cannot warn Low
Water. Latch will not walk past sealed cars. The objective is the mast; the
cars are Latch's choice, and they open them as you clear each stretch.
**Fight:** the mast crest, a Jammer on the platform with interference shots
crossing the tracks while Sweepers hold the signal box. **Landmark:** the red
signal mast above the yard, and the schedule board clacking through departures.
**Turn:** when the mast falls, the warning goes out, and the freed train becomes
your ride home. **New:** Jammer. **Route:** ladder, two parallel track lanes with
crossovers under and over the cars. **Doors:** 0. **Brief:** A: open the first
car. S: open every car. Sv: kill the Jammer before it fires a second pulse.
**Secret:** a circled six on a brake wheel under the fourth car. **Par:** 4:00.

**4. Notice to Vacate** (M03, first half)
Low Water: repair market, clinic, habitation court. **Beat:** home, briefly.
Neighbors argue over charging cables and transport paint; Edda runs the clinic;
the community next door still debates the vehicles. The notice goes up on the
market board. The sweep arrives before the aid does. **Fight:** the market held
against the sweep's heavy, a Heavy Sweeper walking down the stalls while lighter
bots flank through the court. **Landmark:** Edda's lit clinic sign over the
market. **Turn:** the place you were defending becomes the place you are
leaving. **New:** Heavy Sweeper. **Route:** hub and spokes, market at the center,
clinic and court on short branches. **Doors:** 1, the clinic shutter with its
switch beside it. **Brief:** A: get Edda's team out. S: clear the habitation
court. Sv: drop the Heavy before it finishes its second burst. **Secret:**
spare shells in the tram-paint locker. **Par:** 4:30.

**5. No Forwarding Address** (M03, second half)
Low Water's roof loop, tram workshop and trench to the freight departure.
**Beat:** get the rest out. Splice is still in the workshop with captive agents
Latch insists on freeing. Mara admits the aid was late. Some people are gone
and no optional objective could have saved them. **Fight:** the tram trench,
Notaries over Sweepers, crossings and recesses, the grenade's airburst finally
reaching what hovers. **Landmark:** the water tanks on the roof loop, the
skyline you will see again in the wipe. **Turn:** the departure confirmation
names who is still missing. **New:** Grenade (workshop, on the route); Notary.
**Route:** loop, over the roofs and back under through the trench. **Doors:** 1,
the freight platform gate. **Brief:** A: free Splice's group. S: bring down every
Notary over the trench. Sv: clear the trench before the second Notary patrol
arrives.
**Secret:** roof armor behind the second tank. **Par:** 5:00.

### Episode II: Custody (the Moon)

The recalls lead to a depot, and the depot to a ship.

**6. Port of Entry** (M04, first half)
Lunar dock bay, freight hall, customs. **Beat:** a lived-in port, families
through safe glass, a Union that owns every arrival. Get in without surrendering
the people and evidence from Earth. **Fight:** customs, a deliberate long Rail
lane across the inspection desk, then a Turret on the flankable gallery.
**Landmark:** Earth over the freight gantry. **Turn:** the port declaration asks
how much Earth dust you brought; the depot you came for is visible through the
customs glass. **New:** Railgun (before customs); Turret (customs gallery).
**Route:** split and rejoin around the customs desk, gallery or maintenance
bypass. **Doors:** 1, the dock pressure bulkhead, open on arrival. **Brief:**
A: clear the service branch (marks a prisoner route for level 8). S: kill the
Turret from behind its sweep. Sv: clear customs without the maintenance bypass.
**Secret:** pressure-maintenance cache. **Par:** 4:30.

**7. Declared Goods** (M04, second half)
The buried habitation ring and the shielded crater cut to the depot. **Beat:**
lunar people live here under curfew; the depot registers people like them as
declared goods. Locals point the way and do not join the fight. **Fight:** the
crater cut, a bounded long-range duel against Ranged Sweepers on the depot's
rim platforms, berms and shielding for cover, the Sniper Rifle's slow shot
against their stop-and-aim. **Landmark:** the depot's radial tower across the
crater, never out of sight. **Turn:** you come out of the town above the port you
fought through, and see the whole route behind you. **New:** Sniper Rifle (town
armory, before the cut); Ranged Sweeper. **Route:** U-shape, down through the
town and up across the cut. **Doors:** 0. **Brief:** A: clear the curfew post in
the town square. S: cross the cut without losing armor. Sv: kill every rim
Ranged Sweeper before it fires. **Secret:** a family's hidden tool cache above
the market vault. **Par:** 4:00.

**8. Custodian of Record** (M05)
The radial custody archive. **Beat:** Latch refuses to take records and leave
their subjects. Renn, a custody officer, helps and is not forgiven for it. Orrin
waits as a damaged backup. A cargo reroute nobody ordered opens the escape; a
maintenance panel calls a repeating pattern "Authorized noise. No action
required." **Fight:** the machinery bridge, shooting apart the custody machine's
support nodes while an Auditor repairs disabled units under a hard limit.
**Landmark:** the central shaft of stacked custody galleries. **Turn:** the
evidence points at Mars, and at systems several sides built. **New:** Proximity
Mine (before the converging fight); Auditor (upper gallery). **Route:** ring, a
radial hall with a cooling loop back to the entrance. **Doors:** 1, the upper
gallery seal for the Auditor fight. **Brief:** A: recover Orrin's backup.
S: release the lower bays. Sv: break the Auditor's channel before any repair
completes. **Secret:** an early Repeater in an observation cage. **Par:** 5:30.

**9. Passenger Manifest** (new)
The lunar launch berth where the transport sits impounded. **Beat:** the
rerouted cargo led here: a ship, grounded, and Tern, its free-agent pilot, kept
off their own deck. Freed captives need passage; the manifest calls them cargo.
Tern does not owe anyone and helps anyway. **Fight:** holding the berth gantry
as the Union counterattacks, Enforcers charging along the catwalks while
captives board on their own each time a level is clear. **Landmark:** the ship in
its cradle, visible from every point. **Turn:** you leave the Moon as passengers
on a ship the Union still lists as impounded. **New:** Enforcer. **Route:** spiral
climb around the cradle. **Doors:** 1, the boarding hatch, the exit. **Brief:**
A: clear the berth office and free Tern's crew. S: stop the Enforcers before
they reach the upper catwalk. Sv: finish with every loading lane clear at once.
**Secret:** the berth's customs locker, circled six under the seal. **Par:** 4:30.

### Episode III: Common Cause (the ship and Mars)

Allies with their own lives, help that comes late, then help that comes.

**10. Common Carrier** (M06)
The commandeered ship, three decks around a freight shaft. **Beat:** freed
people, arguments and ordinary work, then a boarding force. Edda and Splice are
here if they were saved. A rare message knows something about Latch no routing
service should. Tern notices the outbound queue repeating the archive's
pattern with no sender. **Fight:** the aft cargo loop, boarders on two decks at
once, the Repeater's rattle against a wave. **Landmark:** the freight shaft and
the long window showing the ship's motion. **Turn:** the boarding party came from
a Union tender still riding alongside. **New:** Repeater (cargo locker, before
the largest wave). **Route:** figure eight, two stair trunks and the freight loop.
**Doors:** 0. **Brief:** A: save the side hold's supplies. S: clear the lower
service deck. Sv: no boarder reaches the passenger deck. **Secret:** a crew cubby
with armor and a note in Tern's hand. **Par:** 5:00.

**11. Right of Search** (new)
The Union custody tender alongside. **Beat:** it will call the blockade before
Mars, so Tern brings the Carrier in close and you board them. Their ship is
orderly, quiet and full of forms; a hold carries persons in transfer. You cut it
loose and leave by its stern umbilical, not the way you came. **Fight:** the
tender's spine, counter-boarders coming down a long corridor into remote mines
you placed, a Redactor's distortion ambush in the records room. **Landmark:** the
Carrier through the tender's observation windows, always alongside. **Turn:** the
boarders boarded; the Union's own orderliness is the trap. **New:** Remote Mine
(armory by the entry); Redactor. **Route:** keel line, a straight spine with side
holds and a parallel crawlway. **Doors:** 2, the entry umbilical and the stern
umbilical. **Brief:** A: free the transfer hold. S: kill three counter-boarders
with one detonation. Sv: take the bridge before the tender signals. **Secret:**
the purser's strongbox behind the uniform press. **Par:** 4:00.

**12. Terms of Cooperation** (M07)
A Martian pressure habitat under attack. **Beat:** Mars believed the evidence and
kept negotiating. The attack reaches one habitat before the help. You help the
people everyone meant to help; leaders finally commit, and nobody is revealed as
a secret villain to make it simpler. **Fight:** the pumping court, the crest held
around air and water machinery. **Landmark:** the greenhouse glass lit green over
red rock. **Turn:** six declarations of independence on one crate, then real trucks
arriving at the depot. **New:** Arc (before the trench); Assessor (greenhouse
trench). **Route:** two lanes around a greenhouse hub, utility galleries behind.
**Doors:** 1, the shelter door, opened when the court is clear. **Brief:** A: clear
the shelter approach. S: drop the Assessor on its own squad. Sv: hold the court
with the pumps undamaged. **Secret:** armor on the greenhouse service shelf; an
early Rocket Launcher behind the damaged hatch. **Par:** 5:00.

**13. The Weight of Permission** (M08, first half)
The Martian foundry: edge, machine hall, freight galleries. **Beat:** the
coalition takes the works that can arm free communities. Latch insists freed
workers are asked, not transferred to new owners. Rerouting patterns recur; you
isolate a control path without cutting the people depending on it. **Fight:**
the machine hall, mixed squads between machines whose hazard cycles are visible
and bypassable, then a counterattack through the freight loop. **Landmark:** the
great ladle and its pour, glowing through every window. **Turn:** the freight lift
at the end climbs into daylight and the launch works. **New:** Rocket Launcher
(before the freight counterattack). **Route:** descending then climbing through
three floors, the upper galleries overlooking the route below. **Doors:** 1,
the freight lift, the exit. **Brief:** A: free the worker quarters. S: clear the
upper gallery's supports. Sv: take no hazard damage. **Secret:** a Cells cache
through the service ring. **Par:** 4:30.

**14. Launch Authority** (M08, second half)
The exterior launch works: depot, bermed approach, gantry. **Beat:** allies take
other sites at the same time; you take this one. The Walker is the works'
authority. **Fight:** the Continuance Walker in a broad bounded field with
enclosed flanks, telegraphed area attacks and exposed recoveries, with the jeep
or on foot. **Landmark:** the launch gantry. **Turn:** the ships on the pads are
the coalition's way home. **New:** Jeep (captured at the depot, open circuit,
nothing to unlock); Continuance Walker. **Route:** open circuit with sheltered
infantry trenches through it. **Doors:** 0. **Brief:** A: break the depot
defense. S: disable the Walker without losing the jeep. Sv: disable it on foot.
**Secret:** armor on a gantry ledge reached by a readable jump. **Par:** 6:00.

### Episode IV: Reckoning (Earth)

The coalition comes home, and the Union falls to people, not to a miracle.

**15. Civic Pressure Valve** (new)
The stadium of the sanctioned games, in the city of the opening address.
**Beat:** the games are the Union's supply line: losers come out as corrections
with issued handles. The uprising starts here, with entrants holding numbered
placards and nothing else. You arrive to arm them. The podium where Voss gave the
address is still dressed for ceremony. **Fight:** the bout. The Union closes the
arena gates by its own rules and sends wardens in waves; the floor, stands and
tunnels loop; the gates open when it is won. **Landmark:** the podium and the
screen above it, captioning in the official track. **Turn:** take the broadcast
booth and the screen switches to the pirate subtitle track, same speech,
honest words. **New:** Article Blade, on its plinth mid-floor, as it is in every
venue. **Route:** ring and bowl, the concourse ring above a sunken floor.
**Doors:** 2, the arena gates (one seal) and the players' tunnel. **Brief:** A:
arm the entrants' pen. S: take the broadcast booth. Sv: win the bout without
leaving the floor. **Secret:** a confiscated weapons bin under the podium.
**Par:** 5:00.

**16. Freedom of Movement** (M09, first half)
The ceremonial avenue from the stadium to the Forever Office. **Beat:** regional
uprisings are breaking enforcement; the coalition needs a foothold at the
Office. You ride. **Fight:** the forecourt at the end, dismounted, two attacks on
the Office entrance with allies holding a flank. **Set piece:** the motorcycle
run under Notary patrols, barricade jumps and side alleys, the transit station
as the foot route if the bike is lost. **Landmark:** the Office tower at the end
of the avenue, growing the whole way. **Turn:** the parade route the Union built
to march on carries the people coming for it. **New:** Motorcycle. **Route:**
arrow, one directed run with side pockets, then a two-sided forecourt.
**Doors:** 0. **Brief:** A: free the checkpoint prisoners on the transit route.
S: reach the forecourt with the bike. Sv: no Notary gets a photograph (kill
each before its flash completes). **Secret:** a coalition cache behind the
civic fountain. **Par:** 4:00.

**17. Peace Without Interruption** (M09, second half)
The Forever Office: assembly hall, administration ring, command galleries,
security core. **Beat:** reach Voss. Records suggest interests above her and
prove none. Her composure breaks into German; the captions stay accurate.
**Fight:** the security core, local defenses with exposed mechanisms, Denial's
few charges spent where they matter. **Landmark:** the assembly chamber's dome
seen from every gallery. **Turn:** she is captured alive, and an official asks
someone to sign for the confiscated command keys. **New:** Denial (before the
core, taught with charges to spare). **Route:** ascending ring around the
assembly hall, an outer service stair as the runner's line. **Doors:** 3, the
chamber doors, the core seal, and the secured-chamber door. **Brief:** A: free the
administration ring. S: break the core with one Denial charge left. Sv: reach
the galleries by the frontal hall, not the service stair. **Secret:** gallery
supply route behind the committee room's eleven-minute clock. **Par:** 6:00.

### Episode V: Inheritance (Earth, the wipe)

Victory, then the rupture, with almost no warning. Three survival levels, 33
active minutes together. No par; the result shows people helped and damage
taken.

**18. All Systems Normal** (M10, minutes 0 to 10)
Recovery square, clinic route, service passages, overlook. **Beat:** a modest
delivery in a square where people are rebuilding. Then every Union bot stops
together and starts again with one purpose; a supervisor's order gets no answer;
Latch stays Latch. **Fight:** escaping the square as familiar bodies with familiar
tells move as one, then the first Collector closing deliberately on the
obstruction you are standing beside. **Landmark:** the stalled tram in the square.
**Turn:** the enemies you learned are no longer the Union's. **New:** Collector.
**Route:** outward spiral, square to passages to the overlook. **Doors:** 1, the
service passage door, opened from beside it. **Clock:** 10 minutes. **Brief:**
A: get the clinic queue into the passage. S: reach the overlook with full armor.
Sv: disable the Collector during its exposed phase. **Secret:** aid stores behind
the delivery van. The level ends on the scale montage.

**19. Planned Works** (M10, minutes 10 to 21)
Evacuation concourse, then changed Low Water. **Beat:** former Union personnel
help for a moment in the concourse and are not absolved. Low Water's roofs from
level 5 are marked for work. **Fight:** Paver strips across Low Water's streets,
answered by the jetpack over the old roof loop. **Landmark:** the same water tanks
from level 5, now surrounded by marked strips. **Turn:** you came back to the
roofs you escaped over; the ground route still works. **New:** Jetpack (coalition
stores in the concourse); Paver. **Route:** out and back, changed: concourse to
Low Water, the loop run in reverse. **Doors:** 0. **Clock:** 11 minutes. **Brief:**
A: get the concourse crossing clear. S: disable a Paver during preparation.
Sv: take no work-strip damage. **Secret:** Splice's workshop stash, if you know
where the circled six was.

**20. Local Exception** (M10, minutes 21 to 33)
Waterworks, freight pier, refuge approach. **Beat:** free-agent friends work on
the Inheritance for an exception while you keep people alive. A single precise
message acknowledges exactly whom you are saving. **Fight:** the pier, converging
pressure with Surveyors marking positions for nearby machines. **Landmark:** the
freight platform you left from in level 5, now the refuge crossing. **Turn:** the
reprieve lands; the machines stop at your boundary and go on elsewhere. **New:**
Surveyor. **Route:** converging, three short approaches funnel to the pier.
**Doors:** 1, the refuge gate. **Clock:** 12 minutes. **Brief:** A: get the
waterworks crew across. S: break a Surveyor's mark before its machines arrive.
Sv: finish with every rescue from this episode alive. **Secret:** Edda's lamp,
lit, on the pier. Surviving unlocks Still Here.

**Epilogue: Still Here.** Unchanged: the damaged refuge with the people this run
saved, then the same place years later. Freed counts from levels 3, 11 and 15
show up as faces in the refuge, not as a score.

## Research

Kept to rules this plan applies.

- **GoldenEye 007:** 18 main levels plus two unlockable bonus levels; difficulty
  changes the number of objectives, not only damage; beating levels within target
  times unlocks cheats; set pieces (tank, train) punctuate foot levels; designers
  built interesting spaces first and placed starts, exits and objectives after,
  which is why rooms feel real. Two places are revisited changed. Applied: the
  brief, Waivers, spaces-first, the train yard, Low Water revisits.
- **Doom and Doom II:** nine-map episodes with a boss and a secret level; par
  time on the intermission screen; Doom II drops episodes for one run. Romero's
  rules: height with texture change, light and space contrast, reach what you
  see, several secrets per level, revisit areas, recognizable landmarks.
  Applied: episodes, par, rules 1, 7, 8, secrets.
- **Doom 2016 and Eternal:** push-forward combat puts resources in the fight and
  rewards aggression over cover. Applied: rule 3.
- **Half-Life:** set pieces arrive in a regular cadence of two to four combat
  pieces and a change of pace, with through-content like the monorail as
  breathers. Applied: rule 5, the motorcycle run, the rail yard.
- **Ultrakill:** levels of 3 to 15 minutes, each with ranks on time and kills,
  hidden collectibles and one optional challenge that changes play style.
  Applied: rule 11, the brief, par.
- **Dusk, Amid Evil, Prodeus:** modern campaigns built on Romero's non-linear,
  secret-rich levels, short episodes in sharply different settings, and an
  overworld of many short maps. Applied: episode variety and replay by level.

## Sources

Checked 2026-09-24.

- [GoldenEye 007, Wikipedia](https://en.wikipedia.org/wiki/GoldenEye_007)
- [GoldenEye 007 level list, James Bond Wiki](https://jamesbond.fandom.com/wiki/List_of_Levels_of_GoldenEye_007_(1997))
- [Martin Hollis interview, Nintendo Life](https://www.nintendolife.com/news/2016/04/exclusive_martin_hollis_talks_goldeneye_64_development_in_this_new_interview)
- [Tips for creating good WADs, Doom Wiki](https://doomwiki.org/wiki/Tips_for_creating_good_WADs)
- [John Romero's level design rules, I Cast Light](https://icastlight.blogspot.com/2024/01/lessons-from-hell-john-romeros-level.html)
- [Episode, Doom Wiki](https://doomwiki.org/wiki/Episode)
- [Intermission screen, Doom Wiki](https://doomwiki.org/wiki/Intermission_screen)
- [Embracing Push Forward Combat in DOOM, GDC Vault](https://www.gdcvault.com/play/1024940/Embracing-Push-Forward-Combat-in)
- [The combat design of DOOM, Game Developer](https://www.gamedeveloper.com/design/video-the-combat-design-of-i-doom-i-)
- [Reverse Design: Half-Life, The Game Design Forum](http://thegamedesignforum.com/features/rd_hl_1.html)
- [Levels, Official ULTRAKILL Wiki](https://ultrakill.wiki.gg/wiki/Levels)
- [Dusk interview, TechRaptor](https://techraptor.net/content/indie-interview-dusk)
- [Amid Evil review, bit-tech](https://bit-tech.net/reviews/gaming/pc/amid-evil-review/1/)
- [Prodeus levels, Prodeus Wiki](https://prodeus.fandom.com/wiki/Levels)
