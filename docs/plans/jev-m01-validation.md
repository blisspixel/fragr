# Capped Jev campaign validation

**Status:** proven in [#228](https://github.com/blisspixel/fragr/pull/228),
2026-09-23. This is an automated M01 review increment
under the [full build order](../ROADMAP.md#full-build-order-2026-09-22).
The [campaign-aware brain](jev-campaign-decisions.md) and the
[bounded failure timeline](m01-failure-timeline.md) are already merged.

## Goal and boundary

Play owned M01 Standard seed 67 and Severe seed 42 runs with the pinned Jev
1.13 decision model through OpenRouter. Compare their authoritative terminal
receipts, routes, survival and decision diagnostics with the existing free-rule
evidence. Live scheduling means a shared seed is a
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
   arena request to inspect the pinned model and price estimate without a
   paid call. The live `play` path supplies the campaign-specific questions.
   Inspect the ledger's initial total and unresolved entries.
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

## Results

Both trials used owned loopback M01 servers with zero rule bots and the live
campaign question path. The paid brain supplied decision intent; its local
controller submitted actions to the authoritative server. Each final Mission
had a matching terminal PlayerRecord. The trace format bounded the route to
zero dropped points in both trials.

| Difficulty, seed | Outcome | Combat and route | Decisions and cost |
|---|---|---|---|
| Standard, 67 | Complete on attempt 1, three continues left | 12 kills, zero deaths; 50 seconds from first active phase to departure; four damage events, four pickups, minimum sampled HP 40; 62 trace points | 128 remote decisions, 18 low-confidence decisions, zero provider failures; 147 billed calls, $0.005632872 |
| Severe, 42 | Complete on attempt 3, one continue left | 29 kills and two deaths across attempts; 125 seconds from briefing to departure; 16 damage events, 13 pickups, minimum sampled HP 25; 163 trace points | 350 remote decisions, 22 low-confidence decisions, zero provider failures; 372 billed calls, $0.014244552 |

The durable ledger settled all 519 calls at $0.019877424, with no unresolved
reservation or failed call. The provider-side usage increment matched the
ledger for each run after the counter settled. No top-up or overage was
enabled.

The Severe run's two deaths show that the continue path is exercised, not that
the difficulty is tuned. The free controller has both failed and cleared the
same seed, so neither outcome is a deterministic balance verdict. Both trials
were headless. A separate free-run first-person watch verified camera capture,
but these paid trials do not establish rendered Jev behavior or fresh-player
acceptance. Keep M01 in development and use the trace to inspect repeated
damage and supply timing before changing enemy counts. The next build-order
step is the campaign run file so a completed or failed attempt has durable,
validated ownership across process restarts.
