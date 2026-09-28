# Plan-only GCP container host

This directory describes one authoritative `fragr-server` container on
Container-Optimized OS. It has never been applied. Read
[the host plan](../../docs/plans/cos-container-host.md) and
[the cloud operator guide](../docs/DURABLE-HOST.md) before proposing an apply.
Any apply needs Nick's written approval and a current priced plan.

## Prerequisites for a future approved test

1. Create a private Docker repository in the chosen region and publish the
   locally tested Linux `fragr-server` image. Record its immutable sha256
   manifest digest. This Terraform consumes an existing repository; it does
   not publish or build an image.
2. Create an enabled Secret Manager version containing a single 16 to 256
   byte ASCII token using only letters, digits, underscore and hyphen. Pass
   its ID and numeric version, never its content, to Terraform. The same
   long-term HMAC secret must stay server-side. A public ticket issuer and TLS
   boundary are separate work.
3. Check the complete bill, remaining project allowance, billing alerts,
   approved runtime window and teardown. VM, disk, registry storage and
   egress can bill. Opting into public IPv4 adds its hourly charge.

## Local review commands

Use Terraform 1.7.0 or newer for the mocked provider tests. Terraform 1.16.4
was used for this draft's local checks.

```sh
terraform fmt -check
terraform init -backend=false -lockfile=readonly
terraform validate
terraform test
```

`terraform plan` requires authorized Google credentials and an existing
repository and secret. It must be reviewed before any apply. No plan or
validation command creates cloud resources. Never put secret bytes in a
`*.tfvars` file or Terraform state.

CI runs these checks with a mocked provider for the test cases. It has no GCP
credentials and never applies resources.

The default has no external IPv4 and no game ingress. Private Google Access
on the subnet gives the VM access to Google API endpoints for the image pull
and Secret Manager read without a Cloud NAT. To enable a bounded external
probe later, set `enable_external_ipv4=true` and a reviewed list of
`game_source_ranges` such as one operator IPv4 /32. Only up to eight
distinct canonical IPv4 /32 addresses are accepted; broader ranges are
rejected. Experimental UDP is deliberately blocked.

The COS startup script recreates the local systemd unit at each boot,
configures the built-in registry credential helper, reads the pinned secret
version, pulls the exact image digest and starts the non-root container. A
missing secret or image leaves the service stopped and retrying. The Docker
health check probes `GET /status`; systemd restarts a process that exits.
For details on first-boot probes, restart and rollback, see the operator guide.
