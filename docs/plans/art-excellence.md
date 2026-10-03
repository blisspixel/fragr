# Art excellence

**Status:** proposed, 2026-10-03. It directs work once Nick decides the
questions at the end.
**Spend:** needs approval. Nothing in this plan bills until Nick approves a
service and a cap.

## The bar

Nick, 2026-10-03: "just because its inspired by boomer shooter ... doesnt mean
the graphics and art assets need to be bad. we want excellent art assets and
models and maps", and "I want this to be exceptionally well made."

Retro is the art direction, not a quality ceiling. The reference set is the
modern boomer shooters that look excellent:
- Boltgun: detailed renders reduced by artists who control contrast and
  palette.
- Prodeus: fully 3D worlds, with enemies drawn from 3D models into eight
  rotational sprites that take dynamic light.
- Dusk and Ultrakill: low-poly 3D with strong silhouettes.
- Cultic: sprites under modern lighting.

Every asset is judged against those games at game scale, in motion, under
the venue's light.

## Where fragr is today

Being honest about the gap:

| Area | Today | Gap |
|---|---|---|
| Characters | Assembled from Godot primitive shapes (`client/art/characters/geometry.gd`, `rig.gd`), baked to eight-direction atlases, unshaded | Readable silhouettes, but blocky programmer-art figures that take no light |
| Weapons | Generated stylised pixel viewmodels with idle, fire and pump frames, after art passes 1 and 2 | Good direction. Needs consistent animation and the Rifle redraw finished |
| Pickups and HUD | Object sprites and icons, after art pass 1 | Good direction |
| Maps | Authored solids with tiled pixel textures, some decoration panels and signs | Mostly boxes. Little real architecture, few props, little trim or silhouette |
| Lighting | Three presets with SSAO, glow, venue lights | Planned Ultra preset ([graphics options](graphics-options-and-lighting.md)) |

## Direction

1. **Characters from real models.** Replace primitive assemblies with
   sculpted, textured, rigged models (glTF) as the source of the existing bake.
   Keep the eight directions, the pose layout, feet registration and the
   Union palette, so every downstream contract holds. Bake normal maps beside
   the albedo, so sprites take venue and muzzle light the way Prodeus's do,
   instead of reading flat.
2. **Maps with architecture.** Build a modular kit per environment (Earth
   facility, Low Water, the lunar port, Mars, ships):
   - Trims, arches, columns, pipes, railings, consoles, door frames, lamps.
   - Signage, crates and machines as real meshes with pixel textures.
   - Decals.

   Set dressing has to play. It gives cover, marks landmarks and routes, or
   rewards a look ([size follows the crowd](../MAP-DESIGN.md#size-follows-the-crowd)).
   Collision stays in authoritative solids; detail meshes sit on top.
3. **Weapons from one source.** Render each viewmodel's frames from one model
   per gun, so fire, pump and future animations stay on-model. Or continue
   the stylised generated frames where they already meet the bar.
4. **Light it.** The Ultra preset, venue practical lights, and per-environment
   fog and atmosphere.
5. **Judge it in motion.** Every art change ships with tour stills and a
   motion strip at game scale, compared against the reference set, under
   at least two venues' light.

## Tools, checked 2026-10-03

- **Godot imports glTF natively.** Models are a supported path with no
  engine change.
- **AI 3D generators** (Meshy, Tripo, Rodin and others) export glTF. Current
  reviews say they suit static props, background assets and fast prototypes.
  They are "not reliably one-click production tools for deforming characters,
  exact hard-surface parts or a consistent hero-asset library."
- **Licensing:** Meshy's free tier is CC BY 4.0, which requires attribution.
  Paid plans grant commercial ownership without it. Any service must give
  ownership compatible with Apache 2.0 distribution and need no credit line,
  under the attribution lock.
- **Higgsfield** (already approved) stays the source for concept sheets,
  reference images and textures.

## Decisions for Nick

1. **3D props:** approve a 3D generation service, chosen on output quality,
   glTF export and commercial ownership, with a capped first batch. Start with
   the M01 facility kit and judge it in-game before going wider.
2. **Hero characters and weapons:** AI-assisted modelling plus local
   rigging, or commission a human 3D or pixel artist for the recurring cast
   (Latch, the Union line, the guns). Hero characters are where generators are
   weakest and players look longest.
3. **Lit sprites:** bake normal maps for lit sprites (recommended), or keep
   unshaded atlases for maximum readability.

## Verification

- Bake receipts and manifest entries for every asset (prompt or source,
  model, cost, hashes, licence), with no generator credit in assets or UI.
- Tour stills and motion strips per venue, inspected against the reference
  set.
- `tools/godot_check.sh` and the existing character harnesses: pose layout,
  feet registration and stale-bake rejection.
- Performance measured with the [rendered benchmark](showcase-benchmark.md)
  when models replace boxes.
