# Stylized Sweeper source and poses

Status: **implemented**, 2026-10-04. Base: main `a8611d04`.

Integrate the reviewed angular dark-steel/red bot body into the existing standing
character bake. The current articulated source remains the comparison, not a
finished-art claim. The replacement needs physical two-handed rifle grip,
readable authoritative attack/recovery phases, a real gait, unarmed melee and a
settled corpse at the same registered feet and direction cells.

## Source and ownership

The selected raw body has 12,458 triangles. Its three rig outputs are under
`art/raw/meshy-pilot-20261003/sweeper-stylized-v2-rig-{0,1,2}.glb`.
Inspect actual animation names before selecting the walking source. The root
owns the paid stages, ledger, source reference and optional-cast extension to
`tools/prepare_clerk_source.gd`. This lane makes no paid calls. Use the existing
native preparation seam for embedded nearest 1K maps and retained skin/walk;
preserve required copyright while removing forbidden public authorship metadata.

Own the Sweeper source/presentation tests, prepared candidate, standing bake
receipt and selected outputs, plus this unique plan/evidence. Keep other cast
atlases and their acceptance separate. Shared README, roadmap, changelog, index,
integration and release remain with the root.

## Implementation and acceptance

Selected walking rig: output 1, actual `Armature|walking_man|baselayer` clip.
Native preparation yields a 1.8 m, 24-bone skin with embedded nearest 1K maps.
The shared virtual Clerk loader is the root-owned dependency `a48fd5b4`.
Keep the historical mechanical Sweeper source/export unchanged; its rifle mesh
is reused by the new `sweeper_skinned_source.gd` directional source.

Pose inspection corrected the support wrist to cup the foreend. The supplied
rig has no finger bones, so fingers cannot independently close around the grip.
Existing silhouette gates initially rejected a 44-pixel front outline beside
the Clerk's 45-pixel rest and 51-pixel aim. A reviewed 1.38 horizontal source
calibration gives a 61-pixel issued-bot outline at both rest and aim, retaining
1.8 m height, fixed camera/sprite scale, exact rifle anchors and unchanged
authoritative collision. Front, side and terminal corpse are inspection gates.

Use `bake.gd -- --kind sweeper` for this bounded replacement. The no-argument
all-cast bake remains available. Retain the accepted Clerk, Heavy and Turret
PNG bytes; the receipt names rendered and retained roles and preserves prior
receipt sources/hash. A first all-cast bake changed decoded pixels on this
renderer, so its log is retained privately as a failed scope attempt and its other
cast outputs are not selected. Include the embedded-source import preset in
freshness checks. No standalone extracted texture files are needed.

Measure the prepared skeleton, rest transforms, body bounds and unit conversion.
Reuse the Clerk's deferred-ready posing, root-motion-free walk sampling and
two-bone arm mathematics where appropriate. Its centimetre hand targets and
one-handed pistol pose are not a Sweeper rifle solution. Pose both hands around
a stable carried/shouldered rifle, with recoil and recovery preserving grip.
Keep the gun absent in finite-equipment melee and use a distinct forward strike.
Do not change server damage, attack timing, hit bounds, ammo or enemy composition.

Meaningful source checks cover both hands, gait and feet registration, recover
endpoints, unarmed weapon absence/strike, hit reaction, death bounds/settling and
model/cached-resource retirement. Bake the unchanged 55-pose/eight-direction
standing layout with paired view normals. Check source freshness, albedo/normal
alpha alignment, unclipped directions and existing live pose selectors.

Coordinate the shared GPU lane for actual source pose inspection, baking and
ordinary-input played combat, including windup/fire/hit/death at game scale.
Source, baked atlases and actual runtime use are separate acceptance gates.
Complete client checks and eventual full CI precede integration. Record exact
source and output hashes, inspected frames, attempts and remaining limitations.

## Local result

Source checkpoint `6c7e68923010876dbc6172cfd9cceb45e168192b` passes the focused
skin, standing-atlas, retained Clerk and historical model harnesses. Clean
ordinary-input three-state proofs retain the named Clerk and two Sweeper kills,
finite supplies and all five required rendered combat phases. The close repeat
reaches five ordinary walking arrivals, retains 100 HP and 37 bullets, and
exits 0 without errors. Actual frame 27 shows a partially cabinet-occluded
settled body at 6.09 m. A clearer body frame from the earlier rejected texture
retirement run is preserved and labeled separately. No scene observer,
retirement override or gameplay/lifetime change is used.

Exact source/bake hashes, eight inspected images and failed attempts are in
[the evidence receipt](../evidence/sweeper-stylized-source-20261004.md).
This is one source role's local art acceptance, not a full M01 departure proof.
The complete combined client checker and implementation CI remain integration
gates; no release or shipped claim is made here.

## Risks

Automated humanoid skinning can deform hard shells or move fingers away from
the rifle. Generated textures can be too detailed or gray at sprite scale.
Imported units, root motion, shoulder width or long weapon/death extents can
break the fixed three-metre bake field. Judge played silhouettes and visible
red issue accents before calling the replacement accepted. Rig success alone
does not establish useful movement or a finished enemy.
