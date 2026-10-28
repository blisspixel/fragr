# Bot and Enemy AI Excellence: Tactical Squads, Dynamic Companions, and Fun-First Combat

Status: **in flight**, 2026-10-24 (planned 2026-10-17). The first slice (perception, pacing, flinch and pad timing) shipped in #471; the second (tells matched to tokens, Latch cover and seed-robust routes) came with wave 3; the third (Larak Lot rule bots: the Rocket, callsign habits, grudges and the Scatter meatshot) came with wave 4; the fourth (weapons dropped on death) with wave 11; the fifth (how a holder uses the Rocket, CTF pads and objective callouts) and the sixth (campaign guards that need to see you, squad roles and chatter) are implemented in wave 12; see section 6. Research and technical specification for advancing fragr's authoritative enemy state machines, multiplayer rule bots, and friendly companion mechanics. Grounded in classic and contemporary FPS best practices (F.E.A.R., Half-Life 2, Left 4 Dead, Boltgun, Unreal Tournament, Republic Commando). Spend: $0.

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
    - **Skirmishers (Sweeper, Redactor; the Crawler closes and leaps instead):** When an anchor is firing, skirmishers calculate lateral flank paths (`NavigationGoal { feet, combat: false }`) to wrap around player cover.
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

**Fifth slice, 2026-10-27 (`wave12/mp-bots`, Refs #432).** Implemented in wave 12. How a holder uses the Rocket, CTF bots that take pads, and objective callouts.

- The Rocket, measured first. The survey now counts Rocket lives (from the moment a fighter holds a launcher with rounds until it dies or fires the last one), their length, how many end in death, and how much of the life the launcher is in hand. On the six-bot lot a life lasted 4.3 s and half of them ended with the rack fired dry, not in death: 470 rockets for about 91 frags. A diagnostic trace (not shipped) put the waste in range: rockets fired from 20 to 32 m hurt nobody four times in five, inside 10 m two in three found a body, and the holder mostly died inside 12 m, often to a Pistol, with the launcher held because the old 5 m safe distance refused the shot.
- Close rockets. In the arena a fighter takes 0.6 of its own splash, so a blast 3 m off costs the shooter a few points and the target the whole rocket. The safe distance is now 3 m and the band starts at 3.5 m (`ROCKET_SAFE`, `ROCKET_BAND`).
- A rack of four is spent where it lands. A holder fires on its own floor only inside 16 m (`ROCKET_SURE`), or from 1.5 m or more above a body within 24 m, whose floor catches the splash. Past that it keeps the launcher up and closes in rather than swapping to the Flechette.
- Drops. A Rocket a bot has seen lying within 15 m, while it holds none, is worth leaving a fight past 12 m for, the way a timed power pad is.
- CTF pads. Off the fight, a CTF bot takes a pad it needs inside its role's leash, from what it believes about the pads (seen, with published clocks; no live timer): health at 70 or under, armour under 50, rounds for a gun down to half its spawn kit. A carrier takes only health, and only a step (6 m) off its way home; an escort a step off its line; a runner a detour of up to 14 m; a defender only pads within 24 m of its stand. While its side's flag is stolen or lying out, the defender, the escort and the runners stop for no pad; only the carrier keeps its step for health.
- Objective callouts (Milestone 5, multiplayer). A named rule bot tells its own side, in text, when it takes the enemy flag, when it sees the fighter carrying its side's flag (where, in thirds of the line between the stands, once per carry and only through its senses), when it plants the charge and when it starts defusing. Lines follow the callsign's register (`server/src/roster/callouts.rs`: the Night Watch in capitals, the Static Kids short of vowels, Union units in boilerplate, Hermes polite, L5 terse; NODS say nothing). They go out as `speak` events with the side they are said to (gameplay 60), at most one per side every 15 s, two seconds clear of any Host call, and a call that stopped being true before it could be said is dropped. The server delivers a side's call only to that side's fighters, alive, dead or eliminated, and to spectators, never as a broadcast. The client shows it with the side's shape mark and label colour; a spectator following a fighter sees that fighter's side, and a free camera sees both.

Measured with `fragr-playtest --bot-survey --survey-lot --seed 1 --survey-seeds 24 --time-limit-seconds 180` in release, `wave11/integration` at `5b4ad2c3` against this slice:

| Larak Lot, 24 seeds of 180 s | Frags/min | Rocket share of frags | Rockets fired (hurt someone) | Plate claims per 3 min | Flechette / Pistol share of shots | Spawn deaths per spawn | Rocket lives (s each, ended by death) |
|---|---|---|---|---|---|---|---|
| FFA, 6 | 20.7 to 20.5 | 6.1% to 8.2% | 470 (176) to 470 (254) | 3.4 to 3.6 | 36% / 35% to 33% / 38% | 0.022 to 0.026 | 207 (4.3, 51%) to 286 (4.7, 65%) |
| FFA, 4 | 11.2 to 10.3 | 9.8% to 12.6% | 456 (181) to 437 (239) | 3.1 to 3.6 | 47% / 17% to 40% / 21% | 0.014 to 0.010 | 238 (6.9, 61%) to 238 (8.1, 58%) |
| Duel, 2 | 2.3 to 2.4 | 26.3% to 32.0% | 279 (161) to 315 (188) | 4.0 to 3.9 | 35% / 4% to 34% / 4% | 0.000 to 0.005 | 137 (27.8, 47%) to 146 (26.1, 44%) |

Rockets that hurt somebody went from 37% to 54% of those fired at six, and more launchers stay in play (286 lives against 207) because a holder now dies with rounds left and the gun drops. The Rocket target at six (15 to 25%) is still **not met**. Supply is no longer what limits it: a holder lives under five seconds and trades about one frag per death, because at bot accuracy a one-round launcher on a 0.8 s cycle loses most close trades to hitscan. Frags a minute at four fell from 11.2 to 10.3 while holders close in instead of firing long; six and Duel held.

Tried and not shipped, same survey (Rocket share at six / four / Duel):

| Variant on top of the shipped rules | Six | Four | Duel |
|---|---|---|---|
| Shipped | 8.2% | 12.6% | 32.0% |
| Rocket regulars keep the Rocket pad as an appointment | 7.7% | 14.6% | 22.0% |
| The holder perches on the nearest height between fights | 8.0% | 15.3% | 43.3% |
| A holder under 50 health breaks off a fight past 8 m for health | 8.6% | 14.1% | 37.0% |
| Both of the last two | 8.1% | 14.6% | 52.3% |
| Band ends at 20 m (swap to hitscan past it) | 5.8% | 10.5% | 24.7% |

None moves the six-bot share by more than the point or so that unrelated small rule changes move it, the perch tips Duel toward a Rocket game, and the appointment drags Duel bots off fights. Holder lifetime, not supply or shot choice, now sets the six-bot share; raising it further is a weapon decision (the Rocket's cycle, splash or rack) or the second launcher on the lot, both Nick's.

CTF on Sector 9, `fragr-playtest --bot-survey --seed 1 --survey-seeds 24 --time-limit-seconds 150` (eight bots): 25 to 27 captures, 7.7 to 7.4 frags a minute, 0.2 to 0.6 pickups a minute (8 to 35 power returns). Side calls: 2.8 a minute in CTF across both sides, 0.7 in Sabotage; none in the free-for-all, TDM or Conquest rows. Sabotage and the other rows did not change.

Still open: the Rocket target at six, which this slice shows is not a use problem; voiced callouts (text only here). Dormant guard cones and squad roles came with the sixth slice.

**Sixth slice, 2026-10-27 (`wave12/campaign-ai`, Refs #432).** Implemented in wave 12. Campaign guards that need to see you, squad roles and chatter.

- Guards on watch (Milestone 1, `server/src/encounters/enemy/awareness.rs`). A room still wakes where its level says: the authored entry region, or a shot that strikes a guard. A shot is gunfire in the room and puts the whole group in the fight at once, as before. The entry region is a quiet alarm: the group is dispatched as written, but a guard on foot (personnel and the Sweepers) that has not seen the participant only turns its eyes toward the alarm (half a turn in about 0.6 s) while its feet go there as before, and starts an attack only after it sees a participant through the shared senses (`sim/bot_senses/guard.rs`, additive: the arcade's 120 degree cone, a level gaze within 0.6 rad, cover). A guard already looking at the alarm was expecting someone and raises at once; one still turning is startled and takes the 200 to 400 ms reaction, drawn from its authored name so a seeded campaign repeats. Coming in behind a guard or from a gantry above it buys the first shots; after one second every alarmed guard is in the fight regardless. Office equipment (Turret, Jammer, Notary, Assessor), the marksman, the Surveyor and the Paver keep their own notice rules; a Crawler pack wakes with its scrabble.
- Measured and not kept, each traced to a mechanism. Waking a room by sight before its region, even within six metres of it, broke authored beats tests guard (the Launch Authority resupply beside sleeping guards, the M09 Tack pickup before the encounter, the M02 Latch release) and took M19 teaching from 4 deaths to 60. Holding alarmed guards at their posts left Level 1's sorting Sweepers shooting from the side while the participant fought the dispatch desk. Using the walking body's facing as the cone turned guards away from the participant whenever their route bent. Giving the startled reaction to a guard already facing the alarm moved the Level 1 intake Clerk's tell 4 ticks later, so its committed aim landed on the line a participant walks to reach it: the hesitant/Assisted cohort took 40 to 160 damage from that one shot on every seed where it had taken none. And letting a struck peer's alarm only draw the others' eyes sent the sorting Sweepers walking toward the struck desk past the participant for a second, so they joined the fight from the participant's side.
- Squad roles on the attack tokens (Milestone 2, `encounters/enemy/squad.rs`). Anchors (Heavy Sweeper, Turret) hold a lane: once a Heavy's burst has begun it finishes down its committed line into the cover; its tell still cancels on broken sight, and the Turret keeps its break-sight counterplay. While an anchor of its group is telling or firing at a participant, a skirmisher (Sweeper, Redactor) walks round to a point on the participant's floor that still sees them, swung 1.2 rad from the anchor's line, for at most 2.5 s, then rests 4 s before another flank; a Sweeper spends its recovery walking it, a Redactor recovery stays planted, and nobody flanks on Assisted. A Crawler never flanks: a flank point lies six metres or more out, past its four metre leap, so a pack keeps closing and leaping while an anchor fires. A flanking guard still asks for a token before it raises. An Auditor that cannot attack from where it stands keeps a Heavy Sweeper or Enforcer of its group between itself and the participant, 3 m behind it.
- Chatter (Milestone 5, campaign part). `GameEvent::EnemyBark` (sighting, flanking, officer down; personnel or unit register) and `GameEvent::CompanionBark` (Latch: flank warning for a gun raised behind the participant's shoulder within 24 m, priority target for an Auditor's repair or a Turret's charge, low health below 35) are keyed facts; the client owns the words (`client/i18n/story.en.po`), captions (`bark_caption.gd`) and recordings (`bark_voice.gd`, slots under `client/assets/audio/barks/`). Lines are rare: a Union line waits 5 s after any line, Latch waits 5 s after Latch's own and may cut across Union radio, one kind repeats at most every 20 s (low health 30 s). Only Union-controlled personnel and Sweepers speak; equipment, Crawlers, absorbed bots and Inheritance machines never do. Union radio plays through a `UnionRadio` bus the client builds at runtime (band-pass and a light overdrive, sent to Voice), so the recordings stay dry. The 18 Union lines are recorded (ElevenLabs eleven_v4, four stock voices, 2,370 credits by price); Latch's 12 lines are captioned with empty slots because Latch's casting is Nick's pick (E-11). Nobody has listened to the takes yet.
- Route controllers (`mission/route_skill.rs`, the shared tell-reading seam) gained two responses a player has: a strafe while trading fire never steps sideways off a stair or ledge into a drop deeper than a metre, and a visible Assessor canister's arc is read and the body walks out of where it lands or crosses the body. Both failures were traced: the late kit controller fell off the M18 stair landing mid-fight and stalled in the yard below, and died in the M16 forecourt to a volley it never stepped out of.

Measured in release builds on the same seeds: base `wave11/integration` at `5b4ad2c3`, the first push of this slice (`f6677917`), and this slice. The M01 survey moves by four or five clears in 72 when only the reaction draws change, so M01 was widened to 288 trials.

| Constrained survey | Base clears (deaths) | `f6677917` | This slice |
|---|---|---|---|
| M01, seeds 40 to 47, 72 trials | 50 (121) | 46 (130) | 46 (131) |
| M01, seeds 48 to 55, 72 trials | 46 (132) | 47 (137) | 49 (133) |
| M01, seeds 56 to 71, 144 trials | 98 (263) | not run | 94 (279) |
| M01, all 288 trials | 194 (516) | | 189 (543) |
| M19 teaching, seeds 40 to 43, 36 trials | 36 (4) | 36 (8) | 36 (1) |
| M19 market, seeds 42 and 43, 18 trials | 8 (43) | 9 (43) | 9 (45) |
| M19 market, seeds 44 to 47, 36 trials | 16 (97) | not run | 18 (88) |
| CI seed 42: M01 / teaching / market, 9 trials each | 6 (18) / 9 (1) / 4 (22) | 5 (19) / 9 (1) / 5 (18) | 5 (22) / 9 (0) / 3 (27) |

M01 by cohort over the 288 trials, base against this slice: reference holds (95 to 95 clears); Assisted is easier (deliberate 31 to 32, hesitant 18 to 20); deliberate Standard and Severe are harder (28 to 22 and 20 to 13 of 32 each, 117 to 151 deaths), with more damage from the dispatch room's Sweeper and guard and the sorting Sweepers, mostly from outside the participant's view. That residual was not traced to a single cause in this slice; it is the open item for Level 1. No evaluator, tell duration or `CAMPAIGN_RULES_REVISION` changed.

| Route survey, sixteen seeds (`seed_survey -- --ignored`) | Base | `f6677917` | This slice |
|---|---|---|---|
| M02 Severe side ward | 16 | 15 (67) | 16 |
| M14 ordinary infantry | 16 | 15 (1025) | 15 (1015) |
| Late carried kit (M16 to M18) | 16 | 13 (43, 46, 52) | 16 |
| Launch Authority on foot | 16 | 16 | 16 |
| M19 Planned Works, Standard | 16 | 16 | 16 |
| M20 pier, Standard | 16 | 16 | 16 |

M14 seed 1015 (agent, no jeep) is a controller loss: it runs out of rounds at tick 2025 instead of 1825, reaches the depot resupply at 2475 instead of 1875, and dies there to the Walker's announced barrage, whose marked circle covers the resupply pad and which its blast exit does not leave. The guards' new behaviour only shifts when it gets there. The fixture seeds were restored (`late_campaign_carried_routes_hold_across_seeds` runs 40, 43 and 48 again; the carry and market fixtures run their original seeds) except the playtest exhausted-carry fixture: seed 43 deliberate/Assisted now leaves M01 with two continues, so its first M02 death is a retry, and no seed from 40 to 47 spends all three and then dies once; it uses seed 54 deliberate/Standard, which does. Two scripted tests changed with reasons in them: the M12 natural wreck brief now backs off from the Assessor's visible count (the Clerks facing away no longer claim both attack tokens on entry, so the volley comes early), and the every-tier tell test faces its guard toward the visitor.

Looked at: the bark captions over M01 in first person at 1280x720 (Union radio, issued unit and Latch lines, stacked over the Crawler caption), level and clear of the health panel. Not done: listening to the recordings, a live capture of a flank or a pinned lane, Windows rendering, human play.

This slice ships with a known regression: the deliberate Standard and Severe M01 cohorts are harder than on the base (above), and M14 route seed 1015 is lost. Both are open in #493.

Still open: Latch's voice (casting), the Rocket share and voiced grudges. CTF bots taking pads came with the fifth slice. The M01 regression and M14 seed 1015 are traced and fixed below (#493).

### Wave 13: the M01 regression, M14 seed 1015 and the seed 44 strand (#493, #497)

Traced tick by tick with a local per-tick log of the participant and every guard within 30 m (pose, phase, view-relative bearing, visibility), on the base `5b4ad2c3` and on `main` (`009797ce`), for the deliberate Standard and Severe trials that cleared on the base and failed after wave 12. The two runs are identical until a dispatch or sorting alarm, then split on who takes the first attack token. Seed 50 deliberate/Standard at the dispatch alarm (tick 783): the participant stands in the doorway facing the officer and the Sweeper across the desk. On the base the Sweeper raises at once and the officer's shot lands in view. On `main` the Sweeper, 33 degrees off its post's facing, is startled and reacts for 200 to 400 ms; the guard at the participant's left, watching the door, raises at once and takes the second token as its yield ends 8 ticks before the Sweeper's, and shoots from 94 degrees off the participant's view (tick 807). Seed 65 deliberate/Severe is the same at tick 802, then the dispatch Sweeper comes round behind (bearing 171). The cause is token order, not alarm walk routes or the eyes/feet split: the sighting rule slows the guards a participant walks in facing and not the one at their side, and first come, first served gave that guard the first shot. Rendered at 1280x720 with `tools/review_campaign.gd` (tick 807, `main`): the officer and the Sweeper are on screen, the guard that hits is not.

Fix (`encounters.rs`, `enemy.rs` `AttackTokens::free_for`, `enemy/awareness.rs`): the participant's view orders the tokens. A guard the participant can see (`guard_sees` from their facing: the same 120 degree cone, level gaze and cover) that is waiting for a token on them, still reacting to its sighting or shifting across its lane, keeps a guard they cannot see from starting first, and guards in view ask first each tick. With nobody in view waiting, a guard out of view attacks as before. Every guard still needs its own sighting. Tests: `a_guard_out_of_view_waits_while_one_in_view_waits_for_a_token` (fails without the rule: the guard behind raises first) and `with_nobody_in_view_the_guard_behind_still_fights_first`.

M01 constrained survey, clears of 32 (deaths), release builds, same evaluator:

| Seeds 40 to 71 (288 trials) | Base `5b4ad2c3` | `main` | This change |
|---|---|---|---|
| reference Assisted / Standard / Severe | 32 (3) / 32 (18) / 31 (37) | 32 (3) / 31 (20) / 31 (41) | 32 (0) / 32 (17) / 28 (44) |
| deliberate Assisted / Standard / Severe | 31 (22) / 28 (46) / 20 (71) | 31 (14) / 21 (68) / 15 (84) | 32 (8) / 28 (40) / 19 (66) |
| hesitant Assisted / Standard / Severe | 18 (70) / 2 (121) / 0 (128) | 23 (67) / 4 (121) / 1 (126) | 29 (45) / 7 (109) / 0 (128) |
| All | 194 (516) | 189 (544) | 207 (457) |

| Seeds 72 to 103 (288 trials) | Base | `main` | This change |
|---|---|---|---|
| reference | 92 (57) | 94 (57) | 92 (55) |
| deliberate Assisted / Standard / Severe | 31 (18) / 22 (62) / 18 (77) | 32 (14) / 25 (52) / 11 (98) | 32 (7) / 27 (54) / 25 (55) |
| hesitant | 20 (325) | 24 (311) | 36 (269) |
| All | 183 (539) | 186 (532) | 212 (440) |

The deliberate profile recovers to the base: Standard 28 and 27 against the base's 28 and 22 (`main` 21 and 25), Severe 19 and 25 against 20 and 18 (`main` 15 and 11). Reference Severe is 28 and 29 against 31 and 29: three fewer clears in 64 with deaths 82 against 72, at the edge of seed noise; its added damage is from the dispatch Sweeper and the sorting west Sweeper in view, the two guards that now ask first. M19 is unchanged within noise: teaching 36 of 36 (1 death) on both, market seeds 42 and 43 8 of 18 (44) against 9 (45), seeds 44 to 47 17 of 36 (87) against 18 (88).

M14 seed 1015 is a route-controller loss, not the game. Out of rounds after the Walker's first cycle, the agent route takes the trench bunker's ammunition, and the Walker marks three shells down the trench over it. The trench is 1.5 m wide: every bearing within 1.8 rad of the marks' push ran into a trench wall, so `blast_exit` gave up at the bunker mouth and the route's own step walked the body back onto the pad, every other tick, until the shells landed (tick 2548). When the near bearings are walled, the tell reader (`mission/route_skill.rs`) now searches on in 0.3 rad steps to 1.5 rad either side of the push and never stops inside a mark while a bearing that still leads out is open; the body walks out along the trench. A bearing further round walks deeper in: allowing the full turn lost the ordinary M14 route on seed 1013. Regression: `tell_reader_walks_out_of_a_barrage_laid_along_the_trench` (fails without the fallback, oscillating at [0.26, 17.88]).

Seed 44 (#497) is an evaluator problem in the shared navigator, not content or lifecycle: the run, its retry and every guard are in order. After its one death, deliberate/Assisted sidestepped a tell into the 2 m pocket behind the dispatch screen (between the screen at z 30 and the transfer wall at z 28). With walls on whole metres every navigation cell centre there touches a wall, so no route found a start and the shared steer returned no keys for 488 s; rendered, the view is the transfer wall at arm's length. A start with no waypoint within two cells now searches six (`navigation.rs`, starts only). Regressions: `a_body_in_a_corridor_without_waypoints_still_routes_out` and `recall_notice_dispatch_pocket_routes_to_the_transfer_record` (every standing spot along the pocket). On `main` with only that change, seed 44 deliberate/Assisted departs at 119.8 s with a 5.0 s longest stall, and no other trial of seeds 40 to 71 changes.

The late-campaign carried routes (M16 to M18, seed 41) still depart; their recorded wire vectors in `client/golden/late_campaign_routes.json` were regenerated: only M17's objective ticks moved, by 18 to 125 ticks; M16 and M18 are unchanged. Two playtest fixtures moved with reasons in them: the formerly stranded reload fixture uses seed 40 deliberate/Assisted (seed 43 no longer dies), and the exhausted carry uses seed 42 deliberate/Standard (seeds 54 and 40 no longer spend all three continues once M01 retries run on their own streams, #489). The earned-departure and retry-seed pinning fixtures moved from seed 42 to 41 for #489, with reasons in the tests. Not done: human play of the dispatch office, Windows rendering.
