# infra (GCP)

Native IaC to run the fragr Rust **authoritative game server** on GCP cheaply, with room to scale.

## Product intent

- **Run your own server** (home LAN, cheap VPS, or GCP) without requiring Tailscale for strangers and agents. See [`docs/HOME-LAN.md`](docs/HOME-LAN.md) and [`docs/CHEAP-VPS.md`](docs/CHEAP-VPS.md). The local Compose path uses the same dedicated server binary.
- This folder is the **cloud path**: Terraform to stand up a billable deployment after Nick approves the exact spend and deployment.
- LAN is an optional buddy path. Tailscale Personal is private/dev smoke only, not the multiplayer front door.

## Status

Plan / draft only. **Do not `terraform apply` without written approval from Nick.** Default stops at `fmt` / `validate` / `plan`. Terraform now describes a COS container host with a pinned Artifact Registry image digest and a pinned Secret Manager version, but no image has been published and no GCP resource has been created. The [COS host plan](../docs/plans/cos-container-host.md) records its acceptance limits.

## Low-cost cloud draft

Until Nick explicitly accepts a priced deployment:

1. **Core tick server:** Always Free eligible **`e2-micro` GCE** in **`us-west1` / `us-central1` / `us-east1` only**.
2. **No external IPv4 by default.** Private Google Access lets the internal-only host pull its image and read the pinned secret. Opting into an ephemeral public IPv4 for a reviewed test costs $0.005 per in-use hour on a standard VM ([Google VPC pricing](https://cloud.google.com/vpc/pricing#ipaddress), checked 2026-09-28), even if game ingress is closed. Tailscale is optional private testing only.
3. **Tight firewall:** TCP 6767 has no source range by default. A bounded test may allow up to eight canonical operator IPv4 /32 addresses, with matching COS host INPUT rules. UDP remains blocked because the transport is not implemented. **SSH via IAP only**, no world SSH.
4. **HTTP agent-adapter:** no deployable Cloud Run resource is included. A real, authenticated HTTP service can be designed later. It is not the raw game socket.
5. **Never** put authoritative tick on Cloud Run/Functions as a free UDP front door (no inbound UDP). Slice 1 is WebSocket today; still prefer **GCE for long-lived authority**. The same rule covers a later central service: the sim is a long-lived process you can also run yourself. Serverless is for a status page, a later ticket issuer, and a server list. It is not a stand-in for the 20 Hz server. The first join ticket is an HMAC the host and the joining client share through `FRAGR_JOIN_SECRET`. A later issuer can mint that same ticket without copying the secret onto every player. Watchers are the scale. The fight stays a bounded mix of humans and agents.

## Identity and secrets (required before modules)

- The VM service account receives Artifact Registry Reader on one preexisting repository and Secret Accessor on one preexisting secret. No project-wide log or metric writer role is granted.
- Secret bytes live in Secret Manager, not Terraform variables, metadata, images or committed state. The host stages the secret in root-only tmpfs for the existing server environment-variable interface.
- Any future Cloud Run service needs its own application authentication and private route; this Terraform creates none.
- At Nick's spend gate: review a cost estimate, budget alert and billing export. A budget alert does not stop charges. The North America Free Tier outbound allowance is about 1 GB a month and can be exhausted quickly by real players.
- No GKE "free cluster" as fake free compute. No Private Service Connect endpoints on day zero.

## Block before apply (unless Nick accepts paid PoC)

- Any load balancer / `forwarding_rule` (~$0.025/h class)
- Unused reserved static IPv4
- Wrong region/machine or Cloud Run `min_instances > 0`
- MIG / second VM eating Free Tier hours
- Verbose flow logs / NAT/VPN "for cleanliness"

## Layout (draft)

```text
infra/
  README.md           # this contract
  docs/
    HOME-LAN.md       # home box: LAN + optional public port-forward (no Tailscale-required)
    CHEAP-VPS.md      # generic cheap VM public join (no Tailscale-required)
    ZERO-COST.md      # GCP plan checklist; former zero-cost premise retired
    DURABLE-HOST.md   # GCP container host design and cost gates
  terraform/          # plan-only COS container host, no image or cloud apply
```

## Spend gate

Hard project cap $50 unless Nick raises it. Nick authorized up to $20 in combined external charges on 2026-09-26 for build work, including a bounded GCP test if needed. Price the exact test and keep usage under both caps. This plan-only COS change makes no paid call. Its image repository, image digest and secret version are prerequisites, not resources created by this draft.
