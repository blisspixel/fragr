# fragr 1.0 craft bar: measurable properties from the reference shooters

Research of 2026-10-31, kept as the source for [the 1.0 bar](../ROADMAP.md#the-10-bar). A target here is a proposal until the roadmap adopts it; each adopted target is built and measured through issues. It builds on the October 23 study of the thirteen fun principles (Quake, UT, Counter-Strike, Battlefield and Halo). That note answered "what made them fun"; this one answers
"what numbers and checkable rules made them well made", so the 1.0 bar can be a
list of measurements instead of a feeling.

Source tags used throughout:

- **SRC**: read in shipped source code or config (id GPL releases, Valve cfg and
  botprofile.db via SteamTracking, Epic UnrealScript mirrors).
- **PAGE**: primary or named secondary page or PDF fetched and read.
- **SNIP**: only seen in a search summary (often a 403 page such as the Valve
  Developer Wiki, Liquipedia, doomwiki). A lead, not a fact.
- **DERIVED**: arithmetic by this note from sourced constants.
- **UNSOURCED**: looked for and not found. Do not cite as fact.

fragr baseline values quoted below are read from `main` on this date:
`server/src/movement.rs`, `server/src/rules.rs`, `server/src/sim/rewind.rs`,
`server/src/sim/bot_senses.rs`, `docs/TRANSPORT.md`, `docs/plans/gunfeel.md`,
`docs/plans/ttk-feel-harness-proof.md`, and the playtest report fields in
`tools/playtest/src/`.

---

## Executive summary: the 22 properties that matter most

Each row: property, what the references do, proposed fragr target, how to check.
"Auto" means a headless test, harness, bot survey or capture can gate it;
"Human" means it needs eyes, ears or a fresh player.

| # | Property | Reference values | fragr target | Check |
|---|---|---|---|---|
| 1 | Fixed simulation step, frame-rate independent | Q3 movement changed with frame rate (125 fps jump) until `pmove_fixed`; pmove_msec 8 | Movement identical at 30, 60, 144, 240 fps render; golden vectors bit-stable | Auto: golden vectors replayed under varied render dt |
| 2 | Server tick and snapshot rate | Apex 20 Hz, Q3 sv_fps 20, Titanfall 2 20 Hz state, CS2 64, Valorant 128 | Keep 20 Hz to 1.0; tick p99 under 25 percent of the 50 ms budget at 16 fighters plus 8 watchers | Auto: `--bench-assert`, soak |
| 3 | Interpolation delay | Source 100 ms, Overwatch about 20 ms after 63 Hz, Valorant one 7.8 ms frame | 100 ms now (two ticks); target 50 to 75 ms with one-tick buffer plus loss-triggered widening, only if loss under 1 percent | Auto: probe of render-time minus server-time |
| 4 | Peeker's advantage (time an enemy sees you before you see them) | Valorant about 141 ms baseline, about 71 ms after work at 144 fps | Under 150 ms at 50 ms RTT on LAN-to-regional links | Auto: two-client probe; DERIVED budget below |
| 5 | Lag compensation bound | Source sv_maxunlag 1 s; Riot argues for tight bounds (500 ms "kill behind cover") | Keep 200 ms rewind cap; zero hits through current cover | Auto: rewind tests exist; add playtest shot audit |
| 6 | Input to photon on the local pawn | Most players 50 to 100 ms system latency (NVIDIA); detection threshold median 51 to 90 ms, best players under 40 ms | Local movement and shot presentation under 60 ms at 60 fps vsync off (prediction, not ack) | Auto: frame-stamp probe; Human: feel |
| 7 | Frame-time consistency | Valorant spec tiers 30 / 60 / 144 fps | 1 percent low at or above 60 fps on the reference iGPU at 1080p; no frame over 50 ms in a 5 min match after warmup | Auto: `frame_stats.gd` and benchmark scenes |
| 8 | Stop and start time (counter-strafe) | CS2 counter-strafe to accurate about 80 ms, full stop 110 to 125 ms; release-only 375 to 405 ms | Full stop 100 to 150 ms (now about 150 ms DERIVED); top speed reached in 100 to 150 ms (now about 100 ms) | Auto: movement golden test asserting tick counts |
| 9 | Jump arc | Q3 apex about 1.16 m, airtime 0.68 s; UT2004 double jump 126 u | Apex 1.0 to 1.2 m (now 1.11 m), airtime 0.6 to 0.7 s (now 0.64 s); every authored ledge either clearly jumpable or clearly not | Auto: geometry scan of ledge heights against apex minus margin |
| 10 | Dodge and skill ceiling | UT99 and UT2004 dodge 1.5x run; Q3 strafe jump 320 to 600+ ups | Dodge 1.5x (kept, 9 vs 6 m/s); one owned tech that gains speed or reach (rocket jump) with a hard cap 2.0x to 2.5x run | Auto: blast caps in movement tests; Human: discoverable |
| 11 | Time to kill against reaction time | Simple visual reaction about 265 ms; CS AK body 0.30 s, Halo CE pistol 0.6 s, Halo 3 BR 1.2 to 1.5 s, Q3 LG 100 HP in about 0.63 s | Clean-hit TTK 0.5 to 1.2 s (current sticky table 0.6 / 0.9 / 1.0), measured median 0.8 to 1.5 s; no non-power weapon under 2x reaction time | Auto: sticky table plus harness `time_to_kill_s` quantiles |
| 12 | Weapon share and role separation | Apex nerfs at about 20 percent pick rate; Destiny MIDA 15 percent of PvP kills was "too much"; Valorant uses 4M+ matches | No arcade weapon above 45 percent of shots or kills; each weapon's kill distance median inside its own band with under 30 percent overlap | Auto: harness `shot_share`, `frag_weapons`, `kill_distance` |
| 13 | Power item clocks | Q3 armor 25 s, mega 35 s, powerups 120 s, weapons 5 s FFA / 30 s team; UT2004 UDamage 90 s, belt and keg 60 s | Plate 35 s, power 90 to 120 s, health and armor 25 s (already close); pad contest index above 15 percent | Auto: harness `pad_contest_index`, `appointment_share` |
| 14 | Spawn safety | CoD BO2 "3 second rule": never shot or able to shoot within 3 s of spawning; Q3 furthest-half random from your own death point | Spawn deaths within 3 s under 2 percent of spawns; first contact 5 to 15 s after spawn in FFA | Auto: harness `spawn_deaths_per_spawn`; add a time-to-contact metric |
| 15 | Death to back in the fight | Overwatch 10 to 12 s; Halo Slayer 5 s; Q3 on click; CS one life per round | FFA 4 s, team 3 s (current) plus under 12 s to first contact after respawn; death recap within 300 ms of death | Auto: harness timeline; Human: does dying feel like a beat |
| 16 | Hit and kill confirmation | Overwatch distinct hit sound that cuts through the mix; CS headshot dink; gunfeel plan: 120 ms marker, 40 ms tick, 250 ms on kill | Every damaging hit produces a marker and a sound within one render frame of the server confirmation; kill confirm distinct by sound alone | Auto: client harness asserts event to marker; Human: blind audio test |
| 17 | Enemy readability | TF2: every class recognizable by silhouette alone, characters more saturated than environment; Valorant holds skins for readability; colour-blind enemy highlight options | Enemy vs world luminance contrast above 3:1 at 30 m on every map; faction readable in silhouette at 40 m; one colour-blind preset | Auto: capture plus contrast scan; Human: silhouette test |
| 18 | Footstep and threat audio | CS2 2023: landings as audible as footsteps; Valorant footsteps tuned for presence over distance; Overwatch "play by sound" | Enemy footsteps audible to 20 to 30 m running, silent walking; direction judged within 45 deg in a blind test | Auto: attenuation table test; Human: blind direction test |
| 19 | Loudness and mix | Sony ASWG-R001: -24 LKFS integrated plus or minus 2, true peak at or below -1 dBTP; DICE HDR audio prioritizes by loudness | Gameplay capture integrated -23 to -18 LUFS on desktop, true peak at or below -1 dBTP, announcer and hit sounds never masked | Auto: ffmpeg ebur128 on QA tour audio |
| 20 | Map timing | CS: T about 20 s to a site, CT about 10 s, rotate about 15 s (community SNIP); Carney: hard points 3+ entrances; LDB: 3 to 4 chokepoints | Sabotage: attackers 15 to 25 s to each site, defenders 8 to 12 s, rotate 10 to 18 s; small FFA map corner to corner under 25 s; every hard point 3+ entrances | Auto: navmesh timing tool per map |
| 21 | Bot honesty and difficulty ladder | CS bot reaction 0.05 (Elite) to 0.6 s (Normal) plus 0.7 to 0.9 s attack delay; Q3 needs LOS and 90 to 180 deg FOV; UT3 leads only at skill 4+ | Keep 200 to 400 ms reaction, 120 deg cone, LOS; publish 4 to 5 tiers whose win rate against the median tier is monotonic | Auto: bot survey tier ladder; Human: "felt fair" |
| 22 | Campaign pacing | Doom E1 par 30 to 180 s; Halo 3 / 30 / 3 min loops; Halo saves wait for safety (10 s timeout); LDB 1 to 3 enemy types per encounter; Valve: done when playtests stop being painful | Each level 8 to 15 min first clear; checkpoint gap under 3 min of play; at most 3 enemy types per encounter except named brawls; a new enemy or verb every level, taught without text | Auto: campaign survey times and checkpoint gaps; Human: fresh-player sessions |

The derived latency budget behind rows 3 and 4 is in section 1. The full set
of human-only checks is collected in section 11.

---

## 1. Responsiveness

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Default timestep 15 ms (66.67 ticks/s); client about 20 snapshots/s, about 30 command packets/s (CS:S era defaults) | Source | PAGE (copy of Valve wiki) | https://gist.github.com/CoolOppo/fe0586836de3fb2f90f9 |
| `cl_interp` 0.1 s default, sized so one lost snapshot still leaves two to interpolate; effective delay max(cl_interp, cl_interp_ratio / cl_updaterate) | Source | PAGE | same gist |
| Lag compensation: command time = server time minus latency minus interpolation; `sv_maxunlag` 1 s | Source | PAGE / SNIP | same gist; https://developer.valvesoftware.com/wiki/Lag_Compensation |
| CS:GO matchmaking 64 tick, FACEIT and ESEA 128; CS2 64 tick with sub-tick timestamps on movement start, shots and throws | CS | SNIP | https://gameworldobserver.com/2023/03/22/counter-strike-2-sub-tick-source-2-features-valve |
| Client and server 128 Hz; target 35 ms ping for 70 percent of players | Valorant | PAGE | https://www.riotgames.com/en/news/peeking-valorants-netcode |
| Peeker's advantage about 141 ms baseline; cut about 40 ms by server and network work; about 71 ms at 144 fps | Valorant | PAGE | same |
| Duels decided by 20 to 50 ms; a 10 ms change swung a test matchup to 90 percent | Valorant | PAGE | same |
| Client buffers one frame, server half a frame on average | Valorant | PAGE | same |
| 2.34 ms server budget per game per 128 Hz frame (3+ games per core, 10 percent kept for OS); server frame went from 50 ms to under 2 ms | Valorant | PAGE | https://www.riotgames.com/en/news/valorants-128-tick-servers |
| 20 Hz server; 60 Hz judged "not meaningfully different" for triple bandwidth (60 to 180 kB/s); worst case 75 ms input processing at 50 ms ping vs 41.67 ms at 60 Hz; displays add 20 to 50 ms | Apex | PAGE | https://www.ea.com/games/apex-legends/news/servers-netcode-developer-deep-dive |
| sv_fps 20, snaps 20, cl_maxpackets 30 | Quake 3 | SRC | https://github.com/ioquake/ioq3/blob/main/code/server/sv_init.c |
| Pmove splits moves into steps of at most 66 ms and snaps velocity to integers each step; pmove_msec default 8 (125 Hz) | Quake 3 | SRC | https://github.com/ioquake/ioq3/blob/main/code/game/bg_pmove.c |
| 21 to 63 client updates/s (2016); interpolation about 60 ms to about 20 ms | Overwatch | SNIP | https://gamesbeat.com/overwatch-netcode-tick-rate-60hz/ |
| BF4 retail 30 Hz; 60 and 120 Hz tested 2015; consoles 32p to 45 Hz | Battlefield 4 | SNIP | https://mp1st.com/news/dice-la-introduces-120hz-tickrate-to-battlefield-4-cte-aka-really-good-netcode |
| Titanfall 2 client 60 Hz input, server 20 Hz state; Titanfall 1 was 30/10 | Titanfall 2 | SNIP | https://www.gamestar.de/artikel/titanfall_2,3276505.html |
| Quake Live sv_fps 40 | Quake Live | SNIP (community) | https://www.github.com/etlegacy/etlegacy/issues/2555 |
| Under about 20 ms "generally imperceptible"; 50 ms "responsive, but still subtly lagging" | Carmack (VR context) | PAGE (mirror) | https://danluu.com/latency-mitigation/ |
| "Most gamers play on systems with 50 to 100 ms of system latency" | NVIDIA | PAGE | https://www.nvidia.com/en-us/geforce/news/reflex-low-latency-platform/ |
| 12 vs 20 ms system latency: median aim task 1.348 vs 1.530 s (n=8, p under 0.005) | NVIDIA research | PAGE | https://ar5iv.labs.arxiv.org/html/2105.10498 |
| Most sensitive players detect delay under 40 ms; median threshold 51 to 90 ms | Raaen et al. 2014 | PAGE | https://cms.simula.no/sites/default/files/publications/files/paper_5.pdf |
| Each extra 100 ms network latency costs about 15 percent rifle accuracy and score; shotguns lose about a third as much | WPI CS:GO study, 42 players | PAGE | https://ftp.cs.wpi.edu/pub/techreports/pdf/21-08.pdf |
| 100 ms "approximately the tolerable threshold" for FPS | Claypool | PAGE | https://sites.cs.ucsb.edu/~almeroth/classes/W10.290F/papers/claypool-10.pdf |
| Battlefield 1942 tick, Halo host rates, Overwatch favor-the-shooter ping cutoff, Battle(non)sense per-game delay table, Digital Foundry frame pacing guidance | various | UNSOURCED | none |

### fragr today

20 Hz authoritative tick; local pawn predicts and reconciles (`docs/TRANSPORT.md`);
remote fighters drawn through a 100 ms (two tick) render buffer; hitscan rewind
capped at 4 ticks, 200 ms (`server/src/sim/rewind.rs`); benchmark already gates
the 50 ms tick budget and p99 (`docs/BENCHMARK.md`), and measures
`input.input_to_ack_ms` and `tick_to_watcher_ms`.

### Derived peeker budget (DERIVED)

When an enemy steps out, a fragr victim sees it after: half RTT (25 ms at 50 ms
RTT) plus mean tick wait (25 ms) plus interpolation (100 ms) plus a render frame
(8 to 17 ms) = about 160 to 170 ms. The peeker sees the victim through the same
interpolation, so the asymmetry is dominated by the victim's 100 ms buffer plus
the peeker's prediction lead. That puts fragr near Valorant's untuned baseline
(141 ms), which Riot judged worth months of work to halve. At 20 Hz a buffer
below one tick (50 ms) is not possible without extrapolation, so the reachable
target is about 110 to 130 ms with a one-tick buffer, and about 160 ms today.

### Proposed targets

- **Fixed step everywhere (hard rule).** Movement, projectiles and the
  GDScript mirror step at 1/20 s regardless of render rate. Quake 3's 125 fps
  jump is the warning: frame-rate-dependent physics becomes a competitive
  requirement for one frame rate.
- **Tick.** Stay at 20 Hz through 1.0. Apex and Titanfall 2 show 20 Hz can feel
  fine with prediction and good presentation; the transport doc's UDP spike is
  the place to revisit, with a measurement table.
- **Interpolation.** Target 50 to 75 ms (one tick plus jitter margin) adaptive:
  widen to two ticks only when measured snapshot loss or jitter needs it.
  Range reasoning: Source chose 100 ms for one lost packet at 20 snapshots/s;
  WebSocket over TCP does not lose packets but does stall, so jitter, not loss,
  sets the buffer.
- **Peeker's advantage.** Under 150 ms at 50 ms RTT; under 120 ms stretch.
- **Rewind cap.** Keep 200 ms. Report the share of hits that used rewind above
  100 ms; if it is above 10 percent on LAN, the interpolation buffer is too big.
- **Local presentation latency.** The local shot (muzzle, kick, tracer, sound)
  and local movement must present on the next render frame after input, never
  after the ack. Target input to photon under 60 ms at 60 fps with vsync off on
  the reference machine (NVIDIA's "most gamers" band is 50 to 100 ms; best
  players detect under 40 ms).
- **Hit registration correctness.** Zero confirmed hits through cover that
  exists at the present tick (already the rewind rule). A miss the shooter saw
  as a hit should be under 3 percent of fired hitscan shots at 50 ms RTT
  with a moving target (the client-predicted ray versus the authoritative ray).

### How to measure

- Auto: golden vectors under randomized render dt (exists in part); a two
  client loopback probe with an injected delay (20, 50, 100 ms) that records
  "peer becomes visible" timestamps on both clients; `input_to_ack_ms` already
  exists; add `presented_frame_ms` stamped from input event to the frame that
  shows the muzzle; add a "client said hit, server said miss" counter to the
  playtest shot report.
- Human: feel at 0 ms and at 60 ms RTT netem in a blind A/B.

---

## 2. Movement

### Reference values (units noted; Quake and Source at 1 u = 1 inch unless stated)

| Value | Game | Tag | Source |
|---|---|---|---|
| g_speed 320, accelerate 10, airaccelerate 1, friction 6, stopspeed 100, gravity 800, jump 270 (apex 45.6 u, about 1.16 m), duck scale 0.25 | Quake 3 | SRC | https://github.com/id-Software/Quake-III-Arena (bg_pmove.c, bg_local.h) |
| Strafe jumping 320 to over 600 ups | Quake 3 | SNIP | https://giantbomb.com/wiki/Concepts/Strafe_Jumping |
| Crouch 0.333x; bunnyhop cap 1.7x maxspeed, over cap scaled to 0.65 of cap | Half-Life | SRC | https://github.com/ValveSoftware/halflife/blob/master/pm_shared/pm_shared.c |
| sv_friction 5.2, sv_stopspeed 80, sv_accelerate 5.5, gravity 800 | CS2 | SNIP | https://totalcsgo.com/commands/svfriction |
| Move speeds: knife 250, M4 225, AK 215, AWP 200 u/s | CS2 | PAGE | https://turbosmurfs.gg/?p=8949 |
| First shot accurate below 34 percent of weapon max speed (community measured) | CS2 | PAGE | same |
| Counter-strafe to accurate about 80 ms vs about 200 ms by release; full stop 110 to 125 ms vs 375 to 405 ms | CS2 | PAGE (community model) | same |
| GroundSpeed 440, JumpZ 340, dodge 1.5x run (660), dodge Z 210, gravity 950, AirControl 0.35, crouch 0.4, one double jump | UT2004 | SRC | https://github.com/Deaod/UT2004 |
| Jump 54 u, double jump 126 u, wall dodge combo to 965 u long | UT2004 | PAGE | https://unrealarchive.org/wikis/unreal-wiki/Legacy:Movement_Metrics_(UT2004).html |
| GroundSpeed 400, dodge 1.5x with Z 160 | UT99 | SRC | https://github.com/Slipyx/UT99 |
| Run 16.67 u/tic (583 u/s); SR50 23.57 u/tic, 41 percent faster; no air control | Doom | SRC | https://github.com/id-Software/DOOM (g_game.c, p_mobj.c) |
| CE, 2 and 3 run 2.25 wu/s (about 6.9 m/s), no sprint; Infinite 2.6 with 1.11x sprint | Halo | PAGE | https://halopedia.org/Spartan_(multiplayer) |
| Walk 5.07, sprint 7.59, crouch 2.34 m/s | Apex | PAGE | https://apexlegends.wiki.gg/wiki/Movement |
| Titanfall 1 run 3.4 m/s, sprint 5.1 m/s, wallrun up to about 2x sprint; Titanfall 2 made air and wallrun speed faster and retained across chains | Titanfall | PAGE / SNIP | https://gameranx.com/updates/id/20713/article/titanfall-raw-weapon-stats-decrypted-titan-health-and-speed-revealed/ |
| Titanfall 2 exact slide and wallrun numbers; CPMA and Quake Live air control constants | | UNSOURCED | |

### fragr today (from `server/src/movement.rs`)

Top speed 6.0 m/s (arena), accel 15, friction 12, stop speed 2.0, air accel 2,
air speed cap 7.5, dodge 9 m/s with 3.5 m/s hop and 15 tick (0.75 s) cooldown,
jump 7 m/s at gravity 22 (apex 1.11 m, airtime 0.64 s), crouch 0.34x, blast
push 8.1 with speed cap 14 m/s. Campaign keeps 5 m/s.

DERIVED at 20 Hz with Quake-style friction: from 6 m/s with no input, ticks
go 6.0, 2.4, 0.96, 0, so a full stop takes 3 ticks (150 ms); with the opposite
key held it is about 2 ticks. From rest, top speed in 2 ticks (100 ms). Quake 3
for comparison reaches 320 ups in about 0.2 to 0.3 s and CS in longer (DERIVED,
low confidence). fragr is crisper than both, which suits "CS-crisp" from the
feel decisions, and its jump arc is within 5 percent of Quake 3's.

### Proposed targets

- **Stop time 100 to 150 ms (counter-strafe 50 to 100 ms).** CS's crispness
  comes from stop time near 110 ms and first-shot accuracy gated on speed.
  Keep fragr's current values; add a speed-gated accuracy only if a weapon is
  meant to punish run and gun (likely the Rail only).
- **Accel to top speed 100 to 200 ms.** Under 100 ms reads as weightless;
  over 300 ms reads as sludge (UT3 lesson in the prior synthesis).
- **Jump apex 1.0 to 1.2 m, airtime 0.55 to 0.7 s.** Authored geometry must
  respect it: any ledge between apex minus 0.15 m and apex plus 0.1 m is
  "ambiguous" and must be fixed (Level Design Book: design jumps shorter than
  max, keep special jumps off the critical path,
  https://book.leveldesignbook.com/process/blockout/metrics/quake).
- **Dodge 1.5x run** (UT99, UT2004 ratio; fragr already 9 vs 6).
- **Skill ceiling with a cap.** One owned speed tech (rocket and grenade jump,
  shipped as blast push) capped at 2.0x to 2.5x run horizontal (14 m/s cap is
  2.33x, inside). Half-Life's 1.7x bhop cap shows the industry answer: allow the
  tech, cap the runaway.
- **Readability.** Remote fighters' animation state (run, crouch, airborne,
  dodge) must be distinguishable at 30 m in a capture; dodge has a visible and
  audible tell.
- **Freeze rule.** After 1.0 feel sign-off, movement constants change only with
  a version bump and release note (UT2003 lesson).

### How to measure

- Auto: golden tests that assert tick counts for stop, start, dodge distance and
  apex (cheap, deterministic; the mirror already has goldens). A map scan that
  lists every step and ledge height between 0.6 m (step-up) and 1.3 m and flags
  the ambiguous band. Harness: share of travel airborne and dodges per minute.
- Human: blind feel A/B against a stored reference build; first-session
  players discover blast jump unprompted within 3 sessions.

---

## 3. Weapons and lethality

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Rail 100 per 1.5 s; rocket 100 direct plus 100 splash radius 120 u per 0.8 s, 900 u/s; LG 8 per 50 ms (160 DPS); MG 7 (5 team) per 100 ms; shotgun 11 x 10 per 1.0 s; plasma 20 per 100 ms | Quake 3 | SRC | https://github.com/id-Software/Quake-III-Arena (g_weapon.c, g_missile.c, bg_pmove.c) |
| Spawn 125 HP decaying 1/s to 100; mega +100 to 200 | Quake 3 | SRC | same (g_client.c, g_active.c) |
| LG 70 (2x head) per 1.6 s; shock beam 45 per 0.7 s; shock combo 200 radius 275; flak 9 x 13; rocket 90 per 0.9 s | UT2004 | SRC | https://github.com/Deaod/UT2004 |
| Bullet 5, 10 or 15; shotgun 7 pellets (mean 70); SSG 20 pellets | Doom | SRC | https://github.com/id-Software/DOOM (p_pspr.c) |
| AK 36 dmg, 4x head, 77.5 percent armor pen, 600 RPM; armored body TTK 4 shots / 300 ms; M4A4 5 shots / 360 ms | CS2 | PAGE | https://csdb.gg/compare/ak-47-vs-m4a4/ |
| Vandal 160 head at any range; Phantom 140 at 15 to 30 m; balance drawn from 4M+ matches | Valorant | PAGE | https://playvalorant.com/en-us/news/dev/valorant-data-drop-phantom-vs-vandal/ |
| Pistol 3 head or 5 body vs shields at about 3.33 rps; about 0.6 s three-shot | Halo CE | PAGE / DERIVED | https://www.halopedia.org/M6D_magnum/Gameplay |
| BR 6 x 3 per burst, 0.3 s between, 4 bursts; TTK about 1.2 to 1.5 s | Halo 3 | PAGE / DERIVED | https://www.halopedia.org/H3:Battle_Rifle |
| Shields and health CE 75/75, H2 and H3 70/45, Infinite 140/90 | Halo | PAGE | https://halopedia.org/Spartan_(multiplayer) |
| Bandit fire rate 2.9 to 2.715 "to address community feedback around time-to-kill", from player data | Halo Infinite | PAGE | https://www.halowaypoint.com/news/sandbox-update-halo-infinite |
| SMGs max 4 bullets within 12 m; shotguns 12 pellets | Battlefield 1 | PAGE | https://www.ea.com/games/battlefield/news/improving-battlefield-1-weapon-balance |
| Balance metrics: pick rate (adjusted for availability), encounter win rate, share of downs | Apex | SNIP (official page refused) | https://forums.ea.com/blog/apex-legends-game-info-hub-en/amped-midseason-designer%e2%80%99s-notes/13100020 |
| MIDA share of PvP kills 15.3 to 13.0 percent after nerf | Destiny 2 | SNIP | https://mein-mmo.de/en/destiny-2-die-mida-im-pvp-nicht-op,180525 |
| Simple visual reaction about 265 ms | human benchmark | PAGE | https://ki.infil.net/reaction.html |
| CS fixed spray patterns, "first N bullets accurate"; Battlefield kill share numbers; any published "fair TTK" rule | | UNSOURCED | |

### fragr today

100 HP, head band 2x (`combat.rs`). Sticky clean-hit TTK table: Flechette 4
hits / 0.6 s, Scatter 3 hits / 0.9 s point blank (7 pellets of 10, Doom's
shotgun mean exactly), Rail 80 per shot, 2 hits / 1.0 s; asserted band 0.5 to
1.2 s. Gunfeel plan records measured median kill 0.90 to 1.30 s. Earlier
harness: Flechette 65 to 75 percent of shots, Rail 2 to 4 percent of shots.
Harness already reports `shot_share`, `frag_weapons`, `kill_distance`,
`time_to_kill_s` quantiles and `rocket_frag_share`.

### Proposed targets

- **TTK band.** Clean-hit 0.5 to 1.2 s (keep); measured median under real aim
  0.8 to 1.5 s. Reasoning: arena lineage (Quake LG about 0.63 s, Halo CE 0.6 s,
  Halo 3 BR 1.2 to 1.5 s) sits at 2x to 5x human reaction time, which lets the
  victim respond, dodge or retreat; CS and CoD (0.18 to 0.3 s) sit at or under
  reaction time and are a different game. fragr's watch-or-join, agent-shared
  identity needs the victim to have a turn.
- **Floor.** No non-power weapon kills a full-health target in under 0.5 s
  (about 2x reaction); power items (Overtime triple damage, rocket direct plus
  splash) may.
- **Usage share.** No weapon above 45 percent of shots or kills in the
  six-agent harness with all pads live; no pad weapon under 8 percent of kills
  on the map built for it. Apex treats 20 percent pick on a field of many as a
  nerf trigger; with four to five arcade weapons, 45 percent is the equivalent
  "dominant" line.
- **Role separation.** Each weapon's median kill distance inside its band
  (Scatter under 8 m, Flechette 8 to 25 m, Rail over 20 m on maps with long
  lanes) with under 30 percent of its kills in a neighbour's band.
- **Headshots.** Keep 2x (Quake had none, UT 2x LG, CS 4x, Valorant 4x Vandal).
  2x rewards aim without making body shots pointless. Target headshot share of
  hitscan kills 15 to 35 percent in human play.
- **Falloff and spread.** Every spread or falloff must be deterministic or
  pattern based (CS spray patterns are learnable; random cone bloom is not).
  Scatter pellet pattern fixed per shot: already a seeded server rule; keep it
  seeded and render the true pattern.
- **Splash.** Rocket splash damage readable: self-damage half; a 1 m miss still
  hurts; splash kill share 15 to 25 percent on rocket maps (prior synthesis B1).

### How to measure

- Auto: sticky table assert (exists); harness quantiles, shot share and kill
  distance histograms per map (exist) promoted from report-only to thresholds
  on a long nightly survey, not on short CI samples (noise).
- Human: "which gun would you go for" asked after a session; a weapon nobody
  names is dead content.

---

## 4. Feedback and readability

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Every class recognizable by silhouette alone (tested); rim highlights not outlines; characters more saturated and value contrasted than environment; team colour warm vs cool | TF2 | PAGE | https://www.advances.realtimerendering.com/s2007/Mitchell-IllustrativeRenderingInTF2(Siggraph07%20Course%20Notes).pdf |
| Agent skins withheld: "Readability is critical in our game" | Valorant | SNIP | https://www.gfinityesports.com/article/valorant-riot-agent-skins-act-2-3-pc-customisation |
| Enemy highlight red default, purple and yellow colour-blind options; outline and fresnel toggles (6.06) | Valorant | SNIP | https://dotesports.com/valorant/news/how-to-change-enemy-highlight-color-in-valorant |
| A body-shot particle that reads as a headshot is treated as a readability bug | Valorant | PAGE | https://playvalorant.com/en-us/news/dev/ask-valorant-4 |
| Hit sound designed to cut through the mix without sounding like a hero | Overwatch | SNIP | https://www.pcgamer.com/au/overwatchs-hit-sound-effect-is-apparently-powered-by-beer |
| Hit marker popularized by CoD4 as an MP concession | CoD | SNIP | https://twinfinite.net/2016/12/reticle-unsung-hero-modern-shooters/ |
| Motion tracker CE 15 m (cut from 25), H2 20 m, H3 25 m; crouch hides you in CE | Halo | PAGE | https://www.halopedia.org/Motion_tracker |
| Default respawn 10 to 12 s; wave respawn within 6 to 12 s; group respawn for deaths within 5 s | Overwatch 2 | PAGE / SNIP | https://overwatch.blizzard.com/en-us/news/24122265 |
| Slayer respawn 5 s (MCC custom default) | Halo | SNIP | https://www.halopedia.org/Custom_Games |
| Q3 respawn on fire; g_forcerespawn 20 s | Quake 3 | SRC | https://github.com/id-Software/Quake-III-Arena/blob/master/code/game/g_main.c |
| Hit marker duration, killcam length, damage indicator timing in any title | | UNSOURCED | |

The gunfeel plan already sets ours from Quake 3 sources: 120 ms marker with a
40 ms audio tick, 250 ms on kill, 20 to 30 ms muzzle flash, kick in 100 ms and
out 400 ms, screen shake rotation only and under 2 deg.

### Proposed targets

- **Hit confirmation latency.** Marker and sound on the first render frame
  after the authoritative hit event arrives (one frame at 60 fps = 17 ms after
  receipt). Locally predicted cosmetic impact (sparks, decal) on the shooter's
  frame; damage numbers or marker only on server truth (authority rule).
- **Kill confirmation distinct by ear alone.** A blind listener separates hit,
  headshot, kill and self-hurt sounds 95 percent of the time.
- **Damage direction.** Indicator within one frame of the damage event, error
  under 15 deg to the true source, readable without colour.
- **Silhouette and contrast.** Fighters vs local background luminance contrast
  at or above 3:1 (WCAG non-text contrast as a borrowed floor, an assumption,
  not a game standard) on 90 percent of capture samples at 10 to 40 m; faction
  identity (Union black and red, free personal colours) recognizable in a
  silhouette-only test at 40 m for at least 9 of 10 viewers.
- **Back in the fight.** FFA respawn 4 s, team 3 s (current) are well inside
  Halo 5 s and far under Overwatch 10 to 12 s; keep. New metric: time from
  respawn to first damage dealt or taken, median 6 to 15 s in FFA. Under 5 s
  means spawn camping; over 20 s means a walk.
- **Death recap.** Killer name, weapon and remaining HP of the killer shown
  within 300 ms of death, held for the respawn wait.
- **No tilted text** (house rule) checked in every capture.

### How to measure

- Auto: client harness that injects a hit event and asserts the marker node is
  visible on the next frame; capture scan computing luminance contrast of the
  fighter mask vs a dilated background ring (needs a fighter mask render pass in
  the QA tour); harness metric `respawn_to_contact_s` added beside
  `spawn_deaths_per_spawn`.
- Human: silhouette card test from QA tour stills; blind audio identification.

---

## 5. Map design

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| T about 20 s to each site vs CT about 10 s; CT rotation about 15 s; Dust2 CTs set up in 7 to 8 s, contest about 10 s | CS (community mappers) | SNIP | https://www.mapcore.org/topic/17880-de_summer-wip/ |
| Johnston moved de_dust CT spawn about 2 s closer so CTs reached the hallway 2 s earlier; tuned "when each team would meet in the middle" | CS | SNIP | https://www.bit-tech.net/news/gaming/de_dust_creation/1/ |
| Dust2: arches make chokes between objectives and block lines of sight; B site has only a couple of entrances; "a figure-of-eight that had grown a pair of arms and legs" | CS | PAGE | https://www.johnsto.co.uk/design/making-dust2 |
| More CT than T pathways per site (Mirage 3 vs 2); Nuke CT about 62 percent; pathway count as a balance knob | CS | PAGE | https://www.gamedeveloper.com/design/a-cs-go-level-design-concept-the-pathways |
| Pick a player bucket (4 to 8, 8 to 12, 12 to 16) and 1 to 2 gametypes first; decide vehicles early; hard points need 3+ entrances; landmark visible from anywhere; flow "fun to run around on even without combat"; power weapon not on its ideal ledge | Halo (Carney) | PAGE | https://www.jmeiners.com/shamans/papers/art/bungie_map_design.pdf |
| Spawn: sort by distance from your own death point, pick random among furthest half | Quake 3 | SRC | https://github.com/id-Software/Quake-III-Arena/blob/master/code/game/g_client.c |
| Spawn weights: base 1000, nearby enemy in last 7 s about -500, ally +500, death -700 recovering 100/s | Halo 3 (fan lab) | PAGE | https://halo.bungie.org/misc/fyrewulff_spawnsystem |
| "3 second rule": never shot or able to shoot within 3 s of spawning, but no "running miles" back | CoD BO2 | PAGE (report) | https://mp1st.com/news/treyarch-game-design-director-details-black-ops-2-spawn-system-and-the-3-second-rule |
| 3 to 4 chokepoints, one per lane, not all coverable from one point; aim for 50 percent win rate; first tuning pass double or halve; PvP err on less cover | Level Design Book | PAGE | https://book.leveldesignbook.com/process/combat/balance |
| Quake rooms 256 / 512 / 1024 u; hallways 128 u+; step 18 u; running jump 244 u | Quake | PAGE | https://book.leveldesignbook.com/process/blockout/metrics/quake |
| TF2 ranges: close 256 u, medium 1024, long 2048 | TF2 (community) | PAGE | https://book.leveldesignbook.com/process/blockout/metrics |
| Conquest maps 5 to 7 flags | Battlefield V | PAGE (report of dev) | https://mp1st.com/news/all-battlefield-5-conquest-maps-to-have-5-7-flags-heres-what-50-rounds-of-cq-player-movement-looks-like |
| Shorten base-to-flag travel; cut 360 deg exposure; 64 players better than 128 | BF2042 | PAGE | https://mp1st.com/news/battlefield-2042-core-feedback-for-maps-discussed-by-dice-oultines-some-of-the-changes-incoming |
| At most 2 objectives per sector; early travel times "too great" | BF6 Wake Island | PAGE | https://www.ea.com/games/battlefield/battlefield-6/news/wake-island-developer-map-guide |
| Dust2 developer timings, Q3DM17 and Blood Gulch dimensions, BF1942 flag spacing, UT size per player count, a published "contact in 10 to 20 s" rule | | UNSOURCED | |

### fragr today

Prior synthesis: small map rule "corner to corner under 25 s"; Arena Duel 23
frags/min best, Gulch 6.4 and Tripoint 9 too slow; Sector 9 Mid Doors 5 s
contact. Harness reports `time_to_first_frag_s`, `spawn_deaths`,
`longest_gap_without_frag_s`, `pad_contest_index`, `stall_spots`.

### Proposed targets

- **Size per player count (Carney's buckets).** Declare each map's bucket.
  FFA 4 to 8: corner to corner 15 to 25 s at 6 m/s (90 to 150 m path).
  TDM and CTF 8 to 12: base to base 20 to 35 s. Conquest: base to nearest flag
  under 30 s on foot, under 15 s by vehicle (BF2042 travel lesson).
- **Sabotage timings (CS bomb lineage).** Attackers reach each site in 15 to
  25 s, defenders in 8 to 12 s (defender lead 6 to 12 s); site to site
  rotation for defenders 10 to 18 s; attackers more paths into the map,
  defenders more paths per site (3 vs 2 pattern). Round win rate per side 45
  to 55 percent over 200 seeded bot rounds at equal tier.
- **Contact.** FFA first frag of the match within 20 s (harness
  `time_to_first_frag_s`); median respawn to contact 6 to 15 s; longest gap
  without a frag under 30 s at 6+ fighters.
- **Spawn safety.** Spawn deaths within 3 s under 2 percent of spawns
  (CoD's never, with a tolerance for 20 Hz and bots); no spawn point in direct
  LOS of an active enemy at spawn time.
- **Chokepoints and hard points.** 3 to 4 lanes or chokes per team map; every
  objective and power item has 3+ entrances (Carney) and no single point sees
  all of them (LDB).
- **Sightlines matched to weapons.** Longest unbroken sightline on a map at or
  under the Rail's design band only where a Rail pad exists; elsewhere under
  40 m. Sightline histogram per map compared with weapon bands.
- **Landmark.** One landmark visible from at least 60 percent of walkable
  area (Carney's "visible from anywhere", made checkable).
- **Conquest.** 3 to 5 sites for 8 to 16 players (BF V's 5 to 7 is for 64);
  no more than 2 contested at once for small counts.

Measured (wave 21, `fragr-playtest --map-timing`, `server/src/maps/timing.rs`):
Sector 9 attackers 14.9 / 16.3 s to A / B, defenders 5.9 / 6.2 s, rotation
9.0 s; Low Water attackers 11.0 / 10.9 s, defenders 4.6 s, rotation 7.5 s;
corner to corner from 17.0 s (Larak Lot) to 108.7 s (Holdfast Atoll). Both
Sabotage maps are fast for the defence against these bands.

### How to measure

- Auto: a navmesh timing tool (`navigation.rs` already exists) that prints
  spawn-to-site and site-to-site seconds at the frozen top speed for each
  map, gated in a test; LOS sampling for sightline histograms and landmark
  visibility share from a grid of eye points; harness metrics above.
- Human: callouts learned (a new player names a zone after one session);
  "does it feel like a place".

---

## 6. Match structure and pacing

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Round 1.92 min (115 s), freeze 15 s, buy 20 s, max 24 rounds | CS2 competitive cfg | SRC | https://github.com/SteamTracking/GameTracking-CS2/blob/master/game/csgo/cfg/gamemode_competitive.cfg |
| MR12, first to 13, 6 round overtime | CS2 | PAGE | https://dust2.us/news/39261/valve-officially-confirms-mr12-and-overtime-in-competitive-play |
| C4 40 s; defuse 10 s, 5 s with kit | CS2 | SNIP | https://csdb.gg/guides/how-to-defuse-cs2/ |
| Loss bonus 1400 to 3400 in 500 steps; win 3250 (3500 by bomb); plant 800 to team; cap 16000 | CS2 | SNIP | https://csdb.gg/economy-guide |
| Round 100 s, spike 45 s, defuse 7 s with 3.5 s checkpoint, first to 13 | Valorant | SNIP | https://turbosmurfs.gg/article/how-long-is-a-valorant-game |
| Team Slayer 50 kills, 12 min cap (H3 ranked), 4v4 | Halo | SNIP | https://halo.fandom.com/wiki/Team_Slayer_(playlist) |
| Holding most flags drains enemy tickets; per map tickets and loss per minute | BF1942 | PAGE (shipped con docs) | https://www.realtimerendering.com/erich/bf1942/mdt/MDTDOC/Confiles/Conquest.con.htm |
| DM 25 frags, CTF 3 caps, 20 min (UT99 DM 30) | UT2004 | SNIP | https://www.gamehostbros.com/guides/games/unreal-tournament-2004/goal-score |
| Duel 10 min; fraglimit 20 default | Quake Live / Q3 | SNIP | https://giantbomb.com/wiki/Games/Quake_Live |
| "maybe 30 seconds of fun that happened over and over"; a 3 s loop inside a 30 s loop inside a 3 min loop that is always different | Halo (Griesemer) | PAGE | https://www.engadget.com/2011-07-14-half-minute-halo-an-interview-with-jaime-griesemer.html |
| Episode Two average session 27 min | Valve | PAGE (blog of Valve page) | https://www.jesperjuul.net/ludologist/2007/11/16/half-life-2-episode-two-stats/ |
| BF1942 / BF2 default ticket counts, CoD and BF respawn waves, session length statistics | | UNSOURCED | |

### Proposed targets

- **Three nested loops, measured.** 3 s: an exchange (shot, dodge, hit) at
  least every 3 to 5 s while a fighter is engaged. 30 s: each fighter is in a
  fight or on an objective errand in at least 70 percent of 30 s windows
  (harness `idle_ratio` under 0.3). 3 min: each match has at least one state
  change a spectator can name (lead change, power item taken, flag swing).
- **Match lengths.** FFA 3 to 6 min (current 3); TDM 6 to 10 min; CTF 10 min,
  3 caps (UT); Sabotage rounds 90 to 120 s with a 35 to 45 s charge clock
  (fragr 35 s; CS 40, Valorant 45), match 15 to 25 min (Valorant and CS2 are
  30 to 45 min; fragr's population and session length argue shorter);
  Conquest 10 to 15 min.
- **Lead changes.** FFA lead changes 3+ per match (prior synthesis; harness
  `lead_changes_per_match` exists).
- **Comebacks.** In Sabotage, a side down 0 to 3 wins the next round 25 to 35
  percent of the time (CS loss bonus outcome; unsourced as a CS statistic,
  proposed); no half ends 5 to 0 in more than 15 percent of seeded bot halves.
- **Ties.** Zero drawn matches without a sudden death phase (house rule from A5).
- **Between matches.** Result to next match countdown 15 to 30 s; podium
  readable in under 5 s.

### How to measure

Auto: harness already reports `round_seconds`, `lead_changes`, `idle_ratio`,
`frags_per_minute`, sabotage round lists; add an "exchange gap" quantile and a
30 s window engaged share. Human: "one more" asked unprompted.

---

## 7. Bots and AI

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Reaction s: Elite 0.05, Expert 0.20, VeryHard 0.30, Hard 0.40, Normal 0.60; attack delay 0.7 to 0.9 s on low tiers; aim focus cone 0.5 deg (Elite) to 20 deg (Easy) decaying per second | CS bots (Booth) | SRC | https://github.com/SteamTracking/GameTracking-CS2/blob/master/game/csgo/pak01_dir/botprofile.db |
| Believability needs "human limitations such as reaction times and attention prioritization" | CS bot GDC 2004 | PAGE (session) | https://gdcvault.com/play/1022878/The-Making-of-the-Official |
| Think 10 Hz; no fire until reaction time after first sighting or teleport; vision 900 + alertness x 4000 u, FOV 90 to 180 deg widening to 360 only when hurt or enemy firing; LOS traces | Quake 3 bot | SRC | https://github.com/id-Software/Quake-III-Arena/blob/master/code/game/ai_dmq3.c |
| Skill bands: circle strafe at attack skill 0.4+; linear lead at aim 0.4 to 0.8, exact over 0.8 | Quake 3 bot | PAGE | https://icculus.org/gtkradiant/documentation/bot_manual/chars.html |
| Skill 0 to 7; lead only at 4+; FOV about 91 deg Novice, 180 at 5, about 203 Godlike; aim error x (3.3 minus 0.4 x (skill plus accuracy)); acquisition window 0.5 + (7 minus skill) s with doubled error; worse 0.2 s after being hit | UT3 bots | SRC (UDK mirror) | https://github.com/TotemArts/Renegade-X/blob/master/Development/Src/UTGame/Classes/UTBot.uc |
| "No cheating" (vision, hearing, touch); 20 to 25 actors at about 15 percent CPU; breaking points (flee, berserk); tougher enemies rated "very intelligent" 43 vs 8 percent | Halo CE | PAGE | https://www.jmeiners.com/shamans/papers/ai/the_illusion_of_intelligence.pdf |
| About 50 behaviours at 30 Hz+; stimuli 1 to 2 s; avoid dithering "at all costs"; observer should guess state | Halo 2 | PAGE | https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai |
| 3 states, 4 squad behaviours; flanking emerges from cover; voiced intent with no mechanic behind it | F.E.A.R. | PAGE | https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf |
| Attack tokens; "deliberately miss when you're moving top speed" | DOOM 2016 | PAGE | https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016- |

### fragr today

`server/src/sim/bot_senses.rs`: 120 deg cone, 64 m sight range, cover and
vehicle hulls block, 200 to 400 ms reaction to a new sighting, aim error 0.055,
turn limit 0.1 rad per tick (about 115 deg/s), flinch on hit, hits reveal where
the shot came from, not where the shooter went; pads remembered with published
clocks. This is already in the honest band of every reference.

Wave 21 (#526): five rungs on these numbers (`server/src/sim/bot_skill.rs`,
Tourist to No Crumbs, Regular the default above), host-selectable, reaction
never under 150 ms. `fragr-playtest --bot-ladder`, two sets of 144 seeded Duels
per pair: each rung beats the one below 68 to 80 percent, win share against
Regular is monotonic, dithering 3.7 to 4.4 percent of moving windows. Tables
in `bot-and-enemy-ai-excellence-20261017.md`, wave 21.

### Proposed targets

- **Honesty (hard rules, already true; keep as tests).** No acquisition without
  LOS; hurt or heard fire may widen awareness but never reveals current
  position; reaction to a new sighting never under 150 ms for any tier (CS
  Expert 0.20 s; Elite 0.05 s is the "feels like a cheat" tier fragr should not
  ship).
- **Ladder.** 4 to 5 tiers on two or three knobs (reaction, aim error decay,
  lead prediction and movement choice), following UT and CS: low tiers do not
  lead and stand still to aim; high tiers lead and strafe. Each tier beats the
  tier below 65 to 80 percent of 1v1 duels in a seeded survey (monotonic, not
  a cliff).
- **Readable state.** A spectator can name what a bot is doing (Isla's rule):
  every bot intent change shows within 1 s as movement, a bark or a chip; no
  intent flip back within 1 s (anti-dither) more than 5 percent of the time.
- **Believable mistakes.** Miss more against a dodging or fast target (DOOM
  2016) and after being hit (UT3); measured as bot accuracy against moving
  targets at least 20 percent lower than against still ones.
- **Human beatability.** A median human beats the middle tier in FFA about 50
  percent of the time (Human; first stranger sessions).
- **Campaign enemies.** Telegraph every heavy attack 0.5 to 1 s before damage;
  attack tokens cap simultaneous attackers on the player (3 at normal is a
  proposed start, unsourced).

### How to measure

Auto: `bot_survey.rs` tier ladder with win matrices; intent change log for
dither rate; accuracy split by target speed. Human: "felt fair", "felt dumb",
named rival.

---

## 8. Audio and presentation

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Console -24 LKFS integrated plus or minus 2; portable -18; true peak at or below -1 dBTP; ITU-R BS.1770-3 | Sony ASWG-R001 | PAGE | https://www.gameaudiopodcast.com/ASWG-R001.pdf |
| HDR audio: sounds prioritized by loudness as importance; moving window culls quieter sounds | DICE Frostbite | PAGE | https://www.slideshare.net/slideshow/adaptive-mixing-in-frostbite/3128152 |
| HDR practice: only loudest transients move the window | Wwise | PAGE | https://www.gamedeveloper.com/audio/hdr-audio-in-wwise-best-practices-so-far- |
| Pillars: clean mix, pinpoint accuracy (occlusion, distance, 3D), gameplay information in sound, descriptive voice lines | Overwatch GDC 2016 | SNIP | https://pcgamesn.com/overwatch/overwatch-devs-on-creating-a-game-you-can-play-by-sound-and-announcing-dolby-atmos-support |
| Jump landings as audible as footsteps; grenade bounce range cut | CS2 Nov 2023 | SNIP | https://dust2.us/news/41336/cs2-11-9-update-new-wave-of-fixes-for-sub-tick-and-audio-issues |
| Footstep presence over exact distance; distance hard to judge | Valorant | SNIP | https://www.nme.com/news/riot-games-addresses-criticism-of-in-game-sound-in-valorant-2739939 |
| 30 fps on i3-540 and Intel HD 4000; 60 fps on GT 730; 144 fps on GTX 1050 Ti | Valorant | PAGE | https://support.riotgames.com/valorant/support-tools/minimum-recommended-pc-specs |
| Combat dialogue 57 events, 166 types, 5147 lines; nearby characters reply | Halo CE | PAGE | https://www.jmeiners.com/shamans/papers/ai/the_illusion_of_intelligence.pdf |
| Footstep ranges in metres (CS 1100 u claim, Valorant 50 / 15 / 12 m claim), announcer line lists, Doom 2016 dynamic music mechanism | | UNSOURCED | |

### Proposed targets

- **Loudness.** Gameplay and menu captures at -23 to -18 LUFS integrated
  (desktop PC sits between console -24 and portable -18; unsourced as a PC
  standard), true peak at or below -1 dBTP, loudness range checked so a quiet
  footstep is still above the noise floor at default volume.
- **Priority stack.** Fixed order, louder first: own hits and kill confirm,
  incoming damage, announcer (Host), enemy weapon fire, enemy footsteps,
  own footsteps, ambience, radio and music. A test asserts the ducking table.
  Radio stays small (house rule) and always ducks under combat.
- **Footsteps.** Enemy running steps audible to 20 to 30 m, crouched or walking
  silent or under 5 m; landings as audible as steps (CS2 lesson); occlusion
  through solids reduces level 6 to 12 dB (proposed, unsourced).
- **Weapon identity.** Each weapon identifiable by sound alone by 9 of 10
  listeners; enemy and own versions of the same weapon distinct.
- **Announcer.** Rarity budget (prior synthesis: one line per 6 s, top tier
  under 1 in 50 matches); harness `host_beats_per_minute` exists.
- **Performance on modest hardware.** 60 fps 1 percent low at 1080p on a
  reference integrated GPU (the Valorant 30/60/144 ladder is the pattern);
  30 fps floor on the minimum declared spec; server 16 fighters plus 8
  watchers at under 25 percent of tick budget p99 on one core.

### How to measure

Auto: `ffmpeg -af ebur128` on QA tour recorded audio (no new runtime needed;
ffmpeg is a tool, not a scripting runtime, but confirm it fits the language
rule before adding to CI); attenuation curve unit test per sound class; frame
stats on benchmark scenes. Human: blind weapon and direction identification,
"is the Host funny".

---

## 9. Campaign craft

### Reference values

| Value | Game | Tag | Source |
|---|---|---|---|
| Par times E1: 30, 75, 120, 90, 165, 180, 180, 30 s (E1M9 165); Doom II MAP01 to 32 from 30 to 420 s | Doom | SRC | https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/g_game.c |
| Romero pars: fastest play plus about 30 s | Doom | SNIP | https://doomwiki.org/wiki/John_Romero |
| Romero rules: height change with every floor texture change, contrast light and dark, cramped and open | Doom | SNIP | https://doomwiki.org/wiki/Tips_for_creating_good_WADs |
| 15 minutes of rough gameplay, playtest, reprioritize weekly, 1 to 2 week increments; "done as soon as playtesting was no longer painful to watch"; no hints in playtests | Half-Life 2 | PAGE | https://cdn.fastly.steamstatic.com/apps/valve/2006/GDC2006_HL2DesignProcess.pdf |
| Playtests are experiments; death heatmaps, level times, 1 to 7 difficulty surveys | Valve 2009 | PAGE | https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf |
| Episode Two average completion 6 h 11 m, session 27 min | Valve | PAGE (report) | https://www.jesperjuul.net/ludologist/2007/11/16/half-life-2-episode-two-stats/ |
| 3 s / 30 s / 3 min loops; no dynamic difficulty; AI backs off when shields drop | Halo CE | PAGE | https://www.engadget.com/2011-07-14-half-minute-halo-an-interview-with-jaime-griesemer.html |
| game_save waits until safe (not in combat, not falling), gives up after about 10 s; "checkpoints should be placed regularly" | Halo 3 | PAGE | https://learn.microsoft.com/en-us/halo-master-chief-collection/h3/individual/haloscriptoverview |
| Enemy types per encounter: 1 tutorial or rest, 2 regular, 3 complex, 4 brawl, 5+ chaotic; telegraph 2 to 3 s for standalone attacks (GoW example) | Level Design Book | PAGE | https://book.leveldesignbook.com/process/combat/encounter |
| Action blocks: weekly gameplay vignettes, over 100 made | Titanfall 2 | SNIP | https://gdcvault.com/play/1025105/Designing-Unforgettable-Titanfall-Single-Player |
| Push forward combat: no regen, no cover; take what you need from enemies; glory kills drop health | DOOM 2016 | PAGE | https://gdcvault.com/play/1024940/Embracing-Push-Forward-Combat-in |
| Doom monster introduction cadence, HL2 "new mechanic every N minutes", Titanfall 2 "one mechanic per level" as dev rule, publisher death-rate or checkpoint targets | | UNSOURCED | |

### fragr today

`docs/CAMPAIGN.md` owns the contract: twenty levels, five episodes, about four
hours (so about 12 min per level average), limited continues refilled per
episode. The playtest harness runs a seeded `--campaign-survey`.

### Proposed targets

- **Level length.** 8 to 15 min for a first clear at normal (240 min over 20),
  speed clear at or under 40 percent of that (Doom pars run 30 s to 3 min for a
  speedrunner; fragr's encounter density is higher). Record an authored par
  like Romero's: author's fast clear plus 30 s, shown at results.
- **Checkpoint gap.** No more than 3 min of play between saves on a first
  clear, saves only in safe states (Halo's rule) with a 10 s timeout fallback.
- **Encounter variety.** At most 3 enemy types per encounter except a marked
  brawl; each episode introduces at least one new enemy or verb and teaches it
  first in an encounter with 1 type (LDB tutorial pattern), with no text
  instruction required (Valve: no hints).
- **Telegraph.** Every damaging enemy attack over 25 damage telegraphed 0.5 to
  1 s ahead by pose and sound.
- **Difficulty curve.** Per level, median deaths per first clear at normal 0.5
  to 3 (proposed; unsourced as an industry number); no single encounter
  above 40 percent of a level's deaths unless it is a boss.
- **Loops.** Halo's 30 s: in campaign survey traces, time between combat
  starts or meaningful set pieces under 90 s for 80 percent of the level.
- **Process.** Valve's bar: a fresh player playthrough that is "no longer
  painful to watch", no hints given.

### How to measure

Auto: campaign survey reports level time, deaths by encounter and checkpoint
gaps (extend the report if absent), enemy type count per encounter from
`maps/authored/encounters.rs`. Human: fresh player sessions with think aloud,
death heatmaps, 1 to 7 difficulty surveys per level.

---

## 10. Stability and polish signals

### Reference values

| Value | Source | Tag |
|---|---|---|
| Valorant 2.34 ms per game frame budget; 1.5 ms single instance, about 5.7 ms with 168 instances on 36 cores | https://www.riotgames.com/en/news/valorants-128-tick-servers | PAGE |
| Riot: unbounded rewind lets a 500 ms player "kill you a half second after you'd moved behind cover" | https://www.riotgames.com/en/news/peeking-valorants-netcode | PAGE |
| Crash-free sessions: 99.9 percent called outdated, top quartile 99.99 percent (mobile apps, vendor report) | https://www.instabug.com/mobile-app-stability-outlook-2023 | SNIP |
| Riot or Bungie published crash-free rates; desync measurement standards | | UNSOURCED |

### Proposed targets

- **Crash free.** 99.9 percent of client sessions end without a crash or script
  error (desktop has no industry number; mobile 99.9 is a floor). Measured
  locally: zero script errors in every `godot_check.sh` harness (already a
  rule), plus an opt-in local crash log count in release sessions.
- **Server.** Zero over-budget ticks and zero skipped periods in the 120 s
  soak (exists); RSS growth under 5 percent over a 30 min soak; tick p99 under
  12.5 ms at 16 fighters plus 8 watchers (25 percent of budget, leaving room
  for UDP or more fighters).
- **Desync.** Prediction corrections: reconcile snaps over 0.25 m in under
  1 percent of local ticks at 50 ms RTT with 10 ms jitter; zero mirror golden
  mismatches.
- **Fair play basics.** Server authority over every outcome (house law);
  input sanity (rate, view tick claims, speed) rejected at the boundary; no
  client field ever widens rewind past 200 ms; no hidden information sent to a
  client that a fair client should not see (enemy positions behind solid walls
  beyond a small margin) as a stretch goal for 1.0.
- **Reconnect.** Resume within 10 s after a 3 s outage without losing the seat.

### How to measure

Auto: soak and bench (exist), netem probe in the playtest harness, golden
mirror tests, a snapshot audit that counts enemies sent while fully occluded.
Human: none; this dimension should be fully automatic.

---

## 11. What genuinely needs human judgement

These cannot be gated by a headless check, only informed by one:

1. Does movement feel good (weight, crispness) at the frozen constants.
2. Is each weapon satisfying (sound, kick, impact), not just balanced.
3. Silhouette and faction readability in real lighting, and whether the art
   reads as one world (canon, art bible).
4. Whether the Host and barks are funny and rare enough.
5. Whether a map feels like a place and its callouts stick.
6. Whether bots feel fair, dumb or cheating, and whether a human names a rival.
7. Campaign teaching without text: did a fresh player understand the new verb.
8. Whether a death felt deserved (the recap answers "why", the human answers
   "fair").
9. "One more": asked unprompted at the end of a session.

The prior synthesis's closing rule holds: if the numbers move and the human
signals do not, the numbers were wrong.

---

## 12. Gaps and suggested next research

- Battle(non)sense per-game network delay tables (videos, not text): needed to
  compare fragr's 20 Hz plus 100 ms buffer to Apex and Fortnite measured.
- Booth's CS bot GDC 2004 slides (not retrievable), Aldridge's Halo Reach
  networking talk and Ford's Overwatch GDC 2017 talk numbers (GDC Vault video).
- Dust2 timings: measure them in a CS2 local server with a stopwatch rather
  than relying on forum numbers.
- Overwatch and Valorant footstep ranges from a primary source.
- Any publisher campaign death-rate or checkpoint interval targets (Microsoft
  Games User Research on Halo 3 is the likeliest; the Wired article is gone).
