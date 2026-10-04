# Civilian Pistol source refinement

Status: source and candidate checks tested locally, 2026-10-04.
Runtime selection and packaging acceptance remain open. $0 new spend.
The shared production receipt owns the original 15-credit source operation.

## Source and workmanship

Reviewed raw SHA-256:
`9c097088ab52e63730d6ec4494180c4663b812016035c490a06a19bf51a51318`.
Prepared GLB SHA-256:
`c8a257cd5941060cd44fa43def4c78830a8b1cf602a956bdcd1fb28c5c264038`.

All 5,154 source triangles remain: Body 2,685, Slide 1,985, Trigger 176,
Hammer 308. The front recoil plug is part of the moving slide, while the
actual barrel remains fixed. Authored additions are a 60-triangle curved
trigger blade and 120-triangle recoil guide, for 5,334 total gun triangles.
Compact sage work gloves are authored separately from the prepared gun.

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
one-shot, ammunition and trace gates are unchanged. A clean complete played
receipt remains required before the source can be selected for runtime.
