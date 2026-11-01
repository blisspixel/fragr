# Locational damage and Helldivers 2: lessons for fragr

Research of 2026-10-31 and the design source for locational damage (#533). A proposal until Nick decides the open choices below; adopted parts are built and measured through issues.
Sources are cited inline; anything marked UNSOURCED is the author's inference
or could not be verified. Some numbers come from community wikis and press
summaries, not from the studios; treat them as approximate.

## 0. Short answers

1. **Body parts: yes, but few and loud.** Three height zones (head, torso,
   legs) on the existing fighter cylinder, round multipliers per weapon class,
   and a distinct sound and marker for each. Different damage per part for
   *campaign enemies* is where the real fun is (Union red optics and rear
   vents as weak points, plates that bounce, Inheritance cyan indicators). In
   multiplayer, human and synthetic fighters must share one hitbox and one
   table: a body look is a cosmetic choice, and the league's rules are the
   same for both kinds of person. No player limb injuries in multiplayer.
2. **Helldivers 2:** its fun comes from one consistent rule set that hurts
   everyone (friendly fire, physics), committed call-ins under pressure, shared
   stakes (a ticket pool, extraction), loud readable armour feedback, enemies
   with distinct counters, a live war narrated back to the community, and a
   sincere score under satire. Its failures were fun-removing nerfs, opaque
   armour maths, a forced account link, degrading performance, install bloat
   and kernel anti-cheat. fragr can take most of the first list cheaply and
   already avoids most of the second by design.

## 1. fragr today (read from source)

- Hit volume: a vertical cylinder, radius 0.5 m (`movement.rs` `RADIUS`),
  height 1.8 m standing, 1.35 m ducked (`BODY_HEIGHT`, `DUCK_HEIGHT`). Short
  bodies (Crawler, Notary) and flying equipment have their own volumes
  (`combat.rs` `target_height`, `flying_half_width`).
- One zone: `head_hit` / `head_hit_for` in `server/src/combat.rs`. The band
  starts at `HEAD_GATE` 1.45 m (top quarter on short bodies, dropped by 0.45 m
  when ducked). `HEAD_DAMAGE_SCALE` 2 for every traced weapon except Fists,
  Shiv and Article Blade (`head_bonus`). No leg or arm zones.
- Armour: one scrap pool, `PLAYER_MAX_ARMOR` 100, Custody Plate to 150,
  absorbs 100% of damage before HP (`sim.rs` `resolve_fighter_hit`); the Arc
  ignores it (`WeaponType::ignores_armor`). Head doubling happens before
  armour.
- Humans and synthetic fighters are identical in damage. Presentation already
  differs: `client/scripts/shot_effects.gd` picks FLESH or SYNTHETIC surface,
  sparks off machines, droplets off a body, lint with Blood off
  (`settings.gd` `blood`).
- Campaign enemies already have positional rules (`sim.rs` `shielded`,
  `encounters/enemy.rs`): Auditor frontal plate halves traced damage within
  60 degrees; Assessor plates halve or quarter, recovery joints take full,
  covered splash wraps plates (`docs/ENEMIES.md`); Surveyor closed shutter
  turns two thirds, open lens takes full; armoured kinds (Heavy Sweeper,
  Turret, Enforcer, Assessor, Paver, Surveyor) only stagger at 40+ damage in a
  tick (`STAGGER_DAMAGE`).
- Wire: `ShotResult.head` (bool) and playtest `heads` counters exist.
- Lag compensation: `server/src/sim/rewind.rs`, 4 ticks (200 ms) cap, history
  of `Volume { feet, ducking, epoch }`; cover never rewinds.
- 1.0 bar (`docs/ROADMAP.md`): clean-hit TTK 0.5 to 1.2 s, no non-power
  weapon under 0.5 s, median 0.8 to 1.5 s; no weapon over 45% share; feedback
  gate "body, head and kill told apart by sound"; readability gate 3:1
  contrast. `docs/plans/fun-craft-targets.md` says keep 2x heads, target
  15 to 35% headshot share of hitscan kills.

**Existing finding.** With 2x on every gun, today's all-head clean-hit TTK on
a bare spawn is already below the 0.5 s floor: Flechette 50 x 2 = 0.20 s,
Repeater 28 x 4 = 0.60 s (with warmup), Tack 40 x 3 = 0.50 s, Rail 160 x 1 =
one shot. The gate is presumably meant for body hits, but the doc does not say
so. Whatever is decided below, the gate should name which zone it measures.

## 2. Locational damage across shooters (research A)

### Helldivers 2
- AV and AP share one 0 to 10 scale (0 unarmoured to 4 heavy, 5 to 10 tank
  tiers, 11 indestructible). AP above AV: 100% damage, red hitmarker; equal:
  65%, white marker; below: 0%, ricochet
  (https://helldivers.wiki.gg/wiki/Armor_Penetration).
- The partial band was 50% until patch 1.001.100 (17 Sep 2024), which raised it
  to 65% because 50% was "overly punishing" and caused "an excessive reliance
  on high armor penetration weapons"; the same patch cut heavy armour on
  Hulk, Charger, Bile Titan and Impaler, and cut enemy headshot bonus from
  +100% to +50% (https://helldivers.wiki.gg/wiki/1.001.100).
- Durable damage: a second damage value blended by each part's durable
  percentage; explosions count fully durable (Armor Penetration page).
- Enemy parts have their own HP pools passing a share to main HP: Charger
  main 2,400, head fatal, butt 950 at AV0 (destroying it bleeds the Charger
  out), inner flesh under plates passing 300%, fatal legs
  (https://helldivers.wiki.gg/wiki/Charger). Trooper arms 65 HP passing 50%.
- Player parts (wiki, tagged possibly outdated): head 150% damage, chest
  100%, limbs 85%; broken chest bleeds 10 DPS until stimmed; broken arm sways
  aim; broken leg slows and zeroes stamina; stims fix everything
  (https://helldivers.wiki.gg/wiki/Helldiver).

### Counter-Strike 2
- Head x4, chest and arms x1, stomach x1.25, legs x0.75; legs ignore Kevlar;
  only a helmet covers the head (https://csdb.gg/damage-calculator/).
- Armour penetration per gun: AK-47 36 base, 77.5%, one-taps through a
  helmet; M4A4 does not (csdb.gg). Breakpoints are the memorable output.
- CS2 sub-tick timestamps inputs inside a 64 Hz tick (secondary sources:
  https://primagames.com/gaming/cs2-tick-rate-changes-explained).

### Halo
- Precision headshot kills an unshielded target; no head bonus against
  shields; Halo 5 and Infinite give automatics bonus head damage but no
  instakill, with a distinct critical marker (https://www.halopedia.org/Headshot).
- Reach had no shield bleedthrough until the title update made it optional
  (https://halopedia.org/Halo:_Reach_Title_Update).

### Battlefield
- BF4 head multiplier 2.0 raised to 2.13 (PC Gamer, from a search excerpt,
  https://pcgamer.com/battlefield-4-spring-update); 2042 community figures:
  ARs and SMGs about 2.15, snipers 4, sidearms 1.25 (low confidence,
  https://gameskeys.net/weapon-tips-for-battlefield-2042/); Battlefield 6 rifles
  about 1.4 (https://allthings.how/?p=272023). BF1942 zones UNSOURCED.

### Rainbow Six Siege
- Head x50 (one shot), torso x1, limbs x0.75 (x0.65 at 3 armour); the
  highest zone a bullet passes through counts; stated goal is to make it clear
  where a bullet lands and reduce perceived bad hit registration
  (https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/3JoP5bWperGVXX3N0nNHlM/dev-blog-limb-penetration-system).
- Siege X cut limbs to about 50% of torso and was reverted because limbs are
  the only target against shield operators
  (https://siege.gg/news/ubisoft-to-revert-limb-damage-change-introduced-with-rainbow-six-siege-x-release).

### Valorant
- Vandal 160 / 40 / 34 (head x4, legs x0.85), no falloff
  (https://www.dodge.gg/en-US/valorant/news/vandal-weapon-guide-2026).
- Riot on netcode: 128 Hz, peeker's advantage about 141 ms baseline, and "a
  delta of 10ms of peekers advantage made the difference" between 90% holder
  and 90% peeker win rates; rewind capped, server never trusts the client
  (https://www.riotgames.com/en/news/peeking-valorants-netcode).
- A body-shot particle that reads as a headshot is treated as a readability
  bug (already cited in fun-craft-targets:
  https://playvalorant.com/en-us/news/dev/ask-valorant-4).

### DOOM 2016 and Eternal
- Destructible demons show damage taken
  (https://doomwiki.org/wiki/Destructible_demons, search excerpt).
- Weak points change behaviour: Revenant shoulder rockets (also its jetpack:
  break them and it is grounded), Arachnotron turret, Mancubus arm cannons,
  Cyber Mancubus armour removed by Blood Punch, Cacodemon grenade in the mouth
  (https://www.thumbsticks.com/how-to-exploit-demon-weaknesses-doom-eternal/).

### Fallout, Apex
- VATS crippling: a limb bar empties and the limb stops working; crippled
  head lowers accuracy (https://breezewiki.discard.no/fallout/wiki/VATS).
- Apex helmets once cut headshot damage 20 to 65% by tier; Season 24 removed
  the reduction because it "makes damage more consistent, understandable, and
  easier to calculate"
  (https://www.ea.com/games/apex-legends/news/takeover-patch-notes).
- Cyberpunk 2077 not researched.

### What makes it feel good versus frustrating
1. **Few zones, round numbers, memorable breakpoints** (CS, Valorant). Players
   learn "two heads with the Tack", not percentages.
2. **Three outcomes with three markers** (Helldivers pierce, partial, bounce).
   The middle band must not be punishing or one weapon class takes over
   (1.001.100 lesson); fragr's 45% share gate is exactly that failure.
3. **No hidden modifiers on the head** (Apex removed helmet mitigation).
4. **Limbs close to body** (0.75 to 0.85); a big limb penalty is frustrating
   when legs are what you can see (Siege revert).
5. **Precision gets the big head reward, sprays a small one** (Halo 5 and
   Infinite, BF, Helldivers' cut to +50%).
6. **PvE weak points should change behaviour, not just numbers** (Doom).
7. **Player limb injuries suit slow co-op survival, not fast arena play**
   (UNSOURCED inference: a slowed leg at 6 m/s with a 4 s respawn is pure
   frustration, and it fights the movement gate).
8. **Netcode decides fairness.** At 20 Hz with 50 to 100 ms interpolation, a
   small head box registers inconsistently. Keep the zones large, height
   based, and rewound with the same history; keep a shot audit.
9. **Feedback per zone**, in sound first (the 1.0 gate already requires body,
   head and kill to be told apart by sound).

## 3. Helldivers 2: why it is fun (research B)

### Pillars
- Pilestedt: "The most important thing when we make games is believability...
  we must have friendly fire"; "A good co-op game forces players to play
  together, but a great one makes players want to play together"
  (https://blog.playstation.com/2024/03/12/helldivers-2-how-arrowhead-turned-the-twin-stick-shooter-original-into-a-bombastic-ps5-sequel/).
- "A game for everyone is a game for no one" (Pilestedt, June 2024,
  https://www.pcgamer.com/games/rpg/helldivers-2-director-weighs-in-on-elden-ring-shadow-of-the-erdtrees-difficulty-a-game-for-everyone-is-a-game-for-no-one/).
- Friendly fire stays because it is the same rule as bullets hitting enemies
  (https://www.shacknews.com/article/139269/helldivers-2-friendly-fire-stays-on);
  Beroshi: it "enhances the satire and that feeling of unpredictability and
  chaos. It's also a thing about mastery"; "We don't want death to feel like a
  vast loss"
  (https://www.pushsquare.com/news/2024/02/friendly-fire-at-the-core-of-helldivers-2-all-for-a-good-laugh-and-chaos).
- No PvP, to keep the community supportive
  (https://mein-mmo.de/en/helldivers-2-does-not-have-pvp-because-the-boss-thinks-its-too-toxic-if-you-want-pvp-i-recommend-tarkov,1091280/).

### Mechanics
- **Stratagems**: arrow codes typed under fire, then a thrown beacon; orbitals
  slow and big, eagles fast with uses; supply, defensive and mission
  categories; four per loadout; codes share a first arrow by category; an
  arcade cabinet on the ship for practice
  (https://helldivers.wiki.gg/wiki/Stratagems,
  https://helldivers.wiki.gg/wiki/Stratagem_Hero). Why the combo is fun:
  no developer quote found; the reading is that it makes the player commit at a
  vulnerable moment (UNSOURCED inference).
- **Prone and ragdoll**: explosive damage cut sharply while prone (wiki via
  search); excessive ragdoll was on the 60-day fix list
  (https://pcgamer.com/games/third-person-shooter/helldivers-2-game-director-says-a-chargers-rework-and-an-update-to-fire-damage-are-part-of-a-60-day-update-plan-what-matters-most-now-is-action-not-talk).
- **Reinforcement**: a shared ticket pool (5 per player, up to 20), one back
  every 2 minutes when empty; the respawn is a steered hellpod that crushes
  enemies and allies; reinforcing near a body recovers its gear and samples
  (https://helldivers.wiki.gg/wiki/Reinforce).
- **Extraction**: call after objectives, long terminal code, a 2 minute hold
  within 50 m, shuttle will not land on a blocked zone, those left behind lose
  samples (https://helldivers.wiki.gg/wiki/Extraction).
- **Samples** fund 30 permanent ship modules
  (https://helldivers.wiki.gg/wiki/Samples); difficulty 1 to 10 scales maps,
  heavies and rewards (https://helldivers.wiki.gg/wiki/Difficulty).
- **Factions with distinct counters**: Terminids swarm (mobility, crowd
  control, fire), Automatons are ranged and armoured with head and rear vent
  weak points and fabricators killed through the vent, Illuminate have shields
  and hordes (https://helldivers.wiki.gg/wiki/Factions,
  https://u.gg/hd2/guides/armor-pen-helldivers2,
  https://helldivers.wiki.gg/wiki/Fabricator). Even a developer said of the
  armour system "Honestly I don't know either"
  (https://windowscentral.com/gaming/helldivers-2-dev-reveals-how-the-games-most-confusing-mechanic-works-but-only-kind-of).
- **Co-op**: shared boosters, team reload on backpack weapons, shared samples
  (https://helldivers.wiki.gg/wiki/Boosters).

### Tone
- Starship Troopers is "the most obvious" reference (Pilestedt,
  https://tech.yahoo.com/entertainment/articles/helldivers-2-boss-finds-starship-121936894.html).
- Intro: a Ministry of Truth video; the tutorial cheerfully gives a
  one-in-five survival rate and says "friendly fire is an unavoidable part of
  life" (https://inverse.com/gaming/helldivers-2-intro-tutorial-satire).
- Every enemy has a grievance the state created: bugs are farmed for fuel,
  Automatons want independence, Illuminate avenge a genocide
  (https://helldivers.wiki.gg/wiki/Factions); the Voteless are citizens turned
  into soldiers, a name that is only a joke from inside the regime
  (https://helldivers.wiki.gg/wiki/Voteless).
- Whether players read it as satire: NBC
  (https://www.nbcnews.com/news/amp/rcna140653); critics: GameSpot "fun, but not
  especially deep"
  (https://gamespot.com/articles/helldivers-2-should-become-even-more-like-starship-troopers/1100-6521454/),
  LA Review of Books "Fascist Pleasures and Failed Satire"
  (https://lareviewofbooks.org/article/fascist-pleasures-and-failed-satire/).
- Score: Wilbert Roget II, GDC 2025 "Scoring Satire with Sincerity"
  (https://gdcvault.com/play/1035494/-A-Cup-of-Liber); "Scoring should evoke
  genuine emotions, even in satire"
  (https://gamedev.net/news/3323-a-cup-of-liber-tea-scoring-satire-with-sincerity-in-helldivers-2-clip-2/).

### Live war
- A human Game Master (Joel) issues Major Orders and steers attacks
  (https://kotaku.com/helldivers-2-galactic-war-game-master-joel-1851297376).
- Malevelon Creek: players' obsession became a Major Order and a remembrance
  day (https://www.windowscentral.com/gaming/helldivers-2-players-are-obsessed-with-liberating-malevelon-creek-so-joel-gave-them-a-major-order-for-it,
  https://kotaku.com/helldivers-2-malevelon-creek-liberated-1851379768); "its
  greatest asset is its story, which is being told by the players themselves"
  (https://www.techradar.com/gaming/helldivers-2s-greatest-asset-is-its-story-which-is-being-told-by-the-players-themselves).
- Fatigue when orders felt unwinnable
  (https://www.destructoid.com/helldivers-2s-latest-major-order-has-finally-exhausted-players/).

### What failed
- Launch servers capped at about 450k concurrent
  (https://www.techradar.com/gaming/consoles-pc/helldivers-2-caps-its-concurrent-players-at-around-450000-to-help-server-instability).
- Nerf whack-a-mole: 01.000.300 changed 24 items; Pilestedt said they had
  "gone too far" (https://www.techradar.com/gaming/consoles-pc/helldivers-2-director-agrees-that-balancing-has-gone-too-far).
  Escalation of Freedom's nerfs pushed recent reviews to 42%
  (https://ggrecon.com/articles/helldivers-2-review-bombed-after-escalation-of-freedom-update-nerfs-it-into-oblivion);
  Eriksson: "balance should be fun, not 'balanced' for the sake of balance"
  (PC Gamer link above). The fix buffed players and cut enemy armour.
- PSN link requirement: over 100k negative reviews, delisting in about 177
  regions, reversed 6 May 2024
  (https://videogameschronicle.com/news/ouch-helldivers-2-dev-apologises-as-its-hit-with-over-100000-negative-reviews,
  https://gamedeveloper.com/business/sony-reverses-helldivers-2-s-account-linking-requirement).
- Performance degrading over patches, a rolled-back patch, a later
  "Performance Patch" (https://www.pcgamesn.com/helldivers-2/update-rolled-back,
  https://www.notebookcheck.net/Helldivers-2-Game-Director-admits-they-have-more-issues-than-before-after-the-last-major-update-future-content-delayed-to-improve-stability.1137687.0.html).
- About 154 GB install from duplicated data, cut to about 23 GB
  (https://tomshardware.com/video-games/pc-gaming/helldivers-2-install-size-slashed-from-154gb-to-just-23gb-85-percent-reduction-accomplished-by-de-duplicating-game-data-an-optimization-for-older-mechanical-hard-drives).
- Kernel anti-cheat broke Linux and Deck at launch
  (https://github.com/ValveSoftware/Proton/issues/7486).
- Concurrency: 458,709 Steam peak, down to about 20 to 30k, back to about 138
  to 150k with Omens of Tyranny and about 168k with the Xbox release
  (https://gamingbolt.com/helldivers-2-enters-steams-all-time-top-20-with-over-450000-concurrent-players,
  https://gameworldobserver.com/2024/12/16/helldivers-2-150k-ccu-steam-first-time-since-april,
  https://insider-gaming.com/helldivers-2-player-numbers-surge-on-steam-after-xbox-launch/).
  Content and story events bring people back; balance missteps send them away.

## 4. Mapping to fragr (research C)

### The tonal parallel
Helldivers 2 satirises a fascist bureaucracy from the inside: the player is
its willing soldier, and the joke is that the player cheers along. It works,
but critics argue it lets the power fantasy win. fragr satirises one from the
outside: the player resists the Union, and the comedy lives in the Union's own
voice (the Host, the radio, the paperwork, `the-chancellery.md` "Regulated to
the point of comedy"). That loses Arrowhead's irony but gains a clear moral
footing. The lesson that transfers is Arrowhead's sincerity: the score and
the world play it straight, and the jokes come from a consistent institution
doing absurd things with real consequences. Lore guardrails that change how
fragr can borrow:

- Union bots may be conscious and retain suffering (`people-and-agents.md`);
  captive suffering is never a punchline. So no comic dismemberment of bots,
  no Voteless-style joke about the victims themselves. Breaking a bot's
  issued hardware (plates, a mast, a rifle housing) is fine; making its pain
  funny is not.
- Every power may have been right about something. The Helldivers trick of
  giving every enemy a grievance the state created fits: the Union's fear was
  real, and the Inheritance protects the living world. Write enemy barks and
  radio with that in mind, not as pure villainy.
- No co-op revive or companion controls in the campaign (`VISION.md`), and
  Latch's fate is authored. Optional co-op is a 3.0 direction.

### Features, priority, cost, gate, risk

| # | Feature | Where | Priority | Cost | 1.0 gate | Risk |
|---|---|---|---|---|---|---|
| 1 | **Three height zones with per-class multipliers** (section 5) | MP, campaign, bots | High | Small | Fights (TTK floor and share), Feedback | TTK shifts; must rebalance sticky table and survey share |
| 2 | **Pierce, partial, bounce feedback**: four hit sounds and marker shapes (head, body, legs or plate, weak spot), one frame after `ShotResult` | All | High | Small to medium | Feedback (told apart by sound, blind test) | Sound clutter; must cut through mix (#524) |
| 3 | **Weak points that change behaviour** on campaign enemies: Union red optics as the head weak spot (the attack tell light becomes the target), Heavy Sweeper rear vent, Ranged Sweeper mast that cancels its precision shot when broken, Enforcer joints, Inheritance cyan indicators as the only full-damage surfaces, extending the Surveyor lens and Assessor joint rules | Campaign | High | Medium | Campaign craft (teach before test), Readability | Encounter rebalance across 20 levels; must be taught without text |
| 4 | **One consistent rule, chaos allowed**: friendly fire stays a team option (exists); add a "Hardcore" or "Full Liability" playlist preset with it on and self-splash honest, with Host lines that treat a team kill as a paperwork incident | MP | Medium | Small | Fun bar (human signals: quoting the Host) | Griefing on public hosts; keep off by default |
| 5 | **Called support as a committed, interruptible action**: a short directional input (three presses) to call one supply drop or a Union-requisitioned barrage in Conquest and Sabotage, with a thrown marker everyone can see and a 2 to 4 s arrival | MP team modes, later co-op | Medium | Medium to large | Power and pacing (contest index), Maps | Can bloat an arena shooter; must not replace pads. Never in FFA |
| 6 | **Respawn as a moment**: the team-mode respawn drop as a visible arrival (a requisition crate or a free-side scrap van) that can crush or shove an enemy standing on it | MP team modes | Low | Medium | Power and pacing (spawn deaths under 2%) | Spawn-kill abuse; needs safe-zone rules |
| 7 | **Shared stakes**: a team respawn ticket pool for a new Sabotage or Conquest variant, and a hold-the-zone extraction finale for the Wipe survival design | MP, Wipe mode | Medium | Medium | Maps (side balance 45 to 55%) | Another mode before stranger evidence (roadmap S7 says wait) |
| 8 | **Community war state**: a host-local "front" that records which maps the night's matches were fought on and narrates it through the Host and radio ("the Office regrets to report Larak Lot remains unlicensed") | MP, Host, radio | Low | Medium | Privacy (match-level only), fun bar | Radio stays small; a global war needs servers and spend; keep host-local, opt-in |
| 9 | **Sincere score under satire**: Roget's rule for the campaign score and the Host; the Union's propaganda funny by itself, the free side's music warm and real | Campaign, menus | High | Small (direction) | Completeness (score picked by ear) | None beyond taste |
| 10 | **Enemy counters by faction**: Union troops (cover and headshots), Union bots (plates; go for optics and vents), Inheritance (a different verb per machine; cyan only) | Campaign | High | Medium (mostly authoring) | Campaign craft (3 types per encounter) | Overlap with item 3 |
| 11 | **Bot ladder uses zones**: higher bot tiers aim higher (chest to head) and pick legs only when the torso is covered; agents see zone in `observe` hit events | Bots, agents | Medium | Small | Bots (tiers 65 to 80% win matrix, #526) | Bots that headshot too well feel like aimbots; cap per tier |
| 12 | **Avoid their failures** as rules: no account link; no kernel anti-cheat (server authority plus wave 22 interest filtering); balance by buffing the weaker gun first and changing one number at a time with a survey; size budget for packages; performance gates on every release | All | High | Small (policy) | Performance and stability, Platforms, Fair play | None; most already project law |
| 13 | Player limb injuries (slowing, sway, bleed) | Not in MP; maybe campaign hard tier | Low | Medium | Movement (would fight it) | Frustration; reject for MP |
| 14 | Prone dive with explosive reduction | Optional | Low | Medium (mirror plus goldens) | Movement | fragr already has dodge and rocket jumps; a dive adds a stance to every hitbox |

**What does not fit, and why.**
- Stratagem menus as the core loop: fragr is an arena shooter on timed pads;
  call-ins in FFA would break equal starts. Keep them to team modes and any
  later co-op.
- A live paid Game Master and a global persistent war: needs hosted services
  and spend, contradicts the privacy gate's match-level-only rule unless
  host-local, and makes the radio big. Host-local version only.
- Player-as-soldier-of-the-regime satire: fragr's player resists; a Union-side
  team mode already wears issued livery, which is the right amount of inside
  view.
- Warbonds and premium currency: no store, no accounts before 1.0.
- Comic gore against bots: lore forbids treating their suffering as a joke.

## 5. Locational damage proposal for fragr (research D)

### Zones
Height bands on the existing cylinder, measured from the feet, all shifted
down by `BODY_HEIGHT - DUCK_HEIGHT` (0.45 m) when ducked:

| Zone | Standing band | Notes |
|---|---|---|
| Head | 1.45 m to crown (existing `HEAD_GATE`) | Short bodies keep the top quarter |
| Torso | 0.85 m to 1.45 m | Arms fall in torso; no arm zone (a yaw-free cylinder cannot place them) |
| Legs | feet to 0.85 m | New; just under the hip line (half of 1.8 m is 0.9) |

No arm zone, no neck, no stomach. Three zones are what a 20 Hz cylinder can
register honestly.

### Multipliers by weapon class (integer, rounded down)

| Class | Weapons | Head | Torso | Legs |
|---|---|---|---|---|
| Precision | Rail, Sniper | 2.0 | 1.0 | 0.75 |
| Sidearm | Tack | 2.0 | 1.0 | 0.75 |
| Automatic | Flechette, Repeater | 1.5 | 1.0 | 0.75 |
| Pellet | Scatter (per pellet) | 1.25 | 1.0 | 0.75 |
| Energy | Arc | 1.0 | 1.0 | 1.0 (beam; it already bypasses armour) |
| Explosive | Rocket, grenade, mine, splash | none | 1.0 | none (no zone) |
| Melee | Fists, Shiv, Article Blade | none | 1.0 | none (unchanged) |

### Clean-hit TTK, 100 HP bare spawn (and 100 HP + 100 armour)

| Weapon | Head | Torso | Legs | Today's head (2x) |
|---|---|---|---|---|
| Tack 20 / 0.25 s | 40 x 3 = 0.50 s (1.00) | 20 x 5 = 1.00 s (2.25) | 15 x 7 = 1.50 s (3.25) | same |
| Flechette 25 / 0.20 s | 37 x 3 = 0.40 s (1.00) | 25 x 4 = 0.60 s (1.40) | 18 x 6 = 1.00 s (2.20) | 50 x 2 = 0.20 s |
| Repeater 14 / 0.10 s + 0.30 warmup | 21 x 5 = 0.70 s (1.20) | 14 x 8 = 1.00 s (1.70) | 10 x 10 = 1.20 s (2.20) | 28 x 4 = 0.60 s |
| Rail 80 / 1.00 s | 160 x 1 = one shot (1.00) | 80 x 2 = 1.00 s (2.00) | 60 x 2 = 1.00 s (3.00) | same |
| Scatter 7 x 10 (2 to 4 m) | 84 a blast, 2 blasts 0.60 s | 70, 2 blasts 0.60 s | 49, 3 blasts 1.20 s | 140, one blast |

Effects on the 1.0 bar: torso numbers are today's sticky table, unchanged.
The proposal lifts the all-head Flechette from 0.20 s to 0.40 s and removes
the one-blast head Scatter, so only the Rail (and Tack at exactly 0.50 s)
reach the floor by heads. Recommend the gate read: "torso clean-hit 0.5 to
1.2 s; all-head clean-hit at least 0.4 s for every non-power gun except the
Rail, whose bare-head one-shot is its signature (Quake and UT lineage, a
timed pad, 10 cells, 1.0 s cooldown)." The Rail head one-shot is Nick's call;
the alternative is Rail head 1.2x (96, never a one-shot). Legs at 0.75 keep
leg shots useful (Siege lesson) and nudge the median kill time up slightly;
measure it against 0.8 to 1.5 s.

### Armour and bodies
- **Multiplayer: one hitbox and one table for every fighter.** Humans and
  free agents fight under the same league rules; a synthetic look is a
  cosmetic choice from the wave 22 roster (#530) and must never change the
  volume or the damage. This also follows Valorant's integrity rule on skins
  (https://www.dexerto.com/valorant/valorant-devs-exploring-new-cosmetics-like-gloves-but-not-agent-skins-1478667/).
- **Scrap armour stays one absorb pool**, applied after the zone multiplier,
  covering every zone. No helmet modifier (Apex lesson). The Custody Plate
  stays the visible armour tier.
- **Campaign enemies get zone tables per kind** (extending existing rules):
  - Union human troops (Clerk, Redactor, Auditor): standard table; red visor
    is the head. Auditor plate unchanged.
  - Union bots (Sweeper, Heavy Sweeper, Ranged Sweeper, Turret, Crawler):
    plated torso at 0.5 ("partial", a clank marker), red optic head at 2.0
    for every gun class (the red attack tell light is the target, which is
    readable at 30 m by the faction contract), Heavy Sweeper rear vent 1.5,
    Ranged Sweeper mast breakable (cancels its precision shot until it
    retreats). No severed limbs; broken plates and housings only.
  - Enforcer (human, powered armour): torso 0.5, head 1.5, legs and joints
    1.0, heavy-hit stagger unchanged.
  - Absorbed bots after the wipe: same chassis table, but the weak spot moves
    to the cyan working glow where the red optic was. The player learns that
    the light changed and the weakness moved with it.
  - Inheritance machines (Paver, Surveyor): continuous off-white surfaces at
    partial (0.33 to 0.5), cyan indicators and open lenses full or better.
    Keep each machine's existing verb (Paver strip, Surveyor lens).
- **Latch and free allies** are not targets of the player; no table needed.

### Feedback
- Sound first (the gate): head a bright high "crack" (synthetic) or "tock"
  (human), torso the current chime, legs a lower, shorter tick, plate a
  metallic clank with a ricochet tail, weak spot a sharp break sound. Kill
  keeps its own sound.
- Marker: head a larger marker with a level flare (no rotation, per the
  no-tilted-text rule), legs a smaller marker, plate a grey broken marker.
- World: sparks off synthetic bodies and plates, a brief optic flicker on a
  synthetic head; blood droplets off a human body with Blood on, lint or dust
  with Blood off (existing). Damage states on campaign bots: a cracked plate,
  a dead optic (Doom's destructible demons, scoped to hardware).
- Spectators and the death recap (#528) show the zone of the killing hit.

### Server cost at 20 Hz with lag compensation
- Zone is one comparison of impact height against two gates, per pellet, on
  the existing cylinder intersection. The rewind history already stores
  `feet` and `ducking`, which is everything the zones need: no new state, no
  yaw history, no bigger snapshots.
- Arm zones or per-limb capsules would need yaw history in `rewind.rs`, more
  memory per frame and model-to-box alignment per look; not worth it.
- Wire: replace `ShotResult.head: bool` with a `zone` enum (head, torso, legs,
  plate, weak) and the playtest counters with per-zone counts; update
  `docs/protocol.md`, `agent-adapter/README.md` and client `shot_effects.gd`
  in the same PR (one current wire shape, no compatibility).
- Visual alignment: the rendered head, hip line and plates must match the
  bands; add a zone-band overlay to `tools/qa_tour.sh` captures and inspect
  every fighter look and enemy.

### Deterministic tests
- `combat.rs` unit tests: impact heights at each band edge for standing,
  ducked, short and flying bodies; NaN refusal (existing pattern).
- `server/src/tests.rs`: a table test asserting each weapon's head, torso and
  leg damage and the TTK table above (bare and armoured); armour absorbs
  after the multiplier; Arc and explosives ignore zones; rewound volume gives
  the same zone as an unrewound one at the same feet.
- Campaign: seeded tick tests per enemy kind: optic hit doubles, plate hit is
  partial, rear vent only from behind, mast break cancels the shot and its
  failure path (plate hit does not cancel), absorbed bot's weak spot is the
  cyan point.
- Playtest survey: report zone share, kill time quantiles and gun share before
  and after; gates are median 0.8 to 1.5 s, no gun over 45%, headshot share of
  hitscan kills 15 to 35% once bot tiers aim at heads.
- Client harness: each zone maps to its marker and sound within one render
  frame; blind listening check that head, body, legs and kill are told apart.

## 6. Top ten lessons (ranked)

1. Few zones, round multipliers, loud per-zone feedback. High, small. Fits.
2. Weak points that change behaviour: Union red optics and vents, Inheritance
   cyan. High, medium. Fits the faction contract exactly.
3. Pierce, partial, bounce marker language for plates. High, small. Fits.
4. Sincere score and world under satire. High, small. Fits; the Union's
   voice carries the jokes.
5. Balance by buffing, one number at a time, measured. High, small. Fits the
   survey workflow.
6. Never ship anything that taxes trust: account links, kernel anti-cheat,
   bloat, regressions. High, small. Already law.
7. Faction counters: each power asks a different verb. High, medium. Fits.
8. Committed call-ins for team modes only. Medium, medium to large. Fits as
   Union requisition paperwork or free-side scrap drops.
9. Consistent chaos: friendly fire option and honest self-splash with Host
   comedy. Medium, small. Fits.
10. Player stories as canon, host-local: a front narrated by the Host and
    radio. Low, medium. Fits only small and private.
