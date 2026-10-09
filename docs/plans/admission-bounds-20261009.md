# Admission, ticket, and supply bounds

Status: **in flight**. Branch `fix/admission-bounds`. Not merged.

## Goal

Keep one remote address, one untrusted snapshot, or one mutable third-party
reference from exhausting a match process, replaying a join, or changing a
release artifact. Local and loopback play keep enough room for the desktop
client, playtests, and soak.

## Non-goals

Campaign maps, difficulty, combat rules, save versions, gameplay version,
cloud apply, and paid asset generation. No second campaign door and no second
ticket field. A v2 ticket is a new string in the existing hello ticket.

## Server admission

A socket takes a pre-classification permit before the one-second status wait
and before it holds a global probe. A normal address gets 4 concurrent
permits and 8 accepts per second with a burst of 16. Loopback (`127.0.0.0/8`
and `::1`) gets 32 permits and 64 accepts per second with a burst of 64.
Exhaustion fails immediately.

Status answers stay inside the existing global cap of 8, plus 2 per normal
address and 8 on loopback. Unticketed spectators are capped at 16 process-wide
and 4 per address (8 on loopback) and still count toward the global 64 game
connections. Humans and agents are not refused by the spectator cap.
`FRAGR_SPECTATOR_TICKET=1` requires a spectator-role ticket only when a join
secret is set. The default remains that spectators are not ticketed.

Live and parked participant pawns share a process cap of 96 and a per-address
cap of 40 (64 on loopback). A new join is refused before a player is created
when the cap is full. Resuming an already parked id still works and does not
create a second pawn. Parked pawns with no live socket stay out of outbound
snapshots for the existing 200-tick resume window. Ticks, input sequence, and
inventory are not rewound. New joins, not resumes, are limited to 4 per 10
seconds per normal address and 30 per 10 seconds on loopback.

The game-command channel holds 256 messages and does not block the socket.
The latest action for a player replaces an older unconsumed action. Board
messages are validated before enqueue. A session may place 8 KiB of accepted
board payload per second, and an address may place 16 KiB per second. Notice
cooldowns are keyed by peer address, hold at most 256 addresses, and share a
global rate of 8 per second.

A missing `Origin` is allowed, which covers the native client. A present
`Origin` is rejected unless it is an exact entry in `FRAGR_ORIGIN_ALLOW`.
Unset or empty rejects every present origin.

## Join tickets

`ticket_for()` still mints v1, and the existing v1 golden stays. v2 binds an
expiry, a role, a 32-hex nonce, and a canonical audience (`scheme://host:port`,
lowercase scheme and host, explicit port). The audience travels as unpadded
URL-safe base64, and the MAC covers the raw audience string.

When `FRAGR_JOIN_AUDIENCE` is set, v1 is rejected and v2 must match that
audience. When it is unset, v1 still admits for local tools, and v2 admits
once for any well-formed audience. Each v2 nonce is redeemed once until
expiry. The cache holds 4096 unexpired nonces and rejects a new one when it
is full. Tickets, resume tokens, and secrets are not logged.

The client does not attach a ticket to a public cleartext `ws` host. A ticket
is allowed on `wss` and on loopback or private LAN. A connection without a
ticket remains allowed. Saved server-book entries keep their scheme, so `ws`
and `wss` are different endpoints. A scheme-less older entry loads as `ws`.

## Client snapshots

Every player row is validated before any campaign shortcut: bounded id and
name, finite pose, integer health and score, an allowlisted weapon, and
allowlisted team and body when those fields are present. Duplicate ids are
rejected. The player array caps at 64. A snapshot that would create more than
64 players, 256 pickups, or 320 new nodes is rejected before any node is
created. Displayed strings stay inside the server bound.

## Developer tools and CI

A paid audiogen POST requires a finite spend cap and a reservation taken
before the call. A timeout, a 5xx after send, or a 429 after a billed accept
stays uncertain and blocks another paid POST until it is reconciled.
Generation POSTs are not retried automatically. Response bodies are capped
before they are buffered. Output writes refuse a symlink in the destination
path and do not replace a symlink.

Every third-party `uses:` in the workflows is a full commit SHA, with the
readable tag in a trailing comment. Rust is pinned to 1.97.1, the stable
toolchain checked on 2026-10-09. Godot 4.7.2-stable downloads are checked
against `tools/godot/SHA512-SUMS.txt` before unzip or execute. The committed
file is the pass/fail pin.

## Protocol and saves

No gameplay version bump, no campaign rules revision, and no save migration.
`docs/protocol.md` records the v2 ticket string and the connection caps.
Workflow permissions stay as they are: `contents: write` only on the tag
publish job.

## Verification

Server tests cover the v1 and v2 goldens, a replayed nonce, a partial socket
that does not consume another address's permit, and a full spectator cap that
still admits a participant. Client harnesses cover the book scheme, the v2
golden, actor validation, and the snapshot node cap. Brain and adapter tests
use fake transports. `tools/check_action_pins.sh` and
`tools/test_check_godot_archive.sh` run without a network and without
downloading Godot. A flipped fixture byte fails the archive helper.

## Spend

$0. No cloud apply and no paid provider call.
