# First-person weapon quality

Status: in flight, 2026-10-05. The user rejected the current Pistol's played
appearance. Earlier source, CI and package passes remain technical evidence;
they do not close this visual acceptance gate. This pass follows the existing
art rung in the [Full build order](../ROADMAP.md#full-build-order).

The subsequent explicit direction is to use the Shotgun's successful drawn
first-person image workflow. Flat sprites are acceptable. The Pistol's model
reconstruction and live-3D presentation experiment are stopped. The current
replacement is a new coherent drawn idle/fire pair, with ordinary played and
final integration acceptance still required. Existing world models and
mechanical source receipts are retained separately.

## Observed problem

The current Pistol view reads as a muddy gray slide with an awkward grip and
wood-like hands. `prepare_pistol_source.gd` globally reduces the albedo to 256
pixels before enlarging to 1K, disables metallic/roughness maps, and sets
metallic 0.06, roughness 0.96 and normal strength 0.20. Those choices suppress
material separation. `pistol_source.gd` constructs gloves from primitive palms,
rods and sleeves. `preview_pistol_source.gd` renders seven poses at 896x720,
reduces them to 224x180, then retains only idle and fire pictures for gameplay.

These are actual source facts. Nine controlled material/framing renders then
confirmed that retained source maps recover metal detail under the same light,
geometry and unchanged primitive hands. That does not repair the poor grip or
close art acceptance. The experiment is retained privately and stopped. The existing
prepared geometry may be usable; another paid model does not by itself fix
framing, hands, surface finish or lost motion. Retain the original source and
all rejected comparisons without treating exact source-triangle preservation
as a reason to keep defective geometry.

## Research checked October 5, 2026

[Meshy's image-to-3D guidance](https://docs.meshy.ai/en/webapp/image-to-3d)
recommends a clear subject, consistent lighting and multiple views of the same
object when completeness matters. It distinguishes detailed standard sources
from topology intended for real-time use. Its troubleshooting notes identify
perspective distortion and insufficient reference coverage as causes of poor
proportions and missing back detail.

The [current image API](https://docs.meshy.ai/en/api/image-to-3d) supports Smart
Topology T2 with directly controlled face counts and separated parts, or the
7.1 standard/Ultra route. The native tool already pins 7.1 for that route;
there is no unsupported model upgrade to perform. Do not infer that returned
parts, rig weights or a requested face count are correct without inspecting
the actual model.

The [multi-image API](https://docs.meshy.ai/en/api/multi-image-to-3d) accepts one
to four images of the same object. A matching front, rear, side and quarter
view can reduce reconstruction guesses. Independently generated inconsistent
guns are not a valid multiview set. The current native pipeline must gain any
missing endpoint through the existing ledger and fake-transport tests before
that paid operation is used. The documented API is not proof that our tool
already supports it.

## Intended finishing workflow

1. Define the actual first-person target before generation: practical civilian
   sidearm, readable barrel/slide/grip, restrained charcoal and walnut, clear
   sights, fitted dark work gloves, and a coherent view relative to the Shotgun.
   Examine idle and firing at normal player resolution, rather than choosing
   from large studio renders alone.
2. Audit the retained source under neutral light. Compare original maps,
   current flattened finish, and a deliberately painted finish. Preserve
   recognizable metal, wood and leather values, useful bevel highlights and
   shape normals. Keep nearest sampling and pixel clusters without globally
   crushing every material into the same dull value range.
3. Use the reviewed five-digit glove source and purposeful local finger
   pivots. The source is a left glove despite its request label; any right-hand
   mirror must repair winding and normals. Fit the palm, thumb, wrist and
   trigger finger to actual geometry. Test visible joints, grip contact and
   moving-part clearance, then inspect the hands in motion.
4. Compare several first-person compositions against the same live camera and
   HUD: clear aim direction, visible side planes, believable scale and a small
   amount of screen coverage. The weapon must read well at normal distance
   from the screen and across supported aspect ratios.
5. Use the Shotgun's drawn sprite workflow for first-person weapon replacements.
   Generate a purposeful idle from the accepted visual style, then derive its
   fire image from that exact idle. Reduce both on the same full canvas with
   the registered palette, hard alpha and nearest filtering. Check grip,
   silhouette, registration, muzzle origin, moving-part read and settled idle.
   Preserve resolved-shot timing, ammunition and weapon cooldown. A live 3D
   view is not required for this work.
6. Inspect ordinary discovery, walking, close walls and resolved shots in both
   a daylight venue and an interior. Reject conspicuous shape, texture or hand
   flaws even when technical gates pass. Select the better result only after
   actual played comparison, complete integration checks, CI and packages.

Use paid reference/retexture/regeneration only for an identified source gap,
with the native free balance check, exact stage caps and durable receipts.
The latest account reports are 2,125 Meshy credits (15 held uncertain) and
$12.60 Higgsfield, reported by the user. Included credits remain authorized;
this finishing pass introduces no new cash, renewal, top-up or overage.

## Acceptance still open

The replacement sprite pair is selected locally; main still has the rejected
Pistol until the combined integration passes. Four completed image requests
used an estimated $0.410 prepaid allowance, with no model credits consumed.
The raw request reservations, IDs and sources remain in the native ledger.
The existing refined Shotgun and restored Rifle are comparison controls.
The new glove is an inspected source, not a completed hand rig or runtime asset.
M02's companion presentation is being audited separately against the actual
live model path. Neither this research nor a 3D import closes visual acceptance.
