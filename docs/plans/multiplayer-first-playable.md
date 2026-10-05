# First complete multiplayer trial

Status: **in flight**, October 5, 2026. Nick moved multiplayer modes and server
operation ahead of the remaining campaign. This bounded slice belongs to the
sole [Full build order](../ROADMAP.md#full-build-order), not a second build queue.

## Player outcome

Open the desktop app, host a match or enter a friend's address, watch, join and
play a complete match. Repeat with another person or agent on the same server.
The first trial concentrates on two existing modes:

| Mode | Existing rule contract | Trial venue |
|---|---|---|
| Team deathmatch | Team frags, ordinary respawns and the existing arcade arsenal; friendly fire off by default | Existing registered arenas |
| 5v5 Sabotage | At most five fighters per side, finite Pistol fresh starts, stronger map weapons, surviving equipment carry, plant/defuse and round spectating | Sector 9 |

These are not new rule implementations. Free-for-all, CTF and mutators retain
their current behavior. Additional objective maps, standalone elimination,
Liberation and Wipe remain separately planned. No buy menu is introduced.

## Current source and concrete gaps

Accepted main `f1e36315`, also v0.76.0, already implements authoritative TDM,
Sabotage and the optional ten-seat profile. Existing automated matches and
socket tests exercise combat, scoring, objectives, admission and resume. That
does not establish an enjoyable human match or complete desktop hosting.

The Multiplayer menu can enter an address, probe, watch and join. Its "Use local
server" button only selects loopback and probes; it does not start the packaged
native server. Existing local process ownership is campaign-specific. The boot
probe also builds a malformed HTTP address from an accepted full WebSocket URL,
and ignores the status response's existing mode and mutator fields. Some hosting
instructions still describe source-only setup or obsolete open integration gates.

## Bounded implementation seams

Reuse `LocalProcess`, native executable discovery, `server::local` readiness and
stdin ownership, and the same `run_server` that owns dedicated matches. The
desktop host wrapper has no campaign writer or run file. Ordinary dedicated
stdin and campaign process behavior remain intact.

A root-owned host lifetime survives Watch, Leave and return to menu, with an
explicit Stop action and cleanup when the app closes. Present local-only and LAN
binding as a deliberate host choice. Local startup uses an actual bound port;
LAN instructions use the host machine's real address. Do not invent discovery,
router configuration or a public deployment.

Validate one endpoint for both HTTP status and WebSocket gameplay. Show validated
existing mode/mutator fields; do not infer an unadvertised 5v5 profile from fighter
counts. Host choices are constrained to the two presets and compatible existing
maps. Core match rules, server authority and shared human/agent action remain
the existing contracts.

The client host flow and native arena-child plan own their respective code and
failure paths. This overview owns the trial outcome and priority; source, tests
and dated receipts decide what is actually built.

## Acceptance

- Launch the matching packaged server through the Host flow. Prove readiness,
  strict descriptor validation, busy bind, failed/early child exit and clean
  explicit shutdown. Do not stop an unrelated listener or write campaign storage.
- Use two independent client processes on the same server. Verify actual team
  scoring and result, Sabotage plant/defuse, shared rounds, appropriate weapon
  starts, readable identity, watch/leave/rejoin and occupied-seat handling.
- Verify the reconnect lease and stale/freed seats, status health and ordinary
  ingress/access-list refusal paths. Existing host controls remain address based;
  role or exceptional play is never evidence of cheating.
- Run the owning client and native checks, full required CI, desktop package and
   install checks on the composed source. Retain failures and their corrected proof.
  The existing unpacked-package smoke must reject script/runtime error logs as
  well as require numeric exit 0 and its own PASS marker. Its install check uses
  the matching bundled native executable for both owned arena presets, actual
  spectator maps/snapshots and Stop retirement. Keep all previous asset and
  campaign-preview gates; this is no substitute for a played match.
- Publish a concise trial guide with reproducible commands, actual captures and
  a feedback format. Record an actual two-machine LAN match separately from
  same-machine automation. Nick's unsteered play owns clarity, feel and replayability.

Human feedback guides refinement without stopping authorized local work. Bot
victories, a menu screenshot or headless checks do not close the human fun gate.
No release or public-server claim follows from a plan.

## Budget and retained work

This slice is $0 local development and self-hosting. No cloud apply, paid runtime
model, new asset batch, cash charge, renewal or overage is part of it. Retain the
private M11 native/save checkpoint and paused cast preparation rather than losing
reviewed work; broader mission and asset production resumes below this priority.
