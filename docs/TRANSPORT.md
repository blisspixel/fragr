# Transport and Networking

## Current: WebSocket JSON (Slice 1)

**Status:** Implemented
**Use case:** Loopback, agent play, spectator streams and current human play

### Details
- Protocol: WebSocket over TCP
- Format: JSON text messages
- Address: Server binds `0.0.0.0:6767` by default (loopback, LAN, or public host)
- Client: Loopback default, accepts `FRAGR_SERVER` env var for remote connections
- Tick rate: ~20 Hz server broadcast
- Multi-peer: Multiple spectators/players can connect to same match
- Pros: Simple, universal, easy to debug, works for all roles, multi-peer ready
- Limits: Ordered TCP delivery can stall newer updates after loss; JSON full-world snapshots consume more bytes than a compact, relevant-state format.

**Current playable path.** Spectators and agents share this transport with humans. The local pawn predicts and reconciles movement on the 20 Hz WebSocket path. The [continuous moving-combat probe](plans/websocket-moving-combat-probe.md) measured correction, fallback, cadence and payload on loopback. The [delayed-egress probe](plans/websocket-delayed-egress.md) passed nine 20-second Windows-to-WSL sessions with 0, 40 and 80 ms server-egress delay. Those sessions shared one physical machine and injected no loss or jitter. Competitive feel still needs a two-machine, unsteered human session. The earlier [Action-to-Ack baseline](plans/human-action-ack-baseline.md) samples server-selected Actions; its send-to-Ack interval is not general input latency or RTT.

**Local presentation increment, 2026-09-30.** Remote participant bodies now have
a bounded tick timeline with a 100 ms render buffer, coherent yaw/pitch and
hold-only stale fallback. Spectator eyes use the same transform time and chase
weights are frame independent. Local prediction takes precedence. Campaign
enemies and companions retain their existing phase/shot clock. This implements
participant transform interpolation; it does not implement lag compensation,
delay all combat facts or prove two-machine feel. Evidence and limitations are
in [the presentation plan](plans/remote-participant-presentation.md).

## Planned: measured UDP pilot

**Status:** Planned after a two-machine WebSocket baseline and transport comparison
**Use case:** Low-latency human FPS play, competitive matches

### Why test UDP?

For smooth human FPS, low input latency matters. The current WebSocket JSON path has:
- TCP head-of-line blocking (one dropped packet stalls the stream)
- JSON encoding overhead and full-world snapshot traffic

A suitable datagram transport can carry sequenced inputs and snapshots without
TCP head-of-line blocking. Binary encoding and selective reliability are
separate protocol choices. Client prediction and server reconciliation now run on
WebSocket. The client owns yaw, sends numbered actions at no more than 120 per
second, and replays bounded 20 Hz movement steps from authoritative Acks.

### Transport sequence

```
Godot human client
  local yaw and bounded movement prediction now
       |
       | WebSocket JSON actions, snapshots and acknowledgements (current)
       | optional datagram inputs and snapshots (only after pilot passes)
       v
Rust authoritative server
  20 Hz WebSocket match now; optional datagram socket later
       ^
       | WebSocket JSON remains the path for spectators and agents
Spectators and agent adapter
```

### Godot ↔ Rust UDP Options

| Option | Pros | Cons |
|--------|------|------|
| `PacketPeerUDP` plus a narrow protocol | Existing Godot and Tokio APIs | Must design authentication, replay defense, congestion control and reliability |
| QUIC | Maintained encrypted transport with datagrams and streams | Godot interoperability and certificate flow must be proven |
| ENet | Godot has an ENet peer | Rust interoperability and the existing wire integration must be proven |

**Recommendation:** complete the WebSocket baseline and local prediction first.
Then compare complete Godot-to-Rust input and snapshot loops under the same
conditions. Stage 7 of [`plans/buttery-controls.md`](plans/buttery-controls.md)
records the earlier 12-byte header proposal; validate its security and wire
requirements before treating it as a design. A bind or echo alone is not a
transport pass. Keep WebSocket for control, spectators and agents throughout.

Prediction and reconciliation already run on WebSocket. The [live step](plans/live-movement-step.md), [3D movement Ack](plans/movement-ack-v1.md) and [local pawn prediction](plans/local-pawn-prediction.md) define that path. The [delayed-egress receipt](plans/websocket-delayed-egress.md) is a controlled diagnostic, not a two-machine or symmetric network result. The transport spike follows a two-machine LAN comparison.

## Timeline

- **Now:** WebSocket JSON for everyone; client-owned yaw, movement Acks and bounded local prediction shipped in v0.58.0.
- **Before the pilot:** measure a two-machine WebSocket session, then complete interpolation and bounded lag compensation on that wire.
- **Pilot:** compare a full datagram path against the same WebSocket session. Move humans only if play feel, security, interoperability and reconnect evidence pass.

## References

- Godot 4.7 PacketPeerUDP: https://docs.godotengine.org/en/4.7/classes/class_packetpeerudp.html
- UDP congestion and datagram guidance: https://www.rfc-editor.org/info/rfc8085/
- Fast-Paced Multiplayer: https://www.gabrielgambetta.com/client-server-game-architecture.html
