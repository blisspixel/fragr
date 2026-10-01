# M02: Persons Unknown

**Appearance anchor for level 2:** Correction rooms: issued steel, bounded fixture light and recognizable processing routes; Latch's restraint and reunion remain the personal focus.
Shared [world direction](../design/earth.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** development graybox (`server/maps/m02-persons-unknown.json`). The
two-Clerk Shotgun introduction, single Crawler, later pack, guarded Latch
release and cross-mission run carry have seeded engineering checks in stacked
drafts. The officer's [upper mezzanine](../plans/m02-floor-gantry.md),
[optional side ward](../plans/m02-side-ward.md) and
[maintenance circulation](../plans/m02-maintenance-circulation.md) are also in
draft review. [Draft #278](https://github.com/blisspixel/fragr/pull/278) moves
the optional captives from that ward to the dock under server authority. The
accepted ten-enemy processing-floor roster is staged in
[draft #279](https://github.com/blisspixel/fragr/pull/279); fresh-player Crawler
and floor balance review remain open. The Jammer first appears in level 3.
Earth before the wipe. Target 10-12 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#level-2-persons-unknown).

The current graybox places the Shotgun on the upper gallery and two initially
seated Clerks in a guard room at the top of the service stair. Their encounter
raises them before the descent. A separate trigger stages one low Crawler on
the lower stair, then another stages three Crawlers with a Sweeper. The server
owns their body, leap and contact; the client has distinct motion and a
captioned spatial scrabble cue. Seeded clears and inspected live motion pass;
fresh-player review still decides whether the introduction is accepted.

The [gallery first-view draft](../plans/m02-gallery-first-view.md) lowers the
window sill enough for the primary standing entry to see Latch and the
restraint frame; the other gallery entries can walk to that view. The sill
stays too high to step through, and the first fight and Crawler descent keep
their authored route. This is an authored view and rendered frame check, not
evidence that a new player recognizes Latch at that distance. The
[Notary observation tableau draft](../plans/m02-notary-tableau.md) now places
one passive drone behind a sealed pane. Its small peripheral silhouette is
visible from the gallery, while fresh-player recognition remains open.

The [natural entry draft](../plans/m02-natural-entry-composition.md) turns the
primary gallery spawn toward that restraint without moving its feet or
changing the window. Its unforced first-person frame and live snapshot check
test the view a participant actually receives before input. The Shotgun and
service stair remain reachable; recognizing Latch is still a fresh-player
question.

## Story and cast

Reach Latch before irreversible correction and rescue them early in the campaign.
They recognize the player in body-neutral dialogue. After a short reunion, Latch
helps release another captive and discovers Low Water on the wider recall list.
They argue for helping others and participate in escape. They are neither a
silent trophy nor a fragile escort whose mistakes constantly fail the mission.

The stacked escape draft gives Latch autonomous behavior after release, with
bounded server-owned support on the processing floor. Their reunion does not
introduce a controllable companion, a required second player or a revive
system. Unsteered player review of that support remains open.

The warning to Mara waits until the level 3 Jammer falls. A Notary drone
photographs captives beyond the gallery glass, out of reach. Its first fight
belongs to level 4.

## Layout

Observation gallery -> guard room -> service stair -> ward antechamber -> correction ward ->
processing floor -> loading exit. A maintenance cut forks after the first
Crawler and rejoins at the antechamber beyond the pack landing. A separate
side-ward return loops around processing machinery after Latch's release.

| Zone | Physical job | Play and character beat |
|---|---|---|
| Gallery and guard room | Windows show the ward and processing machinery below; a small table and chairs interrupt the route to the stair | Player finds the Shotgun and Shells, then wakes two seated Clerks before descending; a Notary drone photographs captives beyond the glass, out of reach |
| Service stair | Enclosed switchback, clear landings, no jump requirement | One Crawler gets a captioned scrabble and a readable leap before three Crawlers mix with a Sweeper on the next landing; fresh-player readability review pending |
| Antechamber | Workroom with cover and a view into the ward | Recover after the stair and read the ward before entering it |
| Ward | Open ward around the restraint frame | Set-piece fight; the correction stops when the guards fall; free Latch |
| Processing floor | Two usable levels with broad stairs and machinery islands | The escape draft puts Latch beside the player; the gantry draft raises the Clerk officer. The ten-enemy roster is staged in three encounters; unsteered player balance review remains open. |
| Service loop | A stair bypass and two approaches to the side ward | The early cut offers a learned route around the pack landing; clear the optional guards and the captives free themselves, then move to the dock after the floor is safe |
| Loading exit | Open dock with the yard in view | Clerk and Sweeper crest, regroup and leave for the rail yard |

Winning the ward is the crest's first half; escaping together is the second.

## Encounters and equipment

Carry M01 inventory. Guaranteed Shotgun, Shells and ordinary health support a
player who missed every secret. Crawlers punish retreating straight down a hall;
the antechamber supplies lateral space. A human officer above the processing
floor creates a priority target without requiring the Railgun.

The dock remains a grounded Clerk and Sweeper fight. The Jammer's first
interference shots belong to level 3's rail yard. Do not introduce the entire
enemy roster here.

Secrets: an armor locker reachable from the gallery loop; a Shiv/replenishment
cache behind a clearly altered service panel. Neither changes the core rescue.

## State and retries

`ward_reached` -> `companion_released` (ward guards defeated, then local Use at
the frame) -> `party_departed` (dock arrival). Ward victory quiets the machine;
the release is a separate authoritative one-time transition.
Optional prisoner groups have distinct released/evacuated states.

The current side-ward draft has one required Use control and a ward-exit
shutter raised by that same release. The ward scene shows Latch freeing another
captive and reading Low Water, then
hands off to the moving server-owned companion for later combat.

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
locomotion and gestures, and an accepted Crawler presentation pass. Captive suffering
is purposeful context, not prolonged spectacle. Institutional announcements can
be absurd while the reunion stays sincere.

## Allies and acceptance

Latch follows a secured-route state machine, keeps passage clear, and appears
once. Ordinary combat cannot kill them or fail the rescue after release. Their
later survival is an authored story outcome. A solo player can finish alone.
Prove idempotent release, mission-start retry before and after rescue, blocked
NPC paths, optional captives, muted audio and the complete solo retreat. Rescue must be understood as success.

## Level 2 design (twenty-level expansion)

**Status:** planned, accepted 2026-09-25. Level 2 of the
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

**Teaches.** The Shotgun, then the Crawler. The Shotgun waits on the upper
gallery before a guard room at the top of the service stair, where two Clerks
sit at a table with their weapons down: point blank, one blast each, an easy
first lesson in seven pellets. The Crawler comes next and alone: a scrabble and
a caption, then one low chassis leaping from the switchback's lower landing,
its wind-up a clear crouch, on a landing wide enough to sidestep. The Shotgun
answers it.

**Shape.**
1. **Arrival.** The observation gallery. Through the glass, below: the ward,
   the restraint frame, and Latch on it. A Notary drifts beyond the glass
   photographing captives, out of reach. The destination is the first thing you
   see.
2. **First fight.** Find the Shotgun on the gallery, then fight in the guard room.
3. **Escalation.** The service stair: the first Crawler, then a pack of three
   on the next landing with a Sweeper firing up the well. Keep space without
   backing into its lane.
4. **Set piece.** The ward. Its exit shutter stays shut through the fight and
   rises when Latch is released.
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

**Doors.** One: the ward exit shutter, closed through the fight and raised by
Latch's release at the existing restraint control.

**Secrets.**
- An armor locker off the gallery loop, the six scratched into its hinge.
- A service panel with the six half painted over by a careless inspector:
  Shells and a Shiv behind it.
- The processing floor's upper gantry ledge, reached by a readable jump from
  the stair: a medkit and a sightline down onto the crest.

**Optional challenge ideas, not active objectives.** Freeing the side ward,
clearing the upper gantry and stopping the Crawler pack before the landing may
become named challenges later. The side ward remains optional on Assisted,
Standard and Severe. No tier adds a required rescue or changes the ward release
and dock departure chain.

**Par and the runner's line.** 4:30. The maintenance cut after the lone Crawler
skips the pack landing and rejoins at the antechamber. The side ward has a
separate return opening onto the processing floor. Both routes still pass
through Latch's release and the ward exit shutter.

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
