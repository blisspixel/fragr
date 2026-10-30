# fragr roadmap

The order of operations that takes fragr from a playable development build to an exceptional game people play, watch and host. This file is the plan of record for sequencing. Feel and non-negotiables live in [`VISION.md`](./VISION.md). Bounded work lives in issues, PR descriptions and, for multi-PR efforts, [`plans/`](./plans/README.md). Implementation truth is source, tests and CI. The dated narrative and receipts through 2026-10-23 are in [the roadmap history](history/ROADMAP-2026-10.md).

Every item is **planned**, **in progress**, **shipped** (merged to `main`) or **proven** (shipped and demonstrated by a test, an inspected capture or a real session). Do not promote an item without the evidence.

## The shape of the plan

1. **Make it excellent locally.** Solo play, agents through the adapter, and small multiplayer on one machine or a LAN. Zero spend. Depth before breadth: one slice that looks, sounds and plays well sets the bar everything else is built to.
2. **Expose it.** A hardened server on a spare home machine or a small VM where strangers and their agents join and it does not fall over. Home is a complete host, not a lesser path.
3. **Make it deployable.** The same server as plan-only infrastructure, applied only after the exposed server is proven and spend is approved. The [server excellence plan](plans/server-excellence.md) owns this.
4. **Deepen it.** More maps, modes, vehicles, progression and the tooling that makes watching as good as playing.

Scale runs through every phase: small squads first (four to twelve fighters), then full servers (thirty-two to sixty-four), then large agent-heavy arenas. No rung is claimed until measured.

<a id="now-in-development"></a>

## Where we are (2026-10-30)

- **Release.** v0.94.0 is the development release checkpoint for waves 13 through 17, following the waves 11 and 12 packages in v0.93.0. The [release page](https://github.com/blisspixel/fragr/releases/latest) records published packages, checksums and package validation. Windows human play, real controllers and fresh-player acceptance remain separate unproven evidence.
- **Campaign.** Levels 1 to 20 are connected development missions with mission-entry saves (one current save schema, no migration), finite ammunition and three continues per episode; surviving Level 20 records the campaign's survival, which opens the Still Here epilogue (capability 57) from the menu, and a run exhausted in levels 18 to 20 gets its own ending and credits. Level 1, Recall Notice, is dressed as the golden slice (#461). Level 19, Planned Works (#465), adds the jetpack and the Paver; Level 20, Local Exception (#466), adds the Surveyor; both machines carry final Inheritance models from wave 11. Art, pacing and fresh-player review are open on every level.
- **Multiplayer.** Larak Lot, the hero free-for-all map, holds map 1 (#464). Every free-for-all life starts on the Pistol and Fists with guns on timed pads and a 4 s respawn (#467); fighters move at 6 m/s with a ground dodge (#463) and rocket-jump (#431); the Custody Plate is the lot's power item and Duel runs on it, with a fire-to-rematch podium (#431, wave 3); bots see before they fight (#468); the Host speaks rarely (#462). Team deathmatch, capture the flag, 5v5 Sabotage and vehicle Conquest on Holdfast Atoll remain, hosted from the menu or a dedicated server, with bot fill and agents on the same wire.
- **Honest assessment.** Nick's first Windows session on v0.90.0 filed #433 to #442. Waves 1 (#457) and 2 (#471) of the [October 23 round](plans/playtest-round-20261023.md) answer them and add the slice above, and wave 3 deepens it, with Linux evidence only: headless and Rust suites, coverage, playtest smokes and a rendered tour inspected on one Linux host. Windows human play, real pads and a fresh-player pass remain open evidence for the finished game. v0.92.0 packages passed automated install checks. Nick requested a development release after waves 4 and 5 on 2026-10-25.
- **Is it fun yet? Not proven, and not yet the bar.** The goal is the loop that made Counter-Strike, Battlefield 1942 and GoldenEye: a match so good the player wants another one immediately. Most of the parts that the October 23 study of Doom, Quake, Unreal Tournament, Counter-Strike, Battlefield and Halo found missing now exist: equal starts with power on timed pads, dropped guns, dodge and rocket jumps, a voiced Host for rare moments, Duel rematches and sudden death instead of draws. What still stops "one more game": only Larak Lot of the eight multiplayer maps is built to the bar; nothing after a match pulls the player into the next one (no map vote, no visible rival or personal best, although the server already keeps head-to-head records); dying in a team mode is waiting rather than watching a teammate; and no one but Nick has played. Waves 13 to 18 went mostly into the campaign. Wave 19 turns back to the match loop.

<a id="full-build-order"></a>
<a id="full-build-order-2026-09-27"></a>
<a id="full-build-order-updated-2026-10-04"></a>

## Full build order

This is the only active sequence. When the current rung changes, edit this section. Do not add a second list.

1. **October 23 playtest round, shipped with Linux evidence.** The [round plan](plans/playtest-round-20261023.md) ran in waves, each returning to one reviewed, green `main`. Wave 1 (#457) fixed the death lifecycle (#441), HUD layout and upright results (#437), menu focus and structure (#435, #436), reload readability (#440) and operator console output (#438), and added stutter traces (#434), the music review tool and asset-tool ceilings. Wave 2 (#471) added benchmark UX (#439), the console pad layout, radio dial and announcer setting (#442), the Pistol and Fists FFA start with a 4 s respawn, the feel pass, bot senses, the rare Host spine, one save schema, the faction readability contract and the bot roster. Owed: Windows human play and real pads. v0.92.0 packages passed automated install checks.
2. **Golden slice and hero map, implemented, evaluation continuing.** [Larak Lot](plans/larak-lot.md), a five-level car park, replaced Arena Duel on map 1 (#464), and Recall Notice is dressed as the Level 1 golden slice (#461). Both were judged from inspected Linux stills and motion; continue rendered inspection and constrained play now, while keeping physical-device and fresh-player evidence open. This slice is the quality bar for everything after it.
3. **Episode V to that bar, acceptance continuing.** [Planned Works](campaign/l19-planned-works.md) (Level 19, #465) and [Local Exception](campaign/l20-local-exception.md) (Level 20, #466) are connected development levels with Inheritance Paver and Surveyor models (wave 11, rendered review only; Nick's model pick stays open). The conditional [epilogue](campaign/epilogue-still-here.md), Still Here, and its exhaustion ending have technical boundary and replay coverage. Voice, ambience, page stills and fresh-player timing remain open alongside broader Episode V route evaluation.
4. **Raise the campaign to the bar, current engineering wave (18).** Revisit levels 1 to 18 for layout, art, pacing, encounter readability and fresh-player review. Waves 13 to 17 dressed Levels 2 to 13; wave 18 rebuilds layouts where dressing could not help (Levels 9, 13 and 17) and gives the cast their own colours. Unfinished acceptance above stays explicit while local engineering progresses.
5. **One more game, next (wave 19).** Make the multiplayer match loop the thing people come back for, and make the story hold together. See [Wave 19](#wave-19-one-more-game) below. This continues [multiplayer excellence](plans/multiplayer-excellence-20261017.md) (#431) and [bot and enemy AI](plans/bot-and-enemy-ai-excellence-20261017.md) (#432).
6. **Network depth and the exposed server.** Validate the implemented prediction and bounded lag compensation in a two-machine LAN session with humans, rule bots and an agent. Measure WebSocket capacity before any UDP spike, per [TRANSPORT.md](TRANSPORT.md), then run a public week with strangers. #434's remaining field and transport evidence belongs here.
7. **Prove the release.** Close fresh-player, difficulty, input and visual acceptance against the 1.0 bar below. Cloud apply stays plan-only until the public week is real and spend is approved.

<a id="next-steps"></a>

### Wave 18: layout and encounters, in progress

Too many spaces still read as rectangular rooms joined by straight connectors.
Wave 18 rebuilds three levels where dressing could not fix the layout, using the
[layout review](MAP-DESIGN.md#layout-variety-and-current-gaps): Doom's changing
combat loops, GoldenEye's connected objective rooms and Counter-Strike's
alternate approaches. Every new route is authored on the server and must not
skip a required story fact.

| Lane | Scope |
|---|---|
| Level 9 | A visible ship at arrival, a parallel ship-side approach and a cross-cradle connection |
| Level 13 | Machine silhouettes with matching collision, a closed roof, the gallery and maintenance loop |
| Level 17 | The raised command galleries, two stair routes and the outer service stair its brief promises |
| Characters | Splice, Tern, Renn and Level 8's held people in their own colours (merged; no credits spent) |
| Presentation | A Blood setting, On by default, and a sweep for visual clipping |

The coordinator fixed the capture tour's Rail route (#506) with a server test
that walks every tour route under combat shoves. Renn's own model waits for the
Meshy refresh on November 3; Latch waits for Nick's palette choice (#455).
Wave 17 (Level 10's Repeater and Levels 11 to 13 dressed) is summarized in the
table below.

<a id="wave-19-one-more-game"></a>

### Wave 19: one more game (next)

The test for every lane: after a match, does the player want another one right
away? Finish and polish what exists before adding more.

| Lane | Scope |
|---|---|
| Every map excellent | Keep all eight maps. Bug-hunt and fix each one in play (stuck spots, spawns, pad and route problems, clipping), then raise them toward Larak Lot's bar through the layout review, starting with Compliance Yard and Low Water. Add a per-map enable or disable switch for hosts, in the menu and on the server (today rotation cycles every map or a fixed night list); no map is cut until every map has had that full build-out and play evidence says otherwise. |
| The between-match hook | On the podium: your nemesis, head-to-head against each rival (the server already keeps these records) and personal bests. Then a three-map vote that counts down into the next match with no menu. |
| Death as a seat | In team modes, follow a living teammate after death and mark the clutch. Give the trailing Sabotage side a visible, earned way back (the loss bonus that kept Counter-Strike rounds alive). |
| Story that lands | Fix the story audit's findings on continuity, motivation, names and tone, across the lore, the briefs and what each level actually shows and says, Recall Notice through Still Here. Then make the [designed emotional beats](campaign/story-arc.md#structure) land in play, not on paper: anger as Latch's transport leaves, relief at the rescue, loss at Low Water, triumph at the Chancellor's capture, fear as the Union bots turn, grief as Latch chooses to go. Show them through what the player does, sees and hears, with the people made to matter earlier and restraint over melodrama. |

Promote the October 23 multiplayer study into the wave 19 plan. Close the wave
with a measured fun night of bots and agents across every map, then a
human LAN night:

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
- **Release acceptance.** Review v0.94.0 on Windows with real controllers and
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

Later, after evidence: Wipe and large combined-arms modes, the
[inheritance benchmark](plans/inheritance-benchmark.md),
[agent discovery](plans/agent-door-2026.md), localization and a possible Steam build.

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

## The 1.0 bar

Version 1.0 is a promise, not a milestone count. Until every line below is proven, releases stay at 0.x no matter how much has shipped.

- **Controls feel buttery.** First-person movement and aim with client-side prediction and server reconciliation, interpolation on every other fighter, no rubber-banding on a LAN or a good connection, input latency under fifty milliseconds on a LAN, sixty frames per second at 1080p on a modest machine with a full server. Mouse and gamepad both tuned. Use the offline benchmark for CPU work, live two-machine probes for network behavior, and inspected play plus physical measurements for feel; publish only measured results in release notes. The design, the staged PRs, and the pass numbers are in `plans/buttery-controls.md`.
- **Validated everywhere it claims to run.** A two-machine LAN session, a public server that stays up for a week with strangers on it, agents playing as rule bots, through the adapter, and as the decision-brain client, the single-player campaign complete through the wipe finale and its conditional epilogue, and desktop exports for Windows, macOS, and Linux that boot to Solo Scrap on a clean machine.
- **Extremely polished.** No placeholder art anywhere: every weapon, fighter, map surface, and HUD element final; the radio, effects, and Host voice complete; onboarding to a fight in under a minute with no docs; a twenty-four hour soak with no crash, proven by the status JSON at start and end in the release notes; the fun bar passing on a recorded session; boot to first snapshot under ten seconds as measured by the playtest report; docs and hosting guides current. Cutscene film waits for this same bar: every level, gun and character finished first, the narrated slideshow standing in until then, staged and capped per [`plans/cutscene-film.md`](plans/cutscene-film.md).
- **Hardened and honest.** The exposed-server phase complete (join tokens, rate and size caps, protocol versioning, reconnect resume, status endpoint, fair-play lanes and the profiler), the playtest harness thresholds tightened to the shipped feel, no known bugs that lose a round, and a changelog that matches the releases.

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
