# Lunar pressure-room candidates

Selected source and palette-reduced albedos, 2026-10-01. Runtime copies are integrated under `client/assets/environment/moon/possessions/` and inspected in an isolated lit room preview. Final gameplay capture remains pending. The [batch plan](../../../../docs/plans/m06-lunar-art-batch.md) records approval, exact pricing, request recovery and remaining checks. The [manifest](manifest.json) records assembled prompts, model, request IDs, dimensions, hashes and preparation.

- `lunar_child_earth_drawing`: worn paper, imperfect continent shapes and crayon stars for the existing family-room page.
- `lunar_civilian_patched_textile`: broad individually repaired cloth blocks for existing inaccessible storage possessions.
- `lunar_personal_meal_cloth`: a restrained cyan stripe and rust patch for the existing family table.

Sources are metadata-free 2048-square re-encodes. Processed images use the existing Rust reducer: exact 16:1 area reduction to 128 square, `docs/palette.json`, hard alpha and no trim. All processed pixels are opaque and belong to that palette. Runtime placement preserves nearest filtering and world lighting. No normal map, seamless tile, new collision or named-character design is claimed. The pressure-shell insert was not selected because it duplicates current hull detail without a needed placement slot.
