# Plans

Bounded work lives here as one file per item, written **before** implementation starts. Sequencing across items lives in [`../ROADMAP.md`](../ROADMAP.md). Chat is never the plan of record.

Each plan covers: goal, non-goals, architecture impact, protocol or API changes, verification, spend and safety gates, and success criteria. When the work ships, update the plan's status here and in the roadmap in the same PR.

Status words: **proposed** (a design awaiting Nick's decision; directs no work), **planned**, **in flight**, **implemented** (local evidence recorded; linked task tracks integration), **shipped** (merged to `main`, PR number noted), **proven** (shipped plus evidence), **superseded** (kept for history, no longer directs work).

## Standing facts

- Game port is **6767** (TCP today; UDP reserved for the planned low-latency transport).
- Local play is $0. Public hosting sits under the $50 cap and needs written approval before anything bills. GCP Terraform stays plan-only until then.
- Tailscale is private smoke only, never the documented join path.
- The dedicated server bar is rock solid, secure, and cheap: input validation, rate limits, clean join and leave and reconnect, and a home box or small VM first.

## Index

| Plan | Status | One-liner |
|---|---|---|
| [`replayability.md`](./replayability.md) | **proposed** | Counter-Strike level replay: loops at three time scales, Jammer as a round-based flagship with scrip and lineups, mutators, Host reactions, agent rivals, feats, demos from the trace, and a build order. |
| [`campaign-expansion.md`](./campaign-expansion.md) | **planned**, accepted 2026-09-25 | Twenty levels in five episodes for a four-hour first run, now the contract in [CAMPAIGN.md](../CAMPAIGN.md): the ten-mission spine kept, one new thing per level, the wipe in three levels, a brief by difficulty, par and replay waivers. The 2026-09-25 deep dive adds the [story arc](../campaign/story-arc.md), a full design per level and the pacing curve; the story arc itself stays proposed. |
| [`m01-secret-shiv.md`](./m01-secret-shiv.md) | **shipped** ([#251](https://github.com/blisspixel/fragr/pull/251), v0.53.0) | M01's first secret: a pool-less Shiv in the confiscation alcove's south pocket, found by walking in, with capability 11, a quiet cue and a counted find. Replaces draft #203. |
| [`heavy-sweeper-and-turret.md`](./heavy-sweeper-and-turret.md) | **shipped** ([#245](https://github.com/blisspixel/fragr/pull/245), v0.50.0) | Heavy Sweeper and Turret on the encounter seams with seeded tell tests, a test range, and the black and red Union recolor. |
| [`input-all-devices.md`](./input-all-devices.md) | **shipped** ([#246](https://github.com/blisspixel/fragr/pull/246), v0.51.0) | Keyboard only, keyboard and mouse, and gamepad: rebinding page, key turn ramp, radial stick curves, device-following pad glyphs and aim assist that never touches the mouse. |
| [`boomer-ammo-and-pellets.md`](./boomer-ammo-and-pellets.md) | **shipped** ([#243](https://github.com/blisspixel/fragr/pull/243), v0.49.0) | Doom-style ammo (one count per type, no reload) and a seven-pellet shotgun, with capability 10, rules revision 2 and a clean new-run path for magazine-era saves. |
| [`observability-soak.md`](./observability-soak.md) | **shipped** ([#244](https://github.com/blisspixel/fragr/pull/244), v0.50.1) | Tick percentiles, traffic and health on `/status`, a soak harness sampling it into NDJSON, and two recorded local runs over an hour. |
| [`spawn-quality.md`](./spawn-quality.md) | **shipped** ([#237](https://github.com/blisspixel/fragr/pull/237), v0.47.1) | Spawn pockets on maps 3 to 5, lanes counted only inside rail reach, and an opening spawn-death gate; 47 to 7 spawn deaths over 16 runs. |
| [`rust-tip-gate.md`](./rust-tip-gate.md) | **shipped** ([#239](https://github.com/blisspixel/fragr/pull/239), v0.47.1) | Port the last Python file, the jammer tip screenshot gate, to a Rust tool with identical verdicts. |
| [`desktop-release.md`](./desktop-release.md) | **shipped** ([#233](https://github.com/blisspixel/fragr/pull/233), v0.47.0) | Tagged Windows, Linux and macOS zips with the bundled server, a packaged install check, and an original game icon. |
| [`radio-scene-retirement.md`](./radio-scene-retirement.md) | **proven** ([#231](https://github.com/blisspixel/fragr/pull/231), v0.45.0) | Radio decoder retirement across rapid saved-run restarts, with Linux, Windows and macOS checks. |
| [`m02-objective-gates.md`](./m02-objective-gates.md) | **in flight** | Authored objectives and precomputed gate worlds for the first M02 graybox, with M01 save compatibility. |
| [`flying-drones.md`](./flying-drones.md) | **planned** | Notary patrol drone for M03 and armored Assessor for M07 on the encounter seam: hover, air routing, committed tells, crashes. |
| [`multiplayer-maps.md`](./multiplayer-maps.md) | **proposed** | Rule sheet for multiplayer maps, sixteen proposed maps from duel rooms to conquest-lite fronts, a verdict on the six current maps, and the mode order. |
| [`vehicles.md`](./vehicles.md) | **planned** | Jeep, motorcycle and jetpack, each built only when its mission (M08, M09, M10) is next; multiplayer vehicle map in Phase 4. |
| [`campaign-run-file.md`](./campaign-run-file.md) | **proven** ([#229](https://github.com/blisspixel/fragr/pull/229), v0.45.0) | Versioned local solo run persistence, exact continue restoration and retained M01 exit equipment. |
| [`jev-m01-validation.md`](./jev-m01-validation.md) | **proven** ([#228](https://github.com/blisspixel/fragr/pull/228)) | Capped Jev M01 Standard and Severe trials with authoritative receipts and actual spend evidence. |
| [`m01-opening-weapon-input.md`](./m01-opening-weapon-input.md) | **shipped** ([#226](https://github.com/blisspixel/fragr/pull/226)) | Same-session MapInfo, phase-card timing, and key 1 through a live owned M01 server are covered. |
| [`bounded-spectator-fanout.md`](./bounded-spectator-fanout.md) | **shipped** ([#224](https://github.com/blisspixel/fragr/pull/224), v0.44.1) | Bounded slow watcher delivery with a twelve-roster local load matrix; remote-network and TLS evidence remains. |
| [`m01-failure-timeline.md`](./m01-failure-timeline.md) | **shipped** ([#227](https://github.com/blisspixel/fragr/pull/227)) | Bounded free-run M01 trace, seeded failure diagnosis and a tested terminal-record correction. |
| [`m01-optional-supply-detours.md`](./m01-optional-supply-detours.md) | **shipped** (v0.44.0) | Two reachable optional supply spaces in Recall Notice, with claim and continue checks. |
| [`jev-campaign-decisions.md`](./jev-campaign-decisions.md) | **shipped** ([#223](https://github.com/blisspixel/fragr/pull/223)) | Align brain questions, equipment, objectives and terminal receipts with the authored campaign before paid Jev tests. |
| [`agent-first-person-watch.md`](./agent-first-person-watch.md) | **shipped** ([#219](https://github.com/blisspixel/fragr/pull/219), v0.43.1) | Render and verify one live agent's first-person view against its server identity and free-rule receipt. |
| [`jev-budget-reservations.md`](./jev-budget-reservations.md) | **shipped** ([#218](https://github.com/blisspixel/fragr/pull/218)) | Durable pre-send Jev receipts and one shared paid request at a time, with recovery and no-ledger refusal. |
| [`display-quality.md`](./display-quality.md) | **implemented** ([#202](https://github.com/blisspixel/fragr/pull/202)) | Fullscreen default, real resolution selection and portable graphics presets through the shared settings panel. |
| [`audio-startup-polish.md`](./audio-startup-polish.md) | **shipped** (#201, v0.32.0) | Balanced default effects and music, preserved saved choices, approved logo in the engine splash. |
| [`combat-notification-polish.md`](./combat-notification-polish.md) | **shipped** (#201, v0.32.0) | Three independently expiring corner notices, participant-only pickups and clear aiming; inspected live arena and campaign captures. |
| [`m01-completion.md`](./m01-completion.md) | **in flight** (#195) | Routes through v0.40.0. Silhouettes separated in v0.43.0. Live check 2026-09-22 confirmed the wheel, the pistol label, and a clerk on screen. The intro card returned later in that run, and key 1 did not leave the pistol. Static supply detours shipped in v0.44.0; automated mission checks continue, with human acceptance near 1.0. |
| [`difficulty-and-rewards.md`](./difficulty-and-rewards.md) | **in flight** (#197) | New-run campaign difficulty first; persistent achievements and cosmetic rewards follow the save/retry contract. |
| [`tripoint-spawn-safety.md`](./tripoint-spawn-safety.md) | **shipped** (#193, v0.28.0) | Cover the exposed starting ring, prove all 16 routes and sightlines, and retain measured respawn limitations. |
| [`m01-opening.md`](./m01-opening.md) | **shipped** (#193, v0.28.0) | Reader-paced recall story, replay and authoritative initial/late party readiness. |
| [`asset-request-identity.md`](./asset-request-identity.md) | **shipped** (#191) | Save accepted paid-job identity before validating polling metadata; recover without resubmitting. |
| [`mission-wire-order.md`](./mission-wire-order.md) | **shipped** (#189, v0.27.1) | Queue initial geometry before broadcasts; prove shared departure without depending on socket scheduling. |
| [`opening-spawns.md`](./opening-spawns.md) | **proven** (#175, v0.21.2) | Apply covered spawn selection before the opening fight as well as during play. |
| [`shared-body-integration.md`](./shared-body-integration.md) | **proven** (#174, v0.21.1) | One body-collision integrator for the authority and movement mirror. |
| [`campaign-spaces.md`](./campaign-spaces.md) | **proven** (#176, v0.22.0) | Real ceilings, accessible balconies, layered routes and matching collision/rendering for M01. |
| [`authored-campaign-maps.md`](./authored-campaign-maps.md) | **proven** (#177, v0.23.0) | Validated map files, explicit indoor spawns and M01's traversal blockout through the live server. |
| [`m01-weapon-discovery.md`](./m01-weapon-discovery.md) | **proven** (#179, #181, v0.24.0) | Fists-to-Tack/Flechette discovery, finite ammunition, reload and compatible human/agent presentation. |
| [`readable-arsenal.md`](./readable-arsenal.md) | **in flight** | v0.41.0 shipped Pistol, Rifle, Shotgun, and Railgun. v0.42.0 shipped the wheel and number keys. Sniper, rocket, grenade, and both mines stay later campaign finds and are not implemented. |
| [`m01-intake-encounter.md`](./m01-intake-encounter.md) | **in flight** ([#180](https://github.com/blisspixel/fragr/issues/180)) | Authored human Clerk and Sweeper bot fights, explicit hostility, readable attacks and inspected motion. |
| [`m01-facility-detail.md`](./m01-facility-detail.md) | **shipped** (#182, v0.25.0) | Bounded surface details, localized signs and practical lights make the intake rooms legible. |
| [`m01-mission-sequence.md`](./m01-mission-sequence.md) | **shipped** (#184, v0.26.0) | Physical transfer-record interaction, authoritative lift gate and shared departure state. |
| [`local-campaign-entry.md`](./local-campaign-entry.md) | **shipped** (#187, v0.27.0) | Start the correct local campaign server from Single Player and own its complete lifetime. |
| [`gpu-bot-compute.md`](./gpu-bot-compute.md) | **planned** | Portable optional GPU perception/inference, measured against CPU queries with rendering contention and fallback. |
| [`audio-effects-refresh.md`](./audio-effects-refresh.md) | **in flight** | Distinct weapon, movement, impact and world sounds; capped candidates and in-game mix verification. |
| [`radio-refresh.md`](./radio-refresh.md) | **in flight** | Two fictional talk formats and world-appropriate music; staged pilots, captions and distribution review. |
| [`campaign-scenes.md`](./campaign-scenes.md) | **planned** | Between-mission pixel text first. Spoken clips after the page is frozen. Seedance video waits until the playable campaign is built. |
| [`inheritance-benchmark.md`](./inheritance-benchmark.md) | **later** | Research-grade agent strategy/wipe simulation; controlled budgets, held-out tasks, replay and validated capability claims. |
| [`campaign-story-alignment.md`](./campaign-story-alignment.md) | **shipped** (#173) | Original world alignment and treatment. Superseded by the ten-mission/epilogue contract, itself superseded 2026-09-25 by twenty levels in five episodes; design only. |
| [`authored-compliance-yard.md`](./authored-compliance-yard.md) | **deferred** | Multiplayer spatial study; the campaign opening now has its own M01 brief. |
| [`height-aware-navigation.md`](./height-aware-navigation.md) | **proven** (#172, v0.21.0) | Shared routes, stair/jump and ledge recovery, covered spawns, weapon anchoring and pointer lifecycle. |
| [`shot-impact-feedback.md`](./shot-impact-feedback.md) | **proven** (#171, v0.20.0) | Authoritative world impacts and rail traces, with complete combat accounting. |
| [`vertical-aim.md`](./vertical-aim.md) | **proven** (#170, v0.19.0) | True vertical combat, three-dimensional cover, and matching spectator eye views. |
| [`asset-request-recovery.md`](./asset-request-recovery.md) | **proven** (#169) | Durable request recovery and authenticated-origin checks before more paid art generation. |
| [`player-settings.md`](./player-settings.md) | **proven** (#168, v0.18.0) | Persistent controls, display, and audio through one validated retro panel in boot and match menus. |
| [`arena-surface-pass.md`](./arena-surface-pass.md) | **proven** (#167, v0.17.0) | Industrial pixel surfaces and a readable arena backdrop, preserving server collision geometry. |
| [`local-excellence.md`](./local-excellence.md) | **in flight** | Cohesive local polish through verified instructions, reliable checks, art integration, and repeated visual and playtest review. |
| [`solo-story-episodes.md`](./solo-story-episodes.md) | **shipped** (#106) | Solo Broadcast Episode 0 Calibration / Larak Lot face + juice bar. |
| [`tip-stills-ep0.md`](./tip-stills-ep0.md) | **shipped** (#110) | Recapture tip stills + README Solo Broadcast face after Episode 0. |
| [`ep0-nods-progress-fix.md`](./ep0-nods-progress-fix.md) | **shipped** (#111) | Calibration NODS credit for meatbags, jammer dish silhouette, map_name honesty. |
| [`jammer-dish-silhouette.md`](./jammer-dish-silhouette.md) | **shipped** (#116) | Unmissable Godot jammer dish silhouette in-camera for Solo Broadcast phase two. |
| [`jammer-dish-unmissable.md`](./jammer-dish-unmissable.md) | **shipped** (#123) | Studio dish unmissable + footprint harness; live tip_capture gap owned by live-tip-dish-map-chip. |
| [`live-tip-dish-map-chip.md`](./live-tip-dish-map-chip.md) | **shipped** (#125) | Live tip_capture hangar dish + kill Hangar Candy dual map chip on Larak Lot. |
| [`tip-capture-dish-gate.md`](./tip-capture-dish-gate.md) | **shipped** (#129) | Live tip_capture hangar dish gate: tip_force survives seize, pose lock, orange pixel CI. |
| [`first-calib-seize-stall.md`](./first-calib-seize-stall.md) | **shipped** (#131) | Soft first Calibration jammer seize: pad radius matches eyes so meatbag does not soft-lock. |
| [`tip-capture-dish-pose.md`](./tip-capture-dish-pose.md) | **in flight** | Tip pose lock held transform + chunky dish look-at so orange gate PASSES on stranger re-run. |
| [`tip-stills-hangar-guns.md`](./tip-stills-hangar-guns.md) | **in flight** | README tip face: v0.13.0 hangar dish + guns that kill (not Episode 0 lead). |
| [`host-per-nods-tick.md`](./host-per-nods-tick.md) | **shipped** (#120) | Soft juice: Host / HUD beat on every Solo Broadcast NODS clear, not only the first. |
| [`spectator-stance-chips.md`](./spectator-stance-chips.md) | **shipped** (#119) | Loud Tab-less stance chips on Warmup TV, follow HUD, and nameplates. |
| [`art-pipeline.md`](./art-pipeline.md) | **planned** | Sprites, weapons, icons, and tiles through two pixel-art-native services plus a Rust post-processor and touch-up; provenance recorded; spend gated. |
| [`fair-play.md`](./fair-play.md) | **planned** | Anti-cheat that keeps it fun: validated inputs, lanes for humans and agents, a behaviour profiler, replays as evidence, no kernel drivers. |
| [`localization.md`](./localization.md) | **planned** | Keys for every string, the basics plus regional, community-signed, and lore locales, fonts and layout, a tour per locale. |
| [`benchmark-and-stats.md`](./benchmark-and-stats.md) | **shipped** (#201, v0.32.0) | Authoritative counts, retained campaign/arena/practice records, retro service-record menu, JSON export and optional factual quips; CPU benchmark shipped earlier. |
| [`massive-arenas.md`](./massive-arenas.md) | **planned** | Seeded sim, spatial grid, interest sets, delta snapshots, binary wire, tick budget, and the measured scale ladder to hundreds of fighters. |
| [`visual-qa-tour.md`](./visual-qa-tour.md) | **rung 1 landed** | Manifest-driven tour of every player-facing state with stills, a contact sheet, and feel probes for the agent developer to critique. |
| [`showcase-benchmark.md`](./showcase-benchmark.md) | **rung 1 shipped** (#166) | Reproducible traces and honest CPU measurements; a rendered showcase with frame-time analysis follows. |
| [`weapon-economy.md`](./weapon-economy.md) | **spec** | The pickup economy does not exist: weapon swaps are free, so nobody races for anything. Four shared ammo pools, eight guns, melee, a thrown mine, and the clock-versus-loop rule that creates item timing. |
| [`shot-feedback.md`](./shot-feedback.md) | **spec** | A hit and a miss look identical in the world. The server says where a shot ended, tracers and impacts follow, and a ninety degree yaw mismatch between server and client gets settled by a harness. |
| [`map-roster-2026.md`](./map-roster-2026.md) | **shipped** | Six maps from 110 m to 320 m, a heightfield in the shared movement step, and a map built for the three-cornered mode. |
| [`map-scale.md`](./map-scale.md) | **spec** | Maps that are maps: a size ladder from pit to field, height in the shared movement step, and the Doom, Unreal, Halo and 1942 references each tier answers to. |
| [`hud-rebuild.md`](./hud-rebuild.md) | **spec** | Replace the HUD rather than trim it. Health, armour and ammo on screen, the broadcast strip out of gameplay, one font and one grid, judged against modern boomer shooters. |
| [`hud-quiet.md`](./hud-quiet.md) | **in progress** | Get the words off the screen. Measured HUD coverage per state, clipped panels, duplicate badges, and nameplates that hide the fighter behind them. |
| [`gunfeel.md`](./gunfeel.md) | **in flight** (aim defaults shipped) | What the weapons and the aim do: the parameter set from the classics, dispersion separated from aim assist, feedback timings, the dodge. |
| [`ttk-feel-harness-proof.md`](./ttk-feel-harness-proof.md) | **in flight** | Sticky flechette/rail/scatter TTK asserted from playtest `--assert` (#124 proof). |
| [`buttery-controls.md`](./buttery-controls.md) | **planned** | Client-owned yaw, prediction and reconciliation, timeline interpolation, 60 Hz sim, lag compensation, gamepad curves, transport spike, all with pass numbers. |
| [`public-server-hardening.md`](./public-server-hardening.md) | **in flight** | Caps v0.35.0, `GET /status` v0.36.0, the app match line v0.37.0, join tickets v0.38.0, pawn resume v0.39.0. Next is a measured spectator fan-out. TLS remains. |
| [`agent-door-2026.md`](./agent-door-2026.md) | **planned** | MCP 2026-07-28 compliance with legacy clients kept, the rmcp decision, a team blackboard before A2A. |
| [`decision-brain.md`](./decision-brain.md) | **shipped** (#102) | Decision-brain agent: Jev (TypeSafe or OpenRouter) sets intent a few times a second, local controller plays every tick, hard spend cap with a ledger. |
| [`brain-third-tier-surface.md`](./brain-third-tier-surface.md) | **shipped** (#103) | Surface fragr-brain beside rule bots and MCP agents in the skill card and README, plus the observe-only stance chip. |
| [`radio-stations.md`](./radio-stations.md) | **shipped** (library) | Contested Frequency radio: eight stations, generated library, client player with ducking. |
| [`look-pass-boomer.md`](./look-pass-boomer.md) | **in flight** | Boomer shooter look pass. Increment 1: fixture-lit interiors, venue fog and red Union accents, optional world pixels and palette dither. Atlas, sprites, view models and HUD grid remain. |
| [`campaign-build-order.md`](./campaign-build-order.md) | **planned** | Prove twenty levels in five episodes and the survival-gated epilogue, starting with M01 (level 1) and limited mission-start continues refilled each episode. |
| [`campaign-e1.md`](./campaign-e1.md) | **superseded** | Earlier radio-led nine-level episode; current mission treatment lives in `../CAMPAIGN-MISSIONS.md`. |
| [`campaign-continuance.md`](./campaign-continuance.md) | **planned** | Validated map data, authoritative mission/enemy state, saves and localized presentation; no editor dependency selected yet. |
| [`campaign-continues.md`](./campaign-continues.md) | **shipped (#200, v0.31.0)** | Explicit solo M01 run, three mission-start continues, authoritative retry and exhaustion; broader mission work stays on #195. |
| [`agent-playtest-loop.md`](./agent-playtest-loop.md) | **in flight** (rung 1 shipped, #95) | Playtest harness: scripted agents play rounds and file a metrics report; thresholds run in CI. |
| [`warmup-tv-bumper.md`](./warmup-tv-bumper.md) | **shipped** (#89) | Full-frame Warmup TV bumper: map title, roster chips, countdown, Host flash lingering into Active. |
| [`controller-and-desktop-platforms.md`](./controller-and-desktop-platforms.md) | **shipped** (#88) | Gamepad join, solo, and match input on the same action path; Windows, macOS, and Linux export presets. |
| [`bug-hunt-polish-pass.md`](./bug-hunt-polish-pass.md) | **shipped** (#90) | Tip feel polish: boss down round-end wipe, layout null guard, spectator cam validity, net send hardening. |
| [`l5-vs-nods-why-fight.md`](./l5-vs-nods-why-fight.md) | **shipped** (#87) | Solo Broadcast and L5 versus NODS: the why-fight spine folded into LORE and VISION. |
| [`arty-gold-face-pack.md`](./arty-gold-face-pack.md) | **shipped** (#86) | Gold face pack: Cyanex and Kragge gold idle billboards plus broadcast HUD chrome. |
| [`rule-bot-taunts.md`](./rule-bot-taunts.md) | **shipped** (#85) | Named rule bots speak Contested Frequency scrap-radio taunts. |
| [`public-or-local-join.md`](./public-or-local-join.md) | **shipped** (#84) | Docs scrub: public OR local join; Tailscale private only; spend honesty. |
| [`warmup-host-drama.md`](./warmup-host-drama.md) | **shipped** (#83) | Warmup and pre-round Host countdown drama (roster, map, bumper). |
| [`named-scrap-bots.md`](./named-scrap-bots.md) | **shipped** (#82) | Contested Frequency named rule-bot roster and Host intros. |
| [`ended-linger-mvp-rehydrate.md`](./ended-linger-mvp-rehydrate.md) | **shipped** (#81) | Ended linger plus mid-join structured MVP rehydrate. |
| [`second-scrap-map.md`](./second-scrap-map.md) | **shipped** (#80) | Second Contested Frequency scrap map (Compliance Yard). |
| [`round-end-mvp-drama.md`](./round-end-mvp-drama.md) | **shipped** (#79) | Round-end MVP and podium Host drama. |
| [`coverage-climb-main.md`](./coverage-climb-main.md) | **shipped** (#78) | Climb unfiltered coverage by testing server and adapter main shells. |
| [`tip-stills-recapture.md`](./tip-stills-recapture.md) | **shipped** (#77) | Recapture tip stills after weapon roles. |
| [`weapon-roles-excellence.md`](./weapon-roles-excellence.md) | **shipped** (#76) | Flechette, Rail, and Scatter roles that read in the hand. |
| [`killstreak-host-juice.md`](./killstreak-host-juice.md) | **shipped** (#75) | Multi-kill Host callouts and HUD flash at streak 2, 3, 5. |
| [`human-join-fp-juice.md`](./human-join-fp-juice.md) | **shipped** (#74) | Join first-person juice: crosshair, weapon face and bob, spawn and damage flash. |
| [`reconnect-and-godot-null.md`](./reconnect-and-godot-null.md) | **shipped** (#73) | Clean reconnect (no ghost) plus Godot add_child null guard on pads. |
| [`arena-choke-geometry.md`](./arena-choke-geometry.md) | **shipped** (#72) | Arena choke geometry: low walls, crates, pillar cover, server collision. |
| [`health-pads.md`](./health-pads.md) | **shipped** (#71) | Mid-arena health and light armor pads. |
| [`weapon-pickups.md`](./weapon-pickups.md) | **shipped** (#70) | Mid-map weapon pickups for chase energy. |
| [`continuance-sp-boss.md`](./continuance-sp-boss.md) | **shipped** (#69) | Mid-round Compliance Drone boss beat for Solo Scrap. |
| [`solo-boot-and-scrap.md`](./solo-boot-and-scrap.md) | **shipped** (#68) | Single-player first-class solo boot-and-scrap versus local rule bots. |
| [`far-cam-fighter-scale.md`](./far-cam-fighter-scale.md) | **shipped** (#67) | Distance-aware fighter billboard scale for far spectators. |
| [`pixel-3d-look-bar.md`](./pixel-3d-look-bar.md) | **shipped** (#66) | Pixel-3D look bar: materials, billboards, lighting, tip stills. |
| [`mcp-session-tools.md`](./mcp-session-tools.md) | **shipped** (#65) | First-class MCP join, leave, and round_state tools. |
| [`godot-host-flash-mid-join.md`](./godot-host-flash-mid-join.md) | **shipped** (#64) | Godot Host bumper flash on first mid-round Snapshot. |
| [`sticky-host-line-mid-join.md`](./sticky-host-line-mid-join.md) | **shipped** (#63) | Sticky Snapshot host_line for mid-join Host chrome. |
| [`offtick-speak-taunt.md`](./offtick-speak-taunt.md) | **shipped** | Off-tick speak and taunt for agents; spectators and MCP events. |
| [`mode-fantasy-contested-frequency.md`](./mode-fantasy-contested-frequency.md) | **shipped** | Contested Frequency named mode plus Continuance compliance ping. |
| [`agent-aim-hit-confirm.md`](./agent-aim-hit-confirm.md) | **shipped** | look_at plus shot_results and hit observe feedback. |
| [`testy-playtest-fixes.md`](./testy-playtest-fixes.md) | **shipped** | Join and leave events plus junk-act reject. |
| [`fragr-exceptional-game.md`](./fragr-exceptional-game.md) | **superseded** by `../ROADMAP.md` | Earlier finish-line framing; kept for the decisions it records. |
| [`slice1-exceptional-polish.md`](./slice1-exceptional-polish.md) | **shipped** | Slice 1 polish foundation (PR #1 era). |
| [`fun-playable-pass.md`](./fun-playable-pass.md) | **shipped** | Fun face, sprites, match drama toward v0.2 to v0.4. |
| [`weapons-system.md`](./weapons-system.md) | **shipped** (v0.3.0) | Flechette, rail, and scatter roles. |
| [`client-assets-wiring.md`](./client-assets-wiring.md) | **shipped** | Pixel assets wired into the Godot client. |
| [`audio-drama.md`](./audio-drama.md) | **shipped** | Match audio drama with procedural CC0 audio. |
| [`terraform-zero-cost-gcp.md`](./terraform-zero-cost-gcp.md) | **shipped** (plan-only, PR #5) | Zero-cost GCP IaC; no apply without approval. |
| [`tip-screenshots.md`](./tip-screenshots.md) | **shipped** (#60) | Tip screenshot capture (Xvfb, Viewport API). |
| [`honest-coverage-lock.md`](./honest-coverage-lock.md) | **shipped** | Unfiltered llvm-cov fail-under 80; no carve-outs. |
| [`SPRINT-24H.md`](./SPRINT-24H.md) | **superseded** | 24 hour sprint framing. |
| [`elevenlabs-later.md`](./elevenlabs-later.md) | **superseded** by `tools/audiogen` | Spend approved 2026-09-18 for developer-side generation only; see `tools/audiogen/README.md`. |
