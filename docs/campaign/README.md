# Mission plans

Detailed level plans for ten campaign missions and a conditional epilogue. M01 has a tested development
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
| M10 | Earth, sudden wipe and substantial survival finale | [All Systems Normal](m10-all-systems-normal.md) |
| Epilogue | Survival unlocks immediate aftermath and years-later healing | [Still Here](epilogue-still-here.md) |

The former [M11](m11-what-we-can-carry.md) and [M12](m12-still-here.md) briefs are
explicitly superseded staging references, not additional missions to implement.

## Shared authoring contract

Each brief is a design to prove, not a fixed coordinate prescription. Room IDs
support discussion and later data authoring; proposed state names are not existing
wire fields. Review the graph and encounter rhythm before grayboxing. Geometry
uses actual server movement, collision and the supported map representation.

Target 2-3 hours for a successful run, including the substantial M10 finale and
short epilogue. The initial survival target is about 33 active minutes. Budgets are
provisional and need fresh-player evidence. A limited continue restarts the current
mission with its entry equipment and world state; no mid-mission death checkpoint.
The [run contract](../CAMPAIGN.md#runs-and-continues) owns allowance and persistence
rules. Replay cannot overwrite the main run silently.

Build each mission around one playable character. Viewpoints may differ across
missions; exact assignments remain to be authored. Optional autonomous allies do
not imply companion controls, revives or mandatory co-op. Allies must not block
routes; death removes them for the mission attempt. People
move after routes are secured; no escort chores. Each plan follows the
[pillar](../VISION.md#easy-to-pick-up-deep-to-master): at most three doors,
each switch beside its door, and a planned par time and runner's line. Irreversible
departures require player confirmation with remaining rescue opportunities visible.

Use stable actor/story IDs, localized objective and caption keys, optional audio,
and world-visible consequences. Scene skipping never executes game logic twice.
Muted radio and absent voice preserve every essential fact. Recordings, diagrams,
and procedural brief generation do not establish that a mission is fun.

Every final brief needs: solo human/agent playthroughs; relevant rescue and ally
states; continue/exhaustion/save tests; agent-observable objectives; spectator eye
views; actual first-person motion in both renderer paths; fresh-player navigation
and comprehension observations. Store receipts when earned, not placeholder PASS.

## Content acceptance order

1. Story/cast/route review, including unresolved consequential choices.
2. Collision-correct graybox, playable objectives, exits and encounter pacing.
3. Complete weapon/enemy behaviors, inventory, mission retry and ally cases.
4. Full art, animation, effects, sound and localized scene integration.
5. Mechanical checks, inspected play, fresh-player review, revisions and release.

No further mission is called finished because it reuses the first mission's kit.
The [implementation plan](../plans/campaign-build-order.md) controls sequencing.
