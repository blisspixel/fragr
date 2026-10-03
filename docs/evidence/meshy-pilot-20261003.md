# October 3 model production pilot

**Status:** native pipeline implemented and tested; model production and rendered
inspection proven for the pilot. Runtime art acceptance remains open.

## Account and production

Nick selected Premium and configured `meshy` in the ignored root dotenv.
The native free checker authenticated and reported 3,100 available credits,
zero local holds and sufficient allowance for a 150-credit pilot. It submitted
no generation jobs. The pipeline checks the whole fresh batch and then the live
account immediately before every paid stage, holding unresolved reservations.
It reserves durably before submission and never retries a POST automatically.

Three textured 7.1 models at 35 credits each and a 5-credit humanoid rig completed.
A topology comparison initially returned HTTP 400; its request included an
image-enhancement option documented only for standard models. The tool stopped
and retained the 15-credit reservation. A separately identified corrected Shotgun
request omitted that option and completed for 15 credits. The later generator
comparison was not submitted. Do not erase the unsuccessful request history or
call a conservative reservation an actual charge.

The final live account probe reported **2,975 available credits**, matching
**125 net credits consumed**, with **15 additional credits held locally**.
Total reservations are 140 credits, within the pilot's 150-credit allowance.
The conservative valuation is $0.02 per credit, $2.80 reserved versus $2.50 for
reported consumption. Those are budget equivalents, not new cash charges.
No additional purchase, overage or automatic top-up was enabled.

## Imported geometry and materials

Godot 4.7.2-stable imported and rendered seven GLBs on the Radeon 780M through
Compatibility. This is hardware renderer evidence, not an FPS benchmark or
cross-platform performance proof. Each output carries embedded 4K albedo, normal,
metallic and roughness maps. Four cardinal views were rendered for each file.

| Candidate | Triangles | Skin and motion | Current verdict |
|---|---:|---|---|
| Clerk, 7.1 | 12,476 | Static source, followed by a 24-bone rig | Coherent human silhouette, visible face and issued green cloth/bone armor. Worth continued production; fingers, combat poses and final cloth shading need review. |
| Clerk rig | 12,476 | Rest output, 1.067 s walking clip, 0.667 s running clip | Walking and running visibly deform the mesh. Armed actions, reactions, seated M02 posture and death are still missing. |
| Shotgun, 7.1 | 11,727 | One mesh, no animation | Useful wood/steel silhouette, but close-up finish and separate pump/hand mechanics are unfinished. |
| Shotgun, corrected topology | 12,853 | One imported mesh, no animation | Cleaner surface candidate in reviewed views. Imported node count does not establish usable separate mechanical parts. |
| Yard generator, 7.1 | 11,224 | One mesh, no animation | Recognizable worn industrial machine; dense small features and rear geometry need cleanup and a game-scale check. |

The requested face count was 12,000. Actual counts differ, so budgeting must use
imported geometry. Models are candidates, not selected runtime replacements.
Generation success does not prove animation suitability, visual coherence under
venue lights, a completed first-person weapon or a populated campaign.

The initial inspection framed skinned assets from static mesh bounds and produced
empty rig images. Those images were rejected during review. The corrected tool
computes posed skin bounds through bone transforms, verifies weight layouts and
rejects nearly empty renders. Only the corrected pass supports the motion claims.

## Review images and durable receipts

These are offline model inspections, not gameplay screenshots:

- [Clerk rest view](../screenshots/meshy-pilot-20261003/clerk-rig-0-view-0.png)
- [Walking pose](../screenshots/meshy-pilot-20261003/clerk-rig-1-motion-1.png)
- [Running pose](../screenshots/meshy-pilot-20261003/clerk-rig-2-motion-2.png)
- [Standard Shotgun](../screenshots/meshy-pilot-20261003/shotgun-model-0-view-0.png)
- [Topology Shotgun](../screenshots/meshy-pilot-20261003/shotgun-topology-corrected-0-view-0.png)
- [Yard generator](../screenshots/meshy-pilot-20261003/yard-generator-model-0-view-0.png)
- [Import counts, source hashes, material maps and animation lengths](../screenshots/meshy-pilot-20261003/inspection.json)

Raw original models and the locked request ledger remain under
`art/raw/meshy-pilot-20261003/`, outside desktop exports. They retain provider
metadata privately. Public previews contain no software-authorship metadata.
Preserve required legal notices when preparing source models for public acceptance.
The API's three-day retention is not a backup; keep locally downloaded outputs.

Native receipts and logs are in `.agents/art-playthrough-20261003/`:
`meshy-native-check-20261003.json`, `meshy-pilot.log`, `meshy-pilot-finish.log`,
`meshy-topology-corrected.log`, `meshy-pilot-balance-final.json`,
`meshy-inspection-skinned.log` and its `inspection.json`. No credential is recorded.

## Verification and next acceptance

Offline transport tests cover balances, caps, per-stage rechecks, pending holds,
uncertain submissions, request identity, resume without POST, output URLs, GLB
framing, malformed responses, consumption receipts and price drift. CLI tests
cover refusal before loading secrets and binding each credential to its own origin.
Workspace tests, warning-denied linting, the locked release build, dependency
license checks and the deterministic benchmark pass. The full unfiltered
workspace coverage pass reports 93.72 percent of lines for the initial pipeline;
final CI remains the merge gate for subsequent corrections.

The [production plan](../plans/meshy-pipeline.md) owns this pipeline. Continue the
existing roadmap's art rung with model cleanup, owned combat motion, controlled
pixel bakes or live model presentation, grounded scale and foot registration,
embedded material budgets and inspected mission play. Keep the three finished
API categories distinct from a finished roster or campaign. The v0.68.0 playthrough
records the earlier integrated art and does not display these new candidates.
