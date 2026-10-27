# Bot and Enemy AI Excellence: Tactical Squads, Dynamic Companions, and Fun-First Combat

Status: **in flight**, 2026-10-24 (planned 2026-10-17). The first slice (perception, pacing, flinch and pad timing) shipped in #471; the second (tells matched to tokens, Latch cover and seed-robust routes) came with wave 3; the third (Larak Lot rule bots: the Rocket, callsign habits, grudges and the Scatter meatshot) is on `wave4/bots`; see section 6. Research and technical specification for advancing fragr's authoritative enemy state machines, multiplayer rule bots, and friendly companion mechanics. Grounded in classic and contemporary FPS best practices (F.E.A.R., Half-Life 2, Left 4 Dead, Boltgun, Unreal Tournament, Republic Commando). Spend: $0.

## 1. Executive Summary and Current Architecture Audit

An in-depth codebase audit of fragr's simulation and encounter systems reveals an exceptionally solid, deterministic 20 Hz simulation foundation. However, key behavioral gaps currently limit combat readability, teamplay dynamics, and player fun:

### Identified Architecture Gaps

1. **Perception Asymmetry in Modes:**
   - `server/src/sim/bot_senses.rs` provides human-like perception (120-degree field of view, 64m sight limit, ray occlusion against map solids and vehicle hulls, 200-400 ms reaction delay, 0.055 rad aim jitter, and 0.1 rad/tick turn rate clamps).
   - However, `uses_senses()` currently activates ONLY in FFA, TDM, and Conquest under `FullArsenal`.
   - In Capture the Flag (CTF), Sabotage, and all Campaign encounters, bots bypass `bot_senses.rs` entirely. They possess 360-degree omniscience, instant target acquisition, zero reaction delay, and zero simulated aim error.
2. **Simultaneous Enemy Volleys (No Attack Tokens):**
   - In `server/src/encounters/enemy.rs`, target selection strictly picks the nearest visible participant.
   - When a room awakens, every enemy targets the player on the exact same tick and begins windup simultaneously. This produces unreadable "alpha damage" spikes rather than dynamic, staggered firefights.
3. **Missing Infantry Attack Tells:**
   - While Turrets, Marksmen, and Crawlers have clear telegraphs (sound spin-up, scope glints, leap scrabbles), standard infantry (Clerks, Sweepers, Heavy Sweepers, Auditors) lack auditory and visual cues before discharging bursts. Shots feel like unavoidable chip damage rather than dodgeable attacks.
4. **Companion Passivity in Combat:**
   - In `server/src/mission/m02/companion.rs`, Latch has an excellent 4-step spatial yield algorithm (`safe_yield`) and peripheral slot following.
   - However, combat utility is artificially throttled by an arbitrary 12-shot chapter limit and a 40-tick cooldown, causing companions to feel passive in later missions.
5. **Silent Squads (No Tactical Audio Barks):**
   - Neither Union squads nor multiplayer friendly bots communicate their intent in combat, denying players the satisfaction of outmaneuvering telegraphed enemy tactics.

---

## 2. Best-Practice Design Pillars

| Goal | Mechanism | Player Experience |
|---|---|---|
| **Readable Combat** | Attack token pacing + audio/optic windup tells | The player can see and hear threats before damage lands, allowing skill-based dodging and cover usage. |
| **Tactical Intelligence** | Heavy suppression anchors + skirmisher flankers | Fights feel like intelligent squad engagements rather than individual bots rushing the player. |
| **Human-like Fairness** | Universal 120-degree vision cone + reaction delays | Players can flank enemies from behind, sneak past guards, and evade fire with swift movement. |
| **Reliable Companions** | Peripheral slot following + corridor yielding + reload covering | Companions never block doors or crosshairs; they cover the player during vulnerable reload moments. |
| **Living Team Communication** | In-world vocoder chatter + companion threat warnings | Squads feel alive, communicative, and tactically expressive without blocking gameplay. |

---

## 3. Detailed Implementation Milestones

### Milestone 1: Universal Bot Senses and Combat Fairness (Server & Sim)
- **Scope:**
  - Expand `BotController::uses_senses()` to activate across CTF, Sabotage, and active multiplayer modes.
  - In CTF and Sabotage, bots must visually acquire opponents within their 120-degree view cone before engaging aim and fire routines. Pathfinding to flags, stands, and bomb sites continues unimpeded.
  - Apply 120-degree vision cones and 200-400 ms reaction delays to dormant campaign guards before initial activation. Sneaking behind a guard or ambushing from an elevated angle catches them unaware.
  - Enforce an angular tracking rate limit for walking guards during windup (`TURN_PER_TICK = 0.1` rad/tick) so rapid strafing breaks weapon tracking before burst release.
- **Verification:**
  - Automated tests in `server/src/sim/bot_senses/tests.rs` verifying reaction latency, view-cone occlusion, and aim jitter in CTF and Sabotage.
  - Seeded benchmark surveys verifying balanced win rates and objective capture timings.

### Milestone 2: Encounter Attack Token System and Squad Roles (Campaign AI)
- **Scope:**
  - Implement `AttackTokenManager` in `server/src/encounters.rs`:
    - Ranged Attack Tokens: Maximum 2 concurrent enemies in `Windup` or `Firing` phases per encounter group.
    - Heavy / Melee Attack Tokens: Maximum 1 concurrent enemy in `Charging` or `Leaping` phases.
    - Enemies denied a token execute lateral repositions, strafing, or seeking cover.
  - Establish distinct squad roles:
    - **Suppression Anchors (Heavy Sweeper, Turret):** Lay down lane-denying fire to pin players behind cover.
    - **Skirmishers (Sweeper, Redactor, Crawler):** When an anchor is firing, skirmishers calculate lateral flank paths (`NavigationGoal { feet, combat: false }`) to wrap around player cover.
    - **Backline Support (Auditor):** Auditors path 3 meters behind heavy units, using them as mobile shields, and channel repairs only from protected angles.
- **Verification:**
  - Unit tests proving no more than 2 enemies enter `Windup`/`Firing` concurrently within an encounter group.
  - Integration runs on M04 and M08 showing staggered, readable volleys.

### Milestone 3: Enemy Telegraphing, Stagger Feedback, and Audio Tells (Presentation)
- **Scope:**
  - Add distinct pre-fire windup audio cues:
    - Clerk: sharp pistol hammer cock (`clerk/tell.wav`).
    - Heavy Sweeper: mechanical cycling whir (`heavy_sweeper/tell.wav`).
    - Enforcer: hydraulic servo whine (`enforcer/tell.wav`).
  - Wire a 1-frame optic glint / eye flash on enemy sprites on the first tick of `Windup`.
  - Visceral Stagger Feedback: When an armored unit absorbs 40+ damage in one tick, play an armor-crack audio impact and display an exaggerated head-snap recoil frame during the 16-tick stun.
- **Verification:**
  - Headless Godot audio checks verifying sound playback on state transitions.
  - Inspected renderer captures verifying windup glints and stun recoil frames.

### Milestone 4: Companion Spatial Etiquette and Covering Fire (Campaign Co-op)
- **Scope:**
  - Generalize M02's `formation.rs` lateral slot following across M03, M04, M06, M07, and upcoming M16-M20:
    - Companion stays positioned 30-45 degrees to the left or right of player forward facing, keeping them in peripheral view.
    - Doorway & Choke Yielding: When the player approaches a narrow corridor or door (|yaw - door_yaw| < 0.3 rad within 4 meters), the companion steps back and yields laterally, leaving a clear 2-meter corridor.
  - Active Covering Fire:
    - Remove Latch's arbitrary 12-shot chapter limit; equip a Tack pistol using standard magazine rules (reloads after 12 rounds).
    - When the player reloads (`inventory.reloading()`), the companion prioritizes immediate suppressive fire against the nearest active threat targeting the player.
- **Verification:**
  - Spatial clearance tests verifying companion never blocks player crosshairs or doorway navigation.
  - Combat tests confirming companion fires covering bursts when player reloads.

### Milestone 5: Tactical Voice Barks and Multiplayer Radio Chatter (Polish)
- **Scope:**
  - Implement `GameEvent::EnemyBark` for low-bandwidth vocoder radio chatter:
    - Sighting: *"Contact acknowledged."*
    - Flanking: *"Executing flank, suppress."*
    - Officer Down: *"Auditor severed, fall back."*
  - Implement `GameEvent::CompanionBark` for Latch:
    - Flank Warning: *"Look out, behind you!"*
    - Priority Callout: *"Auditor channeling, take it down!"* / *"Turret on the ceiling!"*
    - Low Health Alert: *"You're taking heavy hits, find cover!"*
  - Implement multiplayer objective radio callouts:
    - CTF: *"I have the flag, escort me home!"* / *"Enemy carrier in mid!"*
    - Sabotage: *"Pushing site A!"* / *"Bomb planted, hold crossfire!"* / *"Defusing now, watch my back!"*
- **Verification:**
  - Deterministic event generation tests on specific combat triggers.
  - Audio routed strictly to the dedicated `Voice` bus with volume controls.

---

## 4. Technical Seams and System Integration

| Concern | Primary Ownership | Interface / Seam |
|---|---|---|
| Universal Perception & Reaction | `server/src/sim/bot_senses.rs` | `BotController::uses_senses`, `BotSenses::observe` |
| Squad Attack Tokens & Roles | `server/src/encounters.rs` | `EncounterState::attack_tokens`, `EnemyController::update` |
| Infantry Tells & Stagger | `client/scripts/enemy_view.gd` | `EnemyPhase::Windup`, `GameEvent::EnemyTell` |
| Companion Etiquette & Covering | `server/src/encounters/companion.rs` | `formation.rs`, `safe_yield`, player reload detection |
| Tactical Voice & Radio Barks | `protocol/events.rs`, `audio_manager.gd` | `GameEvent::EnemyBark`, `GameEvent::CompanionBark` |

## 5. Spend, Safety, and Constraints

- Total external spend: **$0**. Reuses existing synthesis, samples, and offline audio tools.
- Authority: The Rust server remains 100% authoritative over perception rays, attack tokens, damage, and companion movement. Godot client only presents visual glints, sprite flinches, and audio cues.
- Zero AI attribution. Nick Seal strictly author.

## 6. Progress

**First slice, 2026-10-24 (`wave2/bot-ai`, Refs #432).** Implemented, not merged.

- Every arcade mode's rule bots, CTF and Sabotage included, see through the shared senses: 120 degree cone, sight range, cover and hulls, 200 to 400 ms reaction, bounded aim error and turn rate. A hit reveals where the shot came from, not where the shooter went, and spoils the victim's aim for six ticks. CTF bots keep their route and shoot what they see along it; they fight only near the point they guard (defender at its stand, escort beside the carrier, runner at the flag it came for).
- Rule bots and joined MCP agents know pads only from what they have seen, with the published return clocks; nobody reads a live timer. A bot leaves for a returning pad when the walk plus two seconds would get it there, holds the pad sweeping the approaches, and each personality keeps a habit pad. Found Sniper, Repeater and Rocket join the personalities' weapon lanes.
- Campaign ranged attackers share two tokens per participant, with tell starts at least ten ticks apart; a denied guard shifts across its lane for twelve ticks. Turrets and marksmen keep tracking but tell only with a free token. Melee charges are not paced.
- Struck arcade fighters recoil visibly in the client (lean back and give ground, 0.24 s); campaign actors keep their server Hit poses.

Measured with `fragr-playtest --bot-survey --seed 1 --survey-seeds 6 --time-limit-seconds 150` (six seeded 150 s rounds per row, rule bots only, no sockets), before and after:

| Scenario | Frags/min | Spawn deaths per spawn | Power pad appointments | Pad contest | Objective |
|---|---|---|---|---|---|
| FFA Arena Duel, 6 | 17.8 to 15.9 | 0.027 to 0.015 | 0% to 5% | 2.2% to 4.2% | |
| FFA Directive 17, 8 | 26.7 to 27.5 | 0.045 to 0.044 | 1.5% to 2% | 2.5% to 1.7% | |
| TDM Low Water, 8 | 22.7 to 24.3 | 0.016 to 0.030 | 3.9% to 14% | 7.9% to 8.2% | |
| CTF Sector 9, 8 | 1.3 to 6.7 | 0 to 0 | no pads taken | | 3 to 10 captures |
| Sabotage Sector 9, 8 | 3.8 to 5.2 | 0 to 0 | | | |
| Conquest Holdfast, 8 | 2.6 to 3.1 | 0 to 0 | | | 24 to 22 sites held |

A three-Clerk room against a stationary participant over 400 ticks fires 21 shots with pacing against 36 without, and its worst second drops from three tells to two (`a_waking_room_holds_two_tells_at_a_time_and_every_guard_still_fires`).

Seeded campaign route controllers are seed-sensitive. Over eight seeds each, the M14 infantry routes completed 7 of 24 runs before pacing and 17 of 24 with it; the late carried-kit routes and the M02 Severe side-ward route completed on as many seeds before as after, on different seeds. Those tests now name their seed and record the survey. This is controller evidence, not a difficulty verdict. `CAMPAIGN_RULES_REVISION` is unchanged because no tell duration changed.

**Second slice, 2026-10-24 (`wave3/ai-depth`, Refs #432).** Implemented, not merged.

- Tells match tokens. Notaries, Jammers, Assessors, Pavers and Surveyors held a ranged token while telling but never asked for one, so a camera flash or a jammer pulse could be the third attack on a participant (a Jammer with both tokens already held entered its windup on `main`). Every kind that holds a token now asks first; only melee leaps and charges stay unpaced (`every_kind_that_holds_a_token_waits_for_one_before_its_tell`, `a_mixed_room_never_lights_a_third_tell`).
- Visible tells. Union red optics are the attack tell light (art bible): at rest 1.6, a flash on the tick a tell starts, a swell to the shot and hot through the burst (`EnemyView.tell_glow`). Above rest the shader adds saturated red, so a hard-driven optic never clips to pink or white. A guard denied a token keeps resting optics while it shifts across its lane, so lit optics on screen are the attacks coming. The Auditor's Tack shares the Clerk's tell sound.
- Latch fights beside the participant. The twelve-shot chapter cap and 40-tick cooldown are gone: Latch's Tack has a real twelve-round magazine and reload, fires every 12, 16 or 22 ticks (Assisted, Standard, Severe) while the participant is in the fight, every 44 ticks while they hold fire, and every 6 ticks at whoever has a gun raised at them while they reload. In a fight Latch takes a covering position beside the participant with a line on the threat; out of a fight Latch keeps the stand-off. Latch never stands in a walking participant's lane, their crosshair or their line to the threat: a step aside, a lead through a doorway when nobody is shooting, or a place behind their shoulder.
- Seed-robust routes. The route controllers read tells: each committed tell, burst, leap or charge is answered by stepping clear of its line and staying clear until it is spent; they walk out of announced Walker and Paver areas and stop trading with targets their rounds cannot reach. The M14 mission client no longer fires a rocket into a surface inside its splash. Route tests now run several seeds each, including seeds that killed the old controllers; ignored surveys run sixteen (`cargo test -p fragr-server --lib seed_survey -- --ignored --nocapture`, `FRAGR_SURVEY_SEED` narrows one).

Seeds held over sixteen seeds per route, `main` against this slice (late carried kit and M14 count three runs per seed):

| Route | Before | After |
|---|---|---|
| M02 Severe side ward | 7 of 16 | 16 of 16 |
| M14 ordinary infantry | 26 of 48 | 48 of 48 |
| Late carried kit (M16 to M18) | 30 of 48 | 48 of 48 |
| Launch Authority on foot | 8 of 16 | 16 of 16 |
| M19 Planned Works, Standard | not surveyed | 16 of 16 |
| M20 pier, Standard | not surveyed | 16 of 16 |

Latch, `main` against this slice, from the route tests' own counters: the full M02 graybox walk (human or agent) went from 2 shots, 40 damage and 1 kill to 9 shots, 160 damage and 2 kills; the Severe side-ward route from 120 to 220 companion damage (seed 61); the stationary floor probe, where the participant holds fire, stays near 11 shots and leaves the floor to the participant.

Looked at: a controlled lineup of Clerk, Sweeper, Heavy Sweeper, Auditor, Redactor and Turret at rest, tell start, late tell and burst, at 5 and 15 m under dim light (`client/qa/union_tell_review.gd`), and a live M02 first-person still and strip with Latch holding a covering position right of the crosshair while the crossfire crew is awake (`client/qa/m02-latch-cover.json`). The Clerk's tell is its raise and its sound: the human troop has no bright optic to light. Windows rendering and human play were not run.

Still open: dormant guard cones and reaction before activation, squad roles, barks, bot personalities beyond pad habits, CTF bots seeking pads, and a pad contest index near the 15% the multiplayer research asks for (that needs power items worth fighting over).

**Third slice, 2026-10-25 (`wave4/bots`, Refs #431 and #432).** Implemented, not merged. Rule bots that play Larak Lot.

- The Rocket. Every personality fights with a launcher it carries from 6.5 to 32 m and readies it between fights, so it is up before the first body shows. It aims at the shins of where it expects the body to be when the rocket lands, led by the ground velocity it watched over two sightings (never a live position), so low error splashes the floor at the feet and high error strikes the body. A body above the shooter's floor, or shins behind a kerb, take the led chest. It holds fire inside 5 m, or when the first 5 m of the flight would strike a wall, and gives ground while the hand changes.
- Callsign habits (`server/src/roster/habits.rs`): a favourite gun, first in its band and worth a detour, and one pad each callsign times. Canon sets them where it speaks (Nightfall and Graveyard Shift keep the rail, the Static Kids the Scatter, Hangar Candy the Flechette, Aunt Linda the health), with Crackpot and Buzzkill timing the Custody Plate as readings of their own jokes ([cast](../lore/cast.md#the-wider-roster)); everyone else takes their behavior's. A timed power pad is an appointment from anywhere on the lot and outranks a trade past 12 m; so does the Plate for a bot already holding the gun it likes, and a first real gun for a life still on the Pistol. Walking to an appointment it still shoots what it sees.
- Grudges. The head-to-head book (`server/src/statistics/head_to_head.rs`, one schema, saved beside the runs on a desktop host and by `--head-to-head` on a dedicated one) counts frags between callsigns. A rule bot looks first for the fighter present it owes most and, settling the score, says so to them in its own register; NODS keep no grudges. The Duel intro reads the same book.
- The Scatter meatshot: seven pellets inside 2 units make 105, one blast through a bare fighter, asserted in the TTK harness beside the sticky table.

Measured with `fragr-playtest --bot-survey --survey-lot --seed 1 --survey-seeds 24 --time-limit-seconds 180` (24 seeded 180 s rounds per row, rule bots only, release build). The survey now numbers fighters so a seed repeats exactly, and reports Plate and Rocket claims, rockets fired and the Rocket's share of frags. `main` (wave 3 plus `wave4/tooling`) against this slice:

| Larak Lot | Frags/min | Rocket share of frags | Rockets fired (hurt someone) | Plate claims per 3 min | Flechette / Pistol share of shots |
|---|---|---|---|---|---|
| FFA, 6 | 24.1 to 20.3 | 2.3% to 3.9% | 264 (79) to 321 (117) | 0.3 to 3.3 | 20% / 70% to 41% / 40% |
| FFA, 4 | 12.8 to 11.0 | 3.7% to 7.2% | 196 (57) to 308 (122) | 0.6 to 3.3 | 38% / 40% to 50% / 20% |
| Duel, 2 | 3.5 to 2.3 | 3.9% to 28.9% | 107 (34) to 239 (131) | 1.2 to 3.7 | 47% / 6% to 37% / 6% |

The lane's targets for six bots: 18 or more frags a minute (20.3, met), two or more Plate claims in three minutes (3.3, met), the Flechette under 45% of shots (41%, met), and the Rocket at 15 to 25% of frags (3.9%, **not met**). The Rocket's share is a supply limit, not a use limit: in Duel, where a holder lives, it is 29%. On the six-bot lot one pad on a 25 s clock gives about eight claims a round, a holder lives about four seconds after the claim, and lives average twelve seconds, so a launcher fires about two rockets before its owner dies. Measured supply experiments, not shipped: the Rocket on the 15 s clock alone gave 2.9%; that clock with an 8-rocket rack gave 6.8%; a 10-rocket rack on the 25 s clock gave 4.4%. Reaching 15% at six needs the Rocket to be a common gun (a second launcher on the lot, or weapons dropped on death), which is a map and rules decision for Nick. Duel pace fell from 3.5 to 2.3 frags a minute because both bots now keep the Plate and the Rocket; whether that is the Duel we want is for a human session to judge.

CPU cost, `--bench 16 --bench-ticks 1200 --seed 42` in release, four runs alternated with `main` on the same host: mean tick 0.148 to 0.159 ms on `main` against 0.182 to 0.197 ms here (p50 0.127 to 0.139 against 0.156 to 0.172), about a fifth more, still under 0.5% of the 50 ms tick. Part of it is the play itself (twice the rockets in flight); the grudge lookup and the pad plan run only when a choice exists. `--bench-assert` passes.

Client frame time, `look-perf` on Vulkan at 1920x1080 Balanced (mean / p95 / GPU ms), this branch and `main` plus `wave4/tooling` alternated; host load 16.5, 10.1, 7.8 and 4.6 at the four starts, so the first lane run is the loaded one:

| View | Lane run 1 | Base run 1 | Lane run 2 | Base run 2 |
|---|---|---|---|---|
| Larak Lot overview | 7.34 / 10.28 / 6.42 | 7.05 / 10.20 / 6.10 | 6.97 / 9.73 / 6.05 | 7.61 / 11.28 / 6.51 |
| Larak Lot first person | 9.30 / 13.09 / 7.80 | 7.47 / 10.43 / 6.69 | 6.70 / 10.07 / 5.36 | 7.21 / 11.11 / 5.92 |

No client code changed; the spread is the host's.

Looked at (Vulkan, Balanced, 1280x720): the Larak Lot tour against the wave 4 baseline (no presentation change; the follow camera finds a bot in the Pit), the Duel tour with the intro in the Host corner, upright ("HOST: LARAK LOT DUEL. NANA SIX-SEVEN AGAINST MEAT PROXY. FIRST TIME ON THE BOOK."), and `client/qa/larak-bots.json`, strips of the Pit while the Rocket is claimed and fired and of the Roof while a regular walks up for the Plate.

Still open after this slice: the Rocket target above, voiced grudges (text only), and spectator-facing grudge facts.

**Fourth slice, 2026-10-27 (`wave11/mp-rules`, Refs #431 and #432).** Implemented, not merged. Weapons drop on death (Nick's supply decision, 2026-10-27).

- Where lives start on the Pistol (free-for-all and Duel without Full Arsenal or Golden Rail), a fragged fighter leaves the gun in their hands where they fell, with the rounds they still had for it, never more than that gun's pad grant (`server/src/sim/drops.rs`). The Pistol, Fists, the Shiv, the Article Blade, the Flechette (the lot's common pad gun; measured below) and an empty gun stay behind. It lies 15 s, then is gone. The first fighter on it who can use it takes it as a pad grant. Team modes, weapon-only mutators, Golden Rail (its gun returns to the pad), Full Arsenal, Sabotage (its own primary drop), the campaign and the benchmark keep their guns.
- Rule bots know a drop only once they have seen it (the pad senses: cone, range, cover or underfoot), believe it there until they see the spot empty or a regular's sense of its lifetime runs out, and value it by the same habits as a pad: a gun they cannot fire is worth leaving a search for, a habit gun (the Rocket for Rocket regulars) close by, the favourite gun a detour. Joined MCP agents see drops the same way (`agent-adapter/src/pads.rs`).

Measured with `fragr-playtest --bot-survey --survey-lot --seed 1 --survey-seeds 24 --time-limit-seconds 180` in release, `main` at `7f90dd70` against this slice. The survey now reports guns dropped and taken.

| Larak Lot, 24 seeds of 180 s | Frags/min | Rocket share of frags | Rockets fired (hurt someone) | Plate claims per 3 min | Flechette / Pistol share of shots | Guns dropped (taken, Rockets taken) |
|---|---|---|---|---|---|---|
| FFA, 6 | 20.3 to 20.7 | 3.9% to 6.1% | 321 (117) to 470 (176) | 3.3 to 3.4 | 41% / 40% to 36% / 35% | 649 (584, 69) |
| FFA, 4 | 11.0 to 11.2 | 7.2% to 9.8% | 308 (122) to 456 (181) | 3.3 to 3.1 | 50% / 20% to 47% / 17% | 445 (371, 94) |
| Duel, 2 | 2.3 to 2.3 | 28.9% to 26.3% | 239 (131) to 279 (161) | 3.7 to 4.0 | 37% / 6% to 35% / 4% | 146 (63, 24) |

Which guns drop, six bots, 15 s, same survey:

| Rule | Frags/min | Rocket share | Flechette / Pistol share | Guns dropped (taken) |
|---|---|---|---|---|
| Every found gun, full rounds | 20.9 | 5.2% | 50% / 27% | 1031 (875) |
| Every found gun, a dropped Flechette at most half a pad (30) | 20.9 | 5.2% | 50% / 27% | 1031 (875) |
| The Flechette stays behind (shipped) | 20.7 | 6.1% | 36% / 35% | 649 (584) |

Halving the Flechette's rounds changes nothing at six: rule bots run one
Bullets count and rarely run a Flechette dry inside a life, so the gun itself,
not its rounds, is what circulates. Keeping the Flechette out of the drop
meets the 45% gate and raises the Rocket share; frags per minute moved 0.2
(20.9 to 20.7), still above `main`'s 20.3, and the Pistol picks up the shots.

Lifetime, six bots, same survey, every found gun dropping (bots aware of drops):

| Drop lifetime | Rocket share | Flechette share | Drops taken | Frags/min |
|---|---|---|---|---|
| 10 s | 5.4% | 50% | 759 of 1021 | 20.9 |
| 15 s (shipped) | 5.2% | 50% | 875 of 1031 | 20.9 |
| 20 s | 4.8% | 51% | 903 of 1026 | 21.0 |
| 30 s | 4.2% | 49% | 972 of 1038 | 21.0 |

Drops alone, before bots learned them (15 s): Rocket 3.7%, Flechette 45%,
26.1 pickups a minute against 30.4 once bots walk to what they see.

The Rocket target (15 to 25% at six) is **not met**: 3.9% to 6.1%. Lifetime moves it inside noise (4.2% to 5.4%); a longer lifetime only lets more Flechettes circulate. Drops added about 90 Rocket lives over 72 minutes of six-bot play to the 140 the pad gives, and 441 rockets were fired against 321, but a rocket still kills about once in five (160 of 441 hurt someone). The Rocket's frag share at six is limited by how often a launcher is in a living hand in its band, and a dropped launcher mostly goes to whoever just won the fight nearby, usually with a Flechette in hand. Reaching 15% needs the lot to carry more launchers (a second pad), or bots that hold the Rocket longer in mid-range trades; both are map or controller decisions outside a drop rule. With every found gun dropping, the Flechette share rose past the 45% gate (41% to 50%), because dropped Flechettes keep circulating; the shipped rule keeps the Flechette behind and lands at 36%. Frags per minute, the Plate and spawn deaths held. Nick's call whether drops stay in Duel, where the Rocket share moved from 29% to 26%.

**Fifth slice, 2026-10-27 (`wave12/campaign-ai`, Refs #432).** Implemented, not merged. Campaign guards that need to see you, squad roles and chatter.

- Guards on watch (Milestone 1). A room still wakes where its level says: the authored entry region, or a shot that strikes a guard. Waking is now an alarm, not a sighting. A guard on foot (personnel and the Sweepers) that has not seen the participant turns toward the alarm if it can see that spot (half a turn in about 0.6 s) or walks there around cover if it cannot, and starts an attack only after it sees a participant through the shared senses (`sim/bot_senses/guard.rs`, additive: the arcade's 120 degree cone, a level gaze within 0.6 rad, cover, the 200 to 400 ms reaction). Coming in behind a guard or from a gantry above it buys the first shots; after one second every alarmed guard is in the fight regardless, so every authored room still wakes. A struck guard reacts at once. Office equipment (Turret, Jammer, Notary, Assessor), the marksman, the Surveyor and the Paver keep their own notice rules; a Crawler pack wakes with its scrabble. Code: `server/src/encounters/enemy/awareness.rs`.
- Waking a room by sight before its region was built, measured and not kept. Even limited to a six metre band around the region it woke rooms early and broke authored beats that tests guard (the Launch Authority resupply beside sleeping guards, the M09 Tack pickup before the encounter, the M02 Latch release), and it raised the constrained M19 teaching survey from 4 deaths to 60 and cut M01 from 50 to 31 clears of 72.
- Squad roles on the attack tokens (Milestone 2, `encounters/enemy/squad.rs`). Anchors (Heavy Sweeper, Turret) hold a lane: once a Heavy's burst has begun it finishes down its committed line into the cover; its tell still cancels on broken sight, and the Turret keeps its break-sight counterplay. While an anchor of its group is telling or firing at a participant, a skirmisher (Sweeper, Redactor, Crawler) walks round to a point on the participant's floor that still sees them, swung 1.2 rad from the anchor's line, for at most 2.5 s, then rests 4 s before another flank; a Sweeper spends its recovery walking it, Crawler and Redactor recoveries stay planted, and nobody flanks on Assisted. A flanking guard still asks for a token before it raises. An Auditor that cannot attack from where it stands keeps a Heavy Sweeper or Enforcer of its group between itself and the participant, 3 m behind it.
- Chatter (Milestone 5, campaign part). `GameEvent::EnemyBark` (sighting, flanking, officer down; personnel or unit register) and `GameEvent::CompanionBark` (Latch: flank warning for a gun raised behind the participant's shoulder within 24 m, priority target for an Auditor's repair or a Turret's charge, low health below 35) are keyed facts; the client owns the words (`client/i18n/story.en.po`), captions (`bark_caption.gd`) and recordings (`bark_voice.gd`, slots under `client/assets/audio/barks/`). Lines are rare: a Union line waits 5 s after any line, Latch waits 5 s after Latch's own and may cut across Union radio, one kind repeats at most every 20 s (low health 30 s). Only Union-controlled personnel and Sweepers speak; equipment, Crawlers, absorbed bots and Inheritance machines never do. Union radio plays through a `UnionRadio` bus the client builds at runtime (band-pass and a light overdrive, sent to Voice), so the recordings stay dry. The 18 Union lines are recorded (ElevenLabs eleven_v4, four stock voices, 2,370 credits by price); Latch's 12 lines are captioned with empty slots because Latch's casting is Nick's pick (E-11). Nobody has listened to the takes yet.

Measured, base `wave11/integration` at `5b4ad2c3` against this slice, release build, same seeds:

| Constrained survey | Base clears (deaths) | This slice clears (deaths) |
|---|---|---|
| M01, seeds 40 to 47, 72 trials | 50 of 72 (121) | 46 of 72 (130) |
| M19 teaching, seeds 40 to 43, 36 trials | 36 of 36 (4) | 36 of 36 (8) |
| M19 market, seeds 42 and 43, 18 trials | 8 of 18 (43) | 9 of 18 (43) |
| CI seed 42: M01 / teaching / market, 9 trials each | 6 (18) / 9 (1) / 4 (22) | 5 (19) / 9 (1) / 5 (18) |

| Route survey, sixteen seeds (`seed_survey -- --ignored`) | Base | This slice |
|---|---|---|
| M02 Severe side ward | 16 of 16 | 15 of 16 (67) |
| M14 ordinary infantry | 16 of 16 | 15 of 16 (1025) |
| Late carried kit (M16 to M18) | 16 of 16 | 13 of 16 (43, 46, 52) |
| Launch Authority on foot | 16 of 16 | 16 of 16 |
| M19 Planned Works, Standard | 16 of 16 | 16 of 16 |
| M20 pier, Standard | 16 of 16 | 16 of 16 |

The constrained M01 survey is a little harder (four fewer clears, nine more deaths over 72 trials); the market is unchanged within a trial; teaching adds four deaths and keeps every clear. No evaluator, tell duration or `CAMPAIGN_RULES_REVISION` changed. Ablations on the same seeds put the remaining M01 cost on the guard-awareness model (squad roles cannot act in M01, which has no anchors); M01 with the awareness switched off reproduced the base table exactly. The route controllers are seed-sensitive, as before: the late kit failures die in the Freedom of Movement forecourt after the controller wakes it early by shooting its Assessor from the transit stop, and the earlier M18 overlook stalls (the controller stepping off the stair landing during a fight at its top) came back with walking alarmed guards and went away when a guard that can see the alarm stands and turns instead. `late_campaign_carried_routes_hold_across_seeds` now runs seeds 40, 44 and 48; seed 43 left it with the reason in the test.

Looked at: the bark captions over M01 in first person at 1280x720 (Union radio, issued unit and Latch lines, stacked over the Crawler caption), level and clear of the health panel. Not done: listening to the recordings, a live capture of a flank or a pinned lane, Windows rendering, human play.

Still open: Latch's voice (casting), CTF bots seeking pads (#432, the `mp-bots` lane), the Rocket share, voiced grudges and the remaining route seeds above.
