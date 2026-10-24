# Meshy: current practice vs fragr pipeline (checked 2026-10-24)

Read-only research. No paid calls. One free call: `GET /openapi/v1/animations/library`
(saved beside this file as `meshy-animation-library-20261024.json`, 678 clips).

## Primary sources (all fetched 2026-10-24)
- Image to 3D API: https://docs.meshy.ai/en/api/image-to-3d
- Multi-Image to 3D API: https://docs.meshy.ai/en/api/multi-image-to-3d
- Text to 3D v2: https://docs.meshy.ai/en/api/text-to-3d
- Pricing: https://docs.meshy.ai/en/api/pricing
- Changelog: https://docs.meshy.ai/en/api/changelog
- Rigging: https://docs.meshy.ai/en/api/rigging-and-animation
- Animation + library: https://docs.meshy.ai/en/api/animation
- Text to Motion: https://docs.meshy.ai/en/api/text-to-motion
- Remesh: https://docs.meshy.ai/en/api/remesh ; Resize: https://docs.meshy.ai/en/api/resize
- Retexture: https://docs.meshy.ai/en/api/retexture ; UV Unwrap: https://docs.meshy.ai/en/api/uv-unwrap
- Auto Split: https://docs.meshy.ai/en/api/auto-split
- Webapp Image to 3D: https://docs.meshy.ai/en/webapp/image-to-3d
- Help: better image-to-3D results (2026-08-19): https://help.meshy.ai/en/articles/15723519
- Help: character pose/face/hands (2026-08-15): https://help.meshy.ai/en/articles/16102152
- Multi-view tutorial (2026-09-08): https://www.meshy.ai/tutorials/multi-view-image-to-3d
- Low-poly: generate or decimate (2026-09-29): https://www.meshy.ai/topics/ai-low-poly-generate-or-decimate

## Key dated facts
- 2026-09-18 meshy-7.1 (`latest`), `geometry_resolution` standard/2k/4k (4k single-image only).
- 2026-10-15 `meshy-t2.5` Smart Topology: default smart-topology model, "sharper detail for game
  assets", triangles only, target_polycount 100-30,000 (default 15,000). Same price as t2 (15 textured).
  Not on Multi-Image.
- 2026-10-30 `lowpoly` model_type retires. meshy-7 deprecated. symmetry_mode has no effect (since 05-11).
- 2026-10-23 rigging `texture_image_url` deprecated.
- 2026-09-02 Animation `action_ids` up to 10 per request, 3 credits each, one file many clips.
- 2026-09-04 free `GET /animations/library`.
- 2026-08-21 Text to Motion: prime 10 (FBX), swift 3 (BVH), 2-10 s, biped only.
- 2026-09-28 rate-limit headers incl. Retry-After.
- remove_lighting: honoured only by meshy-6 (7.1 accepts and ignores).

## Prices (credits)
Image/Multi-image 7.1 textured 2k/4k 30, 8k 35, Ultra geometry +5; t2/t2.5 textured 15 (image only);
mesh-only 7.1 20, t2.x 5. Text-to-3D preview 20 (7.1) / 5 (t2.x), refine 10. Retexture 10.
Remesh 5, UV Unwrap 5, Resize 1, Convert 1, Auto Split 10. Rig 5. Animation 3/action. Motion 10/3.

## Evidence from our own outputs (client/art/model-candidates/*.glb.json, raw GLBs)
- All 52 round GLBs: 1 mesh, 1 primitive, doubleSided, normal + metal/rough + base colour, 5-15k tris,
  raw longest side ~1.9 units (provider-normalised; we rescale from briefs).
- Proportion drift vs brief/slot (fill ratio per axis): turnstile 0.41/1.0/0.07, growth-rack 0.15/1/0.26,
  recycler 0.34/1/0.17, ingot-trolley 0.33/1/0.24, luggage-scanner 0.23/1/0.38, recall-car 0.28/1/0.63,
  custody-housing 0.42/1/0.45, ship-bunk 1.05/3.68/1.14; Paver both candidates 0.55 m x 1.9 m vs 1.5 x 4 m brief.
- UV: coverage 0.48-0.62 (40-50% atlas wasted); vertices / welded positions 3-5x (heavy seam splits).
  locomotive v1 uv coverage 0.00 (broken). 2026-10-04 Smart Topology Pistol/Rifle: ~1.06 verts/tri,
  55-61 separated islands in one mesh, vs 7.1 remesh 1.5-2.2 verts/tri.
- Topology: custody-housing 806 open / 1229 non-manifold edges; growth-rack 423/383; recall-car 319/414.
- 6 Union subjects lost the restrained red accent through generation + palette lock.

## Gaps (ranked)
1. Single-image only. Multi-Image to 3D costs the same (30 / 35) and constrains depth and the back.
2. Smart Topology path pinned to meshy-t2 <=15k; meshy-t2.5 (30k, game-detail) not allowed.
3. No Animation stage; rig keeps only walk/run. Library has death, hit, reload, shoot-walk, idle clips.
4. Baked lighting risk: ART-GENERATION-SPEC says albedo only; 7.1 ignores remove_lighting.
5. UV layout wasteful for 32 texel/m nearest paint; no UV Unwrap/Retexture(original UV) route.
6. Pre-paid proportion gate missing: reference silhouette aspect is not checked against the brief before spend.
7. Free review aids unused: multi_view_thumbnails, alpha_thumbnail, save_pre_remeshed_model.
8. pose_mode "" used on the Collector biped; any rig candidate must be a-pose/t-pose, +Z facing.
9. Part separation: 7.1 API has no Split (webapp only); our importer rejects multi-mesh GLBs; t2.x
   islands in one mesh are the API-native route.
Balance note: ~300 credits on 2026-10-24 with M-LL taking 270; resets 2026-11-03 20:34 UTC.
