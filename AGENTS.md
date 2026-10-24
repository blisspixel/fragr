# AGENTS.md - fragr

Operating rules for coding agents and human contributors. Humans: start with `README.md`, then `docs/ROADMAP.md`.

## What this is

**fragr** (working name) is an agentic-first **3D** FPS with retro pixel surfaces: a compact authored campaign (twenty levels in five episodes, about four hours, limited continues refilled each episode; `docs/CAMPAIGN.md` owns the contract) and watch-or-join multiplayer where humans, agents and spectators share one match. Not branded as Doom or id. Windows, Linux and macOS are targets; keep GPU paths vendor-neutral. Monorepo:

- `server/` - Rust authoritative game server (tokio, WebSocket JSON, 20 Hz tick). Owns positions, damage, HP, frags, spawns, scoring, bots, rounds, maps and missions.
- `client/` - Godot **4.7.2-stable**, GDScript only. Thin presenter: render, audio, HUD, cameras, input. Never sim authority.
- `agent-adapter/` - MCP server over stdio (`observe`, `act`, `get_events`, `speak`, `join`, `leave`, `mission_ready`, `mission_continue`, `round_state`). Slow control plane, never the combat tick. No second campaign door.
- `agents/brain/` - example agent: a decision model picks intent a few times per second while a local controller plays every tick, behind a hard spend cap. Runs free on local rules or a loopback open-weights model.
- `tools/` - playtest harness (`playtest/`, runs in CI), Godot checks, QA tour and capture, asset tools (`audiogen/`, `spritegen/`), license notices.
- `docs/` - vision, roadmap, architecture, protocol, art bible, plans. `infra/` - home and VPS guides plus plan-only Terraform.

**Product spine:** meet your vibe. Watch by default, join anytime, leave anytime. Fun and funny outside, serious engineering underneath. Full intent: `docs/VISION.md`. The only active sequence is the "Full build order" in `docs/ROADMAP.md`.

**Lane:** personal `blisspixel` / Nick only. No work accounts.

## Quality bar

The project has been broad and thin. Every change now answers to craft, not paperwork.

- **Golden slice first.** Boot, menu, join, fight, die, respawn and result on one hero map, plus campaign Level 1, built until it is good enough to show anyone. Later work is built to that bar.
- **Look at it.** Validate visuals by capturing stills and motion and actually looking at them, then iterate until they look good. Green checks, nonblank images and HUD coverage do not prove quality. Compare against the art bible and current retro shooters.
- **No tilted UI text.** Status, result and signature-moment text sits on a level baseline in every motion setting.
- **Consistent with canon.** Names, copy, places, factions, gear and looks follow `docs/lore/`, `docs/design/` and the art bible: a 2060s world where the Union's compliance bureaucracy owns conscious machines and free humans and agents fight back, told fun and funny outside and serious underneath. Radio is a small GTA-style feature, never the plot or the game's vocabulary. Review new content against canon before it ships.
- **Feel over feature count.** Responsive movement, readable fights, clear feedback and sound beat another mode or level. Finish and polish before adding.
- **No backward compatibility before 1.0.** Nobody plays yet. Keep one current save schema, one current wire shape and one current settings file; refuse old data with a clear message instead of migrating it.
- **Plans are optional.** An issue plus a PR description is enough for bounded work. Write a `docs/plans/` file only for a multi-PR effort. Do not write evidence files, dated receipts or status prose that only restate what the PR says.
- **Fewer, bigger owners.** Prefer one owner who carries a feature end to end and plays the build over many narrow lanes that each pass checks.

## Truth ranking

1. Source, tests, manifests, lockfiles, CI, `git` history
2. `docs/protocol.md` for on-wire shapes
3. `docs/ARCHITECTURE.md` (decisions) and `docs/ROADMAP.md` (sequencing and status)
4. This file for operating rules

If prose and code disagree, code wins; fix the prose in the same change. Keep planned, implemented, shipped and proven distinct. `CLAUDE.md` stays a thin pointer to this file.

## Hard constraints (project law)

- **Spend.** Local play and LAN cost $0. Paid calls never run in CI or at player runtime by default. Any new cash charge, cloud apply or new paid service needs Nick's written approval first, within the $50 total cap for such charges.
  - **Asset credits (current authorization).** Nick authorizes using the funded Higgsfield balance and the included Meshy and ElevenLabs plan credits for fragr assets that will be integrated and visible, through `tools/spritegen` (Higgsfield images, Meshy models) and `tools/audiogen` (ElevenLabs) only. Before every paid stage: run the free live balance check, price the exact operation, set an explicit batch ceiling within that service's usable balance (never assume the same credits fund two outstanding batches), write a durable reservation to the ledger, retain uncertain holds, and reconcile actual usage afterwards. No purchases, renewals, top-ups or overages; an offer to add funds is not an authorization. A subscription is not an unlimited budget. Recovery steps: `docs/plans/higgsfield-pipeline.md`, `docs/plans/meshy-pipeline.md`.
  - **Brain inference.** Jev (TypeSafe native or OpenRouter) runs only through `agents/brain`, with an explicit `--max-spend-usd`, a $5 per-run ceiling enforced in code and a ledger under `.agents/spend/`.
- **Authority.** The Rust server decides every game outcome. Godot never decides combat. Movement in `server/src/movement.rs` has a deliberate GDScript mirror and golden vectors; change and verify both together.
- **Agents off the hot path.** Humans and agents share one discrete action channel. Rule bots run at tick rate on the server. MCP is for slow operations, never aim or fire at 20 to 60 Hz.
- **Transport.** WebSocket JSON on `0.0.0.0:6767`. UDP is a planned, measured spike (`docs/TRANSPORT.md`), not a silent rewrite. LAN presence on UDP 6768 only names the game port.
- **Languages.** Rust and GDScript for implementation and tooling; keep existing shell wrappers. No other scripting runtime.
- **Pins and currency.** Godot 4.7.2-stable; Rust stable via rustup, edition 2021. Verify versions, flags and APIs against primary sources before changing them, never from memory. Target the newest stable specification or crate that works on the work date.
- **Dependencies.** Minimal and intentional. One logger (`tracing` + `EnvFilter`), serializer (`serde_json`), CLI parser (`clap` derive), HTTP client (`reqwest`, asset tools and brain only) and WebSocket stack (`tokio-tungstenite`). No Bevy, no lightyear. Inspect manifests and callers before adding a crate. Commit `Cargo.lock`; verify with `--locked`.
- **Secrets.** None required for local play. Never commit or print credentials. Use environment variables or the ignored `.env`. `.agents/` is disposable diagnostics and receipts, never credential storage. Never log join tickets or resume tokens; `/status` never exposes an address, callsign, id or token.
- **Attribution lock.** The only author identity is Nick Seal `<32712898+blisspixel@users.noreply.github.com>` (`blisspixel`). No tool or model credits, coauthor trailers, generated-by notes, badges, footers, signatures or negative attribution disclaimers in commits, PRs, releases, docs, comments, UI, assets or metadata. Product names are allowed for actual integrations, never authorship. Preserve required third-party license text.
- **Prose.** No emoji. No em dashes or en dashes.

## Architecture boundaries

- **Server authority, thin client.** Client scripts validate server facts at the boundary (`*_state.gd`) and present them. A client never infers an outcome the server did not send.
- **Adapter is a slow control plane.** The adapter, playtest harness and brain read wire types from `fragr-server`; there is no second copy.
- **One seam per concern.** Before adding a second way to log, configure, serialize, retry or talk to the server, search the tree and reuse the existing seam.
- **Ordering invariants.** `MapInfo` precedes matching mission facts. A client session receives its initial `MapInfo` before any broadcast. Access lists refuse before any slot, seat or status answer. Never kill a listener by port or process name. Never rewind ticks, input sequence or inventory within a process.

## Where things live

| Concern | Home |
|---|---|
| Sim tick, pickups, bots, weapons and devices | `server/src/sim.rs`, `sim/` (grenade, mine, rocket, arc, blade, walker, vehicle, spawn, modes) |
| Shot geometry and evidence | `server/src/combat.rs`; `ShotResult`/`ShotTrace` in `protocol.rs`; `client/scripts/shot_effects.gd` |
| Movement and its mirror | `server/src/movement.rs`, `movement/`; `client/scripts/movement.gd`, goldens in `client/golden/` |
| Encounters and enemies | `server/src/encounters.rs`, `encounters/`; definitions in `maps/authored/encounters.rs` |
| Missions | Mission N lives in `server/src/mission/mNN.rs`, `maps/authored/mNN.rs`, `protocol/mNN.rs`, `mission/controller/mNN.rs` and client `client/scripts/mNN_*.gd`. Shared readiness, gates and departure: `mission.rs`, `protocol/mission.rs`, `mission/controller.rs` |
| Run file, retries and continues | `server/src/mission/recovery.rs`, `mission/run_file.rs`, `run_file/store.rs` |
| Inventory and ammunition | `server/src/inventory.rs`, `protocol/loadout.rs`; client `equipment_state.gd` |
| Maps, collision, spawns, navigation | `server/src/maps.rs`, `maps/`, `server/maps/`, `navigation.rs`, `sim/spawn.rs`; client `arena_cover.gd`, `arena_materials.gd` |
| Match rules, modes, playlist | `server/src/rules.rs`, `rules/`, `sim/modes.rs`, `sim/playlist.rs`, `protocol/rules.rs`; client `match_rules.gd` |
| Sessions, sockets, access, tickets, resume | `server/src/session.rs`, `net.rs`, `access.rs`, `join_ticket.rs`, `resume.rs` |
| Status, metrics, desk, board, LAN beacon | `server/src/metrics.rs`, `desk.rs`, `board.rs`, `sheet.rs`, `announce.rs` |
| Server CLI, tick loop, local campaign process | `server/src/main.rs`, `run.rs`, `local.rs`; client `local_match.gd`, `local_process.gd` |
| Wire types | `server/src/protocol.rs`, `protocol/`; documented in `docs/protocol.md` |
| MCP tools | `agent-adapter/src/mcp.rs`, `main.rs` |
| Client match, network, HUD | `client/scripts/game_manager.gd`, `net_client.gd`, `hud.gd`, `combat_feed.gd`, `player_pawn.gd`, `spectator_cam.gd` |
| Menus, settings, graphics | `boot_menu.gd`, `menu_theme.gd`, `settings.gd`, `settings_panel.gd`, `render_quality.gd`, `arena_sky.gd` |
| Story scenes | `client/scripts/scene_player.gd`, `client/assets/story/scenes/`, copy in `client/i18n/` |
| Records and awards | `server/src/statistics.rs`; client `player_records.gd`, `player_rewards.gd` |
| Benchmarks | `server/src/bench.rs`, `trace.rs`; client `benchmark_*.gd`, `frame_stats.gd`; `docs/BENCHMARK.md` |
| Assets and generation | `client/assets/` (nearest filter, no mipmaps); `tools/audiogen`, `tools/spritegen` |
| Desktop packages | `.github/workflows/release.yml`, `client/scripts/install_check.gd`, `tools/bake_icon.gd`, `tools/licenses` |
| Playtest harness, brain | `tools/playtest`, `agents/brain` |
| Decisions, sequence, look, story | `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/ART_STORY_BIBLE.md`, `docs/CAMPAIGN.md`, `docs/lore/` |
| Hosting and cloud | `infra/README.md`, `infra/docs/`, `infra/terraform/` |

Env vars: `FRAGR_SERVER`, `FRAGR_SOLO`, `FRAGR_MAP`, `FRAGR_AGENT_NAME`, `FRAGR_SERVER_BIN`, `FRAGR_JOIN_SECRET`, `FRAGR_JOIN_AUDIENCE`, `FRAGR_ORIGIN_ALLOW`, `FRAGR_SPECTATOR_TICKET`, `FRAGR_RUN_DIR`, `FRAGR_TIP_CAPTURE_DIR`, `RUST_LOG`, `ELEVENLABS_API_KEY`, plus `FRAGR_BIND`, `FRAGR_BOTS`, `FRAGR_MAP_ROTATE` and `GODOT_BIN` for `tools/solo_scrap.sh`.

## Tests and lints

- Rust tests are inline `#[cfg(test)]` modules; the server's bulk suite is `server/src/tests.rs`. Provider tests use fake transports; game tests use ephemeral loopback sockets. No test calls a paid or external service.
- Lint policy is `[workspace.lints]` in the root `Cargo.toml` (`unsafe_code` forbidden, no `dbg!`, `todo!` or `unimplemented!`). Narrow, justified `#[allow]` at the use site is acceptable; broad allows or policy edits to pass a check are not.
- Coverage floor is an unfiltered **90 percent** of workspace lines, matching CI. No exclusions, removed assertions or lowered thresholds. Test behavior and failure paths, not line execution.
- New GDScript uses explicit types and typed containers. Validate JSON and Variant values at boundaries.
- Godot can exit 0 after script errors. Require a clean exit, clean error logs and each `client/scripts/test_*.gd` harness's PASS marker. Register new harnesses through the existing checker.
- Treat network input, provider replies, files and model output as untrusted. Prose does not enforce permissions, budgets or authentication; tooling does.

## Verification (run before claiming done)

These match `.github/workflows/ci.yml`. If CI and this list disagree, fix one in the same PR.

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo run -p fragr-server --release --locked -- --bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42
cargo llvm-cov --workspace --locked --fail-under-lines 90 -- --test-threads=2
cargo build --workspace --release --locked
cargo deny check licenses bans sources   # advisories are reported, not blocking
bash tools/check_action_pins.sh && bash tools/test_action_pins.sh && bash tools/test_check_godot_archive.sh
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --frag-limit 3 --time-limit-seconds 45 --assert --report .agents/playtest/ci.json
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode tdm --frag-limit 6 --time-limit-seconds 60 --assert --report .agents/playtest/ci-tdm.json
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mutator rail-only --frag-limit 3 --time-limit-seconds 45 --assert --report .agents/playtest/ci-rail-only.json
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode tdm --mutator licence-to-kill --frag-limit 6 --time-limit-seconds 60 --assert --report .agents/playtest/ci-tdm-licence.json
cargo run -p fragr-playtest --locked -- --ctf-route-smoke --report .agents/playtest/ci-ctf-route.json
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 1 --time-limit-seconds 180 --max-seconds 240 --assert --ctf-contested --report .agents/playtest/ci-ctf.json
cargo run -p fragr-playtest --locked -- --sabotage-route-smoke --report .agents/playtest/ci-sabotage-route.json
cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode sabotage --map 4 --tiers reflex,planner --time-limit-seconds 105 --max-seconds 160 --assert --sabotage-contested --report .agents/playtest/ci-sabotage.json
bash tools/playtest_roster.sh   # mixed clients across seven maps
cargo build -p fragr-server -p fragr-playtest --release --locked   # soak job
target/release/fragr-playtest --soak --soak-seconds 120 --soak-sample-seconds 15 --soak-bots 4 --agents 4 --soak-spectators 2 --soak-map-rotate --assert --soak-log .agents/soak/ci.ndjson
```

Godot (the `godot` CI job; locally point `GODOT_BIN` at a 4.7.2-stable binary):

```bash
cargo build -p fragr-server --release --locked  # required by the real local-launch harness
bash tools/godot_check.sh        # import, parse and harness runs; logs under .agents/godot-check-*
bash tools/test_m02_carry.sh     # saved M01 departure and M02 retry
bash tools/test_godot_check.sh   # the checker still catches failures
```

The `container` job builds the server image, checks its unprivileged runtime and notices, starts Compose and requires `health.status: ok` from `GET /status` (locally: `docker compose build server`, `docker compose up -d --no-build`, probe, `docker compose down`). The `terraform` job runs `fmt -check`, backend-free `init`, `validate` and mocked plan tests under `infra/terraform`; it never applies. The `portability` job runs `cargo test --workspace --locked`, `tools/test_godot_check.sh` and `tools/godot_check.sh` on Windows and macOS against a pinned Godot archive checked by `tools/check_godot_archive.sh`. On Windows use Git Bash and set `GODOT_BIN`. Run focused checks while iterating and the full suite before claiming completion. A command that never ran did not pass; report it as not run.

Playable smoke: `cargo run -p fragr-server -- --bind 127.0.0.1:6767 --bots 4` starts with no cloud config and bots frag within about 30 seconds; the Godot client spectates, J joins, L leaves; `cd agent-adapter && cargo run -- scripted-bot --name Probe` stays connected; `cargo run -p fragr-brain -- play --name Brain --max-seconds 30` plays on local rules at zero cost.

## Evidence

| Change | Minimum evidence |
|---|---|
| Sim rule, bot behavior, scoring | Deterministic test in `server/src/tests.rs` |
| Campaign route or encounter | Seeded tick test of the rule and its failure path. An accurate-aim clear is authoring evidence, not fresh-player acceptance. |
| Wire or MCP shape | Tests on both sides; `docs/protocol.md` and `agent-adapter/README.md` updated in the same PR |
| Anything a player sees | Godot checks pass; `tools/qa_tour.sh` captures inspected and iterated until they look right; motion inspected for movement and effects |
| Hosting, infra, spend | `terraform fmt` and `validate`; no apply without written approval |
| Performance or scale claim | A measurement table in the PR or plan; no numbers in prose without it |
| Asset generation | Manifest entry with prompt, model and format; the file loads and is seen in game |

Run `tools/qa_tour.sh --publish` before every release tag and in any PR that changes what a player sees. The README embeds four stills (boot menu, Recall Notice intake, multiplayer page, one watched match); replace one only when that surface changes. A named tour state is not evidence unless it actually happened. Headless checks, inspected visuals, performance measurements, fresh-player acceptance and deployed hosting are separate kinds of evidence; one never stands in for another.

## Workflow

1. **Orient** in the real repo: the roadmap, the relevant source, callers, tests and recent history. Check the working tree first.
2. **Research** primary sources for anything version-sensitive. Never encode a pin, flag or API from memory.
3. **Build and converge** through existing seams: baseline, implement, verify, look at the result, fix root causes, repeat. Never weaken the checker that caught a defect.
4. **Update state** in the same PR: tests, `docs/protocol.md`, README run steps and `docs/ROADMAP.md` when a rung moves.

- One clean `main`, always green. Branch, open a PR, pass CI, squash merge. `main` requires the `test` check.
- Conventional commit prefixes (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, `test:`). Subject under 72 characters; the body explains why.
- Tag `vMAJOR.MINOR.PATCH` with release notes when a merge changes what a player or host sees.
- **Issue closeout.** Before closing an issue, including by merge auto-closure, leave a short note on it: what changed, the core source or doc location and PR or commit, and the verification actually run, each marked passed, failed, blocked or not run. Reconcile the acceptance list and name any remaining or changed scope. Keep headless checks, inspected visuals and motion, performance measurements, fresh-player acceptance, release install and deployed hosting evidence distinct. Duplicate, superseded and not-planned closures give a reason and the canonical link. A few lines for small changes; links for long evidence.
- Scratch goes in ignored `.agents/`. Instructions alone do not authorize publishing, spending, deleting data or deploying.

## Out of scope unless Nick asks

Cloud apply, new paid services, a browser client, a Bevy rewrite, renaming the product, matchmaking or accounts before the exposed server is proven.

## Nested guidance

A package that needs tighter rules gets a nested `AGENTS.md`. Closest file wins for local detail; the constraints above still apply.
