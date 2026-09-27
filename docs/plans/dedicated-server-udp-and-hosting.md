# Dedicated server, transport and hosting

**Status:** in flight, 2026-09-26. The local container host is implemented in
[PR #265](https://github.com/blisspixel/fragr/pull/265), which is open as a
draft. No cloud resource has been created and UDP is not implemented.
**Spend:** $0 for this slice. Nick set a $20 ceiling for today's combined
external costs, including asset APIs and a bounded GCP test if needed, still
subject to the project's $50 total cap. No cloud test is needed for this slice.

## Goal and order

Make a reliable dedicated match easy to run for friends, then improve network
feel and prove a public host before introducing fleet infrastructure. The
authoritative Rust server stays the source of truth for fighters, agents and
spectators. A container image is the portable hosting unit; local play remains
available without Docker.

This work supports the [full build order](../ROADMAP.md#full-build-order-2026-09-22).
It does not displace the M02 rescue or the next multiplayer mode. The existing
[transport decision](../TRANSPORT.md) puts prediction, reconciliation,
interpolation and bounded lag compensation on WebSocket before a measured UDP
trial. Change that order only with a recorded comparison and a matching update
to both documents.

## Current baseline

- `fragr-server` runs one 20 Hz authoritative match on TCP WebSocket port 6767.
  `GET /status` reports health and traffic. The server already has bounded
  sessions, inbound budgets, tickets, resume, bans and allow lists, and bounded
  spectator delivery. CLI and local launch share `server/src/run.rs`.
- The Godot client presents server state and sends discrete actions. The shared
  movement mirror has golden vectors, but live prediction is not wired in.
- The six-map mixed roster, 120-second soak and CPU benchmark are local
  evidence. They do not establish internet latency or a ten-fighter minimum on
  a small cloud instance.
- `infra/terraform` is plan-only. Its VM currently boots Debian 12 and runs a
  remote Docker installer, then leaves a placeholder for server deployment.
  Its Cloud Run adapter runs a placeholder image. The `$0.00` cost output is
  inaccurate for a continuously used public IPv4 address.

## Hosting architecture

| Layer | Near-term home | Reason |
|---|---|---|
| Match authority | One `fragr-server` process or container | Needs a continuous tick and a public game socket. |
| Local friend host | Docker Compose on a host or the existing binary | Same server behavior, no cloud cost. |
| Optional HTTP edge | Cloud Run only when ticket, list or status APIs exist | Request-driven HTTP fits; it does not accept public UDP gameplay. |
| Cloud match host | Container image on a thin COS or comparable host, after approval | Reuses the tested image and exposes the game port. |
| Fleet | Agones on GKE after several matches need orchestration | Avoids cluster cost and operations for one friends match. |

The present Cloud Run adapter stub is not deployable: an HTTP container, private
route and application authentication must be designed and tested before it is
enabled. Do not create a ticket issuer or server list with no consumer or access
contract. A host may use TLS for public WebSocket, but TLS termination and
ticket distribution need an end-to-end design before public admission is called
secure. The current Godot client can mint an HMAC join ticket only when it knows
`FRAGR_JOIN_SECRET`; distributing that long-term secret to public clients lets
them mint their own tickets. An issuer must keep the secret server-side and
define who may request a ticket. Existing tickets can also be replayed during
their validity window. Docker alone does not make an open internet server safe.

Google stopped new `gce-container-declaration` and konlet deployments on
2026-07-31; existing deployments have support through 2027-07-31. A future COS
host should start the image through a startup script or cloud-init, with a
repository-scoped Artifact Registry Reader identity. Keep image version,
restart behavior, secret retrieval and rollback explicit. Do not use a floating
image tag for an applied host.

## Transport decision

WebSocket remains the shipping path. First measure round-trip latency, jitter,
input age, snapshot delivery, tick cost and per-client bytes in a real
two-machine session. Build the local prediction and reconciliation loop on the
existing action sequence and authoritative acknowledgment, then measure
correction distance and play feel under controlled delay and loss. Compare the
predicted WebSocket baseline against a bounded UDP or QUIC pilot under the same
conditions. The client currently paces Actions to at most 120 per second, but
its 3D movement mirror is not yet live prediction.

An early UDP bind and echo proves only socket plumbing. It does not prove
responsive play, client interoperability or public safety. A token sent over
plain `ws://` is not a confidentiality or integrity scheme. Any public UDP
path needs authenticated packets, replay rejection, a session lifetime,
congestion and rate control, a datagram size below path MTU, and a Godot client
that exercises the entire input and snapshot loop. Critical events may remain
on a reliable channel. Evaluate Quinn or another maintained protocol against
the real Godot client before accepting the cost of custom reliability.

## Implementation rungs

### 1. Local container host, this slice

Add a multi-stage Dockerfile using the locked Rust workspace, a small runtime
image and a non-root user. Keep the server binary, bundled map data and legal
notices in the image. Add `.dockerignore`, a Compose service with a health probe against
`GET /status`, and a friend-host guide for LAN and an optional router forward.
Keep ticket configuration and access files explicit; do not bake credentials or
private lists into the image. The default match remains open on the local
network and the shipped WebSocket protocol stays unchanged.

**Acceptance:** `docker compose config -q`, image build, an actual healthy
container, a live `/status` reply, and a WebSocket match smoke. Verify the
server exits cleanly and can restart. No UDP port is published until it works.

### 2. Measure and improve control feel on the present wire

Record a two-machine WebSocket baseline first, including action-to-ack time,
snapshot age, per-client traffic and tick percentiles. The current local soak
measured 50,457 outgoing bytes per client per second with four bots, four agents
and two spectators; the 20 KB/s target in `buttery-controls.md` has not been
met. Use the existing movement mirror and action acknowledgment to predict only
the local body. Reconcile unacknowledged inputs, interpolate other actors, and
add a bounded hitscan history when measurements justify it. Keep every outcome
server-owned. Test stairs, jumps, death, resume, spectators and campaign gates,
then record inspected play at controlled latency and loss. Never infer human
feel from a headless pass.

**Acceptance:** golden 3D movement vectors on both sides, replayable delay and
loss tests, a before-and-after table for latency, snapshot age, traffic and
correction distance, and a two-machine human session. A local CPU benchmark or
soak alone does not prove the cloud host class.

### 3. Measured transport pilot

Write the wire and threat model before adding UDP. Prototype one complete
client/server input and snapshot path behind a flag. Compare it with WebSocket
under the same load and network impairment. Decide whether a maintained QUIC
stack is viable with Godot or whether a narrower UDP channel is justified.
Keep WebSocket compatibility until the new path has equal gameplay and
reconnect evidence. Do not publish a UDP firewall rule as a feature claim.

### 4. Capacity and public-host proof

Measure ten fighters plus bounded spectators on the intended host class using
tick percentiles, traffic and dropped updates. Add relevance filtering when
measurements show full broadcasts waste budget. Team assignment already lives
in `server/src/rules.rs`; extend that one seam when objective modes require
it. Prove LAN first, then a public week with ticket, TLS, abuse and recovery
tests. A cloud machine size is selected from measurements, not from its free
tier label.

### 5. Plan-only cloud image deployment

After the local image is proven, replace the placeholder VM startup with a
versioned container image on COS or a justified alternative. Design Artifact
Registry, least-privilege pull, Secret Manager, restart, rollback and health
checks. Add HTTP edge services only for implemented APIs. Run Terraform format
and validation, inspect the plan and cost estimate, and retain the no-apply
gate. Agones stays a later fleet decision.

## Cost and safety gates

Local image builds, tests and LAN play cost $0 externally. No paid asset
generation or GCP test is needed for this slice. Before an ElevenLabs or
Higgsfield call today, verify quota and per-call price, set an explicit cap,
and record the actual charge under the existing asset manifests and ledger.
A GCP test today is within Nick's authorization only when a concrete setup is
needed and its projected running and egress costs fit the remaining $20 daily
ceiling and $50 project cap. No production deployment is part of this slice.
Never enable top-ups or overages.

GCP alerts-only budgets notify and do not cap charges. Google's preview spend
cap budgets cover selected services such as Cloud Run, but do not stop ongoing
Compute Engine, storage, public address or egress charges. The Terraform cost
text must state that an in-use public IPv4 address and game traffic can bill
even when the VM is eligible for Always Free. This round made no paid call or
cloud apply; external spend remains $0.

## Research checked 2026-09-27

- [Docker build practices](https://docs.docker.com/build/building/best-practices/):
  multi-stage builds, a small context, non-root runtime and tested images.
- [Cloud Run container contract](https://docs.cloud.google.com/run/docs/container-contract/)
  and [WebSocket timeouts](https://docs.cloud.google.com/run/docs/triggering/websockets):
  HTTP request service, finite WebSocket lifetime, no public UDP game port.
- [Container startup agent shutdown](https://docs.cloud.google.com/compute/docs/containers/prepare-for-container-agent-shutdown)
  and [COS container launch](https://docs.cloud.google.com/container-optimized-os/docs/how-to/run-container-instance).
- [GCP free features](https://docs.cloud.google.com/free/docs/free-cloud-features),
  [network prices](https://cloud.google.com/vpc/network-pricing),
  [alerts-only budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets)
  and [preview service spend caps](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps).
- [Godot PacketPeerUDP](https://docs.godotengine.org/en/4.7/classes/class_packetpeerudp.html)
  warns that its connected UDP socket does not authenticate peers.
  [RFC 8085](https://www.rfc-editor.org/rfc/rfc8085.html) covers datagram
  congestion control and fragmentation.

## First slice progress, 2026-09-26

The local dedicated host now has a Dockerfile, a narrow build context and a
Compose service. The image built on Docker 29.8.0 with the verified Rust
1.98.1 builder. It runs as UID 10001 with a read-only root filesystem and
carries fragr's license plus notices for 94 linked Linux crates. Compose
reported `healthy`, and `/status` showed an active Arena Duel match with four
rule bots. A ten-second local-rules agent joined through the published
WebSocket port, received 200 snapshots and sent 199 actions; the run made no
remote decision or external API charge. A Compose restart returned to healthy,
then the container and network were stopped cleanly.

The plan-only Terraform draft now leaves UDP closed by default. Its cost
output no longer claims `$0.00`, and the hosting guide identifies the Cloud
Run adapter as an undeployable placeholder. Terraform 1.16.4 in Docker passed
`fmt -check` and `validate`; no plan or apply was run. The CI container job
builds the image, checks legal notices and runtime identity, and probes a live
Compose server. `actionlint` passed on that workflow locally. The first hosted
CI run for PR #265 passed all seven jobs: test, container, Godot, soak, audit,
Windows portability and macOS portability. The branch remains unmerged.

Local workspace checks passed: formatting, Clippy with denied warnings,
workspace tests, the deterministic 16-bot benchmark, `cargo deny` license,
ban and source gates, release build, all four standard match playtests,
the Godot headless checker, all ten verifier fault-injection scenarios, and
unfiltered coverage at 93.58 percent. Logs are
under `.agents/verification/container-hosting/`. The final image was built and
probed through Compose. The Docker build and agent smoke were run directly;
they are not a public-network or ten-fighter capacity measurement. No paid
asset call or cloud resource was made in this slice.

The six-map mixed roster passed with 2, 6, 6, 8, 12 and 16 agents. The
120-second rotating-map soak passed with four rule bots, four agents and two
spectators. These are local machine results, not a ten-fighter capacity claim
for an `e2-micro` or an internet session.

| Check | Measured result |
|---|---|
| 16-agent roster on map 6 | 44.6 seconds, 57 frags, 3,521 bytes per snapshot, no spawn deaths |
| 120-second rotating-map soak | 20.00 Hz, lifetime tick p99 0.59 ms, maximum 12.15 ms |
| Same soak traffic and memory | 50,457 outgoing and 2,408 incoming bytes per client per second; RSS 37.5 to 38.4 MiB |

The next gameplay sprints remain the mode-chip presentation and a human team
round, followed by capture the flag, and level 2's rescue, Crawlers and run
carry. Prediction measurement remains ahead of the UDP pilot. Keep this plan
in flight for the remaining transport and cloud rungs; mark the local host
shipped only after PR #265 merges.
