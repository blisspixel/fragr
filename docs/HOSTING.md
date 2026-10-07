# Hosting fragr

[Back to the README](../README.md) | [Home LAN](../infra/docs/HOME-LAN.md) |
[Cheap VPS](../infra/docs/CHEAP-VPS.md) | [Transport](TRANSPORT.md)

The Rust server owns each match. It runs locally without an account, cloud
service or API key. The current game transport is WebSocket JSON over TCP
6767. UDP 6767 is reserved for a later measured transport; opening that port
today does not make gameplay use UDP. The [infrastructure guide](../infra/README.md)
keeps cloud deployment at plan-only status.

## Start a match

In a build containing the desktop Host controls, choose **Multiplayer > Host**.
Select **Team Deathmatch** and an arena, or **5v5 Sabotage** on Sector 9.
Choose **No bots**, **Fixed bots** or **Automatic fill**, then **Start server**.
Fixed bots keeps the requested bot count, four by default. Automatic fill
targets the total number of fighters, including humans and agents, and makes
room for either by replacing eligible server bots. Watch or Join becomes
available after the bundled server reports readiness. The default is local
to this computer on an available port. Enable **Allow LAN players** and choose
a port to invite another machine; peers enter your LAN address and that port
in Multiplayer. The app shows its own loopback connection address, not a
detected external address. Existing releases before this increment use the
dedicated command below.

Leaving a fighter seat or returning to the menu keeps your server running
for everyone else. **Stop server** explicitly ends the hosted match. Closing
the app also ends its owned server. Campaign saves are separate. A dedicated
process is preferable when the match must continue after the host closes
the game.

```bash
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --bots 4
```

Open the client and choose **Multiplayer**. On another machine, set
`FRAGR_SERVER` to `your-host:6767` before launching. For a LAN match, keep
TCP 6767 inside the network. Trusted friends can use a forwarded TCP 6767
port with the access policy below. The direct `ws://` connection is not
encrypted, and today's ticket flow gives each fighter the shared secret.
A stranger-facing host still needs TLS termination and a server-side ticket
issuer; that public admission path is planned, not shipped. Tailscale is
optional for private tests.

Other examples:

```bash
# Quiet local arena practice without timed round events.
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 0 --no-round-events

# Team deathmatch, Rail Only, first side to 25.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --bots 6 --mode tdm --mutator rail-only

# Golden Rail with two lives.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --bots 4 --mutator golden-rail --mutator two-lives

# Development CTF match on Sector 9, first side to three captures.
# Arena Duel is `--map 1` and Directive 17 is `--map 3`. The other arenas have no stands.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --map 4 --mode ctf --capture-limit 3 --bots 6

# Optional ten-seat Sabotage, five per side; four bots leave six seats.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --map 4 --mode sabotage --sabotage-five-v-five --bots 4

# TDM with automatic fill toward eight total fighters.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --mode tdm --bots 0 --bot-policy auto --fill-target 8

# Bot-filled 5v5, with equal human and external-agent admission priority.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --map 4 --mode sabotage --sabotage-five-v-five --bots 0 --bot-policy auto --fill-target 10

# Stay up and rotate maps and modes. Sabotage plays its short match first.
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --bots 4 --playlist
```

Automatic fill is available for plain TDM and Sabotage, without mutators. Its target is a desired
population, not an additional admission limit. Spectators do not count, while
reserved reconnect seats do. In a full active Sabotage round, replacement can
wait until the next round if removing a bot would change the outcome or cancel
a committed device or objective action. The refusal says to try next round;
Watch remains available. Ordinary late joiners wait for the next Muster with
the existing round rules. Fixed bots retain their existing seat behavior.

A server started with one mode keeps that rule set until it stops.
`--playlist` is the exception: the process stays up and moves through the
built-in night list when the current show ends. The order is Arena Duel
free-for-all, Compliance Yard free-for-all, Directive 17 team deathmatch,
Arena Duel capture the flag, Reclamation Gulch team deathmatch, Sector 9
capture the flag, Tripoint Works free-for-all, and Sector 9 Sabotage. Sabotage
plays its short match, including the half-time side swap, before the list
moves. Free-for-all is first to 10. Team deathmatch is first side to 25. Both
keep the three-minute clock. Capture the flag is first to three captures.
The list has no mutators. A playlist file is later. Two weapon mutators cannot
combine; Golden Rail also cannot combine with Licence to Kill, Shotgun Only
or Fists Only. Invalid combinations fail at startup. A night-list server,
a fixed team server, and capture the flag speak gameplay 37 and geometry 2.
An older or newer client is refused before Welcome. Campaign missions keep
their own floors.
[Multiplayer mode details](plans/multiplayer-modes.md) cover the rule contract.
The night list itself is [night playlist](plans/night-playlist.md).

## A night for about 24, and a house of about 64

Rule bots are fighters inside the process. They do not use a connection.
People do, and so does everyone watching. The process accepts 64
connections, and 32 of those may share one address. A household or an
office behind one public address stops at 32. Someone past that needs
another address. Spectators count toward both caps. `GET /status` does
not.

A straight run is 5 m/s. The floors, side to side, are Compliance Yard
110 m (about 22 s), Arena Duel 140 m (about 28 s), Directive 17 150 m
(about 30 s), Sector 9 200 m (about 40 s), Reclamation Gulch 280 m
(about 56 s), and Tripoint Works 320 m (about 64 s). A handful of
fighters on the longer floors is a walk. The same people on Compliance
Yard, Arena Duel, or Directive 17 is a scrap. The map rule sheet keeps
a large battle at 16 to 32 until a map is drawn for it and the tick is
measured. Sixty-four fighters is that later claim. It is not a bot
count in this build.

**About 24 people.** Eight bots keep the floor live when the room is
quiet. People join beside those bots. Twenty-four connections fit, and
connections remain for friends who only watch.

```bash
fragr-server --bind 0.0.0.0:6767 --playlist --bots 8 --status-every-s 60 --ban-list bans.txt
```

On the three shorter floors that room is a full scrap once people join.
On Sector 9, Reclamation Gulch, and Tripoint Works the same count still
leaves open ground. If the status log shows the slow ticks using more
than half of the 50 ms budget, drop to `--bots 4` before inviting more
fighters. One show, when the night is not the whole list:

```bash
fragr-server --bind 0.0.0.0:6767 --map 1 --mode tdm --bots 8 --status-every-s 60
```

**About 64 people.** Use the same fight. Do not pass `--bots 64`.
Sixty-four bots plus a crowd is not a measured match.

```bash
fragr-server --bind 0.0.0.0:6767 --playlist --bots 8 --status-every-s 30 --ban-list bans.txt
```

Sixty-four people is the whole connection cap. A full house has no
spare connection. Past 32 people on one address, the rest need another
address. Leave the bots at eight. Humans and agents join. Everyone else
watches. Print status every 30 seconds so a slow tick is obvious. This
is how many people the process will accept. It is not a claim that 64
fighters stay inside the tick, or that the fight is fun at that size.
That claim waits on the measurement soak in
[server excellence](plans/server-excellence.md).

Open TCP 6767 on the firewall for this binary. UDP 6767 does not carry
the match. UDP 6768 is only the LAN announcement. A detached night
omits `--console`, because that desk reads the terminal. Add it when
someone is at the keyboard. Set `FRAGR_JOIN_SECRET` when the door is
not open to the whole network. The secret is 16 to 256 bytes, in the
environment, on the host and on each fighter. Watchers do not need it.

At ready, an arcade process logs this room note with the bot count and
the two caps.

What is still missing before this is the fight you play all day, in the
order that raises the fun:

1. The body count has to match the floor. The settings above do that
   for a scrap night. They do not shrink Sector 9, and they do not draw
   the 16-to-32 battle map.
2. A fun bot hesitates, misses, and picks a different gun. The bots in
   this build take the shot they are allowed. That pass comes after the
   tick is measured.
3. On a real network, a shot should meet the person where they were,
   inside a hard cap. Grenades and mines stay in the present. That
   waits on a two-machine session.
4. A bigger room needs a smaller snapshot. Until that is measured, this
   is not a 64-fighter server.

Before the process reports ready, it requests its own `GET /status` on
loopback and refuses to start when that line is missing, the wrong schema,
or larger than the client reads. It then logs each non-virtual IPv4 address
it could reach from this computer. Use one of those addresses from the other
machine. A check on the host does not prove the other machine can connect:
the network, the firewall, and the address the other machine typed still
matter. Virtual adapters (VMware, WSL, Hyper-V, and the same class of name)
are not offered. In the app, Check host keeps "This host did not answer."
when no status was parsed. A finished request names the address it checked,
and says when the reply was too large or the host was busy. Check host uses
the address under Join a server and does not replace it. Run a server is a
separate page. Watch, Join and Stop for a server started in the app are on
that page.

A bind that is not loopback also broadcasts a LAN presence packet on UDP
6768 every two seconds. The packet is `FRAGR/1` and the game port. It is not
a join. The game stays on TCP 6767. The join page lists those announcements
after `GET /status` confirms them. Scan this network does not need that
packet: it probes this computer and each adapter's /24 with `GET /status`,
so a process that does not announce can still appear. The scan does not
search past those /24s. A client can always join by address. Favorites and
recent hosts stay in that install's `user://servers.cfg`. Watch, Join, a
successful check, and Save this host write that file. A process built before
this beacon does not send it.
The [join preflight](plans/join-preflight.md) records the status checks, and
the [server list](plans/server-list.md) records the book and the beacon.

## Join tickets and access lists

Without `FRAGR_JOIN_SECRET`, the join-ticket requirement is disabled; bans,
allow lists and capacity checks still apply. Set a
16 to 256 byte value on the host and on each trusted human or agent allowed
to fight when you want ticketed admission. The clients mint short-lived
tickets; this shared value is not a public player credential or user identity.
Spectators do not need one. The value stays in the environment, not a CLI
flag or saved game setting. An empty value leaves the host open, and a value
of the wrong length prevents startup. Host and client clocks should be within
about 15 seconds. A dropped pawn is parked briefly for resume; explicit
Leave removes it immediately. See the [wire contract](protocol.md) and
[hardening plan](plans/public-server-hardening.md).

Use `--ban-list bans.txt` to refuse peers or `--allow-list allow.txt` to admit
only listed addresses. Each line is an IP address or CIDR range, optionally
followed by `expires=2026-10-01` or exactly
`expires=2026-10-01T18:00:00Z` and then
`reason=` text. Lines beginning with `#` are comments. A ban wins over an
allow entry. Lists apply to watchers too. The server reloads them every five
seconds; a bad reload keeps the previous valid list and logs the error. A
bad file at startup prevents the host from binding. Lists and per-address
caps see a reverse proxy's address if the proxy hides real peer addresses.

A dedicated arcade server started with `--console` opens a venue desk on
that terminal: `who`, `kick <name>`, `ban <name> [reason]`,
`say <sentence>`, and `stats`. `who` and `stats` are for the operator.
`who` is not added to `GET /status`. `stats` reads the night sheet: rounds
finished, the busiest room, and the latest shows. That card may name a
top score. `GET /status` adds only `ops.night` with `rounds_finished`,
`peak_humans`, and `peak_fighters`. `ban` appends the ban file above and
then drops the live socket. The ban is still the address. Closing or
detaching the terminal closes the desk and leaves the match running.
Desktop Host and a local mission already use stdin as a lease, so they
refuse the desk. A container with no stdin has nothing for the desk to
read. A process started without the desk still records the sheet and
serves the three counts.

That same process keeps a wire board. `floor` is the room: a successful
speak, and a venue `say`, are copied there. `notices` hold posted lines
until the process ends. Nothing is written to disk, and a round change
does not clear either board. Spectators can read both and post a notice.
They still cannot speak, and a post to the floor is refused. Dial the
board with
`cargo run -p fragr-server --bin fragr-wire --locked -- --server 127.0.0.1:6767`.
The line commands are `list`, `read floor`, `read notices`,
`post <line>`, and `quit`. The wire contract is in
[protocol.md](protocol.md) under Wire board.

The host pings idle sessions and closes one that sends nothing, including no
automatic pong, for 45 seconds. Flooding or repeated unreadable frames can
also close a connection. Audit logs for joins, refusals, kicks and bans use
`RUST_LOG=fragr_server::audit=info` without logging tickets or resume tokens.
`GET /status` on the game port is a host probe, not a web client. Implemented
modes still need fresh human matches to establish clarity and fun.

## Server options

| Option | Purpose |
|---|---|
| `--bind <ADDR>` | Address, default `0.0.0.0:6767`. |
| `--bots <N>` | Rule bots to stock, default 4. |
| `--bot-policy <POLICY>` | `fixed` (default), `none` or `auto`. None and auto require `--bots 0`. |
| `--fill-target <N>` | Auto's desired total fighters, 1 through 10; zero for fixed/none. Auto is limited to plain TDM and Sabotage, without mutators. |
| `--map <ID>` | Arena ID or name; map 1 is Arena Duel. |
| `--map-rotate` | Alternate arenas between rounds. The mode stays the one chosen at launch. Objective modes refuse it. |
| `--map-file <PATH>` | Authored development map; requires `--bots 0` and no arcade overrides. |
| `--local-mission <ID>` | Desktop-owned mission on a loopback port with readiness and stdin lease. |
| `--desktop-host` | App-owned TDM or 5v5 Sector 9 arena with typed readiness and a stdin lease; the desktop menu sets this flag. |
| `--run-mode <MODE>` | `new` or `resume` for a local mission run. |
| `--local-run-preview` | Read-only campaign save compatibility for the menu. |
| `--solo-broadcast` | Episode 0 Calibration in Arena Duel. |
| `--playlist` | Stay up and rotate the built-in night list of maps and modes. Refuses a fixed map, mode, mutator, or limit. |
| `--mode <MODE>` | `ffa`, `tdm`, `ctf`, or `sabotage`. CTF runs on Arena Duel, Directive 17, or Sector 9. Sabotage runs on Sector 9. A fixed objective mode has no `--map-rotate`. |
| `--sabotage-five-v-five` | Optional Sabotage shared ten-seat profile, at most five per side, with pistol starts and map weapon upgrades. |
| `--sabotage-format <FORMAT>` | Dedicated Sabotage format: `short` or `match`. Desktop hosting uses its fixed preset. |
| `--mutator <ID>` | Repeatable: `rail-only`, `shotgun-only`, `fists-only`, `licence-to-kill`, `golden-rail`, `two-lives`. |
| `--friendly-fire` | Allow team damage in TDM. |
| `--frag-limit <N>` | Fighter limit in FFA or side limit in TDM; unavailable in CTF. |
| `--capture-limit <N>` | Captures to end a CTF round; valid only with `--mode ctf`. |
| `--no-round-events` | Disable timed slowdowns and boss spawns. |
| `--seed <N>` | Simulation seed, default 1. |
| `--status-every-s <N>` | Status log interval; 0 disables it. |
| `--ban-list <PATH>` / `--allow-list <PATH>` | Address lists described above. |
| `--console` | Local venue desk on a dedicated arcade match. End of input does not stop the process. |
| `--bench <N>` / `--bench-ticks <N>` | Offline scripted CPU benchmark, not a serving mode. |
| `--bench-check` / `--bench-assert` | Determinism repeat and threshold gate. |
| `--bench-trace <PATH>` / `--bench-verify-trace <PATH>` | Record or verify an offline trace. |

Run `cargo run -p fragr-server --locked -- --help` for the exact CLI of your
checkout. The benchmark reports CPU and byte measurements, not public-network
capacity or client rendering. Record commit and hardware alongside results;
the [benchmark contract](BENCHMARK.md) defines the limits.

The [home LAN](../infra/docs/HOME-LAN.md),
[cheap VPS](../infra/docs/CHEAP-VPS.md) and
[infrastructure](../infra/README.md) guides cover specific host environments.
Cloud Terraform remains plan-only until an approved spend decision.
