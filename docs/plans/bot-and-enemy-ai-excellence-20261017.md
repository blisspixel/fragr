# Bot and Enemy AI Excellence: Tactical Squads, Dynamic Companions, and Fun-First Combat

Status: **planned**, 2026-10-17. Research and technical specification for advancing fragr's authoritative enemy state machines, multiplayer rule bots, and friendly companion mechanics. Grounded in classic and contemporary FPS best practices (F.E.A.R., Half-Life 2, Left 4 Dead, Boltgun, Unreal Tournament, Republic Commando). Spend: $0.

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
