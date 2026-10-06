# Small VPS dedicated host

Use a small host with a public address when a home connection cannot accept a
router forward. The server remains one long-lived authoritative container on
TCP 6767. [Home LAN](HOME-LAN.md) is the $0 starting point and a complete
host, not a fallback. The [COS host](DURABLE-HOST.md) remains a plan-only GCP
option. A Terraform root for one popular small-VM network, plus AWS and Azure,
is planned in [server excellence](../../docs/plans/server-excellence.md) and
is not written. No VPS has been deployed or measured as part of this guide.

## Before creating a paid host

Compare the provider's current compute, disk, public IPv4 and egress prices
against the remaining project cap. Record an exact estimate and obtain Nick's
written approval before creating a billable instance. A small machine size is
a test candidate, not a ten-fighter capacity claim. Measure tick percentiles,
traffic and health with the intended roster before relying on it for a match.

The container image is the deployment unit. There is no published game image
to pull yet. For a bounded test, check out the reviewed source on the host and
build the same locked image used by local Compose and CI. A later published
digest can replace this build after its image and rollback path are reviewed.

## Start a bounded friends test

Install Docker with the Compose plugin using your host's supported packages.
From the repository checkout:

```bash
docker compose up --build -d
docker compose ps
curl -fsS http://127.0.0.1:6767/status
```

Wait for `healthy` in `docker compose ps` and `health.status: ok` in the
response. The image carries the server, bundled maps and legal notices. The
container runs unprivileged with a read-only root filesystem, and Compose
restarts it after a failure. Set `FRAGR_BOTS` and `FRAGR_MAP` through the
ignored root `.env` or the host environment. See [Home LAN](HOME-LAN.md) for
join-ticket and access-list configuration. Keep secrets out of the image,
checkout and shell history.

Allow inbound TCP 6767 only from the approved friends' addresses during this
test. Keep SSH limited to key-based operator access or the provider's private
management path. UDP is closed because the current game transport uses
WebSocket. The Godot Multiplayer page or `FRAGR_SERVER` connects to the host
address. No VPN is required for this path.

Direct `ws://` gameplay is plaintext, and today's shared join secret is not a
public player credential. An address allowlist and a healthy container do not
make stranger admission safe. A stranger-facing service still needs TLS,
server-side ticket distribution, abuse tests and a recovery exercise. See the
[hosting guide](../../docs/HOSTING.md) and
[transport plan](../../docs/TRANSPORT.md) for those open gates.

## Operate and stop

```bash
docker compose logs --tail=100 server
docker compose down
```

Check the provider bill and egress after the test, and record actual spend.
When load measurements justify a different host size, review its new estimate
before changing it. Cloud Terraform in this repository remains plan-only;
running Compose on a VPS does not apply it.
