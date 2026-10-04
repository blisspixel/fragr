# Articulated model sources

The library combines authored geometry and reusable motion with prepared
weighted character skins. The October 4 cast shares one stylized direction.
The [production library](../production-20261003/README.md) supplies inspected
design and material references; [art excellence](../../../docs/plans/art-excellence.md)
owns quality acceptance.

| Source | Current use |
|---|---|
| `sweeper_source.gd` | Retained mechanical library body. `model_clips.gd` exports its six rigid mechanical clips in GLB. |
| `sweeper_skinned_source.gd`, `candidates/sweeper.glb` | Broader 24-bone issued bot, retained gait, two-handed rifle grip and authored combat/collapse poses. Supplies the live directional Sweeper and paired normals. |
| `shotgun_source.gd` | Original receiver, hollow barrel, walnut stock, guard, sights, moving pump and attached gloves. GLB and twelve coherent poses are development candidates; existing first-person art remains selected pending quality refinement. |
| `pistol_source.gd`, `candidates/pistol.glb` | Offline civilian charcoal/walnut Pistol candidate. Preserves 5,154 reviewed triangles, adds 180 trigger/guide and 300 dark sight/seam triangles, separates a 12 mm slide stroke from the fixed barrel and keeps compact work gloves on the receiver. Three-quarter held/fire/pickup frames remain separate from selected runtime art. |
| `clerk_source.gd`, `candidates/clerk.glb` | Prepared 24-bone human source, retained gait and authored combat, unarmed, seated and collapse poses. Bakes directional sprites and paired normals through the existing character layout. |
| `auditor_source.gd`, `candidates/auditor.glb` | Skinned black/red custody officer, held shield, repair sockets, upper-back cable and raised channel emitter. Supplies directional sprites and paired normals. |
| `free_human_source.gd`, `candidates/free_human.glb` | Warm civilian skin, empty hands and stationary-root gait for the selectable eight-cell body strip. |
| `../../scripts/latch_view.gd`, `../../scripts/latch_source.gd` | Packaged 24-bone civilian chassis with retained gait, expressive screen, left antenna, repairs and voluntary hand gesture. Live companion and ward share the prepared `assets/models/latch_stylized.glb` skin. |
| `../../scripts/facility_geometry.gd` | Merged vent, locker, terminal, light and sign housings on registered faces, with two or three material surfaces and at most 8 mm protrusion. |
| `../../scripts/model_geometry.gd` | Shared chamfered prisms, hollow lathes, tapered shells, pipes, UVs and material cache. Kept in runtime scripts because offline art sources are excluded from desktop packages. |
| `../../scripts/architecture_mesh.gd` | Recessed bays for existing thin tall walls, retaining authoritative volume bounds. |

GLB exports, previews, pose frames and the source/output hash manifest live in
`client/assets/models/`. Mechanical clips animate rigid parts; they do not
claim skeletal skinning. The separate prepared bodies use weighted skins.
The live Latch helper and its embedded 1K maps are packaged; the offline cast
sources and reference library remain excluded. No asset service runs in play.

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
