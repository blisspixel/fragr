# Pistol

Status: in flight, 2026-10-04. Source route: **New source candidate**, inspected and refined offline. Runtime selection remains open. Included in the first bounded production allocation.
Stable ID: `W-pistol`. Parent: [full-game asset plan](../meshy-full-game-assets.md).

## Lore, use and design

Use: M01 onward.

Compact practical sidearm, substantial grip and readable slide/receiver. Preserve the existing role and identity contract; a new visual source does not implement planned mechanics.

Owners: [WEAPONS.md](../../../docs/WEAPONS.md), [guns.md](../../../docs/lore/guns.md), [CAMPAIGN.md](../../../docs/CAMPAIGN.md). All briefs also follow the [art bible](../../ART_STORY_BIBLE.md), [palette](../../palette.json) and [character continuity](../../design/characters.md). Black/red identifies Union issue; free people and buildings keep individual, place-specific materials. Use angular painted forms and coherent pixel clusters in a practical circa-2070 world.

## References

Existing reference basis: [weapon_pistol.png](../../../client/art/production-20261003/weapon_pistol.png). These are design candidates, not approved orthographic sheets or completed models. Review every side and correct conflicts against the owners above.

Record the selected reference paths and hashes, front/side/back silhouette, scale, intended material roles and independently moving parts. Named faces and proposed mechanics require a reviewed identity/role sheet. Remove studio/background artifacts from conversion inputs. Prior wrong-side antennas, unsuitable cloth-panel and water outputs remain historical.

## Parts and motion

Muzzle, trigger grip, support contact; separate slide if visible.

The reviewed source now lives at `client/art/models/candidates/pistol.glb`.
It preserves all 5,154 source triangles across Body, Slide, Trigger and Hammer,
with a separate 60-triangle curved trigger blade and 120-triangle recoil guide.
Five bounded dark sight/seam parts add 300 triangles separately, for 5,634
total gun triangles. Broad face-painted top and side groups keep the slide
readable without chrome. The held bake uses a modest three-quarter view that
exposes the actual ejection port and grip while preserving muzzle registration.
The front recoil plug moves with the slide through 12 mm; the actual barrel,
bore marker and receiver stay fixed within the recoiling gun. Local work
gloves maintain grip and index contact below the slide and sight line.
Prepared maps are embedded at 1K, with nearest sampling and no generated LOD.
The source is 24 cm long, about 20 cm high and less than 5 cm wide.

The [bounded refinement plan](../pistol-source-refinement-20261004.md)
owns source checks and the actual presentation comparison. Its 224x180 held
and fire canvases and 36x26 pickup canvas come from this source, without a
magazine, reload, ammunition grant or altered shot timing. Candidate pixels
remain offline until the played comparison and packaging gates pass.

Author rigid weapon mechanisms, grips and effects locally. Humanoid rigging does not apply to guns or equipment. One accepted source supplies held, pickup and icon views.

## Integration and acceptance

Use the existing model/source, bake, equipment, actor or map presenter seam. Keep source candidates offline until selection passes. Embed compact prepared maps, preserve legal notices, record source/output hashes, keep nearest pixel filtering and measure actual geometry rather than the requested target. Every apparent blocker needs authoritative collision and shot geometry.

Inspect front/side/back and real moving parts. Compare the old and new asset at the same player resolution, distance and venue light; test contact, facing, occlusion, clipping and actual state transitions. Capture an ordinary played use or encounter and clean retirement, then verify the packaged asset. CI is separate from hardware and subjective fun evidence. Do not sacrifice route, supply reachability, target contrast or useful cover to decorative density.

## Credit reservation and next operation

Reserve at most 35 credits for a first 7.1 textured candidate, or 15 for a suitable inspected Smart Topology candidate. The shared revision reserve is separate. The first allocation is capped at 900 included credits across twelve new sources, suitable rigs and justified revisions.

Before every paid stage, use the existing native free balance checker and shared account ledger, retain uncertain holds and price the exact options. Record actual reported consumption. No new cash, renewal, pack purchase, top-up or overage is authorized by this plan.
