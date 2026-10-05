# Desktop-owned arena server

Status: in flight, October 5, 2026. Native child ownership, prepared fixture topology and empty Sabotage Muster corrections passed all thirteen local native gates at `dff0b39ba232ad94c83713870706d05871873fb1`, including 93.66 percent unfiltered workspace line coverage. The optional automatic-fill follow-up is being verified separately. The companion client host flow, packages and physical LAN trial have separate acceptance gates.

The desktop-owned process supplies the native server for the companion Multiplayer Host flow. TDM and the optional ten-seat Sabotage room reuse existing authoritative rules and socket seams.

## Contract

An explicit `--desktop-host` process reuses the existing bounded stdin lease and `run_server` readiness callback. JSON shutdown or stdin EOF ends only this owned child. Ordinary dedicated servers retain their independent lifetime. Campaign children, saves, readiness records and local run storage remain unchanged.

The first desktop profiles are TDM on the existing six built-in maps and five-per-side Sabotage on Sector 9 (map 4). Bot policies are `fixed`, `none` and `auto`, defined in [bot-fill.md](bot-fill.md). Fixed accepts zero through ten initial bots with `--fill-target 0`; none requires both counts zero; auto requires `--bots 0` and a total fighter target from one through ten. Automatic fill supports plain TDM and Sabotage only and rejects mutators. The desktop process accepts an IPv4 loopback bind with an optional ephemeral port, or an explicit `0.0.0.0` LAN bind with a nonzero port. It rejects campaign, benchmark, solo, rotation and other profile-changing flags. Existing parsed match rules and options remain the authority.

After actual map preparation and listener bind, stdout emits exactly one newline-terminated strict `ArenaReady` object:

```json
{"version":1,"kind":"arena","url":"ws://127.0.0.1:6767","listen":"0.0.0.0:6767","map_id":4,"mode":"sabotage","five_vs_five":true,"bots":0,"bot_policy":"auto","fill_target":10,"gameplay_version":36}
```

`listen` is the actual listener address, while `url` is the host player's loopback connection. The capability is the current compiled constant, not a new gameplay capability. Diagnostics go to stderr. No readiness is emitted on invalid configuration, failed bind or parent cancellation during startup.

## Owning paths and acceptance

Own `server/src/local.rs`, the additive CLI/lifetime dispatch in `server/src/main.rs`, and `server/tests/desktop_host.rs`. Client hosting UI and lifecycle belong to the companion host-flow change. This plan and its unique evidence are local to the native seam; the roadmap and public integration remain separate.

The failed-readiness-output probe found that the existing runner detached its listener task and left the port bound after the runner returned inside a still-running executor. The scope therefore also includes a narrow `server/src/run.rs` ownership correction using its existing `AbortOnDrop` guard. Normal shutdown aborts and awaits the exact accept handle; early return schedules its abort through that guard. This does not claim every independently spawned client task has drained, and it changes no admission, tick, campaign or dedicated stdin rule. The initial failure remains recorded rather than dropping the retirement assertion.

Prove the real executable serves matching TDM or five-seat Sabotage MapInfo, supports actual human/spectator hello, advertises the chosen listener, and retires its listener after shutdown or EOF. Exercise invalid mode/profile/bots/address, busy bind, malformed lease, parent cancellation before readiness, and failed readiness output. Check stdout contains only the readiness record even with verbose logging. Set an isolated nonexistent campaign run directory and prove the arena child never creates it. Retain ordinary dedicated stdin behavior and all campaign-child checks.

Run owning tests, locked workspace tests, warning-denied Clippy, formatting, the established benchmark and coverage. The composed client and packaged two-machine LAN/human trial remain distinct acceptance gates. Native/socket success does not establish human match quality or public-internet deployment readiness.

## Audit boundaries

Five-seat Sabotage starts fresh entrants with the finite Pistol supply, keeps survivors' equipment and reserves ten combined bot/human/agent seats. It has no ready quorum. Fixed bots retain their seats. Automatic fill may yield only trusted, safe rule bots through the bounded admission transaction in [bot-fill.md](bot-fill.md); humans and external agents have equal priority, and unsafe full live rooms visibly refuse until a later round. Parked pawns keep their slots through the existing resume grace. TDM uses its existing full-arsenal policy. This change introduces no map geometry, new mutator, second navigation/controller or operator API.

## Mixed-party fixture preparation follow-up

The runtime freeze `ae4ad91870d0f3fb5c60bc4aa11eee2da8c94d62` passed the owning six local tests, six real executable-child tests, locked workspace tests, formatting, warning-denied Clippy, the established deterministic benchmark, release builds and license/source/ban checks. Its first instrumented workspace run had 986 server tests passed, one failed and three existing ignored: the mixed human/agent campaign fixture exceeded its first 20-second progress wait. The unchanged exact instrumented test then completed in 3.54 seconds in isolation. A quiet, default-parallel full retry again had 986 passed, one failed and three ignored, this time with both sockets ending at ReachLift and the watcher observing geometry revert before departure. Neither run established the coverage floor, and isolated success did not establish the cause.

Source inspection shows that each live driver constructs a MissionProbe, which loads both strict fixture worlds, then synchronously calls Navigation::shared on changed MapInfo. The spectator also constructs its probe after connecting. Navigation::shared holds its process-wide cache mutex throughout topology construction. The resulting setup can therefore occupy the same runtime that owns live sockets and the timed walk. That is a preparation hazard; current failure output does not prove which particular wait caused either failure.

The authorized scope now also includes a minimal test-only preparation change in `server/src/mission/wire_tests.rs`. Create all three probes and retain the exact closed/open fixture topologies before starting the server or connecting live sockets. A driver may select a retained topology only after the actual MapInfo passes the existing complete geometry, presentation and mission comparison. Preserve both 20-second progress/departure waits, the five-second fighter completion bound, real human/agent/spectator sockets, ordinary actions and every party, map-order, aboard and departure assertion. Change no production navigation, cache, controller, transport, geometry or lifetime code.

The prepared fixture and empty-host correction subsequently passed the unchanged full coverage command at dff0, with 991 server tests passed, none failed and three existing ignored. Retain both earlier failed whole runs and both isolated launcher records. All thirteen actual Cargo gates returned zero; the original diagnostic wrapper failed while publishing final metadata after its children retired, so an independent receipt binds the completed gate outputs and wrapper retirement. Keep local native evidence, composed renderer/client evidence, desktop packaging and a physical two-machine human LAN trial distinct. Historical immutable Windows inputs are retained separately: ae4 SHA-256 `a55e29cc543481af33f74d0f3f82c16d0c2de50a596625525ca5d7bf4a5c47cb` and dff0 SHA-256 `66d269351d0077cf3216acfd6ce5b60b40c9a50fe2081685aef2af66c04cc795`. Both precede the strict eleven-field policy contract. The protected older root binary remains untouched.

## Empty Sabotage host follow-up

The actual two-desktop Sabotage witness exposed a separate runtime defect before its first fighter joined: a zero-bot host exhausted Muster with no contestants, entered Live and eventually awarded the Union an empty round on time. The delayed first human was eliminated until the next Muster. A later real detonation therefore produced score 1:1 instead of the intended first-round 0:1. Private witness publication failures are retained separately and do not erase the observed authoritative startup defect.

Extend the scope narrowly to `server/src/sim/sabotage.rs` and the existing Sabotage and session test seams. During Muster only, an arena contestant with an assigned team and `detached == false` permits the countdown to advance. With none, reset `phase_started` to the current authoritative tick and retain the full Muster clock, round number, score and lack of result. Spectators never enter the authoritative player roster; parked-only rosters must not start a phantom round. A single connected human, agent or rule bot is sufficient. Do not require both sides, add a ready quorum, change ten-seat accounting, alter live or planted outcome precedence, change real leave behavior, or add a protocol revision.

Prove a long empty wait cannot advance or score, delayed first humans and agents enter alive in the first round, parked-only Muster retains the full clock until resume, and a single rule bot starts without opponents. Exercise the actual session spectator Join and delayed first fighter Join paths. Run all existing Sabotage and five-seat regressions, then review the precise diff before full verification. The prior immutable binary remains a historical input; after review, build a new private immutable native input for the corrected behavior without overwriting it or the protected root binary. Full workspace checks, the unchanged coverage floor, CPU mode outcomes and the corrected two-desktop witness remain required.
