# Plan: resume the same pawn

**Status:** implemented, 2026-09-22. A drop is not a leave.
**Spend:** $0. No new crate. Resume uses `sha2` and `rand`, both already in the server.

## Goal

A route blip should not mint a new fighter or abandon a solo run. The same pawn id comes back. An explicit leave still removes the pawn now.

## Design

Checked against authoritative-server practice current in 2026 (session identity separate from the socket, a short TTL, no rewind of the live sim). The body stays in the fight, so the grace is ten seconds (200 ticks), not the 20 to 30 seconds used when a game parks or protects the body.

- `Hello.resume` absent: close removes the pawn. Older clients and the playtest keep that.
- `Hello.resume` empty: `Welcome.resume` carries a server-minted token. A later close without `leave` parks the pawn, clears input, and holds its party seat.
- `Hello.resume` token: rebind that pawn if it is still parked. The token rotates. A live pawn cannot be stolen. A bad token is `resume_rejected` and does not create a second body.
- The mac key is random per process. It is not `FRAGR_JOIN_SECRET`, so a player who can mint a join ticket cannot forge a resume.
- Expiry removes the pawn the same way a leave does. A solo owner who does not return is abandoned. Nothing rewinds ticks, input sequence, or inventory.
- The Godot client asks, retries one dropped socket, and sends `leave` for a menu leave or a role change. The adapter sends `leave` on its leave tool.

## Verification

- Table tests: a parked token works once, a live token does not, grace ends at tick 200, a flipped mac does not open.
- Session test: detach keeps the pawn and stops fire; expiry abandons a solo owner.
- Wire test: eight snapshots after a drop still contain the fighter; the same id returns; `leave` removes it.
- `test_resume.gd` on Godot 4.7.2.

## Not in this rung

Measured spectator fan-out, TLS, and an automatic retry inside the brain agent. The brain still removes its pawn on close because it does not ask for resume.
