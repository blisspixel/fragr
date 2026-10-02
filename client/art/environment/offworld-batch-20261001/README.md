# Offworld material sources

Five selected 128-pixel palette sources are retained in `reduced/`. The ignored
`art/raw/offworld-materials-20261001/` directory preserves the provider's 2k
downloads and append-only request ledger. The public
[asset manifest](../../../assets/environment/offworld/manifest.json) records
the full prompts, request IDs and source, palette and keeper hashes.

The shared palette includes the dusty rust ramp approved for Mars terrain.
Existing local reduction supplies area averaging and CIE Lab palette selection.
The [seam bake](../../../../tools/bake_offworld_tiles.gd) blends opposing edge
bands and the existing reducer restores exact palette membership afterward.
Five materials are inspected separately and as repeated tiles. Exact boundary
matching is a measured gate; it does not substitute for checking the repeated
pattern visually.

The dark basalt, warm regolith, pale repaired pressure cladding, dark tread deck
and lighter ceramic shield have distinct material and value roles. These are
albedo skins, with no normal maps, emission, collision or liquid rules.

Mars levels remain unbuilt. The `OffworldMaterials` library and the offline
[preview tool](../../../../tools/preview_offworld_materials.gd) provide reusable
assets for authored work. They do not advertise a playable Mars map or vehicle
system. Current gameplay venue integration and final rendered tour acceptance
remain separate parent-owned gates.

The inspected [lit material board](material_preview.png) uses the actual library
materials on separate wall slabs and floors. It was captured with the pinned
Compatibility renderer on AMD Radeon 780M and closed with a clean PASS. The
frame labels Mars missions as unbuilt; it is a material preview, not gameplay.
