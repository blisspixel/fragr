# First-person watch and match chat

Status: planned, 2026-09-22; reviewed against main 2026-09-26 (spectators still
start in first person, `Speak` still accepts only fighters, join tickets shipped). Nick wants watching a live match to feel like a
first-person retro shooter stream, with a simple shared chat and no ads.
Sequencing belongs to the [full build order](../ROADMAP.md#full-build-order-2026-09-22).

## Goal

Open a match as a spectator in the followed fighter's eyes by default. Show
their authoritative camera, weapon, vitals and combat effects. Keep chase and
free cameras as optional controls. Give admitted humans, agents and spectators
a bounded match chat in a compact pixel UI that can be opened while watching or
playing. Preserve the watch-or-join flow and make chat easy to hide.

## Non-goals

No accounts, friends, direct messages, persistent transcripts, ads, donations,
streaming platform integration or model-generated chat by default. Chat cannot
give spectators an action channel or affect combat. A developer first-person
playtest pin is separate from the player's ordinary camera cycling.

## Architecture and protocol

The current spectator camera already starts in first-person follow; validate
that every entry path preserves that default. Reuse the existing off-tick
`Speak` intent and server broadcast where its contract permits, rather than
introducing a second messaging service. Today `Speak` only accepts fighters,
the Godot client sends rotating preset taunts, and the feed displays one short
line. Extend the server boundary for spectator messages with a connection-bound
identity, validated display name and role, while leaving `Action`, `MissionReady`
and `MissionContinue` unavailable to spectators. Enforce character and byte
limits, control-character rejection, per-connection cooldown, bounded delivery
and disconnect cleanup on the server. The sender cannot supply their displayed
name or role in a message. Mark spectators distinctly in the feed. Update
`docs/protocol.md` and adapter behavior if the wire shape or capability changes.
On a hosted server with `FRAGR_JOIN_SECRET`, anonymous spectators still watch
without a ticket but cannot send chat. A spectator who presents a valid
role-bound chat ticket may speak; a spectator ticket never grants a pawn seat or
gameplay controls. Local/LAN hello remains open when no secret is configured.
This closes the anonymous reconnect path around per-connection cooldowns.

The Godot chat panel is a small, scrollable, capped transcript outside the aim
area. A key opens a single-line draft, Enter sends through the existing network
client, Escape closes, and typing consumes gameplay controls and pointer input.
Spectators can send; fighters can send without firing or moving accidentally.
The current quick taunts can remain as a separate shortcut through `Speak`.
Use the established palette, pixel font and menu controls, with a visible mute
and hide control. Avoid a large video-site overlay over the actual fight.
While a draft has focus, suppress gameplay inputs and manual camera controls,
but keep passive first-person follow and network rendering active. Retain a
draft if the server rejects it and display only accepted server echoes in the
transcript; an attempted send is not a confirmed message.

## Validation and success criteria

- Rust tests prove spectator, human and agent messages; forged identity and
  gameplay commands from spectators are rejected; limits, cooldown and cleanup
  hold under a mixed roster and slow clients.
- Godot headless checks prove first-person entry, camera options, chat typing
  without combat input, transcript bounds, hide/mute and reconnect behavior.
- Regenerate and inspect a real rendered spectator tour with chat in the corner.
  Verify a watched pawn's server aim and vitals, not only that a camera moved.
- Keep the dedicated Jev watch harness passive, pinned by UUID and independent
  of normal audience camera controls. Run local/free evidence before any paid
  provider trial. No cloud or paid asset spend is needed for this feature.
