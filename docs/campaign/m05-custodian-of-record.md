# M05: Custodian of Record

**Status:** proposed, unbuilt. Moon before the wipe. Target 10-14 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#level-8-custodian-of-record).

## Story and people

Latch refuses to take records while leaving their subjects behind. Auditor Renn,
a human custody officer, offers practical help after the party reaches the archive.
Their information is useful but is checked against what the player sees. One act
of assistance does not erase participation in the system. Tern prepares space on
the transport. Mara needs evidence and people, not a universal mind-unlock code.

Orrin is an optional recoverable agent backup. Its physical condition and missing
records establish fragility now; later restoration will not restore everything.
No character knows the Inheritance's origin. An unrequested cargo reroute helps
the escape, initially explainable as a local error or another person's assistance.

Proposed signal beat: the freight diagnostics briefly repeat a timing pattern
beneath ordinary traffic. A maintenance notice reads "Authorized noise. No action
required." The joke targets institutional certainty. No character identifies an
intelligence here; the [signal contract](../lore/the-inheritance.md#signal-beneath-the-noise)
keeps this incidental, visible with sound muted, and separate from optional radio.

## Room graph

Entry checkpoint -> circular records hall -> two custody galleries -> machinery
bridge -> inspection workshop -> freight evacuation. A cooling/service ring links
the galleries and creates a shorter return. The M04 prisoner route, if marked, joins
this ring; the normal entrance works without it.

| Zone | Architectural function | Encounter or character beat |
|---|---|---|
| Records hall | Human-facing desks around a visible shaft | Show how a person becomes a registered asset; establish destination |
| Lower gallery | Open bays and a side alcove | Meet Renn after clearing a local threat |
| Upper gallery | Custody platforms with broad stairs and cover | First actual combat Auditor, bounded reactivation mechanic |
| Service ring | Cooling passages looping back to the hall | Optional Orrin recovery with room for withdrawal |
| Machinery bridge | Overlooks a machinery floor, two approaches | Main crest: shoot apart the custody-defense machine under pressure |
| Workshop | Opened restraints and body maintenance | Free agents make their own choices and stage for transport |
| Freight exit | Cargo route back toward the port | Visible evacuation state and regroup |

## Combat and equipment

Teach the Auditor in one readable encounter before the machinery crest. Its
channel is visible and interruptible; it repairs disabled units under a hard
limit, not genuinely resurrected people. Human elites guard it from distinct
positions while Sweepers pressure the lower loop.

Introduce proximity mines before a converging-route fight: they stick, arm
with a visible tell, and detonate when a body comes close. The rocket launcher
waits for M08, where there is room for splash. A Railgun or secret weapon is
never required.
Breakable machinery is visibly different from invulnerable walls and provides
safe attack windows.

Secrets: armor reached through the cooling loop; an early Repeater with limited
ammo in an observation cage. The weapon does not appear as an essential reward
for choosing people over records. Guaranteed ammunition supports all required
enemies plus the machinery without perfect accuracy.

## Objectives and state

Required: beat the upper-gallery Auditor (its fall frees the bays), wreck the
custody machine, grab the transfer evidence on the way out and reach the freight
exit. Objective lines: "Beat the Auditor", "Wreck the machine", "Get out". The
evidence identifies Martian industry and common systems used by several sides.
It does not prove a hidden cabal or explain the AGI.

Track `custody_released`, `transfer_evidence`, `custodian_joined`, and optional
`recovered_mind_secured`. Orrin's recovery is a physical, vulnerable archive with
known incompleteness. Do not label it a guaranteed living person until restoration
has occurred. Local captives have release and evacuation states separately.

A continue returns to mission entry. Replaying release must not duplicate people,
memories, inventory or story events. If the
M04 prisoner route is absent, the ordinary evacuation remains achievable.

## Staging and tone

Record bays, inspection hardware and densely labeled Union panels contrast with
individual repairs and possessions. Renn's face/stance shows discomfort without
asking the player to forgive them. Latch can mock a form asking a captive whether
their recall inconvenienced the service. Keep the captives themselves sincere.

## Allies and proof

Rescued actors stage outside active crossfire after routes clear; no tactical
companion commands are required.

Mastery hooks, planned, not built: a par time on the result, the service ring as
the runner's line between galleries, and best clear time in the service record.
Test both M04 prisoner-route states, Orrin recovered/missed, reactivation limits,
pickup scarcity, repeated releases, save with the archive, scene skips and
mission-start retry. Inspect all overlapping floors.

## Level 8 design (twenty-level expansion)

**Status:** planned, accepted 2026-09-25. Level 8 of the
[twenty-level expansion](../plans/campaign-expansion.md), the same mission.
[Story arc](story-arc.md).

| Episode | Place | New | First run | Par | Doors |
|---|---|---|---|---|---|
| II Custody | The radial custody archive | Proximity Mine; Auditor | 13 min | 5:30 | 1 |

**Premise.** The depot registers people as stock and ships them where the
Union needs hands. Some of Low Water is in the lower bays (**proposal**). Latch
refuses to take the transfer evidence and leave its subjects behind, and this
time Latch being right costs time and blood. Renn, an Auditor who has started
to disbelieve the forms, helps and is not forgiven for it.

**Hook.** Jailbreak a round prison built around a shaft, then shoot its custody
machine apart until it falls through every floor.

**Teaches.** The Proximity Mine, then the Auditor. The mines sit in a lower
gallery equipment cage beside a side alcove with one entrance. Two Sweepers
patrol toward it on a fixed loop: stick a mine on the frame, watch it arm and
blink, step back, and let them walk in. The Auditor is taught in one readable
encounter in the upper gallery: a human officer with a shield plate and three
Sweepers. When a Sweeper drops, the Auditor raises its hand and a visible
repair channel reaches the body; hit the Auditor or break line of sight and the
channel snaps. It can repair twice, never a third time.

**Shape.**
1. **Arrival.** The entry checkpoint. If level 6's prisoner route was marked,
   a side door on the service ring is already open.
2. **First fight.** The records hall: human-facing desks around the central
   shaft, Clerks and Sweepers, the galleries stacked above you.
3. **Escalation.** The lower gallery and the mine lesson. Renn, after the
   local guards fall, lowers a registry case and offers the layout.
4. **Set piece.** The upper gallery. The seal drops for the Auditor fight and
   lifts when the Auditor falls, and the bays unlock with it.
5. **Breath.** The service ring: cooling pipes, a quiet loop, Orrin's damaged
   backup in a cold cabinet. Latch and Renn argue about the lower bays. Latch
   wins by walking toward them.
6. **Climax.** The machinery bridge. The custody machine hangs in the shaft on
   four glowing support nodes; shoot them apart while a second Auditor repairs
   the Sweepers below and Clerks hold the far approach. The last node goes and
   the machine drops through every gallery to the floor of the shaft.
7. **Turn.** The evidence on the bridge desk points at Mars and at systems
   several sides built. An empty freight car rolls up to the loading lane that
   nobody called. The panel above it reads *Authorized noise. No action
   required.*, with a repeating rhythm under the text.
8. **Exit.** A counterattack from both gallery stairs toward the freight lane,
   mines on the converging stairs, then ride the car to the berth.

**Landmarks and sightlines.** The central shaft of stacked galleries, visible
from every floor; the custody machine in it until you drop it. The freight
lane's lights below the bridge, which is the exit.

**Doors.** One: the upper gallery seal for the Auditor fight.

**Secrets.**
- Armor through the cooling loop, the six on a pipe junction.
- An early Repeater with limited Bullets in an observation cage over the
  records hall, reached along a desk-top route marked with a six.
- The records hall's lost-property cage: Shells and a medkit, and a pile of
  confiscated jackets, one of them with the six sewn on its back.

**Brief.** Assisted: recover Orrin's backup. Standard adds: release the lower
bays. Severe adds: break the Auditor's channel before any repair completes.

**Par and the runner's line.** 5:30. The service ring between galleries, the
bridge nodes from the far side, the car.

**Story in play.** Page in: "The custody depot. An hour later. The archive
turns people into stock and ships them where the Union needs hands. Some of
Low Water is in here. Beat the Auditor. Open the bays." Renn's lines are few
and exact ("Upper gallery. The Auditor there believes it.") The lower bays hold
faces from level 4's market; they walk out, and some of them walk to the
freight lane with you.

**Humor.** A form on every bay door asks the captive whether their recall
inconvenienced the service, from *not at all* to *greatly*. Latch ticks
*greatly* on every one as they pass.

**The moment.** The custody machine falling down the shaft through all the
galleries, and then an empty car arriving that nobody sent.
