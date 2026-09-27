# Transport and Networking

## Current: WebSocket JSON (Slice 1)

**Status:** Implemented  
**Use case:** Loopback, agent play, spectator streams, human play (network feel unmeasured)

### Details
- Protocol: WebSocket over TCP
- Format: JSON text messages
- Address: Server binds `0.0.0.0:6767` by default (loopback, LAN, or public host)
- Client: Loopback default, accepts `FRAGR_SERVER` env var for remote connections
- Tick rate: ~20 Hz server broadcast
- Multi-peer: Multiple spectators/players can connect to same match
- Pros: Simple, universal, easy to debug, works for all roles, multi-peer ready
- Limits: TCP loss can delay later messages; JSON snapshots consume bandwidth

**Current evidence:** WebSocket supports human, agent and spectator sessions in
the local test path. A two-machine human session with measured latency, jitter
and loss has not been recorded, so its competitive feel remains unproven.

## Planned: measured transport pilot

**Status:** after WebSocket prediction and a two-machine baseline
**Use case:** Low-latency human FPS play, competitive matches

### Why test another transport?

For smooth human FPS, low input latency matters. The current WebSocket JSON path has:
- TCP head-of-line blocking (one dropped packet stalls the stream)
- JSON encoding overhead and full-world snapshot traffic

A suitable datagram transport can carry sequenced inputs and snapshots without
TCP head-of-line blocking. Binary encoding and selective reliability are
separate protocol choices. Client prediction and server reconciliation work on
WebSocket and must be measured there first. The current client already owns yaw
and sends numbered actions at no more than 120 per second; the server returns
authoritative acknowledgements, but live prediction is not wired in.

### Transport sequence

```
Godot human client
  local yaw now; local prediction and reconciliation planned
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

Prediction and reconciliation do not wait for UDP: stages 1 to 3 of the buttery-controls plan land on WebSocket first.

## Timeline

- **Now:** WebSocket JSON for everyone; client-owned yaw and input acknowledgements have shipped.
- **Before the pilot:** measure a two-machine WebSocket session, then complete prediction, reconciliation, interpolation and bounded lag compensation on that wire.
- **Pilot:** compare a full datagram path against the same WebSocket session. Move humans only if play feel, security, interoperability and reconnect evidence pass.

## References

- Godot 4.7 PacketPeerUDP: https://docs.godotengine.org/en/4.7/classes/class_packetpeerudp.html
- UDP congestion and datagram guidance: https://www.rfc-editor.org/info/rfc8085/
- Fast-Paced Multiplayer: https://www.gabrielgambetta.com/client-server-game-architecture.html
