# Tab leaderboard

**Status:** implemented (2026-10-06). Local client check passed. Not merged. The published game does not have this board.

## Goal

Hold Tab and read every fighter, the way a match scoreboard works. The corner list stays four names so it does not run off the window.

## Non-goals

Ping, a persistent season ladder, and a board that pauses the match. The corner list's words stay the frag line.

The hold-Tab board later gained deaths, hit rate, head share and damage dealt. Those counts come from the snapshot. The frag event does not add them. Hit rate is bodies found over gun shots, including a shield. Head share is the head band over those bodies. A zero denominator is a dash, not 0%. A printed percent carries its count (`66.7 (2/3)`). Damage dealt is HP plus armor, overkill excluded.

## Architecture

`hud.gd` builds the rows it already stores and `MatchRules.scoreboard_text` prints them. The corner passes a limit of four and no local name. The centered `Leaderboard` panel passes every row and marks the local callsign with `YOU`. It opens only while the existing `scoreboard` action is held (Tab, or gamepad Back). The panel ignores the pointer.

## Protocol or API

None.

## Verification

`client/scripts/test_match_rules.gd` checks six fighters, the local marker, the four-name corner, and that the open board stays inside the window.

## Spend

$0.

## Success

A player holding Tab sees the whole roster without losing the fight underneath. Releasing Tab clears it.
