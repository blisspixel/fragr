# M02: Persons Unknown

**Status:** development graybox (`server/maps/m02-persons-unknown.json`): an open route with three Clerk and Sweeper fights and two arrival objectives. Story, Latch as an actor, the Jammer and Crawlers are unbuilt. Earth before the wipe. Target 10-12 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#m02-persons-unknown).

## Story and cast

Reach Latch before irreversible correction and rescue them early in the campaign.
They recognize the player in body-neutral dialogue. After a short reunion, Latch
helps release another captive and discovers Low Water on the wider recall list.
They argue for helping others and participate in escape. They are neither a
silent trophy nor a fragile escort whose mistakes constantly fail the mission.

Latch acts autonomously after release. Their reunion does not introduce a
controllable companion, a required second player or a revive system.

Mara receives the warning at departure. An Auditor oversees the facility through
screens or an inaccessible gallery; this does not require a boss fight yet.

## Layout

Observation gallery -> service stair -> ward antechamber -> correction ward ->
processing floor -> loading exit. A maintenance loop connects the antechamber
to the floor and the gallery.

| Zone | Physical job | Play and character beat |
|---|---|---|
| Gallery | Windows show the ward and processing machinery below | Player sees a destination and evidence of coercion before fighting; a Notary drone photographs captives beyond the glass, out of reach |
| Service stair | Enclosed switchback, clear landings, no jump requirement | Introduce Crawler sounds/captions, then a small visible pack |
| Antechamber | Workroom with cover and a view into the ward | Find the Shotgun before the close encounter; recovery supplies |
| Ward | Open ward around the restraint frame | Set-piece fight; the correction stops when the guards fall; free Latch |
| Processing floor | Two usable levels with broad stairs and machinery islands | Latch fights beside us; mixed threats pressure escape |
| Service loop | Optional captives and supplies | Clear the guards and the captives free themselves |
| Loading exit | Open dock with the transport in view | Kill the Jammer, regroup and leave for home |

Winning the ward is the crest's first half; escaping together is the second.

## Encounters and equipment

Carry M01 inventory. Guaranteed Shotgun, Shells and ordinary health support a
player who missed every secret. Crawlers punish retreating straight down a hall;
the antechamber supplies lateral space. A human officer above the processing
floor creates a priority target without requiring the Railgun.

The Jammer has visible antenna/pulse and projectile tells. It guards the dock
with traveling interference shots and dies to guaranteed guns. Do not introduce
the entire enemy roster.

Secrets: an armor locker reachable from the gallery loop; a Shiv/replenishment
cache behind a clearly altered service panel. Neither changes the core rescue.

## State and retries

`ward_reached` -> `companion_released` (ward fight won) -> `party_departed`
(dock arrival). Latch's release is an authoritative one-time transition.
Optional prisoner groups have distinct released/evacuated states.

The current graybox has no switches or gates and two objectives. It advances
`companion_released` by arriving at the restraint frame ("Find Latch") until
an objective can complete on a won fight, then "Get out" on the dock.

Mastery hooks, planned, not built: a par time on the result, the maintenance
loop as the runner's line, and best clear time in the service record.

Spending a continue returns to mission entry, including Latch's original restraint
state and the player's starting equipment. No timer runs through a cutscene, pause
or loading screen. Any visible correction countdown begins
only where the player can act and supports a fair retry.

## Scene, voice and art

Short in-engine reunion with readable body language. Proposed emotional beat:
the player offers escape; Latch looks toward another occupied bay first. Text
and optional speech carry the same meaning. Do not settle the friend/partner
relationship with gendered or romantic lines before that wording is approved.

Need ward machinery, restraints, active/inactive release states, companion
locomotion and gestures, Crawler set and Jammer projectiles. Captive suffering
is purposeful context, not prolonged spectacle. Institutional announcements can
be absurd while the reunion stays sincere.

## Allies and acceptance

Latch follows a secured-route state machine, keeps passage clear, and appears
once. Ordinary combat cannot kill them or fail the rescue after release. Their
later survival is an authored story outcome. A solo player can finish alone.
Prove idempotent release, mission-start retry before and after rescue, blocked
NPC paths, optional captives, muted audio and the complete solo retreat. Rescue must be understood as success.

## Level 2 design (twenty-level expansion)

**Status:** proposed, 2026-09-25. Level 2 of the
[twenty-level expansion](../plans/campaign-expansion.md). The Jammer moves to
[level 3](l03-scheduled-service.md); the loading dock becomes a Clerk and
Sweeper crest. [Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| I Recall | Correction ward, Earth | Shotgun; Crawler | 11 min | 4:30 | 1 |

**Premise.** The lift only runs down. Below the intake annex is the ward where
correction happens, and Latch is on the frame. Get there before it finishes.

**Hook.** Fight down into the worst room in the building and pull your friend
off the machine with its guards still firing.

**Teaches.** The Shotgun, then the Crawler. The Shotgun waits in a guard room
at the top of the service stair, where two Clerks sit at a table with their
weapons down: point blank, one blast each, an easy first lesson in seven
pellets. The Crawler comes next and alone: a scrabble and a caption, then one
low chassis leaping from the switchback's lower landing, its wind-up a clear
crouch, on a landing wide enough to sidestep. The Shotgun answers it.

**Shape.**
1. **Arrival.** The observation gallery. Through the glass, below: the ward,
   the restraint frame, and Latch on it. A Notary drifts beyond the glass
   photographing captives, out of reach. The destination is the first thing you
   see.
2. **First fight.** The guard room and the Shotgun.
3. **Escalation.** The service stair: the first Crawler, then a pack of three
   on the next landing with a Sweeper firing up the well. Keep space without
   backing into its lane.
4. **Set piece.** The ward. The seal drops behind you for this fight only.
   Sweepers from the bays, Clerks on the gallery above, Crawlers from the floor
   vents, the frame between you and all of them. The machine stops when its
   guards fall. No countdown.
5. **Turn.** The reunion, in engine, under thirty seconds. Latch's first act,
   before they speak to you, is opening the next restraint. Then they read the
   transfer list on the frame's screen: Low Water, next.
6. **Breath.** The side ward on the maintenance loop, optional: captives who
   free themselves once their guards are down.
7. **Climax.** The processing floor, two levels of machinery islands, Latch
   fighting beside you, a human officer on the upper gantry as the priority
   target. Four Sweepers, four Clerks, a last Crawler pair.
8. **Exit.** The loading dock and the open door to the yard. "Get out."

**Landmarks and sightlines.** The restraint frame, seen from the gallery before
the first shot. The gallery glass from below, where you stood a minute ago.
The dock's daylight at the end of the processing floor.

**Doors.** One: the ward seal, down for its fight and up when it is won.

**Secrets.**
- An armor locker off the gallery loop, the six scratched into its hinge.
- A service panel with the six half painted over by a careless inspector:
  Shells and a Shiv behind it.
- The processing floor's upper gantry ledge, reached by a readable jump from
  the stair: a medkit and a sightline down onto the crest.

**Brief.** Assisted: free the side ward. Standard adds: clear the processing
floor's upper gantry. Severe adds: stop the Crawler pack before it reaches the
stair landing.

**Par and the runner's line.** 4:30. The maintenance loop from the antechamber
to the floor, skipping the stair's second landing.

**Story in play.** Page in: "The correction ward, under the same building.
Minutes, not hours. The lift only runs down. Latch is on the frame. Find
Latch." The ward PA speaks in a soft voice. Latch's first line after the
reunion pays off the ledger: "That's four. Don't let it go to your head."
Then, reading the list: "That's our street." Latch's barks through the floor
fight are short and practical ("Left. Gantry.").

**Humor.** The ward PA: "Please remain still. Stillness assists your comfort."
Latch, freed, to you: "Took you long enough." The captives are never the joke.

**The moment.** The frame stops, the room goes quiet, and Latch opens somebody
else's restraint before they say hello.
