# Edda and Splice reference audit

Status: reference and source planning completed, 2026-10-05. No new reference
image, model, rig or runtime asset was generated or selected. The
[bounded plan](../plans/edda-splice-cast-sources-20261005.md) and
[fingerprint receipt](edda-splice-reference-audit-20261005.json) record the scope.

## Existing evidence and actual gaps

| Inspected input | Useful continuity | Required correction |
|---|---|---|
| [Historical medic](../../client/art/production-20261003/character_free_human_medic.png) | Practical closed shoes, work clothes, a medical bag and approachable competence | Photographic skin, hair and fabric; realistic long coat; a small medical cross; no clear bone apron. It is role context, not an approved Edda face or suitable conversion input. |
| [Current human reference](../../client/art/characters/references/free-human-civilian-v3.png) | Angular facial planes, broad painted clothing, civilian hatless silhouette | It is the default human, not Edda. Do not copy its face, jacket or exact patch layout to every survivor. |
| [Anonymous worker reference](../../client/art/characters/references/civilian-agent/worker-stylized-v1.png) | Modest mechanical proportions, friendly screen, ordinary tools and repairs | It does not establish Splice. Wrist identity and offset rack are missing; realistic fine wear needs compact painted refinement. |
| [Actual anonymous worker front import](../screenshots/civilian-first-sources-20261004/free-agent-worker-stylized-v1-ultra-0-view-0.png) | Coherent separated limbs and grounded feet visible in the retained frame | Dense bright wear, generic silhouette and no named expression/gesture. The prior receipt records 12,462 triangles, one fixed mesh, no bones or clips. Local preparation and live selection remain open. |

All four existing images above were visually inspected at full size. Their
current byte fingerprints are retained. The anonymous worker's
[original source inspection](civilian-first-sources-20261004.md) remains the
authority for its eight prior views and geometry, not a new render in this audit.
The prepared `free_human.glb` and `free_human_source.gd` are available as a tested
humanoid source/IK pattern, but do not supply Edda's apron, satchel or medical
gestures. No specific Edda or Splice GLB exists in the selected main sources.

Main `m05_town.gd` presents workshop captives with the generic synthetic strip
and one small repair patch for Splice. Main `m09_berth.gd` uses reusable human
and synthetic strips with personal tint. The separately unmerged M10
`65f340ff` presenter uses the same provisional cast and ground registration;
its source fingerprint is labeled separately in the receipt. A tint and a patch
are insufficient for recognizable named people.

## Reference requests prepared, not submitted

[Edda's native prompt](../../tools/spritegen/specs/edda-reference-20261005.json)
requests a single isolated A-pose clinician, broad bone apron and warm leather
satchel. [Splice's native prompt](../../tools/spritegen/specs/splice-reference-20261005.json)
requests a compact free technician, individual screen, rust repair, offset rack
and muted magenta band. Both specify high 4k, disabled prompt enhancement, empty
separated hands, neutral light and enough framing margin for conversion.

The face, gathered hairstyle, anatomical accessory sides and screen ratio are
proposals for review. The underlying roles, apron/satchel, compact tools/rust
repairs and magenta band come from current cast canon. Reference acceptance
must distinguish these before a named model is requested.

| View | Edda review | Splice review |
|---|---|---|
| Front | Broad apron leaves both legs and hands readable. Satchel sits on anatomical left; strap attaches over the opposite shoulder. Calm painted face and hair stay visible. | Horizontal screen and lean shoulders read as an individual civilian. Left rust forearm, right magenta band and attached left-hip rack stay identifiable. |
| Both profiles | Apron and sleeves separate from body; satchel flap has depth and support. Shoes and toes contact the same baseline. No fused hands or floating strap. | Screen housing has depth; neck and all limb pivots connect. Rack sits behind the hip without penetrating elbow or knee travel. No military back plate. |
| Back | Strap and apron ties attach plausibly without becoming a heavy backpack. Body remains recognizable when facing away. | Rack sockets and two secured tools have real attachment; cabling terminates at housings. Personal repairs continue consistently, no duplicated antenna or hidden limbs. |

Do not feed a multi-view collage into a one-character conversion stage unless
the owning tool explicitly supports it. One accepted isolated reference is the
first conversion input. Actual model front, back and both sides establish
geometry consistency afterward. An attractive front image cannot prove those
other sides.

## Source machinery and motion contracts

| Object or part | Proposed local seam | Acceptance still needed |
|---|---|---|
| Edda body | Distinct candidate path with the existing virtual source cache and humanoid IK pattern | Actual limb inspection before optional 5-credit rig; measured skin and walk, stationary root, fixed feet, compact embedded maps. |
| Apron, strap and satchel | Skin-compatible apron panels, rigid bag and recorded strap attachment points | No detached apron during turns; no body penetration through gait; flap/latches remain attached. Independently authored motion is counted, not assumed from generated seams. |
| Edda medical hands | Local hand-to-satchel and hand-to-lamp grip sockets, empty neutral pose | Packing, offering help and pointing are presentation gestures only. A held lamp is separate bounded local equipment, not a new pickup or healing rule. |
| Splice head and expression | Rigid neck pivot, compact screen with local pixel expression surface | Distinct friendly/impatient expressions without forced combat tells, emissive flooding or Latch impersonation. |
| Splice limbs | Measured rigid shoulder/elbow/wrist/hip/knee/foot pivots with explicit collars | All original triangles retained, additions counted, sweep/contact checks, planted gait and no disjoint fragments. A paid humanoid rig is not the default. |
| Rack, tools and wrist band | Hip-relative rack/storage sockets; separate blunt tool and hand grips; wrist-relative band | Tool remains secured when idle and meets hand when used. Rack does not catch the body during gait. Band follows the chosen wrist consistently in every direction. |

Walking and sitting for the actual passenger state are the immediate integration
needs. Treatment, repair advice, lamp handling and packing are later authored
gestures, not implemented simulation abilities. A generic eight-frame strip
cannot prove that these actions or expressions exist. Preserve existing actual
feet, human-sized contact, actor visual layer, fixed-Y shadow-correct billboard,
nearest filtering and accepted mission facts; derive the named strip layout from
the owning presenter rather than assigning enemy combat clips to civilians.

## Outcome and acceptance boundaries

Edda eligibility follows the recorded M04 clinic-team outcome. Do not relabel a
held patient as Edda, manufacture individual historical survival or populate a
historical Unknown roster. Splice eligibility requires actual M05 evacuation,
not only a released workshop. Assets do not change saves, collision, equipment,
finite supplies, mandatory departure or Orrin restoration.

Future source selection requires a same-camera old/new ordinary M05/M09/M10
appearance, visible 2 m/5 m/12 m reads, close approach and stair/turn contacts,
all eligible/omitted rosters, clean resource retirement and unchanged server
outcomes. M10 remains a separate unmerged prototype. Its current ground feet are
Edda `[2,4.8,-14]` and Splice `[-2,4.8,-14]`; these are location facts, not new
socket offsets. Full client, exact CI and desktop packages remain later gates.

## Validation and spending

The native prompt JSONs parse successfully and contain one specific frame each,
high/4k/1:1 settings and disabled enhancement. Existing reference and source
fingerprints, the distinct M10 prototype hash and prompt hashes are recorded.
Only this plan, this audit, its JSON and the two prompt specifications change.
There was no new renderer, gameplay test, source conversion or paid submission.

The [plan's budget](../plans/edda-splice-cast-sources-20261005.md#bounded-budget-proposal)
reserves at most 70 model credits plus an inspected optional Edda rig. It uses
the root-provided current 2,235 available/15 held reading and first-allocation
390 remainder, retaining the glove 35-credit allocation. Image caps are $0.65
each; the latest comparable $0.622 quote is a preflight reference, not a new
charge. Root owns fresh price/balance checks, every submission and the single
ledger. Actual new consumed credits and cash charges in this leaf: zero.
