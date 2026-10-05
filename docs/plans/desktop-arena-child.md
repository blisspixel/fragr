# Desktop-owned arena server

Status: in flight, October 5, 2026. Native child ownership is not yet implemented or verified. The companion client host flow is a separate work item.

The packaged Multiplayer menu can probe and join a server, but its local-server button does not launch one. TDM and the optional ten-seat Sabotage room already have authoritative rules and socket tests. This change supplies the missing desktop-owned native process rather than rebuilding those modes.

## Contract

An explicit `--desktop-host` process reuses the existing bounded stdin lease and `run_server` readiness callback. JSON shutdown or stdin EOF ends only this owned child. Ordinary dedicated servers retain their independent lifetime. Campaign children, saves, readiness records and local run storage remain unchanged.

The first desktop profiles are TDM on the existing six built-in maps and five-per-side Sabotage on Sector 9 (map 4). The desktop process accepts zero through ten initial bots, an IPv4 loopback bind with an optional ephemeral port, or an explicit `0.0.0.0` LAN bind with a nonzero port. It rejects campaign, benchmark, solo, rotation and other profile-changing flags. Existing parsed match rules and options remain the authority.

After actual map preparation and listener bind, stdout emits exactly one newline-terminated strict `ArenaReady` object:

```json
{"version":1,"kind":"arena","url":"ws://127.0.0.1:6767","listen":"0.0.0.0:6767","map_id":4,"mode":"sabotage","five_vs_five":true,"bots":4,"gameplay_version":36}
```

`listen` is the actual listener address, while `url` is the host player's loopback connection. The capability is the current compiled constant, not a new gameplay capability. Diagnostics go to stderr. No readiness is emitted on invalid configuration, failed bind or parent cancellation during startup.

## Owning paths and acceptance

Own `server/src/local.rs`, the additive CLI/lifetime dispatch in `server/src/main.rs`, and `server/tests/desktop_host.rs`. Client hosting UI and lifecycle belong to the companion host-flow change. This plan and its unique evidence are local to the native seam; the roadmap and public integration remain separate.

The failed-readiness-output probe found that the existing runner detached its listener task and left the port bound after the runner returned inside a still-running executor. The scope therefore also includes a narrow `server/src/run.rs` ownership correction using its existing `AbortOnDrop` guard. Normal shutdown aborts and awaits the exact accept handle; early return schedules its abort through that guard. This does not claim every independently spawned client task has drained, and it changes no admission, tick, campaign or dedicated stdin rule. The initial failure remains recorded rather than dropping the retirement assertion.

Prove the real executable serves matching TDM or five-seat Sabotage MapInfo, supports actual human/spectator hello, advertises the chosen listener, and retires its listener after shutdown or EOF. Exercise invalid mode/profile/bots/address, busy bind, malformed lease, parent cancellation before readiness, and failed readiness output. Check stdout contains only the readiness record even with verbose logging. Set an isolated nonexistent campaign run directory and prove the arena child never creates it. Retain ordinary dedicated stdin behavior and all campaign-child checks.

Run owning tests, locked workspace tests, warning-denied Clippy, formatting, the established benchmark and coverage. The composed client and packaged two-machine LAN/human trial remain distinct acceptance gates. Native/socket success does not establish human match quality or public-internet deployment readiness.

## Audit boundaries

Five-seat Sabotage starts fresh entrants with the finite Pistol supply, keeps survivors' equipment and reserves ten combined bot/human/agent seats. It has no ready quorum and does not evict bots for humans. TDM currently uses its existing full-arsenal policy. This change does not silently introduce Pistol-only TDM, automatic bot replacement, map geometry, mutators, a second navigation/controller, or a new operator API.
