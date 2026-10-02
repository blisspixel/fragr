# Offworld material library

Five opaque 128 by 128 pixel albedo tiles, reduced to the shared palette and
inspected at native scale and in 3 by 3 repeats. Each opposing image boundary
matches exactly. Sampling stays nearest, repeated and without mipmaps. Five
RGBA tiles occupy 320 KiB uncompressed; actual packaged PNG sizes are smaller.

| Tile | Use |
|---|---|
| `mars_basalt.png` | Dark fractured exterior stone with restrained dust in seams |
| `mars_regolith.png` | Dust-red exterior ground with quiet wind-worn grain |
| `offworld_pressure_habitat.png` | Pale repaired enclosure skins and practical sealed joints |
| `offworld_mining_deck.png` | Dark worn cargo and mining tread plate |
| `offworld_thermal_ceramic.png` | Pale chipped thermal shielding and sparse sealed joints |

[`OffworldMaterials`](../../../scripts/offworld_materials.gd) exposes named
descriptors, shared cached textures and independent lit material instances.
It registers a reusable library, not a playable Mars mission. Surface mappings
and world texel density belong to the actual authored venue. The intended world
scale is 16 texels per metre; the offline material board displays a full tile on
each sample to inspect every pixel.

The [manifest](manifest.json) records prompts, medium-quality requests, estimates,
source hashes and preparation. Billing totals remain unconfirmed. Provider
downloads and locked request receipts remain in the local ignored art backup;
the small [reduced sources](../../../art/environment/offworld-batch-20261001/README.md)
are retained for reproducible seam preparation without another generation call.
No normal maps or gameplay systems are implied by the material skin.

The inspected [lit preview](../../../../docs/screenshots/world_materials_mars_library.png)
shows all five imported materials on separate slabs and floors. It explicitly
labels Mars missions as unbuilt and does not claim in-game world acceptance.
