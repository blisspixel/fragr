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
mode, map, bot and 5v5 flags. A strict one-line `ArenaReady` record has eleven fields:
`version: 1`, `kind: "arena"`, `url`, `listen`, `map_id` (integer 1 through 6),
`mode` (`tdm` or `sabotage`), `five_vs_five` (boolean), `bots` (integer 0 through
10), `bot_policy` (`none`, `fixed` or `auto`), `fill_target` and
`gameplay_version: 36`. Fixed bots allow zero through ten and require a zero
fill target. No bots requires both counts zero. Automatic fill requires zero
initial bots and a total fighter target from one through ten. It gives the real
bound IPv4 address and nonzero
port; `url` uses loopback for the host's own connection even for a LAN listener.
TDM permits the six registered maps; Sabotage requires map 4 and the 5v5 flag.
Loopback may request port zero, while wildcard LAN binding requires an explicit
nonzero port. The server plan is [Desktop arena child](desktop-arena-child.md).
Logs stay on stderr. Regular dedicated-server stdin semantics are unchanged.

No campaign control, writer, save shape, gameplay capability, mode arithmetic,
team choice, tick transport or match scoring changes belong here. The paired
[bot-fill increment](bot-fill.md) owns automatic roster replacement and its
safe admission boundaries.
No new maps, public server browser, cloud deployment, automatic firewall rules,
router configuration or ticket distribution are included.

## Human flow and lifetime

1. Multiplayer offers Host and Join. Host initially offers TDM on registered
   arcade maps or 5v5 Sabotage on Sector 9. Select an actual supported map and
   no bots, a finite fixed count or automatic total fighter fill; 5v5 cannot
   exceed ten shared fighter seats.
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

### Packaged host protocol smoke, 2026-10-05

The existing install check verifies exported resources, the adjacent native
executable and a campaign run preview. It does not start an arena. Extend that
same `--check-install` path, after its retained preview gate, to start TDM on
Arena Duel and then 5v5 Sabotage on Sector 9 through `LocalHost`. Use zero bots,
loopback ephemeral ports, the existing strict readiness parser and the existing
bundled executable lookup. A real spectator `NetClient` must accept each map's
validated mode and geometry and receive a matching snapshot. Then leave that
socket, request owned Stop and require IDLE plus the returned native PID's
retirement before the next preset or final PASS.

Keep each startup, wire and stop phase bounded. Failure closes the owned socket
and native lease; cleanup targets only the returned owned process. Never alter
the campaign run or grant gameplay resources. Retain the current missing-server
and resource failures, and the actual native install harness. The release
workflow already invokes the exported check from each freshly unpacked Windows,
Linux and macOS package, so this needs no second launch configuration or package
assembly change. Three platform PASS results must bind to the final source.
This headless protocol and process smoke does not establish rendered combat,
human fun, two-machine LAN operation or every desktop's GPU support.

### Hosted scene audio retirement, 2026-10-05

The combined client checker at `f38ce34346890abc66ae390b7cf0cbeff92d0586`
completed all 133 harnesses, but the desktop host lifecycle test left one MP3
decoder alive at process exit. Its lifecycle assertions and own PASS marker
did not make the error log clean. Retain that failed run as evidence.

Before each ordinary gameplay Leave or Stop in that test, capture a weak
reference to the actual radio playback. Keep production audio and ordinary
scene teardown unchanged. Reuse the existing playback retirement check and its
two-second bound, require every captured decoder to retire after scene exit,
and assert all references are retired before final PASS and quit. Do not mute
audio, manually replace teardown, relax the bound or suppress exit errors.
Verify the real native lifecycle test with clean logs, then repeat the complete
combined client checker on the corrected frozen source.

### Optional automatic bot fill, agreed 2026-10-05

Nick requested automatic bot fill as an option alongside fixed bots and no
bots. Preserve the current fixed-four-bot default. The Host page will offer
three choices: "No bots", "Fixed bots" and "Automatic fill". The client reuses the existing
count control, labeled "Bot count" for fixed bots and "Total fighters" for
automatic fill. Hide it for no bots. Automatic fill targets the combined
fighter population, not a minimum number of bots. State that humans and agents
take priority. Spectators do not count toward that target. A running Host page
must show the accepted policy and configured count rather than imply a current
roster size from the startup record.

The agreed boundary keeps the fixed count in `bots`, adds an explicit
`bot_policy` (`none`, `fixed` or `auto`) and an automatic `fill_target`. The
inactive count must be zero, no bots requires both counts zero, fixed bots allow
zero through ten and automatic targets are integers from one through ten.
The same advertised policy and requested
counts must appear in strict native readiness and match the validated local
settings before Watch or Join is enabled. The exact flags are `--bot-policy`
and `--fill-target`, alongside `--bots`. Automatic fill supports plain TDM and
Sabotage and rejects mutators before binding. Reuse the existing LocalHost settings,
native lookup, endpoint parser and process lease.

The server owns all roster changes, admission and team assignment through the
existing Session and match seams. Human and agent admission has equal priority
over automatic filler bots, without evicting another participant or weakening
tickets, bans, resume or ten-seat Sabotage limits. Fixed bots preserve their
existing admission behavior. The [accepted server plan](bot-fill.md) defines safe
roster transition points, protected actions and reserved resume seats. Failed
or cancelled admission keeps the original bot and world intact. Active Sabotage
can refuse an unsafe replacement until the next round.

Client acceptance must reject unknown policies, malformed or mismatched counts
and readiness that advertises a different policy. Exercise all three menu
choices and both match presets with actual native readiness and owned Stop.
Retain full-room refusal for fixed bots, spectator access, the five real radio
retirement assertions and the packaged Host smoke. The automatic fill option
also needs a played human and agent arrival/departure witness with server-owned
rosters and outcomes. Reinspect minimum window fit after the added control,
then rerun the complete combined checker and three packaged install gates on
the final frozen source. Existing evidence remains scoped to its recorded
policy and source. New verification records must bind to the matching client,
native source and immutable executable.

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
