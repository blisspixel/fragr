# Multiplayer desktop host and join flow

Status: in flight, 2026-10-05. Base: `f1e3631526bac070278459af652dea6f83c7872c`.

Nick prioritized usable multiplayer hosting and human testing before remaining
campaign work. This bounded increment belongs to the existing multiplayer rung
in [the roadmap](../ROADMAP.md), not a separate global sequence.

## Goal and source findings

Let someone using an extracted desktop package start Team Deathmatch or the
existing optional 5v5 Sabotage profile, watch it, join it, invite a LAN player
and stop their owned server without a source checkout or a terminal command.

At the base, `boot_menu.gd` only probes a separately running server. Its
"Use local server" button changes the address to loopback. `LocalMatch` starts
campaign children only. A full `ws://` or `wss://` address understood by
`NetClient` is incorrectly prefixed with `http://` by the menu probe. The
existing status response supplies mode and mutators, but the menu ignores them.
The dedicated executable, team rules, Sabotage, discrete player controls,
watch/join/leave and server outcomes already exist.

## Scope and ownership

The client owns `local_host.gd`, a strict shared endpoint helper, the Host and
Join menu pages, narrow match orchestration and focused tests. Reuse
`LocalProcess` for owned native pipes and shutdown. Reuse the existing native
executable lookup, with a shared narrow extraction if needed, rather than
inventing another search policy.

The separate server increment owns `server/src/local.rs`, `main.rs` and a
narrow `run.rs` accept-task ownership fix:
an explicit desktop arena flag, existing bounded stdin shutdown/EOF lease and
typed readiness wrapping `run_server` with existing parsed match options.
Before implementation, both sides must agree on the exact flag and readiness
fields. The agreed interface is `--desktop-host`, with the existing bind,
mode, map, bot and 5v5 flags. A strict one-line `ArenaReady` record has exactly
`version: 1`, `kind: "arena"`, `url`, `listen`, `map_id` (integer 1 through 6),
`mode` (`tdm` or `sabotage`), `five_vs_five` (boolean), `bots` (integer 0 through
10) and `gameplay_version: 36`. It gives the real bound IPv4 address and nonzero
port; `url` uses loopback for the host's own connection even for a LAN listener.
TDM permits the six registered maps; Sabotage requires map 4 and the 5v5 flag.
Loopback may request port zero, while wildcard LAN binding requires an explicit
nonzero port. The server plan is [Desktop arena child](desktop-arena-child.md).
Logs stay on stderr. Regular dedicated-server stdin semantics are unchanged.

No campaign control, writer, save shape, gameplay capability, mode arithmetic,
seat policy, team choice, tick transport or match scoring changes belong here.
No new maps, public server browser, cloud deployment, automatic firewall rules,
router configuration, ticket distribution or bot eviction are included.

## Human flow and lifetime

1. Multiplayer offers Host and Join. Host initially offers TDM on registered
   arcade maps or 5v5 Sabotage on Sector 9. Select an actual supported map and
   a finite initial bot count; 5v5 cannot exceed ten shared fighter seats.
2. Same-machine hosting binds loopback on an available port. LAN hosting is an
   explicit option with a chosen port, normally 6767. Show the actual port and
   instruct peers to use the host's LAN address. Never advertise wildcard
   `0.0.0.0` as a usable connection address or invent a detected public address.
3. Startup, bound readiness and failure are distinct. Connect through the
   existing Watch or Join paths only after accepted readiness. The normal
   status probe and initial MapInfo still own the match identity shown.
4. A `LocalHost` node under the scene-tree root owns the server across menu and
   gameplay scenes. Returning to watching or leaving to the menu does not stop
   other players. Stop Server explicitly ends this owned match. App shutdown
   closes the lease; forced cleanup can target only the returned owned PID.
5. Hosted arenas never populate campaign `local_match`, request mission
   readiness, capture a run entry or claim that leaving saves a campaign.

Normalize bare host:port and complete ws/wss endpoints once, deriving the HTTP
or HTTPS status endpoint from the accepted game endpoint. Reject credentials,
control characters, malformed hosts/ports and unsupported URL forms at the
owning boundary. Display existing validated status mode/mutator fields, with
compatibility for their documented absence. Do not infer 5v5 from fighter count
or a Sabotage mode name. Existing full-room rejection and spectator access stay
authoritative.

## Acceptance

Focused boundary checks cover valid and rejected settings, endpoint forms,
readiness fields, startup failure, timeout, unexpected output, child exit,
port conflict and stop/scene/app lifetime. An actual two-client local lifecycle
check must prove both human roles share the host's one server, leaving does not
retire it, Stop does retire it, and neither preset touches campaign storage.
Keep all loading-first, no-blank-frame, pointer ownership, profile selection
and old campaign lifecycle controls.

The played gate requires coordinated hardware capture of two clients for TDM
and 5v5 Sabotage: ordinary admission, team identity, an actual resolved kill and
round outcome, plant or defuse, watch/leave/rejoin and a full-room spectator
case. Record source and native hashes, actual outcomes, owned process cleanup
and failures. A scripted human-role witness is distinct from Nick or other
people finding the match understandable and fun. Human play and LAN operation
on two machines remain explicit gates until observed.

Run the complete matching client checker and the server increment's meaningful
CLI/lease tests before review. Final combined CI and all three desktop exports
and install checks bind to one frozen head. A source-only test does not prove
the extracted package can host.

## Documentation, spend and remaining limits

After actual behavior exists, update `HOSTING.md`, `DESKTOP.md`, `PLAYING.md`
and `infra/docs/HOME-LAN.md` with desktop hosting and exact dedicated commands.
Correct the stale omitted Sabotage/profile options and historical open-CI
wording using verified evidence. Root owns README, roadmap and global indexes.

This increment costs zero and submits no asset, cloud or other paid requests.
No secrets are copied into configuration, logs, test fixtures or reports.
Internet TLS and public admission remain separate existing work. A local
package smoke, bot result or automated route cannot establish human fun,
internet reachability or large-server capacity.
