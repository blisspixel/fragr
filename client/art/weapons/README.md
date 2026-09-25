# Weapon source art

The Shiv is the secret in M01's confiscation alcove. Its viewmodel and 48 pixel
icon are in play: the HUD thrusts the viewmodel toward the crosshair on a cut,
and pickups and pawns hold the icon at the 32 pixel size.
See [the plan](../../../docs/plans/m01-secret-shiv.md).

The viewmodel uses the existing fists palette: worn steel, charcoal gauntlet,
restrained rust fabric and ochre grip. The forearm reaches the bottom edge; preserve
that registration during movement and attack animation. The pickup icon repeats
the same knife. No emissive blade, gun muzzle flash or floating wrist.

`manifest.json` records the exact prompts, references, dimensions and hashes.
Source PNGs preserve decoded pixels and alpha without provider metadata. This
directory is excluded from Godot import and export by `.gdignore`.

Regenerate the runtime candidates from the repository root:

```sh
godot --headless --path client --script ../tools/bake_shiv.gd
```

The bake uses nearest-neighbor reduction to 240x180 and 48x48. Import as lossless
textures without mipmaps and render with nearest filtering. Check reduced edges,
grip readability, bottom registration and attack motion in the actual first-person
view before accepting the art. Standalone sprite inspection is not that evidence.
