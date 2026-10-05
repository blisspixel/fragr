# Edda and Splice source production

Status: in flight, 2026-10-05. Two named source candidates are inspected offline.
Their current generic runtime strips remain selected. This receipt extends the
[bounded plan](../plans/edda-splice-cast-sources-20261005.md) and preserves the
earlier [reference audit](edda-splice-reference-audit-20261005.md).

The reviewed references use angular painted forms and civilian circa-2070
workwear. [Edda](../../client/art/characters/references/named/edda-v1.png) keeps a
bone apron, dark clothing, gathered hair and closed left-hip medical satchel.
[Splice](../../client/art/characters/references/named/splice-v1.png) keeps a
horizontal screen, lean practical chassis, left rust forearm and right magenta
wrist band. The actual tool rack is on the right hip, differing from the proposed
left-side prompt. Both 2,880-square references have an opaque checker-pattern
background, not transparency; neither is a finished sprite. Metadata
normalization retained exact decoded pixels. Fingerprints live beside them.

Each source request used textured 7.1 Ultra, 2k geometry, 4k maps and a 16,000
triangle target, under a 35-credit and $0.70 equivalent ceiling. Actual output
counts differ from the target. Each is one fixed mesh with original paint,
normal and physical material maps, initially without bones or clips.

| Source | Task | Actual triangles | Actual vertices | Consumed credits |
|---|---|---:|---:|---:|
| Edda | `01a10c56-b434-743b-b502-68e6a20f03a4` | 14,694 | 17,558 | 35 |
| Splice | `01a10c58-f991-7703-9cd9-69527c78f6d4` | 16,602 | 27,283 | 35 |

Raw fingerprints are
`1f68658b7328fa362d5ea785e3df98baed3fdf645e15ad48adbc3683926dfdcf`
and `4560940190c9877b78885e3138c5e3628e9bfe906474ca14f54986931bbe19f1`.
The [sanitized receipt](named-cast-source-production-20261005/receipt.json)
records exact source measurements and reference hashes. Raw files and private
service URLs remain in the ignored shared account ledger.

Four views of each model were inspected using Compatibility on an AMD Radeon
780M. Both owned renderer processes exited 0 with clean logs and their own PASS
markers. Edda's face, apron, shoes, separate limbs and closed satchel are readable
from every side. Splice's screen, replaced forearm and limbs retain the reference
silhouette; the rear black head panel and noisy physical finish still need local
design review. No moving mechanical parts have been partitioned.

| Cast | Front | Side | Back | Other side |
|---|---|---|---|---|
| Edda | [View](named-cast-source-production-20261005/edda-0.png) | [View](named-cast-source-production-20261005/edda-1.png) | [View](named-cast-source-production-20261005/edda-2.png) | [View](named-cast-source-production-20261005/edda-3.png) |
| Splice | [View](named-cast-source-production-20261005/splice-0.png) | [View](named-cast-source-production-20261005/splice-1.png) | [View](named-cast-source-production-20261005/splice-2.png) | [View](named-cast-source-production-20261005/splice-3.png) |

Edda's clear humanoid limbs justified one separately capped 5-credit rig stage,
task `01a10c5d-16d6-770e-be03-50550dfec461`, requested at 1.8 m. It reported five
credits consumed and returned three GLBs with 24 bones. The walking output has
14,694 triangles, 17,561 vertices and a 1.0667-second clip; its fingerprint is
`bb5511f280147bb3f4fa81db6ce1b42a58cb10daebdf486def6a807d3286693f`.
The actual import bounds measure about 1.79997 m high.

Four walking samples were inspected. At the final sampled phase the satchel
stretches into a fin toward the left hand. The [defect](named-cast-source-production-20261005/edda-walk-defect.png)
is retained, and this rig is rejected for selection. Local satchel, strap and
apron weight repair needs actual surface and motion proof. No replacement paid
rig was submitted. Splice will use measured local rigid pivots by default.

The two models and Edda rig consumed **75 included credits**. Together with the
earlier 35-credit glove stage, this October 5 work consumed 110. The fresh free
checker reports **2,125 available**, the unchanged **15-credit uncertain hold**,
and **2,110 usable**. Tracked total consumption is 945; 620 of the first
900-credit allocation is used, leaving 280. The historical 30-credit unexplained
account decrease remains separate. No cash charge, renewal, pack, top-up or
overage was enabled.

The exact image reservations were $0.625 for Edda and $0.627 for Splice, each
under a $0.65 cap. Including the glove reference's $0.622, new reservations total
$1.874. Subtracting that from Nick's reported $14.42 gives an estimated $12.546
remaining. This is reservation accounting, not a verified image-account balance
or billing receipt.

Source production does not establish finished cast coverage. Compact material
preparation, corrected motion, role gestures, rescue and eligible-ship comparison,
full client checks, matching CI and desktop packaging remain open.
