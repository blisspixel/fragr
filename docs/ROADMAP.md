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

## Where we are (2026-10-25)

- **Release.** v0.91.0 (2026-10-24, waves 1 and 2) is the [latest desktop release](https://github.com/blisspixel/fragr/releases/latest). Wave 3 is on `main`. Wave 4 integrates modelled guns, combat effects, Larak surfaces, lighting, spectator facts and bot habits; its combined verification and visual review are in progress. Wave 5 follows with campaign props, signage and readability. Nick requested an updated development release after these waves on 2026-10-25. Windows play, real controllers and fresh-player acceptance remain separate open gates, not claims attached to that release.
- **Campaign.** Levels 1 to 20 are connected development missions with mission-entry saves (one current save schema, no migration), finite ammunition and three continues per episode; surviving Level 20 records the campaign's survival, which opens the Still Here epilogue (capability 57) from the menu, and a run exhausted in levels 18 to 20 gets its own ending and credits. Level 1, Recall Notice, is dressed as the golden slice (#461). Level 19, Planned Works (#465), adds the jetpack with a placeholder Paver; Level 20, Local Exception (#466), uses placeholder Surveyor and Paver forms. Art, pacing and fresh-player review are open on every level.
- **Multiplayer.** Larak Lot, the hero free-for-all map, holds map 1 (#464). Every free-for-all life starts on the Pistol and Fists with guns on timed pads and a 4 s respawn (#467); fighters move at 6 m/s with a ground dodge (#463) and rocket-jump (#431); the Custody Plate is the lot's power item and Duel runs on it, with a fire-to-rematch podium (#431, wave 3); bots see before they fight (#468); the Host speaks rarely (#462). Team deathmatch, capture the flag, 5v5 Sabotage and vehicle Conquest on Holdfast Atoll remain, hosted from the menu or a dedicated server, with bot fill and agents on the same wire.
- **Honest assessment.** Nick's first Windows session on v0.90.0 filed #433 to #442. Waves 1 (#457) and 2 (#471) of the [October 23 round](plans/playtest-round-20261023.md) answer them and add the slice above, and wave 3 deepens it, with Linux evidence only: headless and Rust suites, coverage, playtest smokes and a rendered tour inspected on one Linux host. Windows play, real pads, packaged builds and a fresh-player pass are still owed, and remain acceptance gates for the finished game. Nick requested a development release after waves 4 and 5 on 2026-10-25.

<a id="full-build-order"></a>
<a id="full-build-order-2026-09-27"></a>
<a id="full-build-order-updated-2026-10-04"></a>

## Full build order

This is the only active sequence. When the current rung changes, edit this section. Do not add a second list.

1. **October 23 playtest round, shipped with Linux evidence.** The [round plan](plans/playtest-round-20261023.md) ran in waves, each returning to one reviewed, green `main`. Wave 1 (#457) fixed the death lifecycle (#441), HUD layout and upright results (#437), menu focus and structure (#435, #436), reload readability (#440) and operator console output (#438), and added stutter traces (#434), the music review tool and asset-tool ceilings. Wave 2 (#471) added benchmark UX (#439), the console pad layout, radio dial and announcer setting (#442), the Pistol and Fists FFA start with a 4 s respawn, the feel pass, bot senses, the rare Host spine, one save schema, the faction readability contract and the bot roster. Owed: Nick's Windows play, real pads and a packaged build.
2. **Golden slice and hero map, implemented, awaiting play.** [Larak Lot](plans/larak-lot.md), a five-level car park, replaced Arena Duel on map 1 (#464), and Recall Notice is dressed as the Level 1 golden slice (#461). Both were judged from inspected Linux stills and motion; the bar is met only when Nick has played them. This slice is the quality bar for everything after it.
3. **Episode V to that bar, current.** [Planned Works](campaign/l19-planned-works.md) (Level 19, #465) and [Local Exception](campaign/l20-local-exception.md) (Level 20, #466) are connected development levels with placeholder Paver and Surveyor forms. The conditional [epilogue](campaign/epilogue-still-here.md), Still Here, and its exhaustion ending are a connected development build judged from Linux stills; voice, ambience, page stills and fresh-player timing are open. No level ships below the golden-slice bar. The next steps below finish this rung.
4. **Raise everything else to the bar.** Revisit levels 1 to 18 for art, pacing, encounter readability and fresh-player review. Deliver the [multiplayer excellence](plans/multiplayer-excellence-20261017.md) (#431) and [bot and enemy AI excellence](plans/bot-and-enemy-ai-excellence-20261017.md) (#432) scope, #434 stages 3 to 6 (stage 2, encode-once broadcasts, is measured and done), and remaining weapon, character and venue art. Nothing in the agreed game is cut; it is built to the bar instead.
5. **Network depth and the exposed server.** A two-machine LAN session on the predicted sim with humans, rule bots and an agent; bounded lag compensation; measured WebSocket capacity before any UDP spike, per [TRANSPORT.md](TRANSPORT.md); then a public week with strangers on it.
6. **Prove the release.** Close fresh-player, difficulty, input and visual acceptance against the 1.0 bar below. Cloud apply stays plan-only until the public week is real and spend is approved.

<a id="next-steps"></a>

### Next steps when work resumes

The current rung's work, in order. Finish wave 4's integrated checks and visual
review, merge its one PR, then integrate wave 5 into one PR. The current release
request does not establish Windows or fresh-player acceptance.

1. **Nick's picks.** Narrator and Host voices (`.agents/voice-casting-20261023/index.html`); the character art treatment from the [#469 trial](plans/art-style-trial-20261023.md); Meshy model picks (`.agents/review-20261023/models.html`); the Latch colours (#455); Union seal option C; radio keepers through `fragr-audiogen review`; the Larak Lot props as they stand in the wave 3 stills, including the bookmaker's kiosk stretched past the proposed 15% tolerance and palette proposal P10. Credits as read on 2026-10-24: Meshy 300 monthly with 15 held, so about 285 usable, resetting 2026-11-03; ElevenLabs 329,544 remaining, resetting 2026-11-06. Run the live balance check before any paid stage.
2. **Windows playtest of the wave 3 build.** Nick plays Larak Lot (free-for-all, the Pit Rocket and rocket jump, Duel and the podium rematch), Recall Notice, Persons Unknown with Latch covering, and the menus on Windows with a real pad; every defect becomes an issue and a fix lane. Judge whether the Heavy Sweeper and Turret optics read red or salmon at the top of a windup.
3. **Integrate the picks.** Selected Meshy models and radio keepers go into the levels and the station library, seen in game and recaptured. Wave 3 put the nine Larak Lot props in on their review grades; Nick's review of the wave PR stands as their pick.
4. **Still Here, built, awaiting play.** The conditional epilogue walks the refuge the morning after and years later from the saved survival, read-only, and a run exhausted in the wipe gets The Last Page and its credits instead. Owed: Nick's play, a fresh-player timing, and the voice, ambience and page stills [listed for the next asset round](campaign/epilogue-still-here.md#owed-to-the-next-asset-round).
5. **Remaining scope.** The rest of #431 (multiplayer excellence: voiced Host lines, hit chime, host presets and mutator stacking, the Conquest bleed, a Duel spectator queue and winner-stays; wave 3 built blast push and the rocket jump, the Custody Plate, Duel and the podium rematch, and wave 4 the Scatter meatshot and a head-to-head book kept across sessions), #432 (bot and enemy AI: dormant guard vision, squad roles, barks, and enough Rocket on Larak Lot for bots to score with it at six, a supply decision measured in the [bot plan](plans/bot-and-enemy-ai-excellence-20261017.md#6-progress); wave 3 built tells that wait for an attack token, lit Union optics and Latch's magazine and cover, and wave 4 callsign habits, grudges and bots that use the Rocket), and #434: the rest of the stage 1 baseline (slow readers, bursty input, saturation) and stages 3 to 6 (relevance, acknowledged deltas, bounded lag compensation, transport comparison). Stage 2, encode-once broadcasts with a before and after table in [BENCHMARK.md](BENCHMARK.md#local-spectator-fan-out), landed in wave 3.
6. **Release v0.92** after waves 4 and 5 pass CI and inspected visual QA, with
   `tools/qa_tour.sh --publish` and release notes that distinguish automated
   portability checks, inspected Linux play and still-owed human acceptance.

Later, after evidence: Wipe and large combined-arms modes, the [inheritance benchmark](plans/inheritance-benchmark.md), [agent discovery](plans/agent-door-2026.md), localization and a possible Steam build.

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
