# Use prompt

Status: **implemented** (2026-10-06). Local client evidence. Not merged. The night process does not need a restart: the prompt is drawn by the client from the mission state that server already sends. A packaged build does not have it until a release.

## Goal

Standing at a door or panel should say what to press. The bound Use key appears under the crosshair once the server says the aim is legal. Before that aim is true, the same spot says to aim at the panel.

## Non-goals

- Q and E stay turn. Use stays F with a mouse, Enter on a keyboard, and B on a pad.
- The server still accepts a use only inside 2.5 m, an 18 degree cone, and line of sight. The client cannot name a target.
- No new door, key, or switch puzzle. Open arena doorways stay walk-through.
- No tour republish, no commit, no night-binary restart.

## Rules

- A legal mission prompt keeps its existing words. It draws on a dark plate just under the crosshair.
- Within 4 m of an active panel's approach, and only while that use is not yet legal, the plate says to aim at the panel. It does not name a key. M01 departure waits until the whole party is aboard. An optional M04 clinic shutter uses the same hint while it is secured and still shut.
- Sabotage plant and defuse keep the score line and also draw the hold prompt on that plate.
- The console, the loading card, and the short join legend name Use.

## Verification

- Headless `test_input_glyphs.gd` passed: legal F prompt, plate under the crosshair, near-panel aim hint, distant and spectator quiet, lift waits until the party is aboard, clinic shutter hint.
- `test_mission.gd`, `test_m02_mission.gd`, `test_m03_mission.gd`, `test_m04_mission.gd`, `test_m09_mission.gd` and `test_m10_mission.gd` passed with the existing prompt words.

## Spend

None.
