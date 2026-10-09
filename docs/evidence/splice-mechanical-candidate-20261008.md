# Splice rigid source candidate

Status: in flight, 2026-10-08. A source-only rigid candidate passes the geometry
and inspected source controls below. Compact materials, exported runtime source
and ordinary mission selection remain open under the
[existing plan](../plans/splice-mechanical-source-20261008.md). The separate
[machine receipt](splice-mechanical-candidate-20261008.json) binds retained
originals, failures, frozen tools, actual measurements and renderer receipts.
Zero external requests, model credits or cash were consumed.

Subsequent compact export and actual reloaded clip/support validation are
recorded in the [separate compact source receipt](splice-compact-source-20261008.md).
This receipt retains the earlier source-candidate checkpoint and its scope.

## Geometry and measured motion

The unchanged original source SHA-256 is
`4560940190c9877b78885e3138c5e3628e9bfe906474ca14f54986931bbe19f1`.
The first 16-label diagnostic remains rejected: its 810 cross-part edges include
unwanted hand/leg and forearm/torso interfaces. The geometry-guided candidate
keeps all 16,602 original triangles exactly once, with unchanged position,
normal, UV and winding payloads. It has 17 regions, 586 cross-part edges and zero
interfaces outside its declared parent hierarchy. Its retained labels GLB has
SHA-256 `f2191a008a44537b821b80da5bdf181958f69890bf6b9d388a51e1d75ebeb7a8`.

Pivots are means of measured original welded interface endpoints, using a
1e-6 m weld tolerance. Each rigid part retains its original source surface.
The separate stored rack label shares the right upper-leg transform with the
remaining original rack/tool surfaces. It is not a complete independent tool
mesh, grip or socket. The actual rust left forearm, magenta right wrist, horizontal
screen and right-side attachment remain in their original anatomical regions.

The current closure adds 908 separately counted flat dark triangles at actual
original opening edges. Original already-closed nonmanifold edges are counted
separately; the new cap triangles have zero geometric degenerates. The parent
and child caps follow their own source boundaries and meet at the common
measured hinge center. Original source triangles are neither hidden nor removed.

| Actual source measurement | Result |
|---|---:|
| Standing rest height | 1.79999995 m |
| Maximum reversible rest error | 1.193e-7 m |
| Off-grid calm / walk phases | 128 / 128 |
| Maximum supported original sole error | 1.193e-7 m |
| Maximum cap-to-original welded rim error | 0 m |
| Maximum common hinge-center error | 1.238e-7 m |
| Maximum original uncapped seam separation | 0.024886 m |
| Shared-parent rack transform drift | 0 |
| Actual indexed walking sole displacement | 0.243948 m |

The zero rim result concerns original welded representative points, not exact
identity among all raw UV-duplicated positions. The measured original seam
separation is retained explicitly; the paired caps close each actual opening
instead of reporting that original separation as zero. Whole-body supported
height is source presentation, not authoritative movement or collision.

Seven real source alterations fail the exact coverage or anatomical identity
gates: normal bytes, UV bytes, winding, duplicated face, omitted face, displaced
part and swapped anatomical surface ownership. Motion checks separately reject
an omitted cap, a detached stored rack, a floating root and a displaced head
pivot. The displaced-pivot control still reconstructs the rest pose, then fails
actual motion. Positive controls establish real indexed sole motion and that
the adversarial rest pose still matches.

## Inspected originals and retained rejection

A previous 2,352-triangle spherical closure passed numerical coverage but
visibly covered mechanical hip, wrist and other detail with large black bulges.
It is rejected. Its exact seven source snapshots, geometry report, 24 static
originals and 96 timed motion frames remain retained separately. Its first
geometry attempt also retains owner warnings; that attempt is not clean
acceptance. The later clean sphere measurement does not override its visual
rejection.

The revised cap renderer exited 0 with clean logs and retired its exact owned
process. It retained 26 static originals and 96 timed source-motion frames on
the local AMD Radeon 780M with the compatibility renderer at 1024 x 768.
All 26 static originals and eight moving originals were inspected at full size.
The moving samples cover quarter phases across both recorded cycles; this does
not claim inspection of every motion frame or a hardware frame-rate benchmark.

The source controls preserve rest silhouette, original mechanical detail and
anatomical paint identity from front, both sides and back. Walking side/back
views preserve the supported sole and shared stored attachment. Neutral and dim
joint close-ups preserve shoulder, hip and wrist detail without the rejected
sphere bulges. The dark caps remain contained inside the reviewed mechanical
silhouette. The source still uses original paint/normal maps at 4096 square and
the packed material map at 2048 square; matte compact conversion and final game
art remain open. All three dimensions were checked during the next compact
conversion preflight, rather than inferring material-map size from paint.

These public images are byte-identical copies of the retained originals:

| Control | Original |
|---|---|
| Untouched raw source | [Raw front](splice-mechanical-candidate-20261008/raw-front.png) |
| Rejected sphere treatment | [Rejected front](splice-mechanical-candidate-20261008/rejected-spheres-front.png) |
| Revised rest silhouette | [Rest front](splice-mechanical-candidate-20261008/caps-rest-front.png) |
| Revised walking side | [Walking side](splice-mechanical-candidate-20261008/caps-walk-side.png) |
| Revised walking back | [Walking back](splice-mechanical-candidate-20261008/caps-walk-back.png) |
| Dim front joints | [Front close-up](splice-mechanical-candidate-20261008/caps-joints-front-dim.png) |
| Dim back joints | [Back close-up](splice-mechanical-candidate-20261008/caps-joints-back-dim.png) |

## Reproduction and remaining gates

Use fresh absolute ignored output paths with the pinned local executable. The
receipt binds the exact pre-render tool snapshots; current tooling may later
advance independently. The frozen scripts retain their existing helper paths.

```powershell
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script ../tools/refine_splice_partition.gd -- C:/GitHub/fragr/.agents/splice-new-regions
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script ../tools/test_splice_mechanical_rig.gd -- C:/GitHub/fragr/.agents/splice-new-regions f2191a008a44537b821b80da5bdf181958f69890bf6b9d388a51e1d75ebeb7a8 C:/GitHub/fragr/.agents/splice-new-geometry.json
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --path client --rendering-method gl_compatibility --script ../tools/preview_splice_mechanical.gd -- C:/GitHub/fragr/.agents/splice-new-regions f2191a008a44537b821b80da5bdf181958f69890bf6b9d388a51e1d75ebeb7a8 C:/GitHub/fragr/.agents/splice-new-preview
```

Compact matte maps, exported/reloaded hierarchy and caps, complete limb-length
and stored-attachment contract, support curves and live adapter integration
remain open. Individual tool grips, physical tool use and finger articulation
are not claimed. Source geometry work remains in ignored diagnostics while
shared client composition is frozen. Ordinary eligible and omitted M05 workshop
and later crew routes, current-map captures, composed client and package checks,
final art and human acceptance remain separate requirements. No production
character resource, server build, source selection or live mission asset changed.
