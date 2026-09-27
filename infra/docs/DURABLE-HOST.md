# Durable cloud host

**Status:** design only, checked 2026-09-26. No GCP host has been deployed.
The current Terraform VM and Cloud Run adapter are placeholders, not a playable
cloud deployment. Follow the [dedicated hosting plan](../../docs/plans/dedicated-server-udp-and-hosting.md)
for the implementation and acceptance gates.

## Deployable unit

Build and test the same `fragr-server` image used by local Compose. For GCP,
store an immutable image digest in Artifact Registry and run it on a small
Container-Optimized OS host through a startup script or cloud-init. Configure
automatic restart, health checks, least-privilege image pull and a documented
rollback. Retrieve secrets at runtime; keep them out of the image, instance
metadata text, Terraform state and command arguments.

Do not use `gce-container-declaration` or the container startup agent: Google
stopped new deployments through that path on 2026-07-31. Do not make a Debian
host maintained by `scp` the default deployment model.

The authoritative tick stays in the container. Cloud Run may later serve
implemented HTTP ticket, status or discovery APIs, but cannot expose the public
UDP game socket. No Cloud Run API exists for fragr yet.

## Public network

- Open **TCP 6767** for the current WebSocket game only after public admission,
  TLS, abuse limits and recovery have been tested. UDP 6767 remains closed until
  an authenticated client/server transport passes its own review.
- Permit SSH through IAP only. No world-accessible SSH, broad admin port or
  public Cloud Run adapter placeholder.
- Tailscale may help private operator tests. Public friends should be able to
  use the documented address without it.
- Test the intended host class with at least ten fighters and bounded
  spectators before claiming capacity. An `e2-micro` Free Tier label does not
  establish game performance.

## Spend decision

The project's external spend cap is $50 total. Nick authorized at most $20
combined external charges for 2026-09-26 build work, including a bounded GCP
test if one is needed. No GCP test is needed for the local container slice.
Before a cloud apply, price the exact configuration and exposure window, check
remaining allowance, and obtain approval for a production deployment.

An Always Free eligible VM does not make a public host free. An in-use external
IPv4 address bills after the applicable free hour, and egress can bill after
the applicable allowance. A billing budget sends alerts; it does not stop a
running host. Inspect the current [GCP Free Tier](https://docs.cloud.google.com/free/docs/free-cloud-features),
[network prices](https://cloud.google.com/vpc/network-pricing) and
[budget behavior](https://docs.cloud.google.com/billing/docs/how-to/budgets)
before choosing a machine, address or test duration.
