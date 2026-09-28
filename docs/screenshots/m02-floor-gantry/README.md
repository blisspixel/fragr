# M02 processing-floor gantry evidence

These unedited 1280 x 720 frames came from the 20-state Severe tour on
2026-09-27 at 19:56 UTC. Godot 4.7.2-stable used OpenGL Compatibility on an
AMD Radeon 780M in Windows. A local release server loaded
`server/maps/m02-persons-unknown.json` with no rule bots. The source manifest
and logs remain under `.agents/qa/m02-floor-gantry-tuned-severe/` in the work
tree. Reproduce the route with `FRAGR_QA_BOTS=0`,
`FRAGR_QA_DIFFICULTY=severe`, `FRAGR_QA_MAP_FILE=server/maps/m02-persons-unknown.json`
and `FRAGR_QA_MANIFEST=res://qa/m02-latch-support.json` passed to
`tools/qa_tour.sh`.

| Frame | What it proves |
|---|---|
| [Officer firing](officer-firing.png) | First person view of the live Clerk officer above the floor, firing down toward the participant. The manifest identifies `floor_officer` in `firing` at tick 1406 with server Y 4.0. |
| [Upper route](upper-route.png) | First person view from the officer's position after climbing the broad stairs. The scripted route returned to the grounded dock approach and departed. |

The Severe participant entered the fight at 85 HP and left it at 35 HP with
ordinary damage and ammunition. The release scene showed 55 HP immediately
before the main-passage floor medkit, so its 30-HP grant was observed in play.
Latch dealt 40 damage to named floor enemies. These frames and the scripted
route verify one authored sequence; they do not establish fresh-player balance
or a finished M02 level. That review remains open in the
[plan](../../plans/m02-floor-gantry.md).
