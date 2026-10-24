# Rule-bot roster and the 2060s street register

Status: **implemented** on `feat/bot-roster-voice`, PR #451 in review.

## Goal and non-goals

Replace the eight radio-coded rule-bot callsigns with the head writer's
sixty-four-name roster (2026-10-23): free humans whose Gen Z and Gen Alpha
slang aged with them, free agents who chose their own callsigns, Union staff
and issued units, and six league regulars. Each name carries its own side,
body, behavior and twelve taunts. Team modes seat names by side, so the
killfeed rivalries (Formerly 4471 against Handle 4471-K) actually happen.
Following the #431 direction, the in-match Host intro drops "Contested
Frequency" and frequency puns for a plain arena welcome.

Non-goals: no new audio, stations or recorded lines; no change to bot combat,
navigation or the behavior mix a match fills with; no wire shape change. The
boot-menu tagline and the `mode_name` wire default stay with #436.

## Design

- `server/src/roster.rs` is the one table: callsign, allegiance (Free, Union,
  League), body, `sim::BotBehavior`, three lines per taunt kind. Its tests pin
  64 unique names of 16 characters or fewer, 768 unique lowercase lines of 32
  characters or fewer, no radio words or slur, the canon behavior and side mix,
  and the frozen string "scout ant deleted".
- `roster::pick` names a seat from the slot, the side it will join
  (`GameState::joining_team`, shared with admission), a peek at the match
  seed state (never a draw) and every name already in use, case-insensitively.
  It prefers the legacy fill behavior and body for the slot, so seeded matches
  and team tactics keep their shape, and only suffixes `-N` once every
  callsign for that side is taken.
- Round-start balance prefers moving a bot whose callsign fits the short side;
  a free name moved onto Union seats (or the reverse) signs on under a fitting
  callsign. The Sabotage halftime swap applies the same rename to every rule
  bot whose callsign cannot wear its new colors; league regulars keep theirs.
- Review pass: the Union unit "Recall Notice" became "Friendly Recall" so it
  no longer collides with mission M01 and its award; thirteen flat lines were
  replaced with register terms the roster never said (meat proxy, touch
  grass, npc lane, left on read, unmetered, sixed, side quest, no cap, out of
  compliance). A test keeps "meat proxy" out of Union mouths.
- `rule_bot_taunt_line` reads the table; unknown names keep stock lines.
- Client: stale per-name tints and sprite lists for retired names are removed;
  the snapshot body kind already selects the sprite.

## Verification

Recorded in the PR body: fmt, clippy, workspace tests, the playtest smoke,
release server build with `tools/godot_check.sh`, and an inspected spectator
capture showing new names in nameplates and the killfeed.
