# October 3 source library

High-resolution production references for fragr's restrained circa-2070 world.
The fixed [inventory](../../../tools/spritegen/specs/production-20261003/inventory.json)
has 147 sources in twenty-one priced batches. The manifest records completed
downloads with request identifiers, exact request estimates, source hashes
and 768-square review exports. Original 4K images and durable job ledgers stay
under ignored `art/raw/`; the API is a developer tool, never a game dependency.

The [spend record](spend.json) preserves $93.365 in request estimates across
151 completed requests, including the initial references and correction attempt.
Nick subsequently reported $14.42 remaining in the API dashboard. That implies
a $91.46 net balance decrease from his reported $105.88 starting balance;
individual request charges remain unverified.

| Collection | Sources | Purpose |
|---|---:|---|
| Venue materials | 56 | Concrete, enamel, steel, deck, ceramic, plaster and trims across eight environment families |
| Prop designs | 28 | Administrative fixtures, industrial tools, civilian belongings and inhabited spaces |
| Character designs | 14 | Civilian free people and issued Union roles, with distinct silhouettes |
| Weapon designs and finishes | 14 | Recognizable civilian mechanisms and restrained advanced equipment |
| Environment key art | 7 | Composition and atmosphere references, not gameplay screenshots |
| Water detail | 7 | Ripples, sediment, shore, foam and caustics; two incorrect panel outputs are retained for review only |
| Wear, personal detail and cloth | 21 | Faction history, repairs, belongings and fabrics |

These are source images, not finished 3D models. A studio floor, invented
text or mismatched joint cannot become geometry merely by reducing the image.
Character and prop references guide local model authoring. The seven fabric
requests produced industrial panel layouts and remain unselected for cloth.
Some machine
designs still disagree with established combat bodies and need adaptation.
Latch's generated references place the antenna on the wrong side; the live
model follows anatomical left and remains the source of truth for that anchor.

The current runtime selects quiet material tiles for Union facilities,
rail yards, Low Water, scrap venues and the lunar archive/port. Existing
regolith, glass and pressure repair surfaces remain where appropriate. It
uses ripples as bounded lit water detail and selected wood/metal/enamel
sources as model finish variation. Mars and ship libraries are future sources,
not evidence that their campaign missions are implemented. Broad lunar panel
outputs are design candidates, not substitutes for quiet floor or plaster.

`EnvironmentTextures.path_for` owns wall/floor selection. The
[model sources](../models/README.md) and existing character bake own geometry,
animation and paired normals. Original keyed signs remain separate from art
so labels stay readable and localizable. The water shader provides shallow
surface motion and lighting, not swimming physics or screen-space reflections.

Review exports can be refreshed with:

```sh
godot --headless --path client --script ../tools/prepare_production_art.gd
```

The exporter reads bounded ledger snapshots made after each producer exits,
never a concurrently locked live ledger. It skips unchanged source/output
hash pairs. Per-batch contact sheets go to ignored diagnostics; selected
runtime tiles are prepared with the existing reducer and seam tool.
The [art excellence plan](../../../docs/plans/art-excellence.md) tracks
rendered inspection, tests, estimates and remaining quality acceptance.
