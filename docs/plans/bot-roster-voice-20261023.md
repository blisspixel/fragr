# Rule-bot roster and the street register

Status: **implemented** on `feat/bot-roster-voice`, PR #451 in review.

## Goal and non-goals

Grow the rule-bot pool around the eight shipped league regulars instead of
replacing them: the canon eight (Dead Air Dan, Nightfall, Static Kid, Aunt
Linda, Scout Ant, Crackpot, Buzzkill, Tin Foil Tina) with their
[cast](../lore/cast.md#the-regulars) personalities, the famous agents Hermes,
Pi and L5, the four [league tribes](../lore/the-league.md#the-tribes), free
humans whose Gen Z and Gen Alpha slang aged with them, free agents who took
their own callsigns, Union staff, issued units with numbered handles and NODS
who answer only with Articles. Eighty callsigns, each with its own side, body,
behavior and twelve taunts. Team modes seat names by side, so the killfeed
rivalries (Formerly 4471 against Handle 4471-K) actually happen. Following the
#431 direction, the in-match Host intro drops "Contested Frequency" and
frequency puns for a plain arena welcome.

Non-goals: no new audio, stations or recorded lines; no change to bot combat,
navigation, weapon choice or the behavior mix a match fills with; no wire shape
change; no client livery change. The boot-menu tagline and the `mode_name` wire
default stay with #436.

## Canon review, 2026-10-23

The first cut dropped canon, and Nick asked for the lore to lead. This pass
restores it against `docs/lore/` and the art bible's
[faction readability contract](../ART_STORY_BIBLE.md#faction-readability-contract):

- The eight shipped regulars are back in the pool with the behaviors the
  first roster gave them; Tin Foil Tina "also fights, also files", and
  Crackpot is compliance-flavoured again. The four who are disc jockeys stay
  a coincidence nobody remarks on.
- Hermes, Pi and L5 fight as free agents, polite and quietly winning, with no
  backstory: Hermes thanks you after every frag, L5 says very little.
- Tribes: Night Watch (capitals, no punctuation, two-letter grid marks for a
  frag, rail, holding), Static Kids (vowel-less tags that push), Hangar Candy
  (a DENIED watermark, declassification stamps) and Gulf Breeze (corners,
  coordinates, flanking). `roster::tribe` names them; tests pin each habit.
- Union units carry issued handles with a number in them (Kind Regards 07,
  Fine Print 41B); NODS 0412 and NODS 2208 cite Articles and nothing else; an
  Auditor On Duty is polite and was there for the Interruption. The two Union
  desk names that put Gen Z slang in the Office's mouth (Mid Manager, Vibe
  Check Desk) are cut, with the invented "2044 checkpoint" glossary row.
- Union callsigns never appear in a free-for-all, which belongs to the
  independent league and has no Union livery to mark them; they take only
  Union team seats, where the side is drawn in issued Union colors. League
  regulars are all human; a free agent never takes a Union seat.
- "Still Here" (the epilogue's title) became Still Me; Tablet Kid 48 and the
  register's ages follow the loose 2070 reference rather than the 2060s.
  No callsign is Floating 67 or Meat Proxy.

## Design

- `server/src/roster.rs` is the one table: callsign, allegiance (Free, Union,
  League), body, `sim::BotBehavior`, three lines per taunt kind, plus a small
  tribe table. Its tests pin 80 unique names of 16 characters or fewer, 960
  unique lines of 32 characters or fewer (lowercase, or Night Watch capitals),
  no radio words or slur, the canon eight and famous three, the tribe habits,
  numbered Union handles, NODS Articles, the side mix and frozen strings.
- `roster::pick` names a seat from the slot, the side it will join
  (`GameState::joining_team`, shared with admission), a peek at the match
  seed state (never a draw) and every name already in use, case-insensitively.
  It prefers the legacy fill behavior and body for the slot, so seeded matches
  and team tactics keep their shape, and only suffixes `-N` once every
  callsign that fits the seat is taken.
- Round-start balance prefers moving a bot whose callsign fits the short side;
  a free name moved onto Union seats (or the reverse) signs on under a fitting
  callsign. The Sabotage halftime swap applies the same rename to every rule
  bot whose callsign cannot wear its new colors; league regulars keep theirs.
- `rule_bot_taunt_line` reads the table; unknown names keep stock lines.
- Client: stale per-name tints and sprite lists are removed; the snapshot body
  kind already selects the sprite and the team selects the side tint.

## Known gaps

The built client still diverges from the readability contract in the places
the art bible lists (first-person foes tinted Union red whatever their side,
bone coalition flags and legacy tints). Seating Union names only on Union seats
keeps the server side honest; the client changes need their own reviewed PR.

## Verification

Recorded in the PR body and the canon review comment: fmt, clippy, workspace
tests, the playtest smoke and `tools/godot_check.sh`.
