# M04 Notice to Vacate prototype

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Continues the
[M03 prototype](m03-scheduled-service-prototype.md). This is a playable prototype
gate, not acceptance of the complete eleven-minute mission or campaign.
**Spend:** $0 new cash charges. The current development round has a $20 combined
external charge ceiling within the repository's $50 total ceiling. Original
Notary/environment art and effects use local tools. The separately bounded
[transition audio batch](campaign-transition-audio.md) used 475 approved existing
credits; the prepared image API batch was not submitted.

The later [M05 increment](m05-no-forwarding-address-prototype.md) supersedes
this plan's live capability 25 and save version 5. Current authored missions
require capability 26 with unchanged rules revision 3; strict historical saves
upgrade to version 6. M04 choices now carry through playable M05 and its retries.
Earlier receipts below retain the contracts and measurements actually tested.

## Goal

Make the accepted [M04 brief](../campaign/l04-notice-to-vacate.md) playable:
an original Low Water market, optional clinic, habitation court and roof exit;
the first shootable Notary, readable locked-aim photographs and harmless falling
wrecks; exact M03 carry into M04 and a durable pending M05 boundary. Polish the
close companion view without changing the authoritative body or blocking rules.

## Non-goals

No Assessor, player flight, general volumetric navigation, vehicle simulation,
paid asset generation, cloud apply, release publication or claim of fresh-player
acceptance. M05 remains unbuilt. Keep M01, M02 and M03 authored bytes unchanged.
Clinic rescue and civilian travel never become a mandatory escort or wait gate.

## Architecture and contracts

- The existing Rust encounter controller owns Notary flight, locked aim, burst,
  interruption, damage, death fall and support. Strict authored hover volumes
  and short patrol segments replace ground navigation for this bounded pilot;
  general lifted-route fallback remains separate work.
- The Notary is a 50 HP raised box, about 1.3 by 0.7 metres, at ordinary weapon
  range. It never attacks directly overhead. Assisted, Standard and Severe use
  the accepted 24/36, 16/26 and 12/20 tick windup/recovery rows. Rules revision 3
  records these new timings; earlier enemy rows remain unchanged.
- Map 1004 uses capability 25 and a mutually exclusive strict `m04` definition.
  Six ordered objective encounters lead to deliberate shared roof departure.
  One locally operated clinic shutter has exactly two worlds prepared before
  readiness. Its optional patients use bounded grounded routes; position is
  presentation, not mission-completion authority. MapInfo precedes changed
  mission facts for every role.
- Use the existing mission controller, readiness, continue, equipment,
  statistics, MCP and local process channels. A photograph counter counts the
  first resolved round hitting its original live, active and ready participant
  once per committed burst, independently of damage amount. Seeded evidence
  must distinguish interruption, locked-aim dodge and cover. Later burst rounds
  never add photographs.
- A versioned local save preserves run identity, equipment, body, difficulty,
  continues and completed M03 choices through M04 entry and retries. Explicit
  version-specific upgrades validate historical rules before promoting to the
  new revision, archive exact old bytes and retain replacement failure safety.
  Completed M04 rescue and photograph outcomes survive the pending M05 edge.
- Client validation, HUD, scenes, records and local launch recognize M04 through
  existing seams. An original offline directional Notary atlas and spatial fan,
  shutter and crash cues follow server facts, including late-join suppression.
  The passive M02 tableau remains passive. Companion near-camera presentation
  cannot shrink its body, draw through walls or decide collision.

## Parallel ownership

Server work owns strict authoring, mission/runtime protocol, encounter flight,
combat and deterministic tests. Client work owns strict mission/UI/local/story
boundaries and offline audio. Map work owns the original M04 data and ordinary
input QA route. Integration owns run storage/migration, local server launch,
Notary art/rendering, shared match glue, world dressing and documentation.
Separate child plans record final fields, commands and evidence.

## Verification and success criteria

1. Strict authoring rejects unsafe flight, unreachable required routes, invalid
   clinic states and unsupported schema combinations. Tests exercise all tiers,
   windup interruption, locked-aim dodge/cover, raised hit geometry, death support,
   retry cleanup, optional rescue and live shared roof departure.
2. Save tests cover M03 to M04 exact carry, historical migrations, immutable
   content validation, retry baseline, retained outcomes, corrupt input and
   failed locked replacement. A real owned local child validates readiness and
   isolated save behavior.
3. Full Rust formatting, lint, tests, release build, unfiltered 90 percent
   coverage, dependency checks, benchmark, match/CTF/roster and soak checks pass.
   Pinned Godot import, parse, harnesses and checker self-tests pass with clean
   logs and explicit PASS markers. Record unavailable container tooling.
4. Run and inspect the standard published visual tour and a named M04 tour
   through ordinary actions. Inspect Notary tell, flight, crash, clinic, market,
   court and roof stills plus motion strips; record actual outcomes and gaps.
   An accurate-aim clear establishes authoring evidence only.
5. Update protocol, run instructions, plan index and the roadmap's single full
   build order with concrete results. Self-review the integrated diff and use
   independent review for consequential contracts. No release is implied.

## Evidence and handoff

Research confirmed that existing campaign actors are grounded bodies and cannot
be elevated cosmetically to implement this enemy. The accepted flying-drone
design requires new timing revision, raised shot volume and real gravity on
death. The prior increment's complete local checks remain the baseline:
1,141 passing Rust tests, 94.56 percent line coverage and clean pinned client
checks. Implementation and final evidence follow below.

The local Notary bake and shadow use existing primitive and spatial shader
paths. [TorusMesh properties](https://docs.godotengine.org/en/4.7/classes/class_torusmesh.html)
and [spatial shader depth modes](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
were checked against the pinned engine's official documentation on 2026-09-30.

## Implemented contracts and independent checks

M04 now has six ordered encounters, 28 enemies (seven Notaries, six Clerks and
fifteen Sweepers), two prepared clinic worlds, two optional patients, three
ordinary-input secrets and deliberate roof use. Optional rescue never delays
departure. The raised Notary ray volume is shared by every weapon and traveling
shot. Its grounded wreck falls through the authoritative movement path and no
longer blocks a route. Seeded tests distinguish interruption, committed aim,
cover, actual resolved photographs, support and retries.

All four authored campaigns serving rules revision 3 require gameplay capability
25 for every role. Historical revision 2 records remain readable. Version 5 run
storage explicitly validates and archives historical v2/v3/v4 documents before
upgrade; a forged v4 M04 is rejected. M03 choices survive M04 retries. M04 rescue
and photograph outcomes survive the pending, unbuilt M05 boundary. Neither ticks,
input sequences nor inventory revisions rewind within a process.

The actual local-child checks preserve exactly 61 HP, 7 armor, Synthetic body,
selected Rifle, Fists/Rifle/Shotgun, 29 bullets, 8 shells, zero cells, one continue,
run identity and two earlier car outcomes. One archive retains the exact old v4
bytes. The client arrival holds readiness until held fire is released. Independent
adapter integration found and corrected omitted M04 readiness/continue tool
schema enums. Its real bundled-map fixture now tests observation, readiness,
clinic handoff steering invalidation, actual death and explicit continue.

Original offline Notary art uses eight directions and sixteen poses, with local
source/output hash receipts. Bounded spatial fan, shutter and crash playback
follows server facts. The rendered supported fall and near-camera companion
clip retain authoritative collision and shot blocking. M04 also has its own
muted terracotta/teal/sage surfaces and an outside-boundary residential skyline.
The [water and environment foundation](environment-water-foundation.md) adds
bounded shallow runoff through the same client map geometry seam; swimming and
liquid gameplay remain separate work. Original repair textures add wear through
the registered material path. The authorized transition audio batch adds six
exact-caption narration clips and an arrival runoff bed; it uses existing credits
and introduces no paid player-runtime call.

## Verification receipts

Logs are under `.agents/m04-buildout-20260930/`, except the named client,
playtest and visual-tour receipts. The first integrated full pass is retained;
final checks follow the adapter schema correction, tolerance-aware roof-route
regression and environmental rendering changes. A command still pending below
has not passed.

| Gate | Recorded result |
|---|---|
| Rust formatting and workspace Clippy | PASS, `fmt-verified.log`, `clippy-verified.log`, including the final async sampler |
| Final workspace tests | PASS, 1167 tests and three existing ignored, `tests-verified.log` |
| Final unfiltered workspace coverage | PASS, 94.47 percent lines, `coverage-verified.log`; reruns all 1167 tests including the sampler's real single-thread regression |
| Adapter full tests and focused Clippy after schema correction | PASS, 91 tests, `.agents/m04-client-buildout-20260930/mcp-adapter-final.log`, `mcp-clippy-final.log` |
| Dependency licenses, bans and sources | PASS, `deny-final.log`; no new dependency |
| Final pinned Godot full checks | PASS, 163 scripts and 76 harnesses, `godot-verified.log`, clean exit and each required PASS marker |
| Checker failure injection | PASS, all ten scenarios, `godot-checker-tests-final.log` |
| FFA, TDM, Rail-only and licence-to-kill playtests | PASS, `playtest-ffa.log`, `playtest-tdm.log`, `playtest-rail.log`, `playtest-licence.log` |
| CTF controlled route | PASS, `.agents/playtest/m04-ci-ctf-route.json` |
| Corrected contested CTF | PASS, two takes, one drop, one return and one capture, `.agents/playtest/m04-ci-ctf-blockers.json` |
| Six-map 2/6/6/8/12/16-participant roster | PASS, `roster-final.log`; no opening deaths |
| Container checks | Unavailable: local Docker Linux engine pipe absent, `docker-availability.log` |
| Final workspace release build | PASS, `release-verified.log`, including the corrected soak harness |
| Rebuilt 120-second release soak | PASS, nine samples, `.agents/soak/m04-verified.ndjson`, `soak-verified.log`; unchanged assertions |
| Final M04 campaign tour | PASS, all 23 states, `.agents/qa/m04-market-ninth/manifest.json`; ten inspected gallery images |
| Final standard published tour | PASS, all 32 states and thirteen locally refreshed stills, `.agents/qa/m04-standard-final/manifest.json`, `standard-tour-verified.log` |
| Local playable CLI smoke | PASS, four rule bots fight, adapter joins and scores, free brain plays 30 seconds with zero remote calls; `cli-server.log`, `cli-adapter.log`, `cli-brain.log` |

The contested baseline met its general assertions but timed out with no flag
takes. [The blocker correction](ctf-attacker-blockers.md) repairs the harness's
normal Reflex attacker firing policy. The same contested command then ended at
the capture limit in 136.25 simulated seconds with nine frags and 40.6 carrier
seconds. That is one map/seed/roster sample, not a multiplayer balance verdict.

| Measurement | Configuration and scope | Result |
|---|---|---|
| CPU tick budget | Release, 16 bots, 1200 ticks, seed 42, session plus encoding; `bench-final.log` | p99 0.622591 ms, max 2.1299 ms, zero over-budget ticks |
| Session-only tick | Same isolated CPU run | p99 0.589823 ms |
| Encoding-only tick | Same isolated CPU run | p99 0.019455 ms |
| Rebuilt release soak | Windows, four rule bots, four agents, two spectators, map rotation, nine samples over 120.0149 seconds | 19.9975 Hz, ticks 35 to 2435, lifetime p99 0.753663 ms, max 7.0276 ms, zero over-budget ticks |
| Soak traffic and queues | Same local process run | 50,623.83 outgoing and 2,415.52 incoming bytes per client per second; zero queue overflows and degraded samples |
| Soak memory | Same run, actual Windows `tasklist` working set | 37.83 MiB initial, 38.52 MiB final, 38.62 MiB maximum |

These CPU measurements do not establish graphics performance, remote-network
capacity or massive-server support. Renderer receipts identify the actual
Compatibility/OpenGL path and AMD Radeon 780M independently.

## Visual convergence and remaining acceptance

The named route retains all guards, actual windup/firing/death/crash proof,
finite supply claims, physical clinic use, optional patients, stairs and roof
departure. Failed tours remain diagnostic receipts. They exposed unanswered
photograph bursts, pickups visited while full, prompt checking after successful
use, travel fire selecting the next encounter too early and a roof crossover
assuming ideal waypoint centers. Corrections improve the shared checker and
ordinary-action route. No enemy health, damage, required roster or acceptance
threshold was weakened.

The final scoped travel controller fires only at explicitly named current
encounter actors when requested. A missing list preserves existing tour behavior.
Invalid, duplicate or oversized target lists are rejected. Death terminates a
failed route immediately and preserves partial diagnostics. The roof regression
carries actual movement positions between tolerance disks instead of resetting
the player to ideal centers.

The final ordinary-input route cleared all 28 guards with zero deaths, opened
the clinic, released both patients, observed seven supported Notary crashes and
used the actual roof departure. It lost 125 HP and 100 armor and finished at
100 HP and 50 armor. All three secret locations were reached, with two claims;
the meal medkit remained available at full health. It recorded zero photographs,
not a claimed dodge guarantee. Seeded tests separately prove actual committed-hit
photographs, interrupted tells, cover and misses. The final aftermath has no
large sky fragments after the render-camera correction. The
[gallery](../screenshots/README.md) preserves inspected states and motion strips.

The [shared look](../ART_STORY_BIBLE.md), [world and character guides](../design/README.md)
and 21 active level/epilogue appearance anchors now agree. Independent continuity
review found no canon conflict; stale surrounding text-first gates and prototype
summaries were corrected. The same world, palette, character and voice identities
govern future stills and film. Rendered proof identifies actual Compatibility on
AMD Radeon 780M; it does not establish cross-platform hardware performance.

The full test run initially exposed blocking Windows RSS sampling. Its
[async correction](soak-sampling-async.md) preserves thresholds and passed current
coverage plus the rebuilt real soak. All owned children stopped. The local Docker
engine is unavailable, so container checks were not run successfully; no infra
changed. Native Windows server cleanup used only its verified owned PID after
the shell timeout proved insufficient. No player's save or unrelated process
was altered.

This bounded prototype increment is locally implemented. The next campaign
build is M05 No Forwarding Address, per the single roadmap sequence; retain
M01-M04 pacing, readability, character/motion and listening work alongside it.

Full eleven-minute pacing, the four-minute-thirty par, unsteered readability,
human difficulty acceptance, ordinary companion motion/listening and broad CTF
seeds remain open. The three new transition scenes have narration and text
fallback; named-character casting and new key images remain open. The table-edge
meal secret and stair-reached awning secret are honest
prototype interpretations. M05 is not built. Release, cloud apply and external
publication have not occurred. New cash charges remain $0 of this round's $20
ceiling; 475 included audio credits were consumed. The $2 conservative equivalent
reserve is recorded separately from cash charges.
