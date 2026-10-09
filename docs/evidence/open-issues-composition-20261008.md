# Open issues and roadmap composition, October 8

Status: implemented locally for the bounded composition. Local work on
`feat/host-rotation-campaign-bests`, based on
`e4df1a0b349aacda926d9c178f6aef10bd3f136c`, preserves the existing dirty combat
and infrastructure work. No merge, release, deployment or external issue-state
change is claimed. The [reconciliation plan](../plans/open-issues-20261008.md)
maps all five open GitHub issues and unfinished roadmap rungs to their owners.

## Implemented local behavior

The [Gulch repair](../plans/gulch-planner-stalls-20261008.md) accepts bounded
forward observation gaps without mistaking replaced unsent snapshots for a
controller reset. Six distinct fresh stationary observations still gate
recovery. Actual movement at both reported corners passes three cadences;
duplicate, backward, stale and idle controls retain their meaning. The historical
CI failure is not conclusively attributed to this reproduced cause.

The [exit repair](client-exit-retention-20261008.md) gives weak decoder tracking
and pending environment retirement a tree-lived owner. Ordinary quit paths stop
owned child processes and drain actual work with a bounded failure deadline.
Released-source audio and premature sky failures reproduce; current-source
headless, OpenGL, Vulkan, minimized and layout-replacement checks pass. Six
verbose Vulkan runs retain two named startup warnings, separately from the
warning-free normal runs. A deliberately retained decoder still fails.

The [local award increment](local-awards-20261008.md) adds two actual supported
human awards, independent recoverable proofs, locked previews and title, emblem
and firearm finish selections. Actual owned M01 earning, save/reload and final
OpenGL/Vulkan presenters pass. Benchmark presentation restores standard.

The [M01 authoring matrix](m01-finite-supply-validation-20261008.md) passes
twelve tier/route/controller combinations with every fourth resolved ranged
attack deliberately missing and consuming finite ammunition. Actual enemy deaths
exercise all three tiers' entry restoration, duplicate refusal and continue
exhaustion. Current Clerk/Sweeper source and atlas hashes were audited against
their manifests. Historical issue descriptions no longer describe missing M06
or version-6 carry in current main. Final art and human mission acceptance remain
open, with obscured and lethal-transition stills scoped honestly.

The preceding [map composition](development-composition-20261008.md) records
M12/M14 development worlds, authored fleets, vehicle-aware spawning, host
rotation and local mission bests. Those receipts retain their own source and
executable hashes. Eleven connected prototypes remain; the static M12/M14 maps
do not add campaign progression or a finished vehicle mission.

## Final composed checks

| Check | Result |
|---|---|
| Formatting and lint | `cargo fmt --all -- --check` and `cargo clippy --workspace --all-targets --locked -- -D warnings` pass. |
| Workspace tests | `cargo test --workspace --locked`: 1,849 passed, zero failed, three existing ignored generator/export checks. |
| Unfiltered coverage | `cargo llvm-cov --workspace --locked --fail-under-lines 90` passes the same 1,849 tests: 93.31% lines, 75,587 lines with 5,056 missed. No exclusions or threshold changes. |
| Dependency checks | Licenses, bans, sources and advisory checks pass. No dependency was added. |
| Release and CPU benchmark | Workspace release build passes. Its native and the separately built standalone tour native each pass the deterministic asserted 16-bot, 1,200-tick, seed-42 CPU benchmark. |
| Full client gate | Final checker passes 332 scripts and all 153 harnesses, with clean logs and own PASS markers. The later QA aim helper also passes a focused parse and the full rendered route. Initial benchmark-fixture failure is retained. |
| Client verifier | All ten injected failure-detection scenarios pass. |
| Network modes, roster and soak | All eight exact CI cases, seven roster cases and 120-second native soak pass. One additional Gulch twelve-agent smoke passes on the final release harness. [Exact artifact and measurement scopes](network-regression-20261008.md) remain distinct. |
| Standard rendered gallery | Same 32-state, seed-42 route passes with clean logs; fourteen stills copied. Original-size inspection includes menus, bodies and all three strips. The [gallery receipt](../screenshots/readme-20261008.json) retains the failed first attempt and earlier capture metadata. |

The initial composed client run exposed an older benchmark fixture that created
a manager without its HUD. The fixture now supplies the actual HUD and checks
standard finish restoration together with console shutdown. Focused verification
passes; the full initial failure remains in `godot-composed.log`.

The final gallery attempt also caught a real death during downward aiming:
normal respawn reset the camera after the QA helper's one-time request. The
helper now resends ordinary input while waiting for a living authoritative pose,
within the same five-second deadline. The same route, seed, bots and strict pitch
assertions pass. Up/down snapshots are alive with matching camera/server pitch
of 0.4/-0.4. No invulnerability, simulation change or weakened assertion was
introduced. The failed tour and its log remain retained; no image from it is
selected. Static body frames still do not establish grounded motion, and small
strip samples do not prove seven separate Scatter impacts.

The workspace release server SHA-256 is
`1981266d899f15b4bb73484969c2920f81e6f7fd49091b3c5234d9f9fae5f826`.
The normal visual wrapper builds its standalone server separately, SHA-256
`339de54d19925bc00a6d114a9fbf4884514ca168608c7bf65ff280d0e3baacc8`.
Both exact artifacts pass the asserted CPU benchmark. The final release harness
is `d02756f41b91e9ab38697ba5bbeca81c9e4d39e18c90d63e579165a3be2c7962`.
Older copied network and actual-earning binaries retain their own hashes and
source scopes; no byte-identity claim joins them.

Dependency checks retain their duplicate-crate and unused-license-allow warnings.
The nonblocking advisory pass also reports the existing `yoke-derive 0.8.3`
yank. [Upstream's report](https://github.com/unicode-org/icu4x/issues/8506) and
[fix](https://github.com/unicode-org/icu4x/pull/8528) identify an older-Rust
compilation regression and the compatible 0.8.4 replacement. Local Rust 1.97.1
and stable CI are above the affected range. The locked reverse graph reaches
only the audio/image tools and decision brain through reqwest, not server or
adapter gameplay. This frozen composition retains its recorded lockfile;
retire the yanked patch with `cargo update -p yoke-derive --precise 0.8.4` and
locked verification before the next release dependency refresh. No advisory
ignore, direct dependency or broad upgrade sweep was added.

The Docker CLI exists, but the Linux daemon pipe is unavailable. Container build,
runtime identity, notices and Compose health checks did not run locally. Other
desktop platforms and hosted CI remain separate. Pre-existing infrastructure
drafts were preserved; no Terraform validation or cloud apply is claimed.

Raw current logs remain under `.agents/open-issues-20261008/`. Final evidence
must distinguish each check's binary/source scope, including the earlier actual
earning capture and final presenter review. Repeated checks do not retroactively
change historical captures.

## Remaining acceptance and spend

All five issues have current findings, implementation or bounded evidence, and
explicit residual criteria. That does not close them automatically. Unsteered
fresh-player clarity, pacing, fun and final difficulty/art remain human gates.
Whole-route spectator/tool review, physical LAN/WAN, broader hardware/platform
proof, the finished M12-M20 campaign, larger modes and release/soak milestones
remain in the roadmap's single full build order.

$0 new cash, zero paid image/audio/model calls. Existing committed assets supply
this work. The reported $4.65 image balance and included audio/model quotas need
no top-up for these corrections. No renewal, overage, cloud work or deployment
ran.
