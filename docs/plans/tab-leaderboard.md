# Tab leaderboard

**Status:** implemented (2026-10-06). Local client check passed. Not merged. The published game does not have this board.

## Goal

Hold Tab and read every fighter, the way a match scoreboard works. The corner list stays four names so it does not run off the window.

## Non-goals

Deaths, ping, a persistent season ladder, and a board that pauses the match. No server or wire change. The corner list's words stay the same.

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
