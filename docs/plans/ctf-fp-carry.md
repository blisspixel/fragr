# First-person flag carry

**Status:** shipped, [#307](https://github.com/blisspixel/fragr/pull/307), 2026-09-29. A presentation follow-up to the [hand grip](ctf-flag-nameplate.md). The pennant is the v0.61.0 still.

## Goal and why

The third-person still shows the Free flag in Aunt Linda's hand. Before this pass, the joined first-person still was Meat Proxy with the Railgun, the corner line `UNION FLAG CARRIED BY Meat Proxy`, and no cloth in the view. The server had already recorded the take. The current [first-person still](../screenshots/ctf_fighter_carried.png) shows the Union cloth and `UNION FLAG` beside the weapon.

First person hides the body and the world weapon. The grip sits at the weapon hand, about 0.7 m below an eye that is only 0.1 m above the pawn origin, so it is outside the view. The corner chip is the only carry read, and it is easy to miss while aiming.

## Design

No server rule changes. Touch radius, drop grace, return timer, capture limit, stands, Sector 9 geometry, bot policy, and the third-person grip constants stay as they are. `FLAG_*` copy stays. The league flag stays a staged match marker.

`ArenaFlags.set_first_person_carrier` is set before `apply`. When a carried flag's carrier is that id and the pawn is in the scene, the world marker stays seated and stays hidden. Home flags, dropped flags, and every other carrier stay visible. `_process` keeps seating a hidden grip and does not show it again. Leaving first person clears the id; the next apply shows the grip.

The HUD draws the same read beside the viewmodel. `HUD.set_fp_carried_flag` accepts `union` or `coalition`. The cloth uses `MatchRules.team_label_color`. The pole uses `MatchRules.team_body_color`, steel for Union and bone for the Free Coalition, matching the world grip. The words are the existing `FLAG_WORLD_UNION` and `FLAG_WORLD_COALITION` strings, in the pixel font, at the mode chip's size and outline, on an ink plate so they stay readable on the pale floor. The pennant sits left of the weapon, clear of the crosshair and of the health numerals. Fists use that same side of the viewmodel. It is hidden when first-person presentation is off, and it ignores the pointer.

The local subject is the joined human whose pawn is in the scene, including the snapshot that enters first person. A spectator's subject is the followed pawn, and only while `is_observing_first_person` is true. The team is the flag whose status is `carried` and whose carrier is that subject, checked with `MatchRules.valid_team`.

## Non-goals

No level 3 work, no new weapon, no flag rename, and no change to interpolation or transport. Human and spectator acceptance of a full Sector 9 round stays open. The third-person grip still is `docs/screenshots/ctf_live_carried.png` and is not replaced by this view.

## Architecture and protocol

Client presentation only. The snapshot shape, gameplay capability, and MCP tools are unchanged.

## Verification and spend

`test_flag_state.gd` hides the named carrier's grip, keeps the other carried flag, keeps a dropped flag visible, and restores the grip when the id is cleared. `test_match_rules.gd` shows `UNION FLAG` and `FREE FLAG` on the pennant, rejects an unknown side, and hides the pennant when first person turns off. Both passed on Godot 4.7.2-stable. `tools/godot_check.sh` passed on that binary after the words moved onto the ink plate. External spend is $0.

The joined tour was `FRAGR_QA_MANIFEST=res://qa/ctf_fighter_capture.json FRAGR_QA_MODE=ctf FRAGR_QA_MAP=4 FRAGR_QA_BOTS=0 FRAGR_QA_CAPTURE_LIMIT=1 FRAGR_QA_SEED=42 FRAGR_PORT=6842 tools/qa_tour.sh .agents/qa/ctf-fp-carry-2`, without `--publish`. The enemy-stand frame shows the Union cloth and `UNION FLAG` beside the Railgun, clear of the crosshair and the health numerals. The same moment with the HUD hidden has no second grip in view. The capture frame drops the pennant, scores Free 1, and ends the round. That enemy-stand frame is [docs/screenshots/ctf_fighter_carried.png](../screenshots/ctf_fighter_carried.png).

## Success

A joined first-person carrier sees the flag's side colour and the stand words beside the weapon, and does not see a second copy of that grip in the world. Another fighter's flag, and the same flag seen from third person, still use the hand grip.
