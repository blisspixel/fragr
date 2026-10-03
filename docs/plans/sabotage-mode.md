# Sabotage, the first flagship round mode

**Status:** in flight (2026-10-02). Design source: [the flagship section of
the replayability plan](replayability.md#the-flagship-rescue-and-sabotage).
Map choice: [multiplayer maps, modes in build order](multiplayer-maps.md#modes-in-build-order).
Closest existing implementation: [capture the flag](capture-the-flag.md).

## Goal

Ship a complete, polished Sabotage match on Sector 9 Transit Hall. The free
coalition carries a charge to one of two Union sites, plants it with a held
Use, and the Union defends the sites or defuses a planted charge. One life per
round, rounds grouped into halves, sides swap at half, no shop and no loadouts.
Humans, agents and rule bots share the same seats and the same action door, and
a bots-only match produces real plants, defuses and round wins for both sides.

## Non-goals

- Rescue (the other flagship mode), the 2v2 Pairs cut and its one-site maps.
- Utility (smoke, Tattler, Tin). That is replayability rung 10.
- The 30-second public spectator delay and match demos. Both need a delayed
  stream and the demo index, which do not exist yet.
- Hiding the charge carrier from the enemy on the wire. Every client receives
  the same snapshot today; per-recipient interest filtering is fair-play rung 5.
  The client shows the carrier only to teammates and spectators.
- Reshaping Sector 9. Its geometry stays shared with deathmatch, team
  deathmatch and capture the flag. Sabotage adds sites, spawn zones, callouts
  and two spawn pads as mode data, not solids.
- Paid art or audio. Placeholders are procedural or reuse committed assets.

## Rules as built

All times are at the 20 Hz simulation and live in `MatchConfig.sabotage`.

| Phase | Default | Rule |
|---|---|---|
| Muster | 10 s | Fighters are held inside their side's spawn zone. Pickups work, fire and throws do not. |
| Live | 1:45 | One life. The charge starts with a seeded random attacker. |
| Plant | 3 s | The carrier, inside a site's plant area, holding Use and not moving. Movement, release or any damage restarts it. Everyone receives `plant_started`. |
| Charge | 35 s | Replaces the round clock. A defender at the charge holding Use for 6 s defuses it; interruption loses all progress. One defuser at a time. |
| Round end | 5 s | Result card. The swap round holds 8 s so the side-swap notice reads. |

Win conditions, resolved after combat each tick in this order:

1. A completed defuse: the Union wins.
2. Detonation: the free coalition wins.
3. Elimination, only when both sides have fighters. Before a plant, the side
   with nobody standing loses; if both fall on the same tick the Union wins,
   because time favours the defence. After a plant, only the Union can lose
   by elimination: killing every attacker does not win, a defender must defuse.
4. The live clock runs out before a plant: the Union wins.

A plant that completes on the tick the clock expires counts. A defuse that
completes on the tick the charge would detonate counts. A defender killed on
the tick their defuse would complete loses it.

**Sides.** The fiction fixes the jobs: the free coalition always attacks and
the Union always defends. At every half the fighters change uniform, so
everyone plays both. The round score is reported by current uniform and swaps
with the fighters, so it always follows the people. A joiner takes the smaller
side as in every team mode. Joining during muster spawns normally; joining
later waits for the next round and watches living teammates.

**Format.** `short` (default, public): halves of 4, first to 5. `match`: halves
of 8, first to 9. At a tie after regulation, `match` plays extra periods of two
halves of 3, first to win 4 of that period, repeating while level. `short`
plays one extra pair (one round each side) and then ends as a draw if still
level, so a public rotation moves. Sides stay put entering an extra period and
swap at its half, the Counter-Strike convention.

**Equipment.** Every life starts empty. In Sabotage the arena uses the
discovery inventory: fists, then a personal Tack pad inside each spawn zone
within two seconds of every spawn point. Map pads stay on as in every other
mode. A survivor keeps every weapon, all remaining ammunition and armour into
the next round, with health restored. A death drops the carried primary (the
best of Rail, Scatter and Flechette) where the fighter fell, for anyone to take,
and the drop is cleared at the next round. Weapon-only mutators keep their
single unlimited weapon and no drops.

**The charge.** Spawns with a seeded random attacker at round start, drops
where its carrier dies, leaves or changes side, and can be picked up by any
living attacker. Defenders cannot carry it.

**Mutators.** Host settings as everywhere: Rail Only, Shotgun Only, Fists
Only, Licence to Kill and Golden Rail run on Sabotage. Two Lives is refused,
because one life per round is the mode. Golden Rail grants the Railgun under
discovery equipment.

## Sector 9 layout

Sector 9 keeps every solid. Sabotage adds, as validated mode data in
`maps.rs`:

- **A Frame** (the correction frame), plant area at (-38, 0, -27), radius 3 m,
  in the West Hall (parcel sort) under the Sort Deck.
- **B Server** (the registry server), plant area at (-38, 0, 27), radius 3 m,
  between the West Hall freight stacks.
- **Defender hall:** six spawn points around the West spawn bay, x -56 to
  -50, muster zone x -74 to -48, z -13 to 13, Tack pad at (-55, 0).
- **Attacker yard:** six spawn points inside the East Hall center door, x 31
  to 35, muster zone x 28 to 44, z -13 to 13, Tack pad at (34, 0).
- **Rule-bot data:** six hold spots around each site, an approach point in
  mid and a staging cluster inside each north or south mid door, out of the
  site's sight.
- **Callouts:** A Frame, B Server, Sort Deck, Defender Hall, Attacker Yard,
  Mid, Mid Doors, North Mid, South Mid, East Hall, West Hall and Service.

Ways into each site: Mid Doors (fastest), the north or south mid door, the West
Hall service door and the defender hall. Each plant area is visible from the
Sort Deck or the freight stacks and from the Mid Doors approach. Route timings
are measured by `sabotage_routes_meet_the_timing_targets` with the shared
navigator and actual `GameState` movement:

| Route | Straight line | Measured walk | Target |
|---|---:|---:|---|
| Attacker spawns to A or B (Mid Doors) | 17.7 to 18.8 s | 19.2 to 21.6 s | 15 to 20 s |
| Defender spawns to the nearer site | 4.6 to 5.4 s | 6.3 to 7.3 s | under 8 s |
| A to B and back | 10.8 s | 10.9 s | 10 to 12 s |

The navigator's two metre grid adds two to three seconds of cornering to the
long attack walk; a player on the straight Mid Doors line meets the target,
and rule bots pay the same cost on both sides. Every stage, approach, hold and
the West Hall service door also reach their site in the same test.

## Evidence

Bots-only survey, `fragr-playtest --sabotage-survey --seed 40 --survey-seeds
16`, short format, 2026-10-02 on this Windows host, no sockets:

| Bots | Matches finished | Rounds | Attack wins | Rounds with a plant | Detonations | Defuses | Mean round | Longest |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4 | 16 of 16 | 124 | 31 % | 14 % | 1 | 8 | 50.7 s | 90.8 s |
| 8 | 16 of 16 | 113 | 47 % | 60 % | 11 | 25 | 77.2 s | 122.7 s |
| 12 | 16 of 16 | 114 | 44 % | 62 % | 16 | 26 | 86.0 s | 130.8 s |

Every round ended inside its clocks (the bound is 151 s), both sides won by
elimination, detonation or defuse, and the 4v4 attack share sits inside the
replayability plan's 40 to 60 percent gate with plants in more than half the
rounds. The 2v2 attack share is low: with one defender per site, the defence
rarely has to rotate, and the bots do not yet split or fake. That is open.

Socket gates, debug build: `--sabotage-route-smoke` (one attacker and one
defender on the shared wire controller) recorded live, plant started,
planted, defuse started and defused, with a Union round, in 33.2 s.
`--mode sabotage --agents 4 --tiers reflex,planner --sabotage-contested`
decided its round by elimination with three frags, a charge drop and pickups.
These prove the wire path for agents, not human fun.

## Architecture impact

| Area | Change |
|---|---|
| `protocol/rules.rs` | `GameMode::Sabotage`, a team mode. |
| `rules.rs` | Validation (Two Lives refused, one life), `SabotageConfig`, `SabotageFormat` and the pure half, swap and match-end arithmetic. |
| `protocol/sabotage.rs` | Wire types: `SabotageMap`, `SabotageState`, charge, progress, events and the round result. |
| `sim/sabotage.rs` | Phases, placement, charge, plant and defuse progress, outcomes, side swap, carried equipment and dropped primaries. |
| `sim/sabotage/bots.rs` | Rule bot attack (carry, take a site, plant, hold) and defence (anchor, rotate, retake, defuse). |
| `sim/sabotage/controller.rs` | One wire controller for external agents: playtest agents, the adapter's scripted bot and any MCP client reading the same snapshot. |
| `maps.rs` | Sector 9 Sabotage layout and its validation. |
| `session.rs`, `run.rs`, `main.rs` | Discovery loadouts in Sabotage, goal-driven bot steering, `--mode sabotage`, `--sabotage-format`, refusal off validated maps, capability requirement. |
| `agent-adapter` | `round_state` reports `sabotage` and `sabotage_map`; `act` documents held `interact` for plant and defuse. |
| `tools/playtest` | Sabotage mode, socket smoke assertions and a seeded bots-only survey. |
| `client` | Validation, site sprites, carried and planted charge, plant and defuse progress, charge timer and tone, result card, round score, side-swap notice, teammate spectating. |

## Protocol

Additive. Gameplay capability **28**; a Sabotage server requires 28 for every
role, fighters and spectators, the way capture the flag required 14. Other
modes keep their earlier minimum. `MapInfo.sabotage` carries the static
layout, `Snapshot.sabotage` the round state, `GameEvent::Sabotage` the facts,
and `RoundEnd.sabotage` the round and match result. `docs/protocol.md` and
`agent-adapter/README.md` record names, units and ordering.

## Verification

- Deterministic tests in `server/src/tests/sabotage.rs` for every rule and its
  failure paths: muster hold, plant success, interrupted plant (release,
  movement, damage, death), clock edges, defuse success, defuse after death,
  one defuser at a time, detonation, elimination before and after a plant,
  simultaneous events in one tick, side swap with scores, extra periods, draws,
  carried equipment and dropped primaries, late joiners and leaving carriers.
- Pure tests for the format arithmetic in `rules.rs`; wire tests for every new
  shape on the server, adapter and Godot sides.
- Route timing and reachability with actual `GameState` players.
- `fragr-playtest --mode sabotage` socket smoke with asserted plants and round
  results, and a seeded bots-only survey across at least 16 seeds asserting
  plants, defuses, wins on both sides and no stuck round.
- Mixed human, agent and spectator sessions; a rendered tour under the machine
  lock with inspected stills.
- The full AGENTS.md verification list before each PR.

## Spend

$0. No paid generation or service. Placeholders are procedural sprites and
synthesized tones; final assets are listed for a later bounded batch.

## Success criteria

- [ ] A host runs `fragr-server --mode sabotage --map 4 --bots 8` and a seeded
      bots-only match ends with a winner, with plants, defuses and round wins
      for both sides.
- [ ] A human can join or watch and read the sites, the carrier, plant and
      defuse progress, the charge timer, the round result and the score by
      round, and after dying watches living teammates.
- [ ] Agents read the same state through MCP and plant or defuse through `act`.
- [ ] CI runs a Sabotage smoke; coverage stays at or above 90 percent.
- [ ] A human group plays a full match and asks for another. Open until it happens.

## Decisions made without Nick

1. The free coalition always attacks and the fighters change uniform at half,
   following the fiction; the score follows the people. (Open question 1 in the
   replayability plan asked free side first or random; join balance decides
   who wears which uniform first.)
2. `short` is the default host format; `match` is a flag.
3. Short-format extra time is one pair of rounds, then a draw.
4. A same-tick double wipe goes to the defence before a plant and to the attack after it.
5. The charge carrier is visible on the wire to everyone for now; only the
   client hides it from the enemy.
6. Personal spawn claims reset each round, so a survivor can always reach a
   pistol and ammunition at the spawn pad.

## Work log

- 2026-10-02: Read AGENTS.md, the flagship design, MODES, the map plan and the
  CTF plan series; audited `rules.rs`, `sim.rs`, `sim/ctf.rs`, `session.rs`,
  navigation, inventory, the playtest harness, the adapter and the CTF client
  presentation. Wrote this plan.
- 2026-10-02: Server rules, wire types, Sector 9 layout, rule bots, the shared
  wire controller, adapter `round_state` fields and 33 deterministic tests are
  in. `fragr-playtest --sabotage-survey` runs seeded bots-only matches without
  sockets. First 8-seed surveys: every match finishes, but the attack wins only
  about a quarter of rounds and plants are rare, because attackers die
  crossing into the West Hall. Staging at the north and south mid doors
  raised plants from 6 to 10 in 42 rounds.
- 2026-10-02: Tuning, each change surveyed on eight seeds: fight in clear
  sight without the navigator (a bot walking a route could not fire for
  several ticks, which handed stationary defenders the first shots); attackers
  hold their route past far enemies; anchors hold angles; the carrier plants
  only with nobody within 20 m; an approach point in mid keeps the walk to
  the B stage out of B's sight; the push waits for the side to gather; the
  defence rotates on sighted contact and the last defender keeps the far
  site; pushing attackers trade from where they made contact. Attack share
  moved from 25 to 47 percent at 4v4 and plants from 11 to 60 percent of
  rounds. Spawns moved toward the sites to meet the measured route targets.
- 2026-10-02: The full Rust suite passed except
  `a_short_in_process_soak_samples_and_passes`, a three-second timing check
  that missed its four samples while six agents shared the machine; alone it
  passes.

- 2026-10-02: The server half shipped as
  [PR #325](https://github.com/blisspixel/fragr/pull/325) with green CI and
  93.86 percent workspace line coverage. The client half adds the Godot
  presentation, three rendered tours and the adapter's scripted bot playing
  the objective through the shared controller. Two wall-clock tests
  (`a_short_in_process_soak_samples_and_passes` and
  `scripted_bot_uses_raised_geometry_under_continuous_snapshots`) missed their
  deadlines only while six agents loaded this machine; each passes alone.

## Handoff

Two PRs. The first carries the server rules, wire, layout, rule bots, the
shared controller, the adapter, the harness gates, CI and the protocol docs.
The second carries the Godot presentation, the rendered tours and the player
docs; its client work is on `feat/sabotage-mode` in the `frmp` worktree. Next
there: run `tools/godot_check.sh` and the three Sabotage tours under the render
lock, inspect the stills, then MODES, README and CHANGELOG.
Fast iteration build: `CARGO_PROFILE_RELEASE_INCREMENTAL=true
CARGO_PROFILE_RELEASE_CODEGEN_UNITS=256 cargo build -p fragr-playtest --release
--target-dir target/iter`, then `target/iter/release/fragr-playtest
--sabotage-survey --seed 40 --survey-seeds 8`.
