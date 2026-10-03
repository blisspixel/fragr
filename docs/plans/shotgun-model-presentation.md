# Shotgun model presentation

**Status:** in flight, 2026-10-03. Local preparation of the reviewed controlled
topology source, within the existing roadmap's art rung. No new paid generation.

The source split and compact export are implemented: 12,853 triangles retained,
two mesh pieces, about 4.5 MB with embedded 1K maps. The actual pump, fixed body,
muzzle and attached-hand checks pass. Twelve coherent views render in Godot.
The first framing and grip were inspected and refined, but live first-person
selection and its played acceptance gate remain open.

[Idle](../screenshots/shotgun-model-20261003/idle.png) and
[pump stroke](../screenshots/shotgun-model-20261003/pump.png) are real Godot
framebuffer views, captured with Forward+/Vulkan on the AMD Radeon 780M, then
reduced to 241 by 180 pixels. They establish the inspected source and cycle,
not a selected in-game viewmodel or proof of other hardware performance.
The prepared GLB's SHA-256 is
`9c5283df04d7bb981dd3a96147e253919936b189e9a8ca64d42116f58ceb666d`.

## Goal

Turn the inspected walnut and blued-steel Shotgun source into a coherent authored
first-person weapon. Preserve the civilian, well-used gun direction and restrained
circa-2070 setting. Improve receiver, stock and fore-end surface detail without
changing ammunition, firing cadence, pellet resolution or server authority.

## Implementation and gate

The topology comparison imports as one mesh but contains disconnected geometry.
An offline analysis finds 24 islands after welding coincident seam vertices at
0.01 mm, including a 1,496-triangle fore-end candidate. Validate the independent
pump before splitting the source; one imported mesh alone proves no articulation.
Keep source textures embedded, reduce their budget locally, preserve legal
notices and reuse export metadata cleanup. Attach authored hands and a muzzle
reference, then bake coherent idle, fire and cycle views under fixed framing.

Inspect all geometry changes, hand contact, pump travel, camera clipping,
silhouette and read at the actual player resolution. Retain the current selected
first-person assets until the candidate passes rendered and played gates.
Do not select a static mesh or disguise missing mechanics with unrelated frames.
Keep preparation in excluded offline art, with reproducible source/output hashes.
Full client and CI checks precede merging any runtime selection.
