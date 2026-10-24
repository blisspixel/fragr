# fragr asset production practices

Checked 2026-10-24 against primary sources (official docs, API references, changelogs, official guides), then reviewed a second time against those sources, the tool source on `main` (`9010d6ad`; `origin/wave2/integration` has merged and no longer exists), the canon docs, the candidate receipts in `client/art/model-candidates/*.glb.json` and the round ledger. This is a working guide, not canon. Lines marked **Proposal** need Nick's agreement. Detailed evidence is in [`higgsfield.md`](higgsfield.md), [`meshy.md`](meshy.md), [`elevenlabs.md`](elevenlabs.md), [`lore-gate.md`](lore-gate.md) and [`brief-template.md`](brief-template.md); where this file and those notes disagree, this file is the corrected one. Raw results from free endpoints are saved beside them. No paid call was made and no tracked file changed.

**Game target:**
- Godot 4.7.2-stable, retro-modern boomer shooter with chunky pixel surfaces. Boltgun is the production reference (`docs/VISION.md`, `docs/ART_STORY_BIBLE.md`).
- Nearest filtering, no mipmaps, colours from `docs/palette.json`.
- Model paint is resampled to 32 texels per metre by `tools/prepare_model_candidates.gd` (`TARGET_TEXELS_PER_METRE`). That is the trial importer's constant, not yet a documented project rule.
- Characters will be either live 3D with pixel treatment or baked directional sprites (trial pending). Everything below works for both.

---

## 0. Read first: facts that change plans now

| Fact | Consequence |
|---|---|
| Higgsfield `GET /models/usage` (free) shows **187 completions costing $24.35** in the 2026-10-24 UTC bucket. Local ledgers have 189 reservations minus 2 nsfw stops = 187, estimate-held $24.49. The hourly bucket for H-LL showed 14 of its 18 images when sampled, so it lags. | The ledger's "about $4.09 actually charged" (from Nick's dashboard, $52.47 to $48.38) is contradicted by the provider's own analytics. The likeliest explanation is that the dashboard shows a different balance (web-app credits or another workspace). The docs say analytics "is not a billing record" and can lag, so this is strong evidence, not proof. Until Nick reads the API console balance for this key, **plan on about $27 usable, not $48** ($52.25 basis, minus $24.35, minus the H-LL rows still lagging). |
| Higgsfield funds **expire one year after they are added** (billing and retention docs). | `docs/plans/asset-round-20261023.md` line 103, "Higgsfield does not expire", is wrong. Usage analytics start on 2026-09-19, so the oldest deposit is on or before that date and can expire as early as about 2027-09-19. Nick to confirm the deposit dates. |
| **Meshy has 30 credits (15 usable after the external hold) until 2026-11-03 20:34 UTC.** M-LL already ran on 2026-10-24 (9 × 30 = 270, closed in the ledger). `lowpoly` retires 2026-10-30. | No Meshy re-run is possible this cycle. Every Meshy recommendation below lands on the November allowance (about 3,000 a month on the plan recorded in `meshy-pipeline.md`; confirm with the free `meshy-check` after the reset). Land the tool changes before the reset. |
| Meshy keeps API task results for **at most 3 days** (non-Enterprise, Asset Retention page). After that, `input_task_id` returns 404. | Rig and animation stages chained by `input_task_id` must run within 3 days of the generation task. Later, send our stored GLB as `model_url`, never an old signed URL. |
| ElevenLabs has used 855,588 of 1,185,132 credits, leaving **about 329,500 until 2026-11-06 14:51 UTC**, when the allowance resets. | This is the planned use of an expiring allowance, not overspend. Reconcile with `audiogen quota` before each batch and keep the plan's 150,000 reserve rule. |
| ElevenLabs **default voices expire 2026-12-31** and "will no longer be accessible". That includes River (all narration), Bill (Host), and Daniel, Brian and Callum (the E-1 Host candidates). | Shipped files stay valid, but no new line can match those voices after that date. Recast before E-2 (about 70 Host lines × 4 takes). |
| The E-1 Host takes say "DOUBLE FREQUENCY", "FREQUENCY RAMPAGE", "TRIPLE SCRAP", "FLAG TAKEN" and "CHARGE ARMED". The E-1 spec used the pre-correction list in `.agents/asset-round-20261023/plan.md`. | This breaks the 10-23 correction and `docs/lore/voice.md` ("no frequency puns"). The tracked plan voices FIRST BLOOD, TRIPLE FRAG, QUAD FRAG, RAMPAGE, FLAG CAPTURED, CHARGE PLANTED and similar, and keeps double frag, lead change, flag taken and golden rail as captions only. Reject those takes. |
| Many of this round's Meshy models do not fit their slots. The receipts show why: **the meshes follow their reference images, and many slots are not single-object briefs.** The Paver reference is itself a low four-legged sledge; the turnstile was fitted against a 16 m row of turnstiles; the growth rack against a 3 × 5.5 m bed area; the recycler against a 3 × 8 m recycling area. Where a brief gave per-object dimensions (the Larak Lot props), single-image 7.1 mostly landed close: toll booth within 5%, burned sedan and kiosk within about 25%; the car stack missed one axis by half. | The fix is upstream: per-object dimensions in every brief, references drawn to those proportions, and a proportion check on the reference before any credit is spent (section 1.4). Multi-view input helps depth and the back, but it cannot fix a reference drawn at the wrong proportions. All inputs this round were 3/4 views, not front views. |

---

## 1. Higgsfield (images: references, view sets, sprites, surfaces, decals)

**Sources:**
- Higgsfield docs (sitemap dates 2026-09-22 to 2026-10-24): [llms-full.txt](https://docs.higgsfield.ai/llms-full.txt), [OpenAPI v2.0.0](https://docs.higgsfield.ai/docs/openapi.json) (stated to be supplementary, not the authoritative catalog), [idempotency](https://docs.higgsfield.ai/docs/concepts/idempotency), [rate limits](https://docs.higgsfield.ai/docs/concepts/rate-limits), [billing and retention](https://docs.higgsfield.ai/docs/concepts/billing-and-retention), [usage and billing](https://docs.higgsfield.ai/docs/enterprise/usage-and-billing), [errors](https://docs.higgsfield.ai/docs/concepts/errors).
- The [OpenAI image prompting guide](https://developers.openai.com/api/docs/guides/image-prompting), which covers GPT Image 2.5 Flare and Sunburst with reference sections for GPT Image 2. Higgsfield's 2.5 endpoints carry the same names, and Meshy's changelog (2026-09-15) lists `gpt-image-2-5-flare` and `-sunburst` as GPT Image models. That Higgsfield's 2.0 Alpha is GPT Image 2 is an inference from its quality tiers and reference surcharges.
- Prices below are live `POST /estimate` receipts from 2026-10-24 (`higgsfield-estimates-20261024.txt`). 1 credit = $0.0625.

### 1.1 Models to use

| Model | Use for | Live price (1:1 prop prompt) | Notes |
|---|---|---|---|
| `marketing-studio/image` (2.0 Alpha) | **The default for everything until a pilot shows something better.** Every recent fragr image spec uses it. | Low 1k $0.017, low 2k $0.023. Medium 2k $0.118 ($0.131 with one reference, $0.157 with three). Medium 2k at 16:9 $0.070. High 2k $0.439. | Quality low, medium or high only (`xhigh` is refused). Up to 16 `image_urls`. The estimate returns an exact usd figure. |
| `marketing-studio/image/flare` and `/sunburst` (GPT Image 2.5) | Pilot only: hero references where 2.0 misses a stated requirement. | Token-priced ($30 per 1M image output tokens, $8 per 1M image input tokens) | The estimate returns `{"type":"description"}` with no usd. spritegen already refuses it (fail-closed); a new budget gate is needed first. |
| `alibaba/qwen-image-3/*` | Pilot: reproducible variants and tile candidates. The only model here with a **seed** and a real **negative_prompt**. The edit endpoint takes 1 to 3 references. | $0.075 at 2k (1536 px), $0.040 at 1k | Set `prompt_extend` and `enable_thinking` to false (both default true). |
| `recraft/v4.1` | Pilot: flat decals, UI icons and blank signage. The **`colors`** palette control can take swatches from `palette.json`. | $0.035 standard 1k, $0.21 pro 2k | No reference images. |
| `xai/grok-imagine-image-2.0` | Pilot only. | $0.040 low 1k to $0.090 medium 2k with a reference | Up to 10 references. |
| `z-image/turbo` | Cheap thumbnails or composition sketches. | $0.015 at 2k | Has a seed. `prompt_extend` doubles the price. |
| Soul v2, Cinema, Marketing presets | Do not use. | | They make photoreal people and ad layouts (H8). |

No documented Higgsfield model offers alpha output, a tiling flag, or orthographic or turnaround controls (the 2.5 schemas are closed and have no `background` field). Keep the flat key-colour pipeline and the local tile wrap tests.

### 1.2 Our settings going forward

- **Tiered quality (Proposal):**
  - Explore at low 1k ($0.017) or low 2k ($0.023).
  - Make keepers, anchors and Meshy inputs at **medium 2k** with references ($0.118 to $0.157). That is the tier every canon-passing input this round used, and the Larak Lot toll booth landed within 5% of its brief from a medium image.
  - Use high only when medium misses a specific, written requirement (OpenAI's guidance for higher tiers is the same). Viewmodel frames that need fine registration are the current example. Never use high for exploring.
- Always set `enhance_prompt: false` (enhancement needs a marketing preset and forces high quality on 2.0 Alpha).
- Set `moderation: auto`. An nsfw stop is not charged (billing docs); log it and move on.
- **Key colour:**
  - Flat `#FF00FF` by default. Its nearest palette swatch is `magenta_light` at 86 Lab units, so check fringes after `reduce`.
  - Flat `#0000FF` for subjects that really carry magenta. Its nearest swatch is `outline_purple` at 113 Lab units.
  - The flat key is removed before Meshy. Meshy wants a plain white, grey or transparent background that is not close to the object's colour, so always upload the keyed transparent PNG.
- Price with `POST /estimate/<model>` using the **exact request body, including `image_urls`**. References raise the price, and 16:9 can be cheaper than 1:1.
- Download outputs straight away. Files are deleted 7 days after the request finishes (`expires_at` on the status response).
- Reconcile every batch with the free `GET /models/usage` (31-day window, hourly to monthly buckets, `expand=auth_method` splits by key) and with Nick's API console reading. The usage figures are analytics, not an invoice, and can lag.

### 1.3 Prompt and brief pattern (consistent sets built from references)

Build each set from the top down, so everything traces back to one approved source:

1. **A place style board**: one approved image per world or level family.
2. **A subject anchor**: one approved 3/4 view per subject, drawn to the brief's per-object proportions and judged at play size.
3. **Derived views and states** (front, side, back, freed, damaged, absorbed, years later): each is a separate **edit of the anchor**, never a collage sheet.

Prompt skeleton. It uses labelled sections, gives every reference a numbered role, and repeats what must not change on every frame (all three are in the OpenAI guide):

```text
REFERENCES: Image 1 = approved <place> style board (style and light only).
            Image 2 = approved <subject> anchor (design to keep exactly).
CHANGE ONLY: <view / state>. Do not redesign the object.
KEEP UNCHANGED: silhouette, proportions <W x D x H m>, part layout, livery
            blocking, materials, wear, blank plates.
STYLE: stylized pixel-craft source, broad painted planes, coherent value
            clusters, even flat light, no cast shadows on the object.
SUBJECT: <faction> <object>, <owner/issued state>, <place material>.
PALETTE: dominant <keys + hex>, secondary <keys>, accent <keys>, emissive <key|none>.
VIEW: <orthographic-like front | side | back | 3/4>, whole silhouette, centred.
TECHNICAL: one object, flat #FF00FF field, no magenta inside the object,
            no text, numbers, logos or watermarks; blank plates and seal bosses.
AVOID: <spec default list> + <reserved-colour negatives for this faction>.
```

- Change one thing per iteration, and restate what must not change every time.
- Where pixels must stay identical, composite the approved edit in locally ("composite the approved edit into the original image", OpenAI guide). H-3's re-registration step is the right practice.
- When comparing models, hold the prompt, references, size and output format fixed. The same quality label does not mean the same quality across models.
- Even, flat lighting in the references matters later. Meshy 7.1 ignores `remove_lighting` on single-image tasks, Smart Topology rejects it, and `ART-GENERATION-SPEC.md` requires albedo only.
- Write the dimensions as numbers in the prompt. A prompt that says "about 3 metres long and 0.9 metres tall" (growth rack) still produced a bench about 1.5:1, so the numbers are a request, not a guarantee; the check in 1.4 is what enforces them.

### 1.4 QA gates

- Pass Gate A (the brief) before any `gen`. Pass Gate B (`lore-gate.md` 11.1) on every keeper.
- **Key check:** a clean field, the whole silhouette visible, and no key colour inside the object.
- **Palette check:** the image survives quantising to `docs/palette.json`. List any invented hex code as "extension, pending Nick" (P10).
- Judge at play size and internal resolution first, then up close.
- **Proportion check before any Meshy credit (Proposal: within 20%).** Measure W:H on an orthographic-like front view and D:H on a side view of the keyed image against the brief's per-object dimensions. A 3/4 view's bounding box is foreshortened and only gives a rough check. This is the main reason to make the front and side edits even for subjects that go through single-image Meshy.

---

## 2. Meshy (models: props, vehicles, mechanisms, characters, animation)

**Sources (all fetched 2026-10-24):**
- API docs: [image to 3D](https://docs.meshy.ai/en/api/image-to-3d), [multi-image to 3D](https://docs.meshy.ai/en/api/multi-image-to-3d), [pricing](https://docs.meshy.ai/en/api/pricing), [changelog](https://docs.meshy.ai/en/api/changelog), [rigging](https://docs.meshy.ai/en/api/rigging-and-animation), [animation](https://docs.meshy.ai/en/api/animation), [text to motion](https://docs.meshy.ai/en/api/text-to-motion), [UV unwrap](https://docs.meshy.ai/en/api/uv-unwrap), [retexture](https://docs.meshy.ai/en/api/retexture), [auto split](https://docs.meshy.ai/en/api/auto-split), [asset retention](https://docs.meshy.ai/en/api/asset-retention).
- Guides: [multi-view tutorial, updated 2026-09-08](https://www.meshy.ai/tutorials/multi-view-image-to-3d) (webapp; its credit figures are webapp prices, not API prices), [image-to-3D help, 2026-08-19](https://help.meshy.ai/en/articles/15723519), [pose help, 2026-08-15](https://help.meshy.ai/en/articles/16102152), [low-poly guidance, 2026-09-29](https://www.meshy.ai/topics/ai-low-poly-generate-or-decimate).
- The free animation library listing (678 clips) is saved as `meshy-animation-library-20261024.json`.

### 2.1 Models and features to use

| Feature | Use for | API credits |
|---|---|---|
| **meshy-t2.5 Smart Topology** (`model_type: "smart-topology"`; added 2026-10-15, now the Smart Topology default) | **Pilot, then hard-surface props and mechanisms.** Triangles only, `target_polycount` 100 to 30,000 (default 15,000), single image only. The docs claim "natively separated parts" only for t2, and fragr's clean-UV and separated-island evidence (2026-10-04 Pistol and Rifle, about 1.06 vertices per triangle, 55 to 61 islands) is also t2. Confirm both on t2.5 before relying on them. | 15 textured (2k or 4k), 20 at 8k, 5 untextured |
| **meshy-7.1** (`latest`, 2026-09-18), single image or **Multi-Image** (1 to 4 views, front first; optional `texture_image_urls`, 1 to 4 more) | **Characters, organic subjects, and any subject whose depth or back came out wrong.** | 30 textured at standard geometry, 35 with `geometry_resolution` 2k or 4k. Multi-Image costs the same as single image. |
| Rigging | Textured standard humanoid bipeds, face toward +Z, at most 320,000 faces, real `height_meters` (default 1.7). Generate in A-pose or T-pose. | 5 (walk and run clips are optional extras) |
| **Animation API** (`action_ids`, 1 to 10 per request, one merged file; `post_process` `change_fps` to 24, 25, 30 or 60) | Idle, pain, disable, reload and shoot-while-walking sets for humanoid roles. | 3 per action |
| Text to Motion (swift gives BVH, prime gives FBX; 2 to 10 s; bipeds only) | Custom moves the library lacks. Swift to iterate, prime for keepers. | 3 or 10 |
| UV Unwrap, then Retexture with `enable_original_uv: true` | Rescuing a kept 7.1 mesh whose UVs are fragmented. Retexture's docs do not list a UV Unwrap task as an accepted `input_task_id`; confirm, or pass the unwrapped GLB as `model_url`. | 5 + 10 |
| Retexture with `ai_model: "meshy-6"` and `remove_lighting: true` at 2k or 4k | Fixing a base colour that fails the baked-lighting check. Only meshy-6 at 2k or 4k applies `remove_lighting`. | 10 |
| Free flags: `multi_view_thumbnails` (front, right, back, left at 512 px), `alpha_thumbnail`, `save_pre_remeshed_model` | Review evidence, and a dense source for baking normal maps locally on hero assets. `save_pre_remeshed_model` applies only when remeshing, so not on Smart Topology. | 0 |

**Do not use:**
- `lowpoly` (retires 2026-10-30) and `meshy-7` (deprecated).
- `symmetry_mode` (no effect), `ultra_mode` and `hd_texture` (deprecated; use `geometry_resolution` and `texture_resolution`), `is_a_t_pose` (use `pose_mode`), and the rigging `texture_image_url` (deprecated 2026-10-23). The tool sends none of these today.
- `remove_lighting` on 7.1 single image (accepted and ignored) or on Smart Topology (400).
- Auto Split. It targets 3D printing, drops textures to flat vertex colour, and rejects Smart Topology inputs.

4k geometry is single-image only (Multi-Image returns 400).

### 2.2 Which route each kind of subject takes

Smart Topology is not offered on Multi-Image, so each subject picks one route:

| Class | Route | Why |
|---|---|---|
| Hard-surface prop, vehicle, or mechanism with moving parts | **After a two-subject pilot passes: t2.5 from a single image**, a 3/4 anchor that has passed the proportion check. Target polycount from the brief. Until then, 7.1 single image at standard geometry (the M-LL route). | Half the price. If the pilot confirms clean UVs and separated parts on t2.5, they survive 32 texel/m nearest paint and give pivots. Note Smart Topology rejects `image_enhancement: false`, so Meshy may alter the reference; compare the textured result against the anchor. |
| The same, when depth or the back comes back wrong | **7.1 Multi-Image** (front first, then side, back, 3/4). Run UV Unwrap and Retexture only if the UV or texel gate fails. | The extra views constrain depth and the back ("the AI must guess" without a back view). |
| Character, enemy biped or creature | **7.1 Multi-Image** with `pose_mode: "a-pose"`, limbs apart, full body, not cropped, front view first. Then rig, then animate, all within the 3-day retention window. | Faces, hands and backs improve with more views. Set the pose with the toggle, not the prompt (pose help). |
| Single-piece set dressing (crate, barrier) | t2.5 at a low target polycount, after the pilot. | Generate low-poly directly rather than decimating a dense mesh. |

**Rigging scope.** Meshy rigging covers standard humanoid bipeds only. In `ENEMIES.md` that means Clerks, Enforcers, Auditors, Redactors and humanoid bot chassis (Sweepers, NODS on foot). The Crawler, Notary, Assessor, Turret, Surveyor, Paver and Walker use local controlled pivots, as `meshy-pipeline.md` already says.

**Polycount targets (Proposal):**
- Small props: up to 5k triangles.
- Large props and vehicles: up to 15k.
- Characters and bosses: up to 20k.

Each brief records its own target. Chunky pixel surfaces gain nothing from extra density.

**Characters work for both render routes.** One rigged, animated source serves both the live-3D trial and the baked-sprite trial. For the pixel look, step the keyframes locally (held poses at a low fixed rate) rather than asking Meshy for it.

**Proposal: a starting clip set for each humanoid role** (6 to 8 actions, 18 to 24 credits; walk and run may come with the rig). IDs checked against the saved library:
- Idle (0, or 11 to 15 for variants), walk, run;
- Walk Forward While Shooting (234);
- Hit Reaction (178) or Gunshot Reaction (177);
- Standing Reload (170);
- Dead (8) or Shot and Fall Backward (183), **for human Union troops only**.

Library clips are human mocap, raw material only. `ENEMIES.md` asks every role for "facing, locomotion, attack, pain, disable/death and any reactivation frames", and its fiction separates disabled, destroyed and recoverable states: bots and NODS are captive persons, so their collapse should read as a machine powering down and remain reactivatable where the rules allow, not as a human death fall. Tells still follow the server phase timing in `ENEMIES.md`.

### 2.3 Our settings going forward

What `tools/spritegen/src/meshy.rs` already sends for 7.1 image stages: `image_enhancement: false`, `should_remesh: true`, `topology: "triangle"`, `target_polycount`, `enable_pbr: true`, `target_formats: ["glb"]`, and `pose_mode`. For `meshy-t2` it already removes `geometry_resolution`, `should_remesh`, `topology` and `image_enhancement`; t2.5 needs the same treatment (section 5, item 4).

- Keep `enable_pbr: true` for the normal map. The importer drops metallic and roughness, sets metallic 0.08 and roughness 0.92, and uses the normal map at `normal_scale` 0.2. 7.1 returns no emission map; author CRT and lamp emission separately.
- **Input images:**
  - keyed to transparent, at least 1040 px on the short side (multi-view tutorial; the help article calls 1024 px ideal), PNG, one object per image, filling most of the frame;
  - the same lighting, scale and style across all views, even diffused light with no hard shadows;
  - front first; side, back and 3/4 as the other views;
  - include the back whenever possible, because without it the back is guessed.
- `pose_mode: ""` for props only. `a-pose` for anything flagged as a rig candidate.
- Send `multi_view_thumbnails` and `alpha_thumbnail` on new stage ids. They change the request identity, so never add them to a resumed stage.
- Never retry a POST automatically (Meshy documents no idempotency key). Honour `Retry-After` on a 429 (headers added 2026-09-28).
- Download results within 3 days. Chain rig and animation stages inside that window, or upload the stored GLB as `model_url` afterwards.

### 2.4 QA gates (Gate B for models)

Most of these are already measured in the `prepare_model_candidates.gd` receipts (`fit.fill_ratio_xyz`, `fit.worst_log_mismatch`, `uv_coverage`, `texels_per_metre`, `topology.boundary_edges`, `topology.nonmanifold_edges`, `faction_colour`). What is missing is a pass or fail verdict on each, and the brief dimensions to compare against.

1. **Proportion (Proposal: within 15%, a `worst_log_mismatch` of about 0.14):** compare against the brief's **per-object** dimensions, never against a server solid that stands for several objects or an area (`concourse_turnstiles`, `growth_bed_0_0`, `greenhouse_east_recycling`, `edge_central_cart`). Stretching one axis is allowed only inside that 15%.
2. **Texel density:** achieved `texels_per_metre` at least 32 before resampling. This is the meaningful UV check: locomotive v1 (1.7), casting furnace (19.6), locomotive v2 (24.8) and recall car (26.2) fail it. UV coverage alone is a warning, not a gate; 31 of 59 candidates sit between 0.48 and 0.55 with usable density. Zero coverage (locomotive v1) is a hard fail.
3. **Mesh health:** report boundary and non-manifold edges. Anything used as a blocking solid or rigged must have close to none (custody-housing, at 806 boundary and 1,229 non-manifold, fails; growth rack and recall car are next worst).
4. **Base colour:** measure brightness variance across faces with the same orientation to flag baked shadow or ambient occlusion. This check is new.
5. **Faction colour survives texturing.** The receipts flag "no restrained Union red" on eight Union subjects (assessor hull, custody housing, impound tug, ingot trolley, lathe, locomotive v1, recall car, turnstile). Compare the raw Meshy texture with the palette-locked paint before blaming Meshy, since the lock can quantise a small red away. The expected answer also depends on P4 and P7 (fixed plant may carry only markings). Re-check `lore-gate.md` 11.1 items 1, 2, 5, 6 and 7 on the textured model, using the multi-view thumbnails including the back.
6. **Parts:** every moving part a tell needs exists as a separate piece or a separable island (Surveyor iris, Assessor optics, Collector panel, wheels, Paver work head).
7. **Anatomy:** count legs, arms and fingers. The 2026-10-04 Smart Topology Crawler came back with six legs against its four-leg combat silhouette.
8. **In engine:** in the target map's light, in motion, beside an approved asset, at internal resolution, with scale matching the authoritative solid, with screenshots as `AGENTS.md` requires.

---

## 3. ElevenLabs (voice, SFX, music)

**Sources (fetched 2026-10-24):**
- Speech: [models](https://elevenlabs.io/docs/overview/models), [Eleven v4](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4) (launch per the 2026-09-28 changelog), [TTS API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [TTS best practices](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices), [pronunciation dictionaries](https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/pronunciation-dictionaries), [default voices](https://elevenlabs.io/docs/help-center/product/voices/my-voices/what-are-default-voices), [voice design](https://elevenlabs.io/docs/eleven-creative/voices/voice-design).
- Sound effects: [SFX API](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert), [SFX overview](https://elevenlabs.io/docs/overview/capabilities/sound-effects).
- Music: [composition plans](https://elevenlabs.io/docs/eleven-api/guides/how-to/music/composition-plans), [inpainting](https://elevenlabs.io/docs/eleven-api/guides/how-to/music/inpainting), [stem separation](https://elevenlabs.io/docs/api-reference/music/separate-stems), [finetunes](https://elevenlabs.io/docs/eleven-creative/products/music/finetunes).
- Changelogs: [2026-05-25](https://elevenlabs.io/docs/changelog/2026/5/25.md), [2026-06-22](https://elevenlabs.io/docs/changelog/2026/6/22.md), [2026-10-12](https://elevenlabs.io/docs/changelog/2026/10/12.md), [2026-10-19](https://elevenlabs.io/docs/changelog/2026/10/19.md).
- Godot 4.7: [audio import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html), [AudioStreamSynchronized](https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html).
- Already in the tool: `tools/audiogen` has `library`, `design` and `save-voice` (`casting.rs`, `docs/plans/audiogen-voice-design-20261023.md`) and accepts `eleven_v4`; the default stays `eleven_v3`.

### 3.1 Models and features to use

| Area | Use | Notes |
|---|---|---|
| Speech | **`eleven_v4`** (the models page's suggestion for quality content; the v4 page calls it "a net upgrade over Eleven v3"), after a 10-line A/B on each chosen voice | Stability and Similarity only; no Style or Speed sliders and no SSML. Reads IPA wrapped in forward slashes. Voice Design voices "may not be as performative" on v4, hence the A/B. `eleven_v4_turbo` is for real-time agents; not needed for assets. |
| Voices | **Owned voices, one per lasting role**: designed with `eleven_ttv_v3` and seeded, or a library voice with a long notice period | Default voices expire 2026-12-31. Official replacements (not one-to-one): Elowen for River (already in the account, 4,015-day notice period), Wyatt for Bill (not in the account). |
| SFX | `eleven_text_to_sound_v2` for now. **Pilot `eleven_text_to_sound_v3`**: it is in the API enum but not yet on the models page or in a changelog entry. | WAV output since 2026-10-19 (8 to 48 kHz). Duration 0.5 to 30 s. `prompt_influence` default 0.3. No loudness control. |
| Music | **`music_v2_5` composition plans**: up to 30 chunks of 3 to 120 s, total 3 s to 10 min, up to 50 positive and 50 negative styles per chunk; v2.x enforces section durations (changelog 2026-06-22) | Plans and text prompts are exclusive. Per the API reference, `seed` works only with a plan and `force_instrumental` only with a prompt; with a plan, put "instrumental" in the styles and "vocals" in the negatives. |
| Music repair | **Inpainting** (`music_v2` or `music_v2_5`). `store_for_inpainting` returns a `song_id`; a section can be kept, regenerated, or conditioned on up to 30 s of the track. An existing take can also be uploaded with `music.upload` to get a `song_id`. | The docs' loop recipe: keep a 3 to 8 s slice, add a 3 s `[Glue]` chunk, keep the same slice again. Plan eligibility and price are not documented; check before the first use. |
| Adaptive layers | **Stem separation** (`six_stems_v1` default, or `two_stems_v1`) | Price not published; check before use. |
| Score identity (later) | A Music Finetune trained on our own approved original cues | Only after the score identity (P9) is accepted. |
| Built-in voice effects (2026-10-12) | **Do not use on character voices.** | Keep voices dry and add space in Godot (reversible). Latch never gets a battle-unit voice filter (`voice.md`). |

### 3.2 Our settings going forward

**Speech (TTS):**
- `model_id` per role (v4 once its A/B passes), plus `stability`, `similarity_boost` and a fixed `seed` per role. audiogen sends only `stability` today.
- `language_code: "en"`. Text normalisation is on by default; set `apply_text_normalization` explicitly only where numbers or codes read wrongly.
- `previous_text`/`next_text` (or `previous_request_ids`) for narration split across requests.
- One fragr pronunciation dictionary (PLS) for proper nouns (Latch, Tern, Edda, Splice, Mara, Unmetered, Continuance, place names). The API reference allows up to 3 locators per request. Matching is case-sensitive and only the first rule applies.
- Write delivery tags as descriptions of the voice (`[low, dry, relaxed]`, the docs' example is `[low, gravelly voice]`), not single words the model might voice as a sound.

**Voice Design:**
- Prompt: "Native English, <variant>. <Gender>, <age>. Studio quality. Persona: ... Emotion: ...", then one or two sentences on timbre and pacing. No FX words.
- Preview text of 100 to 1,000 characters in the role's register. Seed every design.
- Never clone a voice, never imitate a real person, and never sort friend from enemy by accent (`voice.md`: "it does not sort friends and enemies by national labels or accents").

**Sound effects:**
- One event per request, layered offline (transient, body, tail), as the 10-02 Shotgun was made. Use audio vocabulary ("one-shot", "impact", "dry") and the real duration.
- Events shorter than 0.5 s: generate a burst and slice one out.
- Drop "headroom" wording; it had no effect in E-4.
- `loop: true` only for ambience beds of 20 to 30 s (30 s is the maximum). Cut short mechanical loops offline from steady 6 to 8 s takes with equal-power crossfades.
- Request `pcm_48000` (audiogen already wraps PCM into WAV locally; its default is `pcm_24000`, so set it per item) or `wav_48000`.

**Music:**
- Use a composition plan. The first chunk carries at least 6 or 7 styles: BPM, key, era, instrumentation and "instrumental".
- Be generous with negatives ("vocals", "abrupt ending", "cut off").
- Add an explicit ending chunk ("final held chord rings out, natural decay to silence").
- Set `store_for_inpainting: true`. Make masters at `pcm_48000` (audiogen's music default is `mp3_44100_128`).
- Cut loops at bar lines and encode to Ogg Vorbis for Godot.

**Adaptive score:**
- Generate one full-intensity track and separate it into stems. Build layers from sums of stems and play them with `AudioStreamSynchronized` (up to 32 streams in sync).
- Never prompt each layer separately; that was the L20 hold-layer problem.

**Godot formats (4.7 docs):**
- WAV for short, repeated SFX (loop begin and end in samples). Ogg Vorbis for music, speech and long effects (loop offset only, forward only). Godot suggests MP3 mainly for CPU-limited mobile and web targets; the repo ships MP3 for Host and story voice today, so a format change is a separate, measured decision.
- The BPM, beat count and bar beats import fields are "currently unused", so check any bar-synced transition by ear.

**Provenance:** record `request-id`, `song-id`, character cost, model, seed, plan and voice id for each item in `audiogen-manifest.json`. Committed SFX and music ship with that manifest (Nick, 2026-10-23).

### 3.3 QA gates (Gate B for audio, `lore-gate.md` 11.4)

1. **Register** matches the speaker's row. The Host never explains. Latch gets no battle-unit filter. NODS read Articles only.
2. **Words** match the approved caption and the localised source exactly. Voiced Host calls come from the tracked plan list (FIRST BLOOD, TRIPLE FRAG, QUAD FRAG, RAMPAGE, FLAG CAPTURED, CHARGE PLANTED, SUDDEN DEATH and the rest), with no puns; caption-only calls are never voiced.
3. **Voice provenance** is recorded. No default voice for a lasting role.
4. **Offline processing:** declip, remove DC offset, trim silence, normalise to the K50 loudness ladder (`sound-pass-20261002.md`), and keep peaks at or below -1 dBTP. Treat every raw SFX take as too hot.
5. **Music:** no silence at the start, no ending cut off at full level, and loops checked across the seam in the engine.
6. **Tells** land on the windup, have a caption, and sound distinct from the other tells in the same encounter.

---

## 4. Lore and design consistency gate

The full gate is in [`lore-gate.md`](lore-gate.md) and the brief template in [`brief-template.md`](brief-template.md). The same questions are asked twice:

| Gate | When | What passes |
|---|---|---|
| **A. Brief** | Before any `gen`, `meshy-gen`, `batch`, `design` or `tts` | A filled brief: faction, place, level, period check, **at least two canon quotes**, palette keys by role, reserved-colour check, silhouette at 30, 15 and 5 m and against whatever stands next to it, **per-object dimensions (W × D × H) and how many objects fill the slot**, marks (blank), parts and pivots, states, references, **integration slot**, cost ceiling, and Nick gate. An empty canon field, an empty slot or missing dimensions fails. |
| **B. Candidate** | After every stage: image keeper, raw GLB, textured GLB, prepared asset, measured audio | The checklists in `lore-gate.md` section 11, judged at play size, in the target light, in motion. |

Verdicts are PASS, FIX PROMPT, REDO, or HOLD FOR NICK (a stop, not a failure). A generation never creates canon: "Approve and record the reference before producing sets" (`cast.md`).

**Ten hard rules.** Any failure stops the asset. Sources are quoted in `lore-gate.md` section 1.
- **H1:** allegiance reads from canon, not arbitrary colour. Every subject declares Union, free human, free agent, Inheritance restoration, absorbed bot, league (no side), or neutral or civic.
- **H2:** reserved combinations (`ART_STORY_BIBLE.md`, faction readability contract).
  - Black plus red livery is Union only.
  - A matte off-white dominant base is Inheritance only.
  - Red emissive light is Union only, and is the Union attack tell light.
  - Cyan working light is Inheritance and absorbed bots only, muted `#4A8A92`, never neon. Exceptions in canon: navigation equipment (`space.md`) and small painted, unlit accents.
  - Free personal light is warm: amber, warm white, CRT phosphor.
  - "Black alone, red alone, cyan or bone as small painted accents remain allowed."
- **H3:** no generated lettering. Ask for blank plates and seal bosses; text goes on as in-engine decals with i18n keys, level, never tilted.
- **H4:** nothing real: no real insignia, salutes, uniforms, flags, national kit, brands, copied weapon or vehicle models, broadcasters, people, imitated voices or protected emblems.
- **H5:** practical retro-futurism, campaign around 2070.
- **H6:** fun outside, serious underneath. Captive suffering and deaths are never punchlines; Union cruelty is bureaucratic, never gory; menace from order, never spikes or skulls.
- **H7:** combat against Inheritance machines only in levels 18 to 20 and Wipe. Levels 16 and 17 may carry signs, never a fight.
- **H8:** stylized pixel craft, not photographs.
- **H9:** named people keep their established look.
- **H10:** the free side narrates. The Union's own words appear as signs, forms and addresses, "never as the narrator". Union human troops may still call short tactical orders and bots use procedural fragments (`ENEMIES.md`); no constant banter.

The rule underneath them all (`ART_STORY_BIBLE.md`): "Location supplies material and light; faction supplies manufacture and marking."

**Always HOLD for Nick:** enemy sheets and model picks, any named person, the Union seal and emblems, story stills, crowd poses, Edda's lamp, voice casting, music, and anything marked as a proposal.

**Open proposals that block specific work** (`lore-gate.md` section 12):

| # | Decision | Blocks |
|---|---|---|
| P1 | Latch: warm mid values, bone kept under about a third of the body, a warm screen face | Any Latch asset |
| P2 | Absorbed bots keep the tell's shape, timing, sound and caption, with cyan replacing red in the same spot | Absorbed variants |
| P3 | Reword "future-cowboy" in `CAMPAIGN.md` to match the Oct 4 hatless-workwear direction | The main human |
| P4 | Fixed Union machinery: the place supplies the material, the Union supplies only markings | M7 foundry machines, and the Union red-accent check on fixed plant |
| P5 | Red lamps on Union fixtures stay unlit | M7 bank, fixtures |
| P6 | Narrator: finish every River line before 12-31, or design a narrator voice we own and re-record | All narration |
| P7 | The Union accent colour | Union props and equipment |
| P8 | Sorrel's body after correction | Sorrel |
| P9 | Score identity | Music beyond the radio stations |
| P10 | Add league, civilian and utility colour families to `palette.json` | Larak Lot props, and any prompt with invented hex codes |
| P11 | Wall colours in the wipe levels, so Inheritance machines stand out | L18 to L20 surfaces |
| P12 | The Union seal (candidate seal_c risks reading as a religious symbol) | Seal, decals |

Two more issues:
- The growth rack and recycler in the M7 bank spec paint free Martian panels in the exact Inheritance indicator swatch (`#4A8A92`). Painted cyan is allowed on free objects, but pick a different teal so the one canon cyan stays the machines' signature (minor, FIX PROMPT).
- `docs/plans/meshy-assets/*` briefs such as `e-locomotive.md` name no faction and no per-object dimensions. They need the template fields before their next paid stage. `c-paver.md` also has an open design conflict (below).

---

## 5. Tool changes, prioritized

Effort: XS is under an hour, S a few hours, M a day or more. Every change lands with fake-transport tests; no test calls a paid service. Rust and GDScript only.

### P0: before the next paid batch

| # | Tool | What | Why | Effort |
|---|---|---|---|---|
| 1 | spritegen | A `usage` subcommand that calls the free `GET /models/usage` (with `expand=auth_method`). Record it before and after every batch. | Real reconciliation instead of "balance unverifiable". | S |
| 2 | spritegen | `Idempotency-Key`: a UUID per frame, written into the Reserved event before sending. On a timeout, 5xx or 429, resend the identical body with the same key; a replay returns the original `request_id` without a second charge. A 422 mismatch is a hard stop. | The docs present the key for exactly this case (unsure whether a request was accepted) and say to create it before each request and store it with the job. It clears most uncertain holds without risking a double charge. | M |
| 3 | spritegen | 429 `account_queue_full`: "nothing is created or charged"; wait `Retry-After`, resend with the same key. 503 `admission_control_unavailable`: retryable, but the docs do not say nothing was created, so resend only with the same key (safe either way after #2). | Holds are released correctly and fewer runs stall. | XS |
| 4 | spritegen (meshy.rs) | Allow `ai_model: "meshy-t2.5"` with a target of 100 to 30,000, priced at 15 (20 at 8k). Strip the same fields as t2 (`geometry_resolution`, `should_remesh`, `topology`, `image_enhancement`) and never send `remove_lighting`. Keep the t2 15,000 rule. Raise the 7.1 remesh bound only if needed (API allows up to 300,000; tool allows 50,000). | Needed for the t2.5 pilot and, if it passes, the hard-surface route. | S |
| 5 | spritegen (meshy.rs) | A `kind: "multi_image"` stage: `POST /openapi/v1/multi-image-to-3d` with 1 to 4 `image_urls` (front first), optional `texture_image_urls`, `geometry_resolution` standard or 2k only, the same price table. | Constrains depth and the back at no extra credit cost. | S |
| 6 | spritegen | A free proportion preflight: measure the keyed front (W:H) and side (D:H) silhouettes against the brief's per-object dimensions and refuse any Meshy stage outside the tolerance. | Would have stopped the Paver and the growth rack before 30 to 35 credits each. | S |
| 7 | spritegen (meshy.rs) | Send `multi_view_thumbnails` and `alpha_thumbnail` on new stages and download them. Send `save_pre_remeshed_model` for hero 7.1 assets. Require `pose_mode` `a-pose` or `t-pose` on any image stage that feeds a rig stage. Refuse a rig or animation stage whose source task is older than 3 days, or switch it to `model_url` with our stored GLB. | Free review evidence, the rig's preconditions and the retention window enforced in code. | S |
| 8 | audiogen | Record the `request-id`, `song-id` and character-cost headers for each item in the manifest. | Continuity, inpainting and cost reconciliation. | XS |
| 9 | audiogen | TTS and dialogue fields: `similarity_boost`, `seed`, `language_code`, `apply_text_normalization`, `previous_text`/`next_text`, `previous_request_ids`/`next_request_ids`, and pronunciation dictionary locators. Keep `eleven_v3` as default until the v4 A/B, then switch. | Consistent voices and pronunciation across hundreds of lines. | S |

### P1: before the November rounds

| # | Tool | What | Why | Effort |
|---|---|---|---|---|
| 10 | spritegen (meshy.rs) | A `kind: "animate"` stage: `rig_task_id`, 1 to 10 `action_ids`, optional `change_fps`. Download the animation GLB. | At 3 credits per clip, each humanoid role gets a full set. | S |
| 11 | `tools/prepare_model_candidates.gd` | Accept multi-part or multi-island meshes. Split into connected pieces, match pieces to the brief's moving parts, and emit named pivots. | Wheels, work heads, iris, optics, Walker joints. | M |
| 12 | `tools/prepare_model_candidates.gd` | Turn the existing receipt fields into verdicts against the brief: per-object proportion (`worst_log_mismatch`), texel density, boundary and non-manifold edges, faction colour. Add the one new measurement, baked-lighting variance in the base colour. Fit against per-object brief dimensions, not area solids. | Makes section 2.4 a gate rather than a reading. Most of the measuring already exists. | S |
| 13 | audiogen | Music items: `composition_plan`, `seed`, `store_for_inpainting`, `/v1/music/detailed`. A `stems` command. An `inpaint` item (keep and regenerate ranges, `conditioning_ref`, upload of an existing take). `pcm_48000` masters. | Clean endings, retakes of single sections, aligned layers. | M |
| 14 | audiogen | A per-item SFX `model` (`eleven_text_to_sound_v2` or `_v3`). Accepting `wav_*` is optional, since PCM is already wrapped into WAV locally. | For the v3 pilot. | XS |
| 15 | spritegen | A Gate A check on each spec: it must point to a brief that names faction, place, canon quotes, per-object dimensions and integration slot. Reference roles must appear in the prompt. Flag off-palette hex codes, and check reserved-colour words against the faction. | Puts the lore gate into the tool, not only into prose. | S |
| 16 | spritegen | An nsfw stop records `Stopped(nsfw)` and the remaining frames continue. Record `X-Correlation-ID`, `expires_at` and `expires_after`. | One refusal no longer needs a new spec, and support gets the evidence it asks for. | XS |

### P2: when useful

| # | Tool | What | Why | Effort |
|---|---|---|---|---|
| 17 | spritegen (meshy.rs) | `uv_unwrap` and `retexture` stages (`enable_original_uv`, meshy-6 `remove_lighting` at 2k or 4k) | Rescue kept 7.1 meshes | S |
| 18 | spritegen | A budget gate for token-priced Flare and Sunburst: reserve a conservative upper bound per image, then reconcile from `/models/usage` | Required before any use of the 2.5 models | M |
| 19 | spritegen | Submit Higgsfield requests concurrently up to a set limit (after #2) | Saves time only; excess requests are queued, not rejected | M |
| 20 | spritegen | Replace the probes that now return 404 (`meshy_v7_image_to_3d`, `tripo_h3_1_image_to_3d`) in `api-capabilities.json` | Accurate capability checks | XS |

### Docs to correct (no code)

- **`docs/plans/asset-round-20261023.md`** (and the ignored ledger): Higgsfield funds expire one year after deposit (line 103); actual Higgsfield spend per `/models/usage`; Meshy at 15 usable until 11-03; the ElevenLabs remainder.
- **`docs/plans/higgsfield-pipeline.md`:** line 23 ("about four in flight ... returns HTTP 400 ... no Retry-After") is stale: excess requests are queued, a full queue is 429 with `Retry-After`, admission failure is 503. Add idempotency keys, the usage endpoint, 7-day retention, a 1k, 2k and 4k price table with reference surcharges, and the newer models.
- **`docs/plans/meshy-pipeline.md`:** t2.5, Multi-Image, animation, the 3-day retention, the deprecations, the route table (section 2.2) and the Gate B verdicts.
- **Voice records:** once Nick approves a cast, record voice id, model, settings and seed per role in the audiogen manifest and `docs/plans/audiogen-voice-design-20261023.md`, and the approved identity in `docs/design/characters.md` (there is no `docs/lore/characters.md`).
- **`docs/plans/meshy-assets/*`:** per-object dimensions and faction in every brief.

---

## 6. The next asset round: what to do differently

In order. Steps 1 and 2 cost nothing.

1. **Reconcile.**
   - Nick reads the Higgsfield API console balance for this key.
   - Run the free `/models/usage`, `meshy-check` and `audiogen quota`, and correct the ledgers.
   - Release the two H-1a nsfw holds ($0.06) as uncharged: the docs say nsfw is not charged, and the analytics count excludes them.
2. **Free re-fit of this round's candidates.** Re-fit every GLB that was fitted against a multi-object or area slot to a per-object intended size, as M-LL did. Several will likely pass without a paid re-run (the turnstile, at 0.82 × 1.1 × 1.08 m, is a plausible single unit in a 16 m row). Then ask Nick the blocking questions (section 4 table and section 7).
3. **Land the P0 tool changes**, then the P1 Meshy and audio stages, before the Meshy reset on 2026-11-03.
4. **Higgsfield, consistent sets built from references** (possible now, about $27 usable).
   - One style board per place and one anchor per subject, at medium 2k.
   - Then separate view and state edits of the anchor, with reference roles and invariants in every prompt.
   - Proportion-check the front and side views against the per-object brief before anything goes to Meshy.
5. **Meshy after the reset: re-run only true failures.**
   - The Paver needs a design answer first (Q5), then a new reference; Meshy reproduced the low sledge it was given.
   - Real Meshy defects: custody housing (topology), locomotive v1 (UVs), and any subject still failing proportion or texel density after the free re-fit.
   - Pilot t2.5 on two hard-surface subjects (30 credits) before routing others through it. Fall back to 7.1 Multi-Image (30 or 35) where depth or the back fails.
6. **Humanoid characters and enemies:** 7.1 Multi-Image in A-pose, then a rig (5) and a clip set (18 to 24) within 3 days. The same source feeds both the live-3D and baked-sprite trials. Non-humanoid enemies use local pivots.
7. **Audio (before 2026-11-06 for this allowance).**
   - Recast first: owned voices for the Host and the narrator (Nick casts them), then A/B v3 against v4 on 10 lines each.
   - Regenerate only the plain Host calls.
   - Pilot SFX v3 on the six worst shipping cues (Rocket blast, Repeater, CTF): 2 models × 2 takes, through the existing offline processing.
   - Repair E-15 endings by inpainting (upload the take, regenerate the ending chunk) where the plan allows; otherwise redo with composition plans and explicit endings.
   - Rebuild the L20 hold layers from the stems of a single track.
8. **Gate B and integration evidence for every keeper:** play size, target light, in motion, beside an approved asset, with screenshots as `AGENTS.md` requires. AGENTS.md authorizes credits only for assets that will be integrated and visible; a pilot whose output is not meant to ship needs Nick's written approval.

**Budget sketch** (prices from the 2026-10-24 estimates; verify before each stage):
- **Higgsfield:**
  - A four-view set costs about $0.52 to $0.63 per subject at medium 2k with references.
  - An optional model pilot is about 12 images: under $2, plus Flare's token cost.
- **Meshy (November allowance):**
  - t2.5 pilot 30; true-failure re-runs 30 to 35 each; most of this round's other candidates need no credit.
  - Each humanoid role costs about 53 to 64 credits (30 or 35, plus 5, plus 18 to 24).
- **Audio:** recast and A/B first, keep music retakes to inpainted sections.

---

## 7. Questions for Nick

1. What does the Higgsfield API console show for this key's balance? We estimate about $27. When were the funds added?
2. Narration and Host voices:
   - Finish River before 12-31, or design a narrator we own and re-record everything (P6)?
   - For the Host: Wyatt, or a designed Host?
3. Do you approve the pilots, given that not all of their output will ship?
   - The image model pilot: about 12 images, under $2 plus Flare's token cost.
   - The SFX v3 pilot: about 24 short takes on shipping cues.
   - The t2.5 pilot: two hard-surface subjects, 30 credits, after the reset.
4. Do you agree with the polycount targets, the tiered image-quality rule and the proportion tolerances? All are proposals.
5. The Paver: `c-paver.md` describes a "broad restoration machine with substantial work head", while L19 fights it in the ordinary 1.8 m fighter volume. Should it stay a broad, low machine with its own shot and contact volume (the Assessor precedent), or be redrawn upright to fit the fighter volume?
6. Proposals P1 to P12 in `lore-gate.md` section 12, especially P4, P5, P7, P10 and P12, which block specs that are already written.
