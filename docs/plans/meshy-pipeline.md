# Bounded 3D asset production

**Status:** shipped, 2026-10-03, [PR #339](https://github.com/blisspixel/fragr/pull/339).
The full [implementation CI](https://github.com/blisspixel/fragr/actions/runs/37156405220)
passes. Native tooling and the first model pilot are proven. Runtime art acceptance
remains in flight under art excellence; the
[Clerk presentation](clerk-model-presentation.md) records the next increment.

## Goal and scope

Nick selected Premium for fragr, configured `meshy` in the ignored `.env` and
requested live API credit checks in the developer tool. The free balance probe
returned HTTP 200 and 3,100 credits. Build a reusable native account checker and
bounded image-to-3D and humanoid-rigging path within `tools/spritegen`.
The first pilot targets one enemy, one weapon and one prop within 150 existing
credits. References and returned models remain candidates until inspected in
Godot; a generated mesh is not a finished asset or final campaign acceptance.

The [completed pilot evidence](../evidence/meshy-pilot-20261003.md) records four
model candidates, a character rig with walk/run clips and seven rendered GLBs.
It consumed 125 net credits with 15 additional credits held conservatively after
a refused request. The live account reports 2,975 credits; no model is selected
for runtime yet. The topology generator comparison was not submitted.

No new cash purchases, top-ups, runtime API calls or paid CI calls. Server
simulation, collision and campaign facts remain unchanged. Animation authoring,
full roster conversion and twelve complete environment kits remain separate art
acceptance work under the existing roadmap's art rung.

## Architecture and contracts

- Reuse the existing HTTP transport, dotenv integration, durable locked ledger,
  dollar cap and synced artifact writes. Bind each credential to its own API origin.
- Add `meshy-check` for a free live balance and optional requested-credit preflight.
- Add `meshy-gen` for strictly described model or rig stages. Both a credit ceiling
  and dollar ceiling are required. Reserve before POST; never automatically retry
  an uncertain submission. Resume known tasks through GET and download only.
- Check the account balance for the whole fresh batch, then immediately before
  each paid stage. Deduct unresolved local reservations conservatively. API or
  schema failures refuse generation. External account activity can race a check;
  provider refusal must remain observable and never trigger top-ups.
- Use one output/ledger directory for the account's pilot, unique stage IDs and
  exact request identities. Existing request receipts and uncertain reservations
  survive restarts. A missing output cannot authorize a new paid request.
- Validate origin, task IDs, bounded responses, task ownership, output URLs and GLB
  framing. Import and inspect the model separately before runtime selection.
- Accept `meshy` and `MESHY_API_KEY` in the existing ignored dotenv file. Never
  print credentials or provider error bodies. No new dependency or scripting runtime.

## Primary-source research, checked 2026-10-03

- [Authentication](https://docs.meshy.ai/en/api/authentication): Bearer credentials;
  monthly key credit limits are available in the developer account.
- [Balance](https://docs.meshy.ai/en/api/balance): authenticated
  `GET /openapi/v1/balance`, integer `balance` field.
- [Image-to-3D](https://docs.meshy.ai/en/api/image-to-3d): pin `meshy-7.1`, GLB output,
  PBR textures, optional remeshing and canonical poses. Retired modes are excluded.
- [Rigging](https://docs.meshy.ai/en/api/rigging): textured humanoids, 5 credits,
  rigged GLB and basic walking/running outputs. Failed anatomy is not retried blindly.
- [Pricing](https://docs.meshy.ai/en/api/pricing): textured 2K/4K generation is
  30 credits; Ultra geometry adds 5. This is API task pricing, not a subscription tier.
- [Plan guide](https://help.meshy.ai/en/articles/12062933-which-meshy-plan-is-right-for-you-free-vs-pro-vs-premium-vs-ultra):
  Premium $40/month, 3,000 monthly credits, first-month offer user-reported at $20.
  Budget at $0.02 per credit conservatively, the documented Pro retail ratio,
  rather than calling that an itemized charge on this Premium account.
- [Terms](https://www.meshy.ai/terms-of-use), updated 2026-09-19: paid customers
  own their output to the extent allowed by law. Keep original input rights and
  required copyright/license notices. Free-plan outputs have separate obligations.
- [Retention](https://docs.meshy.ai/en/api/asset-retention): API models last at most
  three days. Download complete GLBs immediately, retain source images and hashes,
  and back up accepted work. A remote task link is not durable storage.
- [Rate limits](https://docs.meshy.ai/en/api/rate-limits): keep the pilot sequential,
  poll at five-second intervals with a bounded attempt count, and never retry a
  POST automatically on a timeout, throttling response or lost response.

## Commands

The root ignored dotenv accepts `meshy=<key>` or `MESHY_API_KEY=<key>`. Duplicate
aliases with conflicting values are refused. From the repository root:

```sh
cargo run -p fragr-spritegen --locked -- meshy-check --required-credits 150
cargo run -p fragr-spritegen --locked -- meshy-check --out art/raw/meshy-pilot-20261003 --required-credits 35 --report .agents/meshy-balance.json
cargo run -p fragr-spritegen --locked -- meshy-gen --spec .agents/meshy-models.json --max-credits 150 --max-spend-usd 3
```

Receipts use `create_new`, so an existing report is not replaced. Generation uses
the existing locked `ledger.jsonl`. A conservative pending hold may count credits
already deducted by the provider; reconcile before raising a budget. Separate
ledger directories do not provide an account-wide cap, so retain one account's
production directory and serialize work. Other account users can race a live check.

Model specifications reject unknown parameters and case-colliding IDs. Example:

```json
{
  "out_dir": "art/raw/meshy-pilot-20261003",
  "jobs": [{
    "id": "clerk-model",
    "kind": "image",
    "image_url": "https://example.com/owned-character-reference.png",
    "geometry_resolution": "2k",
    "texture_resolution": "4k",
    "target_polycount": 12000,
    "pose_mode": "a-pose"
  }]
}
```

That exact model stage is 35 credits under the checked price table. The tool pins
7.1, textured PBR triangle output, remeshing and GLB only. Image enhancement is
disabled to preserve the supplied design. The 12,000-face target is an initial
character candidate budget, not measured performance. `standard` geometry costs
30 credits. Use `pose_mode: ""` for props and weapons. Rigging is a separate
5-credit stage with `kind: "rig"`, `input_task_id` and `height_meters`; submit it
only after inspecting the character model. Record provider-reported consumption
separately from reserved dollar equivalents. No auto-rigging promise covers a
mechanical crawler, floating Notary or a malformed humanoid.

For a controlled hard-surface comparison, `ai_model: "meshy-t2"` selects Smart
Topology, with `geometry_resolution: "standard"` and at most 15,000 faces. A
textured 2K/4K stage costs 15 credits; Ultra geometry and remesh parameters are
excluded. Current documentation describes cleaner topology and separated parts,
but inspect actual output nodes before promising a moving pump or mechanical
assembly. The pilot may compare a second Shotgun and generator using this path,
remaining within the same 150-credit allowance (140 including the character rig).

Preserve raw GLBs privately. Before public acceptance, inspect normals, embedded
PBR maps, silhouette from all sides, actual triangle count, unit scale, foot origin,
skin weights and motion. Keep authored CRT emission separate because 7.1 does not
return emission maps. Weapons need separate moving parts and appropriate hand
registration; a static fused mesh cannot replace a working first-person weapon.
Inspect raw metadata for public attribution rules, preserving required copyright
and license notices. The models do not create collision or server authority.

## Verification and acceptance

Offline transports must prove live-balance failure, malformed/insufficient credit,
whole-run and per-stage caps, pending holds, reservation-before-POST, uncertain
submission refusal, unchanged request identity, resume without another POST,
bounded polling, invalid output and artifact recovery. Test dotenv aliases and
CLI refusal before loading a key. Paid or external services never run in tests.

Run format, warning-denied clippy, workspace tests and the unfiltered coverage
gate. Run the native free checker with the actual key and a sanitized receipt.
For the pilot, record priced stages, actual balance snapshots, IDs and output
hashes, then require clean Godot imports, inspected renders and a quality verdict.
Full-client and gameplay gates remain required for any runtime integration.

## Handoff

The existing art increment shipped as v0.68.0. Its Low Water playthrough records
the prior integrated assets, not future Meshy candidates. The 3D pilot does not
promise the whole campaign's art will be finished in one or two subscription months.
Measure accepted-output yield and production time before revising that estimate.
