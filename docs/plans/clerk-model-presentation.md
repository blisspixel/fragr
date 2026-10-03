# Clerk model presentation

**Status:** shipped on main, 2026-10-03, through
[PR #340](https://github.com/blisspixel/fragr/pull/340), after
[full CI](https://github.com/blisspixel/fragr/actions/runs/37158959870) passed.
Desktop package verification uses the tag's release workflow. This closes the bounded source
selection within the existing roadmap's art rung, not broader art acceptance.
[Rendered evidence](../evidence/clerk-model-20261003.md) records the scope.

## Goal

Turn the reviewed humanoid source into a detailed directional Clerk without
changing combat, phase timing or the server-owned body. Preserve a recognizable
human face, charcoal cloth, bone armor, restrained red issue marks and
the circa-2070 industrial direction. Pixel presentation must remain readable in
actual rooms and motion. New source is a candidate until the played gate passes.

## Implementation

Reuse the existing character baker, EnemyAnimation layout and normals shader.
Prepare a compact, embedded source locally, retain skin and gait, and preserve
required legal notices while removing optional software-authorship metadata.
No new paid calls. Keep source in excluded offline art, with hashes in the bake
receipt. Supply armed/unarmed idle, walk, raise, fire, recovery, hit, death and the
M02 seated posture. Match fixed feet and the existing 1.8 m character scale.
Add paired view normals only if rendered light and alpha registration agree.

Any new asset is unfinished if source/output hashes disagree, poses clip a tile,
weapons disappear behind shoulders, or the result loses attack/death readability.
Do not ship a static A-pose as a fighter. The current presentation remains the
fallback until the full prototype is reviewable and passes the acceptance gate.

The prototype now supplies all 55 existing poses in eight directions, including
a separate physical reaction in the two-cell hit clip. Skin posing waits until
the skeleton enters the tree, so dependent joints see current global transforms.
Prepared source and textures remain excluded offline art. The source, atlas,
silhouette and rendered-light checks pass; the 13-state M01 route and five-state
M02 guard-room recording complete. No additional credits were consumed. Broad
cast acceptance, distant live readability and fresh-player review remain open.

A follow-up corrects the unarmed strike to use a forward reach and lower-torso
lean. The actual hand advances more than 15 cm from its ready pose. All armed
albedo and normal cells remain byte-identical to the recorded guard-room assets;
the unarmed atlas cells and bake receipt are updated together.

## Verification

Inspect rest, gait and all combat clips in Godot, then every direction at game
scale. Require clean imports and logs, unchanged atlas/wire contracts and source
receipts. Run the character and model harnesses, full client checks and a rendered
mission route. Compare live character, tell, impact and corpse readability with
the released presentation. Full CI precedes merging runtime selection. Release
only when the shipped change and capture actually include the selected asset.
