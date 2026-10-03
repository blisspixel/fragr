# Weapon source art

The Shiv is the secret in M01's confiscation alcove. Its 48 pixel icon is in
play on pickups and in fighters' hands. See [the plan](../../../docs/plans/m01-secret-shiv.md).
Since 2026-10-02 the first-person Shiv is `viewmodels/shiv_idle.png`, an edit of
`shiv-view-source.png` that keeps the knife, grip and framing and puts the hand in
the same brown leather work glove as every other weapon; its provenance is in
`client/assets/art-pass-20261002-manifest.json`. The forearm still reaches the
bottom edge; preserve that registration during movement and attack animation.
No emissive blade, gun muzzle flash or floating wrist.

`manifest.json` records the exact prompts, references, dimensions and hashes.
Source PNGs preserve decoded pixels and alpha without provider metadata. This
directory is excluded from Godot import and export by `.gdignore`.

Regenerate the runtime candidates from the repository root:

```sh
godot --headless --path client --script ../tools/bake_shiv.gd
```

The bake uses nearest-neighbor reduction to the 48x48 icon. Import as lossless
textures without mipmaps and render with nearest filtering. Check reduced edges,
grip readability, bottom registration and attack motion in the actual first-person
view before accepting the art. Standalone sprite inspection is not that evidence.
