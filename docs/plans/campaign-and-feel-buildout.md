# Campaign and feel buildout

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Verified local work on
`feat/campaign-and-feel-buildout`, starting at `5fb985d` (v0.64.0 documentation).

## Goal and authorization

Make substantial progress on the next campaign capabilities, moving presentation
and free agent control using independent research and implementation lanes.
Nick requested parallel research and development on 2026-09-30 and explicitly
removed human feedback as a prerequisite for this round. Human comprehension,
hardware feel and two-machine acceptance remain unproven until their own evidence
exists. They do not prevent local implementation or automated review.

## Research and ownership

Before implementation, inspect existing source, callers, tests and plans in three
lanes: campaign/server capability, client presentation, and free agent control.
Choose bounded deliverables and assign disjoint files here before those edits.
The coordinating lane owns integration, roadmap and index reconciliation,
verification and rendered evidence. No lane changes another lane's files without
an explicit ownership handoff.

Selected deliverables:

1. **Jammer combat foundation and playable range.** Add a distinct authored
   enemy on existing server phases and delayed-shot collision, with interrupt,
   dodge, hostility and retry coverage. Server lane owns `protocol/actors.rs`,
   `encounters/enemy.rs`, `sim/traveling_shot.rs`, attack dispatch in `sim.rs`,
   its dedicated tests/range and its plan. This unlocks M03's new enemy; it does
   not claim M03's mast, rescue, departure or persistent transition exists.
2. **Remote participant timeline and spectator motion.** Client lane owns
   `remote_presentation.gd`, `player_pawn.gd`, `spectator_cam.gd`, their focused
   harnesses and its plan. Buffer bounded participant snapshots, align rendered
   orientation with position, and make chase smoothing independent of frame
   rate. Preserve local prediction and current campaign attack timing.
3. **Responsive free local decisions.** Agent lane owns brain `bot.rs`,
   `decision.rs`, `main.rs`, its README and its plan. Reduce Ollama play calls to
   stance intent while fresh local rules own equipment and danger; continue
   responsive fallback during slow replies and discard invalidated decisions.
   Fake transports prove delayed-response behavior without paid calls.
4. **Integration and evidence.** Coordinating lane owns client actor validation,
   enemy/Jammer visuals, offline rig/bake resources, projectile presentation,
   capability admission, protocol documentation, shared checker registration,
   README, roadmap, plan index and this plan. Use original locally authored art
   and committed audio. The remaining level 3 contracts follow this foundation.

Independent review found a silent Jammer launch because pulse attacks correctly
have no gun trace. The client lane subsequently owns `jammer_audio.gd`, its
offline PCM bake and tests, and the GameManager audio seam. Its ownership was
returned after those edits; coordinating QA observes actual launch counts and
captures isolated software audio. No paid audio operation is needed.

## Architecture and protocol

Reuse authoritative server combat, encounters, mission/run state and navigation.
Keep movement mirrors and golden vectors in step if either changes. Client
presentation may smooth server facts but never decide an outcome. Reuse the
existing local-model worker and combat controller rather than adding another
provider or runtime. Any strict wire change requires admission checks, both-side
tests and a matching protocol document update.

## Non-goals

No cloud apply, public-server readiness claim, transport rewrite, account system,
vehicle framework or full-campaign completion claim. No release, push or merge
is required to make this local change reviewable. Preserve the designated v0.58.0
campaign player-test target as historical evidence unless the test plan is
explicitly revised for new content.

## Verification

Establish workspace test baseline. Run focused behavior and failure-path tests
for each lane, then the required formatting, Clippy, workspace tests, benchmark,
90 percent coverage gate, release build and dependency checks. Run multiplayer
and mixed-roster playtests, soak and pinned Godot checks. Publish and inspect the
visual QA tour for player-visible changes, plus focused motion/route captures.
Keep exact commands, results and unavailable tools in this plan; logs stay under
`.agents/buildout-20260930/` or the existing QA output directories.

## Spend

Nick's cap is $20 combined external charges for this round, within the repository
total cap. Planned and actual external spend: $0. No paid provider, asset service
or cloud operation is needed for research, coding, testing or local captures.
Before any paid operation, reconcile prior actual spend and available allowance,
price the operation and enforce a bounded cap. Never enable overages or top-ups.

## Success criteria

- Independent lanes deliver working capabilities with behavioral evidence.
- Existing campaign carry/retry, mixed-role matches and local authority hold.
- Required checks pass or specific failures and limitations are recorded.
- Current README, roadmap and plan index describe actual local status without
  converting automated checks into human acceptance or shipped claims.

## Work record

- Clean working tree at the starting commit; created the local feature branch.
- Parallel source research selected the four deliverables above. Mission 3 is
  not a map-only change: current mission IDs, save and transition paths explicitly
  support M01 and M02. Its combat foundation is the bounded first increment.
- Workspace test baseline started; tools available include pinned Windows Godot,
  Git Bash, coverage and dependency checking.
- Baseline workspace tests passed, including 626 server library tests (three
  existing ignored tests). The clean starting tree has no unrelated changes.
- Independent reviews found missing launch sound and mixed-roster/lone-carrier
  CTF regressions. Dedicated cue and reference-agent regression fixes followed.
- Final review found that restored lone-carrier interception selected the thief's
  route without firing. The correction adds visible-thief aim/fire within weapon
  range, preserving occluded pursuit and coordinated home return. Its package
  and workspace rechecks supersede the earlier brain results below.
- The first successful range tour is `.agents/qa/jammer-buildout-final/`. Earlier
  attempts exposed a manifest weapon selection before pickup, an incidental
  Sweeper defeat counted in the wrong capture stage, and a capture policy that
  waited for another Jammer launch while exposed to Sweeper fire. Corrected the
  manifest to select after pickup and explicitly clear both named combatants
  together. Kept failed logs and images diagnostic-only.
- Docker container verification is unavailable locally: `docker info` cannot
  connect to `dockerDesktopLinuxEngine` because the daemon pipe is absent.
  No container or infrastructure source changed in this round.

## Local measurements

Recorded 2026-09-30 on Windows x86_64, release profile, sixteen available CPU
threads. These are CPU/session and software-output measurements, not GPU,
hardware input-latency, LAN or public-server results.

| Probe | Setup | Result |
|---|---|---|
| Deterministic benchmark | Arena Duel, 16 bots, 1,200 ticks, seed 42, no network clients | Tick mean 0.193 ms, p99 0.819 ms, max 3.448 ms; deterministic comparison and budget assertions passed. |
| Real-socket soak | 120 seconds, four rule bots, four external agents, two spectators, map rotation, nine status samples | Observed 19.79 Hz; lifetime p99 0.79 ms, maximum 12.72 ms; RSS 41.4 to 42.1 MiB, maximum 42.1 MiB; assertions passed. |
| Isolated Jammer launch | Radio muted, no player shots, one server-confirmed launch | 6.933-second software capture, RMS 0.001763, peak 0.035065; nonzero output without clipping. |

Benchmark and soak logs are `benchmark.log`, `soak.log`, `soak.ndjson` and
`soak.server.log` under `.agents/buildout-20260930/`. The isolated launch is
`.agents/qa/jammer-buildout-polished/04_live_audio.wav`. Human listening acceptance,
fresh-player campaign pacing and two-machine combat remain distinct evidence.

## Verification results

All commands below ran locally on 2026-09-30. The final Rust rerun follows the
last CTF interception fix; coverage is unfiltered. Three existing server tests
remain ignored. No verification calls an actual decision provider.

| Command or suite | Result | Evidence under `.agents/buildout-20260930/` |
|---|---|---|
| `cargo fmt --all -- --check` | Passed | `verified-fmt.log` |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | Passed | `verified-clippy.log` |
| `cargo test --workspace --locked` | Passed, including 642 server library tests and 114 brain library tests | `verified-tests.log` |
| `cargo run -p fragr-server --release --locked -- --bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42` | Passed | `benchmark.log` |
| `cargo llvm-cov --workspace --locked --fail-under-lines 90` | Passed, 94.62 percent workspace lines | `verified-coverage.log` |
| `cargo build --workspace --release --locked` | Passed after the final interception fix | `verified-release.log` |
| `cargo deny check licenses bans sources` | Passed | `deny.log` |
| Required four-agent FFA, TDM, Rail-only and licence-to-kill playtests | Passed | `ffa.log`, `tdm.log`, `rail.log`, `licence.log` and reports |
| CTF route smoke and contested map 4 run | Passed | `ctf-route.log`, `ctf-contested.log` and reports |
| `bash tools/playtest_roster.sh` | Passed, 2/6/6/8/12/16 clients across all six maps | `roster.log`; reports in `.agents/playtest/roster/` |
| Release `fragr-playtest --soak` with the repository's 120-second options | Passed | `soak.log`, `soak.ndjson` |
| `tools/godot_check.sh` and `bash tools/test_godot_check.sh` | Final full client recheck passed after camera correction; ten checker-failure scenarios passed | `godot-final.log`, `godot-checker-faults.log` |

The six-reference-brain socket smoke additionally passed with three controllers
per side, a spectator, forty readiness-synchronized live ticks and zero model
calls. Its bounded delivery evidence and limitations are in
[brain-responsive-local.md](brain-responsive-local.md).

Independent rendered review found incoming shot-effect quads filling the camera
near a mixed-fight impact. Active-camera clipping corrects that presentation
boundary while preserving the resolved shot, distant beams and effect expiry.
The focused harness, full 64-harness client suite and both regenerated tours
passed. The standard 32-state tour published thirteen selected stills locally;
the eight-state range cleared all three named enemies and reached its exit.
The earlier distant pulse strip was weak motion evidence, so the final range
manifest uses a closer lateral view. Container checks remain unavailable for the recorded
Docker daemon reason. Infrastructure is unchanged, so no Terraform changes or
cloud operations belong to this round.

## Rendered evidence and handoff

Final receipts are `.agents/qa/buildout-publish-final/manifest.json` and
`.agents/qa/jammer-buildout-polished/manifest.json`. Windows OpenGL compatibility
on AMD Radeon 780M rendered both with pinned Godot 4.7.2-stable. The standard
contact sheet, watched match, eyes and menus were inspected. Independent review
confirmed the lateral pulse strip shows advancement and no remaining concrete
camera-effect, pose or HUD defect in the inspected captures. The new mixed-hit
still is a different combat instant from the initial incoming-hit defect; the
mesh harness directly proves listener-hit clipping.

Retained and inspected range images:

- [Windup](../screenshots/jammer_windup_16x9.png).
- [Confirmed launch](../screenshots/jammer_launch_16x9.png).
- [Collapsed emitter](../screenshots/jammer_defeat_16x9.png).
- [Twelve-frame pulse travel](../screenshots/jammer_pulse_strip.png).

The README remains limited to its four standard embedded stills. Original rig,
atlas and PCM source receipts are included alongside the assets; no paid generation
or live synthesis is required. The protocol and adapter documents name capability
23 for Jammer-bearing maps, while M01/M02 admission remains unchanged.

The next development rung at this increment's completion was M03 Scheduled
Service. Continued work is recorded in
[m03-scheduled-service-prototype.md](m03-scheduled-service-prototype.md), which
adds the mast, optional liberated cars, deliberate departure and M02-to-M03
carry through the existing enemy and campaign-control seams.
Human M01/M02 acceptance, actual model latency and two-machine network feel stay
open measurements and do not gate the authorized local development sequence.
This branch remains local, with no commit, push, release or deployment performed.
