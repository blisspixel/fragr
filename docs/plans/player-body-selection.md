# Player body selection

Status: **in flight**, 2026-09-26. Wire, persistence, agent flags, runtime art
and tour stills are implemented with local evidence; the PR is open and not
merged. The [roadmap](../ROADMAP.md) owns sequencing.

## Goal

The player chooses a human or a conscious embodied agent in a synthetic body,
matching the campaign canon in [CAMPAIGN.md](../CAMPAIGN.md): "a customizable
human or conscious embodied agent shares the same personal story", and body type
is not morality. The choice is saved in the profile, travels through the one
Hello every client sends, is visible to other players and spectators, and is
honored for agents through that same Hello.

## Non-goals

No classes, body-specific health, speed, armor, hit volume or collision size.
No side, faction or hostility selected by appearance. No new control role,
companion seat, accounts, paid cosmetics, uploads, full character creator or
mid-life body change. No paid generation: the art is a local rig bake at $0.
No body-specific first-person hands in this slice (see Gaps).

## Salvage decision

The earlier attempt lived only as uncommitted work on `feat/story-frames`
(2026-09-22, backed up under `_backups/fragr-story-frames-2026-09-22`). It was
re-implemented on current `main` rather than applied:

- Its capability 9 is M02 on `main`, and main has since reached 12. The body is
  capability 13 here, additive, with no map requirement.
- Its local save v2 migration targeted a save format that `main` replaced with
  the run file. Carrying the body across a process restart of a solo run is left
  as a gap rather than a second run-file revision in this PR.
- Its Welcome `gameplay_version` echo and strict "refuse a Free AI join on an
  older server" policy were dropped: an absent Welcome body means an older
  server, and the pawn is then shown as human. Nothing is inferred from role or
  callsign.
- Its wire id `robot` became `synthetic`, which names the physical body without
  implying a lesser status; the menu says EMBODIED AGENT.
- Its native pistol-hands prototype had been rejected against the accepted gun
  art, and was not ported. Its participant rig was rebuilt on the current rig
  hooks in the free palette, and now ships as runtime art.
- Its seeded parity, roster, campaign and resume tests were ported and adapted.

## Architecture

- `server/src/protocol/body.rs` owns `BodyKind { Human, Synthetic }`, with serde
  ids `human` and `synthetic`, a Human default, and `for_roster_slot`.
- `ClientMessage::Hello.body` (optional), `ServerMessage::Welcome.body`
  (optional, participants only) and `PlayerState.body` (optional; omitted for
  Union campaign actors and the arena boss).
- `net.rs` passes the requested body into `GameCommand::Connected`; a resume
  returns the parked pawn's body through `ResumeAccept`. `session.rs` admits with
  `add_player_with_body` and gives rule bots bodies by roster slot in the
  pattern human, synthetic, synthetic, human. A plain alternation matched the
  way team sides fill and put one body on each side in the first TDM tour; the
  pattern and a test now keep both bodies on both sides.
  `sim::Player.body` is set once at admission and nothing in combat reads it.
- Agents: the adapter's `join` tool takes `body`, both adapter commands take
  `--body`, `round_state` reports `self_body`; the brain takes `--body`.
- Client: `PlayerBody` (`client/scripts/player_body.gd`) owns the allowlist,
  Welcome and snapshot checks, art paths and gait frames. `settings.gd` persists
  `profile/body`; the callsign page shows a body choice with a preview; the
  game manager hands the saved body to `net_client.gd`, which sends it for
  participants and records `accepted_body`.
- Art: `client/art/characters/player_rig.gd` extends the shared rig in the free
  palette; `player_bake.gd` writes `client/assets/characters/free/` (one strip
  per body, four idle breaths and four walk frames, 160 px cells, the Union
  bake's 3 metre field and feet registration, a one-texel outline in outline
  purple) plus a manifest of source and output hashes.
- `player_pawn.gd` wears the accepted body: the strip, the shared field so the
  figure is exactly the 1.8 metre hit volume, hand-height weapon, a gait that
  advances with distance walked, and a nameplate just over the head. A free
  body keeps its own colours in free-for-all and on the free coalition side of
  a team match; the Union side keeps its dark tint and red plate so sides still
  read apart. Fighters without a body (older servers, the boss) keep the legacy
  strips.

## Protocol

Capability 13, documented in [protocol.md](../protocol.md) and the
[adapter README](../../agent-adapter/README.md). Unknown ids, resource paths and
non-string values fail Hello parsing before admission. A spectator's body is
ignored and its Welcome has none.

## Verification

| Check | Result |
|---|---|
| `cargo test -p fragr-server --lib body` | wire allowlist and defaults, seeded parity for both roles (snapshots equal after removing only `body`, records equal, damage and a frag resolved), respawn keeps the body, bot slot bodies independent of name and role, both bodies on both sides for 4, 6 and 8 bots in a team match, boss and Union actors carry none, both bodies and roles admitted to Recall Notice with identical readiness, equipment and faction, team sides independent of body |
| `cargo test -p fragr-server --test body_identity` | real sockets: all roles and bodies, spectator without body, watcher snapshot shows each body, invalid ids refused before Welcome, resume asking for another body keeps the pawn's own |
| Adapter and brain tests | `join` body validation and persistence, `round_state.self_body`, `--body` parsing on both binaries, the brain's Hello carries its body |
| `test_player_body.gd` | allowlist, Hello per role, Welcome and snapshot validation, older-server human fallback, pawn wearing, coalition and Union tints, gait frames, Union actors never wear a body, bake freshness against the manifest, no Union red and a light mean in both strips |
| `test_frontend.gd`, `test_settings.gd` | body choice, preview, save, cancel and narrowing of unknown stored values |
| Tour `client/qa/tour.json` | `body_human`, `body_synthetic` close stills, the joined player's accepted body recorded as synthetic, the callsign page with the choice and preview |
| Tour `client/qa/modes.json` with `FRAGR_QA_MODE=tdm` | coalition human, coalition synthetic and a Union-side synthetic |

Full repository gates are listed in the PR with their results.

## Gaps

- First-person hands are the shared gloved viewmodels for both bodies. They
  read as either, but they are not body-specific art.
- The strip is front-facing, as the legacy participant strips were; there are no
  directional views, firing, hit or death poses for participants yet.
- A solo campaign run does not record its body. A process restart and resume of
  a run uses the current profile body. A later run-file revision can pin it.
- Body-aware banter and narration variants are not part of this slice.
- No human playtest has judged the two bodies in motion.

## Spend

$0. No paid calls, no new dependencies, no version pins changed.
