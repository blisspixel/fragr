# Inhabited-world prop sources

The assembled references and three compact candidate models share the game's
angular painted circa-2070 direction. They remain offline under `.gdignore`.
No candidate is selected by a map or desktop runtime.

| Candidate | Prepared source |
|---|---|
| `candidates/air-scrubber.glb` | Fixed service cabinet, filter housings, intake and gauge. Bone enamel and charcoal; provisional 1.65 m height. All 11,910 source triangles remain. |
| `candidates/water-pump.glb` | Fixed motor/pump skid, flange ports and gauge. Muted sage and steel; provisional 1.20 m width. All 11,880 source triangles remain, with 48 separately counted triangles for four grounded mounting pads. |
| `candidates/community-radio.glb` | Civilian charcoal/walnut case, controls, speaker, handle and aerial. Provisional 0.38 m width. All 11,646 source triangles remain. |

Compact embedded paint and normal maps are 1K, with quiet material values and
restrained normal strength. The sources are fixed assemblies; generated seams
do not establish independently moving drawers, controls or machinery.

The [preparation receipt](../../../docs/evidence/world-prop-preparation-20261004.md)
records actual export/reimport geometry, UVs, winding, floor supports and
all-side rendering. Metre dimensions remain provisional until authored placement
and ordinary played use pass. Pumps need separate connected pipe infrastructure;
scrubbers need pressure-service context. Tiny painted dials are not objectives.
Blockers require authoritative collision, shot geometry and reachable routes.

From the repository root, using the pinned Godot binary and private raw sources:

```sh
godot --headless --path client --script ../tools/prepare_world_prop_sources.gd -- art/raw/meshy-pilot-20261003 .agents/world-prop-prepared
godot --headless --path client --script ../tools/verify_world_prop_sources.gd -- art/raw/meshy-pilot-20261003 .agents/world-prop-prepared .agents/world-prop-proof.json
```

Pass absolute paths for raw/output directories when launching from another
working directory. Preparation makes no service request and preserves required
legal metadata. Require clean errors and both commands' own PASS markers.
