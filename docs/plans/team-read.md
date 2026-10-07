# Team read

**Status:** implemented in source (2026-10-06). Not merged. `test_match_rules.gd` covers the mark words and the body colours. The running night process does not draw this. Restart Godot from this repo to see it.

## Goal

A fighter in a team match can tell who is on their side while aiming. The same character art can stand on either side, and the full nameplate stays off the first-person view.

## Non-goals

A new uniform, a faction change, or a plate that shows through walls. Spectators keep the existing UNION and FREE plates. Free-for-all keeps callsign colours. The server still decides damage, including friendly fire.

## Architecture

`MatchRules.team_relation` compares the viewer's side with another fighter's side. The pawn stores that as `mate` or `foe`. A teammate is marked OURS and brightened. The other side is marked THEIRS and multiplied toward red. The words are in `client/i18n/match.en.po`. The mark uses the existing overhead label, which depth-tests against the world, and the existing overlap chooser, which keeps a teammate ahead of the other side and still yields to a flag. The viewer's own body is not marked.

## Protocol or API changes

None. `team` on the snapshot is unchanged.

## Verification

`test_match_rules.gd` checks the relation, the words, a bright teammate, a red cast on an authored body, and that clearing the mark restores the spectator chip.

## Spend

$0.

## Success

In capture the flag, team deathmatch, and Sabotage, the people on your side read as yours before you learn which faction you joined.
