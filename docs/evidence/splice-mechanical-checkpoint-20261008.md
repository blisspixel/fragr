# Splice source diagnostic checkpoint

Status: in flight, 2026-10-08. The bounded
[mechanical source plan](../plans/splice-mechanical-source-20261008.md) has
read-only geometry measurements and unaccepted original-triangle labels at this
initial checkpoint. It claims no prepared skin, accepted pivot, motion, live
selection or paid operation.
The [machine receipt](splice-mechanical-checkpoint-20261008.json) binds exact
local source, tools, reports and retained failures.

On October 8 the receipt's historical plan pointer was relocated to retained
identical historical bytes after the owning plan grew. The reconstructed
8,411-byte snapshot matches the original recorded SHA-256
`1acc0f1f6690af560ae97226427720fa1af7648ef75d86cfc6906b584ab4aa62`.
The original receipt remains unchanged in ignored diagnostics, SHA-256
`4c3e5efb258a0d4bafb497a45488c8cfaf8b93bde7e07d6b0b59adf7a3747942`.
The amended receipt explicitly records both paths and this relocation; the
current plan is not represented as the original loaded source. Later partition
and motion work has a [separate candidate receipt](splice-mechanical-candidate-20261008.md).

## Original source and measured boundaries

The pinned retained GLB is
`art/raw/meshy-pilot-20261003/splice-named-v1-ultra-0.glb`, SHA-256
`4560940190c9877b78885e3138c5e3628e9bfe906474ca14f54986931bbe19f1`.
Four previously retained full-size originals were inspected again for the
horizontal screen, left rust forearm, right magenta wrist and actual right-hip
rack. Source sides and physical joints still need labelled geometry review.

| Original measurement | Result |
|---|---:|
| Vertices / triangles | 27,283 / 16,602 |
| Meshes / materials / skins / clips | 1 / 1 / 0 / 0 |
| Original base map | 4096 x 4096 |
| Indexed components | 5,401 |
| Components after coincident welding at 1e-6 m | 1 |
| Geometry / UV degenerates at 1e-12 | 0 / 0 |
| Face winding disagreement with supplied normals | 0 |
| Original welded open / nonmanifold edges | 68 / 93 |

The complete original triangle CSV records indices, centers, normals, UV centers,
original paint samples and actual face/UV areas. The source remains unchanged.
Disconnected UV islands do not establish independent mechanical parts.

## Actual checks and rejected proposal

The first 16-label diagnostic retains each original triangle exactly once, with
unchanged attribute buffer payloads and winding at identical rest transforms.
It adds zero closure triangles. Six negative controls alter actual normal/UV
bytes, reverse winding, duplicate or omit a source face, or displace a part;
each fails the source gate after the unchanged positive control passes.

This establishes exact static coverage, not a correct rig. The actual welded
interface audit finds 810 cross-label edges, including unwanted hand-to-upper-leg
and torso-to-forearm boundaries. The right rack is explicitly unresolved within
an upper-leg label. The proposal is rejected for moving parts. No pivot, collar,
cap, tool grip or motion acceptance is inferred from its passing byte checks.

The first paint diagnostic inverted texture V and is retained as rejected. The
corrected sampler uses the existing raw source reader's direct V. A subsequent
rest-transform check incorrectly compared parsed numeric types; that exit-1
attempt is also retained. The corrected positive coverage gate and all six
negative controls exit 0 with clean logs and their own PASS marker.

## Reproduction and scope

Use the pinned Godot executable with these actual source commands, substituting
a fresh absolute ignored output directory to preserve retained attempts:

```powershell
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script ../tools/audit_splice_source.gd -- C:/GitHub/fragr/.agents/splice-mechanical-source-20261008/raw-final
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script ../tools/partition_splice_diagnostic.gd -- C:/GitHub/fragr/.agents/splice-mechanical-source-20261008/labels-v4
```

The tools refuse overwrite. Logs were copied byte-identically from the original
Edda-lane diagnostic directory into their owning Splice output directories;
originals remain retained. No renderer, native build, generation request,
packaged asset, shared presenter or mission code changed in this checkpoint.
These checks use the original static geometry and do not establish grounding,
animated contacts, ordinary appearances, final art, performance or package
acceptance. Geometry-guided partition refinement and inspected physical joints
come next under the existing zero-credit plan.
