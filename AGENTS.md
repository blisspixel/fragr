# AGENTS.md - fragr

Operating rules for coding agents and human contributors. Humans: start with `README.md`, then `docs/ROADMAP.md`.

## What this is

**fragr** (working name) is an agentic-first **3D** FPS with an authored campaign, co-op, multiplayer, and retro pixel surfaces. Solo boot-and-scrap against local bots, and watch-or-join multiplayer where humans, agents, and spectators share one match, are both first-class. Not branded as Doom or id. Monorepo:

- `server/` - Rust authoritative game server (tokio, WebSocket JSON, 20 Hz tick). Owns positions, damage, HP, frags, spawns, scoring, rule bots, rounds, maps.
- `client/` - Godot **4.7.2-stable**, GDScript only. Thin presenter: render, audio, HUD, spectator cameras, input. Never sim authority.
- `agent-adapter/` - MCP server over stdio (`observe`, `act`, `speak`, `join`, `leave`, `round_state`, `get_events`). Slow control plane, never the combat tick.
- `agents/` - example agents on the same wire: `brain/` fields a fighter whose intent comes from a decision model (TypeSafe Jev natively or through OpenRouter) at a few decisions per second while a local controller plays every tick, behind a hard spend cap. Runs on local rules for free.
- `tools/` - `solo_scrap.sh`, screenshot capture, `godot_check.sh` (headless client checks), `audiogen/` (developer-only ElevenLabs sound and music generation, Rust), and `playtest/` (the agent playtest harness that runs in CI).
- `docs/` - vision, roadmap, architecture, protocol, art bible, plans. `infra/` - GCP Terraform plus self-host guides, plan-only until spend approval.

**Product spine:** meet your vibe. Watch by default, join anytime, leave anytime. Fun and funny outside, serious engineering underneath. Full intent: `docs/VISION.md`. Sequencing: `docs/ROADMAP.md`.

**Lane:** personal `blisspixel` / Nick only. No work accounts.

**Presentation and platforms:** original retro FPS with pixel surfaces and chunky
menus, including settings. Windows, Linux, and macOS are targets. Preserve GPU
vendor-neutral paths; distinguish headless CI, CPU benchmarks, and inspected
renderer/hardware evidence. Never infer massive-server or GPU support from one.

## Truth ranking

1. Source, tests, manifests, lockfiles, CI, `git` history
2. `docs/protocol.md` for on-wire shapes
3. `docs/ARCHITECTURE.md` (decisions) and `docs/ROADMAP.md` (sequencing and status)
4. This file for operating rules

If prose and code disagree, code wins; fix the prose in the same change. Keep planned, implemented, tested, shipped, deployed, and proven distinct. A checklist box is not evidence. `AGENTS.md` is the shared instruction source; keep `CLAUDE.md` a thin pointer.

## Hard constraints (project law)

- **Spend:** hard cap **$50** total. Local play and LAN are $0. Anything that bills needs written approval from Nick first. Approved developer asset services: ElevenLabs through `tools/audiogen` and Higgsfield through `tools/spritegen`, within approved existing credits. Verify quota and price before generation, pass an explicit cap, record usage, and never enable top-ups or overages. Jev (TypeSafe native or OpenRouter) runs only through `agents/brain`, with an explicit `--max-spend-usd`, a $5 per-run ceiling enforced in code, and a ledger under `.agents/spend/`. Paid calls never run in CI or at player runtime by default. Other paid services and cloud apply still need approval. A subscription is not an unlimited generation budget.
- **Authority:** the Rust server is the source of truth for every game outcome. Godot never decides combat. Movement math in `server/src/movement.rs` has a deliberate GDScript mirror and golden vectors; change and verify both together. Mirror availability does not prove prediction is wired into live play.
- **Agents off the hot path:** humans and agents share one discrete action channel. Rule and utility bots run at tick rate on the server. MCP is for slow operations, never aim or fire at 20 to 60 Hz.
- **Transport:** WebSocket JSON on `0.0.0.0:6767` (clients use loopback or `FRAGR_SERVER`). UDP is a planned, measured spike (`docs/TRANSPORT.md`), not a silent rewrite.
- **Languages:** Rust and GDScript for new implementation and tooling; retain existing shell launch/check wrappers. The legacy `tools/gate_tip_jammer_orange.py` still serves the screenshot gate; port and verify it before removal. Do not add another scripting runtime. Committed audio is the offline fallback.
- **Pins:** Godot 4.7.2-stable (official release and local binary checked 2026-09-19). Rust stable via rustup, edition 2021. Verify pins, supported APIs, and migration notes against primary sources before changing them; do not trust memory for versions or flags. Keep the established stack unless a concrete requirement justifies a change.
- **Currency:** target the newest stable specification revision or crate that works as of the work date (for example MCP 2026-07-28, not the 2024-11-05 handshake it grew up on), and keep an older one only as compatibility with a stated retirement. A plan that names a version names the date it was checked.
- **Dependencies:** minimal and intentional. Prefer std and existing crates. One logger (`tracing` + `EnvFilter`, `RUST_LOG`), serializer (`serde_json`), CLI parser (`clap` derive), HTTP client (`reqwest`, developer generators and brain only), and WebSocket stack (`tokio-tungstenite`). No Bevy client, no lightyear. Inspect manifests and callers before adding a crate; assess maintenance, license, platform support, and transitive cost. Use mature implementations for security-sensitive protocols. Commit `Cargo.lock`; use `--locked` for verification.
- **Secrets:** none required for local play. Never commit or print credentials. Use environment variables or the existing ignored `.env` integration. `.agents/` is disposable diagnostics and receipts, never credential storage; ignored does not mean secure. Do not copy existing keys into reports or scratch.
- **Attribution lock:** the only author identity is Nick Seal `<32712898+blisspixel@users.noreply.github.com>` (`blisspixel`). No tool or model credits, coauthor trailers, generated-by notes, badges, footers, signatures, or negative attribution disclaimers in commits, PRs, releases, docs, comments, UI, assets, or metadata. Product names are allowed for actual runtime/developer integrations, never authorship. Preserve required third-party copyright, license, and NOTICE text.
- **Prose:** no emoji. No em dashes or en dashes; use commas, periods, colons, parentheses, or hyphens in compound words.

## Canonical seams

| Concern | Home |
|---|---|
| Sim tick, hit detection, movement, pickups, boss, bots | `server/src/sim.rs` |
| Shot geometry, pitch bounds, target angles | `server/src/combat.rs`; server outcome ownership stays in `sim.rs`. `ServerYaw` maps yaw/pitch to the client camera. |
| Shot evidence, world feedback, combat measurement | Shared `ShotResult`/`ShotTrace` in `server/src/protocol.rs`, `client/scripts/shot_effects.gd`, and `tools/playtest`. Use the resolved shot, including dead shooters, rather than inferring weapon or impacts from live pawns. |
| Map definitions, collision solids, spawn layout | `server/src/maps.rs`; `MapInfo` drives `client/scripts/arena_cover.gd`. Surface materials: `arena_materials.gd`; scenery outside the playable bounds: `arena_backdrop.gd`. |
| Movement math and facing conversion | `server/src/movement.rs`, `client/scripts/movement.gd`, `client/golden/move_vectors.json`, `client/scripts/server_yaw.gd` |
| Walking routes and controller memory | `server/src/navigation.rs`, `navigation/controller.rs`; map geometry and movement remain authoritative. Precompute roster topology before readiness, bound/stagger searches, and prove routes with shared movement and actual `GameState` players. Use `client/qa/movement.json` for rendered stair/jump checks. |
| CPU measurements and offline traces | `server/src/bench.rs`, `trace.rs`; contract in `docs/BENCHMARK.md` |
| Tick loop shared by the binary and harnesses | `server/src/run.rs` (`run_server`, `ServerOptions`) |
| Agent playtest harness and metrics | `tools/playtest` |
| Decision-brain agent, budget gate, spend ledger | `agents/brain` (`budget`, `provider`, `bot`) |
| Session glue, rosters, `min_bots`, broadcast | `server/src/session.rs` |
| Wire types and Host line generators | `server/src/protocol.rs`, documented in `docs/protocol.md`. The adapter, the playtest harness, and the brain agent all read these types from `fragr-server`; there is no second copy to keep in step. |
| WebSocket accept and per-client plumbing | `server/src/net.rs` |
| Server CLI, tracing, tick loop | `server/src/main.rs` (`--bind`, `--bots`, `--map`, `--map-rotate`) |
| MCP request handling and tool schemas | `agent-adapter/src/mcp.rs` |
| Adapter CLI and WebSocket session | `agent-adapter/src/main.rs` |
| Client networking (`FRAGR_SERVER`) | `client/scripts/net_client.gd` |
| Client match orchestration, role, audio routing | `client/scripts/game_manager.gd` |
| HUD, killfeed, Host bumpers | `client/scripts/hud.gd` |
| Pawn presentation, first-person weapon face | `client/scripts/player_pawn.gd` |
| Spectator cameras | `client/scripts/spectator_cam.gd` |
| Desktop pointer ownership | `client/scripts/mouse_capture.gd`, owned by the match manager. Release on focus loss, close, and scene exit; automated scene trees set `fragr_automated` before loading gameplay and never capture the desktop. |
| Boot menu, callsign, shared retro controls | `client/scripts/boot_menu.gd`, `menu_theme.gd`; maps are selected by the server |
| Pixel assets and import presets | `client/assets/` (nearest filter, no mipmaps) |
| Audio assets and provenance | `client/assets/audio/` plus `audiogen-manifest.json` |
| Developer asset generation | `tools/audiogen`, `tools/spritegen`; sprite requests use `ledger.rs` and `generation.rs`. Preserve uncertain reservations; recovery steps live in `docs/plans/higgsfield-pipeline.md`. |
| Settings and diagnostics | `client/scripts/settings.gd` validates and persists; `settings_panel.gd` edits drafts in boot/match menus; `console.gd` uses the same commit path. Audio routing: `client/default_bus_layout.tres`. Harnesses isolate settings through `fragr_settings_path` tree metadata. |
| Product and stack decisions | `docs/ARCHITECTURE.md` |
| Sequencing, status, fun bar | `docs/ROADMAP.md` |
| Bounded work items | `docs/plans/<slug>.md`, indexed in `docs/plans/README.md` |
| Look, palette, tone | `docs/ART_STORY_BIBLE.md`, `docs/palette.json` |
| World and story | `docs/lore/README.md` indexes canon; `docs/CAMPAIGN.md` owns agreed story and open decisions; `docs/CAMPAIGN-MISSIONS.md` owns proposed mission briefs. Derive maps from story. Check recorded strings in `docs/lore/voice.md` before asset migrations; old audio does not override current intent. |
| Hosting and cloud | `infra/README.md`, `infra/docs/`, `infra/terraform/` |

Before adding a second way to log, configure, serialize, retry, or talk to the server, search the tree and reuse the seam above. Env vars in use: `FRAGR_SERVER`, `FRAGR_SOLO`, `FRAGR_MAP`, `FRAGR_AGENT_NAME`, `FRAGR_TIP_CAPTURE_DIR`, `RUST_LOG`, `ELEVENLABS_API_KEY`, plus the `FRAGR_BIND`, `FRAGR_BOTS`, `FRAGR_MAP_ROTATE`, and `GODOT_BIN` knobs read by `tools/solo_scrap.sh`.

## Tests and lints

- Rust tests are inline `#[cfg(test)]` modules. The server's bulk suite is `server/src/tests.rs`; `sim.rs` and `net.rs` are covered from there. Adapter tests sit in `agent-adapter/src/{main,mcp}.rs`. Provider tests use fake transports; game integration tests use ephemeral loopback sockets. No test should call a paid or external service.
- Lint policy is `[workspace.lints]` in the root `Cargo.toml` (`unsafe_code` forbidden, 2018 idioms, no `dbg!`, `todo!`, or `unimplemented!`). Every crate opts in. Narrow, justified `#[allow]` at the use site is acceptable; broad allows, silenced modules, or edits to the policy to make a check pass are not.
- Coverage floor is an unfiltered **90 percent** of workspace lines, matching CI. No exclusions, removed assertions, or lower thresholds to make a change pass. Test useful behavior and failure paths, not line execution alone.
- New GDScript uses explicit parameter/return types and typed containers where supported. Validate and narrow JSON/Variant values at boundaries; casts do not validate data. Existing warning debt is a baseline to improve in touched code, not permission to disable warnings or start an unrelated rewrite.
- Godot can exit 0 after script/runtime errors. Require successful exit, clean error logs, and each `client/scripts/test_*.gd` harness's own PASS marker. Register new harnesses through the existing checker convention.
- Treat network actions, provider replies, files, configuration, and model output as untrusted. Keep validation at the owning boundary, errors observable, and async lifetimes explicit. Prose does not enforce permissions, budgets, or authentication.

## Verification (run before claiming done)

These match `.github/workflows/ci.yml`. If CI and this list disagree, fix one in the same PR.

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo run -p fragr-server --release --locked -- --bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42
cargo llvm-cov --workspace --locked --fail-under-lines 90
cargo build --workspace --release --locked
cargo deny check licenses bans sources   # advisories are reported, not blocking
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --frag-limit 3 --time-limit-seconds 45 --assert --report .agents/playtest/ci.json
bash tools/playtest_roster.sh   # 2/6/6/8/12/16 mixed clients across all six maps
```

Godot (the `godot` CI job runs this; locally point `GODOT_BIN` at a 4.7.2-stable binary):

```bash
tools/godot_check.sh   # import, parse every script, run the harnesses; log lines are the verdict
bash tools/test_godot_check.sh   # inject failed exits, errors, and missing PASS markers
```

On Windows use Git Bash for these shell wrappers and set `GODOT_BIN`; the visual
tour also accepts `FRAGR_GODOT`. Run focused checks during iteration, then the full
suite before claiming completion. Report unavailable tools or baseline failures
with evidence. Keep logs under `.agents/`; a command that never ran did not pass.

Playable smoke:

1. `cargo run -p fragr-server -- --bind 127.0.0.1:6767 --bots 4` starts with no cloud config.
2. Bots fight; a frag appears in server logs within about 30 seconds.
3. Godot spectator shows the match; J joins, L leaves; bots persist.
4. `cd agent-adapter && cargo run -- scripted-bot --name Probe` drives a pawn through the same server.
5. `cargo run -p fragr-brain -- play --name Brain --max-seconds 30` plays on local rules at zero cost and prints a JSON summary. Paid-provider refusal and cap behavior belong in fake-transport tests; a local smoke must not accidentally use an available paid key.

Evidence beats assertion. Regenerate current `docs/screenshots/tour_*.png` through the tour below when UI, weapons, sprites, HUD, or arenas change. The older `tools/capture_tip_screenshots.sh` is for explicitly requested historical capture scenarios; keep its stills marked historical until rerun and inspected.

## Evidence by change type

| Change | Minimum evidence |
|---|---|
| Sim rule, bot behavior, scoring | Deterministic test in `server/src/tests.rs`; server log line from a smoke |
| Wire or MCP shape | Tests on both sides, `docs/protocol.md` and `agent-adapter/README.md` updated in the same PR |
| Client presentation | Godot headless checks pass; regenerated and inspected tour screenshots |
| Hosting, infra, spend | `terraform fmt` and `validate`; no apply without written approval; cost note in the doc |
| Performance or scale claim | A measurement table in the plan doc; no numbers in prose without it |
| Asset generation | Manifest entry with prompt, model, format; file loads in Godot |

## Screenshots, and when they must be refreshed

**Run `tools/qa_tour.sh --publish` before every release tag, and in any PR that changes something a player sees.** The README stills come from that run. Serialize Windows release builds and smokes because a running executable cannot be replaced.

Inspect the stills afterwards, including the world, menus, and transient effects.
HUD coverage and nonblank images do not establish visual quality or fun. A named
tour state is not evidence unless the state actually happened. Fix the capture or
asset source and regenerate derived output; keep screenshot captions honest.

Match validation to the affected roster: vary maps, seeds, enemy behaviors,
weapons, and human/agent/spectator sessions. Inspect motion sequences for movement
and effects. Arena Duel alone cannot prove the game; record unbuilt modes and
untested combinations explicitly in the active plan.

## Research and plan before build

1. **Orient** in the real repo: `README.md`, `docs/VISION.md`, `docs/ROADMAP.md`, relevant architecture/plan, source, callers, tests, CI, and recent history. Check working-tree changes first. Follow symbols with language-server navigation when available, otherwise focused `rg`; any local index is derived, never authority.
2. **Research** current primary sources for anything version-sensitive (Godot 4.7 docs, crates.io, MCP specification, GitHub Actions runners, ElevenLabs API). Never encode a pin, flag, or API from memory.
3. **Write the plan** into `docs/plans/<slug>.md` (goal, non-goals, architecture impact, protocol or API changes, verification, spend gate, success criteria) and link it from `docs/plans/README.md`. Chat is not a plan.
4. **Build and converge:** establish the relevant baseline, implement through existing seams, verify, inspect failures, fix root causes, and repeat. Self-review the final diff for contract changes, regressions, failure paths, and evidence gaps. Use independent review for consequential changes when available. Repeated defects should improve a shared abstraction or check; never weaken the checker that caught them.
5. **Update state** in the same PR: tests, `docs/protocol.md`, README run steps, the plan's status, `docs/ROADMAP.md`, and this file if a constraint moved.

## Workflow

- One clean `main`, always green. Work on a branch, open a PR, let CI pass, squash merge. `main` requires the `test` check.
- Conventional commit prefixes (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, `test:`). Subject under 72 characters, body explains why.
- Tag `vMAJOR.MINOR.PATCH` and publish release notes when a merge changes what a player or host sees. Keep the release notes in the same voice as the commit body.
- Plan docs are bounded and finish; the roadmap and plan index carry state across sessions. Before a handoff, record completed work, decisions, commands/results, unresolved failures, and the next step in the active plan. Use issues only when they add coordination value. Temporary scratch goes in ignored `.agents/`; promote durable knowledge into docs, tests, or code and mark superseded plans explicitly.
- Local reversible inspection, fixes, and tests proceed within the task. Instructions alone do not authorize publishing, spending, deleting data, or deploying. Do not commit, push, merge, tag, or release solely to refine this guidance.
- Security, permissions, and spend are enforced by tooling (branch protection, gitignore, lints, plan-only Terraform), not by prose. If a rule keeps needing repetition, make it mechanical.

## Out of scope unless Nick asks

Cloud apply, paid assets, a browser client, a Bevy rewrite, renaming the product, matchmaking or accounts before the exposed-server phase is proven.

## Nested guidance

If a package needs tighter rules, add a nested `AGENTS.md` there. Closest file wins for local detail; the constraints above still apply.
