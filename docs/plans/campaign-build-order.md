# Plan: the campaign build order

**Status:** spec (2026-09-19)
**Branch:** `feat/campaign-*`, one PR per rung
**Spend:** $0. Geometry, rosters and levels are authored in the repo. Host and enemy voice lines come from the developer audio pipeline when a rung needs them, which is never before rung 10.

The design is `docs/CAMPAIGN.md`. The frameworks are `docs/plans/campaign-continuance.md`. This is the order the work happens in, what each rung is allowed to depend on, and how you know a rung is done.

## The rule this plan is built on

**Every rung ships on its own and a player can feel it.** No rung is a refactor that lands with nothing to show, because a refactor with nothing to show is how a campaign stays eighteen months away forever.

That constraint sets the order more than the dependency graph does. It is why the first rung is not the map format, which is the biggest and most obviously necessary piece of work, but the exit lever, which is two hundred lines and turns a round into a level.

## What exists today, honestly

Reconciled with source on 2026-09-19 after the map roster and local polish work.
This is the remaining gap the rungs close.

| Thing the campaign needs | What is actually there |
|---|---|
| Levels | Six arena layouts in `server/src/maps.rs`, selected by `MapKind`. No external map file format or runtime level manifest yet |
| Level geometry | Per-map bounds, axis-aligned solids with top heights, steps, raised decks, cover pockets, and pickup placement. The client builds the same solids from `MapInfo`. These are arena layouts, not authored campaign levels |
| Height | Gravity, jumping, standable solid tops, and step-up live in `server/src/movement.rs`, mirrored by `client/scripts/movement.gd` and golden vectors. Full 3D authoritative aim and live client prediction remain separate work |
| Weapons | Three: Flechette, Rail, Scatter. No ammunition, no magazines, no reload, and `Action.weapon_swap` is applied unconditionally, so the weapon pads are decoration. Health and armour pads are real and work |
| Enemies | Five bot behaviours sharing one controller. There is no monster entity: the boss is a `Player` with `is_boss: true` and a `Compliance` behaviour. No pain state, no infighting, no wake on sight, and no line of sight in the targeting at all, only in the hit resolution |
| Projectiles | None. Every shot in the game is hitscan. The Lobber, the Jammer and the Walker all need a projectile entity that does not exist |
| Episodes | One, hardcoded. `EpisodePhase` is `Nods`, `Jammer`, `Auditor`, `Won`, `Failed` and the constants are Episode 0 specific. There is no episode list and no level list |
| Finishing a level | Nothing. No exit, no level complete, no results card, no par time, no secrets, no keys, no doors, no triggers. The round ends on a frag limit, a time limit, or the Auditor dying |
| Difficulty | Nothing. No tier, no skill flag, no CLI knob |
| Saving | Nothing but `user://settings.cfg`. The Episode 0 unlock teaser is a string in an event and nothing is remembered |
| Objectives | One, and it is good: seize the jammer dish. It already has a world silhouette and a HUD chip |

Two of those are worse than they look. **The boss is a `Player`**, so rung 6 is a refactor of the thing the whole roster sits on rather than an addition beside it. And **nothing is a projectile**, so three of the ten enemy types and two of the eleven weapons are waiting on an entity kind the server has never had.

Two are better than they look. Height is already simulated and already proven across the language boundary, so rung 4 is about surfaces rather than about physics. And the Episode 0 path already has the exact chrome shape the campaign needs: a title card, an objective chip, a progress string, and start, complete and fail events on the wire.

## The rungs

### Rung 1: a level can be finished

The exit lever, the level complete event, and the results card on the existing
Episode 0 arena. No new geometry, no new format, no new enemies.

- An exit entity reusing the pickup claim machinery that already works (`ArenaPickup`, `PICKUP_CLAIM_RADIUS`), with `live: bool` driven by whether the phase conditions are met, sent in the snapshot so the client can render the alcove and hum.
- `level_complete` on the wire with time, par, kills of total, secrets of total, deaths. Secrets are zero of zero until rung 7, and saying zero of zero is more honest than hiding the row.
- Par time as a field on the level, a constant for now.
- Episode 0 stops ending on the Auditor's death and starts ending when you walk to the lever with the Auditor dead, which is the campaign's win condition stated once, in code, on the level that already ships.
- The client renders the card over the radio and moves on with any key.

**Why first:** it is the smallest change that converts the thing the game already does into the thing the campaign is made of, and every later rung is measured by producing one of these cards.

**Verify:** a deterministic sim test that walks a fighter into a live exit and asserts the event and its fields; a test that an exit with conditions outstanding is not live; `cargo run -p fragr-playtest` completes Calibration through the lever; `tools/godot_check.sh` passes with a headless check that the card builds from a synthetic event.

### Rung 2: a level list, and coming back tomorrow

`--campaign e0` and `--campaign e1`, an episode manifest, level to level handoff, and a save.

- `server/maps/episodes.json`: episodes as ordered level lists, each with a par time and a boss flag. Episode 0 becomes `e0m1` and nothing about it changes for the player.
- On a complete, the server loads the next level in the list and starts it. On the last, an episode card.
- The server keeps `campaign.json` in its data directory: episode, level index, tier, best time per level. `--campaign-continue` loads it.
- The client mirrors best times into `user://campaign.cfg` and the boot menu grows a Continue entry and an episode list. `client/scripts/boot_menu.gd` already has the disabled Episode 1 button waiting for this.
- Content for this rung is three levels laid out on the two existing arenas with different pickup and bot placements. They are not good levels. They prove the chain.

**Verify:** a headless run that completes three levels in sequence in a bounded tick count; a save round trip test; a boot menu headless check that Continue appears only when a save exists.

### Rung 3: maps as data

The manifest, the validator, `tools/mapc`, and one source of geometry for the server and the client. The full specification is already written in `campaign-continuance.md` and is decision complete; this rung implements it.

- Ship it by converting the two existing arenas to manifests and deleting the hardcoded builders. If the game plays identically afterwards, the rung worked.
- `fragr-mapc check` runs in CI over every manifest in the tree.
- The client's open question is unresolved and must be settled first: func_godot's Godot 4.7 compatibility is unstated. Test it in an afternoon before building on it. The fallback is `mapc` emitting meshes the client loads, which is more work and no risk.

**Verify:** a validator test per failure mode (bounds, no spawn, missing exit, dangling trigger target, a solid over a spawn); a test that the converted Arena Duel manifest produces the same solid list as the function it replaces; the playtest harness reports the same kill distance buckets before and after.

### Rung 4: floors you can stand on

The movement foundation shipped with the six-map roster: solid tops, step-up,
and golden-vector coverage already exist. Do not implement a second heightfield.
This rung now means using those surfaces deliberately in authored campaign maps
and extending coverage only for new traversal requirements.

- Preserve standable top heights and the existing tested step-up rules.
- The client's box meshes already come from the same solids, so they follow for free.
- `plans/map-scale.md` rung 1 is partly done by the work that already shipped; what remains is this.

**Why here:** rule five of `docs/MAP-DESIGN.md` is the Episode 1 boss fight and half the encounter vocabulary. Without it every level is one plane and the campaign is a maze.

**Verify:** extended golden vectors committed and asserted in both languages; a test that a fighter walking off a crate falls and lands; a test that a step of the allowed height is walked and a step above it is not; a headless client walk over a ramp.

### Rung 5: the weapon economy

`plans/weapon-economy.md`, implemented. An owned weapon set, the swap gated on it, four ammunition pools, magazines and reloads, the carry limit, and the eight weapons that do not exist yet.

**Why before the enemies:** every answer in `docs/ENEMIES.md` is a weapon, and six of the ten answers are weapons the game does not have. Building the roster first means building ten problems with three solutions.

It also unblocks the campaign's only progression axis. Until the swap is gated, a player has every weapon in the game on every level and the ladder in `docs/CAMPAIGN.md` is a fiction.

The Lobber's projectile is the first projectile in the game. Build the entity here rather than in rung 6, because one weapon is a smaller first customer than three enemy types.

**Verify:** the tests in that plan; the playtest harness reports a weapon usage spread that is not seventy percent one gun; a test that a dry trigger costs nothing and does not auto-swap; a projectile test that asserts travel, the first thing hit, and the splash falloff.

### Rung 6: monsters as tables

The ten types in `docs/ENEMIES.md` as server entities on the tick, with the row schema, the state machine, wake on sight and sound, pain, and infighting. This is rung 2 of `campaign-continuance.md` and its detail is already decision complete there.

Two things to be honest about before starting.

**The boss is a `Player`.** Lifting monsters out into their own entity kind touches the snapshot, the killfeed, the scoreboard, the most valuable player logic, the playtest harness and the adapter. Doing it in one PR is a bad idea. Do it as: the entity kind and one type (the Clerk) first, the remaining nine second, the existing boss migrated onto it third.

**Timings are in seconds or this rung is wasted.** Every tell in the roster is authored in seconds. Land this after stage 4 of `plans/buttery-controls.md` so nothing in the tables is expressed in ticks.

**Verify:** one deterministic sim test per type asserting wake, chase, attack timing and pain to the tick; an infighting test where a Sweeper that catches a Crawler becomes the Crawler's problem; a test that a closed door blocks sound propagation; a test that an Auditor is never targeted by another monster and always retargets.

### Rung 7: doors, keys, triggers, secrets

The level format's remaining verbs, which the manifest already has fields for.

- Doors as solids removed while open, with a colour and an optional key.
- Keys as items, with the three colours and the rule that half the levels have none.
- Triggers as polygons with an action list: spawn a group, open a door, alert monsters in a radius, play a Host line. The closet and the teleport trap are both this.
- Secrets as polygons that count once and print on the card.

**Verify:** a test per action; a validator test that a door's key exists somewhere reachable; a test that a secret counts once and only once; a headless run of a hand-built level that exercises every element.

### Rung 8: tiers, objectives, and the two bodies

The GoldenEye layer, which is the rung that makes replaying a level worth doing.

- Three placement bits per thing in the manifest, plus a fast flag and the tier one damage halving. Four tiers, named from the Schedule.
- The seven objectives in `docs/CAMPAIGN.md`, each as a small server rule with a four word chip. The dish already exists and is the template.
- The entries counter and the Auditor at three.
- The body choice and its four asymmetry rules. Three of the four are one-line rules on existing systems: health and armour pads already exist and already differ in placement, the reload timer arrives in rung 5, and the log arrives with the objectives. Only the agent's see-through-walls-on-fire read is new work, and it is a one second flag on a monster the client already renders.
- Agent telemetry grows here too: visible monsters by type and range, keys held, a locked door seen, and an objective hint, so the brain agent can play a level rather than just fight in one.

**Verify:** a tier table test; a test per objective including the failure path; a test that a human's clerk filing delay and an agent's instant filing both land on the tick; a recorded run of the same level at tier two and tier four showing different objectives on the card; a playtest run where an agent completes a level using the objective hint.

### Rung 9: the routing

Where an objective comes from, and the machinery that lets some of them serve something else. The design is in `docs/CAMPAIGN.md`; this is what it costs.

- **A source on every objective.** One word, four values, shown on the chip and carried in the snapshot. Cheap, and it ships alone as a small readability win even if nothing else in this rung lands.
- **Objectives drawn rather than written.** A level's manifest gains objective slots with candidate lists, and the draw is seeded from the run seed so it is reproducible, testable, and identical for every member of a co-op party except where it is deliberately not.
- **A routed flag on a candidate,** which changes nothing the player can see at the time and sets a world flag on completion.
- **World flags that survive a level.** They live in the campaign save beside the level index, and a later level's manifest can swap a spawn group, darken a wing, or change one string on the strength of one. This is the only cross-level state the campaign has and it must stay that small.
- **The extra row on the results card,** in the Office's plain face, after a routed completion.
- **The flicker:** one frame, on some routed objectives and on some that are not. A frame of a label and a seeded coin flip.
- **No counter anywhere.** The tally must not exist in the save, the snapshot, the card, or the logs. Add a test that asserts it does not, because somebody will add it later in good faith.

**Why its own rung:** it is the only part of the campaign that is not Doom, it touches the save and the manifest rather than the tick, and it can ship and be proven on a synthetic two level episode long before Episode 2 exists to use it.

**Verify:** a seeded draw test proving the same seed gives the same objectives and a different seed does not; a test that a routed completion sets the flag and that a later level reads it; a test that the card row appears only after a routed completion; a test that no tally is persisted or transmitted; a two level headless run where the second level is visibly changed by what happened in the first.

### Rung 10: Episode 1

Eight levels and a secret level, authored against `docs/plans/campaign-e1.md`, built to the rules in `docs/MAP-DESIGN.md` and the five beat shape.

This is the largest rung by wall clock and the smallest by code, and that ratio is the entire point of rungs 3 through 9. If it is not the smallest by code, one of those rungs is unfinished and this rung will discover it painfully.

Ship it in threes: E1M1 to E1M3 with the secret exit, then E1M4 to E1M6, then E1M7, the secret level, and the boss level's geometry without its boss.

**Verify:** a recorded full episode run at tier two with the card from each level; par times set from the median of three runs rather than guessed; the map validator green on all nine; the tour photographs each level from three poses so a grey box shows up.

### Rung 11: the bosses

The Continuance Walker and the Custodian of Record, each as a monster row plus an arena rule, not as a special case in the tick loop.

The Walker needs the projectile from rung 5 and the standable floors from rung 4. The Custodian needs the Auditor's resurrect, scaled, and nothing else, which is why it is the cheaper of the two and should be built first as a rehearsal even though it belongs to Episode 2.

**Verify:** a deterministic test per boss; a recorded kill of each; a test that the exit is dead while a boss lives.

### Rung 12: co-op, and the seat on the other side

The same server mode with more seats. Keys, doors and secrets shared, one results card for the party, one save for the party. Then counter-op: a spectator seat possessing monsters in turn, with the lanes in `plans/fair-play.md` keeping it honest.

**Verify:** a recorded run of Episode 1 with two humans and two agents in the party; a test that a key taken by one member opens the door for all of them; a counter-op test that a possessed monster obeys the same rules its table gives it.

### Rung 13: Episodes 2 and 3

Same bar, new families of levels, the Custodian and the Address, and the ending. Written as `docs/plans/campaign-e2.md` and `docs/plans/campaign-e3.md` when rung 10 has taught what an episode actually costs.

**Verify:** recorded runs; the campaign completable end to end at every tier.

## What this plan does not do

- **It does not build a world map screen.** That is the last rung of `campaign-continuance.md` and it is a menu, not a campaign.
- **It does not build the arcade ladder or the Sweep.** They share the monster tables from rung 6 and they are their own modes in `docs/MODES.md`. Building them is cheap once rung 6 lands and they are not on the path to a campaign.
- **It does not add a second simulation.** Everything above is the existing server mode with more in it, which is the reason agents and spectators get the campaign for free.
- **It does not buy anything.** No rung here bills money. The voice lines in rung 10 come from the existing developer pipeline and are optional.

## The risks worth naming

**func_godot on Godot 4.7 is unverified.** Rung 3 depends on it or on a fallback that costs more. Spend one afternoon proving it before the rung starts, and write the answer into `campaign-continuance.md` either way.

**Rung 6 is a refactor wearing a content hat.** The boss being a `Player` means the monster entity lands in the middle of the snapshot, the killfeed and the harness. The three step sequence above exists because a single PR here will be too large to review and too large to revert.

**Projectiles are genuinely new.** Nothing in the game has ever travelled. They touch the wire, the client, the spectator, and the agents' world model. Rung 5 introduces them with one customer on purpose.

**The content is the cost.** Twenty-four levels is the largest single piece of work in the project. It is authoring rather than engineering only if rungs 3 to 9 land first and land properly. The failure mode is authoring level four and discovering that the trigger you need does not exist, then writing it as a special case, and then having twenty levels each with their own special case.

**The routing is the easiest thing in this plan to ruin.** Every instinct a developer has will push it toward being legible: a counter, a reveal, an achievement, a log line that says what really happened, a tell that actually works. All of those are the same mistake, which is turning an uncertainty into a puzzle, and the game has a rule against puzzles. Rung 9 carries a test asserting the tally does not exist specifically so that somebody has to delete a test on purpose to add one.

**The coverage floor applies to every rung.** Unfiltered eighty percent of workspace lines, no carve outs. A content rung adds data rather than code and helps; a framework rung adds a great deal of code and must carry its own tests in the same PR.

## Verification that applies to every rung

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo llvm-cov --workspace --locked --fail-under-lines 80
cargo build --workspace --release
cargo deny check licenses bans sources
cargo run -p fragr-playtest -- --agents 4 --rounds 1 --frag-limit 3 --time-limit-seconds 45 --assert --report .agents/playtest/ci.json
tools/godot_check.sh
```

A rung is done when its own verification passes, the list above passes, the plan's status is updated in `docs/plans/README.md` and `docs/ROADMAP.md`, and a card from a real run is in the PR.

## Success criteria

- [ ] Rung 1: a level is won by walking to a lever, and a card says how it went.
- [ ] Rung 2: three levels in a row, and a Continue that works tomorrow.
- [ ] Rung 3: both existing arenas load from manifests and play identically.
- [ ] Rung 4: you can stand on a crate and drop through a hole.
- [ ] Rung 5: the ladder exists, the swap is gated, and something travelled.
- [ ] Rung 6: ten types, each a different problem, and they fight each other.
- [ ] Rung 7: a red key opens a red door and a wall hides a Rail.
- [ ] Rung 8: the same level at two tiers is two levels, and the two bodies walk it differently.
- [ ] Rung 9: an objective has a source, two runs of one level ask for different things, and a level changes because of what happened in the last one.
- [ ] Rung 10: Episode 1 end to end with par times taken from real runs.
- [ ] Rung 11: two bosses that are rooms rather than health bars.
- [ ] Rung 12: Episode 1 with a party, and one seat on the Continuance side.
- [ ] Rung 13: the campaign ends the way `docs/CAMPAIGN.md` says it does.

## Related

- `docs/CAMPAIGN.md`: what is being built.
- `docs/plans/campaign-e1.md`: the first episode, level by level.
- `docs/plans/campaign-continuance.md`: the map manifest, the map tool, and the monster row schema, all decision complete.
- `docs/plans/weapon-economy.md`: rung 5 in full.
- `docs/plans/map-scale.md`: the size ladder rung 4 and rung 10 build against.
- `docs/plans/buttery-controls.md`: the movement work rung 6 waits on.
- `docs/plans/fair-play.md`: the lanes counter-op needs.
