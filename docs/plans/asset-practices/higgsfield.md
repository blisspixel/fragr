# Higgsfield: current docs vs fragr usage (checked 2026-10-24)

Sources: docs.higgsfield.ai (sitemap lastmod 2026-10-24 for billing, errors,
idempotency, rate-limits, data-retention, usage-and-billing; model pages
2026-09-22/29), `/docs/llms.txt`, `/llms-full.txt`, `/docs/openapi.json`
(v2.0.0, explicitly "supplementary, not the authoritative model catalog").
Tool read from `origin/wave2/integration:tools/spritegen/src/{lib,generation,api_check,upload}.rs`.
Free live calls only: `POST /estimate/*`, `GET /models/usage`,
`GET /marketing-studio/image/presets`. Receipts beside this file.

## 1. Billing: the round's reconciliation is probably wrong

- `GET /models/usage` (documented 2026-10-24 under Enterprise > Usage and
  billing, works on our key, free, read-only) reports for UTC 2026-10-24:
  **187 completed marketing-studio/image generations, $24.35 estimated cost.**
  Local ledgers: 189 reservations (H-1a..H-M7 + H-LL), 2 nsfw = 187 completed,
  $24.49 estimate-held. Count and dollars match within 1%.
- Ledger entry (asset-round ledger.md ~line 233) concluded actual charges were
  "about $4.09, roughly a fifth of estimates" from Nick's dashboard ($52.47 ->
  $48.38). The provider's own analytics contradict that. Most likely the
  dashboard Nick reads is a different balance (web-app credits / workspace),
  as the H-5 note already suspected.
- All-time analytics: 510 generations, $141.68 (10-03 alone 180 gens,
  $96.36, the 4k/high batch-01..21 run). 10-03..10-07 analytics ($106.6)
  slightly exceed the $105.88 reported available, so analytics run at or a
  little above real charges, never at 20%.
- Implied API balance now: about $52.25 - $24.35 = **~$27.9** (minus any
  lagging H-LL rows: hour 18 shows 14 of 18). Treat ~$28 as the planning
  number until Nick reads the API console balance for this key's account.
- Docs caveat: usage analytics "is not a billing record... can lag... use
  invoices for reconciliation." Still the best free signal we have.
- Docs, billing-and-retention: failed and nsfw are **not charged**; any
  reservation is refunded automatically; canceled-while-queued refunded. The
  two H-1a nsfw holds ($0.06) can be released (analytics count excluded them).
- **Balance funds expire one year after they are added.** The round plan's
  "Higgsfield does not expire" is wrong. The 2026-10-13 $50 expires ~2027-10-13.

## 2. API behaviour changes the tool and pipeline doc predate

| Topic | Docs now | fragr today |
|---|---|---|
| `Idempotency-Key` header | Supported on every generation POST; same key returns original request_id, no second charge; 422 on param mismatch | Not sent. Any ambiguous POST leaves `Reserved` and needs manual dashboard recovery |
| Above concurrency | Accepted and `queued`, starts automatically | pipeline doc says "about four, exceeding returns HTTP 400" (stale) |
| Queue full | `429` + `Retry-After`, `account_queue_full`, nothing created | Treated as generic API error after reservation written |
| 503 `admission_control_unavailable` | retryable, nothing created | same as above |
| Status | adds `expires_at`; submit adds `expires_after` (604800) | not recorded |
| `DELETE /requests/{id}` | deletes files/prompt, keeps billing | unused (not needed) |
| `X-Correlation-ID` | on every response; record with request_id for support | not recorded |
| Estimate response | `{"type":"estimate","credits","usd","discount"}`; token-priced models return `{"type":"description","pricing_description"}` with **no usd** | parse_usd refuses missing usd (correct, fail-closed) |
| Webhooks `hf_webhook` | available | n/a for CLI; polling fine |
| Usage `GET /models/usage` | free analytics per model/key | unused; "no balance endpoint" repeated in every check |

1 credit = $0.0625 on current estimates.

## 3. Image models available now (17 catalog entries)

Live estimates 2026-10-24 for a short prop prompt, 1:1:

| Endpoint | Key params | Est. USD | Fit for fragr |
|---|---|---|---|
| `marketing-studio/image` (2.0 Alpha) | quality low/med/high; 1k/2k/4k; up to 16 `image_urls`; `moderation` auto/low | low 1k .017, 2k .023, 4k .031; med 1k .064, 2k .118, 4k .189; high 1k .222, 2k .439, 4k .723. Refs add: med 2k +1 ref .131, +3 refs .157; high 4:3 +1 ref .339. **med 2k 16:9 .070** | Current workhorse; proven edits/registration |
| `marketing-studio/image/flare` (2.5 Flare) | adds xhigh/max; same 16 refs | **no usd: token-priced** ($30/1M image-output tokens, $8/1M image input), "initial charge is an estimate reconciled on completion" | OpenAI: "small model, quality comparable to GPT Image 2" |
| `marketing-studio/image/sunburst` (2.5 Sunburst) | same | token-priced | OpenAI: "base model, higher image quality than GPT Image 2" |
| `xai/grok-imagine-image-2.0` | low/med; 1k/2k; up to 10 refs | low 1k .040, med 2k .080, +1 ref .090 | A/B candidate for edits |
| `alibaba/qwen-image-3/text-to-image` / `/edit` | **seed**, real **negative_prompt**, 1-3 refs (edit), prompt_extend/enable_thinking default true | 2k (=1536px) .075; 1k .040 | Only model with seed + true negative + refs; materials/tiles A/B |
| `ideogram/v4.0` | one `image_url`, `image_weight` 1-100, TURBO/DEFAULT/QUALITY | .030/.060/.100 | UI/text-heavy art (we avoid text) |
| `recraft/v4.1[/pro][/utility[/pro]]/text-to-image` | **`colors` RGB palette, `background_color`**, png, no refs | std 1k .035, pro 2k .210 | Palette-locked UI icons, decals, seals |
| `z-image/turbo` | seed, 1k/2k, prompt_extend (doubles price) | 2k .015 | Cheapest exploration |
| `higgsfield-ai/soul/v2/standard`, `soul/cinema` | photoreal people, seed, Soul ID | .006 | Not for pixel assets |
| `higgsfield-ai/soul/standard` | | .188 | Superseded |

No documented Higgsfield model exposes alpha/transparent output, a tiling or
seamless flag, or orthographic/turnaround controls. OpenAI's own GPT Image
2.5 API supports `background="transparent"`, but Higgsfield's Flare/Sunburst
schemas are `additionalProperties:false` without it. Keep the magenta key.
Marketing Studio presets (75, all ad layouts) are irrelevant; keep
`enhance_prompt:false` (enhance requires preset + forces quality high on 2.0).

## 4. Prompt and consistency guidance (primary)

OpenAI image prompting guide (developers.openai.com/api/docs/guides/image-prompting),
relevant because Higgsfield's Ads Studio page names its renderer "GPT Image
2.5 Flare" (2.0 Alpha's provider is not stated; its low/med/high and ref
surcharge are consistent with GPT Image 2, an inference):
- Structure complex prompts as labelled sections: scene, subject, details, constraints.
- Edits: "change only X" and list what to preserve; assign roles to numbered
  inputs (subject, style, background). For iteration pass the previous output
  back, one change at a time, restating invariants.
- "If a region must remain pixel-identical, composite the approved edit into
  the original image instead of relying on prompting alone." (Matches H-3's
  local re-registration; make it standard for reload/fire frames.)
- Character consistency: generate the reference first, reuse it, repeat its
  defining details and add "Do not redesign the character."
- Compare models with prompt, refs, dimensions and quality fixed; "the same
  quality label does not imply the same image quality... across models."
- `xhigh`/`max` only when they fix an unmet requirement.
- gpt-image-1 retired 2026-10-23; gpt-image-1.5 shuts down 2026-12-01.

fragr's specs already follow most of this (style/subject/view/technical
sections, hex colours from palette.json, explicit avoid lists, magenta field,
refs for every promoted frame). Gaps: refs are not role-labelled in the prompt
("Image 1 = style board, Image 2 = subject"), and invariants are not always
restated per frame.

## 5. Recommended changes (priority order)

1. **Fix the balance number** in the round ledger/plan: use `/models/usage`;
   ~$28 not ~$48 until Nick confirms the API console. Correct "Higgsfield does
   not expire" (one year from deposit). Release the two nsfw holds.
2. **Send `Idempotency-Key`** (UUID minted and written into the `Reserved`
   event before POST). Then a timeout/5xx/429 resumes by re-POSTing the same
   key instead of a dashboard hunt; 422 mismatch stays a hard stop. Keep the
   ledger; this removes most `Reserved` limbo.
3. Treat 429 `account_queue_full` and 503 `admission_control_unavailable` as
   "nothing created": honour `Retry-After`, same key.
4. Add a free `usage` subcommand (`GET /models/usage`, per-model, per-key) and
   run it as pre/post check of every batch instead of "balance unverifiable".
5. Record `X-Correlation-ID`, `expires_at` in the ledger.
6. Optional throughput: submit up to account concurrency with a semaphore
   (excess is queued server-side, not rejected); keep reservations per frame.
7. An `nsfw` frame should not block the rest of a spec: record `Stopped` and
   continue, since it is documented as uncharged.
8. Token-priced models (Flare/Sunburst) need a different budget gate: the
   estimate has no usd. Either a conservative per-image ceiling derived from
   observed `/models/usage` unit prices after a 2-3 image pilot, or keep them
   off the paid path. Do not let the tool treat "description" as free (it
   already refuses).
9. Update `higgsfield-pipeline.md`: concurrency/400 text, price table (add
   1k/4k and ref surcharges, 16:9 being cheaper than 1:1 at medium), Flare and
   Sunburst, Qwen/Recraft/Grok/Z-Image rows, `api-capabilities.json` probes
   (Meshy/Tripo names via Higgsfield 404 and are not in the catalog).

## 6. Asset-type guidance for fragr

- **Meshy image-to-3D inputs:** 2k medium + refs is the proven sweet spot
  (H-1a/H-5/H-M7 all passed canon). 4k/high costs ~6x with no shown benefit
  for Meshy input. One object, one view per image; front-3/4 from slightly
  above; magenta field; no cast shadow. meshy.md notes Multi-Image to 3D costs
  the same and constrains depth and the back, so generate front/side/back as
  separate consistent edits of the approved 3/4 (same refs, "do not redesign")
  rather than one collage sheet.
- **Viewmodel frames:** high + idle as ref, 4:3, then local registration
  composite; never trust the edit for pixel-identical regions.
- **Pickups/props sprites:** medium + 1-3 style-board refs (shipped sprites
  upscaled 4x nearest on magenta), then `reduce` with palette minus magenta
  swatches (`magenta_muted`/`magenta_light` exist in palette.json; fringe can
  land on them). For subjects that legitimately carry magenta, key on pure
  blue `#0000FF` (Lab distance 113 from nearest swatch vs 86 for magenta).
- **Tileable textures:** no model offers tiling; ask for "seamless, edge to
  edge" but always verify with a local wrap/offset test and heal locally.
  Candidate A/B at $0.075: Qwen Image 3 with seed + real negative_prompt.
- **Decals/seals/UI icons:** A/B Recraft V4.1 (std $0.035) with `colors` set
  from palette.json Union/faction swatches and `background_color` magenta.
- **Exploration:** z-image/turbo at $0.015 (seed, no refs) or 2.0 Alpha low
  1k at $0.017 before promoting.
- **Lore gate unchanged:** every prompt quotes palette hexes, faction livery
  rules and ENEMIES/ART_STORY_BIBLE canon; every output opened before use.
  Nothing here changes taste decisions pending with Nick.

## 7. Suggested pilot (needs Nick's go; small)

Same 3 subjects (one prop, one viewmodel edit, one decal), fixed prompt/refs:
2.0 Alpha medium 2k vs Flare medium 2k vs Grok med 2k vs Qwen edit 2k, and
Recraft std for the decal. ~12 images, est. under $2 plus Flare's token cost
(read actual from `/models/usage` afterwards). Decide by reduced-sprite
readability at game scale, not by full-res beauty.
