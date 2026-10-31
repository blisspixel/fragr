# Level 8: Custodian of Record

**Appearance anchor for level 8:** Sheltered custody archive: records machinery and personal remnants; evidence and captivity occupy one recognizable institution.
Shared [world direction](../design/moon.md) and
[character, voice and scene continuity](../design/characters.md) govern assets
and staging. This anchor is a production target, not finished-appearance evidence.

**Status:** a playable development mission on main (map 1008,
`server/maps/m08_custodian_of_record.json`) built per the level 8 design below
([plan](../plans/l08-custodian-of-record-prototype.md)), dressed toward the
golden slice in wave 16 ([below](#golden-slice-dressing-wave-16)). Fresh-player
and difficulty acceptance are open. Moon before the wipe. Target 10-14 minutes.
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

**Status:** accepted 2026-09-25; built as a development prototype. Level 8 of the
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

## Golden-slice dressing (wave 16)

`client/scripts/m08_dressing.gd` raises the built route toward the Recall
Notice bar the way the port's and the town's dressing do, and reuses their
helpers: every piece is a flush fitting, a small possession against a wall or
on a top, a run overhead or practical light, and the server's solids are
unchanged. `M08Archive` owns one `M08Dressing` that outlives a re-sent map:
the server re-sends MapInfo when the seal lifts and again when the machine
falls, so the layout guard keys only on walls that never move (the checkpoint
wall, the archive's ring walls, both stair towers, the freight lane's end wall
and the registry desk), and the seal, the machine and its nodes are never keys.

The archive has its own face. The port is issued bone-grey shell and cargo
light and the town is lived paint under curfew floods; the archive is an old
institution. `M08Dressing.restyle_archive` paints its walls in institutional
green-grey enamel with a green dado band at every deck under a brass pinline
that never glows, lays green linoleum on the hall floor and both gallery decks
over dark coffered ceilings, and gives the desks olive steel with linoleum
tops. Rails and shaft screens are galvanised steel, stairs and platforms are
issued steel with ochre nosing, the cooling columns are pale frosted steel and
the custody machine is dark issued steel whose nodes carry the only hot light.
The checkpoint is the Union's colder enamel and the freight lane bare concrete.
The black-and-red `service_steel` that striped every rail, stair and screen in
glowing red is gone. `ArenaSky.custodian_of_record()` has no sun: the archive
is lit where people sit by green-shaded pendants with warm pools, while the
Union's cold issued fixtures hang over intake, the custody platforms, the
cooling ring, the shaft and the freight lane.

Evidence and captivity share the building, told in objects. The hall's outer
walls are runs of four-drawer olive cabinets, a card and a brass pull on every
drawer, a few left open. Between the runs hang register boards: rows of small
cards, each a portrait square and the same red stamp. Every desk carries a
terminal with a warm phosphor face, trays of forms, a stamp rack and a card
file, and brass pneumatic tubes run round the ceiling and drop to each desk.
Intake has painted queue lanes and stand-here marks, a rack of blank forms,
two black banners with the red seal and a camera over the hall opening, and
confiscation bins along the wall, each full of somebody's bags under a red
destruction tag. Lost property keeps tagged bags on shelves, boots, an
instrument case and a child's toy blocks. The lower gallery is open steel
shelving of archive boxes. The bays hold fold-down bunks on chains, each with
a folded blanket, a cup and shoes, beside open restraint frames upstairs. The
mine cage has a wire front over its rack, crates of charges, a work lamp and a
hazard band at the alcove mouth; the corridor is evenly lit so a stuck charge
and its lamp read. The cooling ring carries pipe runs, feeds, valve wheels,
frost and drip trays; the bridge desk has the transfer files and a foundry
crate. Gantry beams carry the machine's chain. The freight lane has rails to a
dark portal where the car came in, chevrons at the boarding line and bundles
where the released wait. The four held people are individuals on the live
bodies, one human and three agents, each in their own clothes or plates (moss
jacket, terracotta, plum, denim blue) and height, facing out of their bays.
Renn wears the human body in the issued black coat with the red and rank
removed, behind the desk and facing the party. Both are `CastPaint` schemes
baked from existing art; neither is Renn's own model yet.

**Signal beat.** The noise panel is a maintenance screen over the car. Its
line, "Authorized noise. No action required.", is on screen in warm phosphor
whether or not anything can be heard, with three short ticks and one long
under it; the existing lamp blinks that rhythm once the evidence is taken.

**Signs.** Eight readable signs, the level budget, counted with
`tools/audit_world_signs.gd`: `REGISTRY`, `LOWER BAYS / RELEASE`, `PROXIMITY
CHARGES`, `RECOVERED MINDS / KEEP COLD`, `FOUNDRY TRANSFERS`, `CUSTODY SHAFT`,
`FREIGHT / BERTH LANE` and the authorized-noise screen. The intake and bay
forms are pinned papers, not readable copy, and the three sixes are marks.
The dressing adds only the screen's line, which the reduced-signage pass had
hidden.

`client/qa/m08-golden.json` frames every beat on the route from a spectator
camera; `m08-golden-guards.json` wakes the records hall and frames its Clerks
and Sweepers against the cabinets and pendants. Later groups are chained
behind earlier clears, so the Auditor, the Sweepers it repairs and the mine
lesson are read through the combat route in `client/qa/m08_custodian_of_record.json`.
`client/scripts/test_m08_dressing.gd` holds the guard through both re-sent
stages, the light and faction-colour rules and the surface roles.

