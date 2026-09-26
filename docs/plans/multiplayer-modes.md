# Plan: multiplayer modes

**Status:** in flight (2026-09-25). Rung 1 below is built on
`feat/multiplayer-modes`. Every later rung is a design.
**Spend:** $0. Server rules, client presentation, harness runs and tour stills
are local. No paid audio: the Host reactions are keyed text only.

## Goal

A multiplayer loop as fun as early Counter-Strike or Doom II, with retro
vibes: several named ways to play on the same maps, chosen by the host,
visible to everyone watching or playing, with humans, agents and rule bots in
the same seats. Nick's direction (2026-09-25): deathmatch, team deathmatch,
capture the flag, GoldenEye-style rule twists, and a big combined-arms or
objective mode in the spirit of Battlefield 1942, Call of Duty or Halo.
Mutators are host settings from the start, not unlocks. No loadout shop.
Minimal radio work.

## The mode list, in order

Nick's order (2026-09-25). Radio is not a mode.

| # | Mode | Status |
|---|---|---|
| 1 | Free-for-all (Scrap) | built |
| 2 | Duel | designed in [multiplayer-maps.md](multiplayer-maps.md#modes-in-build-order) |
| 3 | Team deathmatch | this work |
| 4 | GoldenEye-style mutators | this work |
| 5 | Capture the flag | next, rung 2 below |
| 6 | Rescue | rung 3 below, on its own maps |
| 7 | Sabotage | rung 3 below, on its own maps |
| 8 | The big combined-arms objective mode (Frontline) | rung 4 below |

The bar is feel before graphics: responsive fighters, readable kills, strong
hit feedback, fast respawn and a round that keeps moving. A new rule earns its
place when it changes how a round plays, not how it looks.

## Non-goals

- A buy menu, scrip or loadout shop, in any mode. Rescue and Sabotage are
  fought with what the floor gives you.
- Unlocks for mutators. Every mutator is a host flag on day one.
- New radio or voice production. Host reactions are text keys in the client.
- New maps. Every mode here runs on the six built-in arena maps.
- Matchmaking. A host picks the rules; a server's rules are its personality.
- Blood and oil effects (welcome later, see What is next).

## The rule set framework

A server runs one **rule set**: a mode plus zero or more mutators. The host
picks it at launch:

```
fragr-server --mode tdm --mutator rail-only --mutator two-lives
```

- `--mode ffa|tdm` (default `ffa`).
- `--mutator <id>`, repeatable: `rail-only`, `shotgun-only`, `fists-only`,
  `licence-to-kill`, `golden-rail`, `two-lives`.
- `--friendly-fire` turns team damage on (off by default).
- `--frag-limit <n>` sets the limit: fighter frags in free-for-all, team
  frags in team deathmatch. Default 10 for free-for-all, 25 for teams.

The rule set lives in `MatchConfig` (`server/src/rules.rs`), so the dedicated
binary, the playtest harness and tests share one path. It is validated once at
start: two weapon-only mutators together, or Golden Rail beside Licence to
Kill, Shotgun Only or Fists Only, refuse to start with a clear error. Authored
campaign maps refuse rule overrides as they already refuse arcade options.

Everyone sees the same rules:

| Reader | Where |
|---|---|
| Godot client | `map_info.rules` drives a mode chip under the round line; teams add a score line and team colours |
| Agents (MCP) | `round_state` returns `rules`, `team_scores` and `self_team`; `observe` carries the same `map` and snapshot fields |
| Operators and server lists | `GET /status` adds `mode` and `mutators` (additive to schema 2) |
| Logs | the start line names the rule set |

Wire shapes are in [protocol.md](../protocol.md#match-rules). Clients need
gameplay capability 12 when a server runs any rule set other than plain
free-for-all, so an older client is refused at hello rather than shown a team
match without teams.

## Modes

### Free-for-all (Scrap), built

Every fighter for themselves. Frag limit and clock. Unchanged, now named `ffa`.

### Team deathmatch, this PR

- **Sides:** the Union (black and red) against the free coalition (bone,
  leather and ember, per [ART_STORY_BIBLE.md](../ART_STORY_BIBLE.md)). Wire ids
  `union` and `coalition`.
- **Balance:** every join, human, agent or rule bot, goes through the same
  `add_player` and lands on the smaller side (ties go to the side with fewer
  frags, then the coalition). At each round start, if one side is two or more
  ahead, rule bots move first, then the most recent joiners; a moved fighter
  respawns on its new side.
- **Spawns:** each side spawns in its own half of the map, chosen by the
  existing spawn safety (clear slot, fewest exposed lanes inside
  `SPAWN_THREAT_RANGE`, then the widest gap), counting only enemies as threats.
- **Friendly fire:** off by default. A shot still stops on a teammate, which
  takes no damage. With `--friendly-fire`, damage lands but a team kill scores
  nothing for anyone.
- **Score and win:** a frag of an enemy adds one to the killer and one to the
  side. First side to the limit wins; at the clock the higher side wins, or the
  round is a draw. `round_end` carries `winning_team` and `team_scores`.
- **Weapons** respawn every 30 s in team modes (12 s in free-for-all), the
  rule sheet's slower team clock.
- **Presentation:** team-coloured fighters and nameplate chips, a team score
  line and team-tagged scoreboard rows, killfeed names in team colours, a team
  chip beside the followed fighter for spectators.
- **Agents and bots** read `team` on every fighter; `PlayerState::is_hostile_to`
  ignores teammates, so the scripted bot, the brain, the playtest agents and
  rule bots stop aiming at their own side through the same shared check.

### Mutators (GoldenEye style), this PR

Each is one small server rule, shown in the mode chip.

| Mutator | Rule |
|---|---|
| Rail Only | Everyone holds the Railgun with unlimited cells. Weapon and ammunition pads are off; health and armour stay. |
| Shotgun Only | The same with the Shotgun. |
| Fists Only | The same with fists: the old Slappers Only. |
| Licence to Kill | Any hit that deals damage kills. |
| Golden Rail | One golden Railgun sits on the map's Railgun pad (the centre when a map has none). Its holder's Railgun kills in one hit, the holder glows gold and the Host names them. When the holder dies or leaves, it returns to its pad. |
| Two Lives | Each fighter has two lives per round. A fighter out of lives watches until the round ends. The last fighter (or side) with a life left wins the round. A fighter who joins a live round enters with one life. |

Two Lives changes the round's end, so it also turns off the mid-round
Compliance Drone for that server: a boss that can spend everybody's last life
is not a fair referee.

### Host reactions, this PR

Structured `host_reaction` events from authoritative facts. The server sends a
`kind`, a `variant` (0 to 2) and the names involved; the client owns the words
in `client/i18n/match.en.po` (`HOST_REACTION_<KIND>_<VARIANT>`), so there is one
source for the lines. Reactions never fire more than once every eight seconds,
except the Golden Rail call, which is information rather than drama.

| Kind | When |
|---|---|
| `first_blood` | The first frag of a round |
| `streak_ended` | A fighter on a streak of three or more is killed |
| `last_standing` | A lives-limited team round leaves one side with one fighter against two or more |
| `comeback` | A side that trailed by four or more draws level |
| `golden_rail` | Somebody picks up the golden Railgun |

## Cells cap 100

Nick approved raising the Cells cap from 50 to 100 on 2026-09-25. A rail cell
is still one shot and a Railgun pickup still adds 10. The cap moves in
`protocol/loadout.rs`, the client's `equipment_state.gd`, the tests,
[WEAPONS.md](../WEAPONS.md) and the
[boomer ammunition plan](boomer-ammo-and-pellets.md). Discovery maps require
capability 12 because an older client would refuse a loadout above 50 cells.

## Architecture impact

| Area | Change |
|---|---|
| `server/src/rules.rs` | Rule set parsing, validation, team assignment and balance helpers |
| `server/src/protocol/rules.rs` | Wire types: `MatchRules`, `GameMode`, `Mutator`, `Team`, `TeamScores`, `HostReactionKind` |
| `server/src/sim.rs` | Teams, lives, golden holder, weapon-only inventories, team score and win conditions, reactions |
| `server/src/inventory.rs` | A restricted arsenal: one weapon, unlimited ammunition |
| `server/src/main.rs`, `run.rs` | `--mode`, `--mutator`, `--friendly-fire`, `--frag-limit`; capability 12 requirement |
| `agent-adapter` | `round_state` adds `rules`, `team_scores`, `self_team` |
| `tools/playtest` | `--mode` and `--mutator`; checks that a team round saw both sides and a weapon-only round fired only that weapon |
| `client` | `match_rules.gd` (validation, labels, colours), mode chip, team scoreboard, team colours, keyed Host reactions |

## Verification

- Deterministic server tests for each mode and mutator rule, team balance,
  friendly fire both ways, team and elimination win conditions, the golden
  Railgun's return, reaction triggers and their rate limit, and wire
  round trips.
- Adapter tests for `round_state` rules and team fields.
- Godot harness `test_match_rules.gd`: rules validation, the mode chip, the team
  scoreboard and every reaction key.
- CI playtest runs team deathmatch and two mutators beside the free-for-all
  smoke.
- Tour stills of a team match and a mutator chip, inspected.

## What shipped

Filled in when the PR merges: the PR number, the tests, the playtest lines and
what the stills show.

## What is next

### Rung 2: capture the flag

Two flags, one per side, each on a stand in its side's back third. Touch the
enemy flag to carry it; touch your own stand while your flag is home to score.
A carrier who dies drops the flag where they fell; a teammate who touches a
dropped flag returns it at once, and an untouched dropped flag returns after
20 s. Carriers can shoot (the GoldenEye flag tag rule where the carrier cannot
shoot belongs to Custody). Three captures or the clock. Needs: a carried
object on the wire (`flags` in the snapshot: stand, state, carrier, position),
flag events for the Host, flag stands in each built-in map's team halves (Arena
Duel's opposite gantries, Sector 9's two ends first), agents reading flag state
in `observe`, and harness gates for captures per round and carrier survival
time. The carried-object seam is shared with Rescue's captives and Sabotage's
charge.

### Rung 3: Rescue and Sabotage

The Counter-Strike round as two modes on dedicated maps, the way that game split
its hostage and bomb maps. One set of round rules for both: one life per round
(the Two Lives machinery with one life and a round clock), attack and defend,
sides swap at half, no buy shop and no loadouts. The free coalition attacks and
the Union defends.

- **Rescue.** The coalition breaks into a Union correction site and extracts
  captive agents to an exit zone; the Union holds them. A captive follows the
  attacker who freed it and stops when that attacker dies. Attackers win by
  extracting enough captives or eliminating the defenders; defenders win on the
  clock or by elimination.
- **Sabotage.** The coalition plants a charge on a Union correction frame or
  registry server at one of two sites; the Union defends the sites and can
  defuse a planted charge. After a plant, eliminating the attackers does not
  win: a defender still has to defuse.

Needs: round and half flow in `RoundState`, a carried or escorted object on the
wire (shared with capture the flag), timed stand-still actions (plant, defuse,
free a captive) with interruption, dedicated maps built to the rule sheet, and
harness gates for attacker win rate per site and mean round length.

### Rung 4: the big combined-arms mode (Frontline)

Battlefield 1942 conquest on foot first. Three to five control sites on a
medium or large map; the capture points include pirate radio masts on the big
maps. Holding more sites bleeds the other side's tickets, faster as the gap
grows; a side spawns at its base or any site it holds; the round ends at zero
tickets. Sites flip by standing on them with no enemy inside, with the zone
state on the wire (the Control mode's seam from
[multiplayer-maps.md](multiplayer-maps.md#modes-in-build-order)). Classes stay
out: roles come from what you pick up. Vehicles (jeep, motorcycle, jetpack)
join only after the mode is fun on foot and their missions have built them
([vehicles.md](vehicles.md)). Needs: a larger map from the roster plan, zone
state and tickets on the wire, spawn-at-site selection through the existing
safety, and measured server budgets at 16 to 32 fighters before any claim.

### Later

- Duel admission and rematch sit second in the mode list and can land beside
  any rung above; Control and Custody from
  [multiplayer-maps.md](multiplayer-maps.md#modes-in-build-order) are candidate
  shapes for Frontline's sites and carried objects.
- Open Weights (everything loaded, no pickups, no respawns) is one more
  mutator on this framework.
- Boomer-shooter hit effects: blood for humans, oil and sparks for machines,
  as a presentation follow-up on the existing `shot_effects.gd` impact path.
  Cheap once the art exists; not part of this work.
- Rotations as data: a playlist file of map, mode and mutators per slot.
