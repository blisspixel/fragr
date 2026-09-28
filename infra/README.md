# infra (GCP)

Native IaC to run the fragr Rust **authoritative game server** on GCP cheaply, with room to scale.

## Product intent

- **Run your own server** (home LAN, cheap VPS, or GCP) without requiring Tailscale for strangers and agents. See [`docs/HOME-LAN.md`](docs/HOME-LAN.md) and [`docs/CHEAP-VPS.md`](docs/CHEAP-VPS.md). The local Compose path uses the same dedicated server binary.
- This folder is the **cloud path**: Terraform to stand up a billable deployment after Nick approves the exact spend and deployment.
- LAN is an optional buddy path. Tailscale Personal is private/dev smoke only, not the multiplayer front door.

## Status

Plan / draft only. **Do not `terraform apply` without written approval from Nick.** Default stops at `fmt` / `validate` / `plan`. The current Terraform still boots a Debian VM and leaves game deployment as a placeholder. The [dedicated hosting plan](../docs/plans/dedicated-server-udp-and-hosting.md) moves the deployable unit to the tested container image in a later sprint.

## Low-cost cloud draft

Until Nick explicitly accepts a priced deployment:

1. **Core tick server:** Always Free eligible **`e2-micro` GCE** in **`us-west1` / `us-central1` / `us-east1` only**.
2. **Ephemeral external IP** (no orphan reserved static IPv4). An in-use public IPv4 address is billed separately even on an Always Free eligible VM, currently $0.005 per hour for a standard VM ([Google VPC pricing](https://cloud.google.com/vpc/pricing#ipaddress), checked 2026-09-28). The current service uses **TCP 6767**; the Terraform UDP firewall is reserved for an unbuilt, measured transport and must stay closed on any real deployment until that path is ready. Tailscale is optional private testing only.
3. **Tight firewall:** game port(s) + **SSH via IAP only** (no world SSH). A future COS host also needs a narrow host firewall allowance and an end-to-end ingress probe, in addition to VPC rules.
4. **HTTP agent-adapter (optional):** the present Cloud Run resource is a placeholder image without the private route or application authentication. Do not enable it for deployment. An implemented HTTP service could use **`min_instances=0`** later. It is not the raw game socket.
5. **Never** put authoritative tick on Cloud Run/Functions as a free UDP front door (no inbound UDP). Slice 1 is WebSocket today; still prefer **GCE for long-lived authority**. The same rule covers a later central service: the sim is a long-lived process you can also run yourself. Serverless is for a status page, a later ticket issuer, and a server list. It is not a stand-in for the 20 Hz server. The first join ticket is an HMAC the host and the joining client share through `FRAGR_JOIN_SECRET`. A later issuer can mint that same ticket without copying the secret onto every player. Watchers are the scale. The fight stays a bounded mix of humans and agents.

## Identity and secrets (required before modules)

- Separate least-privilege service accounts: adapter SA is not the VM SA.
- Secrets in Secret Manager only. Never bake into images or commit `terraform.tfstate` / secret-bearing `.tfvars`.
- Cloud Run: no `allUsers` invoker unless Nick explicitly ACKs. Adapter to game via private IP plus app auth (HMAC / mTLS / token). Open RFC1918 alone is not enough.
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
  terraform/          # draft modules; not yet a deployable game host
```

## Spend gate

Hard project cap $50 unless Nick raises it. Nick authorized up to $20 in combined external charges on 2026-09-26 for build work, including a bounded GCP test if needed. Price the exact test and keep usage under both caps. No cloud test is needed for the local container slice, and the current Terraform still lacks a deployable game image.
