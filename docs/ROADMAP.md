# fragr roadmap

The order of operations to take fragr from a playable vertical slice to an exceptional game that people play, watch, and host. This file is the plan of record for sequencing. Feel and non-negotiables live in [`VISION.md`](./VISION.md). Bounded work items live in [`plans/`](./plans/README.md). Implementation truth is source, tests, and CI.

Every item below is in exactly one state: **planned**, **in progress**, **shipped** (merged to `main`), or **proven** (shipped and demonstrated with evidence: a test, a recorded smoke, a screenshot from the tip, or a real session). Do not promote an item without the evidence.

## The shape of the plan

1. **Prove it locally.** Solo play against bots, agent play through the adapter, and small multiplayer on one machine or a LAN. Zero spend. Everything here is testable in CI or a recorded smoke.
2. **Expose it.** A hardened server you can run on a home box or a small VM with the port open, where strangers and their agents join and it does not fall over.
3. **Make it cloud native.** GCP Terraform that applies cleanly, scales along a ladder, and stays under the spend cap. Not before the exposed server is proven.
4. **Deepen it.** More maps, modes, vehicles, progression, and the let's-play tooling that makes watching as good as playing.

The engineering ladder for scale runs through every phase: small squads first (four to twelve fighters, the current bar), then full servers (thirty-two to sixty-four), then large agent-heavy arenas (hundreds of fighters where most are agents). Each rung has its own measurements and is not claimed until measured.

## Where we are (2026-09-25)

**Shipped and proven on the tip:**

- Rust authoritative server at 20 Hz with hitscan combat, respawn, round scoring, six maps with heightfield movement, weapon and health pads, a mid-round boss, and eight named rule bots with four behaviors.
- Godot 4.7.2 client as a thin presenter: boot menu, Solo Scrap, spectator director camera, human join and leave, first-person weapon face, HUD with killfeed and Host bumpers.
- MCP adapter with `join`, `leave`, `observe`, `act`, `speak`, `get_events`, `round_state`, plus a scripted bot. Unknown action fields are rejected. Speak is rate limited.
- Decision-brain agent (`agents/brain`): a fighter whose stance, weapon, and danger read come from Jev (TypeSafe natively or through OpenRouter) at up to five decisions per second while a local controller plays every tick. Paid providers refuse to start without an explicit cap; every call is estimated, settled, and ledgered. Local rules play for free and CI proves that path.
- CI on Linux: fmt, clippy with warnings denied, tests, deterministic benchmark and budget checks, the agent playtest smoke with thresholds, an unfiltered 90 percent line coverage floor, release build, cargo-deny for licences, bans, and sources, and headless Godot checks. Windows and macOS also pass workspace tests and Godot checks.
- Live tip screenshots, a one-command Solo Scrap launcher, self-host guides, and plan-only GCP Terraform.
- v0.34.0 through v0.45.0 are recorded in [the changelog](../CHANGELOG.md). In short: Recall Notice's routes, exit, optional supplies and durable local runs; connection and frame caps; `GET /status`; join tickets; pawn resume; player-facing gun names and cycling; campaign-aware agent control; and bounded spectator delivery. The README stills show current play.
- v0.46.0 through v0.53.0 (2026-09-24 and 25): host hardening (idle pings, kicks, ban and allow lists, an audit log), localized kick messages, downloadable Windows, Linux and macOS packages on every tag with an original icon, spawn cover on maps 3 to 5, the M02 fight graybox and 120 Hz input pacing, Doom-style ammo with a seven-pellet shotgun, the black and red Union with the Heavy Sweeper and the Turret on a test range, status health metrics with a soak harness, keyboard-only, mouse and gamepad controls with rebinding and aim assist, the first lighting pass, and the M01 secret Shiv.
- Two developer-only generation pipelines: `tools/audiogen` for audio and `tools/spritegen` for art. Audio uses per-run estimate caps and requires quota reconciliation; art has durable request reservations. Neither replaces asset review. The first art slice produced twenty-four frames for sixty-nine cents, with surfaces rejected.
- The setting has three sides: the Union/Chancellery, free humans and conscious agents with agency, and the Inheritance. The Inheritance's ecological recovery and mass killing leave conflicting survivor perspectives, not a narrator's declaration that it is right. `docs/lore/` owns the world and voice; bodies do not establish who has freedom or whose suffering matters.

**Generated art and audio:** twenty-four initial sprite frames (ten weapon
viewmodels, six enemies, four effects, four rejected surfaces), plus a weapon
bake-off. Three locally prepared idle viewmodels are now integrated. The remaining
frames need integration. Twelve Chancellery addresses remain under story and
language review. The old ten-part epilogue and 43 news/PSA/ad clips have been
quarantined by the [audio cleanup](plans/music-review.md), with verified backups.
The old radio-only ending cannot be integrated as the new campaign's actual ending. The initial art receipt was $0.69; current remaining provider credit
must be checked before any new call rather than inferred from that old balance.

**Not built yet (honest list):** low-latency transport (WebSocket JSON only), live client prediction (shared movement vectors exist), a complete protocol migration policy (geometry and gameplay admission exist), unlimited lifetime statistics, progression, DJ bumpers and a voiced Host, a finished single-player campaign or full co-op lifecycle, a complete art pass, public-server load tests, any cloud apply, vehicles, and multiplayer objective modes. `GET /status` on the game port is a host probe in the current line of work, not an in-app server browser and not a web client. M01 has a developing discovery/combat/mission slice; Episode 0 remains a separate arena prototype. A deterministic local benchmark already exists; it does not establish public-server readiness. Frame caps, connection caps, and the inbound message budget shipped in v0.35.0.

**Decided 2026-09-25:** the campaign is twenty levels in five episodes, per the
[expansion plan](plans/campaign-expansion.md), now the contract in
[CAMPAIGN.md](CAMPAIGN.md); the wipe splits into three levels with their own
clocks; continues refill to three at the start of each episode; five
introductions moved (the Jammer out of M02); the campaign has no carry cap
([readable arsenal](plans/readable-arsenal.md)); and mutators are host
settings from the start, not unlocks, per the
[replayability plan](plans/replayability.md#the-flagship-rescue-and-sabotage). **Decisions
waiting on Nick:** from the [multiplayer maps proposal](plans/multiplayer-maps.md),
three new pickups; and whether the Cells cap stays at 50 or rises to 100.
Parked for the next session: a flaky map 5 opening spawn gate in the six-map
roster (a regression test is drafted, no fix yet) and a local open-weights
decision model for the reference agent, which needs its model and licence
verified first.

## What is next, in order (as of 2026-09-25)

The current sequence is the [full build order](#full-build-order-2026-09-22) below. This section records increments that already shipped. It is not the queue.

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
Persistence, final art and fresh-player acceptance remain open. The requested shared level kits, distinct
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
and a later combined-arms vehicle showcase in M08's launch works. General moving
lifts and vehicles remain unbuilt. The sniper rifle, grenade, proximity mine,
remote mine, and rocket launcher are campaign finds in
[the readable arsenal](plans/readable-arsenal.md) and are not implemented. Gold
finishes and curated weapon colors are cosmetic-only achievement directions
under #197.

The phases below are the long shape. The sequence that follows is the build order. Each rung is there because the rung before it is what makes the next one true. A green harness is not a finished mission. A scripted clear is not a fresh player.

## Full build order (2026-09-22)

**Active goal:** build the agreed game through a proven 1.0. That is Recall Notice as the quality bar, then each later mission on systems the whole campaign reuses, then local prediction before the first long Rail lane, then the wipe and its conditional epilogue, then a LAN proof, then an exposed server. Cloud apply, matchmaking, and conquest-scale vehicles stay behind that server. The story spine in [`CAMPAIGN.md`](CAMPAIGN.md) is settled. Names, rescue tradeoffs, wipe operations, and the reprieve's exact terms stay proposals until the gate that needs them. Mission briefs live in [`CAMPAIGN-MISSIONS.md`](CAMPAIGN-MISSIONS.md) and [one plan per level](campaign/README.md). Geometry comes from the mission, not from an arena layout. The six current layouts stay playable foundations. Boltgun remains the visual bar for a played sequence, not a reason to generate the roster before the first two enemies read. Every rung serves the [easy to pick up, deep to master pillar](VISION.md#easy-to-pick-up-deep-to-master): fights and flow first, at most three doors a level.

The numbered list that used to sit here is historical. It put the campaign foundation seventh, behind a generation pipeline M01 does not need, and it still treated gunfeel rung 2 as next after that work had shipped. Spend restraint stays: no paid batch to paper over the uncertain art reservation, no cloud, and no server browser.

Story between missions is a full-screen pixel text page, the same family as the M01 opening. Optional spoken clips for those pages come through `tools/audiogen` only after the wording is frozen. Higgsfield video, including Seedance 2.5 character cutscenes, waits until the playable campaign is built. A movie spent while the missions are still moving would be thrown away. [`plans/campaign-scenes.md`](plans/campaign-scenes.md) holds that gate.

Admission sits beside the mission rungs and does not close the M01 quality gate. v0.35.0 through v0.39.0 shipped frame caps, per-address caps, the inbound budget, `GET /status`, the app match line, join tickets, and a ten-second pawn resume. v0.40.0 lets the mission card leave after the introduction. v0.41.0 is the player-facing gun names. v0.42.0 is weapon cycling and four README stills. The Clerk and the Sweeper no longer share one outline in the unshaded atlases. A live Recall Notice run on 2026-09-22 confirmed the boot menu, host `127.0.0.1:6767`, fists then the pistol, the `+24 BULLETS` pickup, and the mouse wheel switching between those two guns. That live run saw a card return after the first one left, and key 1 appeared not to leave the pistol. A later owned M01 server check dismissed the five page story, repeated MapInfo without replaying it, claimed the pistol, and selected fists with a real key 1 event; both the private loadout and public snapshot confirmed fists. The eight second objective card is designed to return on a new mission phase, but the earlier sighting did not identify which card it was. The exact live conditions remain unproven. The server seam now has bounded outbound queues and a twelve-roster local spectator fan-out measurement ([plan](plans/bounded-spectator-fanout.md)); remote-network evidence remains before any higher cap. Optional M01 supply detours shipped in v0.44.0; the next mission rung is automated review, with human acceptance near 1.0. Paid enemy sheets were not bought.

Automated Jev playtests run alongside these rungs. Durable paid-call reservations shipped in [#218](https://github.com/blisspixel/fragr/pull/218). The free first-person watcher shipped in v0.43.1 ([plan](plans/agent-first-person-watch.md)). Campaign-aware questions, objective control, and authoritative outcome receipts shipped in [#223](https://github.com/blisspixel/fragr/pull/223). The bounded M01 timeline and terminal-record drain shipped in [#227](https://github.com/blisspixel/fragr/pull/227) before a capped OpenRouter trial. A final free Standard seed 67 watch departed on attempt 1 with a matching record, eight first-person frames and no paid calls. Standard seed 1 cleared in a later replay; Severe seed 42 both exhausted its continues and cleared on separate live runs with the same name and seed. These results expose sorting pressure and live outcome variance, not fresh-player comprehension. Human acceptance sessions remain near 1.0; automated evidence should continue to improve M01 and later missions in the meantime.

**1. Make M01's two routes a real choice, and prove a sloppy clear.** This is first because the records wing, the lift, and the three continues already exist. The bypass is its own encounter: reception's region does not wake it, and its ammo is not standing on the sentry. Both seeded routes still depart. A seeded bypass clear also departs after one Flechette magazine is fired into the bypass ceiling, without claiming the file-stack supplies, and without walking the west side of sorting. The east route now leaves all four file-stack guards alive. `files_a_return` closes the shot from the records approach, around (-18, 10.7), through the stacks doorway. The reception counter screen, the bypass lip, and a narrow stacks screen keep sorting and the bypass from being cleared early, without moving `stacks_sweeper` and without sealing `stacks_cross_aisle`. Seed 67, human control, `east_bypass_departs_with_all_stack_guards_alive`: 1639 ticks, 80 hp, 0 armor, 16 defeats, 101 shots. This seeded sightline debt is closed. Secrets, a new weapon, and disk saves do not belong in this rung. The next rung is the building explaining itself.

**2. Let the building explain itself.** The records deck now shows the custody lift before the records wing. The reserved opening (x=-5 to -1, z=12 to 13) is no longer filled: `office_front_sealed` is `office_front_sill`, y=3 to y=5, and the header still starts at y=6.5. `records_balcony_sees_the_lift_sign_but_not_the_transfer_guards` stands at (-4, 3, 9), on that deck between the public stair and reception, and sees the lift sign. A half-metre sweep of standing deck positions does not see `transfer_clerk`, `transfer_sweeper_west`, or `transfer_sweeper_east` at 0.2, half height, or full height. The walk from `records_balcony` to that stand stays on the deck, and the walk on to reception does not enter the transfer office. `m01_routes_use_ordinary_actions_through_the_live_session` passes. Seed 67, human control, `east_bypass_departs_with_all_stack_guards_alive` is unchanged: 1639 ticks, 80 hp, 0 armor, 16 defeats, 101 shots. `m01_main_and_maintenance_approaches_clear_with_discovered_equipment` still departs for human and agent control. Public stairs: 1765 ticks, 100 hp, 19 defeats, 92 shots. Maintenance: 1833 ticks, 100 hp, 20 defeats, 117 shots. `MISSION_DEPARTED` now states the correction ward and that this mission ends here. It no longer calls the result a prototype. The match menu says leaving abandons the run, and that continues are not refilled, only when the boot mode is the owned local campaign. Arena and joined matches keep "LIVE MATCH. FIND COVER FIRST." `test_mission.gd` and `test_frontend.gd` passed headless on Godot 4.7.2. Reception stays bone enamel on green records tile. The file stacks keep that tile and use service-steel walls. Sorting stands on concrete. Dispatch stands on service steel. The lift face stays the lift panel. These are registered surfaces only. A local tour on 2026-09-22 (`client/qa/m01-rooms.json`, frames under `.agents/qa/m01-rooms/`, not published) shows the balcony opening, bone reception on green tile, dark steel stacks on that same tile, grey sorting concrete, and a dark dispatch floor. Sorting and dispatch still share the bone wall. That inspection is not a finished art pass. Running from the Godot executable still shows the engine icon in the Windows taskbar.

**3. Two readable enemies, before any new paid art.** Done as a local rebake, not a purchase. The atlases are unshaded. At rest the Sweeper is wider than the Clerk. While aiming, the Clerk's pistol clears the shoulder and the Sweeper's rifle stays inside the pauldrons. `test_enemy_animation.gd` checks those outlines. The uncertain Clerk reservation was not replaced. A later albedo sheet can lock to this silhouette. It is not required to keep going, and tile batches stay forbidden until a local seam check exists. Recall Notice still uses the facility fill in `arena_sky.gd`. An unknown map name still falls through to the scrapyard.

**4. Optional detours, then secrets.** The confiscation alcove and maintenance overlook are walking detours with optional supplies; ordinary routes leave them unclaimed. This static slice [shipped in v0.44.0](plans/m01-optional-supply-detours.md). Neither holds the objective, the ward name, or a required gun. The [secret Shiv](plans/m01-secret-shiv.md) now lies in the alcove's south pocket: a pool-less melee grant, found by walking in, counted in the service record, never needed for the clear. No moving wall panel: the alcove is open, and a hidden room would spend part of the three-door budget. The imperfect-aim supply check still stands. Finding either detour or the Shiv is not part of the clear in rung 1.

**5. Prove M01 with automation, retain the fresh-player gate for later.** Run varied seeds, bodies and difficulties through the live server, inspect first-person agent captures, and check route choice, survival, encounter variety, readable objectives and regressions. Record failures and corrections in [`plans/m01-completion.md`](plans/m01-completion.md). Then continue building the campaign and multiplayer. Near 1.0, run one unsteered human session with radio and voice muted: the player can say who was taken, find the flank, tell the two enemies apart, and reach the lift. Record their words, deaths and stalls. If they needed a hint, that acceptance gate stays open. Automated clears do not satisfy it. Aim stays the shipped mouse-frame look. Prediction, projectiles, a sniper, grenades, mines, and vehicles are not required for M01's automated review.

**6. Finish M02 on the durable run and objective seams.** The versioned local run file shipped in v0.45.0. It resumes M01 at mission entry without refilling continues or rewinding live state, and records departure without pretending the campaign is over. The [M02 foundation](plans/m02-objective-gates.md) now validates authored objectives and precomputed gate worlds, advances them on the server, and publishes optional mission state to Rust readers. M01 content and capability 8 remain regression fixtures. A bundled ward graybox (gallery, stair, antechamber, ward, processing floor, loading dock) is an open route with no switches or gates: three Clerk and Sweeper fights and two arrival objectives, "Find Latch" and "Get out". `--local-mission persons_unknown` serves it as a development child with no run file, and Single Player has a development entry. Seeded tests have a solo human and a solo agent fight through all nine enemies and depart through the shared wire, equipment and mission controllers, and prove a wipe restores the first objective, the enemies and the supplies. The Godot client reads capability 9 and shows one keyed objective line, and a live tour fought every room. Latch is an arrival stand-in and the Jammer is unbuilt. Levels follow the fights-first, few-doors, readable-without-English rule in [`MAP-DESIGN.md`](MAP-DESIGN.md). A quick Use or jump tap was being dropped on fast displays because the client flooded the server's inbound budget; actions are now paced. Next, Latch as a story-controlled actor, the Jammer kill as the loading-exit beat, Crawlers, and M01-to-M02 run carry with explicit save migration tests. M02 is not complete until the route, retry, presentation and encounter evidence pass; Latch is not a second player.

**7. M03, then the controls the Rail lane needs.** M03 adds the district, the Heavy Sweeper, and the first flying [Notary drone](plans/flying-drones.md) in the Turret's old slot, and no new gun. The Turret first appears in M04. Both named rescues have to persist. Disk save and the outcome record are part of calling Act I a release. Then buttery stages 2 through 6, still on WebSocket: movement constants in seconds, prediction and reconciliation of the local body only, interpolation of everyone else, bounded hitscan lag compensation, and gamepad curves. M04 is the first deliberate long Rail shot, which is the first place a late snapshot spoils the fight. Do not stop M01 to migrate the clock.

**8. One new capability per later mission.** M03 finds the grenade on the ordinary route and adds no new mandatory gun. M04 teaches the Railgun in customs and finds the Sniper Rifle on the crater cut. M05 introduces proximity mines. M06 finds remote mines after that lesson, and doors that close during play always have a bypass. M08 finds the rocket launcher before the exterior crest, and finishes its infantry route before adding one rover the mission can afford to lose. That rover is the jeep; [vehicle](plans/vehicles.md) rung 1 starts only when M08 is next, the motorcycle when M09 is next, and the jetpack when M10 is next. M07 adds the armored Assessor drone for the Arc lesson. None of those five weapons is implemented. Splash and traps share one server-owned projectile and placed-device seam when they are built. M07, M09, and M10 stay as proposed in the mission briefs. M10 prototypes the survival route before its encounter budget is locked, then the conditional epilogue. Decided 2026-09-25: the [campaign expansion](plans/campaign-expansion.md) grows the ten missions into twenty shorter levels in five episodes; this rung still ships one mission at a time (M03, M04, and so on), each now mapped to its level number in [CAMPAIGN-MISSIONS.md](CAMPAIGN-MISSIONS.md).

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
   The [developer review loop](plans/music-review.md) is
   implemented and verified locally: standalone Rust listening, local transcription, current-canon
   evidence checks, capped Jev classification, reversible culls and station
   replacement batches, followed by human listening. The
   [editorial contract](audio-editorial.md) retires the old news/PSA/ad and
   epilogue recordings for rewrites, and calls for four original long-form radio
   formats. All fifteen lore chapters have been reviewed, superseded claims
   removed and asset history separated; factual and editorial gates must both
   pass, with explicit pass/rejection/unknown counts, and unknowns never count
   as approvals. The [production sources](audio-production/README.md) hold four
   candidate full programs and sixteen supporting pieces with local transcripts,
   passing script comparisons and draft captions; current-canon acceptance and
   human listening remain gates before any of it ships. The initial library
   shipped (#97, #99, #100): seven music stations with twenty tracks each, forty
   talk clips, three news beds/stings, basic effects and station switching/ducking.
   This is not a finished sound pass, and it does not gate the campaign or
   multiplayer rungs. [Radio refresh](plans/radio-refresh.md) replaces the old
   arena-heavy editorial direction with four sustained optional talk formats and
   music from an inhabited world. [Effects refresh](plans/audio-effects-refresh.md)
   covers weapon identity, movement, surfaces, pickups, machines and mix, which
   matter far more to the fun bar than any radio segment. Listening, captions,
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

The next weapon work is the gun the next mission teaches, not another rename. The shotgun is already in the sim and belongs in M02. The sniper rifle, grenade, proximity mine, remote mine, and rocket launcher are locked to later missions in [readable-arsenal.md](plans/readable-arsenal.md) and are not implemented. v0.41.0 shipped the display names. v0.42.0 shipped the wheel and the number keys.

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
| Phase 1.1: movement and gunfeel | `plans/gunfeel.md` (weapons and aim), `plans/buttery-controls.md` (netcode plumbing) | rungs 1-3 and buttery stage 1 shipped; stages 2-6 after Act I, before M04 |
| Phase 1.2: look pass | `plans/look-pass-boomer.md`, assets from `plans/art-pipeline.md` | lighting increment and stage 1 (world pixels, palette dither) in flight; stages 2 to 5 next; art rung 1 (the Rust tool) any time, paid rungs after written approval |
| Phase 1.3: sound and music | `plans/radio-stations.md` (shipped; bumpers and Host voice remain) | |
| Phase 1.4: bots that read as players | plan needed | after campaign rung 2 |
| Phase 1.5: reference agents and the door | `plans/decision-brain.md` (shipped), `plans/agent-door-2026.md` | 7 |
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

- **Controls feel buttery.** First-person movement and aim with client-side prediction and server reconciliation, interpolation on every other fighter, no rubber-banding on a LAN or a good connection, input latency under fifty milliseconds on a LAN, sixty frames per second at 1080p on a modest machine with a full server. Mouse and gamepad both tuned. All of it measured by the benchmark mode and printed in the release notes. The design, the staged PRs, and the pass numbers are in `plans/buttery-controls.md`.
- **Validated everywhere it claims to run.** A two-machine LAN session, a public server that stays up for a week with strangers on it, agents playing as rule bots, through the adapter, and as the decision-brain client, the single-player campaign complete through the wipe finale and its conditional epilogue, and desktop exports for Windows, macOS, and Linux that boot to Solo Scrap on a clean machine.
- **Extremely polished.** No placeholder art anywhere: every weapon, fighter, map surface, and HUD element final; the radio, effects, and Host voice complete; onboarding to a fight in under a minute with no docs; a twenty-four hour soak with no crash, proven by the status JSON at start and end in the release notes; the fun bar passing on a recorded session; boot to first snapshot under ten seconds as measured by the playtest report; docs and hosting guides current. Cutscene film waits for this same bar: every level, gun and character finished first, the narrated slideshow standing in until then, staged and capped per [`plans/cutscene-film.md`](plans/cutscene-film.md).
- **Hardened and honest.** The exposed-server phase complete (join tokens, rate and size caps, protocol versioning, reconnect resume, status endpoint, fair-play lanes and the profiler), the playtest harness thresholds tightened to the shipped feel, no known bugs that lose a round, and a changelog that matches the releases.
