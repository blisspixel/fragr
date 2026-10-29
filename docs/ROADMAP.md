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

## Where we are (2026-10-26)

- **Release.** Waves 11 and 12 of the October 27 round ship in v0.93.0; waves 3 to 5 shipped in v0.92.0. Wave 4 integrates modelled guns, combat effects, Larak surfaces, lighting, spectator facts and bot habits. Wave 5 adds twelve campaign props, reduced signage, rescue continuity fixes, selectable Sniper scope modes and direct Rocket Launcher selection. The acceptance patch keeps Continue available after a failed send and qualifies campaign evaluation, recovery and ending boundaries. The [latest desktop release](https://github.com/blisspixel/fragr/releases/latest) records the published version and package validation. Windows human play, real controllers and human fresh-player acceptance remain separate unproven evidence.
- **Campaign.** Levels 1 to 20 are connected development missions with mission-entry saves (one current save schema, no migration), finite ammunition and three continues per episode; surviving Level 20 records the campaign's survival, which opens the Still Here epilogue (capability 57) from the menu, and a run exhausted in levels 18 to 20 gets its own ending and credits. Level 1, Recall Notice, is dressed as the golden slice (#461). Level 19, Planned Works (#465), adds the jetpack and the Paver; Level 20, Local Exception (#466), adds the Surveyor; both machines carry final Inheritance models from wave 11. Art, pacing and fresh-player review are open on every level.
- **Multiplayer.** Larak Lot, the hero free-for-all map, holds map 1 (#464). Every free-for-all life starts on the Pistol and Fists with guns on timed pads and a 4 s respawn (#467); fighters move at 6 m/s with a ground dodge (#463) and rocket-jump (#431); the Custody Plate is the lot's power item and Duel runs on it, with a fire-to-rematch podium (#431, wave 3); bots see before they fight (#468); the Host speaks rarely (#462). Team deathmatch, capture the flag, 5v5 Sabotage and vehicle Conquest on Holdfast Atoll remain, hosted from the menu or a dedicated server, with bot fill and agents on the same wire.
- **Honest assessment.** Nick's first Windows session on v0.90.0 filed #433 to #442. Waves 1 (#457) and 2 (#471) of the [October 23 round](plans/playtest-round-20261023.md) answer them and add the slice above, and wave 3 deepens it, with Linux evidence only: headless and Rust suites, coverage, playtest smokes and a rendered tour inspected on one Linux host. Windows human play, real pads and a fresh-player pass remain open evidence for the finished game. v0.92.0 packages passed automated install checks. Nick requested a development release after waves 4 and 5 on 2026-10-25.

<a id="full-build-order"></a>
<a id="full-build-order-2026-09-27"></a>
<a id="full-build-order-updated-2026-10-04"></a>

## Full build order

This is the only active sequence. When the current rung changes, edit this section. Do not add a second list.

1. **October 23 playtest round, shipped with Linux evidence.** The [round plan](plans/playtest-round-20261023.md) ran in waves, each returning to one reviewed, green `main`. Wave 1 (#457) fixed the death lifecycle (#441), HUD layout and upright results (#437), menu focus and structure (#435, #436), reload readability (#440) and operator console output (#438), and added stutter traces (#434), the music review tool and asset-tool ceilings. Wave 2 (#471) added benchmark UX (#439), the console pad layout, radio dial and announcer setting (#442), the Pistol and Fists FFA start with a 4 s respawn, the feel pass, bot senses, the rare Host spine, one save schema, the faction readability contract and the bot roster. Owed: Windows human play and real pads. v0.92.0 packages passed automated install checks.
2. **Golden slice and hero map, implemented, evaluation continuing.** [Larak Lot](plans/larak-lot.md), a five-level car park, replaced Arena Duel on map 1 (#464), and Recall Notice is dressed as the Level 1 golden slice (#461). Both were judged from inspected Linux stills and motion; continue rendered inspection and constrained play now, while keeping physical-device and fresh-player evidence open. This slice is the quality bar for everything after it.
3. **Episode V to that bar, current.** [Planned Works](campaign/l19-planned-works.md) (Level 19, #465) and [Local Exception](campaign/l20-local-exception.md) (Level 20, #466) are connected development levels with final Inheritance Paver and Surveyor models (wave 11, rendered review only; Nick's model pick stays open). The conditional [epilogue](campaign/epilogue-still-here.md), Still Here, and its exhaustion ending are a connected development build judged from Linux stills; voice, ambience, page stills and fresh-player timing are open. No level ships below the golden-slice bar. The next steps below finish this rung.
4. **Raise everything else to the bar.** Revisit levels 1 to 18 for art, pacing, encounter readability and fresh-player review. Deliver the [multiplayer excellence](plans/multiplayer-excellence-20261017.md) (#431) and [bot and enemy AI excellence](plans/bot-and-enemy-ai-excellence-20261017.md) (#432) scope, #434 stages 3 to 6 (stage 2, encode-once broadcasts, is measured and done), and remaining weapon, character and venue art. Nothing in the agreed game is cut; it is built to the bar instead.
5. **Network depth and the exposed server.** A two-machine LAN session on the predicted sim with humans, rule bots and an agent; bounded lag compensation; measured WebSocket capacity before any UDP spike, per [TRANSPORT.md](TRANSPORT.md); then a public week with strangers on it.
6. **Prove the release.** Close fresh-player, difficulty, input and visual acceptance against the 1.0 bar below. Cloud apply stays plan-only until the public week is real and spend is approved.

<a id="next-steps"></a>

### Next steps when work resumes

Waves 4 and 5 are released. Continue evaluation and bounded fixes without waiting
for human sessions or optional art picks. #480 delivered #479's guided Recall Notice
survey to the existing playtest harness: constrained vision, reaction, turning
and aim, actual supplies, deaths and continues, and preserved failure reports.
The [harness guide](../tools/playtest/README.md) states its assumptions. Inspect
failures in the rendered level before changing encounters, retain a fixed
controller baseline when comparing game changes, and promote demonstrated
defects to regression tests. Development-release checks and synthetic profiles
do not establish physical-controller feel or human fresh-player acceptance.

The recovery acceptance slice (#481) keeps Continue available after a failed
transport enqueue. It tests an earned, finite-ammunition M01 departure through
disk save, M02 entry, enemy-caused death and a reopened retry, with exact entry
inventory and one continue spent. This is known-route continuity evidence,
separate from the constrained Recall Notice survey. A standalone M02 entry
fixture transfers the same perception, aim and reload policy through the
existing mission controller; forwarding its omitted objective fields repairs
the initial configuration. It does not claim an inherited M02 clear. Repeated pending refreshes,
stale requests, duplicate accepts and later-campaign recovery remain covered by
the existing client and server harnesses. The visual tour now restarts pickup
routes after a death or round change, waits for timed supplies at their pad,
and uses ordinary defensive fire along the route. This authoring controller
has accurate aim at visible rivals in every direction; it is separate from
the constrained survey and keeps the existing route and retry limits.
The mixed-client roster exposed a separate Holdfast aircraft-edge stall:
the shared mission controller's arena fallback omitted live vehicle hulls.
It now uses the existing snapshot collision geometry for routing and local
avoidance. Install checks retain bounded child diagnostics on premature wire
loss and use the process owner's confirmed retirement result during cleanup.
These changes preserve the roster's five-second stall gate and the package
check's required wire facts and owned-process shutdown.

The bounded ending acceptance (#482) covers the M20 survival threshold and
exhaustion in levels 18 to 20 across all difficulties, duplicate completion,
muted/skipped scenes and read-only saved epilogue replay. Immediate aftermath
and years-later walks were inspected with no rescues and with an explicit
saved-survivor fixture. These are lifecycle, presentation and replay checks;
they do not establish a full inherited constrained finale or combat pacing.
The review helper now refuses unmet named states and unsettled arrivals
instead of saving misleading captures. Continue the Episode V rung with
bounded encounter/readability trials using the calibrated policy, without
waiting on optional human sessions or asset picks.

The bounded M19 slice (#485) extends that same survey through the jetpack
lesson and first tram-street Paver, before the market. It measures supported
powered ascent independently of objective arrival and filters strip perception
by view, cover and reaction time. The crossing transfer exposed an evaluator
that forgot guards behind cover and waited at its arrival forever; bounded
last-seen search now routes only to observed positions. Retain the matched
baseline and repaired-controller trials, including failures. Recorded flight,
strip and stalled windows support rendered inspection; they do not establish
full inherited M19 pacing or human route discovery. Continue broader Episode V
acceptance in later bounded slices, rather than treating this endpoint as a
whole-level approval.

The adjacent market slice (#487) continues that earned prefix through
`market_strips`, stopping before the tanks and Latch's departure. Per-attempt
equipment and health receipts separate depleted arrivals, market failures and
completion; no replacement kit is supplied. Stage-specific work windows keep
the street lesson separate from the two-Paver encounter. Compare the declared
seed/profile matrix and inspected motion before changing ammunition or escape
behavior. Attempt-wide challenge flags cannot establish market-only damage or
interruption. A retained ordinary-action trace exposed escape/pursuit
oscillation at a live strip and generic dodging that replaced the strip escape.
The market evaluator preserves that escape and rejects grounded re-entry into
currently perceived strips without changing the teaching prefix or authored
content. This remains standalone constrained evaluation, not inherited
whole-level or human first-play acceptance.

Wave 11 of the [October 27 round](plans/build-round-20261027.md) finishes that
diagnosis with per-action market facts. The overlapping-strip death came from
a shared strip escape that re-chose its exit beside a wall corner every tick;
keeping one exit per strip half is enough to free the body, with a recorded-
geometry regression and no change in clears (8/18), deaths or exhaustion on
the matched cohort. Most remaining market deaths are shots at a fighter with
no ranged rounds after a prefix that skips the gallery Scatter and pocket
Repeater; measure supply visibility before any policy or content change.
`--survey-mission m19-tanks` takes every earned market clear to the water
tanks without loss; the roof loop is the next bounded slice. Separately,
`--survey-mission m02-carry` carries the constrained Recall Notice departure
into M02 through the server's own run file and plays a bounded 60 s window:
every death is reopened from disk, dropped, stale and duplicate Continue
requests are refused, and exactly one continue restores the entry kit. Over 72
trials, 50 departures entered M02, 42 were alive when the window closed and 8
exhausted, with no lifecycle violation and no M02 clear claimed. Retries
restore carried low health, so very low-health entries can exhaust a run (a
design question). The local child's fixed seed replayed a deterministic
agent's death on every Continue (#489); since wave 13 each retry runs on its
own stream derived from the run and attempt.

Wave 12 of the same round voices and deepens the arena and the campaign.
Callum records the 48 voiced Host slots, chosen and levelled by transcript and
loudness measurement and still to be heard by Nick; a tiered hit confirm reads
damage, a headshot (`shot_results.head`) and a kill; the Scatter gains a sub
kick and a pump clack. Rule bots fire the Rocket close, save rockets for shots
that land and chase Rocket drops they have seen (six-bot share 6.1% to 8.2%;
holder survival is now the limit, a weapon or map call); CTF bots take pads
within their role; named bots post rare objective calls that reach only their
own side and spectators (gameplay 60). Campaign guards on foot answer the quiet
region alarm by looking and need their own sighting and a 200 to 400 ms
reaction unless they already face it; a shot puts the whole group in the fight;
heavies pin, skirmishers flank and the Auditor shields behind a heavy; Union
radio barks are voiced and Latch callouts are captions until casting. Over 288
constrained Recall Notice trials clears are 189 against 194 (within noise), but
the deliberate profile on Standard and Severe is harder and M14 route seed 1015
regresses (#493). The #434 stage 1 baseline is measured in
[BENCHMARK.md](BENCHMARK.md): healthy readers and the tick stay isolated, no
tick runs over budget at the 64-connection cap with about 101 fighters, and
stage 3 relevance is deferred because distance cuts only 5 to 8% of entries on
Larak Lot; slow readers linger (#492).

Wave 13 pays those debts. In Recall Notice, guards the participant can see
now take the first attack tokens, so a careful player is no longer shot from
the blind side while facing the room (#493). The deliberate profile on Standard
and Severe is back to 28 and 19 of 32 clears (base 28 and 20), and all 288
constrained trials clear 207 against 194 before wave 12. A wider barrage escape
holds M14 seed 1015, and a navigator start fallback frees the seed 44 strand
(#497). Sector 9's staging block left a one-body slot below the inspection
deck that trapped anyone who stepped off. It now stands flush, and a new check
walks off every ledge on every arcade map (#491; probe stalls 7 to 0). Timing
tests wait on observed readiness (#494), and each campaign retry runs on its
own seeded stream (#489). The network closes a slow reader in about 6 to 12 s
instead of 38 s (#492). A 30 s grace after MapInfo or Mission protects a level
load, whose worst measured frame is 0.48 s. Snapshot deltas (#434 stage 4,
gameplay 61) cut per-client traffic by 66 to 73% at 6 to 64 connections.
Persons Unknown (Level 2) is dressed toward the golden slice in rendered
passes and drops its graybox name. CLAUDE.md now imports AGENTS.md (#498).

Wave 14 carries the golden-slice bar into three more levels. Each was dressed
in rendered passes from a level-specific script, with no new collision:
- **Level 3, Scheduled Service.** A working rail yard: recall cars, a hut, the
  signal box and a mast readable from anywhere. Its fallen-mast state and its
  route tour are fixed too.
- **Level 4, Notice to Vacate.** A late-afternoon Low Water market town. Its
  tram vote sign now carries only after the vote, and the dressing no longer
  vanishes when the clinic shutter opens.
- **Level 6, Port of Entry.** The cargo no longer wears Union black and red,
  so the guards stand out against it.

Each level keeps to six or fewer readable signs. Level 2's dark rooms are
lifted to Level 1's brightness, and the news station is plainly Perimeter
Talk. Bounded hitscan lag compensation (#434 stage 5, gameplay 62) rewinds
ordinary fighters to what the shooter saw, at most 200 ms:
- before, about 60% of shots that looked like hits on screen missed on the
  server, even at 0 ms ping;
- now none miss up to 100 ms ping, and 15.8% at 150 ms.

Cover is tested as it stands now, and seated riders stay with their vehicle.
The campaign briefs are now named by their level number.

Wave 15 finishes Episode I and opens the lunar town:
- **Level 5, No Forwarding Address.** Low Water's roofs and tram trench now
  share Level 4's district look.
- **Level 7, Declared Goods.** Its blocks were plain off-white, which read as
  Inheritance; they are now painted in household colours. The curfew post,
  shields and ramp had worn Union black and red; they are restyled.
- **Heavy Sweeper.** Its sprite was painted much lighter than a Clerk's and
  had no normal map, so it read tan in daylight. It now reads issued black
  and red. Captured in Levels 5, 6 and 12.
- **Radio.** "Frequency" is gone from spoken audio for 3,912 ElevenLabs
  credits: nine clips cut at natural pauses, five re-recorded, the station ID
  regenerated, and two songs whose chorus is the pun left rotation. A
  listening pass is owed.
- **Network (gameplay 63).** Deltas name fighters by roster position, and the
  encoder diffs JSON text without parsing. Delta bytes fell 40 to 44% on top
  of wave 13, and encode cost about halved. The lag compensation counters are
  on `/status`.
- **#502.** The Level 1 fixture drew a random run id, so since wave 13 each
  retry played a different fight in every process. It failed 19 of 300 times
  locally. The fixture now uses replay ids, with the seed and count unchanged.

Wave 16 finishes Episode II and opens the ship:
- **Level 8, Custodian of Record.** The archive was pale enamel striped with
  glowing red; it is now green enamel, filing runs, brass tubes and warm desk
  light, with cold light where Sweepers stand so they read black. The
  "Authorized noise" screen is visible again, with a tick pattern that reads
  muted. Eight signs, the budget.
- **Level 9, Passenger Manifest.** Tern's ship reads as a ship in its cradle:
  gunmetal hull, its name on the port side, Union seal tape and one impound
  notice that goes when the hatch opens. Four signs. The Enforcer reads black
  and red at every range captured.
- **Level 10, Common Carrier.** The walls had been Inheritance off-white with
  cyan flecks; the three decks are now gunmetal and warm bone, freight below,
  lived-in crew deck, quiet command above, with the custody tender outside.
- **Union tells stay red.** The Turret and Heavy lamps drifted to salmon at
  the top of a windup (#FF7162); they now swell to a deeper red (#FF2924).
  Absorbed Heavies in Level 19 swelled to pale mint; they stay cyan. Level 6
  turrets and the Railgun trail read against the darker customs hall.
- **Network (#434).** Positions, aim and shot traces are rounded on the wire
  only, 6 to 12% less per client. A link shaper in `fragr-playtest` shows on
  loopback that slow links hit the ping close before per-reader deltas ever
  trigger, and rewind under jitter lands every seen hit up to 50 ms jitter at
  50 ms round trip ([BENCHMARK.md](BENCHMARK.md)).

What comes next, and why. Wave 17 continues in this order:
1. **Characters in personal colours.** Splice, Latch (#455) and Tern all read
   pale silver near the Inheritance off-white, Renn has no art of their own and
   Level 8's captives share one figure. This is the largest readability gap
   left in Episodes I and II. Meshy credits reset on 2026-11-03.
2. **Level 10's Repeater.** The level introduces the Repeater, but the server
   never grants it there, so the lesson is missing. A gameplay fix with a
   route test.
3. **Levels 11, 12 and 13 toward the golden slice.** The tender, the Martian
   habitat and the foundry, at the same standard as Levels 1 to 10.
4. **Geometry the dressing cannot fix.** Level 9's ship is boxes under paint
   and the arrival view cannot see it; Level 6 has no limited-perception
   survey scenario.
5. **#434 on two machines.** Jitter, loss, the real Godot client on a shaped
   link and stage 6 all need a second machine; one host, no root and no
   netem cannot produce them. The next byte saving is `shot_results`.

**Nick's review round (kept open on purpose).** These wait for a round built
for Nick to see options and listen, not for engineering:
- a listening pass on Callum's Host, the barks and the radio edits;
- the Rocket share (8.2% against a 15% target, a weapon or map change);
- whether the hesitant profile's easier Recall Notice is wanted;
- the Latch scheme (#455) and a minimum health on entering or retrying M02;
- the Paver and Surveyor model pick and Latch's voice (#472).
The round gathers each choice on one page, with stills side by side and the
audio playable in place, so each answer is a pick plus a note.

Wave 5 adds twelve prepared campaign props, replaces repeated prose with
physical and painted detail, shortens objectives while retaining control and
threat cues, and reconciles rescue continuity with the saved outcomes. The
world-text audit covers all twenty maps and Still Here; its initial-state
counts and inspected sign sheets are authoring evidence. Human completion
times, deaths, stuck points and first-play pacing remain unmeasured. The
source and deterministic route checks do not close that acceptance work.

1. **Optional art feedback; continue with the current treatment.** Narrator and Host voices (`.agents/voice-casting-20261023/index.html`); the character art treatment from the [#469 trial](plans/art-style-trial-20261023.md); Meshy model picks (`.agents/review-20261023/models.html`); the Latch colours (#455); Union seal option C; radio keepers through `fragr-audiogen review`; the Larak Lot props as they stand in the wave 3 stills, including the bookmaker's kiosk stretched past the proposed 15% tolerance and palette proposal P10. Credits as read on 2026-10-24: Meshy 300 monthly with 15 held, so about 285 usable, resetting 2026-11-03; ElevenLabs 329,544 remaining, resetting 2026-11-06. Run the live balance check before any paid stage.
2. **Optional Windows playtest of v0.93.0; no engineering wait.** Nick plays Larak Lot (free-for-all, the Pit Rocket and rocket jump, Duel and the podium rematch), Recall Notice, Persons Unknown with Latch covering, the Sniper scope modes and the menus on Windows with a real pad; every defect becomes an issue and a bounded fix.
3. **Integrate the picks.** Selected Meshy models and radio keepers go into the levels and the station library, seen in game and recaptured. Wave 3 put the nine Larak Lot props in on their review grades; Nick's review of the wave PR stands as their pick. Wave 5 put twelve campaign props in where a server solid already stands for them (`client/scripts/campaign_props.gd`, `tools/campaign_props_20261025.json`): the correction machine (level 2), the impound tug seen through the customs glass (6), the pilot consoles, galley and berths (10), the lathes and freight hoist (13), the stalled trams (19, 20) and the concourse stretcher, cases, duffels and crates (19). In issued black, the correction machine and the lathes failed the P4 interim grayscale check: a black-coated Clerk standing in front of either was readable only by his outline. Both now wear the Union's plate steel (`union_plate`) and keep their red seal marks. Nick's P4 answer can still move the lathes to a place colour. The other graded models wait on a matching solid, which needs a playtest, or on Nick (the wave PR lists each with its reason).
4. **Still Here, technical acceptance covered; pacing and art remain.** The conditional epilogue walks the refuge the morning after and years later from the saved survival, read-only, and a run exhausted in the wipe gets The Last Page and its credits instead. Survival alone opens it; rescues change the people. Automated boundary and replay checks plus inspected walks cover the bounded ending slice above. Owed: human fresh-player timing and the voice, ambience and page stills [listed for the next asset round](campaign/epilogue-still-here.md#owed-to-the-next-asset-round). These do not block further technical acceptance.
5. **Remaining scope.** #431 (multiplayer excellence) is built through wave 12: blast push and the rocket jump, the Custody Plate, Duel and the podium rematch (wave 3); the Scatter meatshot and the head-to-head book (wave 4); host presets with stacking, the Duel line with winner-stays and the Conquest bleed (wave 11); Callum's Host voice, the hit confirm and the Scatter sound pass (wave 12). Owed: Nick's listening pass and a two-human Duel hand-over. #432 (bot and enemy AI) is built through wave 12: perception, attack tokens, tells, Latch's cover, callsign habits, grudges, guns dropped on death, Rocket use, CTF pads, objective calls, guard sighting, squad roles and barks. Wave 13 orders attack tokens by the participant's view, which fixes the Recall Notice deliberate-profile regression (#493). Owed: the Rocket at 15% of frags at six (8.2% now; a weapon or map decision, see the [bot plan](plans/bot-and-enemy-ai-excellence-20261017.md#6-progress)) and Latch's voice. #434: stages 1 and 2 are measured, and stage 3 is deferred with numbers in [BENCHMARK.md](BENCHMARK.md). Wave 13 closes slow readers (#492) and lands stage 4's snapshot deltas (66 to 73% less traffic per client). Wave 14 lands stage 5, bounded hitscan lag compensation at 200 ms; wave 15 finishes stage 4's measured remainder (roster positions in deltas, per-reader deltas, a text-level encoder) and publishes the rewind counters. Wave 16 rounds motion on the wire and measures simulated links on loopback. Next are two-machine jitter and loss evidence, the real client on a shaped link and stage 6 (transport comparison).
6. **Next release follows acceptance fixes.** Keep automated portability,
   inspected Linux visuals, package checks and human acceptance distinct.

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
