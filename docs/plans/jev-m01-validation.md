# Capped Jev campaign validation

**Status:** in flight, 2026-09-23. This is an automated M01 review increment
under the [full build order](../ROADMAP.md#full-build-order-2026-09-22).
The [campaign-aware brain](jev-campaign-decisions.md) and the
[bounded failure timeline](m01-failure-timeline.md) are already merged.

## Goal and boundary

Play one owned M01 Standard seed 67 run with the pinned Jev 1.13 decision
model through OpenRouter. Compare its authoritative terminal receipt, route,
survival and decision diagnostics with the existing free-rule evidence. A
second Severe seed 42 run is optional only if the first receipt is complete
and the cost gate remains healthy. Live scheduling means a shared seed is a
comparison input, not a deterministic outcome guarantee. This does not
replace fresh-player acceptance near 1.0 or change mission balance on one run.

## Spend gate

Nick authorized Jev validation through OpenRouter below $20 total. This
increment uses a tighter $0.25 run cap, $1.00 cumulative ledger cap and 600
call cap, enforced by `agents/brain`. The ignored ledger is
`.agents/spend/jev-campaign.jsonl`; no paid call runs in CI or at player
runtime by default. Stop on an uncertain reservation, malformed receipt,
provider refusal, key-limit issue, or a failed first attempt to price a call.
Do not use the native TypeSafe endpoint in this trial.

OpenRouter's [Jev 1.13 model page](https://openrouter.ai/typesafe/jev-1.13/api)
showed $0.042 per million input tokens and $0 output on 2026-09-23. The
calling key's remaining provider-side limit was checked through the existing
read-only `key` command before this plan. Recheck before a second paid run.
No key or provider balance belongs in committed evidence.

## Method and verification

1. Build the merged server and brain with `--release --locked`. Run a dry
   request to inspect the pinned model, estimate and question shape without
   a paid call. Inspect the ledger's initial total and unresolved entries.
2. Start an owned loopback `recall_notice` campaign server at seed 67 with
   Standard difficulty. Run `fragr-brain --provider openrouter` with the caps
   above, an explicit time limit and a bounded timeline path. Use the existing
   ignored `.env` integration; do not copy or print a credential.
3. Validate the brain's server participant, terminal Mission and matching
   final Record, ledger charge, action count, attempts, deaths, route and
   pickups. If the mission has not terminated by the time limit, record the
   incomplete state. Compare only like-for-like facts with the free run.
4. Record the actual call count, charged dollars and any provider failures in
   this plan. Keep raw provider responses and timelines under `.agents/`.
   Run the focused brain tests and full checks if code changes are needed.

Success is a validated, capped paid-play receipt and an evidence-backed next
controller action. A clear, one failure, or a refusal is useful evidence;
none alone proves campaign quality.
