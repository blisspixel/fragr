# Weapon source art

The Shiv is a candidate for the optional M01 service cache. Its source and reduced
sprites are inspected, but gameplay presentation and animation are not integrated.
See [the active plan](../../../docs/plans/m01-secret-shiv.md).

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
