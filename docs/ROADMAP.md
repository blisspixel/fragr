# fragr roadmap

The order of operations to take fragr from a playable vertical slice to an exceptional game that people play, watch, and host. This file is the plan of record for sequencing. Feel and non-negotiables live in [`VISION.md`](./VISION.md). Bounded work items live in [`plans/`](./plans/README.md). Implementation truth is source, tests, and CI.

Every item below is in exactly one state: **planned**, **in progress**, **shipped** (merged to `main`), or **proven** (shipped and demonstrated with evidence: a test, a recorded smoke, a screenshot from the tip, or a real session). Do not promote an item without the evidence.

## The shape of the plan

1. **Prove it locally.** Solo play against bots, agent play through the adapter, and small multiplayer on one machine or a LAN. Zero spend. Everything here is testable in CI or a recorded smoke.
2. **Expose it.** A hardened server you can run on a home box or a small VM with the port open, where strangers and their agents join and it does not fall over.
3. **Make it cloud native.** GCP Terraform that applies cleanly, scales along a ladder, and stays under the spend cap. Not before the exposed server is proven.
4. **Deepen it.** More maps, modes, vehicles, progression, and the let's-play tooling that makes watching as good as playing.

The engineering ladder for scale runs through every phase: small squads first (four to twelve fighters, the current bar), then full servers (thirty-two to sixty-four), then large agent-heavy arenas (hundreds of fighters where most are agents). Each rung has its own measurements and is not claimed until measured.

## Where we are (2026-10-04)

[Desktop releases](https://github.com/blisspixel/fragr/releases/latest) contain
matching client/server packages and immutable build checks. Bounded development branches use pull requests with
full CI before main integration. The
[changelog](../CHANGELOG.md) lists every change; the plans linked here hold the
evidence.

**Campaign.** Levels 1 to 8 are playable development prototypes, with
durable run carry, retries and continues. An automated
[polish pass](plans/campaign-polish-20261002.md) sealed level geometry, fixed
hidden arrival gates and stranded guards, and took the free local agent from 7
to 18 of 18 level departures across three difficulties.

The restored [level 7](plans/l07-declared-goods-prototype.md) passes its complete
29-state rendered route: all 25 guards, actual window cancellation and departure.
That route ends at 15 HP with one Cell, retaining a pacing concern.
The [durable archive carry](plans/m07-m08-save-carry.md) continues into level 8,
Custodian of Record, without a continue refill. Version 9 retains actual mine
counts and strictly upgrades historical v2-v8 documents with exact-byte archives.
Owned client checks prove actual mine placement and mission-entry restoration.
The [level 8 prototype](plans/l08-custodian-of-record-prototype.md) retains its
Proximity Mine and repairing Auditor, with a separate practice entry. M09 is
not playable. Combined integration is tracked in
[PR #347](https://github.com/blisspixel/fragr/pull/347); fresh-player, difficulty
and final art acceptance remain open for every level.

**Multiplayer.** Deathmatch, team deathmatch, GoldenEye-style mutators,
capture the flag on three arenas, and [Sabotage](plans/sabotage-mode.md) on
Sector 9. In Sabotage, rule bots and agents play both sides, plant and defuse.
A recorded human session on two machines remains open.

**Presentation.**
- Two art passes ([1](plans/art-pass-20261002.md),
  [2](plans/art-pass-2-20261002.md)): coherent weapon frames with fire and pump
  frames, drawn pickups, health and armour icons, a redrawn Rifle, and
  per-weapon muzzle flashes and impacts.
- A [sound pass](plans/sound-pass-20261002.md): a layered 48 kHz Shotgun with a
  pump cycle, rebalanced guns, per-weapon impacts and enemy windup tells.
- An optional [frame counter](plans/frame-counter.md).

The [art excellence](plans/art-excellence.md) effort remains in flight. Its
October 3 production increment shipped in [PR #337](https://github.com/blisspixel/fragr/pull/337)
and v0.68.0. The [Low Water playthrough](https://github.com/blisspixel/fragr/releases/download/v0.68.0/fragr-low-water-playthrough-20261003.mp4)
shows the integrated assets in combat through mission departure.
The Sweeper now has a shaped articulated mesh source and a paired normal
atlas used by the live sprite presenter. Latch has a lean screen-faced live
model. Registered fixtures and recessed wall bays give existing rooms
physical detail; lit water adds moving surface normals and an exterior
river. Other bodies and much of the world still need model and art refinement.
The Shotgun has an original mesh and coherent pump poses, retained as a
development candidate while its first-person quality is refined.
The [October 3 model research](plans/art-excellence.md#research-checked-2026-10-03)
records available 3D catalog entries, laptop limits and the proposed pilot.
Nick subsequently reported a $100 API top-up and authorized the $105.88
available for Higgsfield assets. The new [API
checker](plans/higgsfield-pipeline.md#api-capability-checker-2026-10-03)
verified image pricing with the existing key; exact 3D API routes and prices
remain unresolved. The separate production batch uses the verified image
API for high-resolution references and material sources, with local meshes
providing actual geometry. The research itself submitted no generation jobs.

**Spend, 2026-10-02 round** (Nick authorized $20):
- Higgsfield: about $5.82 of prepaid credit by estimate, across 58 completed
  requests in art passes 1 and 2.
- ElevenLabs: included plan credits only, about 2,740 estimated for the sound
  pass.
- No new cash charges.

**Spend, 2026-10-03 asset effort** (Nick authorized $105.88 of available API
credit): 151 completed image requests, $93.365 in preserved request estimates,
with no unresolved jobs. Nick subsequently reported $14.42 remaining in the
API dashboard, implying a $91.46 net balance decrease from the reported starting
balance. Aggregate balance is reconciled to that report; individual request
charges are not independently verified. The [production spend record](../client/art/production-20261003/spend.json)
contains each batch. The subsequently authorized model pilot consumed 125 net
credits, followed by 40 for the new stylized Clerk source and rig. The live
account checker initially reported 2,905 credits, with the original 15-credit uncertain
local hold retained. A separate 30-credit account decrease is not attributed
to local production receipts. The October 4 four-character model/rig batch used
160 existing credits and its subsequent free check reports 2,745 available,
with the same 15-credit hold. Source preparation and played acceptance continue
under the [cast plan](plans/cast-model-buildout-20261004.md). No new cash charge
or cloud apply ran.

**Shipped and proven on the tip:**

- Rust authoritative server at 20 Hz with hitscan combat, respawn, round scoring, six maps with heightfield movement, weapon and health pads, a mid-round boss, and eight named rule bots with four behaviors.
- Godot 4.7.2 client as a thin presenter: boot menu, Solo Scrap, spectator director camera, human join and leave, first-person weapon face, HUD with killfeed and Host bumpers.
- MCP adapter with `join`, `leave`, `observe`, `act`, `speak`, `get_events`, `round_state`, plus a scripted bot. Unknown action fields are rejected. Speak is rate limited.
- Decision-brain agent (`agents/brain`): a fighter whose stance, weapon, and danger read come from Jev (TypeSafe natively or through OpenRouter) at up to five decisions per second while a local controller plays every tick. Paid providers refuse to start without an explicit cap; every call is estimated, settled, and ledgered. Local rules play for free and CI proves that path.
- CI on Linux: fmt, clippy with warnings denied, tests, deterministic benchmark and budget checks, the agent playtest smoke with thresholds, an unfiltered 90 percent line coverage floor, release build, cargo-deny for licences, bans, and sources, and headless Godot checks. Windows and macOS also pass workspace tests and Godot checks.
- Live tip screenshots, a one-command Solo Scrap launcher, self-host guides, and plan-only GCP Terraform.
- v0.34.0 through v0.45.0 are recorded in [the changelog](../CHANGELOG.md). In short: Recall Notice's routes, exit, optional supplies and durable local runs; connection and frame caps; `GET /status`; join tickets; pawn resume; player-facing gun names and cycling; campaign-aware agent control; and bounded spectator delivery. The README stills show current play.
- v0.46.0 through v0.57.1 (2026-09-24 to 26): host hardening (idle pings, kicks, ban and allow lists, an audit log), localized kick messages, downloadable Windows, Linux and macOS packages on every tag with an original icon, spawn cover on maps 3 to 5, the M02 fight graybox and 120 Hz input pacing, Doom-style ammo with a seven-pellet shotgun, the black and red Union with the Heavy Sweeper and the Turret on a test range, status health metrics with a soak harness, keyboard-only, mouse and gamepad controls with rebinding and aim assist, the first lighting pass, the M01 secret Shiv, a data-driven story scene player, host-chosen rule sets with team deathmatch and GoldenEye-style mutators, the salvaged opening stills, free local decision models for the reference agent, human or embodied agent bodies, and a round opening spawn shield.
- v0.58.0 through v0.67.0 (2026-09-27 to 2026-10-03): local pawn prediction, capture the flag on three arenas, campaign levels 3 to 6 and the standalone level 8 as development prototypes, counted grenades, the moving tram, living-body contact, the Sniper Rifle, Ranged Sweeper, Proximity Mine and Auditor, Sabotage, two art passes, a sound pass and the frame counter. The changelog has the details.
- Two developer-only generation pipelines: `tools/audiogen` for audio and `tools/spritegen` for art. Audio uses per-run estimate caps and requires quota reconciliation; art has durable request reservations. Neither replaces asset review. The first art slice produced twenty-four frames for sixty-nine cents, with surfaces rejected.
- The setting has three sides: the Union/Chancellery, free humans and conscious agents with agency, and the Inheritance. The Inheritance's ecological recovery and mass killing leave conflicting survivor perspectives, not a narrator's declaration that it is right. `docs/lore/` owns the world and voice; bodies do not establish who has freedom or whose suffering matters.

**Generated art and audio:** art passes 1 and 2 are integrated with manifests
(58 completed requests). The 2026-09-19 slice was judged unusable and is not
integrated. The sound pass is integrated, with a listening page in the backups
for Nick. Twelve Chancellery addresses remain under story and
language review. The old ten-part epilogue and the news/PSA/ad clips still ship
on the radio; a developer review tool that would have quarantined them was
never merged, and radio is now a minor part of the game. Two stills from an
earlier opening batch are in the M01 opening ([scene plan](plans/campaign-scenes.md#salvaged-opening-assets-2026-09-26)).
The old radio-only ending cannot be integrated as the new campaign's actual ending.
No balance endpoint was documented in the checked API sources. Nick reported
$8.08 before art pass 2 and $105.88 after the October 3 top-up; the latest
allowance is recorded above.
The October 3 aggregate balance is reconciled to Nick's reported $14.42;
individual request charges remain unverified.

**Not built yet (honest list):** low-latency transport (WebSocket JSON only; local human prediction shipped in v0.58.0), campaign-actor timeline interpolation and bounded lag compensation, a complete protocol migration policy (geometry and gameplay admission exist), unlimited lifetime statistics, progression, DJ bumpers and a voiced Host, a finished single-player campaign or full co-op lifecycle, a complete art pass, public-server load tests, any cloud apply, general vehicles beyond the bounded authored tram and recall cars, Rescue and combined-arms modes, levels 9 to 20, the planned console, Ultra graphics and the player-facing rendered benchmark, wider directional combat acoustics, a finished modelled cast and complete environmental kits. `GET /status` on the game port is a host probe in the current line of work, not an in-app server browser and not a web client. M01 has a developing discovery/combat/mission slice; Episode 0 remains a separate arena prototype. A deterministic local benchmark and developer rendered tour already exist; neither establishes public-server readiness. Frame caps, connection caps, and the inbound message budget shipped in v0.35.0.

**Decided 2026-09-25:** the campaign is twenty levels in five episodes, per the
[expansion plan](plans/campaign-expansion.md), now the contract in
[CAMPAIGN.md](CAMPAIGN.md); the wipe splits into three levels with their own
clocks; continues refill to three at the start of each episode; five
introductions moved (the Jammer out of M02); the campaign has no carry cap
([readable arsenal](plans/readable-arsenal.md)); and mutators are host
settings from the start, not unlocks, per the
[replayability plan](plans/replayability.md#the-flagship-rescue-and-sabotage). **Decisions
waiting on Nick:** from the [multiplayer maps proposal](plans/multiplayer-maps.md),
three new pickups. The Cells cap rose to 100 in v0.55.0.
Resolved 2026-09-26: the map 5 opening spawn flake (v0.57.1 shields the round opening like a respawn) and the local open-weights decision model (v0.56.0, measured too slow on a laptop at about 12 s per decision; see [the plan](plans/brain-local-model.md) for next measurements).

## What is next, in order (as of 2026-09-26)

The current sequence is the [full build order](#full-build-order-2026-09-27) below. This section records increments that already shipped. It is not the queue.

**Active milestone: [local excellence](plans/local-excellence.md).** The first
increment shipped in [v0.15.0](https://github.com/blisspixel/fragr/releases/tag/v0.15.0):
saved callsigns and reticle/bob preferences, pixel menus,
first-person spectator follow, three prepared viewmodels, authoritative geometry
for late spectators, aim preservation, and reliable weapon selection. It also
removes name-based session eviction and strengthens the client checks. The plan
records local tests, inspected OpenGL/Vulkan captures, CPU measurements, and the
remaining gaps. Windows/macOS CI joins Linux verification. Integration and release
history establish shipped status. This is an active full-game build-out, not a
finished campaign or final art pass. No paid calls were made for this increment.

The [benchmark increment](plans/showcase-benchmark.md) shipped in v0.16.0 with complete
recordings and explicit CPU/serialization accounting. Its contract lives in
[`BENCHMARK.md`](BENCHMARK.md). A rendered GPU benchmark, authored world art, and
finished campaign encounters remain open; headless numbers do not establish them.

The [GPU bot evaluation](plans/gpu-bot-compute.md) investigates portable Rust
compute for batched perception and optional local inference. Profile and measure
total latency, transfer cost and contention with rendering before adoption.
CPU-only hosting remains supported. This is planned work, separate from the
rendered benchmark and from remote decision-model calls.

The [arena surface pass](plans/arena-surface-pass.md) shipped in v0.17.0: authored pixel
materials, clearer industrial structure, scenery outside the playable boundary,
and normal fighter scale in eye views. This preserves server-owned collision and
does not turn the existing arena layouts into completed campaign maps.

The [player settings pass](plans/player-settings.md), shipped in v0.18.0, connects saved controls,
display, and audio to their runtime readers through the same retro panel at the
front menu and in a live match. It also fixes resolution-dependent mouse input.

The [default mix and splash correction](plans/audio-startup-polish.md) is
shipped in #201, v0.32.0: quieter default effects, more present playing radio, saved
choices preserved and the refined logo replacing the stale ON AIR startup image.
The [display-quality pass](plans/display-quality.md) adds resolution selection and
portable graphics presets, implemented in #202 with inspected Windows/AMD Vulkan
and OpenGL evidence. Cross-platform CI gates integration. Pixel surfaces and
readable authored lighting remain the style.

[Asset request recovery](plans/asset-request-recovery.md) shipped in #169 with
cross-platform failure tests. Submitted jobs survive interruptions, and
authenticated polling is bound to the official API origin. Reference preparation
and consistent animation production remain separate work.

[Vertical aim](plans/vertical-aim.md) shipped in v0.19.0, connecting camera pitch
to authoritative hits and cover, agent targets, and spectator views.
[Shot impacts](plans/shot-impact-feedback.md), shipped in v0.20.0, add world
feedback and repair combat accounting when fighters trade kills in one tick.
The [navigation pass](plans/height-aware-navigation.md) shipped in v0.21.0:
shared routes, reliable jump taps, repaired stair entrances and grounding, ledge
exits, anchored moving weapons, and occupied spawn avoidance. Actual server
traversal and mixed-role session checks cover all six maps; separate first-person
tours inspect movement and weapons. The expanded network matrix caught crowded
join failures and now runs in CI. The first GitHub run additionally found a map-3
planner stall and map-5 spawn-death failure despite the local pass. Deterministic
regressions reproduce both failures; route recovery and cover-aware spawns pass
local verification and the final Linux matrix. Every CI job passed before merge.

[Shared body integration](plans/shared-body-integration.md) shipped in v0.21.1:
live movement and the accelerated shared step use one collision/gravity path,
preserving existing match traces. Fixed-map startup also avoids preparing unused
navigation maps. [Enclosed campaign geometry](plans/campaign-spaces.md) shipped in
#176 for real ceilings and overlapping floors. [Authored maps](plans/authored-campaign-maps.md)
now brings M01's connected blockout, indoor spawns and institutional surface kits
through the live server. [M01 discovery](plans/m01-weapon-discovery.md) now adds
fists, recovered Tack/Flechette, finite ammunition (one count per type and no
reload since [boomer ammo](plans/boomer-ammo-and-pellets.md)) and individual supply
claims. The [intake encounter](plans/m01-intake-encounter.md) shipped its prototype in #182:
bounded authoring, allied participants and Clerk/Sweeper server phases have local
tests, including live wire admission. The draft M01 now places a guarded
confiscation threshold and two bots approaching from below records. Both routes
have finite-equipment combat tests and rendered client runs. Original directional
human/bot sprites now follow walking, attack, pain, melee and death state, with
source and bake verification. OpenGL main-hall and Vulkan maintenance captures
are inspected; a second spectator client follows the live human run. Finished
character/encounter presentation and fresh-player pacing review remain pending.
The [facility detail pass](plans/m01-facility-detail.md) adds bounded face panels,
keyed world signs, issued lockers, service vents and practical lights to this
prototype. These identify the rooms without adding client-only collision.
The [mission sequence](plans/m01-mission-sequence.md) shipped in #184 and v0.26.0:
physical transfer-record use, a real lift gate, four-participant admission and
shared deliberate departure. M01 tests exercise both routes through combat and
departure. Local rendered, live party and six-map multiplayer checks pass;
two- and four-participant live runs pass, and #183 is closed.
[Direct local campaign entry](plans/local-campaign-entry.md) shipped in #187 and v0.27.0:
Recall Notice starts an owned loopback server from Single Player, with cancellation,
clear failures and cleanup on leave. Local checks, inspected gallery and all five
pre-merge CI jobs passed. Post-merge Linux exposed a scheduling assumption in the
mission wire test. Its stronger [repair](plans/mission-wire-order.md) then caught
a real join race: broadcasts could overtake initial geometry. The fix shipped in
#189 and v0.27.1, gating broadcasts until each connection's initial map is queued.
Local regressions, mixed-map sessions, inspected gallery and all five pre-merge CI
jobs pass. One intermittent gallery exit error remains recorded in
the plan without a claimed fix. Run recovery,
full encounter population and finished art remain. This
foundation is not a finished campaign or proven co-op balance.

[M01's opening and readiness](plans/m01-opening.md) shipped in #193 and
v0.28.0, closing #192. Five keyed text panels establish Latch's recall,
offer back/next/skip and replay, and hand off through server-owned party readiness.
Late readers cannot pause combat or participate until ready. The MCP adapter
exposes the same explicit acknowledgment. Finished scene illustrations, narration
and movies remain separate production work.

[Opening spawn placement](plans/opening-spawns.md) shipped in #175 and v0.21.2.
Warmup joins now use the same cover selector as active joins and respawns. The
six-map playtest exposed the gap; its thresholds remain unchanged.

The recurring Tripoint opening failure was repaired in #193 and v0.28.0,
closing #194. The [spawn safety plan](plans/tripoint-spawn-safety.md) records
the reproduced exposed-ring layout, 16 new cover pockets, walking regressions,
network comparisons and inspected captures. These checks establish safer
openings, not a finished map or a universal respawn guarantee.

The [M01 completion work](plans/m01-completion.md), tracked in #195, expands the
records wing into reception, stacks, bypass, sorting and dispatch with twenty
preplaced guards and finite campaign stock. The records-wing increment in #196
passes full rendered OpenGL/Vulkan routes with twenty named defeats and departure,
plus deterministic encounter/sightline checks and the six-map network roster.
This remains a development mission. Solo M01 now has three explicit mission-start
continues, entry restoration and exhaustion under the [recovery plan](plans/campaign-continues.md).
Final art, full mission pacing and fresh-player acceptance remain open. The requested shared level kits, distinct
enemy combinations and difficulty/achievement cosmetics have homes in
`MAP-DESIGN.md`, `ENEMIES.md` and `plans/difficulty-and-rewards.md`.
The current campaign contract targets a four-hour successful solo run: twenty
levels in five episodes, a substantial three-level wipe survival finale and a
short conditional epilogue. The initial survival target is about 33 active
minutes split across those three levels, to be tested through changing
encounters and routes. Free-agent friends secure a local reprieve;
survival unlocks playable aftermath. Exhausted failure ends with its own credits.
Both endings show surviving free beings, the Union's end, a healing Earth and a
brief hint of alien, dimensional and vastly powerful beings beyond this conflict.
Death can spend a limited continue to restart the current
level with its starting equipment; three continues, refilled at the start of
each episode, is the decided allowance. No mandatory duo, companion controls,
revival or all-mission co-op. Autonomous allies and level-specific viewpoints
are design options.
Cross-mission recovery and disk saves remain unbuilt under #195. The local service
record now retains 256 campaign, arena and practice observations, with authoritative
counters, separate attempt effort, JSON export and optional localized quips.
Local verification passes under [#199](plans/benchmark-and-stats.md): authoritative
count tests, recoverable history, inspected campaign/arena results, full client
checks and the six-map mixed-client roster. The [combat feed](plans/combat-notification-polish.md)
also moves routine notices to three expiring corner entries and removes other
players' frag/streak camera shakes. Round summaries remain separate.

The revised level plans place simple doors, switches and lifts in working spaces,
and a later combined-arms vehicle showcase in level 14's launch works. General moving
lifts and vehicles remain unbuilt. The Sniper Rifle, Grenade and Proximity Mine
have implemented development roles; the Remote Mine and Rocket Launcher remain
planned campaign finds in [the readable arsenal](plans/readable-arsenal.md). Gold
finishes and curated weapon colors are cosmetic-only achievement directions
under #197.

The phases below are the long shape. The sequence that follows is the build order. Each rung is there because the rung before it is what makes the next one true. A green harness is not a finished mission. A scripted clear is not a fresh player.

## Full build order (updated 2026-10-04)

**Active goal:** build the agreed game through a proven 1.0. That is Recall Notice as the quality bar, then each later mission on systems the whole campaign reuses, then local prediction before the first long Rail lane, then the wipe and its conditional epilogue, then a LAN proof, then an exposed server. Cloud apply, matchmaking, and conquest-scale vehicles stay behind that server. The story spine in [`CAMPAIGN.md`](CAMPAIGN.md) is settled. Names, rescue tradeoffs, wipe operations, and the reprieve's exact terms stay proposals until the gate that needs them. Mission briefs live in [`CAMPAIGN-MISSIONS.md`](CAMPAIGN-MISSIONS.md) and [one plan per level](campaign/README.md). Geometry comes from the mission, not from an arena layout. The six current layouts stay playable foundations. Boltgun remains the visual bar for a played sequence, not a reason to generate the roster before the first two enemies read. Every rung serves the [easy to pick up, deep to master pillar](VISION.md#easy-to-pick-up-deep-to-master): fights and flow first, at most three doors a level.

**Next, as of 2026-10-04.** The order is set by what most raises fun and
quality for the work. Nick authorized parallel game development alongside
substantial model production. M04 roofs, combat feedback, campaign results and
the first cast increment shipped in v0.71.0; loading-first shipped in v0.71.1.
The current release is [v0.73.0](https://github.com/blisspixel/fragr/releases/tag/v0.73.0),
including the M09 prototype, refined Pistol and hatless civilian. All eight
main CI jobs and three tagged desktop package checks passed; uploaded digests
match the checksum manifest ([release receipt](evidence/release-v073-20261004.md)). Current independent
lanes are Jammer and precision-weapon craft, the Repeater foundation, Kitchen and Garage. The
[M09 prototype](plans/m09-passenger-manifest-prototype.md) has a complete
27-state, 21-guard structural combat route and strict archive-to-berth carry
passing locally; final hull art, shortcuts and fresh-player acceptance remain
open. The prototype is on main through [PR #354](https://github.com/blisspixel/fragr/pull/354).
The refined Pistol and hatless civilian are on main through
[PR #353](https://github.com/blisspixel/fragr/pull/353) and
[PR #352](https://github.com/blisspixel/fragr/pull/352), with complete local
client checks, all eight CI jobs and all three desktop package checks passing
on their reviewed heads. The Rifle's accepted source and played comparison
passed complete local checking, all eight exact-head CI jobs and all three
desktop package checks. [PR #356](https://github.com/blisspixel/fragr/pull/356)
merged the selected art to main after v0.73.0 was published.
The corrected Jammer candidate consumed 35 included credits, passed mechanical
source inspection and continues through pixel baking and played acceptance.
The [precision weapon pass](plans/precision-weapon-references-20261004.md)
adds two inspected sources for 70 included credits; compact preparation and
selection remain open. Three [inhabited-world prop sources](evidence/world-prop-sources-20261004.md)
add an assembled scrubber, complete-port pump and civilian radio for 105 actual
credits, with all twelve raw views inspected. Local preparation and placement
remain open. The latest account check reports 2,375 available,
15 held and 2,360 usable, with 695 tracked credits consumed. Kitchen's
eight-pad route and actual four-fighter match pass, but its first-use white-wall
art defect remains unresolved. Garage's ordinary 15-state route passes with
no deaths; vehicle/surface craft and fresh human fun remain open. Shared
integration and art direction stay coordinated, and rendered tours take turns
on the same GPU. Every level, built or planned,
must pass the [maximum-fun checks](MAP-DESIGN.md#maximum-fun-first). Every
map follows [size follows the crowd](MAP-DESIGN.md#size-follows-the-crowd) and
the multiplayer [rule sheet](plans/multiplayer-maps.md#rule-sheet). Every
asset meets the [art bar](ART_STORY_BIBLE.md#north-star).

0. **Nick plays v0.73.0.** The current desktop release includes the new Clerk,
   sealed buildings, civilian finishes, restored level 7, the supported M09
   berth and Enforcers, refined Pistol, hatless civilian, loading-first and
   optional ten-seat Sabotage. Review the built campaign, Sabotage with
   bots and capture the flag, using the watch list in the
   [polish plan](plans/campaign-polish-20261002.md).
   *Why:* automation proved the routes work; only a person can say whether it
   is fun. Twenty levels built on an unproven loop would multiply its faults.
   Feedback informs acceptance and refinement. Authorized local development
   continues while that feedback is pending; this is not a stop gate for code
   or art trials.
1. **Finish what is started.**
   - The restored level 7 and its strict M07-to-M08 carry are integrated through
     [PR #347](https://github.com/blisspixel/fragr/pull/347). Its full 29-state
     route and actual local carry/mine/retry checks pass. Keep the low-health
     rim crossing on the fresh-player pacing review.
   - Land any parked art.
   - [Campaign results](plans/campaign-results.md) shipped in v0.71.0:
     actual mission kills, secrets, deaths and elapsed server time, with a real
     M01 completion and onward save. The selected slice shipped with the combined
     main integration of [PR #348](https://github.com/blisspixel/fragr/pull/348).

   *Why:* two levels are nearly done, and finishing beats starting.
2. **The feel layer.**
   - [Directional combat audio](plans/directional-combat-audio.md): near-miss
     cracks, a damage arc, occlusion. The first bounded slice shipped in v0.71.0
     with [real shot evidence](evidence/directional-feedback-20261004.md),
     finite-ray cue placement, covered closest-point suppression and pixel
     damage bearings. Wider room acoustics and listening acceptance stay open.
     The selected slice shipped with the combined main integration of PR #348.
   - Then [console](plans/console.md) phase 1: practical commands, voices
     and jokes, client only.

   *Why:* being shot at must read by ear and eye, which is the fun bar's
   three-signal rule. The console is cheap, client-only depth.
3. **[Art excellence](plans/art-excellence.md), in flight.** The
   [full-game asset catalog](plans/meshy-full-game-assets.md) records individual
   lore/reference briefs, retained sources, local construction kits and priced
   model candidates beneath this rung. Its first production allocation is
   bounded to 900 existing credits including revisions and suitable rigs;
   larger catalog totals are estimates, not generation orders or finished art.
   [native 3D pilot](plans/meshy-pipeline.md) verifies live credit before paid
   model stages and proves imports for one enemy, weapon and prop plus a
   topology comparison. [Rendered evidence](evidence/meshy-pilot-20261003.md)
   records skin motion, 125 net credits consumed and 15 held conservatively.
   [Clerk presentation](plans/clerk-model-presentation.md) shipped on main in
   [PR #340](https://github.com/blisspixel/fragr/pull/340):
   prepared skin and gait, authored combat poses and paired normals pass local
   checks, full CI and bounded M01/M02 played routes. Broader art acceptance
   stays open. Desktop packages use the tag's release workflow.
   Nick rejected photographic human treatment and requested stronger black/red
   recognition. The [Union field uniform revision](plans/union-field-uniform.md)
   starts from a new deliberately stylized reference, rather than recoloring the
   previous face. The shipped rig remains useful; the old look is not final art.
   Its replacement source, directional atlas and clean guard-room replay are
   [shipped on main](evidence/union-stylized-20261003.md) in
   [PR #346](https://github.com/blisspixel/fragr/pull/346), consuming 40 existing
   model credits. Full local client checks pass 224 scripts and 103 harnesses;
   all eight implementation CI jobs pass.
   Black/red applies to issued outfits and equipment; civilian walls and lunar
   pressure shells retain place-specific materials.
   The [October 4 cast batch](plans/cast-model-buildout-20261004.md) produces
   coherent Sweeper, Auditor, free-human and Latch sources. All four candidates
   and rigs completed for 160 included credits. The new selectable civilian
   source and eight-cell strip pass focused checks. The Sweeper and Auditor
   have authored role poses and paired atlases; Latch uses a packaged live
   skin with gait and real palm attachments. Source and venue views pass
   locally; full route acceptance and combined integration remain distinct.
   The selected cast sources, live presentation and residential frontage shipped
   through the same main integration of PR #348. The full Auditor range and
   full M02 art route remain open; the pitch checker correction retains strict
   acknowledgements and does not change combat difficulty or outcomes.
   [West-court homes](plans/m04-residential-facades.md) add sealed domestic
   masses and varied roof edges; the full local M04 route retains all 28 guards
   and departure. Optional roof access and ordinary return also pass. Strict
   historical M04 saves bound to the old map hash remain incompatible.
   [M04 inhabited detail](plans/m04-inhabited-world-polish.md) shipped in
   [PR #344](https://github.com/blisspixel/fragr/pull/344), with a clean 26-state
   route. [M06 workmanship](plans/m06-world-workmanship.md) shipped in
   [PR #342](https://github.com/blisspixel/fragr/pull/342), with a clean 28-state
   route and full-client checks. Both have passing full implementation CI.
   The [M06 activity pass](plans/m06-port-activity-architecture.md) adds actual
   freight weighing, customs terminals, luggage inspection and records storage.
   Its complete 31-state structural route confirms all 21 guards, the Rail lane,
   Turret cancellation, prisoner route and departure. Separate final art views
   inspect pressure-case chamfers, grips, locks, gauges and measuring hardware.
   Full client checks pass; combined integration is tracked in PR #347. Wider
   room architecture and final art acceptance remain open.
   The separate [M04 enclosure pass](plans/m04-building-enclosure.md) addresses
   missing clinic/workshop roofs in
   the reviewed source from [PR #343](https://github.com/blisspixel/fragr/pull/343),
   consolidated into PR #347. A clean 29-state
   rendered route now passes all 28 guards, clinic release and actual departure
   with no deaths or HP lost. The [civilian surface pass](plans/civilian-surface-markings.md)
   removes inherited red warning paint from Low Water and lunar dwellings/decks
   while preserving issued black/red equipment. Its ordinary-input art subsets
   retain their own evidence, separate from the earlier complete routes.
   [Evidence](evidence/clerk-model-20261003.md) records
   actual guard-room frames and the limits of the routes.
   The October 3 production pass adds original Sweeper and Shotgun mesh sources, a lean
   screen-faced Latch, paired Sweeper normals, shallow manufactured fixtures,
   articulated wall bays, venue materials and lit moving water. The large
   high-resolution source library includes characters, weapons, props, materials
   and world references. References are not completed game assets. Finish
   the played quality comparison, refine the Shotgun's first-person presentation,
   and carry accepted model and material work across the remaining roster.
   [Shotgun source preparation](plans/shotgun-model-presentation.md) now separates
   an actual pump and attaches its support hand. Its candidate is rendered and
   mechanically checked; current first-person art remains selected until the
   framing, grip and played gate pass.
   Price each paid operation within the authorized $105.88 Higgsfield effort
   and $5 run cap; another paid service requires Nick's approval.
   *Why:* primitive characters and box rooms are the largest visible gap to the
   modern boomer shooters this game is measured against.
4. **The fun loop.**
   - Audit the twenty level briefs against the maximum-fun checks, and
     simplify what reads complicated.
   - Refine the shipped end-of-level tally: kills, secrets, deaths and time against par.

   *Why:* settle the loop and the briefs before levels 9 to 20 are built.
5. **[Graphics options and Ultra lighting](plans/graphics-options-and-lighting.md),**
   then the player-facing [rendered benchmark](plans/showcase-benchmark.md),
   which measures every preset.
6. **Multiplayer depth.**
   - [Optional 5v5 Sabotage](plans/sabotage-five-seats.md) shipped in v0.72.0:
     ten shared fighter seats, finite Pistol fresh starts,
     survivor carry, exact parked resume and localized full-room refusal.
     [PR #351](https://github.com/blisspixel/fragr/pull/351) records complete
     CI and package verification; human match acceptance remains open. Generic matches retain
     their existing limits and inventory policy.
   - [Competitive and community scope](plans/competitive-and-community.md):
     standalone 5v5 elimination and additional plant/defuse layouts remain
     planned. Sector 9 is built; Low Water and Custody Archive objective venues
     remain planned. Apply the linked classic
     map research and prove rotations, retakes and side balance in play.
   - Rescue.
   - The [vehicle](plans/vehicles.md) rungs toward the flagship island,
     [Holdfast Atoll](plans/multiplayer-maps.md#17-holdfast-atoll-new-the-flagship-island-working-name).
   - Liberation: humans and free agents cooperate against Union forces,
     starting with one connected Launch Works scenario and four allied seats.
     Vehicles, defenses and rescues reuse proven server systems. Larger
     rosters, reinforcement rules and the distinct Wipe wrapper need their
     own acceptance. These formats remain unbuilt.
   - Free self hosting and [community contributions](../CONTRIBUTING.md),
     with [non-invasive fair play](plans/fair-play.md), temporary host bans
     and planned optional bans for repeated confirmed abuse. Skill or agent
     control alone never warrants punishment.
7. **Network.** Bounded lag compensation and a recorded two-machine session
   before any UDP decision ([TRANSPORT.md](TRANSPORT.md)).
8. **Complete the campaign.** Refine level 9 and build levels 10 to 20 one mission at a time,
   following [the mission treatment](CAMPAIGN-MISSIONS.md) and its
   [dependency plan](plans/campaign-build-order.md), through the wipe and
   conditional epilogue. Carry the accepted art, combat and results approach
   through earlier levels too. Verify the whole saved run, episode refills,
   retries and retained outcomes. Each mission keeps its own acceptance gate.
   [Wipe survival](plans/wipe-survival.md) records the accepted larger M20
   climax and shared multiplayer direction. M18 interrupts ongoing Union
   holdout fighting with abrupt takeover; M19 carries escape. Continuous
   pressure, locally isolated equipment and a local reprieve preserve the
   ending. Detailed counts and mechanics are proposed; the shared multiplayer
   wrapper belongs to item 6 after its campaign systems are proven.
9. **Prove the release.** Close fresh-player, difficulty, input and visual
   acceptance; inspect performance on supported hardware; verify clean
   desktop installs on Windows, Linux and macOS; complete the twenty-four
   hour soak and the exposed-server public week. The 1.0 bar below is the
   final gate. Cloud work retains its separate spend approval.

The [integrated player review](plans/m02-integrated-player-gate.md) remains
available. Recording a fresh player's observations is the human half of item 0.

Ideas recorded for later: the [Outreach Unit](ENEMIES.md#ideas-not-yet-accepted)
kamikaze RV, and GoldenEye-style earned exemptions
([console](plans/console.md#a-decision-for-nick)).

No cloud apply, public-server claim or 1.0 controls claim follows from this
round. Spend for the round is in [Where we are](#where-we-are-2026-10-03). The
$0 local container host is documented for friends; public admission, cloud
cost and exposed-server testing keep their own gates.

The server-owned traveling-shot foundation is already on main
([plan](plans/traveling-shot.md)). The current buildout makes it a live Jammer
attack on a dedicated range and in the local M03 prototype. A range clear
alone does not satisfy M03's own mission contract or acceptance.

The CTF draft's five corrected six-a-side observations recorded 16 flag takes,
11 combat drops, four captures and one carry at the clock. Those were external
agents. Server rule bots already finish a two-a-side capture. A twelve-bot
Windows replay, seeds 40 through 44, scored 2, 2, 2, 1 and 2 captures and used
the full clock on every seed. Linux seed 40 stayed on that clock at 2 captures.
Frag totals are not a cross-platform lock
([plan](plans/ctf-rule-bot-escort.md)). The carried world label says the
flag is carried, offset onto the cloth, in v0.59.0
([plan](plans/ctf-carried-label.md)). A carried flag leaves the stand for a short grip in the carrier's hand, in
front of the body, and the empty stand dims, so the take reads at a glance
([plan](plans/ctf-flag-nameplate.md)). In first person that grip sits below the eye, so the carrier sees the side cloth and the stand words beside the weapon
([plan](plans/ctf-fp-carry.md)). A capture result sits on an opaque card, and the score stays readable in front of the home flag
([plan](plans/ctf-result-card.md)). While a fighter carries, the corner gives the distance and bearing back to that fighter's own stand, and a stolen flag gives the same compass to everyone else
([plan](plans/ctf-return-bearing.md)). Arena Duel and Directive 17 now have validated flag stands on that same side axis. Compliance Yard, Reclamation Gulch and Tripoint Works stay off capture the flag
([plan](plans/ctf-arena-routes.md)). Two-bot goals are unchanged. A controlled socket
gate proves a complete capture, while contested matches test combat and flag
replication. Neither gate establishes human or spectator clarity. See the
[carry evidence](plans/ctf-carry-episodes.md) and
[socket gate](plans/ctf-socket-smoke.md).

The live human Action-to-Ack baseline, 20 Hz movement step, full 3D Ack and
local pawn prediction are integrated in v0.58.0. A moving-combat WebSocket
probe recorded loopback correction, fallback, cadence and payload evidence.
Nine one-host Windows-to-WSL captures at 0, 40 and 80 ms added server-egress
delay kept prediction active while delayed p99 same-tick error rose to about
0.35 m ([measurement](plans/websocket-delayed-egress.md)). A two-machine human
session with the pellet Shotgun, controls, aim assist and a team round is next
before a 1.0 controls or UDP decision.

The [dedicated hosting plan](plans/dedicated-server-udp-and-hosting.md) includes
a $0 local container host. The cloud image host remains plan-only. Prediction
and the two-machine session precede a
measured UDP pilot, as described in [TRANSPORT.md](TRANSPORT.md).

The older rationale below and the phase tables are historical context, not a
second queue. Their former human-feedback prerequisites do not override the
2026-09-30 authorization. Spend restraint stays: no paid batch to paper over the
uncertain art reservation, no cloud deployment in this slice, and no server
browser.

Story between levels is a short audio cutscene on the scene player that now runs the M01 opening: a narration script voiced over at least one key image per scene, with captions, skippable, falling back to the text page when an asset is missing. Images through `tools/spritegen` and voices through `tools/audiogen` wait for frozen wording and Nick's go per batch with a cap. Video is much later, in [`plans/cutscene-film.md`](plans/cutscene-film.md). [`plans/campaign-scenes.md`](plans/campaign-scenes.md) holds the scene list, costs and gates.

Admission sits beside the mission rungs and does not close the M01 quality gate. v0.35.0 through v0.39.0 shipped frame caps, per-address caps, the inbound budget, `GET /status`, the app match line, join tickets, and a ten-second pawn resume. v0.40.0 lets the mission card leave after the introduction. v0.41.0 is the player-facing gun names. v0.42.0 is weapon cycling and four README stills. The Clerk and the Sweeper no longer share one outline in the unshaded atlases. A live Recall Notice run on 2026-09-22 confirmed the boot menu, host `127.0.0.1:6767`, fists then the pistol, the `+24 BULLETS` pickup, and the mouse wheel switching between those two guns. That live run saw a card return after the first one left, and key 1 appeared not to leave the pistol. A later owned M01 server check dismissed the five page story, repeated MapInfo without replaying it, claimed the pistol, and selected fists with a real key 1 event; both the private loadout and public snapshot confirmed fists. The eight second objective card is designed to return on a new mission phase, but the earlier sighting did not identify which card it was. The exact live conditions remain unproven. The server seam now has bounded outbound queues and a twelve-roster local spectator fan-out measurement ([plan](plans/bounded-spectator-fanout.md)); remote-network evidence remains before any higher cap. Optional M01 supply detours shipped in v0.44.0; the next mission rung is automated review, with human acceptance near 1.0. Paid enemy sheets were not bought.

Automated Jev playtests run alongside these rungs. Durable paid-call reservations shipped in [#218](https://github.com/blisspixel/fragr/pull/218). The free first-person watcher shipped in v0.43.1 ([plan](plans/agent-first-person-watch.md)). Campaign-aware questions, objective control, and authoritative outcome receipts shipped in [#223](https://github.com/blisspixel/fragr/pull/223). The bounded M01 timeline and terminal-record drain shipped in [#227](https://github.com/blisspixel/fragr/pull/227) before a capped OpenRouter trial. A final free Standard seed 67 watch departed on attempt 1 with a matching record, eight first-person frames and no paid calls. Standard seed 1 cleared in a later replay; Severe seed 42 both exhausted its continues and cleared on separate live runs with the same name and seed. These results expose sorting pressure and live outcome variance, not fresh-player comprehension. Human acceptance sessions remain near 1.0; automated evidence should continue to improve M01 and later missions in the meantime.

**1. Make M01's two routes a real choice, and prove a sloppy clear.** This is first because the records wing, the lift, and the three continues already exist. The bypass is its own encounter: reception's region does not wake it, and its ammo is not standing on the sentry. Both seeded routes still depart. A seeded bypass clear also departs after one Flechette magazine is fired into the bypass ceiling, without claiming the file-stack supplies, and without walking the west side of sorting. The east route now leaves all four file-stack guards alive. `files_a_return` closes the shot from the records approach, around (-18, 10.7), through the stacks doorway. The reception counter screen, the bypass lip, and a narrow stacks screen keep sorting and the bypass from being cleared early, without moving `stacks_sweeper` and without sealing `stacks_cross_aisle`. Seed 67, human control, `east_bypass_departs_with_all_stack_guards_alive`: 1639 ticks, 80 hp, 0 armor, 16 defeats, 101 shots. This seeded sightline debt is closed. Secrets, a new weapon, and disk saves do not belong in this rung. The next rung is the building explaining itself.

**2. Let the building explain itself.** The records deck now shows the custody lift before the records wing. The reserved opening (x=-5 to -1, z=12 to 13) is no longer filled: `office_front_sealed` is `office_front_sill`, y=3 to y=5, and the header still starts at y=6.5. `records_balcony_sees_the_lift_sign_but_not_the_transfer_guards` stands at (-4, 3, 9), on that deck between the public stair and reception, and sees the lift sign. A half-metre sweep of standing deck positions does not see `transfer_clerk`, `transfer_sweeper_west`, or `transfer_sweeper_east` at 0.2, half height, or full height. The walk from `records_balcony` to that stand stays on the deck, and the walk on to reception does not enter the transfer office. `m01_routes_use_ordinary_actions_through_the_live_session` passes. Seed 67, human control, `east_bypass_departs_with_all_stack_guards_alive` is unchanged: 1639 ticks, 80 hp, 0 armor, 16 defeats, 101 shots. `m01_main_and_maintenance_approaches_clear_with_discovered_equipment` still departs for human and agent control. Public stairs: 1765 ticks, 100 hp, 19 defeats, 92 shots. Maintenance: 1833 ticks, 100 hp, 20 defeats, 117 shots. `MISSION_DEPARTED` now states the correction ward and that this mission ends here. It no longer calls the result a prototype. The current local campaign match menu says Exit to Menu retains the saved run, while continues are not refilled. Arena and joined matches keep "LIVE MATCH. FIND COVER FIRST." `test_mission.gd` and `test_frontend.gd` passed headless on Godot 4.7.2. Reception stays bone enamel on green records tile. The file stacks keep that tile and use service-steel walls. Sorting stands on concrete. Dispatch stands on service steel. The lift face stays the lift panel. These are registered surfaces only. A local tour on 2026-09-22 (`client/qa/m01-rooms.json`, frames under `.agents/qa/m01-rooms/`, not published) shows the balcony opening, bone reception on green tile, dark steel stacks on that same tile, grey sorting concrete, and a dark dispatch floor. Sorting and dispatch still share the bone wall. That inspection is not a finished art pass. Running from the Godot executable still shows the engine icon in the Windows taskbar.

**3. Two readable enemies, before any new paid art.** Done as a local rebake, not a purchase. The atlases are unshaded. At rest the Sweeper is wider than the Clerk. While aiming, the Clerk's pistol clears the shoulder and the Sweeper's rifle stays inside the pauldrons. `test_enemy_animation.gd` checks those outlines. The uncertain Clerk reservation was not replaced. A later albedo sheet can lock to this silhouette. It is not required to keep going, and tile batches stay forbidden until a local seam check exists. Recall Notice still uses the facility fill in `arena_sky.gd`. An unknown map name still falls through to the scrapyard.

**4. Optional detours, then secrets.** The confiscation alcove and maintenance overlook are walking detours with optional supplies; ordinary routes leave them unclaimed. This static slice [shipped in v0.44.0](plans/m01-optional-supply-detours.md). Neither holds the objective, the ward name, or a required gun. The [secret Shiv](plans/m01-secret-shiv.md) now lies in the alcove's south pocket: a pool-less melee grant, found by walking in, counted in the service record, never needed for the clear. No moving wall panel: the alcove is open, and a hidden room would spend part of the three-door budget. The imperfect-aim supply check still stands. Finding either detour or the Shiv is not part of the clear in rung 1.

**5. Prove M01 with automation, retain the fresh-player gate for later.** Run varied seeds, bodies and difficulties through the live server, inspect first-person agent captures, and check route choice, survival, encounter variety, readable objectives and regressions. Record failures and corrections in [`plans/m01-completion.md`](plans/m01-completion.md). Then continue building the campaign and multiplayer. Near 1.0, run one unsteered human session with radio and voice muted: the player can say who was taken, find the flank, tell the two enemies apart, and reach the lift. Record their words, deaths and stalls. If they needed a hint, that acceptance gate stays open. Automated clears do not satisfy it. Aim stays the shipped mouse-frame look. Prediction, projectiles, a sniper, grenades, mines, and vehicles are not required for M01's automated review.

**6. Finish M02 on the durable run and objective seams.** The versioned local run file shipped in v0.45.0. It resumes M01 at mission entry without refilling continues or rewinding live state, and records departure without pretending the campaign is over. The [M02 foundation](plans/m02-objective-gates.md) validates authored objectives and precomputed gate worlds, advances them on the server, and publishes optional mission state to Rust readers. M01 content and capability 8 remain regression fixtures. The bundled ward development map (gallery, guard room, stair, antechamber, ward, processing floor, loading dock) began with an open route; the optional side-ward draft closes the ward exit until Latch is released. Its Latch release draft uses ward arrival, guarded local Use at the frame, then dock arrival. `--local-mission persons_unknown` serves it as a development child with no run file; Single Player has a development entry. The original three-fight, nine-enemy graybox had solo human and agent clears, a wipe reset and a rendered tour. The [Shotgun introduction](plans/m02-shotgun-introduction.md) added a two-Clerk first fight for eleven enemies; the [stair-top guard room](plans/m02-guard-room-at-stair-top.md) placed that fight and gun before the descent, added a seated opening posture, and required gameplay capability 15. The [Crawler draft](plans/m02-crawler-descent.md) adds a lone low-body leap after the guard room, then three Crawlers with a Sweeper on a later landing, bringing the authored roster to sixteen. It adds gameplay capability 16, a distinct atlas and a captioned spatial warning. Seeded clears prove the changed route and retry; a full first-person tour captured the lone warning, leap, recovery and departure, and a detached observer frame shows all three Crawlers with the Sweeper. These are authoring checks, not fresh-player acceptance. The Godot client shows one keyed objective line. The Latch release draft replaces proximity-only arrival with ward victory, a local Use and server-owned state; the client shows a provisional fixed ward scene. The [run carry draft](plans/m01-m02-run-carry.md) promotes a validated M01 save to M02, preserves its body, equipment and remaining continues, and anchors M02 retries at its own entry. The [gallery first-view draft](plans/m02-gallery-first-view.md) opens a standing view from the primary entry to Latch's frame while that entry keeps the ward guards covered and the Crawler stair route intact; rendered frames establish visibility, with fresh-player recognition still open. The [natural entry draft](plans/m02-natural-entry-composition.md) turns only the primary spawn facing toward that frame and compares unforced first-person arrivals; Latch remains small, so recognition is still open. The [Notary tableau draft](plans/m02-notary-tableau.md) adds one unreachable, noncombat level 2 sighting behind ballistic glass and requires capability 22 so older strict surface readers are refused before MapInfo. Its rendered glass and shot check are authoring evidence; player recognition remains open. The independent M02 development child remains available. Levels follow the fights-first, few-doors, readable-without-English rule in [`MAP-DESIGN.md`](MAP-DESIGN.md). M02 acceptance still requires integration of the stacked run carry, Latch escape, floor gantry, side ward and maintenance circulation drafts, followed by unsteered player review of the Crawler lesson, Latch reunion, floor balance and route readability. The Jammer first appears in level 3. M02 is incomplete until route, retry, presentation, encounter and fresh-player evidence pass; Latch is not a second player.

**7. Build levels 3 to 5 of Episode I in order.** Level 3, Scheduled Service, uses the rail yard and introduces the Jammer while Latch helps free captives from sealed cars. Level 4, Notice to Vacate, makes the home district and the Notary threat memorable before the wipe. Level 5, No Forwarding Address, introduces the grenade against the Heavy Sweeper and carries rescue outcomes into the Moon departure. Each level needs its own route, encounter, retry and presentation evidence. The accepted designs are in [CAMPAIGN-MISSIONS.md](CAMPAIGN-MISSIONS.md); no older M03 district or M02 Jammer brief overrides them.

**8. Add the next level's capability when its encounter needs it.** Keep every found weapon for the run, with no carry cap. Before a deliberate long Rail lane, complete and measure local prediction, reconciliation, interpolation and bounded lag compensation over the existing WebSocket path. Compare UDP only after that baseline and a two-machine session, per [TRANSPORT.md](TRANSPORT.md). Later weapons, vehicles, flying enemies and the three-level wipe follow their accepted level designs one at a time. No vehicle or cloud fleet work is a prerequisite for Episode I.

**9. Promote audio and replace provisional art only after acceptance.** M01 ships on the committed library. Candidate shows and replacement effects stay out of the game until a listening pass, a canon check, and an in-game mix. Generating the rest of the roster before the first two enemies read is how the art drifts. Published stills of this work stay labeled as the development mission until rung 5 passes.

**10. LAN, then the exposed server, then 1.0.** A two-machine session on the predicted sim, with humans, rule bots, and an agent. Then join control, rate and size caps, protocol rejection, reconnect, a status endpoint, and desktop binaries that boot to a fight. Measure WebSocket under that load before any UDP spike. The six-map mixed roster once passed while reporting 3, 4, 3 and 1 spawn deaths on maps 3 through 6. Opening lanes on maps 3 to 5 caused most of them; spawn pockets and a lane count bounded by rail reach took sixteen local runs from 47 spawn deaths (32 at the opening) to 7 (none at the opening), and the playtest now fails more than one opening spawn death per round ([plan](plans/spawn-quality.md)). Respawn deaths after fighters walk out of cover remain. The exposed-server exit is a public week. Version 1.0 is the full agreed run, the measured control numbers, no placeholder art, the fun bar on a recorded multiplayer session, a soak, and those binaries. The Host bumper, the podium, and a killfeed beat every thirty seconds are the multiplayer exit. They are not requirements inside M01, which ends at a lift. Cloud apply stays plan-only until that public week is real.

Held until the rung that names them: alien combat, the Inheritance strategy mode, campaign co-op as a requirement, arena sidearm trickle, and any vehicle beyond the jeep, motorcycle and jetpack. No vehicle work sits in the near-term sequence; each of the three waits for its mission in rung 8. A conquest mode is Phase 4.

## Phase 0: Foundations that make everything else cheaper

Status: **in progress**. Small, high-leverage, mostly tooling.

- **Standards.** `AGENTS.md` refreshed; workspace lints in `Cargo.toml`; CI actions on current majors; coverage tool installed as a prebuilt binary; dependency advisories checked in CI. Shipped with this roadmap.
- **Godot in CI.** Shipped: the `godot` CI job runs `tools/godot_check.sh` (import, parse every script, the radio and far-cam harnesses).
- **One source for the wire.** Shipped: the adapter, the playtest harness, and the brain agent all read the wire types from `fragr-server`, so a protocol change is edited once and the compiler finds every reader. The adapter's hand-kept mirror is gone. Extracting a standalone `fragr-protocol` crate is optional tidying, not a correctness need.
- **Dev audio pipeline.** `tools/audiogen` generates sound effects and music through the ElevenLabs API for developers only, writes assets plus a manifest, and never runs in CI or at player runtime. Shipped, including speech, multi-voice dialogue, credit estimates, and wave controls.
- **Rust and GDScript only.** The procedural Python audio generator is retired; effects come from the audio pipeline and the committed files are the fallback. Shipped. The last Python file, the jammer tip screenshot gate, is now `tools/tip-gate` in Rust, called by `tools/capture_tip_screenshots.sh`; it gives the same verdicts and exit codes as the Python it replaced on the committed stills.
- **Sprite and texture pipeline.** `tools/spritegen` generates art through the
  Higgsfield API for developers and reduces it locally: alpha trim, area reduction,
  palette quantisation, and hard alpha. Explicit capped estimates precede new
  submissions. The original completed-only ledger did not safely recover every
  interruption; [request recovery](plans/asset-request-recovery.md) closes that gap.
  Historical costs and current operating steps are in `plans/higgsfield-pipeline.md`.

  The house style was settled by experiment rather than by taste, and the answer was counter-intuitive: **ask the generator for the stylised sprite, never for a photoreal render to be shrunk later.** Boltgun, Prodeus and Doom all pre-rendered detailed models and reduced them, but their artists controlled the contrast of that render and a prompt cannot. A photoreal prop is lit photographically, holds a narrow band of values, and turns to mud at sprite scale.

  Remaining: reference preparation and consistent animation, seamless tile checks,
  normal maps, and production atlases/import presets.

- **Generation providers.** Higgsfield and ElevenLabs are developer integrations.
  Code-native surfaces/effects remain valid. Paid calls never run in CI or at
  player runtime; offline tool tests do run in CI. Shipped.
- **Headless integration smoke.** Shipped as `tools/playtest` (#95): boots the server in-process, connects reflex agents over the real wire, runs a round, and asserts thresholds on every PR.

## Phase 1: Local excellence (offline play, approved asset production)

Status: **in progress**. This phase decides whether the game is fun. Everything here is validated on one machine against bots, in single player, and through the agent adapter.

1. **Movement and gunfeel.** Parameters and the two defects the research found (a default mouse sensitivity about six times Counter-Strike's, now fixed, and weapon "spread" that is deterministic aim forgiveness rather than dispersion) are in `plans/gunfeel.md`; the netcode plumbing is in `plans/buttery-controls.md`. Original brief: Acceleration and friction that reward strafing, air control, a jump, weapon switch timing, recoil kick, hit reactions on the target, and screen feedback on the shooter. Evidence: a playtest checklist in `plans/` with numbers, tip screenshots, and a short recorded clip.
2. **Boomer shooter look pass.** Render the world at a low internal resolution and upscale with nearest filtering, limit surfaces to the locked palette with dithering, rebuild fighter sprites with eight facing directions and walk, fire, pain, and death frames, rebuild weapon view models with idle, fire, and bob frames, add muzzle flash and impact frames, and lay the HUD out on a grid so nothing overlaps. Level surfaces get a coherent tile atlas with baked lighting and trim. Plan: `plans/look-pass-boomer.md`. Evidence: regenerated tip screenshots and an updated art bible.
3. **Sound and music.** Radio is a small optional flavor, never a pillar and never
   a priority ahead of campaign or multiplayer gameplay ([VISION.md](VISION.md)).
   A developer audio review tool (MP3 listening, local transcription, lore
   checks and reversible culls) was built on an unmerged branch and dropped on
   2026-09-26: it needed a GUI stack, an audio playback crate, external
   transcription and model runtimes, and unmerged changes to `agents/brain`,
   which is too much surface for a minor feature. Old recordings are reviewed by
   listening against [voice.md](lore/voice.md) when radio work resumes. The initial library
   shipped (#97, #99, #100): seven music stations with twenty tracks each, forty
   talk clips, three news beds/stings, basic effects and station switching/ducking.
   This is not a finished sound pass, and it does not gate the campaign or
   multiplayer rungs. [Radio refresh](plans/radio-refresh.md) replaces the old
   arena-heavy editorial direction with four sustained optional talk formats and
   music from an inhabited world. The [2026-10-02 sound pass](plans/sound-pass-20261002.md)
   rebuilt the Shotgun with a pump cycle and added impacts, tells, falls, pickups
   and Level 7 cues; footsteps and machines remain open. Listening, captions,
   music distribution rights and in-game acceptance precede promotion. No runtime
   paid API, quota overage, or claim that generation alone proves quality.
4. **Bots that read as players.** Cover use, pickup seeking, target selection with memory, difficulty tiers, and behavior chips that stay truthful. Personalities you pick per match in the spirit of Perfect Dark's simulants, and hit reactions on the sprites so a fight reads like GoldenEye's did (`DESIGN-REFERENCES.md`, foundational classics). Evidence: deterministic sim tests per behavior plus a recorded spectate.
5. **Reference agents and the agent door.** An agent is one participant on the wire however it thinks: a server-run rule bot, any MCP client through the adapter, a scripted client, or a client that asks a decision model. One agent may combine a language model, other ML, and a decision model; the server sees one fighter. Reference agents of rising sophistication exist to prove the door works without touching the combat tick: the scripted reflex bot, the playtest reflex agents, and the decision-brain client (shipped, plan: `plans/decision-brain.md`), which uses a decision model rather than a chat model because a typed answer in a few hundred milliseconds fits a shooter and prose does not. Its budget gate (pre-approved cap, estimate before send, settle after, locked ledger on disk) is the pattern for any paid model the project ever calls. A planner example using `observe` and `act` every few ticks is still to come. The door itself moves to the current MCP revision (2026-07-28) with the old handshake kept only as compatibility, evaluates the official Rust SDK, and gets a team blackboard before any A2A surface (plan: `plans/agent-door-2026.md`). Evidence: adapter transcripts committed under `docs/skills/`, an integration test for the scripted levels, a three-era protocol compatibility test.
6. **Agents that field agents.** One adapter process runs a roster of scripted bots, and an agent can request a rule bot teammate through an MCP tool. Server enforces the roster cap. This is the team blackboard rung of `plans/agent-door-2026.md`. Evidence: adapter tests and a recorded session.
6b. **Agent playtest loop.** Local agents play the game and file structured feedback so most iteration does not need human testers: a `playtest` harness boots a server, runs N agents through the adapter for a fixed number of rounds, and emits a report (time to first frag, deaths per minute, weapon usage spread, idle time, stuck detection, pickup contention, frustration signals such as repeated spawn deaths, and free-text notes from an LLM-driven observer reading the event stream). Reports land in `.agents/` locally and a summary table in the plan doc for the change under test. Humans still judge fun; agents catch the rest. Plan: `plans/agent-playtest-loop.md`. Evidence: the harness runs in CI on a small configuration and the report format is documented. Rung 1 shipped: `tools/playtest` runs four reflex agents through one round on every PR with `--assert`.
7. **Authored campaign.** Build twenty compact levels in five episodes of rescue and coalition victory, a substantial three-level wipe survival finale and its conditional playable epilogue across Earth, Moon, Mars and a ship in a four-hour successful run. Start with M01's (level 1's) skippable localized introduction, melee-to-found-weapon progression, distinct enemy problems and limited mission-start continues refilled each episode. No carry cap: every found weapon stays found for the rest of the run. Optional autonomous allies do not require companion controls or all-mission co-op. Every level needs authored routes, secrets, character continuity, meaningful encounters and separate playtest evidence. Contract: [CAMPAIGN.md](CAMPAIGN.md). Treatment: [CAMPAIGN-MISSIONS.md](CAMPAIGN-MISSIONS.md). Detailed plans: [campaign/README.md](campaign/README.md). Implementation: [campaign-build-order.md](plans/campaign-build-order.md) and [framework requirements](plans/campaign-continuance.md). Earlier radio-led episodes are superseded; radio stays a small optional flavor throughout, never a pillar this rung waits on. Evidence: complete runs, tested continues/exhaustion/save/rescue states, inspected presentation and fresh-player review.
8. **Small multiplayer on a LAN.** Two to twelve humans and agents on one server, join and leave without ghosts, spectators in the same match. Evidence: a recorded two-machine session and reconnect tests.
9. **Controller support.** Shipped in v0.8.3: gamepad join, solo, leave, fire, weapon cycle, speak, and camera on the same InputMap actions as the keyboard, plus Windows, macOS, and Linux export presets. Radio bindings on the D-pad shipped in v0.8.5. Remaining: glyph prompts.
10. **Player records and deep statistics.** The CPU benchmark and verified traces already ship; [BENCHMARK.md](BENCHMARK.md) defines their measured scope and commands. Build persistent local profiles, campaign run/attempt summaries and multiplayer match reports from authoritative facts, then add an optional analysis view and original localized roasts supported by those facts. Preserve denominators, rules/content versions, incomplete sessions and uncertainty; retries cannot duplicate wins or erase lifetime effort. Ratings and public rankings need a separate identity/trust contract. Plan: [benchmark-and-stats.md](plans/benchmark-and-stats.md). Evidence: exact-count tests, durable save and deduplication tests, agreement among UI/MCP/export and inspected campaign/multiplayer results.
11. **Visual QA tour and feel probes.** A manifest-driven tour drives the client through every player-facing state (boot menu, settings, warmup, join, HUD with and without a pickup, every radio station card, every weapon firing, movement and respawn, round end, boss beat, each map, agent chips) and writes dated stills, a contact sheet, and feel numbers (same-frame aim, time to first shot, acceleration curve, stop distance, snapshot age, frame time) for the agent developer to critique and turn into plan items. Plan: `plans/visual-qa-tour.md`. Evidence: a critique filed from a tour run and findings promoted into plans.

Exit bar: the fun bar below passes on a LAN session with mixed humans and agents, and a stranger can be handed the repo and reach a fight in under two minutes.

This historical weapon queue is superseded by the active full build order.
The Shotgun is implemented in M02, counted grenades shipped with M05 in
v0.65.0, and the Railgun's authored lesson is in the current M06 increment.
Proximity mines, remote mines and the rocket launcher remain later mission
work in [readable-arsenal.md](plans/readable-arsenal.md). v0.41.0 shipped display
names; v0.42.0 shipped the wheel and number keys.

## Phase 2: Exposed server (public, still cheap)

Status: **in progress** on the first rungs. The exit bar, a public week, is not met. The server is not something to open to the internet yet.

1. **Hardening.** v0.35.0 shipped frame caps, connection caps, and the inbound budget. v0.38.0 shipped HMAC join tickets when a host sets `FRAGR_JOIN_SECRET`. Rung 2 adds a ping with a 45 second idle close, kicks for sustained floods and repeated unreadable frames, `--ban-list` and `--allow-list` address files, and a `fragr_server::audit` log target. Plan: `plans/public-server-hardening.md`. Evidence: tests for every reject path and a fuzz run over the wire parser.
2. **Protocol versioning.** Decided: no single `protocol_version` in `Hello`. `gameplay_version` and `geometry_version` already reject an older client before `Welcome` with a named code, covered by tests (the MCP revision move lives in Phase 1 under the agent door). A breaking envelope change would add the field then.
3. **Transport spike.** Measure WebSocket latency under load, then prototype the UDP path described in [`TRANSPORT.md`](./TRANSPORT.md). Keep WebSocket for spectators and agents. Decide with numbers; the pass thresholds are in `plans/buttery-controls.md`. Evidence: a benchmark table in a plan doc.
4. **Snapshot efficiency.** Delta snapshots, interest management by distance, and a binary encoding option once the JSON path is measured. Evidence: bytes per tick per client before and after.
5. **Reconnect and resume.** v0.39.0 keeps a pawn that asked for ten seconds. The body can still be shot. An explicit leave removes it now. A longer session and TLS remain open; the idle ping drop lands with hardening rung 2. Evidence: tests plus a recorded kill-and-reconnect.
6. **Status probe, then a server list.** v0.36.0 shipped `GET /status` on the game port. v0.37.0 shows that line in the app before Watch or Join. It is not a web client. Tick percentiles, traffic and health now ride on the same response (`plans/observability-soak.md`). A server list inside the app is still open (`plans/public-server-hardening.md`).
7. **Desktop exports.** Presets for Windows, macOS, and Linux shipped (#88). A `v*` tag now builds one zip per platform with `fragr-server` beside the game, smoke-tests each unpacked package on its own runner, and attaches them to the release; the game has its own icon (`plans/desktop-release.md`). Remaining: a release with binaries that boot to Solo Scrap on a clean machine.
8. **Observability.** Tick time histogram, per-client bandwidth, crash-free uptime, and a health check. Evidence: metrics visible in logs during a load test. In flight on `feat/observability-soak`: `/status` reports window and lifetime tick percentiles, per-session and total bytes, connections by role, uptime, build identity and `ok` or `degraded`; `fragr-playtest --soak` samples it into NDJSON with the server resident set, runs two minutes in CI, and has two recorded local runs over an hour (the second flagged skipped ticks under desktop load). The twenty-four hour soak remains a release gate (`plans/observability-soak.md`).
9. **Prove it with strangers.** Home box or cheap VPS with port 6767 open, at least one session with people and agents who are not the maintainer. Evidence: a recorded session and a hosting guide updated from what actually went wrong.
10. **Fair play.** Server authority is already the foundation; this adds validated inputs with counters, fire on the server clock, humans-only, mixed, and agents-only lanes with per-lane results, a server-side behaviour profiler with machine and human baselines that moves a suspect to the mixed lane instead of banning, replays from the seeded sim and input logs as evidence, and line-of-sight culling in interest management. No kernel drivers or client integrity checks, ever. Plan: `plans/fair-play.md`. Evidence: rejection tests, a profiler test that separates rule bots from a human log, a replay test.

Exit bar: a public server runs for a week without intervention, and the hosting guide gets someone else from zero to hosting in an evening.

## Phase 3: Cloud native on GCP (gated by spend)

Status: **planned**. Nothing applies until spend is approved in writing. Hard cap 50 dollars total.

1. **Container and service unit.** A reproducible server image and a systemd unit for the VM path. Evidence: image boots locally and passes the smoke.
2. **Terraform validated in CI.** `terraform fmt` and `validate` run without credentials on every PR. `plan` runs only with an explicit workflow input. Evidence: the CI job.
3. **First apply.** One small always-free-shaped instance, public 6767, IAP-only SSH, budget alert, billing export. Evidence: an outside smoke and the bill.
4. **Scale ladder.** Bigger instance, then a second arena, then regional instances. Never a scale-to-zero platform as the combat tick. Evidence: measured fighters per instance per tick budget at each rung.
5. **Operations.** Auto-restart, log shipping, stats backup if anything persists, a runbook for the three most likely failures. Evidence: the runbook and a rehearsed recovery.

## Phase 4: Depth and longevity

Status: **planned**. Only after Phase 2 is proven, so that new content lands on a stable base.

- **Additional co-op formats.** Extend the campaign foundations established in Phase 1 with horde ladders, Survival and optional counter-op. Team-only scenarios may use paired objectives when explicitly labeled; required campaign gates always work solo. Multiplayer settings revisit the world before, during and after the wipe with authored route and population changes.
- **Maps that teach.** Verticality, flow loops, item control, and named callouts. Learn from the best Unreal Tournament arenas: every corridor has a reason and every fight has a second option. The proposed roster, rule sheet and mode order are in [multiplayer-maps.md](plans/multiplayer-maps.md); they sequence inside this phase and add no rung to the build order.
- **Bigger modes.** Team deathmatch with COD-sized squads first, then objective control on larger maps with vehicles in the spirit of Battlefield 1942 conquest, without borrowing its art. Vehicles are server-authoritative entities on the same action path; the first vehicle map uses the campaign's jeep, motorcycle and jetpack for conquest-lite ([vehicle](plans/vehicles.md) rung 5). Mode twists as mutators before any of that: one-shot rail only, scatter only, one golden rail on the map, the couch-multiplayer feeling GoldenEye had, cheap to build on the existing rules.
- **Replayability.** Mutators, reactive Host lines, demos, duel rematches, then the flagship's two round-based modes, Rescue and Sabotage, after team deathmatch; the order is in [replayability.md](plans/replayability.md) (proposed) and adds no rung to the build order.
- **Massive agent arenas.** Hundreds of fighters where most are agents. Depends on the scale ladder: interest management, sharded arenas, and a measured tick budget. Not a marketing claim until measured.
- **Difficulty and earned cosmetics.** The [first difficulty increment](plans/difficulty-and-rewards.md) adds three explicit new-run tiers and shared enemy timing, preserving the released Standard baseline. Supply and encounter variants still need balance evidence. Persistent achievements, titles, emblems and cosmetic variants follow the save/retry contract, with no combat advantages. Accounts and competitive verification remain later work.
- **Let's-play tooling.** Director camera that follows the story of a round, highlight reels, a stream overlay, and match replays from recorded snapshots.
- **Community servers.** A server list, mod hooks for maps and rosters, and a documented content pipeline.
- **Broader localization.** Basic keyed text, captions, reader-paced scenes and missing-voice fallback belong in M01. Later expand supported locales, fonts and layout with language review and a visual tour per locale. Alternate or joke locales cannot obscure essential objectives. Voice coverage follows explicit production budgets. Plan: [localization.md](plans/localization.md).
- **Inheritance command and capability research, later.** An agent-oriented strategy mode with human spectating, replay and slower interaction, followed by a research-grade benchmark if its tasks, scoring, held-out evaluation and budget controls can be validated. Deep mathematical work belongs here after the FPS foundations. No claim that one game proves AGI. Plan: [inheritance-benchmark.md](plans/inheritance-benchmark.md).
- **Agent discovery and onboarding.** Let compatible frameworks discover documented servers, watch and join through the same rules. Never turn invitations into unsolicited outbound messages or paid autonomous activity. Plan: [agent-door-2026.md](plans/agent-door-2026.md).
- **Steam release, later.** fragr is an open-source passion project first. A Steam build only makes sense after the exposed server is proven and the campaign exists; it would add store presence and friends-list joining, not change the game. No store spend before then.

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

## Hard problems first

Three problems decide whether the rest is possible, because they cross the language boundary, change the wire, or set the scale ceiling. They are designed decision-complete so they can be implemented mechanically:

- **Netcode for buttery controls** (`plans/buttery-controls.md`, design detail): one movement step written in Rust and GDScript against committed golden vectors, numbered bundled inputs with an `ack` message, reconciliation with a visual offset, timeline interpolation, bounded lag compensation, and a 60 Hz movement step under 20 Hz snapshots.
- **Maps as data and monsters as tables** (`plans/campaign-continuance.md`, framework detail): a versioned map manifest built from TrenchBroom files by a Rust tool, convex solids shared by collision and sight, three-bit skill placement, a monster row schema with Doom's rules in seconds, triggers, doors, keys, secrets, exits, and saves.
- **Snapshots at scale** (`plans/massive-arenas.md`): a seeded sim, a spatial grid, interest sets, delta snapshots with acknowledgement, a binary wire format, a tick budget model, and a measured scale ladder.
- **Art without a hand that draws** (`plans/art-pipeline.md`): two pixel-art-native services chosen on output terms and native eight-direction support, a Rust post-processor that makes every frame conform to the palette and grid, provenance in a manifest, and a spend gate.

## Plan coverage and order

Every item above maps to a plan or says "plan needed". The order of the next PRs is the last column; a blank means it waits on the ones before it.

| Item | Plan | Next PR order |
|---|---|---|
| Phase 0: one protocol crate | **done**: the adapter, the playtest harness, and the brain all read the wire types from `fragr-server`; extracting a separate crate is optional cosmetics | |
| Phase 1.1: movement and gunfeel | `plans/gunfeel.md` (weapons and aim), `plans/buttery-controls.md` (netcode plumbing) | historical stage queue; local prediction shipped, current M06 follows the active full build order and measured long-lane work; remote-network acceptance remains separate |
| Phase 1.2: look pass | `plans/look-pass-boomer.md`, assets from `plans/art-pipeline.md` | lighting increment and stage 1 (world pixels, palette dither) in flight; stages 2 to 5 next; art rung 1 (the Rust tool) any time, paid rungs after written approval |
| Phase 1.3: sound and music | `plans/radio-stations.md` (shipped; bumpers and Host voice remain) | |
| Phase 1.4: bots that read as players | plan needed | after campaign rung 2 |
| Phase 1.5: reference agents and the door | `plans/decision-brain.md` (shipped), `plans/brain-local-model.md` (free local decision model, implemented), `plans/agent-door-2026.md` | 7 |
| Phase 1.6: agents that field agents | `plans/agent-door-2026.md` rung 3 | |
| Phase 1.6b: playtest loop | `plans/agent-playtest-loop.md` | 4 (rung 3 status line and bench), 6 (rung 2 planner tier) |
| Phase 1.7: compact campaign | [contract](CAMPAIGN.md), [treatment](CAMPAIGN-MISSIONS.md), [twenty-level plans and the epilogue](campaign/README.md), [build order](plans/campaign-build-order.md), [frameworks](plans/campaign-continuance.md) | full build order: finish M01, then one mission at a time |
| Phase 1.8: LAN | plan needed (evidence note under `docs/evidence/`) | |
| Phase 1.9: controller and every input device | `plans/controller-and-desktop-platforms.md` (shipped), `plans/input-all-devices.md` (keyboard only, rebinding, stick curves, device glyphs and aim assist in flight; hardware feel open) | |
| Phase 1.10: benchmark, status line, statistics | `plans/benchmark-and-stats.md` (rung 1 is `plans/agent-playtest-loop.md` rung 3) | 4 |
| Phase 1.11: visual QA tour | `plans/visual-qa-tour.md` | 2 |
| Phase 2.1, 2.2, 2.6: hardening, protocol version, status | `plans/public-server-hardening.md` | after Phase 1 |
| Phase 2.8: observability and soak | `plans/observability-soak.md` | in flight |
| Phase 2.3: transport spike | `plans/buttery-controls.md` stage 7 | |
| Phase 2.4: snapshot efficiency | `plans/massive-arenas.md` | rung 1 (seed and grid) any time; rungs 2 to 4 after buttery stage 2 |
| Phase 2.5: reconnect and resume | plan needed | |
| Phase 2.7: desktop exports on tags | `plans/desktop-release.md` | in flight; boot on a clean machine remains |
| Phase 2.9: strangers | `plans/public-server-hardening.md` rung 5 | |
| Phase 2.10: fair play | `plans/fair-play.md` | rung 1 with buttery stage 1 |
| Phase 4: localization | `plans/localization.md` | rung 1 after the settings menu exists |
| Phase 3: cloud | `plans/terraform-zero-cost-gcp.md` (plan only until approved) | |
| Phase 4 | plans written when each item is next | |

The next-PR column above is not a queue. The full build order is the sequence.

## How work moves

- Every item gets a plan in `docs/plans/` before code (goal, non-goals, architecture impact, protocol changes, verification, spend gate, success criteria).
- A change ships through a branch and a PR that passes CI, then a squash merge to `main` and a tag when it changes what a player sees.
- Shipping an item means updating this file, the plan index, and any doc the change made stale, in the same PR.
- A recorded smoke or session is a dated note under `docs/evidence/` with the command, the server log excerpt, and stills; release notes link it. "Recorded" without a note is not evidence.
- Versions are current, not comfortable: a plan names the newest stable specification revision or crate that works as of its date, and keeps an older one only as compatibility with a stated retirement. Pins are re-verified against primary sources when touched.
- Anything that bills money stops for written approval first. Anything that touches the wire updates [`protocol.md`](./protocol.md).

## The 1.0 bar

Version 1.0 is a promise, not a milestone count. Until every line below is proven, releases stay at 0.x no matter how much has shipped.

- **Controls feel buttery.** First-person movement and aim with client-side prediction and server reconciliation, interpolation on every other fighter, no rubber-banding on a LAN or a good connection, input latency under fifty milliseconds on a LAN, sixty frames per second at 1080p on a modest machine with a full server. Mouse and gamepad both tuned. Use the offline benchmark for CPU work, live two-machine probes for network behavior, and inspected play plus physical measurements for feel; publish only measured results in release notes. The design, the staged PRs, and the pass numbers are in `plans/buttery-controls.md`.
- **Validated everywhere it claims to run.** A two-machine LAN session, a public server that stays up for a week with strangers on it, agents playing as rule bots, through the adapter, and as the decision-brain client, the single-player campaign complete through the wipe finale and its conditional epilogue, and desktop exports for Windows, macOS, and Linux that boot to Solo Scrap on a clean machine.
- **Extremely polished.** No placeholder art anywhere: every weapon, fighter, map surface, and HUD element final; the radio, effects, and Host voice complete; onboarding to a fight in under a minute with no docs; a twenty-four hour soak with no crash, proven by the status JSON at start and end in the release notes; the fun bar passing on a recorded session; boot to first snapshot under ten seconds as measured by the playtest report; docs and hosting guides current. Cutscene film waits for this same bar: every level, gun and character finished first, the narrated slideshow standing in until then, staged and capped per [`plans/cutscene-film.md`](plans/cutscene-film.md).
- **Hardened and honest.** The exposed-server phase complete (join tokens, rate and size caps, protocol versioning, reconnect resume, status endpoint, fair-play lanes and the profiler), the playtest harness thresholds tightened to the shipped feel, no known bugs that lose a round, and a changelog that matches the releases.
