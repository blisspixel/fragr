# Carried flag world label

**Status:** shipped, [#300](https://github.com/blisspixel/fragr/pull/300), v0.59.0, 2026-09-29. The presentation follow-up to the [rule-bot escort](ctf-rule-bot-escort.md).

## Goal and why

Before this change, a carried flag used the same world words as a flag at home. The previous live carrier still showed "FREE FLAG" over the runner while the HUD already said who was carrying it. A spectator should be able to tell those states apart on the flag itself.

## Scope

- Home stays `UNION FLAG` and `FREE FLAG`. Dropped stays `UNION FLAG DOWN` and `FREE FLAG DOWN`.
- Carried uses `UNION FLAG CARRIED` and `FREE FLAG CARRIED` in `client/i18n/match.en.po`.
- The carried label moves to the cloth's horizontal offset, local x `0.66`, and keeps the existing height so the words stay above the fabric. Home and dropped labels stay on the pole.
- The world label does not add the carrier's callsign. The HUD already names them.
- No flag rule, bot, wire, or score change.

## Verification and spend

`test_flag_state.gd` checks home, carried, and dropped words, and that the carried label is on the cloth offset while the others stay on the pole. Refresh `docs/screenshots/ctf_live_carried.png` from the existing outcome-gated tour and inspect the words. The README's four stills do not show this label.

External spend is $0.

The later [held-flag pass](ctf-flag-nameplate.md) moves this carried cloth and its words onto a short grip in the carrier's hand. Home and dropped labels stay on the stand pole. This result records the v0.59.0 label itself.

## Result

`test_flag_state.gd` passed on Godot 4.7.2-stable: home, carried, and dropped words, cloth offset `0.66` while carried, pole offset after a drop, and no callsign on the world label.

The outcome-gated tour was `FRAGR_QA_MANIFEST=res://qa/ctf_live.json FRAGR_QA_MODE=ctf FRAGR_QA_MAP=4 FRAGR_QA_BOTS=4 FRAGR_QA_CAPTURE_LIMIT=1 FRAGR_QA_SEED=42 FRAGR_PORT=6831 tools/qa_tour.sh .agents/qa/ctf-carried-label` from Git Bash. The server log recorded Sector 9 and `Capture limit reached`. The v0.59.0 carried frame showed `FREE FLAG CARRIED` on the flag, with the carrier nameplate crossing the cloth and the words still readable. The Godot log had no script error. The later grip pass replaced [docs/screenshots/ctf_live_carried.png](../screenshots/ctf_live_carried.png). The result frame is the ended round, so its home words are unchanged and that file stays.

## Success

The three flag states use three different world labels, and the refreshed carried still shows the carried words. A human and spectator session still has to judge the label in motion.
