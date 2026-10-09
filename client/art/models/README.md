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
| `pistol_source.gd`, `candidates/pistol.glb` | Reviewed civilian charcoal/walnut Pistol source. Preserves 5,154 reviewed triangles, adds 180 trigger/guide and 300 dark sight/seam triangles, separates a 12 mm slide stroke from the fixed barrel and keeps compact work gloves on the receiver. Accepted three-quarter held/fire/pickup pictures are copied into `assets/weapons/pistol-source-20261004/` for runtime selection; original art remains retained. |
| `rifle_source.gd`, `candidates/rifle.glb` | Offline Rifle source, its held presentation rejected by the player. Preserves 6,122 reviewed triangles, 384 local hollow bore triangles, independent bolt/trigger and glove-contact proofs. Historical pictures remain in `assets/weapons/rifle-source-20261004/` unselected; runtime uses the earlier retained Rifle artwork. |
| `sniper_source.gd`, `candidates/sniper.glb` | Reviewed walnut precision Rifle source with recessed optics, authored independent bolt and connected plain work gloves. Retains 9,552 source triangles including clipped fragments and separately counts 3,992 local hardware triangles. Accepted held/fire/pickup pictures are selected in `assets/weapons/sniper-source-20261004/`; the original art and raw source remain retained. |
| `clerk_source.gd`, `candidates/clerk.glb` | Prepared 24-bone human source, retained gait and authored combat, unarmed, seated and collapse poses. Bakes directional sprites and paired normals through the existing character layout. |
| `auditor_source.gd`, `candidates/auditor.glb` | Skinned black/red custody officer, held shield, repair sockets, upper-back cable and raised channel emitter. Supplies directional sprites and paired normals. |
| `enforcer_source.gd`, `candidates/enforcer.glb` | Prepared issued combat source for the directional Enforcer and paired normals; runtime follows authoritative attack phases. |
| `redactor_source.gd`, `candidates/redactor.glb` | Distinct prepared walking source with authored Shiv raise, strike and recovery; supplies directional Redactor art and paired normals. |
| `free_human_source.gd`, `candidates/free_human.glb` | Warm civilian skin and retained 24-bone gait. The compact source is packaged as `assets/models/free_human_live.glb` for the live player body; its eight-cell strip remains the menu and missing-model fallback. |
| `free_synthetic_source.gd`, `candidates/free_synthetic.glb` | Civilian worker with retained 24-bone gait, bone/olive plates and amber expression. Packaged as `assets/models/free_synthetic_live.glb` for the live player body; its eight-cell strip remains the menu and missing-model fallback. |
| `tern_source.gd`, `candidates/tern.glb` | Prepared named civilian, retaining actual source geometry and walking keys. Packaged as `assets/models/tern_live.glb` for current Tern in M09 and M10. Optics and original shoulder asymmetry remain separately documented art gates. |
| `edda_source.gd`, `candidates/edda.glb` | Repaired weighted civilian source, packaged unchanged as `assets/models/edda_live.glb` for eligible M09 and M10 appearances. Retains Edda's face, apron and medical satchel. |
| `../../scripts/splice_character.gd`, `assets/models/splice_live.glb` | Selected rigid civilian with 17 measured regions and 28 joint closures, retaining original faces, UVs and stored tools. Complete-source fallback is checked; horizontal foot planting remains provisional. |
| `../../scripts/skinned_character.gd`, `../../scripts/civilian_figure.gd` | Shared live weighted presenter and accepted-feet mission wrapper. Offline weighted bounds produce packaged support curves; no asset service or offline art source runs during play. |
| `../../scripts/latch_view.gd`, `../../scripts/latch_source.gd` | Packaged 24-bone civilian chassis with retained gait, expressive screen, left antenna, repairs and voluntary hand gesture. Live companion and ward share the prepared `assets/models/latch_stylized.glb` skin. |
| `../../scripts/facility_geometry.gd` | Merged vent, locker, terminal, light and sign housings on registered faces, with two or three material surfaces and at most 8 mm protrusion. |
| `../../scripts/model_geometry.gd` | Shared chamfered prisms, hollow lathes, tapered shells, pipes, UVs and material cache. Kept in runtime scripts because offline art sources are excluded from desktop packages. |
| `../../scripts/architecture_mesh.gd` | Recessed bays for existing thin tall walls, retaining authoritative volume bounds. |

GLB exports, previews, pose frames and the source/output hash manifest live in
`client/assets/models/`. Mechanical clips animate rigid parts; they do not
claim skeletal skinning. The separate prepared bodies use weighted skins.
The live Latch helper, selected cast models and their compact embedded maps
are packaged; offline cast sources and the reference library remain excluded.
No asset service runs in play.

The prepared enemy models above still supply baked directional pixel art.
Current source selects Latch, both player bodies, Tern and Edda as live weighted
meshes; see the [live presenter plan](../../../docs/plans/live-character-presenters-20261008.md)
and [Edda integration](../../../docs/evidence/edda-live-integration-20261008.md)
for integration evidence and remaining acceptance.
[Edda and Splice](../../../docs/evidence/named-cast-source-production-20261005.md)
remain separate retained identities. Edda's [satchel-weight repair](../../../docs/plans/edda-live-repair-20261008.md)
has its own source evidence. Current source selects the prepared rigid Splice mesh for
eligible mission appearances, with complete-source fallback; world-space foot
planting remains provisional. Their source, skeleton and motion receipts remain
the authority for what was actually produced.

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
