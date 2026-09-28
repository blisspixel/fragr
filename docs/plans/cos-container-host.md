# Plan-only COS container host

**Status:** implemented in draft PR #287, 2026-09-28. This is a Terraform and
operator-documentation change. It has not been applied to GCP. External spend
is $0.

## Goal

Replace the Debian installer placeholder with a reviewable, single-match
Container-Optimized OS boot path for the tested `fragr-server` image. Keep the
authoritative game on the same WebSocket protocol and port. Deploy only an
exact published image digest and a pinned join-secret version. Use one VM
identity with Artifact Registry Reader on one repository and Secret Accessor
on one secret. Open no game ingress by default.

The image repository and secret must already exist. This avoids creating a VM
before an image can be pushed and avoids putting secret bytes in Terraform
state. The startup service retrieves the secret at boot, refuses an absent or
malformed value, pulls the requested digest, and starts the image as UID 10001.
The existing image legal notices remain in the image.

## Scope

- COS stable image, Docker and systemd, with a startup script reapplied on
  every boot. No container startup agent or remote Docker installer.
- Narrow host INPUT allowances for TCP 6767, each matching one of at most
  eight reviewed canonical operator IPv4 /32s, only when external IPv4 is
  enabled. IAP SSH stays on its
  documented source range. UDP stays disabled until the transport pilot.
- A service that restarts after failure, a local `GET /status` probe and
  instructions for an external ingress probe.
- Digest change forces a single-host replacement; rollback restores the
  previous digest through a separately reviewed plan and apply.
- Cost and deployment docs updated to describe the actual state.

## Non-goals

No Terraform apply, image push, public-server readiness claim, Cloud Run
adapter, matchmaking, managed fleet, TLS terminator, ticket issuer or UDP
implementation. No ten-player cloud capacity claim. No paid call.

## Boundaries and failure behavior

The host starts no game container if the image digest is absent, the repository
cannot be read, Secret Manager access fails, or the secret value is invalid.
The game firewall has no public source range in the default plan. A configured
source range is only a narrow test allowance: plain WebSocket traffic and
current ticket distribution still need an end-to-end public admission design.
The server reads `FRAGR_JOIN_SECRET` from an environment variable, so the
host launcher must briefly stage it in root-only tmpfs for Docker's env file.
That is a current application boundary, not a general secret storage scheme.
The shell parser accepts the documented Secret Manager `payload.data` shape
from that trusted API and fails closed on missing or malformed data. Fixture
checks cover a formatted response and an absent payload; a live API response
still needs an approved host test. The launcher removes stale env files before
each attempt and clears a new one if image pull fails.

An external IPv4 is omitted by default. Private Google Access on the subnet
allows the internal-only VM to reach Artifact Registry and Secret Manager
without NAT. A later opt-in external IPv4 bills while the VM is running even
with ingress closed. VM, storage, Artifact Registry and egress can also bill.
Budget alerts do not stop charges. Any apply needs a current exact cost
estimate, remaining-cap check and Nick's written approval.

## Verification

Run `terraform fmt -check`, `terraform init -backend=false` and
`terraform validate` with the committed lock file. Check default and invalid
variable shapes with no cloud credentials where possible. Inspect rendered
startup script for a pinned digest, Secret Manager version, narrow firewall,
non-root Docker flags, restart behavior and health probe. Run shell syntax
checks. An actual image pull, first boot, external reachability, and rollback
remain unproven without an approved cloud deployment.

## Source check, 2026-09-28

- [COS container execution](https://docs.cloud.google.com/container-optimized-os/docs/how-to/run-container-instance):
  Docker credential helper for private Artifact Registry images and writable
  HOME needed in systemd.
- [COS firewall](https://docs.cloud.google.com/container-optimized-os/docs/how-to/firewall):
  host-network containers require an explicit INPUT rule as well as VPC rules.
- [Container startup agent migration](https://docs.cloud.google.com/compute/docs/containers/migrate-containers):
  use startup scripts or cloud-init, not container declarations.
- [Secret Manager access](https://docs.cloud.google.com/secret-manager/docs/access-secret-version):
  use a pinned version, cloud-platform scope and secret-scoped IAM.
- [Artifact Registry repository IAM](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam):
  a repository IAM member preserves other members.
- [Google provider releases](https://github.com/hashicorp/terraform-provider-google/releases):
  v8.4.0 was the latest published stable release checked 2026-09-28.
- [Terraform test mocking](https://developer.hashicorp.com/terraform/language/tests/mocking):
  mocked providers require Terraform 1.7.0 or newer.
- [Terraform test mocking](https://developer.hashicorp.com/terraform/language/tests/mocking)
  and [expected validation failures](https://developer.hashicorp.com/terraform/language/tests):
  plan tests can prove variable and lifecycle guards without cloud credentials.
- [VPC address pricing](https://cloud.google.com/vpc/pricing#ipaddress):
  an in-use public IPv4 address is billable on a standard VM.
- [Private Google Access](https://docs.cloud.google.com/vpc/docs/private-google-access)
  and [Artifact Registry private reachability](https://docs.cloud.google.com/artifact-registry/docs/securing-with-vpc-sc):
  an internal-only VM can reach Google APIs and Artifact Registry through
  the subnet's Private Google Access path.

## Handoff

The draft is based on 7814c37. No GCP resource, image pull or paid call was
made while preparing it.

- Terraform 1.16.4: `init -backend=false -upgrade -input=false` selected
  signed Google provider 8.4.0. `providers lock` recorded Windows, Linux
  and both macOS architecture checksums for the `~> 8.4.0` constraint.
  Subsequent
  `init -backend=false -lockfile=readonly -input=false`, `fmt -check`
  and `validate -no-color` passed. `git diff --check` passed.
- Terraform `templatefile` rendered the startup script with a dummy digest,
  pinned secret version and two example operator /32s. `bash -n` passed.
  The rendered host rules contained the same two /32s on TCP 6767 only.
- `terraform test` with a mocked Google provider passed eleven plan cases:
  closed default, two allowed operator /32s, alternate /0 spelling, a /1,
  complementary /1s, noncanonical host prefix and IPv4 text, more than
  eight addresses, duplicates, and mismatched public IPv4/source-range
  switches. No cloud credentials or API calls were used.
- Synthetic Secret Manager responses with formatted `payload.data`, a
  missing payload and malformed base64 exercised the exact extraction line.
  The rendered Docker health command accepted `health.status: ok` and
  rejected `degraded`. No real secret was used or printed.
- No `terraform plan` was run: it would require GCP credentials and a
  reviewed existing repository and published image. None were used. An actual pull,
  VM boot, IAP tunnel, external ingress, ten-fighter capacity and rollback
  remain unproven.

Independent static review found no remaining boot blocker after the narrow
/32 ingress guard was tested. Keep this plan in flight until the code is
integrated; cloud apply and its first-boot proof remain separate gates.
