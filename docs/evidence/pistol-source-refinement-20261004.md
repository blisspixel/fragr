# Civilian Pistol source refinement

Status: refined source and played comparison tested locally, 2026-10-04.
Runtime art review is accepted and the three pictures are selected locally.
Full client, integration and packaging acceptance remain open.
$0 new spend.
The shared production receipt owns the original 15-credit source operation.

## Source and workmanship

Reviewed raw SHA-256:
`9c097088ab52e63730d6ec4494180c4663b812016035c490a06a19bf51a51318`.
Initial prepared GLB SHA-256:
`c8a257cd5941060cd44fa43def4c78830a8b1cf602a956bdcd1fb28c5c264038`.

All 5,154 source triangles remain: Body 2,685, Slide 1,985, Trigger 176,
Hammer 308. The front recoil plug is part of the moving slide, while the
actual barrel remains fixed. Authored additions are a 60-triangle curved
trigger blade and 120-triangle recoil guide, for 5,334 total gun triangles.
Initial compact sage work gloves are authored separately from the prepared gun.

The 24 cm source embeds 1K material maps, samples nearest pixels and imports
without generated LOD. Four rendered studio views retain the actual bore,
iron sights, right ejection port and civilian charcoal/walnut finish. Seven
coherent held frames and paired side views expose the independent 12 mm
stroke. The initial reused shotgun gloves were rejected; compact gloves
replace their oversized, spiked silhouette. Finger readability at play scale
still requires the actual comparison, rather than studio acceptance alone.

## Focused checks

Pinned Godot 4.7.2-stable checks exit 0 with their PASS markers and clean
error logs. `test_pistol_source.gd` checks retained topology, physical bounds,
embedded maps, hardware, below-slide glove clearance, 31 mechanism samples,
five invalid/rest timings, exact source/bake hashes and hard pixel alpha.
The three candidate canvases retain 224x180 held/fire and 36x26 pickup sizes.

The original selected `test_viewmodel.gd` passes unchanged. A candidate-only
subclass tests its actual centre glove cut at column 112 instead of the
selected art's column 150. All inherited cut-off, alpha, walking, recoil,
resize and fire assertions remain. Temporary texture substitutions are
restored byte-for-byte; no runtime weapon selection is committed.

Private diagnostics: `.agents/pistol-refinement-20261004/`. Clean source logs
are `prepare-clean.log`, `test-source-clean-final.log`,
`test-source-final-checked.log` and `test-candidate-registration-final.log`.
Final studio/bake images and immutable receipts live in `candidate-final/`.

## Actual comparison gate

The owned discovery range loads through the canonical server helper, SHA-256
`844bb2dc58c9c04e0689fbf2771a76f5404ed4c0462e1a474c02ded99a03481d`.
It grants no supplies through QA. A real pad must award the Pistol and 50
Bullets, then one ordinary shot must leave 49 and resolve on an actual solid.
The local client freezes only its presenter for selected/candidate pictures
of the same camera and played sample. Rust continues normally. Only the held
picture and Pistol pickup icon texture change temporarily; transforms,
pixel size, lighting, actor facts and inventory remain unchanged.

Failed trials remain private. The first combined walk/select state requested
an unowned Pistol before arrival; the route now separates claim and selection.
The next two trials correctly rejected two shots and 50-to-48 ammo. The
manual release in the third was unnumbered, which canonical human ingress
correctly refused after numbered inputs. The corrected fixture waits for the
existing manager to transmit physical release before any capture work. Its
one-shot, ammunition and trace gates are unchanged.

The fourth trial, `played-pair-4/`, exits 0 with clean error logs: eight
nonblank states and nine ordinary walking arrivals. The real pad supplies
the Pistol and 50 Bullets. Exactly one Pistol shot at tick 274 resolves on
the authoritative near wall, leaving 49. The normal sender transmits the
release before capture, with sequence 863; no second sequence writer remains.
Nine same-sample pairs freeze only client presentation for 14 to 18 ms,
preserving camera transform, textures and processing through restoration.
The canonical server continues normally, with retained samples from ticks
201 through 463. `resolved-shot.json`, `same-sample-pairs.json` and
`manifest.json` preserve the facts, timestamps and image hashes.

The selected/candidate held, firing, close-wall, occluded and returned pickup
views are inspected at 1280x720. This is one played sample with two
presentations, not two independent runs. The pickup silhouette is coherent;
the initial held candidate is too low and small, with noisy chrome highlights
and overly cool gloves. It remains unselected.

The next offline revision retains exact raw geometry, scale and mechanisms.
It uses closer bake framing, broad charcoal/walnut value groups, reduced
normal strength and matte roughness without metallic/roughness maps. Plain
worn civilian workshop gloves replace the cool sage treatment; they add no
costume theme. Initial source receipts, scripts and all four played trials
remain archived. Fresh pixel, motion, registration and matched-view gates
are required for the refined outputs.

## Quiet material and framing revision

The refined GLB is 1,098,860 bytes, SHA-256
`b7463eea8ca234a2343ea9eeaa2d4c4f259a49502511491c3c7b2e244dd31df2`.
It preserves all part counts and motion. The embedded 1K albedo uses broad
four-pixel charcoal, walnut and restrained sage value clusters. Metallic
and roughness maps are removed; metallic strength is 0.06, roughness 0.96
and normal strength 0.20. The plain warm gloves depict civilian workshop
workwear, with no costume theme.

Only the offline camera changes to fill the useful 224x180 vertical envelope.
Gameplay camera, canvas, weapon transform, scale and bob remain unchanged.
Two higher framing attempts clipped the firing burst at the top edge. Both
private bakes and the failed strict gate remain retained. The corrected
`candidate-quiet-v2-clearance/` bake passes every original source and inherited
registration threshold, plus new full-height silhouette and top-edge checks.
Logs `test-v2-source-clearance.log` and `test-v2-registration.log` have their
PASS markers, successful exits and no errors. The original selected
`test_viewmodel.gd` also passes after exact restoration.

The fifth comparison, `played-pair-5/`, retains the same diagnostic map,
eight states and nine ordinary arrivals. One actual Pistol shot at tick 304
resolves on the near wall, reducing 50 Bullets to 49. Canonical physical
release precedes capture, sequence 836. Nine same-sample presentation pairs
take 16 to 25 ms across ticks 227 through 500. Their images, hashes and camera
facts remain in `same-sample-pairs.json`; `source-pairing.json` records the
map, route, wrapper, native helper, GLB and bake hashes.

The final manifest and tour log contain all eight nonblank captures with no
error lines. A private process owner launches and retires the renderer and
cleans only its returned server PID; its own exit is 0. The child renderer's
exit code was not recorded by this fallback launcher. This evidence therefore
establishes the completed manifest, clean log and observed child retirement,
rather than claiming a measured child exit status.

Full-size held, resolved-fire, close-wall and returned pickup pairs are
inspected. The closer framing and matte planes improve the initial low,
chrome-like candidate; gloves remain angular at play scale. The HUD texture
is still an overlay, so the close-wall comparison does not establish world
mesh near clipping. Runtime selection and exported-package checks remain
open. No paid source, ammunition policy or server outcome changes here.

## Three-quarter readability revision

The fifth pair's held view still reads as a long, weakly differentiated slide.
The third offline revision preserves that entire trial and the prior source
while moving the bake camera 75 mm to the side. The actual muzzle projects
near column 113 on the unchanged 224x180 canvas. It exposes the right ejection
port, slide cuts, trigger contact and walnut grip instead of viewing only
the upper spine. Gameplay camera and weapon transforms remain unchanged.

All 5,154 reviewed triangles remain. The original 180 local trigger/guide
triangles remain separately counted. Five bounded dark sight/seam pieces add
300 triangles, giving 5,634 total gun triangles. These use matte charcoal and
stay inside the original sidearm envelope. Broad per-face top and side value
groups clarify the source geometry without adding reflective scratches.
Prepared source SHA-256:
`6b53c545e6efb89cb1e43f19c0e6f012b6590424ae2e37fe8fc82111e660d543`.

A new meaningful material gate caught preserved vertex colors with the
imported material's paint flag disabled. The offline source presenter now
duplicates and activates its local slide material. The failed proof and
first studio bake remain retained. The actual corrected rebake lives in
`candidate-three-quarter-v3-active/`; source and inherited registration logs
`test-v3-source-active.log` and `test-v3-registration-active.log` exit 0 with
clean errors and their PASS markers. The source contract checks the real
active material flag, contrasting vertex groups, dark trim bounds and every
prior raw count, mechanism, alpha, full-height and bottom-edge assertion.

The sixth played comparison completes eight nonblank states and nine ordinary
arrivals. Exactly one actual Pistol solid impact at tick 280 leaves 49 from
50 Bullets, with canonical release sequence 852 preceding the capture. Nine
same-sample pairs last 17 to 19 ms across ticks 203 through 477. Full-size
held, fire, close-wall and pickup pairs are inspected, with visibly clearer
slide side, sights and grip. `played-pair-6/` preserves the complete manifest,
trace, camera and picture-hash receipts. `source-pairing.json` binds the actual
map, route, wrapper, native helper, GLB and bake hashes.

The private process owner now records the actual renderer exit code through
the documented [process exit API](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-get-process-exit-code).
`process-receipt.json` records exit 0, no timeout and cleanup of owned children.
The clean tour log and complete manifest provide separate successful content
evidence. Selected WeaponArt is restored to SHA-256
`1610df85e0bf1eac6e0d00b0f9f028861856d054bdaca593da1356b255eb246a`.
The actual matched views are accepted for runtime selection. Exact copies of
the three PNGs now live in `assets/weapons/pistol-source-20261004/`, outside
the desktop export presets' offline `art/*` exclusion. WeaponArt selects those
packaged copies. `selection.json` binds their exact source, presenter, bake
and picture hashes; generation-time candidate receipts remain unchanged.
Original artwork, source revisions and all six played trials remain intact.

The canonical viewmodel gate now checks the reviewed Pistol glove column 112
instead of the previous artwork's column 150, retaining every swap, alpha,
bob, recoil, firing and resize assertion. Focused source and canonical
viewmodel harnesses pass with runtime selection active. The diagnostic pair
wrapper explicitly loads historical baseline pictures for its first frame
and restores the selected runtime textures, so later comparisons do not
accidentally compare the new art against itself. Full client, integration
and exported-package acceptance remain open; no campaign or whole-arsenal
completion is claimed.

Public frames are exact copies of the sixth diagnostic pair's candidate
presentation, with the same actual gameplay samples and no desktop pointer:
[held](../images/pistol-source-20261004/held.png),
[resolved fire](../images/pistol-source-20261004/fire.png), and
[returned pickup](../images/pistol-source-20261004/pickup.png).
