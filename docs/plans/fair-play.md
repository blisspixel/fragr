# Fair play and host moderation

Status: **planned** follow-up, current controls recorded 2026-10-04.
Spend: $0. Scope belongs to multiplayer depth in ROADMAP.md.

Humans and agents are welcome in the same match. Excellent aim, fast reactions
and machine control are not cheating. Allegiance is separate from control
method and body type. Protect outcomes and let hosts moderate their rooms
without kernel drivers, client surveillance or mandatory external accounts.

## Built controls and limits

The Rust server owns movement, collision, damage, health, ammunition, weapon
cooldowns, pickups and rounds. Clients request actions rather than assigning
outcomes. Validation and bounded traffic reduce abuse; they do not prove the
absence of implementation bugs or perfect cheat resistance.

As of 2026-10-06, a shared arcade room admits only the gameplay and geometry
versions that binary speaks. A campaign mission still uses its content floor,
and every door refuses a hello newer than the binary. A human action on a
shared-room socket drops `look_at`, so the server does not aim that pawn.
Yaw and pitch stay. An external program that sends those angles is ordinary
input. Excellent aim, fast reactions, and machine control are not cheating.
An agent may still send `look_at`. A campaign human socket may still send it,
because the mission probe aims that way. That campaign path is not closed.
There is no kernel driver, no client scan, and no automatic ban.

`server/src/access.rs` owns strict address/CIDR allow and ban lists. Bans can
expire at midnight UTC on a date or at an exact UTC timestamp. Startup refuses
malformed policy; a bad reload preserves the previous good list. Reloads
check every five seconds and apply to connected peers too. Callsigns are not
ban identities. Optional join tickets protect fighter admission, while
spectators are not ticketed. Never log tickets or resume tokens.

Run `fragr-server --ban-list bans.txt`. One valid entry is
`192.0.2.8 expires=2026-10-11T12:00:00Z reason=repeated abuse`.
On a dedicated arcade match, `--console` can append the connected address
of one uniquely named person to that same file and drop them now. The ban
is still the address. The desk does not ban a name, and it does not pull
a roster bot.
See [home/LAN hosting](../../infra/docs/HOME-LAN.md). Address bans can affect
shared networks and can be evaded by changing address; hosts need review and
an easy way to remove mistaken entries.

Full fighter snapshots currently expose information a modified client can use
through cover; spectators can relay information too. Visibility-based interest
management, spectator delay, bounded lag compensation and replay review are
follow-ups, not proven protections today. There is no automatic-ban switch or
reliable human-versus-agent classifier in the current server.

## Planned defense in depth

1. Keep validation and rate limits at existing server boundaries, with bounded
   observable counters and focused failure-path tests.
2. Minimize fighter information where visibility rules allow. Measure peeks
   and reappearance so withheld state does not create unfair pop-in. Decide
   spectator policy explicitly without breaking watch-or-join play.
3. Add optional visible host room rules and declared roles. A role claim is not
   proof of control. Do not infer faction, transfer rooms or punish players
   based on aim, reaction time or skill profiling. Mixed play stays welcome.
4. Offer optional temporary bans for repeated server-confirmed transport abuse
   already subject to disconnection, disabled by default. Define thresholds,
   duration, bounded history, reason and review before implementation. Ordinary
   bursts, desync, expired tickets, compatibility fields and skill alone do
   not qualify. This is not a promised generic cheat detector.
5. Reuse AccessList ownership for policy writes, with strict entries, atomic
   replacement and protection against concurrent host edits. Test expiry,
   reload, reversal and shared-address mistakes. Do not build a second ban
   store inside a client or adapter.
6. Add server-side evidence and deterministic replay only after their storage,
   privacy, timing and compatibility contracts are implemented and verified.
   Existing offline traces are not an unrestricted replay service.

Acceptance requires legitimate human and agent traffic to remain admitted,
confirmed abuse to be bounded, host decisions to be reversible and sensitive
identifiers absent from public status. Good players are not a negative test.
