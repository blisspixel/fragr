# Multiplayer Excellence: The Golden Era Benchmark

Status: **in flight**, 2026-10-27: [rules depth](#rules-depth-431-and-432-wave-11) (dropped guns, the Duel line, Host presets and the Conquest bleed) is built; 2026-10-24: the [Host spine](#host-spine-431-wave-2) (Pillar 1's rules and text, and Pillar 7) is built, and so are [blast push, the Plate, Duel and the rematch](#movement-depth-and-the-rematch-431-wave-3) (Pillar 3 and the GoldenEye "couch friction"); voice casting and the other pillars stay planned. Planned 2026-10-17. Follows [bot-and-enemy-ai-excellence-20261017.md](bot-and-enemy-ai-excellence-20261017.md) and integrates into [ROADMAP.md](../ROADMAP.md#full-build-order). Spend for this plan: $0, using existing assets, local tools, and approved asset allowances.

---

## 1. Executive Summary and The Core Question

Does fragr have multiplayer working right now?
**Yes.** The authoritative 20 Hz Rust server, WebSocket networking on port 6767, UDP 6768 LAN presence discovery, 8 built-in multiplayer arenas, 5 competitive game modes (FFA, TDM, CTF, Sabotage, Conquest), multi-seat combined-arms vehicles (Jeeps, Boats, Aircraft, Motorcycles), proximity/remote mines, and humanized rule-bot backfilling are completely functional and tested in the codebase today.

Is it currently as fun as Doom II, Battlefield 1942, Halo, and GoldenEye 007?
**Almost, but with specific, identifiable tactile gaps.** The underlying engine architecture and movement physics are rock-solid, but the sensory reward loop, explosive physics interplay, and custom party mutators need targeted elevation to achieve the legendary S-tier status of the genre's greatest classics.

This specification details the concrete architectural upgrades required to bridge that gap.

---

## 2. Competitive Deconstruction: What Made the Legends Unforgettable

### 2.1 Doom II: The Meatshot and Kinetic Flow
- **The Super Shotgun:** The visceral rush of barrel-stuffing an opponent for a 1-hit kill. High risk, high reward.
- **Rocket Physics:** Leading moving targets, splash damage mindgames, and rocket jumping / vertical propulsion.
- **Map Circulation:** Controlling weapon respawns, armor pads, and megahealth loops.

### 2.2 Battlefield 1942: Combined-Arms Frontline Drama
- **Multi-Seat Teamwork:** Driver handles the vehicle while the gunner sweeps the horizon.
- **Splatter Kills:** High-speed roadkills reward vehicular momentum.
- **Conquest Bleed Tension:** When tickets bleed under 25, the music and sirens escalate into heart-pounding last-second turnaround drama.

### 2.3 Halo: Combat Evolved & Halo 3: The Party Sandbox
- **The Golden Triangle:** The seamless, rhythmic combat loop of Guns + Grenades + Melee.
- **The Booming Announcer:** Deep, electrifying voice callouts (*"Double Kill!"*, *"Triple Scrap!"*, *"Flag Taken!"*, *"Killing Spree!"*).
- **Tactile Hit Feedback:** The crisp chime / pop confirmation that confirms damage dealt.

### 2.4 GoldenEye 007: Tactical Trolling & Party Mutators
- **Proximity Mines:** The psychological warfare of booby-trapping doorways, armor pads, and corridor ceilings.
- **Legendary Mutators:** *Licence to Kill* (1-shot kills), *Golden Gun / Golden Rail* (single golden weapon), *Slappers Only* (fists only), and custom weapon restrictions.
- **Couch Friction:** Instant rematches, sudden death, and high-energy social banter.

---

## 3. The 7 Pillars of Multiplayer Excellence

### Pillar 1: Arena Host Announcer & Multikill Audio Juice
Currently, the Host reacts with textual barks in the combat chat feed (`FirstBlood`, `Double Kill`, `Triple Scrap`, `Streak Ended`, `Last Standing`, `Flag Taken`, `Flag Returned`, `Comeback`).
- **Implementation:** Record or synthesize dry, deadpan, cynical arena booth Host voice barks through `tools/audiogen` (ElevenLabs integration within approved credit allowances), matching the existing lines in `client/i18n/match.en.po`.
- **Client Playback:** Hook `ServerMessage::HostReaction` in `client/scripts/game_manager.gd` and play high-priority 2D broadcast audio clips over the `Voice` audio bus.
- **Key Callouts:**
  - Multikills: *"Double kill."*, *"Triple scrap."*, *"Rampage."*
  - Objectives: *"Flag taken."*, *"Flag dropped."*, *"Flag returned."*, *"Flag captured."*, *"Charge armed."*, *"Charge defused."*
  - Match Beats: *"First blood. Somebody had to."*, *"Streak ended. Say something nice."*, *"Comeback."*, *"The booth is standing."*

### Pillar 2: Visceral Hit Confirmation ("The Chime")
Currently, scoring a hit displays crosshair tick marks and floating damage numbers, but produces zero shooter-side audio cue.
- **Implementation:** Add a sharp, punchy metallic hit chime (`hit_confirm.wav`) triggered inside `hud.gd:show_hit_marker()`.
- **Dynamic Pitch Modulation:** Modulate the audio pitch upwards based on damage magnitude and critical headshot placement (e.g. baseline pitch for Tack 20 dmg, +4 semitones for Railgun 80 dmg or headshot flechettes).

### Pillar 3: Blast Impulse & Rocket Jumping Physics
Currently, `resolve_blast` in `server/src/sim/grenade.rs` computes line-of-sight damage but applies zero velocity impulse to players.
- **Server Implementation:** Compute a 3D outward momentum vector from blast epicenter to target feet:
  ```rust
  let impulse_dir = [
      (player.x - blast.position[0]) / distance,
      ((player.y - blast.position[1]) / distance).max(0.35),
      (player.z - blast.position[2]) / distance,
  ];
  let force = (1.0 - distance / blast.radius) * blast.peak * 0.18;
  player.vy += impulse_dir[1] * force;
  ```
- **Rocket Jumping Self-Damage Scaling:** Reduce self-inflicted explosive damage by 40% while preserving 100% vertical impulse, enabling high-skill rocket jumps to bypass stair routes or scale high gantries (Directive 17, Arena Duel).

### Pillar 4: Super Shotgun "Meatshot" Tuning

Built in wave 4 (`wave4/bots`): seven pellets inside 2 units make 105, one
blast through a bare fighter; the playtest harness asserts it beside the
sticky TTK table. The sound pass below is not part of it.
Currently, `WeaponType::Scatter` fires 7 pellets at 10 damage each (70 total), requiring 2 point-blank shots to kill an unarmored fighter.
- **Tuning:** Increase point-blank pellet concentration so landing all 7 pellets within 2.0 meters inflicts **105 total damage**, rewarding aggressive barrel-stuffing with an immediate one-shot kill.
- **Sound Feedback:** Thicken the Scattergun fire sound with a deeper sub-bass kick and audible pump mechanical clack.

### Pillar 5: Host UI Unlock: Full Modes & GoldenEye Mutators
The Rust server already supports `LicenceToKill`, `GoldenRail`, `ShotgunOnly`, `RailOnly`, `FistsOnly`, and `TwoLives`. However, the Godot client host UI (`client/scripts/local_host.gd` and `boot_menu.gd`) restricts mode selection to TDM/Sabotage/Conquest and omits mutator arguments.
- **Implementation:**
  - Expand `local_host.gd` to expose all 5 modes (`FFA`, `TDM`, `CTF`, `Sabotage`, `Conquest`).
  - Add a Mutators dropdown selector and quick-launch presets on the Host menu:
    - *Standard Match*
    - *Licence to Kill* (1-hit kill instagib)
    - *Golden Rail* (one golden gun with instant kill)
    - *Slappers Only* (fists only, high speed)
    - *Shotgun Wedding* (Scatterguns only)
    - *Proximity Party* (Pistols + Proximity Mines only)

### Pillar 6: Conquest Ticket Bleed Siren & Endgame Tension
Currently, Conquest tickets bleed silently on the HUD.
- **Implementation:**
  - When either team's ticket count drops below 25:
    - The ticket counter on `conquest_hud.gd` pulses in high-visibility warning amber/red.
    - An audible low-frequency alarm siren (`siren_warning.wav`) plays every 4 seconds.
    - A rapid heartbeat thump reinforces the final tickets.

### Pillar 7: Sudden Death
Not called overtime: that is the power item's name in the rule sheet ([multiplayer maps](multiplayer-maps.md#5-items-and-clocks)). Built as described in the [Host spine](#host-spine-431-wave-2) below; this was the original brief.
Currently, matches that reach the time limit with tied scores simply terminate with `"Match drawn"`.
- **Implementation:**
  - When the match clock expires while scores are tied, trigger `HostReactionKind::SuddenDeath`.
  - The HUD displays *"SUDDEN DEATH: NEXT FRAG DECIDES"*.
  - Match clock freezes; the next frag, flag capture, or bomb detonation ends the match instantly with a celebratory winner podium.

### Pillar 8: The Legendary Homage Maps & Modes ("Fuck Yeah Let's Go")
Classic multiplayer legends earned their immortality through unforgettable map layouts and mode rulesets that produced instant adrenaline. fragr honors these masterpieces through authentic in-universe homages that capture the exact tactical feel without being a lazy clone:
- **"Square One" (Doom II: Dead Simple / Map07 Homage):**
  - *Arena Duel* and *Directive 17 Substation* running **"Shotgun Wedding"** (Scatterguns only + meatshot 105 dmg) or **"Rocket Duel"** (Rocket Launchers only + 3D blast impulse).
  - Sunken central killing floor surrounded by elevated perimeter catwalks. Instant respawns, zero hiding spots, pure kinetic strafe-dueling and vertical rocket jumps.
- **"Perimeter Gulch" (Halo: Combat Evolved: Blood Gulch Homage):**
  - Two-base CTF on *Reclamation Gulch* and *Directive 17*.
  - Opposing fortified bases separated by a rugged canyon with mid-field boulder and container cover.
  - Vehicles enabled: Jeeps and Motorcycles for high-speed flag runs. A single high-value power weapon (Rocket Launcher or Golden Rail) spawns on the central ridge.
  - The unmistakable "Golden Triangle" combat loop: primary automatic fire to strip shields/armor, grenade bank around rocks, and a lethal shiv melee strike to finish.
- **"Atoll Battery" (Battlefield 1942: Wake Island Homage):**
  - Five-point Conquest on *Holdfast Atoll*.
  - Combined arms warfare: coastal road motorcycle dashes, multi-seat jeep sweeps, watercraft shallows flanking, and infantry bunker holds.
  - Dramatic ticket bleed siren when either team drops under 25 tickets, escalating the final stand.
- **"The Facility / Golden Rail" (GoldenEye 007 Homage):**
  - Tight subterranean chokepoints, blind corners, and vent drops on *Compliance Yard* and *Sector 9 Transit Hall*.
  - Preset Mutators:
    - *Licence to Kill:* Instant 1-hit kill lethality with Tack pistols and shivs. Pure twitch reflexes and corner-peeking tension.
    - *The Golden Rail:* One single golden Railgun in the map center. One-shot kill, illuminates through fog, drops on death.
    - *Proximity Party:* Pistols and Proximity Mines only. Trap doorways, blind corners, and spawn exits.
    - *Slappers Only:* Fists only, movement speed boosted to 1.25x. Rapid-fire comedic melee brawls.

---

## Host spine (#431, wave 2)

Text and rules only; voice casting is Nick's and no audio was generated.

**Direction (Nick, #431, 2026-10-23).** Host calls are rare: voice only big
moments, captions for the rest, eight seconds or more between voices. No
frequency puns and no station ident in match copy; the intro is a plain arena
intro. Canon ([voice](../lore/voice.md), [cast](../lore/cast.md)): capitals and
adrenaline when calling, never explains the setting, never chants. Players get
an announcer setting (On, Big moments only, Off) and an announcer volume.

**Rules as built.**
- Every call is a `HostReactionKind` (`protocol/rules.rs`); `big()` marks the
  voiced kinds. Multikills chain frags within three seconds (`double_frag`
  caption, then `triple_frag`, `quad_frag`, `frag_storm` voiced). Sprees scale
  by mode (`rules::spree_step`: 5 in FFA and TDM, 4 in CTF and Conquest, 3 in
  Sabotage): `rampage`, `riot`, `untouchable` at one, two and three steps, and
  `streak_ended` needs one step. `lead_change` and `flag_taken` are captions;
  `flag_captured`, `charge_planted`, `match_point` and `sudden_death` are voiced.
- Spacing (`sim/modes.rs`): a big call waits eight seconds after the last big
  call, a caption eight seconds after any call; a frag makes at most one call,
  the biggest; `sudden_death` and `golden_rail` are never held back.
- Sudden death replaces the draw: a level clock with something scored stops and
  the next score wins; two quiet minutes end level. A short Sabotage match level
  after its extra pair plays one deciding round. Not called overtime, which is a
  power item.
- Client: captions keep names; `host_voice.gd` plays the name-free slot
  `res://assets/audio/host/<kind>_<variant>.mp3` on the `Announcer` bus when a
  recording exists, so recorded lines drop in without code. The setting uses
  the same keys as PR #448.

**Not done.** Casting and recordings (asset round E-1, E-2). Conquest lead calls
(the ticket bleed call landed in wave 11). Quad and frag storm rarely voice, because the triple
just spoke inside the eight seconds; that is the rarity rule working, revisit
after a listening pass.

---

## Movement depth and the rematch (#431, wave 3)

Built on `wave3/mp-depth`, 2026-10-24. Linux evidence only.

- **Blast push (Pillar 3).** `movement::blast_push` beside the frozen feel
  block, mirrored in `MoveStep.blast_push` and pinned by six blast cases in
  each golden file (`docs/protocol.md`, Movement). Every arena explosive
  throws the fighters it damages; a rocket always throws its owner, who takes
  0.6 of its splash. Standing rocket jump about 1.3 m, jump-then-rocket about
  2.9 m. It replaced the wave 2 rocket's inline self-only impulse, whose
  upward ratio mixed world and feet heights.
- **The Rocket and the Custody Plate on Larak Lot** ([larak-lot.md](larak-lot.md#wave-3-the-plate-the-rocket-and-duel)).
- **Again.** `Action.again` on the podium; when every seated person and agent
  has pressed, the next round opens 2 s after the result instead of 8 s. Rule
  bots never hold it up. A fighter fragged at the whistle presses too. After
  a finished free-for-all or Duel round every fighter starts the next from a
  spawn at full health.
- **Duel.** `--mode duel`: free-for-all rules, two seats with bot hand-over,
  no Continuance pressure, a running series and a Host rematch line, no MVP
  for a level round. The spectator queue and winner-stays landed in wave
  11 and the head-to-head book in wave 4.

## Rules depth (#431 and #432, wave 11)

Built on `wave11/mp-rules`, 2026-10-27. Linux evidence only.

- **Weapons drop on death** in the Pistol start (free-for-all and Duel): the
  gun in hand with its rounds, 15 s on the floor, known to bots and agents
  only once seen. Rules, exceptions and measurements are in the
  [bot plan](bot-and-enemy-ai-excellence-20261017.md#6-progress). The Rocket
  share target at six bots is still not met.
- **The Duel line and winner-stays.** A watcher presses Join to wait in line
  (`queue`); the head of the line is called to any seat that opens with a
  one-time token the server holds for ten seconds (`seat_call`, Hello
  `seat`). When a round between two people ends with a winner and somebody
  waits, the loser's socket closes with `duel_seat_passed`, the caller takes
  the seat, and the native client returns the loser to the back of the line.
  A level round passes nobody. The line shows on the watcher's plate and on
  the podium (`duel_queue`), and each hand-over is a `next_up` Host caption
  ("NIGHTFALL STAYS. STATIC KID, YOU'RE UP!"). Server-owned
  (`server/src/session/queue.rs`); MCP has no queue tool.
- **Host presets and stacking (Pillar 5).** Standard, Licence to Kill, Golden
  Rail, Slappers Only and Shotgun Wedding as one row on the Host page, with a
  short Stack line (Licence to Kill, Two Lives, Full Arsenal) disabled where
  the server would refuse the combination. Dedicated parity:
  `fragr-server --preset <id>` stacks with repeated `--mutator`
  (`server/src/rules/preset.rs`). Proximity Party is not built: the server
  has no Pistol and mines start kit.
- **Conquest bleed (Pillar 6).** Under 25 tickets (`CONQUEST_BLEED_TICKETS`)
  the side's counter pulses between bone and warning red on a level
  baseline, a low siren sounds every four seconds, and from ten tickets a
  heartbeat joins it (`client/scripts/conquest_hud.gd`). The Host calls each
  side's fall once a round (`tickets_low`, a voiced slot; the recording is
  for the Host voice round).

## 4. Verification and Delivery Sequence

1. **Phase 1: Audio Feedback & Sensory Juice:** Announcer voice lines, slang updates, and metallic hit confirmation chime.
2. **Phase 2: Physics & Weapon Tuning:** Blast impulse, rocket jumping, and Super Shotgun meatshot balance.
3. **Phase 3: Host UI & Mutator Freedom:** Enabling all 5 modes (`ffa`, `tdm`, `ctf`, `sabotage`, `conquest`), mutator flags, and legendary homage presets in the desktop host dialog.
4. **Phase 4: Endgame Drama & Overtime:** Conquest siren bleed cues, Sudden Death tiebreakers, and homage map playlist rotations.

---

## 5. Spend and Asset Safety

- Zero mandatory cash spend ($0).
- Voice announcer generation consumes existing included ElevenLabs credits via `tools/audiogen`.
- All code authorship strictly Nick Seal (`blisspixel`). Zero AI attribution.
