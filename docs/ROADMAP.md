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

## Where we are (2026-10-23)

- **Release.** v0.90.0 is the [latest desktop release](https://github.com/blisspixel/fragr/releases/latest) for Windows, Linux and macOS.
- **Campaign.** Levels 1 to 20 are connected development missions with mission-entry saves, finite ammunition and three continues per episode; surviving Level 20 records the campaign's survival and leaves the Still Here epilogue pending, unbuilt. Level 19, Planned Works (#429), has its generated jetpack in place and a placeholder Paver; Level 20, Local Exception (#430), uses placeholder Surveyor and Paver forms. Art, pacing and fresh-player review are open on every level.
- **Multiplayer.** Free-for-all, team deathmatch, capture the flag, 5v5 Sabotage and vehicle Conquest on Holdfast Atoll, hosted from the menu or a dedicated server, with bot fill and agents on the same wire.
- **Honest assessment.** Breadth has outrun depth. Nick's first Windows multiplayer session on v0.90.0 filed #433 to #442: death camera and input carryover, HUD collisions and tilted results, menu focus, silent reloads, buried server output, benchmark UX, music controls and stutter. Green checks did not catch any of it. The build order below fixes that before adding more.

<a id="full-build-order"></a>
<a id="full-build-order-2026-09-27"></a>
<a id="full-build-order-updated-2026-10-04"></a>

## Full build order

This is the only active sequence. When the current rung changes, edit this section. Do not add a second list.

1. **October 23 playtest round, current.** The [round plan](plans/playtest-round-20261023.md) runs in waves, each returning to one reviewed, green `main` before the next. Wave 1 fixes the death lifecycle (#441), HUD layout and upright results (#437), menu focus and structure (#435, #436), reload readability (#440), operator console output (#438) and stutter diagnosis (#434). Wave 2 adds benchmark UX (#439), music controls (#442), the Tack and Fists FFA starting kit and a 4 s FFA respawn, alongside an asset round that spends the funded image, model and audio credits on assets that will be integrated and visible. Every wave ends with the visual QA loop: recapture, look, fix, repeat until a pass finds nothing.
2. **Golden slice and hero map.** Boot, menu, join, fight, die, respawn and result on one hero free-for-all map, plus campaign Level 1, built until it looks, sounds and plays well enough to show anyone. Validate by capturing and looking at stills and motion, iterating until they look good, and Nick playing it. This slice is the quality bar for everything after it.
3. **Episode V to that bar.** [Planned Works](campaign/l19-planned-works.md) (Level 19, #429) and [Local Exception](campaign/l20-local-exception.md) (Level 20, #430), following the accepted ground-escape and wipe-survival briefs, then the conditional [epilogue](campaign/epilogue-still-here.md). No level ships below the golden-slice bar.
4. **Raise everything else to the bar.** Revisit levels 1 to 18 for art, pacing, encounter readability and fresh-player review. Deliver the [multiplayer excellence](plans/multiplayer-excellence-20261017.md) (#431) and [bot and enemy AI excellence](plans/bot-and-enemy-ai-excellence-20261017.md) (#432) scope, stutter stages 2 to 6 (#434) once wave 1 measurements exist, and remaining weapon, character and venue art. Nothing in the agreed game is cut; it is built to the bar instead.
5. **Network depth and the exposed server.** A two-machine LAN session on the predicted sim with humans, rule bots and an agent; bounded lag compensation; measured WebSocket capacity before any UDP spike, per [TRANSPORT.md](TRANSPORT.md); then a public week with strangers on it.
6. **Prove the release.** Close fresh-player, difficulty, input and visual acceptance against the 1.0 bar below. Cloud apply stays plan-only until the public week is real and spend is approved.

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
