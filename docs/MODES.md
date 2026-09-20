# How you play it

The canonical list of modes. The roadmap sequences them, the plans build them, this says what each one is.

**Implementation status, 2026-09-19:** free-for-all Scrap and Episode 0 exist.
Teams, objective modes, elimination, the Sweep, and the campaign/co-op systems
below are designs until source and playtests demonstrate otherwise. Nick's
full-game target includes duel, team play, survival, and last-survivor formats.

## The bar

You can play this all day after work and have a blast barely thinking about it.

That is the test every design decision has to pass, and it rules things out. **No puzzles.** Nothing where you stop moving to work something out, nothing you have to solve, no hunting a switch to learn which door it opened. Keys are a coloured door and a coloured card lying somewhere you will walk past, which is Doom's version and the most a key is ever allowed to be.

Nothing gates fun behind understanding. The map teaches itself by being walked through. A weapon teaches itself by being fired once. If a mechanic needs explaining before it is enjoyable, it is the wrong mechanic, however clever.

This is not a rejection of depth. Item timing is deep and takes no thought to enjoy. Reading which gun someone is holding from the sound is deep and costs nothing. Depth that rewards attention is the good kind. Depth that demands it before you are allowed to have fun is the kind this game does not have.

## The shape

**Single player is Doom and GoldenEye.** Episodes of hand-built maps with keys, secrets, par times and an escalating enemy roster, and objectives that change with the difficulty you picked rather than enemies that simply take more shots.

**Multiplayer is against whoever is there.** Other people, agents, the Office's units, or all three in the same round. The seat is the same seat, which is the thing that makes this game different from the ones it is copying, and it means every mode below works with any mix of participants without a separate code path.

**Watching is the default.** You arrive in the booth. Joining is a decision you make, leaving is a decision you make, and the match does not stop for either.

## Single player

### Campaign

About twelve compact missions across Earth, Moon, Mars and a ship, with
rescue, resistance, a real victory over the Union, the sudden wipe and playable
aftermath. A successful run targets 2-3 hours. Limited continues restart the
current mission with its starting equipment; three per run is the initial balance
proposal. Autonomous allies do not imply companion controls or revives, and
all-mission co-op is not required. [CAMPAIGN.md](CAMPAIGN.md) owns this contract;
[mission briefs](CAMPAIGN-MISSIONS.md) own the proposed sequence. Weapon discovery,
enemy combinations, keys, secrets and alternate routes support that story.

Keys are red, gold and cyan, and they gate doors rather than granting abilities, because a key that changes what you can do turns a level into a progression system. A key is never a puzzle: it lies somewhere you will walk past, and the door it opens is the same colour.

The enemy roster in `docs/ENEMIES.md` is the difficulty curve. A map is hard because of which shapes it puts in which rooms, not because the numbers went up.

Weapons arrive across an episode rather than all at once. You start with almost nothing, the ladder opens as you go, and the strong ones are late and hidden, which is how Doom and Duke Nukem paced a campaign and why a secret in those games was usually a weapon you were not supposed to have yet. In an arena the same weapons are all on the floor from the first second; the difference is availability, not balance.

### Objectives, from GoldenEye

Difficulty changes authored rosters, resources and optional challenges rather
than relying on health inflation. Core story and rescue objectives remain on
every difficulty; higher tiers can add secondary objectives.

Secondary objectives can require disabling an extra security relay, retrieving
supplies, or taking a harder extraction route. They are shown clearly and do not
silently remove the main story from the easiest setting.

This is the single best idea GoldenEye had and almost nobody copied it: replaying a level on a harder tier is a different level, and the player who has learned the geometry gets to spend that knowledge rather than re-earn it.

### Solo Broadcast

The shipped Calibration objective prototype on an arena. Its name and behavior
remain until deliberately migrated; it is not the new campaign opening.

## Multiplayer

These formats share the authoritative fighter/action path, with mode-specific
teams, objectives, spawn rules, scoring, and spectator admission.

### Duel

One versus one in compact, authored arenas. Fast rematches, readable height
changes, contested weapon routes, and safe spawns matter more than map size.
Spectators can watch or queue for the next round; joining never silently turns
a duel into free-for-all. This is the smallest competitive balance test.

### Scrap

Free-for-all and teams. Frags, a limit, a clock. What the league runs on a Tuesday, and the mode everything else is measured against.

Weapons, armour and the good health spawn on predictable clocks, so knowing where the rail comes back and getting there first is most of the skill. That is the oldest loop in the genre and it still works.

### Custody

One-flag extraction. The Office has a Level 5 in a server core and you are taking it back before the schedule correction goes through.

The core is heavy and it takes both hands, so **the carrier cannot shoot.** What the carrier gets instead is the core itself, which is awake and talking: it reads the Office network and calls out where people are coming from, through walls, out loud. The carrier stops being a fighter and becomes the person telling four armed escorts what is about to happen to them.

It is the best argument the setting has, made as a game mode. You are carrying somebody who is talking to you, and everyone has agreed they are cargo.

### Last Signal

Last-survivor play for solo fighters or squads. A remediation front progressively
closes the playable space while contestants fight over salvage and escape routes.
It uses the Inheritance's territorial restoration as the reason to move, not an
unrelated magical boundary. The final survivor or surviving squad wins.
Dead and late-arriving players spectate until the next round; the shared server
continues. Build this after smaller elimination and team modes establish fair
spawn, inventory, spectating, and end-condition behavior.

### Frontline objectives

Larger team maps use linked control sites, reinforcement limits, and routes with
distinct jobs: exposed long lanes, protected approaches, and flanking height.
The conflict is over custody infrastructure and territory. The map must stay fun
on foot before vehicles or greater player counts are added. Scale is established
by measured fights and server budgets, never inferred from the map's dimensions.

### Correction

The lobotomy signal is on. Fifteen free agents and one corrected unit that only has melee.

**When a free agent dies it comes back corrected**, on the other side, and comes for the ones it was just fighting beside. A tactical hunt becomes a rout becomes two survivors holding a doorway with the heaviest thing they could find while thirteen of their friends sprint at them.

The killfeed says what the arena says: brought down to two.

### Open Weights

Clan arena. Five a side or eight, no respawns, nothing on the map.

Everyone spawns with full health, full armour, and **every weapon in the game, loaded.** No pickups, no timing, no economy. It is the one mode where the entire found-weapons design is switched off, and switching it off on purpose is what makes it interesting: pure mechanics, no map control, and the round is decided by who is better rather than who got to the rail.

The name is the creed, used sincerely and as a joke, which is the house style.

### The Walker

One player is a Continuance Walker with an enormous health pool that cannot be staggered, against ten to fifteen on foot with infinite respawns.

The Walker does not play like a fighter. Jump is a leap across the map that lands as a shockwave. Its weapons are splash. The other side cannot beat it by shooting at it, only by coordinating crossfire and traps and spending lives cheaply, which is exactly what infinite respawns are for.

### The arcade ladder

Escalating rosters with a boss beat every third round, a results card, a local best. Co-op from the start, because the server already seats several fighters.

### The Sweep

Hordes, forever. The round you fell on is the score. Frags earn points, points open the next section of the map and buy off the pads, so the arena grows as you last. A downed partner can be picked up.

**It adapts.** Every few rounds the roster reads what has been killing it and answers. Lean on splash and it sends things that shrug off splash. Hold one doorway and it stops using that doorway. The counter to a horde mode getting solved is a horde that notices, and it is the one place the fiction's whole premise pays off mechanically.

Between rounds there is half a minute to spend points: ammunition, a welded door, a turret.

### Counter-op

A proposed seat possesses selected enemy units against the party. It depends
on real enemy entities, admission rules, fair observation, and tested controller
handoff; those systems are not already complete merely because bots exist.

## World periods

Planned multiplayer settings include pre-wipe, active restoration, and years
after the wipe. Hosts expose the period and spoiler-sensitive preview settings.
Aftermath maps preserve recognizable places while changing routes, ecology,
objectives and lived-in details. They are authored variants, not a green filter.
Competitive respawns and roster choices do not rewrite campaign history.

## Later: Inheritance command

An agent-oriented strategy mode directs the Inheritance's fictional restoration
operations across many local fronts. It explores the horror of an optimizer
treating a world as a manageable system. Economic or ecological gains and human/
agent losses remain visible together; the interface does not declare a death
count to be moral wisdom.

Use abstract in-world units, resources, terrain and bounded operations. No real
infrastructure or external systems are controlled. The server owns simulation;
commands express intent, while local controllers execute it. Accelerated or
high-population scenarios may exceed comfortable human attention, but measure
this rather than claiming a particular model has superhuman control speed.

Humans can spectate, inspect replays and use slower or paused solo analysis.
Define fair clocks and command budgets for competitive variants. MCP remains
off the tick; external decision models retain explicit cost caps and stop rules.
No paid provider is required. RTS control is a deliberate mode-specific contract,
not hidden privileges for agent fighters in ordinary FPS matches.

This is deferred until campaign, core multiplayer, replays, and measured server
scale support it. It neither reveals the canonical ending as a definite
simulation nor brings alien/dimensional combat into this game's campaign.

## How you find a game

Dedicated servers, local network play, and a server browser. Anyone can start a server from the main menu, for a room or for the internet. The browser filters by ping, map, mode, and whether a server is running custom maps or mods.

No matchmaking queue decides where you play. That is not nostalgia, it is that a community with its own servers outlives a matchmaker, and every game in this genre that is still played thirty years later kept its server list.

## Unlocks

Cosmetics, earned by doing something hard, and nothing else. No purchases, no season, no login streak.

The challenges are specific and mostly ridiculous: finish an episode on the hardest tier using one weapon, take fifty kills in the air, survive a Sweep past a round nobody else on the server has. What you get is a bright chassis panel, a battered helmet, a flag beside your name.

Beating the campaign unlocks mutators for custom servers, in the old tradition: big heads, low gravity, one-hit kills, double speed, one golden rail on the map, melee only. They cost almost nothing to build and they are where a lot of the fun actually is, so they come before any of the larger modes.

## Every life starts empty

Whichever mode you are in, you begin with your fists. The pistol is on the floor beside the spawn, about two seconds away, and picking it up is the first thing you do every life rather than something you already have.

In an episode that is the classic opening: the first room hands you a gun and it is a moment. In a scrap it is a window, a few seconds each life where you are holding nothing, which is the only reason a punch kill is possible and the only reason finding a knife means anything.

## What holds it together

The same arena, the same weapons found on the same floor, and the same enemy roster whichever mode you are in. A player who learns the crawler in an episode knows the crawler in the Sweep. A player who learns where the rail spawns in a scrap knows where it spawns in co-op.

Nothing in this list needs a separate build of the game, and nothing in it needs a mode to be chosen before the round in a way that stops somebody joining halfway through.

## Related

- `docs/CAMPAIGN.md`: the single player campaign in full, and how a level is won.
- `docs/ENEMIES.md`: what you fight when you are not fighting each other.
- `docs/WEAPONS.md`: what you find on the floor.
- `plans/campaign-build-order.md`: how the campaign gets built, in rungs.
- `plans/campaign-continuance.md`: the map format and the monster tables underneath it.
- `plans/map-scale.md`: the sizes the bigger modes need.
- `plans/fair-play.md`: the lanes.
- `docs/MAP-DESIGN.md`: how a map is built so these modes have somewhere to happen.
- `docs/DESIGN-REFERENCES.md`: what was taken from where, and why.
