# Articulated model sources

The October 3 production pass supplies real geometry and reusable motion.
These are original local sources, not meshes inferred from unrelated views.
The [production library](../production-20261003/README.md) supplies inspected
design and material references; [art excellence](../../../docs/plans/art-excellence.md)
owns quality acceptance.

| Source | Current use |
|---|---|
| `sweeper_source.gd` | Shaped Union body, joints, equipment and poses. The character bake uses this source for the live directional Sweeper and its view-aligned normals. `model_clips.gd` exports six rigid mechanical clips in GLB. |
| `shotgun_source.gd` | Original receiver, hollow barrel, walnut stock, guard, sights, moving pump and attached gloves. GLB and twelve coherent poses are development candidates; existing first-person art remains selected pending quality refinement. |
| `../../scripts/latch_view.gd` | Lean roughly 1.8 metre civilian chassis, tall screen, pixel eyes, left antenna, repairs and voluntary hand gesture. Live companion and ward presentation share this model. |
| `../../scripts/facility_geometry.gd` | Merged vent, locker, terminal, light and sign housings on registered faces, with two or three material surfaces and at most 8 mm protrusion. |
| `../../scripts/model_geometry.gd` | Shared chamfered prisms, hollow lathes, tapered shells, pipes, UVs and material cache. Kept in runtime scripts because offline art sources are excluded from desktop packages. |
| `../../scripts/architecture_mesh.gd` | Recessed bays for existing thin tall walls, retaining authoritative volume bounds. |

GLB exports, previews, pose frames and the source/output hash manifest live in
`client/assets/models/`. Mechanical clips animate rigid parts; they do not
claim skeletal skinning. Runtime sources use imported finish textures so the
desktop package does not need raw PNG files or the source reference library.

From repository root, using the pinned Godot 4.7.2 binary:

```sh
godot --headless --path client --script ../tools/prepare_model_finishes.gd
godot --headless --path client --import
godot --path client --rendering-driver opengl3 --windowed --script art/models/bake.gd
godot --path client --rendering-driver opengl3 --windowed --script art/characters/bake.gd
godot --headless --path client --import
godot --headless --path client --script scripts/test_model_assets.gd
godot --headless --path client --script scripts/test_enemy_animation.gd
```

Require clean logs and each command's PASS marker. Repeat the model harness
with a real framebuffer for moving-light evidence, and run the live mission
tours for art review. Re-export and rebake after a source or finish changes.
No model changes combat, weapon timing, collision or mission facts.
