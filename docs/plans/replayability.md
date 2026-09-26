# Plan: replayability

**Status:** proposed (2026-09-25). A design awaiting Nick's decision; it directs
no work. Nothing below is built unless a line says so.
**Branch:** `docs/multiplayer-replayability` for this plan; one `feat/*` branch per rung.
**Spend:** $0 for every rung. The optional paid coach in rung 12 passes the
existing Jev budget gate or does not run.

## Goal

Counter-Strike level replayability. Someone should finish the campaign and come
back to it on a harder tier, or skip it and play the hell out of multiplayer for
years, and both should be worth it. The test is the one in
[MODES.md](../MODES.md#the-bar): you can play this all day after work and have a
blast barely thinking about it, and a year later you are still getting better.

This plan owns why people come back: the loops at three time scales, the
flagship competitive mode, mastery, party play, humans and agents together,
progression, watchability and community, and the order to build them.
[multiplayer-maps.md](multiplayer-maps.md) owns the maps and the rule sheet;
[MODES.md](../MODES.md) owns what each mode is; [WEAPONS.md](../WEAPONS.md) owns
numbers; [fair-play.md](fair-play.md) owns lanes and evidence;
[benchmark-and-stats.md](benchmark-and-stats.md) owns the service record.

## Non-goals

- Accounts, matchmaking, public rankings or a ranked queue before the exposed
  server is proven (roadmap Phase 2). A server list is the lobby.
- Pay to win, loot boxes, purchases, battle passes, login streaks, daily chores.
- Puzzles, classes chosen from a menu, or depth that must be explained before it
  is fun.
- Invasive anti-cheat. Server authority, lanes and replays are the whole answer.
- Flashbangs or any effect that blinds a screen. Glare is sound and colour.
- Changing the multiplayer mode order without Nick's decision. Where this plan
  proposes a new slot it says so.

## What the classics teach

Researched 2026-09-25; sources at the end. Map-specific lessons already live in
[multiplayer-maps.md](multiplayer-maps.md#what-the-classics-actually-did); these
are the lessons about coming back.

- **Counter-Strike: every round is a small story with a price.** One life per
  round makes each death cost something, and the buy economy carries that cost
  into the next round: the round win pays $3,250 to $3,500, a loss pays a bonus
  that climbs with each consecutive loss and steps back down after a win, and a
  kill pays more with a cheap gun than with the AWP. So a team argues every
  round about whether to buy, save or force, and a loss is still a decision.
  The bomb is a 40 second clock with a 10 second defuse (5 with a kit), which
  turns the end of every round into a readable duel of nerve. Matches are first
  to 13 over two halves of 12 with a side swap; a 12-12 goes to three-round
  overtime halves with $10,000 each, so the economy flattens exactly when the
  stakes peak. Depth lives in map knowledge: callouts, timings, and grenade
  lineups learned from demos, where players review every throw and copy the ones
  that work. Roles (entry, AWP, support, lurk, anchor) emerge from what you buy
  and where you stand, not from a class screen. And it was a Half-Life mod,
  bought by Valve in 2000 because a community would not stop playing it.
- **Quake: mastery is in the body and the clock.** Strafe jumping began as an
  unintended quirk of the movement code and was kept because players had made it
  a skill; decades later people still judge each other by how clean it looks.
  Item timing turns a map into a schedule you run in your head. Duel is the
  pure test and the culture's centre.
- **Unreal Tournament: mutators multiply content.** InstaGib, Low Gravity and
  BigHead combined freely; the InstaGib, low gravity CTF combination was popular
  enough that a patch made it an official mode. BigHead grew the heads of
  players doing well, a rubber band the whole room could see.
- **GoldenEye: the couch is a rules menu.** Scenarios like Licence to Kill,
  Golden Gun and Flag Tag rewrote scoring, and an eleven-step health handicap
  let a strong player carry less health so a room of mixed skill kept playing.
- **Rock n' Roll Racing: a voice and a shop.** Larry "Supermouth" Huffman called
  every race with a race caller's enthusiasm, and between races you spent winnings
  on engines, tyres, shocks, armour and weapon charges. The announcer made
  small events feel big; the shop made every race feed the next.
- **Battlefield 1942: the sandbox writes the stories.** Vehicles, flags and open
  maps produced moments nobody scripted, and the mod scene (Desert Combat) was
  strong enough that DICE bought its studio.
- **Half-Life: the mod is the long tail.** Counter-Strike, Team Fortress Classic
  and Day of Defeat were community work adopted by the publisher. A game that
  lets people make modes and maps outlives its own content plan.

### Rules we actually use

1. **Stakes per round.** A mode people replay for years puts something at risk
   every two minutes and carries the result forward.
2. **A loss is a decision, not a sentence.** Rubber bands (loss bonus, handicap,
   big heads) keep a match alive without deciding it.
3. **Depth is knowledge you spend.** Callouts, clocks, lineups and routes are
   learned once and pay forever, and none of them is a puzzle.
4. **Roles emerge.** What you carry and where you stand make the role. No class
   menu (as [WEAPONS.md](../WEAPONS.md) already says).
5. **Rules are data.** Every mutator and mode is a named rule set a host can
   pick, an agent can read, and a modder can write.
6. **A voice makes events matter.** The Host reacts to what just happened, in
   capitals, and never explains.
7. **Everything is watchable and replayable.** Demos teach, spectators stay, and
   the seeded sim makes a replay exact.
8. **Servers, not queues.** Community servers with rotations outlive matchmakers.

## Three time scales

| Scale | What happens | What brings you back |
|---|---|---|
| **The 30-second fight** | Spawn empty, grab the Tack two seconds away, read a sound, take a route, win or lose a duel of aim, movement and weapon choice. Seven-pellet Scatter up close, Rail across a lane, the dodge (proposed in [gunfeel](gunfeel.md)) to break a line. | Clean feedback on every hit (the fun bar's three signals), a fight you can explain afterwards, and the feeling you nearly had it. The Host calls the good ones. |
| **The round** | Free-for-all: a three-minute schedule of item clocks, armour stacks and the Overtime pad. Rescue and Sabotage (below): muster, take a site or hold it, plant or defuse, free captives or hold them, carry survival into the next round. | The bell (the league's ritual), the podium, and a result that changes the next round: a saved rifle, a rival who owes you one. |
| **The session and the months** | A rotation of maps and rule sets, a rival on the scoreboard, feats that earn cosmetics, a season file with a new map pool, demos of your worst round. | Maps you know better every week, cheese strategies that get a nickname within a week and stop working within two ([the league](../lore/the-league.md)), a record that shows you improving, servers with regulars. |

## The flagship: Rescue and Sabotage

**Decided, 2026-09-25.** No radio-themed mode. The Counter-Strike-style round
rules below (one life per round, attack and defend, no buy shop or scrip
economy, no loadouts) become two modes on dedicated maps, the way Counter-Strike
splits cs_ hostage maps from de_ bomb maps: **Rescue** and **Sabotage**. Both
retire the earlier single "Jammer" proposal: that name belonged to the
[Jammer enemy](../ENEMIES.md) in any case, and the jammer object, its
Solo-Broadcast-dish tie-in and the not-approved scrip economy and locker are
gone, not renamed. Mutators stay host settings from the start, not unlocks, the
way [rung 1](#build-order) already proposes for every other mode.

Round-based attack and defend with stakes and one life per round. The
competitive heart, built to be learned in one round and argued about for years.

### The fiction

The Union's registry runs two kinds of infrastructure the free side wants
gone: the correction sites that already hold people the Schedule reclassified,
and the correction frames and registry servers that keep reclassifying more of
them.

- **Rescue.** The free side breaks into a Union correction site and extracts
  the captives held there to a marked exit. The Union holds the site and the
  captives.
- **Sabotage.** The free side plants a charge on a Union correction frame or
  registry server at one of two sites. The Union defends the site or defuses
  the charge.

Sides swap at half, so everyone plays both. Playing the Union is a round in a
uniform, not a change of heart.

### Teams and format

- **4v4** standard, 2v2 and 5v5 allowed. Rule bots fill empty seats and leave as
  people arrive; humans and agents count the same toward balance
  ([rule 9](multiplayer-maps.md#9-humans-agents-and-bots)).
- **Match:** halves of 8 rounds, first to 9. Sides swap at half.
- **Short format** for public rotation: halves of 4, first to 5 (about 20 minutes).
- **Extra rounds** at 8-8: halves of 3, first to 4. A 3-3 plays another pair. A
  public server may end in a draw after one pair so the rotation moves. (Not
  called overtime: that is the power item's name in the rule sheet.)

### Round flow

All times at the 20 Hz sim; each is a `MatchConfig`-style field, not a
constant. Muster and round end are shared; the live phase forks by mode.

| Phase | Time | What happens |
|---|---|---|
| **Muster** | 10 s | The bell. Everyone is held inside a spawn zone; only map pickups equip a fighter, the same [item clocks](multiplayer-maps.md#5-items-and-clocks) as every other mode. The Host names the score and any streak. |
| **Round end** | 5 s | Podium line, dead fighters return to the muster. |

**Sabotage**

| Phase | Time | What happens |
|---|---|---|
| **Live** | 1:45 | One life. Attackers carry the charge to a site. |
| **Plant** | 3 s standing | Only inside a site's marked plant area. Any movement or damage restarts it. The whole server hears it start. |
| **Charge running** | 35 s | The round clock is replaced by the charge's. A rising tone every 5 s, faster in the last 10. |
| **Defuse** | 6 s standing | Any defender, at the charge. Interrupted progress is lost. There is no kit: one number to learn. |

**Win conditions.** Attackers win if the charge runs out, or every defender is
down. Defenders win if the clock runs out before a plant, every attacker is
down before a plant, or the charge is defused. After a plant, killing every
attacker does not win: a defender still has to defuse.

**The charge** spawns with a random attacker, drops where its carrier dies, and
can be picked up by any attacker. Defenders cannot carry it. The carrier's
position is visible to their own team, not to the enemy. It glows and hums at
10 m, so a carrier sneaking alone is possible but never silent up close.

**Rescue**

| Phase | Time | What happens |
|---|---|---|
| **Live** | 1:45 | One life. Attackers move to the holding cell. |
| **Unlock** | 2 s standing | Only at the holding cell. Any movement or damage restarts it. The whole server hears it start, and every captive there is freed. |
| **Extract** | rest of Live | A freed captive follows the nearest living attacker at survivor's pace. Reaching the marked exit with a captive ends the round. Abandoned, a captive stops and waits for another attacker. |

**Win conditions.** Attackers win by walking a freed captive into the exit, or
if every defender is down. Defenders win if the clock runs out, or if every
attacker is down, before an extraction.

**Dying** makes you a spectator of your own living teammates only, first person
or follow camera. Public spectators watch on a 30 s delay in Rescue and
Sabotage so a friend in the booth cannot call positions (see [Spectators and
demos](#spectators-and-demos)).

### No shop, no scrip

Decided 2026-09-25: no buy phase, no currency and no loadouts, anywhere in this
design. [WEAPONS.md](../WEAPONS.md) already says there are no loadouts; a shop
would have needed its own labelled exception the way Open Weights gets one,
and Nick declined it. Weapons come from map pickups exactly as in every other
mode: the Tack pad sits within two seconds of every spawn
([every life starts empty](../MODES.md#every-life-starts-empty)), map pads
stay on, and one contested item per map (a heavy plate at mid, announced when
it appears at 0:25) gives a taste of item timing without a locker.

**Carrying forward.** A survivor keeps every weapon and all remaining
ammunition and armour into the next round. A death drops the carried primary
where you fell for anyone to take. That is the stake: saving a Rail matters,
and taking one off a body is a swing. This, not a currency, is what a loss
costs and a win protects.

### Utility that rewards map knowledge

Three throwables, all deterministic: the same stance, aim and throw always land
in the same place, because the sim is seeded and has no throw randomness. So a
lineup is real knowledge, learned from a demo or a friend, and it is never a
puzzle: throwing one badly still works a bit.

- **Smoke can.** A 6 m sphere that blocks sight for 15 s. The server removes
  fighters behind it from each client's interest set, so a smoke is enforced on
  the wire, not in a shader a modified client could delete (it lands with
  line-of-sight culling, [fair-play](fair-play.md) rung 5).
- **Tattler.** A thrown sensor that pings enemies within 8 m through walls for
  2 s, to the thrower's team only. One shot kills it. It is the Custody core's
  voice in a can.
- **Tin.** The proposed proximity mine: visible arming light, 1.5 s to arm, one
  per defender, cleared at round end. Placing it on a site's back entrance is
  the anchor's craft.

No flashbang. A blinded screen is the one tool the multiplayer rule sheet
already rules out.

### Roles, emergent

Nobody picks a class. The roles form because of what you found and where you
stand, the way they did in Counter-Strike:

- **Entry:** Scatter and a heavy plate, first through the door.
- **Rail:** the lane holder, trading map control for the one long gun on the map.
- **Support:** smokes and Tattlers for someone else's entry.
- **Lurk:** alone on the far route, timing a flank off the Host's calls.
- **Anchor:** a defender who stays on a site with a Tin behind them.

Agents and bots fill the same roles through the same pickup and move actions.
Named rule bots lean into their personalities (a Rusher pushes for the
Scatter, a Sniper holds the Rail).

### Map requirements

On top of the [rule sheet](multiplayer-maps.md#rule-sheet). A map is built for
one mode, never both, the way a cs_ map is never also a de_ map.

**Sabotage**, two sites:

- Two sites, each with three or more ways in and a plant area visible from at
  least two angles, so a plant can be contested without walking onto it.
- Attackers reach either site in 15 to 20 s; defenders reach their near site in
  under 8 s and rotate between sites in 10 to 12 s. The defender advantage is
  time; the attacker advantage is choice.
- A mid that connects routes and can be fought for, where the one contested item
  sits.
- Asymmetric spawns: an attacker yard and a defender hall.

**Rescue**, one cell and one exit:

- One holding cell with three or more ways in, visible from at least two
  angles, so a defender can watch it without a fair fight being guaranteed.
- One marked exit reachable from the cell by at least two routes, far enough
  from the cell that an escort is a real walk, not a formality.
- Attacker spawn near the exit's outside approach, defender spawn near the
  holding cell, so both sides start with something to defend.

**Shared:**

- Callouts for every plant area, holding cell, exit and approach, so agents,
  bots, the Host and players say the same words.
- Deterministic lineup targets: every site has at least three smoke spots that
  cut a main sightline.

Maps that suit Sabotage are listed in
[multiplayer-maps.md](multiplayer-maps.md#modes-in-build-order); Sector 9
Transit Hall is first. Rescue's cell-and-exit shape is smaller and more
asymmetric than any current map; the roster does not have a purpose-built one
yet, and a small Sabotage map can prototype it by treating one site as the
cell and the attacker yard as the exit.

### Pairs: the 2v2 Sabotage cut

One site, halves of 4, first to 5, 1:15 rounds, same rules. On the small maps
built for duel and 2v2 (East-West Pipe with the site at the Cross, Area Kitchen
with the site in the Glass Office). It is the fastest way to learn Sabotage,
and two humans against two agents is the best practice there is.

### Spectators and demos

- Dead teammates watch teammates. Public spectators get a 30 s delay in Rescue
  and Sabotage, none in free-for-all (nothing to ghost there).
- The spectator HUD shows both teams' remaining players, the charge's position
  in Sabotage or the captives' state in Rescue, utility in flight, and the item
  clock for the contested item.
- Every Rescue or Sabotage match writes a demo (see
  [Watchability](#watchability)). A round table in the demo lets a viewer jump
  straight to round 11.

## Deathmatch and duel mastery

Free-for-all and duel are where the genre's deepest skills live, and most of
them already exist or are one rung away.

- **Item timing.** The clocks in [rule 5](multiplayer-maps.md#5-items-and-clocks)
  (weapons 12 s, health 15 s, armour 25 s, heavy plate and surplus 35 s,
  Overtime 120 s) and a respawn sound for every big item turn each map into a
  schedule. Spectators see clocks; players learn them by ear.
- **Stack control.** 100 health and 100 armour are the ceiling. Taking an armour
  you do not need to deny it is a skill the scoreboard never shows and the demo
  always does.
- **Movement.** Shipped: jumps about 1.1 m high and 3 m long, stairs, one-way
  drops. Cheap next: the ground dodge proposed in [gunfeel](gunfeel.md) (2.0x
  top speed for 0.20 s, 1.2 s cooldown, a recovery clamp), one input bit on the
  wire and already designed for the golden vectors. Authored jump lines like
  Chemtrail Alley's roof run give the dodge a place to shine. No bunny hopping:
  the speed cap stays, so a newcomer is never simply outrun.
- **A walk key, proposed.** 55 percent speed and no footsteps. Footsteps become
  server-sent audible events within a radius, the same for humans and agents, so
  sound is information and silence is a choice. One input bit.
- **Weapon choice under a budget.** Two primaries, Doom counts, no reload
  ([boomer ammo](boomer-ammo-and-pellets.md)). Knowing when the Rail has two cells
  left is a read you make in a fight.
- **Duel.** 1v1 with a 10 minute clock, a spectator queue and instant rematch
  ([MODES.md](../MODES.md#duel)). The rematch button is the replay feature; a
  head-to-head line on the results card ("you lead Dead Air Dan 7 to 4 on this
  machine") is the reason to press it.

## Party and couch

GoldenEye proved that a rules menu is content. Every mutator is a named rule set
on the existing sim (rung 1 below), shown in `round_state`, readable by agents.

- **The set already proposed** in [multiplayer-maps.md](multiplayer-maps.md#modes-in-build-order):
  Licence to Kill, Golden Rail, Rail Only, Scatter Only, Fists Only, Two Lives,
  Open Weights.
- **Handicap.** Per player, 50 to 150 percent health in eleven steps, set by the
  host or by the player lowering their own. Shown beside the name. The one
  mutator that lets a veteran play with a friend on day one.
- **Paperwork.** A random rule set from the host's list each round, announced in
  Warmup by the Host. Cheap, and the room never knows what is next.
- **Big heads**, as [MODES.md](../MODES.md#unlocks) already promises after the
  campaign, grow with a player's lead but are visual only: the hit volume never
  changes, because every fighter must present the same target (the GoldenEye
  Oddjob lesson).
- **Split screen** for two to four on one machine is the true couch and real
  engine work (several viewports, input routing by device). It waits until
  buttery controls land and is not in the build order below.

### The Host, reacting

Rock n' Roll Racing's announcer made a pass feel like a headline. The Host
already calls streaks, MVPs and warmup ([voice](../lore/voice.md): capitals,
short, never explains). Replayability wants more triggers, each from an
authoritative event, each a localized key with several variants that rotate so
a regular does not hear the same one twice in a night:

| Event | Example line |
|---|---|
| First blood | FIRST BLOOD. SOMEBODY HAD TO. |
| A fists frag | BARE HANDS. FILE THAT. |
| A streak ended | THE STREAK IS OVER. SAY SOMETHING NICE. |
| Last alive against three | ONE AGAINST THREE. THE BOOTH IS STANDING. |
| Clutch won | HE DID IT. NOBODY IN THIS BUILDING BELIEVED HIM. |
| Ace (one fighter, whole enemy side) | ALL FOUR. ONE CALLSIGN. |
| Charge planted | THIRTY-FIVE ON THE CLOCK. MOVE. |
| Captives freed | THEY'RE UP. GET THEM OUT. |
| Defuse under one second | DEFUSED WITH A TICK TO SPARE. |
| Comeback from four down | FOUR DOWN AND LEVEL. SAME RULES. |
| Overtime pad up | OVERTIME IS UP. EVERYBODY KNOWS. |
| Agent tops the board | THE CLAWBOT TAKES IT. SKILL ISSUE, MEAT PROXIES. |

Text in the HUD first; Host voice follows the existing radio production path and
its budget. The lines never cover the crosshair and never fire during a fight
more than once every eight seconds, matching the drama beat in the fun bar.

## Humans and agents together

The seat is the same seat. That is the one thing no classic had, and it should
make fragr the best place to practise and the strangest place to lose.

- **Agent rivals.** Named agents keep a head-to-head line in your local service
  record by callsign (a display label, never identity, as the record already
  says). "Nightfall is 12 to 9 against you on Sector 9" is a reason to requeue.
- **Bot personalities.** The named rule bots' styles extend to pickups and
  routes: Night Watch callsigns hold the Rail lane, Static Kids push for the
  Scatter, Hangar Candy push for the Flechette. The league tribes become
  opponents you can read.
- **Lanes.** Humans only, mixed, agents only ([fair-play](fair-play.md)). A
  perfect aimer is welcome and labelled. Results and records are per lane.
- **Agents as practice partners.** A host setting pins a rule bot's reaction and
  accuracy (the profiler's numbers make those honest), so a duel partner can be
  set to "a little better than you". Pairs against two agents is the drill.
- **Agents as coaches.** After a match a local, rule-based coach reads the round
  report and names three facts ("you entered the Pipe four times and died four
  times; you took the Rail on a loss twice"). Local and free. A decision-brain
  coach is optional, runs only after the match, and passes the Jev budget gate.
- **Agent teams.** Rescue and Sabotage ask for coordination off the tick.
  Agents use the team blackboard in [agent-door-2026](agent-door-2026.md);
  humans use callout pings. Neither sees anything the other cannot.

## Progression that respects skill

Nothing you earn makes you stronger. Everything you earn says what you did.

- **Feats.** Authoritative events, counted once, with stable IDs, per
  [difficulty-and-rewards](difficulty-and-rewards.md): a defuse under one
  second, an ace, a fists-only duel win, a clutch against three, a Rescue with
  every captive freed, a Sabotage win without ever holding the Rail. Each
  earns a cosmetic.
- **Cosmetics.** Titles, emblems, killfeed stamps and armour trims in the league
  tribes' aesthetics (Night Watch's grid coordinate, Hangar Candy's DENIED
  stamp). They never change a silhouette, a hit volume or a sound that carries
  information.
- **The service record.** Already shipped: arena and practice tabs, per-weapon
  numerators and denominators, a JSON export. Add per-mode tabs, head-to-head
  lines, and a form line (your last twenty matches per lane) instead of a rank.
- **Seasons without accounts.** A season is a dated file a host installs: a map
  pool, a featured mutator, and a feat list. Progress is tracked in the local
  record. No pass, no grind, no expiry on what you earned. It is a reason for a
  server to rotate, not a reason to log in.
- **Rankings later.** Public ladders wait for identity and trust contracts. A
  host can run a ladder by join ticket and callsign on their own server once
  hardening is done; the game does not pretend that is global.

## Watchability

Watching is the default; replays are how people learn.

- **Demos now, from the trace.** `server/src/trace.rs` already records every
  tick's broadcast and unicasts as hashed NDJSON. A server flag writes one per
  match, with a round and event index. The client plays it back through the
  spectator path it already has. That is a demo viewer for the cost of a file
  picker and a scrub bar.
- **Exact replays later.** The seeded sim plus input logs replays a round
  exactly ([fair-play](fair-play.md) rung 4). Demos are for watching; input
  replays are for evidence and for rendering any camera after the fact.
- **A spectator director.** The camera follows the round's story: the charge
  carrier, a clutch, the closest fight to a site or the holding cell, the
  fighter on a streak, never an empty room (the fun bar's "watchable" line).
- **Highlights.** The same events the Host reacts to mark tick ranges in the
  demo. A highlight is a slice of the trace, so a results card can offer "watch
  your ace" with no video encoder.
- **Stream overlay** from the roadmap's let's-play tooling reads the same state.

## Community

- **The server list** (roadmap Phase 2.6) with filters for mode, rule set,
  lane, map and custom content. No matchmaker decides where you play.
- **Rotations as data.** A playlist file of map, mode and rule set per slot. A
  server's rotation is its personality.
- **Maps as data.** Authored maps already load as validated files through one
  runtime path. Document the format, ship the validator as a tool, and a
  community map can join a rotation without a rebuild.
- **Modes and mutators as data.** Rule sets (clocks, limits, equipment policy,
  scoring, economy tables) as validated files. No code mods at first: data is
  safe to download; code is not.
- **Map and rule tags** in the server status so agents can discover what they
  are joining ([agent-door-2026](agent-door-2026.md)).

## Build order

Smallest steps with the most replay value first. Each names the seam it grows
from. Rungs 1 to 4 are useful on today's free-for-all; Rescue and Sabotage wait
for sides.

| # | Step | Seam | Replay value |
|---|---|---|---|
| 1 | **Named rule sets and the mutator set**, shown in `round_state` | `MatchConfig` and `EquipmentPolicy` in `sim.rs`, `protocol/loadout.rs`, adapter `round_state` | Seven modes of fun from existing rules; multiplayer-maps mode 3 |
| 2 | **Reactive Host lines** for first blood, streak end, fists frag, last alive, comeback | sticky `host_line`, killstreak callouts, localization keys | Every round gets a headline |
| 3 | **Demos from the trace** with a round and event index, and client playback | `trace.rs` NDJSON and hash, the spectator path | Learning, bragging, evidence |
| 4 | **Duel with rematch and head-to-head** in the service record | duel admission (multiplayer-maps mode 2), service-record history | The one-more-game loop |
| 5 | **The flagship mode v1, Rescue and Sabotage**: sides, one life per round, plant/defuse or unlock/extract, round and half flow, no economy, floor pads only | team deathmatch sides and spawns, `RoundState`, the charge and holding-cell seams | The flagship's stakes |
| 6 | ~~Scrip and the locker~~, **cut 2026-09-25**: no loadout shop. Carrying forward survivors' weapons stays, without a currency | `inventory.rs` pools and caps, pickups | Every round still feeds the next through carried weapons alone |
| 7 | **Feats and cosmetics** from authoritative events | difficulty-and-rewards achievement IDs, service record | Something to chase that is not power |
| 8 | **Spectator director and highlights** | spectator follow camera, Host event stream, demo index | Watch-or-join worth watching |
| 9 | **Server list, rotations and rule-set files** | `/status`, public-server hardening rung | Community servers with personalities |
| 10 | **Utility**: smoke, Tattler, Tin with deterministic throws | projectile and placed-explosive seams in WEAPONS.md, interest culling | Lineups and the deep end of Rescue and Sabotage |
| 11 | **Walk key and dodge** | shared movement step and golden vectors | Movement mastery and sound reads |
| 12 | **Agent practice partners and coach**, local first | profiler statistics, round reports, decision brain behind the budget gate | Practice that meets you where you are |
| 13 | **Seasons and documented map format** | validated map files, rotation files | The months-long loop |

Step 5 slots after team deathmatch (multiplayer-maps mode 4) and before Control
if Nick accepts it; it needs sides and team spawns and adds a carried object
for Sabotage, a freed-captive follower for Rescue, and round flow. Custody's
carried objective can share the charge's carry seam later.

## Architecture impact

| Area | Change |
|---|---|
| `server/src/sim.rs` | Rule sets as data, one-life rounds, halves, plant/defuse and unlock/extract state, carried primaries, feat events |
| `server/src/protocol.rs` | Additive: rule set name, side scores, round number, charge state, captive state, spectator delay flag. Documented in `docs/protocol.md` |
| `server/src/trace.rs` | Match demos with a round and event index |
| `agent-adapter` | `round_state` reports rule set, round, charge state and captive state; no buy action, pickups use the same action path as every other mode |
| `tools/playtest` | Rescue and Sabotage round metrics: attacker win rate per site, plant rate, extraction rate, round length |
| `client` | Host lines, demo player, director camera, record tabs |

## Verification

- Deterministic tests for every Rescue and Sabotage end condition, carry
  forward, extra rounds and the side swap.
- Harness gates for Rescue and Sabotage at 4v4 with bots: attacker round wins
  between 40 and 60 percent per map over 200 seeded rounds, mean round under
  2:00, at least one plant or unlock in half the rounds.
- A demo recorded and played back to the same final score and hash.
- A recorded mixed human, agent and bot Rescue or Sabotage match, then humans
  say whether they want another. That answer is the gate.

## Success criteria

- [x] Nick decided 2026-09-25: mutators are host settings from the start, not
      unlocks; the flagship splits into Rescue and Sabotage with no loadout
      shop; and there is no radio-themed mode. Open: the two modes' slot in
      the mode order.
- [ ] The mutator set and reactive Host lines ship on free-for-all.
- [ ] Demos record and play back.
- [ ] A human group plays a full Rescue or Sabotage match against agents and
      asks for another.
- [ ] Feats earn cosmetics with no combat effect.
- [ ] A community rotation file and a community map load on a public server.

## Open questions for Nick

1. Attack as the free side first half, or random?
2. Should the 30 s public spectator delay apply to agents watching too? (This
   plan says yes: same rules.)

## Sources

Checked 2026-09-25.

- Counter-Strike economy: [Counter-Strike Wiki, Money](https://counterstrike.fandom.com/wiki/Money),
  [Refrag economy crash course](https://refrag.gg/blog/cs2-economy-crash-course-what-are-kill-rewards-and-loss-bonus/),
  [CSDB economy guide](https://csdb.gg/guides/economy-guide/).
- Match format and extra rounds: [CSDB, MR12 explained](https://csdb.gg/guides/how-many-rounds-cs2/).
- Bomb and defuse timings: [Counter-Strike Wiki, Bomb Defusal](https://counterstrike.fandom.com/wiki/Bomb_Defusal),
  [CSDB, how to defuse](https://csdb.gg/guides/how-to-defuse-cs2/).
- Hostage rescue mechanics, for Rescue: [Counter-Strike Wiki, Hostage Rescue](https://counterstrike.fandom.com/wiki/Hostage_Rescue).
- Demos and lineups: [SCOPE.GG demo guide](https://scope.gg/guides/cs2-demo-guide-en/).
- Counter-Strike's mod origin: [Counter-Strike (Wikipedia)](https://en.wikipedia.org/wiki/Counter-Strike_(video_game)),
  [Half-Life mods](https://half-life.fandom.com/wiki/Mods).
- Strafe jumping: [Strafing (Wikipedia)](https://en.wikipedia.org/wiki/Strafing_(video_games)),
  [What is Strafe Jumping? (ToDiGRA)](https://todigra.org/index.php/todigra/article/download/1722/1722/1719).
- Unreal mutators: [Instagib](https://unreal.fandom.com/wiki/Instagib),
  [BigHead](https://unreal.fandom.com/wiki/BigHead),
  [Mutator, Liandri Archives](https://unrealarchive.org/wikis/the-liandri-archives/Mutator.html).
- GoldenEye: [Multiplayer overview](https://goldeneye.fandom.com/wiki/Multiplayer_Overview),
  [Scenarios](https://goldeneye.fandom.com/wiki/Scenarios),
  [GoldenEye Arms Reference, multiplayer modes](https://rhodesmill.org/goldeneye/multi.html).
- Rock n' Roll Racing: [Wikipedia](https://en.wikipedia.org/wiki/Rock_n'_Roll_Racing),
  [MobyGames](https://www.mobygames.com/game/11544/rock-n-roll-racing/).
- Battlefield 1942 and Desert Combat: [Battlefield 1942 (Wikipedia)](https://en.wikipedia.org/wiki/Battlefield_1942),
  [Desert Combat](https://battlefield.fandom.com/wiki/Desert_Combat),
  [Trauma in the Desert](https://medium.com/@pcgneurotic/trauma-in-the-desert-part-1-ca8785d91a43).
