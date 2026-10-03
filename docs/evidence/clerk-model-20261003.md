# Clerk model presentation, 2026-10-03

The prepared humanoid now supplies the Clerk's directional campaign presentation.
The 24-bone skin and sampled gait are retained; the existing baker adds armed and
unarmed idle, walk, raise, fire, recovery, reaction, seated and collapse poses.
There are 55 poses at eight angles in the unchanged 160-pixel cell layout.
The game still presents sprites, with paired view normals under venue light.
No source animation decides combat or changes the server-owned body.

The reference fabric was graded to canon charcoal, preserving its face, bone
plates, wear and red issue marks. The source has embedded 1K PBR maps and is
excluded from desktop exports. Raw 4K sources remain in the private production
archive. The bake receipt hashes the prepared source, pose code and both atlases.
Preparation and combat posing used no additional paid generation.

## Inspected renders

- [Directional pose sheet](../screenshots/clerk-model-20261003/poses.png): rows
  are idle, walk, raised pistol, fire, seated and settled death; columns cover
  all eight facing directions. Feet use the established fixed three-metre field.
- [Seated guards in Persons Unknown](../screenshots/clerk-model-20261003/seated-guards.png):
  visible faces and issued gear in the actual guard room before activation.
- [Live guard-room fight](../screenshots/clerk-model-20261003/live-fight.png):
  standing Clerks, ordinary human input and resolved Shotgun impacts.
- [Normal lighting](../screenshots/clerk-model-20261003/normal-lit.png) and
  [opposite light](../screenshots/clerk-model-20261003/opposite-light.png):
  same source and sprite, with body shape responding to the moved light.
- [Unarmed follow-through](../screenshots/clerk-model-20261003/melee.png): ready
  pose above the extended strike, in all eight directions. The lower torso leans
  into the forward reach; the weapon stays absent.

Godot 4.7.2-stable, Compatibility/OpenGL on the AMD Radeon 780M captured these
images. The rendered harness compares actual normal-lit, planar and opposite-light
pixels. It passes for both Clerk and Sweeper. This establishes an inspected
rendering path, not performance on other GPUs.

## Played routes and limits

The Recall Notice enemy route completed all 13 states and four encounter checks.
The first five Persons Unknown side-ward states completed pickup, seated guards
and the two-Clerk fight at 100 HP. The harness retained idle, windup, hit and dead
phase captures, matched both named kills and sampled the presented body frames.
A final 15.201-second, 1280 by 720 recording repeats the latter route after the
unarmed correction and retains game audio aligned to the real capture timestamps.
Receipts are under `.agents/art-playthrough-20261003/clerk-m01-route` and
`clerk-m02-realtime` and `clerk-final-m02-realtime`; the final recording is
`fragr-clerk-guard-room-20261003.mp4`.

Existing atlas gates pass for every unclipped direction, distinct gait, low
settled corpse and different human/bot silhouettes. The pistol's raised outline
clears the shoulder without making the human as broad as a Sweeper. New checks
verify the actual posed grip, physical foot motion, reaction, seated knees,
weapon-free melee and matching normal alpha throughout the atlas.

The automated routes are authored evidence. Some Recall Notice stills frame
occluded enemies, and the guard-room table obscures settled corpses. They do not
establish long-distance live readability, fresh-player discovery or difficulty
acceptance. Fingers and uniform variants remain candidates for further refinement.
The Shotgun and generator from the pilot are not selected by this change, and
the other character sources and environmental kits remain unfinished.

The final local client gate passes 220 scripts and 101 harnesses, including the
Clerk follow-through and prepared Shotgun source. The prepared import
keeps textures embedded losslessly without duplicate loose image sources. The
armed albedo and normal cells match the recorded route's assets byte for byte.
The subsequent unarmed correction changes its strike cells and bake receipt.
Its source check proves a forward hand advance greater than 15 cm; the full
atlas checks retain unclipped directions and distinct human/bot silhouettes.

The source selection merged through
[PR #340](https://github.com/blisspixel/fragr/pull/340) after
[full CI](https://github.com/blisspixel/fragr/actions/runs/37158959870) passed.
Desktop package evidence lives in the tag's release workflow and release assets.
Subsequent refinements are tracked by the
[presentation plan](../plans/clerk-model-presentation.md).
