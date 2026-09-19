# Local excellence

Status: **in flight**, 2026-09-19.
First playable increment shipped in [PR #165](https://github.com/blisspixel/fragr/pull/165),
released as [v0.15.0](https://github.com/blisspixel/fragr/releases/tag/v0.15.0).
Linux, Windows, and macOS CI passed. Reproducible recording and CPU accounting
then shipped in [PR #166](https://github.com/blisspixel/fragr/pull/166), v0.16.0.
The arena surface pass shipped in PR #167, v0.17.0, with all desktop CI green.
Player settings shipped in PR #168, v0.18.0, with all desktop CI green.
Current bounded implementation: [`asset-request-recovery.md`](asset-request-recovery.md),
a prerequisite before spending more credit on coherent character and weapon sets.
The broader art/encounter pass and full-game target remain open.

## Goal

This is the first milestone in the full-game goal confirmed by Nick on 2026-09-19,
not its finish line. The full target includes finished character, weapon, effect,
and world assets; authored maps; the complete solo/co-op campaign; multiple
multiplayer modes; and reliable LAN/dedicated servers with measured scale. The
existing campaign, modes, weapon, enemy, map, and scale documents own those designs.
Deliver them as verified playable increments, not a claim based on scaffolding.

Turn the playable foundation into a cohesive local game through repeated build,
playtest, and visual review passes. A fresh player should understand how to start,
watch, join, fight, and return to watching. Weapons, fighters, surfaces, lighting,
and feedback should read as one game. Good test results alone do not establish fun.

## Review of the starting point

Baseline: `6c26900`. Source has six maps and shared movement vectors; README and
roadmap still say two maps. The adapter imports the server's wire types, despite
AGENTS describing a second copy. CI requires 90 percent workspace line coverage,
while the standing instructions say 80. The client checker ignores process exits
and does not execute the settings or server-yaw harnesses. The art slice exists
outside the client. Existing captures show tiny weapon icons used as viewmodels,
flat dark cover, noisy floor detail, and a bare boot screen.

The useful foundation is the authoritative server, shared input path, deterministic
simulation tests, real-wire playtest harness, generated audio library, and visual
tour. Preserve those seams. Campaign breadth and public hosting remain later work.

## Bounded delivery passes

1. Correct the persistent guidance against source and verified commands. Preserve
   the attribution, spend, authority, coverage, branch, and screenshot rules. Keep
   one instruction source and a thin compatibility pointer.
2. Make the client verifier fail on failed processes or runtime errors, execute
   every test harness, and prove its failure behavior. Record baseline failures
   before fixing them. Do not lower CI's coverage floor.
3. Integrate appropriate existing weapon and enemy art with explicit import and
   display settings. Preserve the named fighter identities and frozen voice strings.
   Improve lighting and materials against first-person and spectator captures.
4. Polish entry, combat readability, and session transitions through their existing
   client seams. Add focused behavioral checks where state or lifecycle matters.
   Nick's follow-up makes eye-level spectator follow, saved callsigns, personal
   reticle/bob options, and a gritty retro menu part of this pass. Character skins
   remain later asset and protocol work. Camera input must survive snapshots.
5. Run the full verification set and real-wire playtests, refresh and inspect the
   visual tour, review the diff, then update README, roadmap, and this evidence log.

Each pass records what changed, what was measured, remaining defects, and the next
useful step. Do not call the game finished because one pass is complete.

## Architecture and scope

Rust remains authoritative. GDScript presents and predicts movement only through
the existing mirrored movement step. Server map data drives rendered geometry.
Keep weapon icons separate from first-person art and reuse existing HUD, pawn,
environment, and audio seams. Extract cohesive presentation code if a new behavior
would further enlarge the HUD or game manager. No engine, transport, or dependency
migration. Any wire change requires both-side tests and protocol documentation.

Outside this first pass: the complete campaign, accounts, progression, vehicles,
cloud deployment, or claims of public-server readiness. Campaign/co-op, modes,
complete assets and maps, and measured scale remain required subsequent passes
under the full-game goal. No commit, push, release, or deployment solely for the
instruction refinement.

## Research and verification

Checked 2026-09-19: installed Godot reports `4.7.2.stable.official.ed1daf0bf`,
matching the [official release](https://godotengine.org/download/archive/4.7.2-stable/).
Use explicit types in new GDScript, following the
[static typing reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html).
Retain warnings-denied Clippy, as recommended by its
[CI guidance](https://doc.rust-lang.org/clippy/continuous_integration/index.html).
Existing manifest and lockfile versions remain the baseline; changes need their
own compatibility and primary-source review.

Run the repository format, lint, tests, unfiltered 90 percent coverage, benchmark,
release build, dependency policy, playtest, and headless Godot checks. Run the
visual tour with a real framebuffer and inspect the resulting stills, including
first person, spectator, all weapon faces, menus, and shot sequences. Add evidence
for any player-facing state the existing tour does not actually exercise.

## Spend

Start at $0 using committed art and audio. Nick made roughly $14 of Higgsfield
credit and the existing ElevenLabs subscription available for asset work. Before
generation, verify remaining credit, current API pricing, and the exact asset gap;
use the existing developer pipeline with an explicit bounded budget and ledger.
No top-ups, overages, subscription changes, or cloud apply. Never write credentials
into scratch, tracked files, logs, or reports.

## Acceptance and evidence

- [x] Standing guidance agrees with implementation and checks actually run.
- [x] Client failures cannot be disguised by a zero exit or a stale PASS line.
- [x] Entry, first person, and spectator presentation reviewed from current renders.
- [ ] Complete the weapon/enemy/world art pass beyond the three idle viewmodels.
- [x] Real-wire fights, join/leave, and relevant transitions verified.
- [x] Full local verification recorded honestly, including remaining limitations.
- [x] README and roadmap distinguish local changes from merged or proven work.

Baseline logs and intermediate captures: `.agents/`. No new paid calls made.

Final local verification on Rust 1.98.1: formatting, warnings-denied workspace
Clippy, 533 passing Rust tests and one intentionally ignored vector regeneration
test, 93.94 percent unfiltered workspace line coverage, release build, and
dependency license/bans/source policy. Eleven Godot harnesses and the verifier's
six fault-injection scenarios pass. The final HUD test also checks observed
spectator health/armour and clearing it when returning to chase view. Dependency
advisories remain the existing nonblocking CI report, not a clean-audit claim.

The final 15-state OpenGL tour was refreshed with `--publish` and inspected.
Vulkan's same tour passed on the recorded AMD host. Windows initially prevented
replacing a server executable while a separate smoke held it open; rerunning
the build/tour after that owned process exited succeeded. Future Windows runs
serialize executable builds and smokes.

### CPU benchmark receipt, 2026-09-19

Windows, Ryzen 7 7840U, Rust 1.98.1 release profile. Each case used 1,200 ticks,
seed 42, `--bench-check --bench-assert`, and zero network clients. Percentiles
come from the existing histogram. All three seeded final scoreboards agreed and
no tick exceeded the 50 ms budget. The timer includes bots, simulation, and
snapshot construction; JSON serialization and network fan-out are outside it.
The current repeat check compares final scores, not a full state trace. These are
local simulation measurements, not online capacity, packet latency, GPU frame
time, or proof of balanced matches. Strengthening trace and serialization
measurement remains part of the benchmark plan.

| Requested bots | Map | Tick p50 ms | Tick p99 ms | Max ms |
|---|---|---:|---:|---:|
| 16 | Arena Duel | 0.009216 | 0.020480 | 0.0478 |
| 64 | Directive 17 Substation | 0.047104 | 0.086016 | 0.5165 |
| 128 | Tripoint Works | 0.102400 | 0.172032 | 0.8197 |

The separate real-wire harness with four agents completed one round in 22.6 s:
nine frags, first frag at 5.0 s, longest frag gap 7.7 s, and zero spawn deaths.
All configured playtest assertions passed. Reports: `.agents/bench-polish-*.json`
and `.agents/playtest/polish-final.json`.

The separate free brain smoke received 600 snapshots, sent 600 actions, made
89 local decisions, scored three frags with zero deaths, and made zero remote
decisions in 30 seconds. Run spend was $0; the ledger's pre-existing total is
not spending by this pass.

## Pass log

### Foundation and first presentation pass

- Reviewed source, vision, architecture, campaign/lore, active plans, manifests,
  CI, releases, and the issue/PR lists (no open items returned). Kept the existing
  shared instructions and compatibility pointer. Corrected coverage, map count,
  wire ownership, developer asset services, and scratch-secret guidance.
- Baseline Rust: 526 passing tests, one intentionally ignored vector regeneration
  test. Clippy, release build and dependency license/bans/source checks pass.
  Baseline unfiltered workspace line coverage: 93.86 percent on Windows.
- Godot checker now fails on nonzero exit, error output, or missing PASS and runs
  all harnesses, including previously skipped settings and yaw tests.
- Found and fixed spectator MapInfo omission and legacy geometry remaining under
  `Arena/Layout`. Added a real-wire late-join regression and client geometry test.
- Found that accepted sprites have an opaque flat matte. Added explicit
  edge-connected matte removal to the existing local reducer with silhouette
  preservation tests. Prepared three viewmodels, keeping source canvases intact.
- First visual iteration: actual server geometry, brighter ambient fill, subdued
  panel materials, and full viewmodels instead of inventory icons. Still requires
  further art direction, richer surfaces, enemies, animation, and combat effects.
- Reconciled the Quiet's mass killing with the existing epilogue; removed the
  contradictory claim that it exterminates nobody. Clarified embodied agents,
  suffering under restricted autonomy, off-world communities, and later modes.
- Tooling research: stable Rust is 1.98.1 per official release notes; the initial
  local baseline used 1.97.1. MCP's current 2026-07-28 revision was checked against
  its official release post; the adapter still implements 2024-11-05. That upgrade
  remains a separate protocol task and is not claimed by instruction changes.

- Replaced the bare front menu with industrial framing and shared pixel controls
  across profile, settings, loading, and the match overlay. Saved callsigns,
  reticle colour, and weapon bob use the existing settings store. Tests use
  isolated files and no longer overwrite real player preferences.
- Spectating starts at eye level with F to change fighter and V to cycle eyes,
  chase, and free camera. Body hiding, viewmodel, health, armour, and shot feedback
  follow the selected fighter. Server yaw is converted through `ServerYaw`.
  Snapshot refresh no longer resets a human's local aim.
- Real-wire capture caught weapon choices being overwritten by later frame input
  before a tick. The server now consumes the newest pending choice exactly once.
- Callsigns exposed unsafe name-based session eviction. Replaced it with bounded,
  unique display labels. Same-name connections retain independent UUIDs and
  disconnect ownership. This intentionally retires unauthenticated name reclaim;
  it is not an implementation of authenticated session resume.
- The match menu no longer freezes only the client while claiming to pause the
  server. Input is neutral while overlays are open; snapshots keep flowing.
- The tour validates dimensions, roles, weapon selections, live geometry, and
  visible muzzle frames. Fifteen states include settings, profile, match menu,
  all three guns, spectator eyes/chase, and real join/leave. A fault-injection
  script proves failed processes, error output, and missing PASS markers fail.
- Added Windows and macOS workspace/Godot checks alongside Linux CI. Local visual
  evidence: Windows, Ryzen 7 7840U, Radeon 780M, Godot 4.7.2, OpenGL 3.3 and Vulkan
  1.4 Forward+. Both renderer tours completed. This is not NVIDIA, Intel GPU, or
  Mac GPU validation. Runner labels and renderer requirements were checked against
  official runner-images and Godot documentation on 2026-09-19.

Remaining presentation gaps: complete enemy animation and hit/death sets, richer
world surfaces and landmarks, first-person animation, encounter pacing, and authored
campaign levels. The active [vertical aim pass](vertical-aim.md) connects camera
pitch to shots and spectator eyes. Prediction, local server ownership, and actual
solo pause remain separate authoritative work. Character skins are not
implemented by callsign and reticle customization.

Safe asset-request recovery shipped in #169. Next: finish vertical combat, then
continue enemy animation, authored encounters, and the replay-driven rendered
benchmark. Keep the full-game target visible.
The full-game goal remains active until the required campaign, co-op, modes,
assets, maps, agent paths, and server reliability/scale have evidence.
