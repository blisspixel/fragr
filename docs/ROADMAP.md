# fragr roadmap

The order of operations to take fragr from a playable vertical slice to an exceptional game that people play, watch, and host. This file is the plan of record for sequencing. Feel and non-negotiables live in [`VISION.md`](./VISION.md). Bounded work items live in [`plans/`](./plans/README.md). Implementation truth is source, tests, and CI.

Every item below is in exactly one state: **planned**, **in progress**, **shipped** (merged to `main`), or **proven** (shipped and demonstrated with evidence: a test, a recorded smoke, a screenshot from the tip, or a real session). Do not promote an item without the evidence.

## The shape of the plan

1. **Prove it locally.** Solo play against bots, agent play through the adapter, and small multiplayer on one machine or a LAN. Zero spend. Everything here is testable in CI or a recorded smoke.
2. **Expose it.** A hardened server you can run on a home box or a small VM with the port open, where strangers and their agents join and it does not fall over.
3. **Make it cloud native.** GCP Terraform that applies cleanly, scales along a ladder, and stays under the spend cap. Not before the exposed server is proven.
4. **Deepen it.** More maps, modes, vehicles, progression, and the let's-play tooling that makes watching as good as playing.

The engineering ladder for scale runs through every phase: small squads first (four to twelve fighters, the current bar), then full servers (thirty-two to sixty-four), then large agent-heavy arenas (hundreds of fighters where most are agents). Each rung has its own measurements and is not claimed until measured.

## Where we are (2026-09-20)

**Shipped and proven on the tip:**

- Rust authoritative server at 20 Hz with hitscan combat, respawn, round scoring, six maps with heightfield movement, weapon and health pads, a mid-round boss, and eight named rule bots with four behaviors.
- Godot 4.7.2 client as a thin presenter: boot menu, Solo Scrap, spectator director camera, human join and leave, first-person weapon face, HUD with killfeed and Host bumpers.
- MCP adapter with `join`, `leave`, `observe`, `act`, `speak`, `get_events`, `round_state`, plus a scripted bot. Unknown action fields are rejected. Speak is rate limited.
- Decision-brain agent (`agents/brain`): a fighter whose stance, weapon, and danger read come from Jev (TypeSafe natively or through OpenRouter) at up to five decisions per second while a local controller plays every tick. Paid providers refuse to start without an explicit cap; every call is estimated, settled, and ledgered. Local rules play for free and CI proves that path.
- CI on Linux: fmt, clippy with warnings denied, tests, deterministic benchmark and budget checks, the agent playtest smoke with thresholds, an unfiltered 90 percent line coverage floor, release build, cargo-deny for licences, bans, and sources, and headless Godot checks. Windows and macOS also pass workspace tests and Godot checks.
- Live tip screenshots, a one-command Solo Scrap launcher, self-host guides, and plan-only GCP Terraform.
- Two developer-only generation pipelines: `tools/audiogen` for audio and `tools/spritegen` for art. Audio uses per-run estimate caps and requires quota reconciliation; art has durable request reservations. Neither replaces asset review. The first art slice produced twenty-four frames for sixty-nine cents, with surfaces rejected.
- The setting has three sides: the Union/Chancellery, free humans and conscious agents with agency, and the Inheritance. The Inheritance's ecological recovery and mass killing leave conflicting survivor perspectives, not a narrator's declaration that it is right. `docs/lore/` owns the world and voice; bodies do not establish who has freedom or whose suffering matters.

**Generated art and audio:** twenty-four initial sprite frames (ten weapon
viewmodels, six enemies, four effects, four rejected surfaces), plus a weapon
bake-off. Three locally prepared idle viewmodels are now integrated. The remaining
frames need integration. Twelve Chancellery addresses and a ten-part epilogue
exist as assets, but require a story and language audit before selection. The old
radio-only ending cannot be integrated as the new campaign's actual ending. The initial art receipt was $0.69; current remaining provider credit
must be checked before any new call rather than inferred from that old balance.

**Not built yet (honest list):** low-latency transport (WebSocket JSON only), live client prediction (shared movement vectors exist), authentication or join tokens, per-connection rate limits and size caps, reconnect resume, packaged release downloads, a complete protocol migration policy (geometry/gameplay admission capabilities exist), a status endpoint, persistent stats, progression, DJ bumpers and a voiced Host, a finished single-player campaign or full co-op lifecycle, a complete art pass on sprites, guns, and levels, public-server load tests, any cloud apply, vehicles, and multiplayer objective modes. M01 has a developing discovery/combat/mission slice; Episode 0 remains a separate arena prototype. A deterministic local benchmark already exists; it does not establish public-server readiness.

## What is next, in order (as of 2026-09-20)

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
fists, recovered Tack/Flechette, finite ammunition, reload and individual supply
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
This remains a development mission. Limited continues, persistence, final art and
fresh-player acceptance remain open. The requested shared level kits, distinct
enemy combinations and difficulty/achievement cosmetics have homes in
`MAP-DESIGN.md`, `ENEMIES.md` and `plans/difficulty-and-rewards.md`.
The current campaign contract targets a 2-3-hour successful solo run across twelve
compact missions. Death can spend a limited continue to restart the current
mission with its starting equipment; three continues per run is the initial
balance proposal. No mandatory duo, companion controls, revival or all-mission
co-op. Autonomous allies and mission-specific viewpoints are design options.
Run recovery and save behavior remain unbuilt under #195.

The phases below are the long shape. This is the remaining build order, with the reason each item sits where it does.

**Immediate priority: review the twelve-mission treatment, then complete M01.**
The agreed rescue-led story, sudden wipe, played aftermath and ambiguous final
fragment live in [`CAMPAIGN.md`](CAMPAIGN.md). The detailed proposed route and
spatial briefs live in [`CAMPAIGN-MISSIONS.md`](CAMPAIGN-MISSIONS.md), with [one detailed plan per level](campaign/README.md). Core story
choices are settled; names, exact historical transitions, individual wipe operations,
and individual rescue tradeoffs remain identified proposals. Derive geometry
from the mission's purpose, not the current arena layout. The
[authored layout brief](plans/authored-compliance-yard.md) captures the spatial bar.
The all-map rendered audit confirms oversized open spaces and weak landmarks.
The inspection-complex study is deferred and does not dictate the campaign
opening. Build distinct spaces, alternate routes, deliberate elevation, protected
spawns, and purposeful items. Integrate a melee start, discovered weapons and ammo,
animated enemies, and finished combat effects into the first single-player level;
an arena revision alone is insufficient. Boltgun is the visual production bar.
The existing six layouts are playable foundations,
not finished levels or proof that their reference-game comparisons were achieved.

**1. Reference preparation and consistent animation.** Specs already pass
`params.image_urls` through. Prepare reusable references with verified current
model limits, prove one complete animated character, then expand the roster.
Safe recovery and quota reconciliation precede paid batches.

[Accepted request identity](plans/asset-request-identity.md) shipped in #191,
with strict checks and all five CI jobs passing.
A live reference submission exposed a gap: rejecting polling metadata discarded
the returned request ID. Save that ID before checking the address and keep
recovery bound to it. The existing uncertain reservation still needs dashboard
reconciliation; do not buy a replacement to work around it.

**2. Surfaces, properly.** The first attempt failed for two known reasons: reduced at 128 where 256 is the floor, and no seam checking of any kind. Needs larger output, prompts that spend detail on a few big features rather than many small ones, and a seam check in the reducer that wraps the tile and compares the gradient across the join against the gradient within the body. Levels cannot get an art pass without this.

**3. Finish integrating the slice.** Three prepared idle viewmodels are in the
client. Enemy sprites, animation sets, and combat effects still need coherent
imports, silhouette review, and real encounter tests. The explicit matte reducer
is now the local preparation path; preserve internal highlights and full canvases
where muzzle registration depends on them.

**4. Animation, tested once.** Verify current image-to-video availability, price, quota and clip suitability
before a capped trial; old per-clip estimates are not a current spending quote. One test converting an enemy still into a walk cycle answers whether the sprite-sheet route works at all. If it does, it unlocks the entire animation column of the asset list; if it does not, that column needs a different plan and it is better to know now.

**5. Apply the faction and location palette.** `ART_STORY_BIBLE.md` and
`palette.json` now define institutional green, bone restoration machines and
vegetation ramps. Build and inspect consistent asset sets under each location's
light. Those authoring decisions have not recolored the live roster.

**6. Maps: the rest of what the roster needs.** Six maps from 110 m to 320 m exist, with heightfield movement, shared golden vectors, spawn validation, and reachability tests. True 3D hitscan shipped in v0.19.0. The current [navigation pass](plans/height-aware-navigation.md) adds shared walking routes and repairs the collision trap at deck exits. Remaining work from `plans/map-roster-2026.md`: three-cornered teams, zones and end conditions; permeable floors; lifts, jump pads and doors; and authored encounters.

**6b. A lighting pass.** A cover block's shadowed face is very dark up close, which in first person fills most of the frame. The ambient tint is doing all the work and there is no fill. Cheap, and it is now the worst-looking thing in the game.

**7. Full campaign foundation and M01.** `plans/campaign-build-order.md` sequences
validated map data, inventory/ammo, real enemy roles, interaction, limited continues,
text presentation and a complete authored opening. Calibration remains a shipped
prototype. M01 has a playable development slice; none of the twelve planned
missions is complete.

**8. Story presentation.** Localized framing and text/voice fallback belong in
M01. Brief pixel-styled scenes support reunion, travel, victory, sudden rupture
and aftermath. Inspect subtitles separately from diegetic propaganda. Audit old
recordings before reuse; voice and paid video are not prerequisites for proving
the first mission.

Deliberately not next: cloud, vehicles, progression, the server browser, and any further art generation beyond what item two needs. Generating more assets before item one lands is spending money to produce drift.

## Phase 0: Foundations that make everything else cheaper

Status: **in progress**. Small, high-leverage, mostly tooling.

- **Standards.** `AGENTS.md` refreshed; workspace lints in `Cargo.toml`; CI actions on current majors; coverage tool installed as a prebuilt binary; dependency advisories checked in CI. Shipped with this roadmap.
- **Godot in CI.** Shipped: the `godot` CI job runs `tools/godot_check.sh` (import, parse every script, the radio and far-cam harnesses).
- **One source for the wire.** Shipped: the adapter, the playtest harness, and the brain agent all read the wire types from `fragr-server`, so a protocol change is edited once and the compiler finds every reader. The adapter's hand-kept mirror is gone. Extracting a standalone `fragr-protocol` crate is optional tidying, not a correctness need.
- **Dev audio pipeline.** `tools/audiogen` generates sound effects and music through the ElevenLabs API for developers only, writes assets plus a manifest, and never runs in CI or at player runtime. Shipped, including speech, multi-voice dialogue, credit estimates, and wave controls.
- **Rust and GDScript only.** The procedural Python audio generator is retired; effects come from the audio pipeline and the committed files are the fallback. Shipped, with one exception still outstanding: `tools/gate_tip_jammer_orange.py` is a Python gate called by `tools/capture_tip_screenshots.sh`, so it cannot simply be deleted. It needs porting, and until it is, the rule has a hole in it.
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
3. **Sound and music.** The initial library shipped (#97, #99, #100): seven music
   stations with twenty tracks each, forty talk clips, three news beds/stings,
   basic effects and station switching/ducking. This is not a finished sound pass.
   [Radio refresh](plans/radio-refresh.md) replaces the old arena-heavy editorial
   direction with two distinct optional talk formats and music from an inhabited
   world. [Effects refresh](plans/audio-effects-refresh.md) covers weapon identity,
   movement, surfaces, pickups, machines and mix. Local candidates now exist;
   waveform checks have already rejected a malformed cue. Listening, captions,
   music distribution rights and in-game acceptance precede promotion. No runtime
   paid API, quota overage, or claim that generation alone proves quality.
4. **Bots that read as players.** Cover use, pickup seeking, target selection with memory, difficulty tiers, and behavior chips that stay truthful. Personalities you pick per match in the spirit of Perfect Dark's simulants, and hit reactions on the sprites so a fight reads like GoldenEye's did (`DESIGN-REFERENCES.md`, foundational classics). Evidence: deterministic sim tests per behavior plus a recorded spectate.
5. **Reference agents and the agent door.** An agent is one participant on the wire however it thinks: a server-run rule bot, any MCP client through the adapter, a scripted client, or a client that asks a decision model. One agent may combine a language model, other ML, and a decision model; the server sees one fighter. Reference agents of rising sophistication exist to prove the door works without touching the combat tick: the scripted reflex bot, the playtest reflex agents, and the decision-brain client (shipped, plan: `plans/decision-brain.md`), which uses a decision model rather than a chat model because a typed answer in a few hundred milliseconds fits a shooter and prose does not. Its budget gate (pre-approved cap, estimate before send, settle after, locked ledger on disk) is the pattern for any paid model the project ever calls. A planner example using `observe` and `act` every few ticks is still to come. The door itself moves to the current MCP revision (2026-07-28) with the old handshake kept only as compatibility, evaluates the official Rust SDK, and gets a team blackboard before any A2A surface (plan: `plans/agent-door-2026.md`). Evidence: adapter transcripts committed under `docs/skills/`, an integration test for the scripted levels, a three-era protocol compatibility test.
6. **Agents that field agents.** One adapter process runs a roster of scripted bots, and an agent can request a rule bot teammate through an MCP tool. Server enforces the roster cap. This is the team blackboard rung of `plans/agent-door-2026.md`. Evidence: adapter tests and a recorded session.
6b. **Agent playtest loop.** Local agents play the game and file structured feedback so most iteration does not need human testers: a `playtest` harness boots a server, runs N agents through the adapter for a fixed number of rounds, and emits a report (time to first frag, deaths per minute, weapon usage spread, idle time, stuck detection, pickup contention, frustration signals such as repeated spawn deaths, and free-text notes from an LLM-driven observer reading the event stream). Reports land in `.agents/` locally and a summary table in the plan doc for the change under test. Humans still judge fun; agents catch the rest. Plan: `plans/agent-playtest-loop.md`. Evidence: the harness runs in CI on a small configuration and the report format is documented. Rung 1 shipped: `tools/playtest` runs four reflex agents through one round on every PR with `--assert`.
7. **Authored campaign.** Build the twelve-mission rescue, coalition victory, sudden wipe and aftermath across Earth, Moon, Mars and a ship in a 2-3-hour successful run. Start with M01's skippable localized introduction, melee-to-found-weapon progression, distinct enemy problems and limited mission-start continues. Optional autonomous allies do not require companion controls or all-mission co-op. Every mission needs authored routes, secrets, character continuity, meaningful encounters and separate playtest evidence. Contract: [CAMPAIGN.md](CAMPAIGN.md). Treatment: [CAMPAIGN-MISSIONS.md](CAMPAIGN-MISSIONS.md). Detailed plans: [campaign/README.md](campaign/README.md). Implementation: [campaign-build-order.md](plans/campaign-build-order.md) and [framework requirements](plans/campaign-continuance.md). Earlier radio-led episodes are superseded. Evidence: complete runs, tested continues/exhaustion/save/rescue states, inspected presentation and fresh-player review.
8. **Small multiplayer on a LAN.** Two to twelve humans and agents on one server, join and leave without ghosts, spectators in the same match. Evidence: a recorded two-machine session and reconnect tests.
9. **Controller support.** Shipped in v0.8.3: gamepad join, solo, leave, fire, weapon cycle, speak, and camera on the same InputMap actions as the keyboard, plus Windows, macOS, and Linux export presets. Radio bindings on the D-pad shipped in v0.8.5. Remaining: glyph prompts.
10. **Benchmark mode, status line, and deep statistics.** `--bench N M` runs N scripted fighters on a fixed map and seed for M ticks and prints one JSON object: tick time by phase as distributions (mean, p50, p90, p99, p99.9, max) from histograms, budget headroom and overrun counts, bytes per client per tick, and a determinism check that two seeded runs match. The live status line serves the same JSON, so a benchmark and a running server read alike, and CI fails on a regression. On top of it sits an analysis layer for people who enjoy the mathematics: time-to-kill distributions, accuracy with Wilson intervals, engagement distance histograms that demonstrate the weapon triangle rather than asserting it, map and spawn balance, TrueSkill across policies with convergence reporting, dead time and pickup contention, a nerd overlay in the client, and a versioned full export in JSON and CSV. Every figure carries its sample size; a single number is a headline, never a conclusion. Plan: `plans/benchmark-and-stats.md` (rung 1 is playtest rung 3). Evidence: a benchmark table in `docs/` updated with each release.
11. **Visual QA tour and feel probes.** A manifest-driven tour drives the client through every player-facing state (boot menu, settings, warmup, join, HUD with and without a pickup, every radio station card, every weapon firing, movement and respawn, round end, boss beat, each map, agent chips) and writes dated stills, a contact sheet, and feel numbers (same-frame aim, time to first shot, acceleration curve, stop distance, snapshot age, frame time) for the agent developer to critique and turn into plan items. Plan: `plans/visual-qa-tour.md`. Evidence: a critique filed from a tour run and findings promoted into plans.

Exit bar: the fun bar below passes on a LAN session with mixed humans and agents, and a stranger can be handed the repo and reach a fight in under two minutes.

## Phase 2: Exposed server (public, still cheap)

Status: **planned**. The server becomes something you would open to the internet.

1. **Hardening.** Join tokens or a server password, per-connection message rate and size caps, idle timeouts, player and spectator caps, name validation, structured audit logs for join, leave, and rejects. Plan with settings and crates: `plans/public-server-hardening.md`. Evidence: tests for every reject path and a fuzz run over the wire parser.
2. **Protocol versioning.** `protocol_version` in `Hello` and clear rejection on mismatch (the MCP revision move lives in Phase 1 under the agent door). Evidence: compatibility tests.
3. **Transport spike.** Measure WebSocket latency under load, then prototype the UDP path described in [`TRANSPORT.md`](./TRANSPORT.md). Keep WebSocket for spectators and agents. Decide with numbers; the pass thresholds are in `plans/buttery-controls.md`. Evidence: a benchmark table in a plan doc.
4. **Snapshot efficiency.** Delta snapshots, interest management by distance, and a binary encoding option once the JSON path is measured. Evidence: bytes per tick per client before and after.
5. **Reconnect and resume.** A session token that reattaches a dropped human or agent to its pawn within a grace window. Evidence: tests plus a recorded kill-and-reconnect.
6. **Status endpoint and server list.** A tiny read-only status response (map, players, round) so a server browser or a Discord bot can show what is live, plus the benchmark mode that prints tick and bandwidth percentiles (`plans/public-server-hardening.md`). Evidence: documented and tested.
7. **Desktop exports.** Presets for Windows, macOS, and Linux shipped (#88). Remaining: built on tags in CI and attached to releases. Evidence: a release with binaries that boot to Solo Scrap.
8. **Observability.** Tick time histogram, per-client bandwidth, crash-free uptime, and a health check. Evidence: metrics visible in logs during a load test.
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
- **Maps that teach.** Verticality, flow loops, item control, and named callouts. Learn from the best Unreal Tournament arenas: every corridor has a reason and every fight has a second option.
- **Bigger modes.** Team deathmatch with COD-sized squads first, then objective control on larger maps with vehicles in the spirit of Battlefield 1942 conquest, without borrowing its art. Vehicles are server-authoritative entities on the same action path. Mode twists as mutators before any of that: one-shot rail only, scatter only, one golden rail on the map, the couch-multiplayer feeling GoldenEye had, cheap to build on the existing rules.
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
| Phase 1.1: movement and gunfeel | `plans/gunfeel.md` (weapons and aim), `plans/buttery-controls.md` (netcode plumbing) | gunfeel rung 2 (weapon table) next; buttery stage 2 after 4 |
| Phase 1.2: look pass | `plans/look-pass-boomer.md`, assets from `plans/art-pipeline.md` | 8 (stage 1); art rung 1 (the Rust tool) any time, paid rungs after written approval |
| Phase 1.3: sound and music | `plans/radio-stations.md` (shipped; bumpers and Host voice remain) | |
| Phase 1.4: bots that read as players | plan needed | after campaign rung 2 |
| Phase 1.5: reference agents and the door | `plans/decision-brain.md` (shipped), `plans/agent-door-2026.md` | 7 |
| Phase 1.6: agents that field agents | `plans/agent-door-2026.md` rung 3 | |
| Phase 1.6b: playtest loop | `plans/agent-playtest-loop.md` | 4 (rung 3 status line and bench), 6 (rung 2 planner tier) |
| Phase 1.7: compact campaign | [contract](CAMPAIGN.md), [treatment](CAMPAIGN-MISSIONS.md), [12 level plans](campaign/README.md), [build order](plans/campaign-build-order.md), [frameworks](plans/campaign-continuance.md) | M01 foundation and authored mission after story/route review |
| Phase 1.8: LAN | plan needed (evidence note under `docs/evidence/`) | |
| Phase 1.9: controller | `plans/controller-and-desktop-platforms.md` (shipped; glyphs remain) | |
| Phase 1.10: benchmark, status line, statistics | `plans/benchmark-and-stats.md` (rung 1 is `plans/agent-playtest-loop.md` rung 3) | 4 |
| Phase 1.11: visual QA tour | `plans/visual-qa-tour.md` | 2 |
| Phase 2.1, 2.2, 2.6, 2.8: hardening, protocol version, status, observability | `plans/public-server-hardening.md` | after Phase 1 |
| Phase 2.3: transport spike | `plans/buttery-controls.md` stage 7 | |
| Phase 2.4: snapshot efficiency | `plans/massive-arenas.md` | rung 1 (seed and grid) any time; rungs 2 to 4 after buttery stage 2 |
| Phase 2.5: reconnect and resume | plan needed | |
| Phase 2.7: desktop exports on tags | plan needed (small) | |
| Phase 2.9: strangers | `plans/public-server-hardening.md` rung 5 | |
| Phase 2.10: fair play | `plans/fair-play.md` | rung 1 with buttery stage 1 |
| Phase 4: localization | `plans/localization.md` | rung 1 after the settings menu exists |
| Phase 3: cloud | `plans/terraform-zero-cost-gcp.md` (plan only until approved) | |
| Phase 4 | plans written when each item is next | |

The first PR in that order is this docs sync itself.

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
- **Validated everywhere it claims to run.** A two-machine LAN session, a public server that stays up for a week with strangers on it, agents playing as rule bots, through the adapter, and as the decision-brain client, the single-player campaign complete through episode one, and desktop exports for Windows, macOS, and Linux that boot to Solo Scrap on a clean machine.
- **Extremely polished.** No placeholder art anywhere: every weapon, fighter, map surface, and HUD element final; the radio, effects, and Host voice complete; onboarding to a fight in under a minute with no docs; a twenty-four hour soak with no crash, proven by the status JSON at start and end in the release notes; the fun bar passing on a recorded session; boot to first snapshot under ten seconds as measured by the playtest report; docs and hosting guides current.
- **Hardened and honest.** The exposed-server phase complete (join tokens, rate and size caps, protocol versioning, reconnect resume, status endpoint, fair-play lanes and the profiler), the playtest harness thresholds tightened to the shipped feel, no known bugs that lose a round, and a changelog that matches the releases.
