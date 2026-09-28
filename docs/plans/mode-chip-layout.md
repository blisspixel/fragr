# Mode chip layout and team round presentation

**Status:** implemented locally, 2026-09-26. Integration remains open. This is
a separate presentation slice after the first named team mode. It does not
declare a human team playtest done.
**Spend:** $0. Use the shipped match rules, local Godot checks and a rendered
tour. No external asset call or cloud resource is needed.

## Goal

Make the selected match rule readable beside the round state without floating
over the world at the top center of the screen. Keep a team score and limited
lives visible in the same place. Inspect a live team match and a free-for-all
match at the desktop tour size.

## Current behavior and ownership

`client/scripts/hud.gd` creates `ModeChipLabel` dynamically as a direct HUD
child, anchored to the screen center. `client/scenes/main.tscn` already owns
the top-left round, weapon and scoreboard stack. `match_rules.gd` owns labels
and score formatting; `test_match_rules.gd` checks the text but not placement.
The [multiplayer modes plan](multiplayer-modes.md) shipped its first server
rule set, so this slice changes presentation only.

## Build

1. Give the mode line a scene-owned place directly under the round line in
   the top-left stack. Preserve the existing labels, localization and server
   scores. Do not add a second rules parser or new network field.
2. Keep the line legible for free-for-all, team deathmatch, a long mutator
   combination and lives. Avoid clipping the weapon and scoreboard lines.
3. Extend the client harness to check scene ownership and placement, plus the
   existing text and clear-on-campaign behavior.
4. Capture and inspect a live team mode and a free-for-all view. Refresh the
   published tour after any player-visible change, with honest captions.

## Acceptance

- The mode and team score appear in the top-left HUD beneath the round line,
  not at the top center over the arena. Full text is visible at the tour size.
- A first-person fighter and a watcher both retain their other HUD elements.
- `tools/godot_check.sh` and relevant Rust match tests pass; `qa_tour.sh
  --publish` completes and the images are inspected.
- A human team round remains a separate observation gate. Automated agents
  and rendered screenshots cannot establish human fun or readability alone.

## Non-goals

No new multiplayer mode, rules protocol, team assignment, paid art, map,
server hosting or balance claim.

## Local progress, 2026-09-26

The mode label is now a scene-owned child immediately after the round label.
The existing server rules and localized text still feed it. The focused Godot
test checks the hierarchy, team score, clear-on-campaign behavior and a
combined Rail Only plus Two Lives label within the HUD panel bounds.

The default `qa_tour.sh --publish` completed all 32 states and refreshed the
affected stills. The free-for-all first-person and watcher views were inspected:
the mode is under the round line and the top center of the arena is clear.
A standard team deathmatch tour also completed all 32 states. Its inspected
[first-person](../screenshots/tour_team_first_person_16x9.png) and
[watcher](../screenshots/tour_team_spectator_16x9.png) captures show the mode
and team score without covering the arena or losing the weapon line.

A diagnostic tour with Rail Only and Two Lives produced a readable two-line
mode label and lives count, but the full tour failed because its scripted
weapon capture expects Flechette and Scatter. That run is layout evidence
only, not a passed tour. The focused HUD test covers the long text. A real
human team round remains open.

The full `tools/godot_check.sh` and `cargo test --workspace --locked` passed
in the isolated worktree. `cargo fmt --all -- --check` and `git diff --check`
passed. Local logs and the diagnostic tour are under `.agents/`.
