# Server list

Status: **implemented**, 2026-10-06. Not merged, and not a release.

## Goal

The join page should work the way a boomer-shooter server browser does. Type an address and connect. Keep favorites and recent hosts on this computer. On a LAN, see a server without typing its address. On the internet, the same address field and the same saved list reach a host that does not announce.

## Behavior

**Direct connect** stays the address field. Check host reads that field and does not replace it. Watch and Join stay disabled until the match line is a schema 2 arena or mission. A successful check appends the round-trip time to that line, for example `12 ms`. The missing-status sentence is still exactly "This host did not answer."

**Save this host** keeps the typed address. A check that returns a match line also remembers the address when it was not already saved. Watch and Join remember it too, even when the check was skipped. Favorites hold 12. Recent holds 8. The file is `user://servers.cfg` on this computer. There is no account and no custom label. Drop removes a saved host. Keep moves a recent host into favorites. The same host is stored once: `127.0.0.1` and `127.0.0.1:6767` are one row. A scan does not write the book. Choosing that row and watching or joining does.

**On this network** listens only while the join page is open, and leaving the page closes that socket. A beacon is not a row by itself. The page probes `GET /status`, and the address takes one of the eight slots only when that reply is a schema 2 match or this server's busy body. An unanswered packet, a public address, and the cloud metadata address do not take a slot. At most eight probes wait at once. The section is not written to disk. Hide removes one for this visit. If nothing announces, the page says so and the address field still works.

**Scan this network** is a button. It does not run by itself. Godot does not report a subnet prefix, so the scan checks `127.0.0.1`, then this computer's private, link-local, and `100.64.0.0/10` IPv4 addresses, then the other hosts in those /24s, and stops at 1024 addresses. A public adapter is skipped. `169.254.169.254` is skipped, including when it is a neighbor in the same link-local /24. The port is the one in the address field, or 6767. Sixteen `GET /status` probes run at a time, each with a half-second budget. A closed port is not a row. A schema 2 match line or a busy reply is. The night process does not broadcast, and this scan can still see it, because the probe is the same status read Check host already uses. It does not take a player slot. A wider network than /24 is not guessed, and the public internet is not scanned.

A row shows the address, then the map, the fighter count, the mode when the server sends one, and the check time. It does not show callsigns. A list check does not change the Watch and Join line unless that row is the address in the field. Busy, no answer, and a reply that is not a match each have their own short row text.

## LAN presence

A process whose bind is not loopback broadcasts UDP `6768` every 2 seconds. The packet is exactly `FRAGR/1 <tcp-port>` and a newline. It names the game port and nothing else. It is not a join, not a status body, and not the game transport. Loopback binds, including tests and a same-computer desktop host, do not send it. A wildcard or LAN address does.

The client still joins on TCP `6767`. A firewall that blocks UDP `6768` leaves direct connect and the saved list working. The game port stays TCP.

The night process that is already running was built before this beacon. It does not announce. Replacing it would reset the match, so it stays up as it is.

## Non-goals

No public directory, no master server, no web client, and no accounts. Public `/status` still has no callsigns, addresses, tickets, or tokens. The beacon does not carry those either. Join tickets are not shown, because the public status line does not say whether a ticket is required. A gameplay-version warning is not on the wire yet, and an old server stays joinable. UDP game transport stays the measured spike in `docs/TRANSPORT.md`. No changelog entry until a release is cut. No screenshot tour until that release. No new mode, no Wipe, no Terraform, and no measurement table.

## Architecture

`server/src/announce.rs` owns the packet. `run_server` starts the broadcast only when `should_announce` is true, and aborts it with the process. `client/scripts/server_book.gd` owns the file, the row text, and the same packet parse. `boot_menu.gd` draws the rows and probes them with a second `HTTPRequest`, separate from Check host. A cancelled probe cannot apply an older reply to a newly selected row. Harnesses that pass their own settings file get a sibling `.servers` file, so they do not write this computer's real book.

## Verification

Godot 4.7.2.stable headless, 2026-10-06, on this machine:

- `test_server_book.gd`: PASS. Canonical addresses, the 12 and 8 caps, junk lines, a row that names map, mode, and check time and does not repeat a callsign, and the beacon parse.
- `test_frontend.gd`: PASS. The match-line sentences are unchanged. Save, select, drop, and hide work. A list row does not replace the join line. Watch still follows Check host. The log has no `ERROR:` line.
- `test_host_menu.gd`: PASS. Run a server and Join a server stay apart. Watch still follows Check host.

`cargo test -p fragr-server --lib --locked announce`: 2 passed. The packet test sends to `127.0.0.1:0`, not to `0.0.0.0:6767`. `cargo clippy -p fragr-server --all-targets --locked -- -D warnings` is clean. `cargo fmt --all -- --check` is clean.

Scan and remembered joins, Godot 4.7.2.stable headless, after `--import`, exit 0, no script or parse errors:

- `test_server_book.gd` PASS. The /24 list, the 1024 cap, a busy row, and a closed port that finishes with no row.
- `test_frontend.gd` PASS. The Scan button is on the join page, and Watch or Join writes the book. Check host still sits immediately before Watch.
- `test_host_menu.gd` PASS. Run a server and Join a server stay apart.

The full `tools/godot_check.sh` suite and the workspace CI suite were not run. Spend is $0.

## Success

A player can type a host, save it, and return to it. A server on the same LAN can appear without that typing, after its status line confirms it. A server on the internet is the same field and the same saved list. The night process was not restarted.
