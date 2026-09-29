# Carried flags read as held

**Status:** shipped, [#305](https://github.com/blisspixel/fragr/pull/305), 2026-09-29. A presentation follow-up to the [carried flag label](ctf-carried-label.md). The hand grip is the v0.60.0 still.

## Goal and why

The v0.59.0 carried still, and the first reserved-rect pass after it, show `FREE FLAG CARRIED` on a world pole while the framed fighter is someone else. The server had already given that flag to the carrier named in the HUD. A spectator reads the pole as a pickup the nearby fighter failed to take.

The flag has to sit on the carrier. The empty stand has to stop competing with the cloth.

## Design

`ArenaFlags` keeps the authoritative stand and flag position. Home and dropped flags keep the tall pole. When the snapshot names a living carrier whose pawn is in the scene, the marker leaves that pole for a short grip in the carrier's off hand: at the held-weapon height, on the camera's right, and in front of the billboard so the cloth draws over the arm. It is seated again after pawn interpolation. With no camera, the grip uses the pawn's own left and forward. With no pawn yet, the marker stays at the server position. The world words stay on the cloth and do not name the carrier.

Home and dropped flags keep the tall pole. The stand pad uses the side colour while the flag is home, and a dim plate while the flag is carried or down, so the bright cloth is the flag.

`NameplateLayout.choose` still accepts reserved screen rects for each visible flag's words and cloth, including a carrier. A plate that misses the flag still shows, and a carrier still wins against another pawn when the flag does not cover either plate. The world label does not add the callsign. No flag rule, return timer, capture limit, map solid, or wording changes.

The carried tour camera frames the carrier from the front, close enough that the hand and the face are both in the shot.

## Non-goals

No level 3 work, no new weapon, and no callsign on the world label. Human and spectator acceptance of the whole Sector 9 round stays open.

## Verification and spend

The flag harness checks the hand seat, the upright grip, the short carried pole, the dim empty stand, the restored home stand, and the three world labels. The nameplate harness still rejects a plate that covers a reserved flag rect. External spend is $0.

`test_flag_state.gd` passed on Godot 4.7.2-stable. The outcome-gated tour was `FRAGR_QA_MANIFEST=res://qa/ctf_live.json FRAGR_QA_MODE=ctf FRAGR_QA_MAP=4 FRAGR_QA_BOTS=4 FRAGR_QA_CAPTURE_LIMIT=1 FRAGR_QA_SEED=42 FRAGR_PORT=6840 tools/qa_tour.sh .agents/qa/ctf-flag-held-7` from Git Bash. The carried frame shows Aunt Linda, the HUD carrier, with the Free flag's pole through her rifle hand and the cloth overlapping her shoulder. Her face is clear, and her nameplate sits above her head. The same run ended Union 1, Free 0. That carried frame is [docs/screenshots/ctf_live_carried.png](../screenshots/ctf_live_carried.png). `tools/godot_check.sh` passed on the same Godot 4.7.2 binary after the tour.

## Success

A spectator view of a carried Sector 9 flag shows that flag in the carrier's hand, cloth overlapping the arm, with `FREE FLAG CARRIED` on the cloth. The framed body is the carrier named by the HUD, and the face stays readable. A nameplate does not cross the cloth or those words. Plates that miss the flag remain.
