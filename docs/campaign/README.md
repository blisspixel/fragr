# Mission plans

Detailed level plans for twenty campaign levels in five episodes and a
conditional epilogue, accepted 2026-09-25 as the contract (formerly ten
missions and a conditional epilogue). Level 1 (M01) has a tested development
slice; no complete level has reached the design's quality gate. The
[campaign contract](../CAMPAIGN.md) distinguishes confirmed story
from proposals and owns the twenty-level table; the [treatment](../CAMPAIGN-MISSIONS.md)
gives the complete arc.
This directory owns room sequence, cast staging, encounter beats and mission
state proposals. Working names are defined in [cast](../lore/cast.md).
The [art bible](../ART_STORY_BIBLE.md#factions-places-and-continuity) owns shared
faction and environment rules; [character anchors](../lore/cast.md#visual-continuity)
persist through every level and scene. Mission briefs describe local staging,
not independent redesigns of those assets.

Ten of the twenty levels keep a former mission's name and number (1, 2, 5, 6,
8, 10, 12, 13, 17, 18); their full design is a section at the end of that
mission's plan. The other ten are new levels with their own `lNN` files. The
[expansion plan](../plans/campaign-expansion.md#how-the-ten-become-twenty) keeps
the full mapping from the old ten missions to the new twenty levels, and the
research behind the split.

| # | Level | Episode | Place and purpose | Detailed plan |
|---|---|---|---|---|
| 1 | Recall Notice | I Recall | Earth intake, begin the personal rescue | [m01](m01-recall-notice.md#level-1-design-twenty-level-expansion) |
| 2 | Persons Unknown | I Recall | Earth correction, free the companion early | [m02](m02-persons-unknown.md#level-2-design-twenty-level-expansion) |
| 3 | Scheduled Service | I Recall | Perimeter rail yard, silence the jamming and free the recall cars | [l03](l03-scheduled-service.md) |
| 4 | Notice to Vacate | I Recall | Low Water market and clinic, defend home before the sweep | [l04](l04-notice-to-vacate.md) |
| 5 | No Forwarding Address | I Recall | Low Water roofs and tram trench, evacuate before wider recall | [m03](m03-no-forwarding-address.md#level-5-design-twenty-level-expansion) |
| 6 | Port of Entry | II Custody | Lunar port, enter the custody network | [m04](m04-port-of-entry.md#level-6-design-twenty-level-expansion) |
| 7 | Declared Goods | II Custody | Lunar town and crater cut, cross curfew ground to the depot | [l07](l07-declared-goods.md) |
| 8 | Custodian of Record | II Custody | Lunar archive, free captives and obtain evidence | [m05](m05-custodian-of-record.md#level-8-design-twenty-level-expansion) |
| 9 | Passenger Manifest | II Custody | Lunar launch berth, take back the ship | [l09](l09-passenger-manifest.md) |
| 10 | Common Carrier | III Common Cause | The ship, survive boarding with rescued people | [m06](m06-common-carrier.md#level-10-design-twenty-level-expansion) |
| 11 | Right of Search | III Common Cause | The Union's custody tender, board the boarders | [l11](l11-right-of-search.md) |
| 12 | Terms of Cooperation | III Common Cause | Martian habitat, experience delayed cooperation | [m07](m07-terms-of-cooperation.md#level-12-design-twenty-level-expansion) |
| 13 | The Weight of Permission | III Common Cause | Martian foundry, win the means to break the blockade | [m08](m08-weight-of-permission.md#level-13-design-twenty-level-expansion) |
| 14 | Launch Authority | III Common Cause | Martian launch works, mobilize the coalition | [l14](l14-launch-authority.md) |
| 15 | Civic Pressure Valve | IV Reckoning | The sanctioned games stadium, arm the uprising | [l15](l15-civic-pressure-valve.md) |
| 16 | Freedom of Movement | IV Reckoning | The ceremonial avenue, ride for the Office | [l16](l16-freedom-of-movement.md) |
| 17 | Peace Without Interruption | IV Reckoning | Earth command, defeat the Union | [m09](m09-peace-without-interruption.md#level-17-design-twenty-level-expansion) |
| 18 | All Systems Normal | V Inheritance | Earth, the sudden wipe begins | [m10](m10-all-systems-normal.md#level-18-design-twenty-level-expansion) |
| 19 | Planned Works | V Inheritance | Concourse and changed Low Water, the dark night | [l19](l19-planned-works.md) |
| 20 | Local Exception | V Inheritance | Waterworks and pier, survive to the reprieve | [l20](l20-local-exception.md) |
| E | Still Here | Epilogue | Survival unlocks immediate aftermath and years-later healing | [epilogue](epilogue-still-here.md#in-the-twenty-level-expansion) |

The [story arc](story-arc.md) tells the whole run as one story: the player's
want and need, Latch's arc and the ledger, the Union's faces, the Inheritance's
signs, the midpoint reversal, both endings, and how the story is told without
stopping play. It stays a proposal; nothing in it contradicts the
[campaign contract](../CAMPAIGN.md).

## Shared authoring contract

Each brief is a design to prove, not a fixed coordinate prescription. Room IDs
support discussion and later data authoring; proposed state names are not existing
wire fields. Review the graph and encounter rhythm before grayboxing. Geometry
uses actual server movement, collision and the supported map representation.

Target about four hours for a successful run, including the substantial wipe
finale (levels 18 to 20) and short epilogue. The initial survival target is
about 33 active minutes, split across those three levels. Budgets are
provisional and need fresh-player evidence. A limited continue restarts the
current level with its entry equipment and world state; no mid-level death
checkpoint, and continues refill to three at the start of each episode. The
[run contract](../CAMPAIGN.md#runs-and-continues) owns allowance and persistence
rules. Replay cannot overwrite the main run silently.

Build each level around one playable character. Viewpoints may differ across
levels; exact assignments remain to be authored. Optional autonomous allies do
not imply companion controls, revives or mandatory co-op. Allies must not block
routes; death removes them for the mission attempt. People
move after routes are secured; no escort chores. A rescue stays fast and
physical: break a line of restraint frames, clear the guards on a freight car,
take a depot's registration desk. Never a second objective to babysit. Each plan
follows the [pillar](../VISION.md#easy-to-pick-up-deep-to-master): at most three
doors, each switch beside its door, and a planned par time and runner's line
(the three wipe levels show people helped and damage taken instead of a par).
Irreversible departures require player confirmation with remaining rescue
opportunities visible.

Use stable actor/story IDs, localized objective and caption keys, optional audio,
and world-visible consequences. Scene skipping never executes game logic twice.
Muted radio and absent voice preserve every essential fact. Recordings, diagrams,
and procedural brief generation do not establish that a mission is fun. Show,
do not tell: put the Union's cruelty, the exploitation of corrected agents, and
the wipe's meaning into what the player sees and does, never into a line of
text or dialogue that explains what the room already showed.
[Story arc](story-arc.md#show-dont-tell) owns this rule.

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

No further level is called finished because it reuses the first level's kit.
The [implementation plan](../plans/campaign-build-order.md) controls sequencing.
