# October 4 source production and credit reconciliation

Source production is in flight. These receipts establish completed source tasks
and local inspection, not selected runtime assets or finished game coverage.
The [190-brief catalog](../plans/meshy-full-game-assets.md) owns the scope;
the roadmap remains the only global build sequence.

## Credits

The free native balance check after the Rifle task on 2026-10-04 reports
**2,625 API credits**, **15 uncertain local credits held**, and **2,610 usable**.
It submitted zero generation requests. The uncertain hold stays reserved.

| Operation in the first 900-credit allocation | Actual included credits | Disposition |
|---|---:|---|
| Enforcer 7.1 Ultra model | 35 | Completed source, inspected skin preparation in flight |
| Enforcer humanoid rig | 5 | Completed, 24 bones and retained gait inspected |
| Crawler Smart Topology model | 15 | Rejected: six legs conflict with its four-leg combat silhouette |
| Crawler 7.1 Ultra model | 35 | Four-leg source inspected, local mechanical poses and paint refinement in flight |
| Pistol Smart Topology model | 15 | Completed source, independent mechanisms prepared locally |
| Rifle Smart Topology model | 15 | Completed source, all-side inspection performed; compact preparation remains open |
| **Actual allocation consumption** | **120** | **780 credits remain inside the 900-credit ceiling** |

The shared ledger now tracks **445 consumed credits** across historical and
current tasks. The separate historical 30-credit account decrease remains
unattributed. No new cash, subscription change, pack, top-up or overage occurred.
Higgsfield's last user-reported dashboard balance is $14.42; it is not a fresh
API balance. Conversion-reference uploads used its free upload endpoint.

Eight families in this allocation still need first candidates: Jammer,
non-Latch free agent, Railgun, Sniper Rifle, repair workbench, community radio,
water pump and air scrubber. At 35 credits each and one suitable five-credit
humanoid rig, their first source tasks would cost at most 285 credits before
revisions. This is source pricing, not a promise of accepted assets. Current
credits cover that bounded work; there is no reason to buy a pack for this cut.

Exact pricing and image-to-3D options were checked against the
[official API prices](https://docs.meshy.ai/en/api/pricing) and
[image-to-3D contract](https://docs.meshy.ai/en/api/image-to-3d) on 2026-10-04.
Every paid stage used the existing native developer tool, a free immediate
balance/hold preflight, the shared account ledger and explicit credit/USD
equivalent ceilings. Guns use local pivots, not humanoid rigging.

## Weapon source inspection

| Source | Actual geometry | Source SHA256 |
|---|---|---|
| Pistol | 5,154 triangles, 5,445 vertices, one mesh, 61 spatially joined islands | `9c097088ab52e63730d6ec4494180c4663b812016035c490a06a19bf51a51318` |
| Rifle | 6,122 triangles, 6,511 vertices, one mesh, 55 spatially joined islands | `5d53e8995a825b4e594c9b812759dcb070342bfddc73bd64ba351ea9a0576394` |

The new references retain original practical civilian forms, warm walnut,
charcoal steel and individual sage repairs. They avoid a uniform Union issue
appearance. Reference hashes are
`72a76bd37930e2b1e682f87bd935222f598b047e200d30ef9a24d7230505bd91`
(Pistol) and
`fa4f218e10bb5c40d4671c874b9f8769b9581c9a7d7e85fed8cf8a4de9c7989f`
(Rifle). Both used textured standard Smart Topology with 4K service maps and
an explicit fifteen-credit, $0.30 equivalent ceiling.

Four actual Godot views of each source were inspected on Radeon 780M using
the Compatibility renderer. Pistol preparation embeds nearest 1K maps and
preserves all source triangles in separate receiver, slide, trigger and hammer
groups. Eleven studio motion frames prove a measured 12 mm slide stroke,
stationary receiver and return to rest. It still needs a clearer trigger,
front guide refinement, fitted hands and actual held/fire/pickup/near-clip review.
Rifle inspection found coherent stock, grips, sights, guard and barrel, with
local material and mechanism preparation still required. Neither studio test
is an ordinary gameplay test.

The first private Pistol motion capture incorrectly aimed its camera before
adding it to the scene tree. Its error log was retained and that capture was
rejected; the corrected run exited zero with its PASS marker and clean logs.
Prepared Pistol byte/hash snapshots remain private because further refinement
is in flight. Public source selection will carry its own immutable receipt.

## Character acceptance still open

Enforcer source and weighted motion inspection pass; the full M09 rendered
encounter route remains in flight. Crawler preparation retains four articulated
limbs and paired directional normals. Its first bake applied noisy material
highlights twice. Subsequent local paint trials removed excessive wear, then
corrected an over-dark chassis. A complete played route, settled corpse review
and stair support acceptance remain open. An actual sprite footprint straddled
several stair heights; a global sprite offset would conceal that geometry issue
and has not been applied.

No offline source replaced selected presentation merely because a provider
task succeeded. Final promotion still requires consistent pixel clusters,
readable silhouette, actual motion and contact, ordinary combat or equipment
use, clean retirement, offline packages and the applicable full CI checks.
