# Dedicated hosting

[Back to the README](../README.md) | [Home LAN](../infra/docs/HOME-LAN.md) |
[Cheap VPS](../infra/docs/CHEAP-VPS.md) | [Transport](TRANSPORT.md)

The Rust server owns each match. It runs locally without an account, cloud
service or API key. The current game transport is WebSocket JSON over TCP
6767. UDP 6767 is reserved for a later measured transport; opening that port
today does not make gameplay use UDP. The [infrastructure guide](../infra/README.md)
keeps cloud deployment at plan-only status.

## Start a match

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
```

One server keeps one rule set for its lifetime. Two weapon mutators cannot
combine; Golden Rail also cannot combine with Licence to Kill, Shotgun Only
or Fists Only. Invalid combinations fail at startup. Current clients and
agents understand team rules; older clients need gameplay capability 12 for
any nonplain arena rules, and CTF requires capability 14. [Multiplayer mode details](plans/multiplayer-modes.md)
cover the rule contract.

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

The host pings idle sessions and closes one that sends nothing, including no
automatic pong, for 45 seconds. Flooding or repeated unreadable frames can
also close a connection. Audit logs for joins, refusals, kicks and bans use
`RUST_LOG=fragr_server::audit=info` without logging tickets or resume tokens.
`GET /status` on the game port is a host probe, not a web client. CTF is in
draft review and needs a human match before it can be called accepted.

## Server options

| Option | Purpose |
|---|---|
| `--bind <ADDR>` | Address, default `0.0.0.0:6767`. |
| `--bots <N>` | Rule bots to stock, default 4. |
| `--map <ID>` | Arena ID or name; map 1 is Arena Duel. |
| `--map-rotate` | Alternate arenas between rounds. |
| `--map-file <PATH>` | Authored development map; requires `--bots 0` and no arcade overrides. |
| `--local-mission <ID>` | Desktop-owned mission on a loopback port with readiness and stdin lease. |
| `--run-mode <MODE>` | `new` or `resume` for a local mission run. |
| `--local-run-preview` | Read-only campaign save compatibility for the menu. |
| `--solo-broadcast` | Episode 0 Calibration in Arena Duel. |
| `--mode <MODE>` | `ffa`, `tdm`, or `ctf`. CTF runs on Arena Duel, Directive 17, or Sector 9, with no rotation. |
| `--mutator <ID>` | Repeatable: `rail-only`, `shotgun-only`, `fists-only`, `licence-to-kill`, `golden-rail`, `two-lives`. |
| `--friendly-fire` | Allow team damage in TDM. |
| `--frag-limit <N>` | Fighter limit in FFA or side limit in TDM; unavailable in CTF. |
| `--capture-limit <N>` | Captures to end a CTF round; valid only with `--mode ctf`. |
| `--no-round-events` | Disable timed slowdowns and boss spawns. |
| `--seed <N>` | Simulation seed, default 1. |
| `--status-every-s <N>` | Status log interval; 0 disables it. |
| `--ban-list <PATH>` / `--allow-list <PATH>` | Address lists described above. |
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
