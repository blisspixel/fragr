# Capture result card

**Status:** implemented, 2026-09-29. A presentation follow-up to the [first-person carry](ctf-fp-carry.md). Local evidence is below.

## Goal and why

A Sector 9 capture ends on the scoring stand. The result used the weapon card at 92 percent opacity, so the home flag's pole showed through the words. The player has to read who took the round while standing on that flag.

## Design

No server rule changes. Stands, return, capture, and the flag meshes stay as they are. The result words stay the existing `FLAG_ROUND_WINNER`, `FLAG_ROUND_DRAW`, and `FLAG_ROUND_FINAL_SCORE` strings.

The capture card gets its own flat style. The fill is the same ink as the weapon card, fully opaque, with the same border. The words are inset on that card. Other round results keep the wide unbacked line. The weapon icon keeps the translucent shared style.

## Non-goals

No new mode, no flag rename, and no change to interpolation or transport. A human and spectator round is still the acceptance gate. This does not close it.

## Architecture and protocol

Client presentation only. The snapshot shape and gameplay capability stay unchanged.

## Verification and spend

`test_match_rules.gd` checks that a capture result shows the card, that its fill is opaque, and that the words sit inside it. `test_qa_combat.gd` accepts `stop_on_round_state` only for `Warmup`, `Active`, and `Ended`. External spend is $0.

A capture freezes the pawn for the end delay, and the result waypoint's arrival disk sits inside the 2.5 metre touch radius. Waiting for that waypoint lets the next round open before the still. The result state in `client/qa/ctf_fighter_capture.json` stops the walk when the round is `Ended`. The tour compares flag, score, and round expectations to the snapshot taken with the still, before the pixel compare resumes the tree.

The joined tour passed on Godot 4.7.2 and the AMD Radeon 780M renderer. Command: `FRAGR_QA_MANIFEST=res://qa/ctf_fighter_capture.json FRAGR_QA_MODE=ctf FRAGR_QA_MAP=4 FRAGR_QA_BOTS=0 FRAGR_QA_CAPTURE_LIMIT=1 FRAGR_QA_SEED=42 FRAGR_PORT=6844 tools/qa_tour.sh .agents/qa/ctf-result-card-2` from Git Bash, without `--publish`. The server logged `Round 1 ended: Capture limit reached` with captures union 0 coalition 1 at 2026-09-30T01:55:07Z. The result walk stopped on `Ended` after 1962 ms. The manifest records `home,home`, Coalition 1, Union 0, and round 1 `Ended`.

[docs/screenshots/ctf_fighter_scored.png](../screenshots/ctf_fighter_scored.png) is that frame. The words are `FREE TAKES THE ROUND`, `CAPTURES: UNION 0 : 1 FREE`, and `CAPTURE LIMIT REACHED`. Pixels at the card center are the ink, RGB 10, 10, 12. The bone pole remains visible below the card, and the cloth remains visible beside it. The full `tools/godot_check.sh` passed on Godot 4.7.2-stable after that tour.

## Success

A player who scores can read who took the round, the capture count, and why it ended, with the home flag still visible around the card.
