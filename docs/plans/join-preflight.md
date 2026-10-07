# Join preflight

**Status:** implemented, 2026-10-06. Local tests named in Verification passed.
Not merged, and not a release.

## Goal

A long-running dedicated server should fail at startup when its own match
line is missing, and a player checking a host should see which address was
checked and why that check failed. The other computer's "This host did not
answer." line had been one sentence for a timeout, a refusal, an oversized
body, a busy snapshot, and a body that was not JSON.

## What was wrong

`GET /status` copied the snapshot while holding the status lock. When that
lock was busy, the process answered HTTP 200 with `{"schema_version":1}`.
The client treats schema 1 as "did not return a match line." A serde failure
answered `{}`, which the client treats as a host that did not answer.

Readiness was signaled before the accept loop was running, so a client that
connected in that gap could be refused. Nothing probed the status line, and
nothing logged which of this computer's addresses answered. A check from this
computer still does not prove another computer can connect. The log has to
say that.

The app collapsed every failed HTTP result and every non-dictionary body into
"This host did not answer." The missing-status path keeps that exact sentence.
A completed request now says which address it checked.

## Behavior

Before the process reports ready, it requests `GET /status` on its loopback
address and requires HTTP 200, schema 2, kind `arena` or `campaign`, a
non-empty map, and a body of at most 4096 bytes. That is the client's read
limit. A schema mismatch fails immediately. A refused or busy loopback probe
is retried, then startup fails.

A wildcard bind then lists non-virtual IPv4 addresses and probes each one.
Loopback, link-local, and adapters whose names contain vmware, vethernet,
wsl, hyper-v, bluetooth, virtualbox, docker, loopback, teredo, or isatap are
not offered. A failed self-probe is a warning. A loopback bind logs that
other computers cannot join. A specific bind probes only that address.

Interface names come from `if-addrs` 0.15.0 (checked 2026-10-06, MIT or
BSD-3-Clause). The server crate still has no HTTP client. The probe is a
short TCP read. `/status` still omits addresses, callsigns, ids, and tokens.
The log may name this computer's own join addresses.

When the status lock cannot be copied within 50 ms, the probe answers HTTP
503 with `{"schema_version":2,"busy":true}` and does not invent a map. It
does not answer schema 1 or `{}`. The snapshot is serialized after the lock
is released.

A new socket waits up to one second for its first bytes before it is treated
as a game handshake. A `GET /status` that arrives inside that wait is still
a status probe. A line that is clearly not status returns at once. The old
50 ms peek gave up, so the desktop Check host, which connects and writes on
a later frame, was already in the WebSocket handshake when its request
arrived. `a_status_line_that_arrives_after_connect_is_still_status` writes
400 ms after connect and requires HTTP 200. The running night process does
not have this wait yet.

Check host keeps "This host did not answer." when there is no parsed status.
A finished request adds the address. An oversized body, a busy host, and a
200 that is not a JSON object each have their own sentence. Watch and Join
stay disabled. Check host reads the join address and does not replace it.
Starting a server is a separate page ([join menu](join-menu.md)).

## Non-goals

No new mode, no Wipe, no Terraform, no tick change, and no measurement table.
No claim that a local probe means another computer can connect. No firewall
change inside the server. No playlist file. No changelog entry until a
release is cut.

## Verification

Local, 2026-10-06, on this machine:

- `cargo fmt --all -- --check`
- `cargo clippy -p fragr-server --all-targets --locked -- -D warnings`
- `cargo test -p fragr-server --locked --lib preflight` (the join filter,
  schema 1 without a retry, a live loopback probe, and a busy reply)
- `cargo test -p fragr-server --locked --lib a_busy_status` (a held status
  lock answers HTTP 503, then the next probe is schema 2)
- `cargo test -p fragr-server --locked --lib late_connections_receive_authoritative`
  (a real process reports ready only after its own status line)
- Godot 4.7.2 headless `test_frontend.gd`: PASS. The missing-status sentence
  stays exact, and the new timeout, size, and busy sentences are checked.

Workspace CI was not run. Spend is $0.

## Success

The process logs a schema 2 loopback answer before ready, names each join
address it could reach from this computer, and says that this does not prove
another computer can connect. Check host names the address when the line
does not come back.
