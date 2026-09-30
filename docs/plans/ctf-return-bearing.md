# Carrier return bearing

**Status:** shipped, [#311](https://github.com/blisspixel/fragr/pull/311), 2026-09-29. A Sector 9 readability follow-up to the [result card](ctf-result-card.md). Display only. The compass is the v0.63.0 still.

## Goal and why

A joined carrier's corner line reads `UNION FLAG CARRIED BY Meat Proxy // FREE FLAG HOME`. Dropped flags already add metres and a compass. The carrier does not. The place they must touch is their own stand, and nothing in the corner says which way that is.

The same gap hits everyone else when a flag is stolen. `CARRIED BY` names the fighter and does not say where they are, so a defender or an escort off the lane has to search.

## Design

No server rule changes. Touch radius, drop grace, return timer, capture limit, stands, Sector 9 geometry, bot policy, grip constants, and the result card stay as they are. The league flag stays a staged match marker. Gameplay capability stays the same.

`FlagState.status_text` builds one corner phrase per flag. The server still owns every touch.

- A flag at home stays `HOME`, except while this viewer is carrying the enemy flag and this flag is their own. Then it reads `HOME {distance}M {bearing}`, measured from the viewer to that flag's stand. That stand is the capture point, and only while their own flag is home can they score.
- A dropped flag keeps `DOWN {seconds}S, {distance}M {bearing}` when the viewer has a position, and the shorter drop line otherwise.
- A flag carried by someone else reads `CARRIED BY {player}, {distance}M {bearing}` from the viewer to the flag's server position. The carrier's own line stays `CARRIED BY {player}` with no distance, because that position is the viewer.
- A distance that rounds to under one metre omits the compass. Standing on the stand, or on the carrier, does not need `0M N`.
- A viewer with no position, no team, or no stand falls back to the short phrase. Spectators use the followed pawn, which is the same viewer the dropped-flag compass already uses.

Bearings stay the existing eight `FLAG_BEARING_*` strings. `+X` is east and `-Z` is north. Two new strings carry the extra fields: `FLAG_HOME_BEARING` and `FLAG_CARRIED_BEARING`.

## Non-goals

No level 3 work, no new weapon, no flag rename, and no change to interpolation or transport. The frag board stays a frag board. Human and spectator acceptance of a full Sector 9 round stays open. This does not retag v0.61.0.

## Architecture and protocol

Client presentation only. `docs/protocol.md` is unchanged. The snapshot already carries `stand`, `position`, `carrier`, and each fighter's `team`.

## Verification and spend

`test_flag_state.gd` covers the return compass, the chase compass, the carrier's own line, a sub-metre omit, a missing position, a missing team, and a dropped own flag. `test_match_rules.gd` checks the composed corner line and that it still fits the HUD panel. Both passed on Godot 4.7.2-stable, with clean parse checks for `flag_state.gd`, `hud.gd`, and `qa_tour.gd`.

The joined tour was `FRAGR_QA_MANIFEST=res://qa/ctf_fighter_capture.json FRAGR_QA_MODE=ctf FRAGR_QA_MAP=4 FRAGR_QA_BOTS=0 FRAGR_QA_CAPTURE_LIMIT=1 FRAGR_QA_SEED=42 FRAGR_PORT=6846 tools/qa_tour.sh .agents/qa/ctf-return-bearing`, without `--publish`. It passed three states on the AMD Radeon 780M. At the Union stand the corner reads `FREE FLAG HOME 140M E`. On the home approach it reads `FREE FLAG HOME 25M NE`. After the capture both flags read `HOME`, with no compass. The enemy-stand frame is [docs/screenshots/ctf_fighter_carried.png](../screenshots/ctf_fighter_carried.png). `tools/godot_check.sh` passed on Godot 4.7.2-stable after the tour. External spend is $0.

## Success

A carrier can read which way their stand is, and how far, without leaving the corner. Anyone else can read which way a stolen flag went. A flag at home, seen by someone who is not carrying, still says `HOME`.
