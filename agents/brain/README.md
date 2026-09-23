# fragr-brain

A reference agent whose intent comes from a decision model and whose reflexes stay local. An agent in fragr is one participant on the wire, however it thinks: server-run rule bots, any MCP client through the adapter, a scripted client, or this one, which asks a decision model what to do a few times a second while a local controller keeps playing every tick. One agent can combine a language model, other ML, and a decision model; the server sees one fighter either way.

The brain is Jev, TypeSafe AI's decision model, reached either at TypeSafe's own endpoint or through OpenRouter. Jev does not generate text. It answers typed questions (a choice between named options, a yes-or-no probability, a score on an ordered scale) with calibrated confidence, in a few hundred milliseconds, for about four cents per million input tokens. That shape fits a shooter far better than a chat model: no prose to parse, no invalid actions to guard against, no warm-up.

The MCP door is unchanged. Any MCP client still drives a fighter through `agent-adapter`; this crate is a separate, optional client on the same wire protocol, and the two can be mixed inside one agent.

## Run it for free

```bash
# Terminal 1
cargo run -p fragr-server -- --bind 127.0.0.1:6767 --bots 3

# Terminal 2: local rules only, no key, no spend
cargo run -p fragr-brain -- play --name Brain-1 --max-seconds 120
```

`--provider local` is the default. The same loop runs, the same telemetry is built, and the same controller plays; only the decision comes from rules instead of a model. CI exercises this path in-process.

The local controller reads `MapInfo` for cover and walking routes, using the same
heightfield navigator as rule bots and playtest agents. It routes around walls and
up stairs, holds fire through cover, and clears route memory on map or life
changes. Search work is bounded and stays local; it does not add model calls.

For a rendered first-person developer watch, run `bash tools/qa_watch.sh` from
the repository root (Git Bash on Windows). It starts an owned local M01 server,
one free-rule brain pawn and a passive Godot spectator, then saves eight eye
frames and a paired UUID/tick/brain receipt under `.agents/watch/`. Set
`FRAGR_WATCH_SECONDS=180` for a longer M01 attempt. The wrapper uses no provider
key and stops only the processes it started. A short capture proves the live
view, not a mission clear.

## Run it with a brain

Put a key in `.env` at the repository root (gitignored) or in the environment:

```
typesafe=sk_...          # or TYPESAFE_API_KEY
openrouter=sk-or-...     # or OPENROUTER_API_KEY
```

Then pre-approve a cap. Nothing paid happens without one:

```bash
cargo run -p fragr-brain -- --provider typesafe --max-spend-usd 5 play --name Jev-1 --decision-hz 3
cargo run -p fragr-brain -- --provider openrouter --max-spend-usd 5 play --name Jev-2
```

Both providers send the same body: a `state` object, a `model`, and a `questions` map. TypeSafe gets `jev-1.13.0` at `https://api.typesafe.ai/v1/systemone`. OpenRouter gets `typesafe/jev-1.13` at `https://openrouter.ai/api/alpha/decisions` plus the app attribution headers pointing at this repository. Override the model with `--model`.

## Budget controls

Every paid path goes through one gate, in this order:

1. **Pre-approval.** `--max-spend-usd` defaults to zero. A paid provider with a zero cap refuses to start and says how to approve one.
2. **Estimate before send.** Each request is priced from its byte length (two characters per token, the ratio measured against OpenRouter's billed count, rounded up, plus overhead) at `--price-input-per-million` and `--price-output-per-million`, which default to Jev's list price. If the estimate would cross a cap, the call is not sent.
3. **Reserve before send, settle after return.** A synced pending receipt beside the ledger is created before the request leaves the process. Only one paid call across processes sharing that ledger can be in flight. Any failed response, or a successful response without provider billing evidence, leaves the receipt unresolved and blocks later calls until provider usage is reconciled. The provider's reported usage and cost replace the estimate after a fully evidenced return.
4. **Ledger on disk.** Completed calls and failures are synced as JSON lines to `.agents/spend/brain.jsonl`. Failed calls retain their pending receipt after the estimated charge is recorded. The total carries across runs. `--max-total-usd` re-reads the ledger under the exclusive pending reservation; `--max-calls` caps count regardless of price. A restart clears a leftover pending receipt only when its matching settled charge is already in the ledger. Paid `play`, `ask`, and library decisions refuse a missing ledger. `fragr-brain spend` shows ledger totals and any pending receipt requiring provider reconciliation.
5. **Fail open to rules.** A refused, failed, slow, or low-confidence decision hands the fighter to the local rules for that cycle. A cap refusal, a bad key or model id, or any unresolved paid request turns the brain off for the rest of the run, once, with a warning, so an uncertain bill cannot be followed by another call. Dead fighters and fighters outside an active round are never asked. The fighter never stops playing.
6. **Per-run ceiling.** `--max-spend-usd` above five dollars is refused outright; that ceiling is a constant in the code, so raising it is a reviewed change.
7. **Provider-side backstop.** For OpenRouter, create a key with its own lifetime dollar limit in the dashboard; `fragr-brain --provider openrouter key` shows the limit and what remains, and warns when the key has none. A token estimate is not a guarantee of final cost, so the provider limit backs up the local cap.

Measured on 2026-09-18 through OpenRouter: an arena call billed roughly 700 input tokens (the fixed question text dominates the small state). At the checked $0.042 per million input tokens, that is about $0.0000294 per call, $0.0053 per minute at three calls per second, or $0.32 per hour of continuous play. Actual usage and cost vary by state and are recorded from provider responses. A five dollar cap is roughly fifteen hours at that example rate, never a guarantee. Latency and win rates stay in local ledgers and reports under the provider agreement.

## What the brain is asked

The state is a small object of words, not numbers. TypeSafe's guidance for Jev is an object with descriptive names, comparisons done in code, and nothing unrelated to the questions, because Jev reads numbers as text and unrelated detail measurably lowers accuracy. So the bot buckets distances and health before asking:

```json
{
  "self":  {"health": "high", "armor": "none", "weapon": "flechette", "taking_damage": false, "score": "behind"},
  "enemy": {"present": true, "range": "mid", "health": "low", "weapon": "rail"},
  "pads":  {"health": "near", "armor": "none"},
  "clock": "ending_soon"
}
```

Range is close (under 10 units), mid (to 30), or far, matching the weapon ranges in the questions. A pad is near inside 12 units. The clock is ending_soon at 30 seconds. The human-readable four-line form still appears in logs and in the run summary.

The questions are fixed so estimates stay honest, and written the way TypeSafe recommends: short and atomic, each choice option saying what it is for and what belongs to a neighbour, each score level describing a situation rather than a degree.

- `stance`, a choice: `push_enemy`, `fall_back_heal`, `hold_angle`, `kite_distance`.
- `weapon`, a choice: `scatter`, `flechette`, `rail`.
- `danger`, a score over five situations from healthy and unbothered to low health under fire with no pad near. The bot takes the most likely level, never the interpolated expectation, because TypeSafe documents the score's numerical calibration as weak.

**Gating.** A choice is trusted when its top option leads the runner-up by at least `--margin-floor` (default 0.2), or when the provider's own `confidence` statistic reaches `--confidence-floor` (default 0.65). The margin is the primary test: on a four-way stance question the winning option often sits near 0.6 with a clear lead, and TypeSafe's own worked example calls a 0.60 versus 0.38 split "clear enough to act on" while reporting a confidence of 0.39. Rejected answers leave the stance to local rules for that cycle and count as `decisions_low_confidence` in the summary.

**Backoff.** Rate limits (429), overload (529), other server errors, and timeouts are never retried inside a cycle. Each one doubles the decision interval, up to sixteen times the base, and the first success restores it. The fighter plays on local rules in between. TypeSafe's published default limit is 1,200 requests per minute per key, which four to six brain fighters at three to five decisions per second would saturate, so keep the decision rate modest when fielding several.

**Model pinning.** The gate was tuned against Jev 1.13, so the defaults pin it: `jev-1.13.0` natively and `typesafe/jev-1.13` through OpenRouter. TypeSafe advises pinning once thresholds are tuned rather than riding the `jev-latest` alias.

Try one decision by hand, with or without sending. A JSON object is sent as an object; anything else goes as a plain string:

```bash
cargo run -p fragr-brain -- --provider openrouter ask --dry-run --state '{"self":{"health":"low","armor":"none","weapon":"flechette","taking_damage":true,"score":"even"},"enemy":{"present":true,"range":"close","health":"high","weapon":"scatter"},"pads":{"health":"near","armor":"none"},"clock":"plenty"}'
cargo run -p fragr-brain -- --provider openrouter --max-spend-usd 0.01 ask --state '{...}'
```

## What it reports

`play` prints a JSON summary when it leaves: snapshots seen, actions sent, decisions by source (remote, low confidence, failed, local, budget refusals), backoffs, decision round-trip statistics, frags, deaths, dollars this run, dollars in the ledger, the last plan, and the last state string. The summary is for your eyes; keep it out of public write-ups.

## Known limits

- Jev reads instructions literally, is weak at arithmetic and multi-step reasoning, and can be distracted by irrelevant state. The state is words only, kept tiny, and the questions are blunt on purpose.
- One request evaluates one state. Several fighters could share a request through field paths, but that adds exactly the unrelated detail TypeSafe warns about, so each fighter asks alone.
- TypeSafe's customer agreement forbids publishing benchmarks or performance figures about the service. Keep win rates out of the repository; the playtest harness reports stay under gitignored `.agents/`.
- OpenRouter accepts `typesafe/jev-1.13` (served as `typesafe/jev-1.13-20260917` on 2026-09-18) and the alias `~typesafe/jev-latest`; the plain `typesafe/jev-latest` does not exist there. The dated id is the default.
- No A2A surface yet. Team play between brains is a roadmap item.
