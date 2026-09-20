# M02: Persons Unknown

**Status:** proposed, unbuilt. Earth before the wipe. Target 15-20 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#m02-persons-unknown).

## Story and cast

Reach Latch before irreversible correction and rescue them early in the campaign.
They recognize the player in body-neutral dialogue. After a short reunion, Latch
helps release another captive and discovers Low Water on the wider recall list.
They argue for helping others and participate in escape. They are neither a
silent trophy nor a fragile escort whose mistakes constantly fail the mission.

The resistance partner introduced in M01 is a different recurring character.
Latch's reunion preserves that continuity; it does not silently replace the
partner or duplicate a combat seat. Solo and custom co-op tell the same rescue.

Mara receives the warning at departure. An Auditor oversees the facility through
screens or an inaccessible gallery; this does not require a boss fight yet.

## Layout

Observation gallery -> service stair -> ward antechamber -> correction ward ->
processing floor -> loading exit. A maintenance loop connects the antechamber
to the floor and opens back to the gallery after release.

| Zone | Physical job | Play and character beat |
|---|---|---|
| Gallery | Windows show the ward and processing machinery below | Player sees a destination and evidence of coercion before fighting |
| Service stair | Enclosed switchback, clear landings, no jump requirement | Introduce Crawler sounds/captions, then a small visible pack |
| Antechamber | Workroom with cover and a view into the ward | Find Scatter before the close encounter; checkpoint |
| Ward | Release console beside a clearly connected restraint bay | Fight guards, stop the correction process, free Latch |
| Processing floor | Two usable levels with broad stairs and machinery islands | Latch opens a local path; mixed threats pressure escape |
| Service loop | Optional release bays and supplies | Free other captives; stage them safely after combat |
| Loading exit | Jammed gate with visible local equipment | Disable Jammer, regroup and leave for home |

Opening the ward is the crest's first half; escaping together is the second.
The geometry changes through visible opened routes, not walls silently respawning.

## Encounters and equipment

Carry M01 inventory. Guaranteed Scatter, Darts and ordinary health support a
player who missed every secret. Crawlers punish retreating straight down a hall;
the antechamber supplies lateral space. A human officer above the processing
floor creates a priority target without requiring the Rail.

The Jammer has visible antenna/pulse and projectile tells. Its effect is a local
release gate, not loss of optional music. Damaging or reaching its exposed circuit
is possible with guaranteed guns. Do not introduce the entire enemy roster.

Secrets: an armor locker reachable from the gallery loop; a Shiv/replenishment
cache behind a clearly altered service panel. Neither changes the core rescue.

## State and checkpoints

`ward_reached` -> `correction_stopped` -> `companion_released` ->
`loading_gate_open` -> `party_departed`. Latch's release is an authoritative
one-time transition. Optional prisoner groups have distinct released/evacuated
states; opening a bay does not automatically claim a safe evacuation.

Checkpoint before the ward and after the reunion in secured space. Retry restores
the correct actor and restraint state. No timer runs through a cutscene, pause,
loading screen or disconnected party. Any visible correction countdown begins
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

## Co-op and acceptance

Latch follows a secured-route state machine, keeps passage clear, and appears
once regardless of party size. A solo player can operate every gate. Disconnecting
the releasing player cannot interrupt the rescue forever. Prove simultaneous
release attempts, all checkpoint phases, blocked NPC paths, optional captives,
muted audio, and a full four-player retreat. Rescue must be understood as success.
