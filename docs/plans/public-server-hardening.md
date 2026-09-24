# Plan: public server hardening

**Status:** in flight, 2026-09-24. v0.35.0 shipped frame and message caps,
handshake and hello deadlines, global plus per-address connection caps, and
an inbound budget (burst 64, 256 per second). v0.36.0 shipped `GET /status`.
v0.37.0 shows that line in the app. v0.38.0 shipped HMAC join tickets. v0.39.0
keeps a dropped pawn for ten seconds. Rung 2 (`feat/hardening-rung2`) adds a
15 second ping with a 45 second idle close, kick-on-repeat for floods and
unreadable frames, host ban and allow lists, and an audit log target. A quiet
spectator that reads is not idle. Next is a measured spectator fan-out before
any higher connection cap, then TLS. Timing percentiles stay on the log. No
new crate.
**Branch:** `feat/hardening-*` (one PR per rung)
**Spend:** $0 for everything here. A VM for the stranger test needs written approval and sits under the cap.

## Goal

Phase 2 of [`../ROADMAP.md`](../ROADMAP.md): a server you can open to the internet on port 6767 (or behind TLS on 443) that strangers and their agents can join without it falling over, plus the status endpoint and benchmark mode the 1.0 bar needs. This plan records the research of 2026-09-18 as concrete settings and crates.

## Non-goals

- Accounts, identity, or matchmaking. Tickets prove a join was issued, not who a player is.
- A web export. Godot Web is out of scope for the project; the ticket travels in the first frame.
- A metrics stack. The status JSON is enough until something scrapes it.

## Design

1. **Frame and buffer caps.** `tokio-tungstenite` takes a `WebSocketConfig` through `accept_async_with_config`. Defaults are 64 MiB per message and 16 MiB per frame with an unlimited write buffer. Set `max_message_size` to 64 KiB, `max_frame_size` to 64 KiB, and `max_write_buffer_size` between 256 KiB and 1 MiB; a full write buffer surfaces as an error, which is the cue to drop a slow reader. The pinned 0.24 exposes plain fields; the current 0.30 makes the struct non-exhaustive with builder setters and adds a read buffer size, so the upgrade is its own PR.
2. **Accept hardening.** Wrap the handshake in a five second `tokio::time::timeout` (slow-loris); cap connections per IP with a `DashMap` and total connections with a `tokio::sync::Semaphore`; ping every 15 seconds and close a session that sends no frame, not even a pong, for 45 seconds. Tower middleware does not fit a raw accept loop. `governor` was not added: the per-address connection cap already bounds concurrent accepts, and the shipped per-session token bucket plus a leaky strike counter cover the rest without a new crate.
3. **Join tickets.** HMAC-SHA256 with the existing `sha2` crate. No new crypto crate. The ticket is `v1.<unix exp>.<human|agent>.<64 lowercase hex>`, over `fragr-join-v1`, the expiry, and the role. It does not carry the callsign. The server accepts an expiry from 15 seconds ago through 75 seconds ahead and compares the mac with xor. `FRAGR_JOIN_SECRET` is 16 to 256 bytes, read by the dedicated and local processes, never by `run_server` itself and never from clap or `settings.cfg`. No secret leaves hello open and ignores any ticket. Spectators are never ticketed. A bad ticket is `join_rejected` before a party or solo seat is taken. The same ticket can be replayed until it expires. TLS is what closes that window. A separate rejoin token is the reconnect rung, not this one.
4. **Names and roles.** Three to sixteen characters, NFKC normalised, allowlist letters, digits, underscore, and hyphen; reserved names such as server and admin; duplicates get a suffix. Admin is gated on a token, never on a name, since without an auth server anyone can take any name.
5. **Speak and action limits.** Speak keeps the shipped 60-tick cooldown from `docs/protocol.md` (mirrored in the adapter). The per-session action-rate cap is the inbound budget (burst 64, 256 per second). Dropped messages feed a strike level draining at 4096 per second; past 8192 the session closes with `rate_limited`. The drain is that high because the Godot client sends one action per rendered frame and renders uncapped by default. Unreadable frames (binary, or text without a JSON object and string `type`) feed a second level draining one per second; past 16 it closes with `malformed`. Well-formed unknown types stay ignored for forward compatibility. Both kicks remove the pawn and its resume token. Ban and allow list files (`--ban-list`, `--allow-list`): one IP or CIDR per line, optional `expires=` (UTC date or `YYYY-MM-DDTHH:MM:SSZ`) and `reason=`, strict parsing with line numbers, refused at start when malformed, reread every five seconds with a bad edit keeping the previous list. A refusal happens before any slot, seat, or status answer. A new ban closes a matching live session. Entries never match callsigns. No player id column: there are no accounts.
6. **TLS.** Terminate at Caddy: `reverse_proxy localhost:6767` upgrades WebSockets automatically, `stream_close_delay 5m` survives reloads, certificates by DNS-01 (no open port, works behind NAT, DuckDNS or a DNS plugin) for a home box or HTTP-01 on a VM. The client connects with `connect_to_url("wss://play.example", TLSOptions.client())` by name, never by IP. No in-process rustls; issuance and reload would be extra code for no gain.
7. **Status over HTTP.** The status line and `--bench N M` are built by playtest rung 3 in Phase 1. This rung serves the same JSON to a plain `GET /status` on the game port, answered from the WebSocket upgrade callback before any upgrade, so no HTTP crate is added; a `status` WebSocket message mirrors it for Godot. Percentiles come from `hdrhistogram`, the one new crate here. A Prometheus `/metrics` endpoint waits until something scrapes it.
8. **Protocol version.** Decided 2026-09-24: no single `protocol_version` field. `gameplay_version` and `geometry_version` are maximum-understood capabilities; each rejects an older client before `Welcome` with a code naming the missing contract (`unsupported_gameplay`, `unsupported_geometry`) and admits newer ones. A single number would duplicate them and could only say "different". The JSON envelope has not changed; a breaking envelope change would add the field with its own rejection code. Recorded in `docs/protocol.md`. The MCP side is covered in [`agent-door-2026.md`](./agent-door-2026.md).
9. **Audit log.** One `tracing` target, `fragr_server::audit`, with `event` = `join`, `resume`, `reject`, `kick`, `ban`, `lists_loaded`, `lists_reloaded` or `lists_rejected`, plus peer address, client id, role, player id, a bounded escaped callsign, and the stable code. Tickets, resume tokens and the join secret are never fields.

## The cheapest sane public setup

Plaintext on port 6767 stays the LAN path and the documented public path, as the README and hosting guides say. The TLS option is a small VM with the firewall open only on 22, 80, and 443, fragr bound to loopback, Caddy in front, or a home box with DuckDNS, DNS-01 certificates, and only 443 forwarded. Both go in `infra/` once proven.

## Verification

- A test for every reject path (oversize frame, bad ticket, expired ticket, bad name, rate limit, idle, per-IP cap).
- Property tests over the wire parser in `server/src/tests.rs` on stable Rust (cargo-fuzz needs nightly and stays a local extra with a committed corpus if ever used).
- A flood test against a local server with the caps on, watching the status JSON stay sane.
- The status and benchmark JSON documented in `docs/protocol.md`.
- The stranger session from the roadmap, recorded, with the hosting guide updated from what went wrong.

## Rungs

1. Frame and buffer caps, handshake timeout, idle timeout, per-IP and global caps. Tests. New crates: none (`DashMap` only if the per-IP map outgrows a mutexed `HashMap`).
2. Idle ping drop, kick-on-repeat, ban and allow lists, audit log. New crate: none (`governor` not needed, see Design 2).
3. Join tickets. No new crate (`sha2` is already a server dependency). Rejoin tokens stay with reconnect. Gameplay and geometry versions already reject an old hello. A single `protocol_version` field is not this rung.
4. Status over HTTP on the game port and the Godot status message. New crate: `hdrhistogram`.
5. Caddy guide and the wss client path; the stranger session.

## Success criteria

- [ ] Rung 1 shipped with reject-path tests. Caps, deadlines and budget shipped in v0.35.0; the idle close lands with rung 2.
- [ ] Rate limits and lists shipped: tests cover idle close with a parked pawn, a quiet reading spectator kept past three idle windows, flood and junk kicks that remove the pawn, unknown types ignored, ban and allow refusals before a seat or status, a live ban edit, strict list parsing, and reload keeping the last good list. Open until merged and released.
- [x] Protocol version decision recorded: no single field; capabilities already reject old clients.
- [x] Join tickets shipped: bad, expired, wrong-role, and missing tickets are `join_rejected` before a seat is taken. Watchers stay open. An unset secret ignores a ticket.
- [ ] Reconnect tokens. Gameplay and geometry versions already reject an old hello.
- [ ] Status and benchmark mode shipped and documented.
- [ ] A recorded stranger session behind TLS.

## Progress

- 2026-09-24, rung 2 on `feat/hardening-rung2`: `server/src/access.rs` (lists), `server/src/net.rs` (ping, idle, strikes, kicks, audit), `--ban-list` and `--allow-list` in `server/src/main.rs`. Verification commands and results are in the PR body.
- Open after rung 2: the Godot client does not yet map the new close codes to messages or skip its one resume attempt after `rate_limited`, `malformed` or a ban (GDScript follow-up). The client sends one action per rendered frame; a send throttle would let the flood threshold come down. Behind a reverse proxy the lists and per-address caps see only the proxy address; there is no forwarded-address support. There is no inbound byte-rate budget beyond the 64 KiB frame cap.
