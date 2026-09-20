# Mission plans

Detailed level plans for the twelve-mission campaign. M01 has a tested development
slice; no complete mission has reached the design's quality gate. The
[campaign contract](../CAMPAIGN.md) distinguishes confirmed story
from proposals; the [treatment](../CAMPAIGN-MISSIONS.md) gives the complete arc.
This directory owns room sequence, cast staging, encounter beats and mission
state proposals. Working names are defined in [cast](../lore/cast.md).
The [art bible](../ART_STORY_BIBLE.md#factions-places-and-continuity) owns shared
faction and environment rules; [character anchors](../lore/cast.md#visual-continuity)
persist through every mission and scene. Mission briefs describe local staging,
not independent redesigns of those assets.

| Mission | Place and purpose | Detailed plan |
|---|---|---|
| M01 | Earth intake, begin the personal rescue | [Recall Notice](m01-recall-notice.md) |
| M02 | Earth correction, free the companion early | [Persons Unknown](m02-persons-unknown.md) |
| M03 | Home district, evacuate before wider recall | [No Forwarding Address](m03-no-forwarding-address.md) |
| M04 | Lunar port, enter the custody network | [Port of Entry](m04-port-of-entry.md) |
| M05 | Lunar archive, free captives and obtain evidence | [Custodian of Record](m05-custodian-of-record.md) |
| M06 | Transport, survive boarding with rescued people | [Common Carrier](m06-common-carrier.md) |
| M07 | Mars habitat, experience delayed cooperation | [Terms of Cooperation](m07-terms-of-cooperation.md) |
| M08 | Mars industry, mobilize the coalition | [The Weight of Permission](m08-weight-of-permission.md) |
| M09 | Earth command, defeat the Union | [Peace Without Interruption](m09-peace-without-interruption.md) |
| M10 | Earth, sudden wipe and expanding comprehension | [All Systems Normal](m10-all-systems-normal.md) |
| M11 | Changed home, rescue after the initial wipe | [What We Can Carry](m11-what-we-can-carry.md) |
| M12 | Refuge route, survival and years-later coda | [Still Here](m12-still-here.md) |

## Shared authoring contract

Each brief is a design to prove, not a fixed coordinate prescription. Room IDs
support discussion and later data authoring; proposed state names are not existing
wire fields. Review the graph and encounter rhythm before grayboxing. Geometry
uses actual server movement, collision and the supported map representation.

Normal campaign saves carry inventory and survivor outcomes. Checkpoints snapshot
the authoritative party state. A retry returns to that snapshot, including people,
doors, pickups and interactions. Replay cannot overwrite the main run silently.
Melee-start replay is a labeled challenge, not a surprise reset between missions.

One to four combatants share objectives and keys. Required gates work solo.
Companions do not body-block, teleport visibly through sealed doors, or create
four copies on four-player runs. People move after routes are secured; avoid
fragile walking-escort chores. Irreversible departures require an explicit party
leader confirmation with remaining rescue opportunities visible.

Use stable actor/story IDs, localized objective and caption keys, optional audio,
and world-visible consequences. Scene skipping never executes game logic twice.
Muted radio and absent voice preserve every essential fact. Recordings, diagrams,
and procedural brief generation do not establish that a mission is fun.

Every final brief needs: one-player and four-player playthroughs; relevant rescue
states; join/leave/retry/save tests; agent-observable objectives; spectator eye
views; actual first-person motion in both renderer paths; fresh-player navigation
and comprehension observations. Store receipts when earned, not placeholder PASS.

## Content acceptance order

1. Story/cast/route review, including unresolved consequential choices.
2. Collision-correct graybox, playable objectives, exits and encounter pacing.
3. Complete weapon/enemy behaviors, inventory, checkpoint and co-op cases.
4. Full art, animation, effects, sound and localized scene integration.
5. Mechanical checks, inspected play, fresh-player review, revisions and release.

No further mission is called finished because it reuses the first mission's kit.
The [implementation plan](../plans/campaign-build-order.md) controls sequencing.
