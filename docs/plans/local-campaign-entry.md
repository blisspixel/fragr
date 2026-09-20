# Local campaign entry

Status: implemented, 2026-09-20. Integration: [#187](https://github.com/blisspixel/fragr/pull/187), task [#185](https://github.com/blisspixel/fragr/issues/185).
The M01 mission sequence shipped in #184 and v0.26.0. Local launch implementation
and verification are recorded below; #187 tracks remote CI and integration.

## Player outcome

Choose Recall Notice from Single Player and enter the actual M01 slice without
manually starting a server. The menu identifies this as a development mission;
the complete campaign remains unfinished. Move Calibration under arcade practice
and remove the obsolete disabled Episode 1 label. The main story remains the
personal rescue, not the old radio-led arena episode.

## Initial state

`boot_menu.gd` only changes the client scene and connects to a presumed listener
on 6767. It cannot start or select a mission. `game_manager.gd` consumes boot
metadata, and `net_client.gd` owns the wire connection. There is no client process
owner to reuse. `tools/solo_scrap.sh` starts a server externally; its Linux
`fuser -k` path can kill an unrelated listener and must be removed when touched.
Export presets build the client, not a complete server-and-client installation.

## Implementation boundary

- Preserve the authoritative Rust server and ordinary protocol. A local match is
  the same server on loopback, never a second GDScript simulation.
- Add one explicit child-process mode to the server CLI. Bind loopback port 0,
  load M01 through the canonical authored-map loader, and emit one bounded typed
  readiness record on stdout after validation and bind. Diagnostics stay on
  stderr. Embed the committed map source for this registered mission so packaged
  launch does not depend on a checkout or a second copied JSON document.
- Give the child an explicit parent lease through stdin and graceful shutdown.
  EOF must stop it when the game exits or crashes. Do not rely on discovering a
  process by name or killing whatever happens to own 6767. Preserve dedicated
  server CLI and LAN behavior outside the explicit child mode.
- One GDScript process owner survives scene changes. It handles start, bounded
  readiness, failure, cancellation, live ownership and stop. Keep menu rendering
  separate. Use structured argument arrays, validated loopback readiness, bounded
  pipe reads and only the child PID returned by the engine.
- Stop the owned server on leaving the local match or quitting. Joining/leaving
  a player role inside that match keeps it alive. Never stop an external server.
  Missing binaries, failed bind/validation, early exit and timeout must produce
  actionable visible errors without silently joining a different listener.
- Find the matching bundled executable on installed platforms and the built
  executable in a checkout. Do not shell out to a compiler from the player menu.
  Define and verify the package layout before claiming exported one-click play;
  macOS embedded-helper requirements need explicit export handling.
- Local campaign boot uses its own role/HUD mode and selected endpoint. It must
  not inherit Solo Broadcast objectives or an unrelated FRAGR_SERVER override.
  Multiplayer joins keep their existing explicit address behavior.

## Research

Checked the [stable OS API](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-execute-with-pipe)
on 2026-09-20. `execute_with_pipe` supports nonblocking pipes and returns stdio,
stderr and a PID. The child does not terminate automatically with Godot. Sandboxed
macOS exports restrict execution to embedded helpers. Verify actual pipe EOF,
flush and exit behavior with the pinned local engine before adopting the design.
Retain Rust and GDScript; no new dependency is presently justified.

A local Windows probe with Godot 4.7.2 passes nonblocking output reads, input
write/flush, explicit child exit and termination after closing the parent's pipe.
Receipts: `.agents/local-process-probe.log` and `local-process-eof-probe.log`.
The probe uses a disposable GDScript child. It does not yet prove the Rust lease,
crash cleanup or another operating system. Production readers must retain bytes
across partial UTF-8 reads and enforce bounded record/log buffers.

## Verification and scope

Test CLI conflicts, loopback-only binding, readiness schema, bounded input,
parent EOF, explicit shutdown and failed startup. Client tests cover cancellation,
repeated activation, malformed readiness, wrong endpoint/mission, missing binaries,
unexpected exit, leave versus role change, and preserving an external listener.
Run real process lifecycle checks on Windows, Linux and macOS where CI supports
them. Inspect a menu-to-M01-to-menu rendered run and confirm no child or mouse
capture remains. Repeat existing multiplayer, Godot and release gates.

No paid services, cloud, accounts or transport rewrite. The introduction,
checkpoint/retry system, full encounter population and finished art remain
separate bounded tasks. Successful launch does not establish a complete mission.

## Local implementation and evidence

- `AuthoredSource` retains one loader for editable maps and the bundled M01 JSON.
  The explicit local CLI cannot accept host, bot or arcade overrides.
- `local.rs` emits typed readiness and owns the stdin lease. Four real executable
  tests pass outside the checkout: ordinary wire admission, explicit shutdown,
  EOF shutdown, malformed control and CLI override rejection.
- `LocalProcess` owns native pipes and only the returned PID. `LocalMatch` owns
  bounded startup, cancellation, handoff, failure and shutdown. New keyed menu
  text introduces Latch's transfer-record objective and labels the old prototype
  as arcade practice.
- 688 Rust tests pass, with two existing artifact generators ignored. Strict
  clippy passes; unfiltered workspace line coverage is 95.78 percent.
- All 26 Godot harnesses pass, including fake-process boundary tests and the real
  menu-to-M01 lifecycle. They cover repeated activation, partial/invalid/oversized
  readiness, startup timeout, failed creation, cancellation, unexpected exit,
  role changes, leave, native pipe EOF and unrelated listener preservation.
- OpenGL and Vulkan lifecycle runs pass on this Windows host. The Vulkan mission
  entry capture is inspected after the controls card clears; it shows fists,
  Annex 67 and the actual transfer-record objective. Menu and failure captures
  are inspected. An intentionally unusable `FRAGR_SERVER` override does not
  redirect the owned match. Receipts: `.agents/local-entry-*.log` and
  `.agents/qa/local-entry*/`.
- Package discovery is defined, but export templates are unavailable locally.
  There is no packaged-release claim. CI now builds the server for real client
  lifecycle tests on Windows, macOS and Linux; those remote results are pending.

Release build, verifier fault injection and dependency license/bans/source checks
pass. The deterministic CPU benchmark retains the v0.26.0 trace:
`459243bbd70300ca9a014aed7f21b8ef1ee1d49fd9849e3feddf3eb78e7b50c4`.

| Measurement | Local result |
|---|---|
| CPU benchmark | Windows release, 16 bots, 1200 ticks, seed 42, repeated trace agrees |
| Tick p99 / 50 ms budget | 0.721 ms / 1.44 percent, zero ticks over budget |

The six-map mixed-client roster passes the existing assertions. This is regression
evidence, not final map balance or proof of public-server capacity.

| Map / seed | Clients | Duration s | Frags | First frag s | Longest gap s | Spawn deaths |
|---|---:|---:|---:|---:|---:|---:|
| Arena Duel / 67 | 2 | 61.90 | 7 | 10.35 | 11.00 | 0 |
| Compliance Yard / 42 | 6 | 49.00 | 24 | 3.15 | 4.15 | 2 |
| Directive 17 / 19 | 6 | 48.00 | 25 | 2.95 | 5.80 | 3 |
| Sector 9 / 42 | 8 | 61.90 | 35 | 2.95 | 5.05 | 2 |
| Reclamation Gulch / 42 | 12 | 54.80 | 46 | 2.95 | 5.00 | 3 |
| Tripoint Works / 42 | 16 | 24.45 | 40 | 2.95 | 2.95 | 6 |

The final 21-state gallery is refreshed and inspected, including the new Single
Player page. One initial OpenGL tour reported two leaked ObjectDB instances and
one resource at exit. The verifier rejected it. A smaller verbose tour, full
verbose tour and full normal tour then passed without source changes. The failed
receipt remains under `.agents/qa/local-entry-release/`; no fix is claimed.
Investigation: [#186](https://github.com/blisspixel/fragr/issues/186). Retain verbose
leak details if it recurs. Error filtering and thresholds remain unchanged.

Remaining integration gates: CI and release. No paid APIs were called.

The first Linux client CI run caught an invalid crash-test assumption. Godot's
Unix `OS.kill` waits for the child itself, leaving its process-status cache stale.
The [pinned engine source](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/unix/os_unix.cpp)
was checked on 2026-09-20. The Unix test now sends SIGKILL from an external `kill`
process so the actual owner performs the wait, as for a crash. The process owner
also retires its PID after observing exit; repeated cleanup cannot touch a reused
PID. The real crash assertion and clean-log gate remain intact. Remote results
on the corrected revision are required before merge.
