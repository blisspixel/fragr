# GCP plan checklist

**Status:** plan-only, checked 2026-09-26. The former zero cost claim is
retired. Use [DURABLE-HOST.md](DURABLE-HOST.md) and the
[dedicated hosting plan](../../docs/plans/dedicated-server-udp-and-hosting.md)
for the intended image deployment.

## Before a cloud test or deployment

- [ ] Build and locally probe the versioned game image; record its digest.
- [ ] Replace the current Debian startup and placeholder server deployment
      with a reviewed container launch on COS or a justified equivalent.
- [ ] Leave experimental UDP closed until the measured, authenticated client
      and server path exists. The present game uses TCP 6767.
- [ ] Keep SSH behind IAP, use narrow service accounts and retrieve secrets at
      runtime. Never commit a key, state file or secret-bearing `.tfvars`.
- [ ] Remove or implement the Cloud Run adapter placeholder before enabling
      it. Require application authentication and a real private route.
- [ ] Check VM, disk, public IPv4, egress, Artifact Registry and any Cloud Run
      costs against the remaining $50 project cap and the applicable daily
      authorization. Set alerts and a timed teardown; alerts do not cap bills.
- [ ] Run `terraform fmt`, `terraform validate` and a reviewed `plan`. Record
      what the plan would create and how long it may bill.
- [ ] Obtain Nick's written approval for production cloud deployment before
      `terraform apply`.

Do not treat a free VM allowance as a free public server. Do not add a load
balancer, fleet, static IP, NAT or always-on Cloud Run instance for a single
friends match without a measured need and a new cost review.
