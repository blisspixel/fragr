# Union character source

Original articulated source for the M01 human Clerk and bot Sweeper. These are
the first directional campaign sets, still under visual review in the M01 intake
plan. They do not establish a completed cast or final character production bar.

`geometry.gd` owns material/mesh primitives; `rig.gd` owns anatomy, issued gear
and joint poses; `bake.gd` renders the committed atlases in
`client/assets/characters/union/`. Edit source and rebake, never retouch an atlas
that the next bake will replace. The source directory is excluded from exports.
The bake writes a manifest with source/output hashes. The headless harness rejects
stale outputs after source or layout changes; a rebake updates the receipt.

The human has an open helmet, visible face and green cloth. The bot has covered
issued mechanisms, a status slit and battery pack. Shared bone armor, steel,
green and restrained red seals establish Union manufacture. Neither body type
establishes moral status. These are not free-agent character designs.

## Bake and verify

Use the pinned Godot 4.7.2 binary with a real graphics context. From repository
root, replacing `godot` with the local binary path when necessary:

```sh
godot --headless --path client --import
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_enemy_animation.gd
```

Require clean logs and `character_bake: PASS` / `test_enemy_animation: PASS`.
On Linux, the bake needs a display or the existing Xvfb approach from
`tools/qa_tour.sh`. Headless rendering cannot bake usable pixels. Windows OpenGL
on the AMD Radeon 780M was used for the first bake, 2026-09-20. Exact pixels can
vary across drivers; tests assert bounds and behavior, not a driver-specific hash.

The layout is shared through `EnemyAnimation`: 54 poses at eight angles, 160-pixel
cells, 18 columns, 24 rows. Each atlas is 2880 by 3840, below a 4096 texture limit.
Two uncompressed RGBA atlases total 84.375 MiB, loaded lazily by archetype. PNG
disk size is smaller and does not describe texture memory. No mipmaps or automatic
3D compression; nearest sampling and cutout alpha preserve the pixel edges.

The orthographic field is three metres with its centre 0.9 metres above the
feet. Runtime placement subtracts the server reference height. The living
silhouette is approximately 1.8 metres tall. Do not trim individual tiles, scale
corpses to fill their cell, or enlarge combat bodies for distant cameras.

Animation is presentation only. Server phases choose raise, hit and collapse;
resolved shots start recoil; traveled distance advances the gait. A delayed
windup holds its final pose instead of predicting an attack. Dead actors settle
and remain down until server cleanup. Armed and exhausted melee poses are distinct.
Recovery lowers/regrips the weapon; the wire does not yet distinguish reload
from recovery, so the client must not pretend to know which occurred.

Run the main and maintenance M01 tours after changes. Inspect attack and death
sequences, facing from multiple sides, occlusion, feet, both renderers, and
spectator eyes. The atlas harness cannot determine whether motion looks good.
