# fragr roadmap

The order of operations that takes fragr from a playable development build to an exceptional game people play, watch and host. This file is the plan of record for sequencing. Feel and non-negotiables live in [`VISION.md`](./VISION.md). Bounded work lives in issues, PR descriptions and, for multi-PR efforts, [`plans/`](./plans/README.md). Implementation truth is source, tests and CI. The dated narrative and receipts through 2026-10-23 are in [the roadmap history](history/ROADMAP-2026-10.md).

Every item is **planned**, **in progress**, **shipped** (merged to `main`) or **proven** (shipped and demonstrated by a test, an inspected capture or a real session). Do not promote an item without the evidence.

## The shape of the plan

1. **Make it excellent locally.** Solo play, agents through the adapter, and small multiplayer on one machine or a LAN. Zero spend. Depth before breadth: one slice that looks, sounds and plays well sets the bar everything else is built to.
2. **Prove it with people early.** Nick and friends on a LAN, then small rounds of fresh players, before the content is finished, so people steer what gets built.
3. **Expose it.** A hardened server on a spare home machine or a small VM where strangers and their agents join and it does not fall over. Home is a complete host, not a lesser path.
4. **Finish it to the 1.0 bar.** Every shipped level, map, sound and piece of art at the golden-slice bar, release candidates, then 1.0 only when [every gate](#the-10-bar) is proven.
5. **Grow it after 1.0.** Deployed hosting once spend is approved ([server excellence plan](plans/server-excellence.md)), bigger nights and a bigger world, per [Beyond 1.0](#beyond-10).

Scale grows with evidence: small squads (four to twelve fighters) for 1.0, then full servers (thirty-two to sixty-four) and large agent-heavy arenas after it. No rung is claimed until measured.

<a id="now-in-development"></a>

## Where we are (2026-10-31)

- **Release.** v0.97.0 is the development release checkpoint for wave 20 (weapon balance, hunting bots and jeep drivers, the Level 18 square, Voss captured in play, Latch through Episode IV, and the shared-mesh fix), following v0.96.0 for wave 19. The [release page](https://github.com/blisspixel/fragr/releases/latest) records published packages, checksums and package validation. Windows human play, real controllers, fresh-player acceptance and listening to the campaign score remain separate unproven evidence.
- **Campaign.** Levels 1 to 20 are connected development missions with mission-entry saves (one current save schema, no migration), finite ammunition and three continues per episode; surviving Level 20 records the campaign's survival, which opens the Still Here epilogue (capability 57) from the menu, and a run exhausted in levels 18 to 20 gets its own ending and credits. Level 1, Recall Notice, is dressed as the golden slice (#461). Level 19, Planned Works (#465), adds the jetpack and the Paver; Level 20, Local Exception (#466), adds the Surveyor; both machines carry final Inheritance models from wave 11. Art, pacing and fresh-player review are open on every level.
- **Multiplayer.** Larak Lot, the hero free-for-all map, holds map 1 (#464). Every free-for-all life starts on the Pistol and Fists with guns on timed pads and a 4 s respawn (#467); fighters move at 6 m/s with a ground dodge (#463) and rocket-jump (#431); the Custody Plate is the lot's power item and Duel runs on it, with a fire-to-rematch podium (#431, wave 3); bots see before they fight (#468); the Host speaks rarely (#462). Team deathmatch, capture the flag, 5v5 Sabotage and vehicle Conquest on Holdfast Atoll remain, hosted from the menu or a dedicated server, with bot fill and agents on the same wire.
- **Honest assessment.** Nick's first Windows session on v0.90.0 filed #433 to #442. Waves 1 (#457) and 2 (#471) of the [October 23 round](plans/playtest-round-20261023.md) answer them and add the slice above, and wave 3 deepens it, with Linux evidence only: headless and Rust suites, coverage, playtest smokes and a rendered tour inspected on one Linux host. Windows human play, real pads and a fresh-player pass remain open evidence for the finished game. v0.92.0 packages passed automated install checks. Nick requested a development release after waves 4 and 5 on 2026-10-25.
- **Is it fun yet? Not proven, and not yet the bar.** The goal is the loop that made Counter-Strike, Battlefield 1942 and GoldenEye: a match so good the player wants another one immediately. Most of the parts that the October 23 study of Doom, Quake, Unreal Tournament, Counter-Strike, Battlefield and Halo found missing now exist: equal starts with power on timed pads, dropped guns, dodge and rocket jumps, a voiced Host for rare moments, Duel rematches and sudden death instead of draws. Wave 19 added the between-match pull (nemesis and rivals on the podium, a map vote into the next match), watching a teammate after death, a Sabotage comeback ladder and rebuilt Compliance Yard and Low Water; wave 20 balances the guns and teaches bots to hunt. What still stops "one more game": Larak Lot remains the only map built to the full bar, and no one but Nick has played. Every fun number so far comes from bots.

<a id="full-build-order"></a>
<a id="full-build-order-2026-09-27"></a>
<a id="full-build-order-updated-2026-10-04"></a>

## Full build order

This is the only active sequence. When the current rung changes, edit this section. Do not add a second list.

1. **October 23 playtest round, shipped with Linux evidence.** The [round plan](plans/playtest-round-20261023.md) ran in waves, each returning to one reviewed, green `main`. Wave 1 (#457) fixed the death lifecycle (#441), HUD layout and upright results (#437), menu focus and structure (#435, #436), reload readability (#440) and operator console output (#438), and added stutter traces (#434), the music review tool and asset-tool ceilings. Wave 2 (#471) added benchmark UX (#439), the console pad layout, radio dial and announcer setting (#442), the Pistol and Fists FFA start with a 4 s respawn, the feel pass, bot senses, the rare Host spine, one save schema, the faction readability contract and the bot roster. Owed: Windows human play and real pads. v0.92.0 packages passed automated install checks.
2. **Golden slice and hero map, implemented, evaluation continuing.** [Larak Lot](plans/larak-lot.md), a five-level car park, replaced Arena Duel on map 1 (#464), and Recall Notice is dressed as the Level 1 golden slice (#461). Both were judged from inspected Linux stills and motion; continue rendered inspection and constrained play now, while keeping physical-device and fresh-player evidence open. This slice is the quality bar for everything after it.
3. **Episode V to that bar, acceptance continuing.** [Planned Works](campaign/l19-planned-works.md) (Level 19, #465) and [Local Exception](campaign/l20-local-exception.md) (Level 20, #466) are connected development levels with Inheritance Paver and Surveyor models (wave 11, rendered review only; Nick's model pick stays open). The conditional [epilogue](campaign/epilogue-still-here.md), Still Here, and its exhaustion ending have technical boundary and replay coverage. Voice, ambience, page stills and fresh-player timing remain open alongside broader Episode V route evaluation.
4. **Raise the campaign to the bar, continuing.** Revisit levels 1 to 18 for layout, art, pacing, encounter readability and fresh-player review. Waves 13 to 17 dressed Levels 2 to 13; wave 18 rebuilt layouts where dressing could not help (Levels 9, 13 and 17) and gives the cast their own colours. Unfinished acceptance above stays explicit while local engineering progresses.
5. **One more game, implemented in waves 19 and 20.** Make the multiplayer match loop the thing people come back for, and make the story hold together. See [Wave 19](#wave-19-one-more-game) below. This continues [multiplayer excellence](plans/multiplayer-excellence-20261017.md) (#431) and [bot and enemy AI](plans/bot-and-enemy-ai-excellence-20261017.md) (#432).
6. **Close the largest craft gaps (wave 21, next), then first human evidence.** See [Wave 21](#wave-21-craft-gaps). Then Nick plays a LAN night with a friend, bots and an agent on the current build, then a small fresh-player round (proposed: five people who have never seen fragr) plays the campaign opening and a multiplayer session. What they do and say steers the next waves. People validate the measured gates early and find what the numbers miss.
7. **Network depth and the exposed server.** Validate the implemented prediction and bounded lag compensation in a two-machine LAN session with humans, rule bots and an agent. Measure WebSocket capacity before any UDP spike, per [TRANSPORT.md](TRANSPORT.md), then run a public week with strangers. #434's remaining field and transport evidence belongs here.
8. **Content complete to the bar.** Every campaign level, the epilogue and every multiplayer map that ships enabled by default meet the golden-slice bar; every weapon, fighter, surface and HUD element is final; the score, Host, barks and radio are picked by ear; nothing placeholder remains. Maps not yet at the bar may ship switched off.
9. **Release candidates.** Versions 0.99.x: a full audit against [the 1.0 bar](#the-10-bar), a larger fresh-player round, clean-machine installs by people on Windows, macOS and Linux, the twenty-four hour soak and the public week. Fix what they find; do not add features.
10. **1.0.** Tag 1.0 only when every gate in the 1.0 bar is proven with the evidence it names. Cloud apply stays plan-only until the public week is real and spend is approved.

<a id="next-steps"></a>

### Wave 18: layout, presentation and score, implemented

Too many spaces still read as rectangular rooms joined by straight connectors.
Wave 18 rebuilt three levels where dressing could not fix the layout, using the
[layout review](MAP-DESIGN.md#layout-variety-and-current-gaps). Every new route
is authored on the server, and tests show it skips no required story fact.
Evidence is native tests, scripted routes and inspected Linux captures; no
fresh player has tried these routes.

| Lane | Result | Still open |
|---|---|---|
| Level 9 | The office stands on piers so one aisle frames the ship from arrival; an outer gantry and a hull-side lane reach the first gantry; a bow crossing joins them | The ship is a glimpse at arrival, not a full reveal; the hatch capture route keeps the timing race it has on `main`; the hatch bridge and boarding floor share a 40 m² floor face |
| Level 13 | The foundry is composed around its maintenance loop: a closed roof, a service corridor flank, a walled stair onto the gallery, machines whose collision matches their shape, dark works lit by amber process light, a casting line and crane | Lathes still read as boxes from some angles; the hall is murky away from process light; the map is at its navigation build budget |
| Level 17 | Raised command galleries over a working floor, an exposed and a sheltered stair, the outer service stair and a shorter opened return, dressed as an occupied Union institution in grey stone, dark steel and red | The approach, hall, ring and chamber have the palette but no furniture; the gallery fight capture route passes 3 of 5 runs |
| Characters | Splice ochre, Tern gunmetal, Renn in a dark coat, Level 8's four held people distinct; no credits spent | Renn's own model waits for the Meshy refresh; Nick accepts Splice and Tern; Latch waits for #455 |
| Presentation | A Blood setting, On by default; the multiplayer death camera no longer flies into walls and ceilings; Screen Flashes now reaches the HUD | Live-play viewing of the death camera |
| Campaign score | An optional ambient bed for every campaign map and six story cues, A and B takes each, switchable per level in the pause menu; the radio replaces the score when tuned | Nick auditions all 27 slots in play; unpicked takes are then removed |
| Shared | A fire press is latched on the server like every other press, so a quick click between ticks fires exactly once; the capture tour's Rail route stays off the Toll stair edge (#506) | |

<a id="wave-19-one-more-game"></a>

### Wave 19: one more game, implemented

The test for every lane: after a match, does the player want another one right
away? Evidence is bots-only surveys, native tests and inspected Linux captures;
no human has played any of it.

| Lane | Result | Still open |
|---|---|---|
| Between-match hook (#509) | The podium names your nemesis and rivals this session; a three-map vote counts into the next match; hosts switch each map in or out of rotation, every map on by default | Human couch play; personal bests have no capture; the example brain abstains from the vote |
| Death as a seat (#510) | In team modes the dead follow a living teammate; a rare clutch stamp; a Sabotage resupply ladder took comebacks from 0 to 3 from 14% to 29% | 59% of short Sabotage matches now reach the extra pair |
| Map bug hunt (#511) | No body in a wall, out of bounds or wedged across 232 bot matches on all eight maps; a survey of every map in every mode; a walked route to every pad | Findings carried into wave 20: Rifle dominance, quiet Duels off Larak Lot, unused vehicles |
| Compliance Yard and Low Water (#512) | Compliance Yard rebuilt as nine rooms, crossing in 24.5 s with a 46 m longest line; Low Water's sites differentiated, the trench broken up, its own spawn table; both lit and dressed; Low Water joins the roster | Plain floors; Low Water Sabotage favours attackers (#520) |
| Story that lands (#513) | Level 18's turn happens in play and no longer announces the wipe; Latch, Sorrel, Kessel, Orrin and Mara set up before they matter; story pages and timeline fixed; the radio stays silent through a story moment | The Level 18 square's dressing and Voss's capture moved to wave 20 (#518) |

### Wave 20: balance, hunting bots and the campaign's middle, implemented

Bots-only surveys, native tests and inspected Linux captures; no human play.

| Lane | Result | Still open |
|---|---|---|
| Weapon balance (#516) | Pad supply rebalanced off Larak Lot: every free-for-all top gun at 42% or under across 24 seeds (the Rifle was 50 to 73% on five maps), no weapon stat changed, the Rocket 6 to 8% of frags where present | Team deathmatch stays 62 to 71% Rifle unless the fire rate changes (Nick's call); lead changes dipped on Directive 17 and Tripoint |
| Bots hunt (#517) | Bots judge pads by when they can take them, hear gunfire, explosions, pads and footsteps without wallhacks, patrol and glance; Duel fights on every map but Holdfast (Sector 9 from 0 to 1.2 frags a minute); Conquest bots drive Holdfast's jeeps | Holdfast Duel (whether Duel should refuse large maps is Nick's call); bots do not use boats or aircraft |
| Level 18 and Voss (#518) | Level 18's square dressed as Low Water's people rebuilding on a clear morning, its light and noise stopping at the turn; Voss taken alive in play at her rostrum, escorted by free people; Latch with the party in Levels 12, 13, 14 and 16, with the Level 13 lift and Level 16 doors waiting for Latch | Voss wears the generic human body; Latch does not react at the capture |
| Open levels (#519) | Level 9's shared floor split; Level 17 furnished throughout; Level 13's lathes read as machines; the berth crew's own figures; a shared-mesh bug that hid rods and cylinders (shipped on Level 9) fixed at its root; the Level 17 fight capture runs from a carried kit, 6 of 6 | The Level 13 hall is still murky away from process light |

The coordinator also freed CI runner disk after a test job ran out of space,
and set the [1.0 bar](#the-10-bar) and the order of work toward it.

<a id="wave-21-craft-gaps"></a>

### Wave 21: close the largest craft gaps (next)

The [1.0 bar](#the-10-bar)'s gates where fragr is furthest from the reference
shooters, each lane delivering both the change and the measurement that proves
it.

| Lane | Gates it closes |
|---|---|
| Hear the fight (#524) | Player footsteps and landings audible 20 to 30 m and placeable by direction, silent when walking; a limiter and a -23 to -18 LUFS mix with combat ducking music and radio; a loudness measurement on tour audio |
| Netcode and frame feel (#525) | Remote interpolation from 100 ms to 50 to 75 ms with jitter-driven widening; peeker's advantage and input-to-photon probes; movement goldens at 30, 60, 144 and 240 fps; a map ledge-height scan |
| Bots with a ladder (#526) | Four or five bot difficulty tiers proven by a win matrix; time from respawn to first contact, kill distance bands and a navmesh timing tool for crossings and Sabotage site and rotation times, which also drives #520 |
| Campaign checkpoints (#527) | Mid-level checkpoints no more than three minutes apart through the run-file seam; an encounter audit for enemy types per fight and teaching before testing |
| Readable deaths (#528) | A death recap within 300 ms, a contrast scan of fighters against backgrounds at 10 to 40 m, a colour-blind preset and the transient whiteout (#521) |

Wave 22 follows with fair play (each client receives only what its fighter
could perceive) and opt-in fun metrics (#529): match-level records on a host's
disk, announced at join and shredded after 67 days per the
[privacy policy](PRIVACY.md), reusing the survey metrics this wave adds so real
matches and bot surveys are measured the same way. It also brings a roster of
human and synthetic fighter looks for multiplayer (#530), a redesigned
spectator pad timer board (#532), a Counter-Strike-style split scoreboard with
objective stats and rivals for keyboard and controller (#536), and locational damage: head, torso and
legs, machine plating and faction weak points per the
[locational damage plan](plans/locational-damage.md) (#533). Benchmark and auto settings get
their own lane before 1.0: tiers from a 720p floor to great looks, an auto-tune
that targets the 1% low, and player and developer docs
([graphics auto-tune plan](plans/graphics-autotune.md)), built after the
November 3 model credit refresh, so a lobby is never a room of clones.

Close the multiplayer work with a measured fun night of bots and agents across
every map, then a human LAN night:

| Signal | Target |
|---|---|
| Frags per minute, every map in rotation | 10 or more |
| Lead changes per free-for-all match | 3 or more |
| Most-used gun's share of shots | Under 45% |
| Human signals | "One more", naming a rival, timing an item unprompted, quoting the Host |

If the numbers move and the people do not, trust the people.

### After these waves

- **Continue campaign acceptance.** Episode V remains open: broaden the earned
  M19 market/tanks prefix into the roof loop and later route, investigate supply
  discovery before tuning ammunition, and retain failure reports. Still Here
  needs human timing, voice, ambience and the [planned page stills](campaign/epilogue-still-here.md#owed-to-the-next-asset-round).
  Technical ending/replay checks do not establish pacing or finished art.
- **Network field evidence (#434).** Two-machine jitter/loss, the real Godot
  client on a shaped link and stage 6's transport comparison remain open.
  Loopback simulation does not close them. Profile before pursuing more byte
  savings in `shot_results`; no speculative transport rewrite.
- **Release acceptance.** Review the latest release on Windows with real controllers and
  fresh players. Its release notes separate Linux rendered evidence and
  automated package checks from human play. Keep later source changes and
  published packages distinct when the next engineering wave starts.

### Nick's review round

[#472](https://github.com/blisspixel/fragr/issues/472) owns choices and human
play, not an engineering dependency. Present each choice with current context,
side-by-side stills or playable audio, a recommendation and room for a note.
Callum is already the selected Host; listening acceptance remains open.

| Review | Decision or evidence still needed |
|---|---|
| Narrator, Host, Union barks and edited radio | Choose the Narrator voice; listen to the selected Callum Host and barks in context; choose radio keepers through the existing review tool |
| Rocket balance | Decide whether to change weapon or map balance against the measured shortfall in the [bot plan](plans/bot-and-enemy-ai-excellence-20261017.md#6-progress) |
| Campaign difficulty | Review the easier hesitant Recall Notice profile and minimum health on M02 entry/retry |
| Character and model art | Latch's palette and voice, character treatment, enemy v1/v2 picks including Paver/Surveyor alternates, Edda's lamp and Union seal C |
| Existing prop exceptions | Larak kiosk proportions and palette P10; foundry lathe place-colour choice P4; integrate other candidates only at a matching, verified location |
| Human play | Windows and real pads, Larak FFA and Duel, menus, Recall Notice, Persons Unknown and Sniper scope modes; two-human Duel hand-over; dedicated terminal in Windows Terminal and stutter traces if reproduced |

The existing local audition/model pages and `fragr-audiogen review` hold
candidates. A proposed combined review page is not yet delivered. Keep the
current treatment until a choice is made; record defects as bounded work.

### Implemented baseline and remaining acceptance

| Work | Implemented evidence and remaining boundary |
|---|---|
| Recovery and evaluation (#479 to #482) | Constrained Recall Notice survey; earned M01 save to M02 and retry with exact entry kit; Continue enqueue failure handling; M20 survival/exhaustion and read-only epilogue replay checks. Controller assumptions live in the [harness guide](../tools/playtest/README.md). Known routes and synthetic profiles are not fresh-player acceptance. |
| M19 slices (#486, #487, wave 11) | Earned street-to-market-to-tanks evaluation and a retained strip escape regression. Broader inherited campaign pacing remains open. |
| Waves 11 and 12 (#490, #495) | Paver/Surveyor models, dropped guns, Duel queue, host presets, Conquest feedback, voiced Host, hit confirm, Scatter sound, guard perception/squads and bot improvements. Released in v0.93.0. |
| Wave 13 (#500) | Recall Notice attack-token regression (#493), retry streams and fixture trust, slow-reader closure, snapshot deltas and Level 2 dressing. |
| Wave 14 (#501) | Levels 3, 4 and 6 dressing, Level 2 lighting, radio naming and bounded hitscan rewind. |
| Wave 15 (#503) | Levels 5 and 7 dressing, Heavy readability, radio edits, roster deltas/text encoding and deterministic fixture repair (#502). Radio listening remains open. |
| Wave 16 (#504) | Levels 8 to 10 dressing, red Turret/Heavy tells and cyan absorbed Heavies, wire rounding and simulated link evidence. Merged at `166c14d8`; all CI jobs passed. Human play and two-machine evidence remain open. |
| Wave 17 (v0.94.0) | Level 10's Repeater from finite pickup through fire and reload, Levels 11 to 13 dressed, the Assessor in black and red, mine prompts on active bindings. Spin cues, human weapon feel and Level 13 geometry remain open. |
| Multiplayer (#431) | Implemented through wave 12. Listening and two-human Duel hand-over remain open. |
| AI (#432) | Wave 13 fixed the deliberate-profile regression. Rocket balance and Latch voice remain open. |
| Networking (#434) | Stages 1 and 2 measured; stage 3 deferred with evidence; stages 4 and 5 implemented with loopback measurements in [BENCHMARK.md](BENCHMARK.md). Field validation and stage 6 remain open. |

Later work, after 1.0, is sorted into horizons in [Beyond 1.0](#beyond-10).

### Fun-compound lens (not a second build order)

Read the numbered rungs above through this lens. It does not replace them, and
it does not add a list to execute. The Full build order owns the rungs. The
[multiplayer order](plans/multiplayer-modes.md) owns mode sequence.

| Lens | What it asks | Owner |
|---|---|---|
| S0 Door | A scripted bot survives the first server ping. MCP `observe` and `round_state` return `content`. `--version` matches `/status`. `mcp --local` can spawn the loopback server. | Adapter and server, not a new rung |
| S1 Stranger Scrap | A stranger plays free-for-all on a friend host. | Full build order, multiplayer order's first seat |
| S2 Same seat | Duel, team deathmatch, and the mutators on that same host. | Those rungs |
| S3 Carry | Sabotage carry tuning only. No shop, no scrip, no credits. | Sabotage rung, tune only |
| S4 Four roles | Rivals, teammates, spectator sport, and a bring-your-own skill path. Compact observe and local MCP. Not a new brain. The LLM stays off the tick. | Agent door on the existing adapter |
| S5 Campaign | Episode I and the campaign spine as [CAMPAIGN.md](CAMPAIGN.md) already states. Do not reopen the spine. | Campaign rungs |
| S6 Friend host | Prove a friend host before UDP or cloud. | Hosting rungs |
| S7 After evidence | Wipe and big combined-arms only after S1 through S3 have stranger evidence. | Those later rungs |

Do not expand public dream modes before S1 through S3 have stranger evidence on Scrap, team modes, and Sabotage carry.

<a id="the-10-bar"></a>

## The 1.0 bar

The aspiration is a shooter that is fun as hell: the kind people play for
"one more" without being asked. That is what every gate below serves, but it is
not itself a gate. The gates are craft: properties that made Counter-Strike,
Battlefield 1942, Quake, Unreal Tournament, Halo and GoldenEye exceptionally
well made, each with a target and a repeatable measurement, researched with
sources in [fun craft targets](plans/fun-craft-targets.md). Until every gate is
met on the release build, releases stay at 0.x. Human play validates the gates
and finds what the numbers miss; it never replaces a measurement.

| Area | Gate | How it is measured | Today |
|---|---|---|---|
| **Responsiveness** | Local shot and movement on screen within 60 ms at 60 fps; simulation identical at 30, 60, 144 and 240 fps | Frame-stamped input probe; movement goldens replayed at varied frame times | Fire to resolved shot 41 ms on one machine; frame-rate independence unproven |
| **Netcode** | Remote players drawn 50 to 75 ms behind (100 ms today), widening only on measured jitter; peeker's advantage under 150 ms at 50 ms round trip; lag compensation never hits through present cover | Render-time probe; two clients with injected delay; rewind tests and shot audit | 100 ms interpolation; 200 ms rewind cap; no two-machine measurement |
| **Movement** | Stop in 100 to 150 ms and reach top speed in 100 to 200 ms; jump apex 1.0 to 1.2 m with no "maybe jumpable" ledges; one owned speed trick capped near 2.3x run speed | Tick-count golden tests; map ledge-height scan | Inside the bands except the ledge scan, which does not exist |
| **Fights** | Torso clean-hit time to kill 0.5 to 1.2 s; all-head kills take at least 0.4 s for every non-power gun (the Railgun's head one-shot is a deliberate signature); median kill time 0.8 to 1.5 s; no weapon above 45% of shots or kills in any mode; each weapon's median kill distance in its own band | Sticky TTK table; bot survey kill-time quantiles, shot and kill share, kill distances | Free-for-all top gun at 42% or under; team deathmatch Rifle 62 to 71%; kill distance bands unmeasured |
| **Power and pacing** | Power items on 90 to 120 s clocks, the Plate on 35 s; pad contest index above 15%; respawn 3 to 4 s; under 2% of spawns die within 3 s; 6 to 15 s from respawn to first contact | Bot survey pad, spawn and contact metrics | Clocks and respawn in band; time to contact not yet measured |
| **Feedback** | Hit marker and sound on the first frame after the server hit event; body, head and kill told apart by sound; a death recap within 300 ms | Client harness timeline; blind listening check | Tiered hit chime exists; no death recap |
| **Readability** | Every fighter at least 3:1 luminance contrast against its background from 10 to 40 m; faction readable in silhouette at 40 m; a colour-blind preset | Contrast scan of tour captures; silhouette review | Faction colour contract exists; no contrast scan |
| **Audio** | Running footsteps and landings audible 20 to 30 m away and silent when walking, direction within 45 degrees; mix at -23 to -18 LUFS with true peak at or below -1 dBTP; combat always ducks music and radio | Attenuation-curve test; loudness analysis of tour audio; ducking harness | No player footsteps or landings; no limiter; loudness unmeasured |
| **Maps** | Small maps crossed corner to corner in 25 s; Sabotage attackers reach a site in 15 to 25 s, defenders in 8 to 12 s, rotations 10 to 18 s; 10+ frags a minute and 3+ lead changes per free-for-all on every default map; Sabotage sides within 45 to 55% | Navmesh timing tool; bot survey | Frag pace met; lead changes short on three maps; Sabotage attack bias on two (#520) |
| **Bots** | Four or five difficulty tiers, each beating the one below 65 to 80% of the time; no tier reacts under 150 ms; perception stays honest (sight and sound only); under 5% dithering | Bot survey win matrix; perception tests | One fixed skill; honest senses and 200 to 400 ms reactions in band |
| **Campaign craft** | 8 to 15 min per level; at most 3 min between checkpoints; at most 3 enemy types per encounter outside marked brawls; every new enemy and verb taught without text before it is tested | Campaign survey times and checkpoint gaps; encounter audit | Level times and three continues per episode; no mid-level checkpoints |
| **Graphics scale and auto settings** | Floor: the lowest settings hold a 1% low of 60 fps at 720p on a defined low-end reference machine. Ceiling: on a strong machine fragr looks great. The benchmark and auto settings choose the highest resolution and quality that still hold a 1% low of 60 fps (or the player's higher target), explain the choice in plain words, keep manual overrides, and rerun when hardware, drivers or rendering cost change. Works on NVIDIA, AMD, Intel and Apple GPUs on Windows, Linux and macOS, with a renderer fallback for very weak GPUs. Runs great on the Steam Deck: a steady 40 fps in its 40 Hz mode (1% low at or above 36) at 1280x800 on its auto-chosen settings, with a 60 fps profile where it holds, legible HUD and menus at 800p and full controller play (a store release is undecided; the research may refine these numbers) | Benchmark runs across a hardware matrix (integrated Intel, AMD APU, an older and a modern NVIDIA and AMD card, Apple Silicon, a Steam Deck); auto-tune tests for search, variance and overrides; player and developer docs ([graphics auto-tune plan](plans/graphics-autotune.md)) | Presets and a benchmark that replays a fight per preset exist; no auto-tune; frame times measured on one GPU (Radeon 780M at 1280x720) |
| **Performance and stability** | No frame over 50 ms after warmup on any tier; tick p99 under 25% of budget at 16 fighters and 8 spectators; a 24-hour soak with no crash; no known bug that loses a round or a save | Benchmark scenes and frame stats; bench; soak; issue triage | Tick headroom met; one GPU measured; 120 s soak only |
| **Fair play** | A client receives only what its fighter could perceive (no wall information to modify); rate and size caps; resume and join tickets | Interest-filter tests; hardening plan checks | Every fighter receives full snapshots |
| **Privacy** | Nothing phones home; fun metrics are opt-in per host, announced at join, match-level only with no field that can identify a person, and shredded after 67 days ([policy](PRIVACY.md)) | Schema test that refuses identifying fields; retention test; join and status notice tests | Policy written; fun metrics planned (#529) |
| **Completeness** | No placeholder art, model, sprite, sound or copy anywhere a player can reach; every level, the epilogue and every default map at the golden-slice bar; score, voices and character art chosen by Nick | Asset manifest audit; inspected captures of every surface; Nick's review round (#472) closed; story audit rerun clean | Many surfaces open, tracked per wave |
| **Platforms and docs** | Windows, macOS and Linux packages boot to a fight on a clean machine; controllers and accessibility work; guides, changelog and release notes current and honest | Package install checks plus clean-machine installs; docs review | Packages checked automatically; clean-machine and controller installs not done |

Cutscene film waits for this same bar: every level, gun and character finished
first, the narrated slideshow standing in until then, staged and capped per
[`plans/cutscene-film.md`](plans/cutscene-film.md).

## Beyond 1.0

Direction, not promises. Each horizon starts only after the one before it is
proven with people, and the fun bar applies to everything added.

| Horizon | Direction |
|---|---|
| **2.0: bigger nights** | Full servers of 32 to 64 fighters and large agent-heavy arenas, measured; Wipe and large combined-arms modes on Holdfast-style fronts with vehicles bots can use; a UDP transport if the measured spike earns it ([TRANSPORT.md](TRANSPORT.md)); deployed cloud hosting once spend is approved; the [agent discovery](plans/agent-door-2026.md) door for public agents |
| **3.0: a bigger world** | New campaign chapters or optional co-op where the story supports them; the [inheritance benchmark](plans/inheritance-benchmark.md); localization; community maps and mutators; a possible Steam build |

Ideas that do not fit a horizon stay in issues until evidence says they belong.

## The fun bar

Concrete, checkable, and required before any phase is called done. Evidence is a screenshot, a test, or a recorded session.

Nick's October 3 target is the care and replay appeal of a breakout competitive
shooter, with the immediate fun of a strong mainstream multiplayer game for
players who like this style. This is an ambition, not a claim about current
quality. Art production must serve readable fights, responsive movement,
distinct routes and a reason to play another round. Keep fresh-player and LAN
acceptance open until actual people demonstrate those qualities.

- **Ten seconds.** Boot to a live fight in under ten seconds. Something happens on screen in the first five.
- **Readable.** Any fighter is identifiable at thirty meters. Any weapon is identifiable by silhouette and by sound alone.
- **Feedback.** Every hit has three signals: visual, audio, and HUD. Every frag has a callout.
- **Drama.** At least one Host or killfeed beat every thirty seconds of play. Round end has a podium. Warmup has a countdown.
- **Agency.** Bots visibly change behavior and react to the player. Agent joins are announced. Behavior chips are never lies.
- **Watchable.** The spectator camera never stares at nothing. The killfeed is legible from a couch.
- **Sticky.** The next round starts without a menu. Leaving to spectate never ends the match.
- **No slop.** No overlapping HUD text, no placeholder sprites in a shipped screenshot, no mood art labeled as gameplay.

## How work moves

- An issue states the problem; the PR description records what changed and the verification actually run. A plan in `docs/plans/` is written only for multi-PR efforts.
- Every change ships through a branch and a PR with passing CI, then a squash merge to `main`, and a tag when it changes what a player sees.
- Shipping a rung updates this file in the same PR. Anything that touches the wire updates [`protocol.md`](./protocol.md). Anything that bills money stops for written approval first, per `AGENTS.md`.
