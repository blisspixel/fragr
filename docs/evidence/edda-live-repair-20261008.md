# Edda retained source repair

Status: implemented locally, 2026-10-08. The existing named walking source now
has a bounded skin repair, compact matte maps and inspected offline motion.
This receipt accepts source preparation only. Runtime selection and ordinary
eligible/omitted mission appearances require their separate integration gate.
No paid requests, credits or cash were used. Owning
[plan](../plans/edda-live-repair-20261008.md),
[machine receipt](edda-live-repair-20261008.json), and
[historical rejected source](named-cast-source-production-20261005.md).

## Source and repair

The retained raw file is
`art/raw/meshy-pilot-20261003/edda-named-v1-rig-1.glb`, SHA-256
`bb5511f280147bb3f4fa81db6ce1b42a58cb10daebdf486def6a807d3286693f`.
It retains 17,561 vertices, 14,694 triangles, 24 joints and the original
`Armature|walking_man|baselayer` clip (1.066666603 seconds).

The original fingers and wrists incorrectly shared substantial leg influences.
A previously retained private region-only repair removed the finger fin but
split coincident wrist vertices by up to 0.213551 m. Closing only those seams
moved deformation into a sleeve or bag boundary, so those attempts were rejected
and retained. The accepted repair solves a continuous skin field on welded
source positions around the inspected satchel, strap, apron transition and both
forearms. Actual source paint and anatomy supply the seed hints. The upper strap
transitions back into its original skin; other body weights remain frozen.

The candidate is `client/art/models/candidates/edda.glb`, 4,895,504 bytes,
SHA-256 `cbf1e1e16329da194fdf058f308676e72bfefb357faeea915fc3d9500d57ea40`.
The reconstructed skin-only raw container hashes to
`7e7c10d1f0ee39a6836bb900e5b4d2630a1d5233910cc1a7c04a033c61884a56`.
Exactly 5,387 vertices have changed joint/weight bytes; 12,174 retain those bytes
exactly. All position, normal, tangent, UV, index, bind and animation payloads
remain exact. The independent audit checked 73 unchanged binary views and 1,775
edited coincident groups. Weights are finite, valid against all 24 joints and
normalized, with maximum sum error 0.000000117347.

Three opaque 1,024-square RGB8 PNG maps retain source paint and normal detail.
Only packed roughness green is bounded to at least 224/255; metallic and roughness
factors are 0.08 and 1.0. Texture locations and double-sided state remain intact.
The raw source has no copyright field; no legal notice was removed.

## Checks and measured limits

Every unique indexed edge and 10,206 coincident pairs was measured at 64 off-grid
walking phases, `(sample + 0.37) / 64`. These are diagnostic deformation ratios,
not a blanket claim that every cloth edge is rigid or unstretched.

| Source | Whole maximum edge ratio | Maximum on the final edited edge set | Maximum coincident gap |
|---|---:|---:|---:|
| Original walking source | 84.974944 | 84.974944 | 0 m |
| Historical private v4 repair | 20.419616 | 20.419616 | 0.213551 m |
| Final compact candidate | 8.341501 | 7.657284 | 0 m |

The original 1.134 mm fingertip edge became 96.354 mm during walking. Its final
maximum is 1.134 mm, ratio 1.000079. The final whole-source maximum is the
unchanged lower-apron edge: 3.414 mm becomes 28.480 mm, with exactly the original
weighted points. The edited maximum remains at a small bag/apron transition,
2.676 mm becoming 20.489 mm. This local deformation and inherited cloth folds
remain explicit limits even though the inspected controls show no original
large fin, detached wrist or broken strap.

Focused source validation passed exact payload checks, valid skin, untouched
skin outside conservative inspected bounds, actual 1.8 m rest scale and 20
weighted rest/calm/off-grid-walk/crouch/fallen controls. UV movement, reversed
winding, an altered unaffected weight, an invalid joint and the original
unrepaired skin are rejected negative controls. Actual weighted geometry is
registered to the floor. Resting wrists reach Right (-0.27, 0.97, 0.08) m and
Left (0.35, 0.97, 0.08) m; the left resting wrist stays outboard of the satchel.
The earlier unreachable 0.96 m targets and validator failure are retained.

The independent source audit and the final renderer both passed with numeric
exit 0 and clean logs. The renderer retired normally. Sixty-two controls cover
original/prepared front, sides, back and head views under neutral, dim and
clinic-like light, 16 retained walk frames from opposite angles, 12 resting views
and four crouch/fallen views. All walking, resting and crouch/fallen originals
were inspected at 1,024 x 768, together with selected head originals; the
overview covers all non-head views. The machine receipt identifies the exact
full-size inspection set.

Observed renderer: Godot 4.7.2-stable, Compatibility, OpenGL3, AMD Radeon(TM)
780M. This is local visual evidence, not a frame-rate, other GPU or final-art
claim. Individual fingers, hand-to-bag contact, treatment gestures and facial
animation are not accepted by these controls.

## Reproduction and retained evidence

Run from the repository root with the pinned Godot console executable:

```powershell
$godot = 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe'
$eddaRaw = 'C:/GitHub/fragr/art/raw/meshy-pilot-20261003/edda-named-v1-rig-1.glb'
$eddaCandidate = 'C:/GitHub/fragr/client/art/models/candidates/edda.glb'
$eddaEvidence = 'C:/GitHub/fragr/.agents/edda-live-repair-20261008'
& $godot --headless --path client --script ../tools/prepare_edda_source.gd -- $eddaRaw $eddaCandidate "$eddaEvidence/preparation-final"
& $godot --headless --path client --editor --quit
& $godot --headless --path client --script ../tools/validate_edda_source.gd -- $eddaRaw $eddaCandidate "$eddaEvidence/validation-final.json"
& $godot --headless --path client --script ../tools/audit_edda_skin.gd -- $eddaRaw "$eddaEvidence/final-edge-audit.json" $eddaCandidate 'C:/GitHub/fragr/.agents/named-cast-mechanical-preparation-20261005/.agents/edda-repair-v4/edda-walk-repaired.glb'
& $godot --path client --rendering-driver opengl3 --windowed --script ../tools/preview_edda_source.gd -- $eddaRaw "$eddaEvidence/preview-frozen"
```

The private historical v4 input is optional for reproducing the original/final
comparison; omit that last argument when it is unavailable. Final preparation,
validation, complete edge maxima, independent audit, renderer controls, numeric
process receipts and all failed experiments are hash-bound in the machine
receipt. Tool sources and `.gd.uid` for the project adapter are included. The
final preparation uses no ignored-source dependency.

Representative originals:
[resting front](edda-live-repair-20261008/neutral_prepared_calm_0.png),
[dim side](edda-live-repair-20261008/dim_prepared_calm_1.png),
[walk](edda-live-repair-20261008/neutral_prepared_walk_0_6.png),
[opposite walk](edda-live-repair-20261008/neutral_prepared_walk_1_6.png),
[crouch](edda-live-repair-20261008/clinic_prepared_crouch_0.png),
[fallen](edda-live-repair-20261008/clinic_prepared_fallen_0.png),
[head](edda-live-repair-20261008/neutral_prepared_head.png),
[overview](edda-live-repair-20261008/overview.png).
