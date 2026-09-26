# Plan: a free local decision model for the brain agent

**Status:** implemented (branch `feat/brain-local-openjev`, local evidence below)
**Spend:** $0. No key, no ledger entry, no cap. Weights are pulled by the user into Ollama's own store and are never committed.

## Goal

Let `fragr-brain` take its intent from an open-weights decision model running on the player's own machine, at no cost, through the same loop, latency budget and local-rules fallback the paid Jev path uses. Two providers:

- `--provider ollama` asks APUS-OpenJev-v1-4B through a local Ollama server.
- `--provider openjev` posts the TypeSafe `systemone` body to an openjev server the user runs themselves.

`--provider local` keeps its meaning (free local rules, the default). The new providers are named after what they talk to so the default never reaches for a model.

## Non-goals

- Bundling, downloading or defaulting to any weights. The user pulls them.
- A Python runtime. APUS ships a Python reference runtime; fragr talks to Ollama's HTTP API instead.
- Calibrated confidence from APUS. Its letter probabilities are relative preferences, so the answers carry no `confidence` and only the margin gate can accept them.
- Beating local rules. This rung makes the model reachable and measured; tuning the questions for it is later work.

## Models (checked 2026-09-26 on Hugging Face)

| | APUS-OpenJev-v1-4B | openjev/openjev |
|---|---|---|
| License | Apache 2.0 (from Qwen/Qwen3.5-4B) | CC BY-NC 4.0, non-commercial only (helper code Apache 2.0) |
| Revision | GGUF repo `7389d774` (2026-09-23), converted from source `65797c526c27` | `0b6bb6e5` (2026-09-24) |
| File used | `APUS-OpenJev-v1-4B-Q8_0.gguf`, 4.2 GiB, SHA-256 `5e57075a169a76de5150f5c5defd805525ce4df86ae8865f70f128e15e57416c` (matches the repository's `SHA256SUMS`) | none; about 54 GB at 16-bit, not run here |
| Serving | Ollama, llama.cpp or LM Studio | vLLM plus the Python `helper/shim.py` on port 3000 |
| Contract | 2 to 16 candidates labelled A to P; the answer is the next-token distribution over those letters | `POST /v1/systemone` with `state` and typed `questions`, the hosted Jev shape |

APUS facts that shaped the code, all from its model card, `RUNTIME.md`, `openjev_contracts.py` and `examples/openjev_local.py`:

- The prompt is `Shared state:\n{state}\n\n{task}\nReturn only the selected letter: A, B, C.\nAnswer:` where `{task}` is `json.dumps({"primitive", "instructions", "criteria": [{"label", "description"}]}, ensure_ascii=False, sort_keys=True)`. fragr renders it byte for byte (Python separators, sorted keys) and a unit test pins the card's own example.
- It is wrapped in the trained no-thinking turn (`<|im_start|>user ... <|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n`) and sent with `"raw": true`, because Ollama renders this architecture with its built-in Qwen3.5 renderer and opens a thinking block otherwise (the card measured 49/80 matching labels with thinking left on). `"think": false` is sent as well.
- Ollama returns at most 20 `top_logprobs` per position. A letter missing from them is given the lowest returned log probability, an upper bound, which can only shrink the margin the gate reads.
- `score_level` judges one proposition and is not an ordinal scale, so fragr asks its danger score as a `choice` over the five levels and reports the expectation and the argmax, as it does for Jev.
- `noul` uses the canonical yes and no candidates; fragr's yes and no descriptions go into the instructions.
- Choice candidates are described as `id: text` because the model sees only descriptions and the state names weapons and stances by id.

Ollama facts, checked against `docs/openapi.yaml` on `main` on 2026-09-26: `/api/generate` takes `raw`, `think`, `logprobs`, `top_logprobs` and `options`, and returns `logprobs[].top_logprobs[]` with `token` and `logprob`. The installed Ollama is 0.34.2; the newest release is 0.34.4 (2026-09-23), not installed for this work.

## Shape

- `agents/brain/src/local_model.rs`: loopback check, the candidate mapping, prompt rendering, the Ollama and systemone requests, strict reply parsing and answer validation, and one latency budget for the whole decision.
- `provider.rs`: `Provider::Ollama` and `Provider::OpenJev` (not paid, no key), a per-request timeout, an `Error::Timeout` class, a 1 MiB response bound for every provider, and `HttpTransport::local` with redirects and environment proxies off.
- `bot.rs`: one `Asker` routes a decision to the free path or through the spend gate. The summary gains `timeouts`, `fallbacks`, `p50_ms`, `p95_ms`, `elapsed_seconds` and `decisions_per_second`.
- `main.rs`: `--model-url`, `--allow-remote-model`, an Ollama warmup before `play` that names `ollama pull` when the model is missing, and `ask` (with `--dry-run`) for both local providers.

## Safety and failure policy

- **Loopback only.** `localhost`, 127.0.0.0/8 and `::1` pass; any other host needs `--allow-remote-model`. Credentials, queries and fragments in the URL are refused. The local transport never follows a redirect.
- **Untrusted replies.** A reply over 64 KiB, a selected token that is not an offered letter, a log probability above zero or not finite, a count of scored positions other than one, an unoffered choice, a probability outside [0, 1], a distribution that does not sum to one, a score outside its levels, a type that does not match its question, or a missing answer from a systemone server is `Malformed`. The server's own id, model and billing fields are dropped.
- **One latency budget.** `--timeout-ms` bounds the whole decision, every question included. Each request gets the time left; no request is sent once it is spent; a late answer is a timeout.
- **Same fallback as the paid path.** Timeouts and 5xx back off (doubling the interval up to sixteen times), three unreadable answers in a row or a 4xx turn the model off for the run, and local rules play every cycle the model does not answer.
- **No spend.** The free path never reserves, estimates or records a charge.

## Verification

Fake transports only in CI, in `local_model.rs`, `provider.rs`, `bot.rs` and `main.rs`: the contract prompt, question mapping (including a campaign weapon question with one carried weapon, which is skipped), letter distributions, ten malformed Ollama shapes, twelve malformed systemone shapes, the whole-decision timeout, loopback enforcement, warmup errors, a live in-process match on the free path with an empty ledger, a slow model that times out and backs off, and unreadable answers that switch the model off. Real loopback sockets check the local transport's timeout, response bound and refusal to follow a redirect.

## Local measurement (2026-09-26)

Hardware and runtime: AMD Ryzen 7 7840U (8 cores, 16 threads), Radeon 780M integrated graphics (Ollama reports the model 100% on GPU through Vulkan), 61.8 GB RAM, Windows 11 Pro 10.0.26200, Ollama 0.34.2. Model: the Q8_0 file above, created in Ollama as `apus-openjev-v1-4b:q8_0` from the published Modelfile (`ollama pull hf.co/apus-ailab/APUS-OpenJev-v1-4B-GGUF:Q8_0` failed on 0.34.2 with "blocked redirect to a different host" at the Hugging Face CDN; the direct download and `ollama create` worked). Game: `fragr-server --bind 127.0.0.1:6790 --bots 3`, arena, one fresh server per run, one `fragr-brain play` fighter for 60 seconds at `--decision-hz 1`.

| Run | Budget | Model answers | Answers per second | p50 | p95 | Timeouts | Fallbacks | Kills | Deaths |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Local rules | none | 0 (56 rule cycles) | 0 | | | 0 | 0 | 10 | 1 |
| APUS 4B Q8_0 | 20 s | 4, all trusted | 0.06 | 12,361 ms | 12,908 ms | 0 | 0 | 6 | 2 |
| APUS 4B Q8_0 | 2 s (default) | 0 of 5 | 0 | 2,012 ms | 2,017 ms | 5 | 5 | 4 | 1 |

Answers per second divides answers by elapsed wall time, which includes up to five seconds waiting for the last in-flight decision. One run each against rule bots is not an outcome comparison; the kill counts are recorded, not claimed.

Where the time goes, from Ollama's own timings for one arena decision on the same machine:

| Question | Prompt tokens | Prompt evaluation | Request total |
|---|---:|---:|---:|
| danger (five levels) | 239 | 2,275 ms | 4,232 ms |
| stance (four options) | 326 | 2,740 ms | 4,632 ms |
| weapon (three options) | 213 | 2,502 ms | 4,092 ms |

No prompt tokens were reused from the cache between the three questions even though they share the state prefix. On this integrated GPU each request also carries about 1.8 seconds beyond prompt evaluation. A separate check of the card's 118-token example forced onto the CPU (`num_gpu` 0) took 2.7 to 3.1 seconds uncached against 3.5 to 3.7 seconds on the GPU, and 0.14 seconds when the whole prompt was cached. `fragr-brain ask` answered the free example state in 12.1 and 10.0 seconds, choosing `fall_back_heal` at 0.998 for a low-health fighter with a near health pad.

The answers are sensible and every reply passed validation. On this laptop the model is two orders of magnitude slower than the decision cadence the brain was designed for, so at the default two second budget every decision times out and the fighter plays on local rules.

## Gaps and next steps

- **Latency.** Three questions cost three uncached prompt evaluations. Options, in order of cost: ask only the stance, run the model on a discrete GPU or through llama-server (which the card says returns the exact distribution and caches prompts), try Q4_K_M, or order the state so the shared prefix is reused. Measure each; none is claimed here.
- **openjev not run.** Its weights need a large GPU and vLLM; the provider is proven with fake transports only. It stays opt-in and non-commercial.
- **Ollama 0.34.4** is the newest release and was not tried; the `hf.co` pull failure is recorded against 0.34.2 only.
- **Outcome.** A paired-round comparison against local rules (the design in `decision-brain.md`) needs a model fast enough to decide more than once per fight.

## Success criteria

- [x] `--provider ollama` and `--provider openjev` with loopback enforcement, strict validation, one latency budget and the paid path's fallback, at $0 with no ledger entry.
- [x] Fake-transport tests for mapping, validation, timeout, malformed replies and loopback enforcement; no model in CI.
- [x] A real local smoke recorded above with model, version, license, runtime and hardware.
- [ ] Decisions inside the default two second budget on the reference laptop.
