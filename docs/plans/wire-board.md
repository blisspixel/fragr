# Wire board

**Status:** in flight, 2026-10-06. Local. Not merged.

## Goal

The server that is already hosting the match also keeps a board for the
humans and free agents in the room. One board is the live floor, which is
the speak that is already there. The other is notices, which stay until
that process ends. A person dials it with `fragr-wire` and reads a line
board. An agent uses the same JSON on the same socket.

## Non-goals

Mailboxes, accounts, a second port, a telnet door, disk archives, a public
directory, and a Godot screen for the board. The venue desk stays the
operator's stdin. This does not build the detached-desk plan, Wipe, or
another combat mode. Gameplay version stays 37. The on-air Host is not the
voice of the board.

## Architecture

`server/src/board.rs` owns the two rings. `GameSession` copies a successful
speak and a venue sentence onto the floor, and answers `board` unicasts to
the connection that asked. Spectators can list, read, and post a notice.
They still cannot speak. The floor rejects posts.

`fragr-wire` is a second binary in the server package. It connects as a
spectator, prints the masthead, and speaks the board commands. The package
`default-run` stays `fragr-server`, so `cargo run -p fragr-server` still
starts the match. Docker and the release package still copy `fragr-server`
by name.

The MCP adapter's `speak` tool still feeds the floor through the existing
callout. A notice tool on that adapter is the next slice. An agent that
speaks the JSON can post today.

## Protocol

See `docs/protocol.md`, "Wire board". No gameplay or record version change.
Unknown client types stay ignored, so an older server does not drop the
socket for a `board` message it does not know.

## Verification

Board unit tests, a session test for the floor copy and a spectator notice,
a spectator socket test that the list is forwarded, and `fragr-wire` command
tests. `cargo fmt`, server tests, and clippy.

2026-10-07 loopback dial, not a public listener: `fragr-wire` against
`127.0.0.1:6791` listed both boards empty, posted `still here`, and the
following read returned that line under the name Wire. The client exited 0.

## Spend

$0. No new crate.

## Success

A spectator on a running server can list both boards, read a speak that just
happened, and leave a notice that a later read returns. Posting to the floor
is refused. The lines die with the process.
