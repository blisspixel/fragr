# Durable cloud host

**Status:** plan-only, checked 2026-09-28. No GCP host or game image has been
deployed. Follow the [bounded COS plan](../../docs/plans/cos-container-host.md)
and [Terraform guide](../terraform/README.md).

## Image and identity

The Terraform draft consumes an existing private Artifact Registry Docker
repository and a published `fragr-server` manifest digest. The repository,
build, push and legal-notice check must be done and reviewed before a cloud
apply. A floating tag cannot select the deployed build.

The host uses a COS stable image, Docker and a startup script. It uses no
container startup agent, Debian package installer, or `scp` game binary.
The VM's service account receives repository-scoped Reader and secret-scoped
Secret Accessor. It has the `cloud-platform` OAuth scope required by Secret
Manager; IAM limits what it can read. Operator IAP IAM is separate.

Create a Secret Manager version with a single 16 to 256 byte ASCII token
containing letters, digits, underscore or hyphen. Pin its numeric version.
Terraform holds only the secret name and version, not its value. At boot the
host reads that version into root-only `/run/fragr` tmpfs and passes it
through Docker's env-file interface, because the current server reads
`FRAGR_JOIN_SECRET` from the environment. Root and Docker administrators on
the host can inspect the running environment. A missing or invalid secret
keeps the game container stopped. The launcher removes a stale env file at
each attempt and deletes a newly staged file if image pull fails. Its shell
parser expects the trusted Secret Manager API's documented `payload.data`
shape; an unexpected response fails closed.

## Network and cost

Default Terraform has no external IPv4 and no game firewall source ranges.
The subnet enables Private Google Access, which lets this internal-only VM
reach normal Artifact Registry and Secret Manager endpoints without Cloud
NAT. An approved public test would enable an ephemeral external IPv4 and
specify up to eight distinct canonical operator IPv4 /32 addresses. The VPC
then allows TCP 6767 from those sources; the COS startup installs a matching
host INPUT rule for each /32 for its
host-network Docker container. Test the actual ingress from an allowed
outside address. UDP cannot be enabled in this draft. SSH is IAP only.

This is still plain WebSocket. A CIDR and HMAC secret do not complete public
admission, TLS termination, ticket distribution, replay control or abuse
review. Do not advertise this as a public stranger server. A future
serverless ticket, list or status edge needs a real HTTP implementation and
an access contract; none is deployed by this Terraform.

An `e2-micro` Free Tier allowance does not establish ten-fighter capacity.
The VM, disk, Artifact Registry storage and egress may bill. An in-use
external IPv4 costs $0.005 per hour on a standard VM, even if game ingress
is closed ([Google VPC pricing](https://cloud.google.com/vpc/pricing#ipaddress),
checked 2026-09-28). Billing alerts notify but do not cap charges. Price the
exact approved runtime window and teardown before any apply.

## Boot and recovery probes after a future approved apply

1. Confirm the desired digest and numeric secret version in the reviewed
   Terraform plan, then inspect the instance's startup-script journal.
2. Through IAP SSH, check `systemctl status fragr-server.service`,
   `docker inspect fragr-server --format '{{json .State.Health}}'`, and
   `curl -fsS http://127.0.0.1:6767/status`. Require
   `health.status: ok` and the expected map/roster. Do not print the secret,
   metadata token, env file or Docker environment.
3. If public ingress was separately approved, probe `GET /status` and a
   complete WebSocket join from an allowed external /32, then confirm a
   blocked source cannot connect. Test IAP access and closed UDP.
4. Review journal and `docker logs fragr-server` on startup failure.
   Systemd retries a failed image pull or stopped container. Docker's
   health check reports degraded status, but an unhealthy container does
   not automatically restart solely because of that result.
5. Roll back by restoring the last known-good image digest and matching
   secret version in Terraform, review the replacement plan and its downtime
   and cost, then apply only with the relevant approval. Changing the
   startup script replaces the single host and its ephemeral address.

The current work can validate Terraform and inspect a rendered startup
script, but cannot prove first boot, Google API reachability, remote ingress
or rollback without an approved cloud test.

## Sources checked 2026-09-28

- [COS startup and Docker credentials](https://docs.cloud.google.com/container-optimized-os/docs/how-to/run-container-instance)
- [COS host firewall](https://docs.cloud.google.com/container-optimized-os/docs/how-to/firewall)
- [Private Google Access](https://docs.cloud.google.com/vpc/docs/configure-private-google-access)
- [Artifact Registry private route](https://docs.cloud.google.com/artifact-registry/docs/securing-with-vpc-sc)
- [Secret Manager access](https://docs.cloud.google.com/secret-manager/docs/access-secret-version)
- [Container startup agent migration](https://docs.cloud.google.com/compute/docs/containers/migrate-containers)
