# Latch live mesh presentation

**Status:** in flight, 2026-10-04. Main base `a8611d04`; shared cast preparation
and virtual source helpers from parent dependency `a48fd5b4` (local cherry-pick
`643d3c3f`). No asset generation belongs to this change.

## Goal and continuity

Replace the provisional visible workshop chassis with the reviewed stylized
Latch source in both the ward tableau and server-owned following pawn. Latch
stays a lean, roughly 1.8 metre civilian free agent, worn bone and dark steel,
individual rust repairs, one anatomical-left antenna and friendly screen optics.
Use the already generated rig and the shared preparation helper. Keep the face
as an independently controllable expression/emission surface rather than a
permanent painted expression alone.

## Boundaries and existing seams

`LatchView` remains the shared presenter. Preserve its public pose, release,
weapon visibility, confirmed-shot, render-layer and near-camera contracts, and
the node paths used by the existing ward/pawn connectors. The Rust server alone
owns position, collision, identity, release timing, following and weapons.
Preserve the one-Latch fixed-to-moving handoff, retry and late spectators.

The raw reviewed source and three rig exports are parent-owned under
`art/raw/meshy-pilot-20261003/latch-stylized-v2*.glb`. Original references,
generation metadata and provider receipts remain parent-owned. Prepare one
runtime source through `tools/prepare_clerk_source.gd` with cast name `Latch`,
retaining its skin and bounded walking clip, embedded 1K nearest textures and
the existing metadata cleanup. Match the existing embedded-image import preset
to avoid unwanted texture sidecars. Reuse the reviewed two-bone math in the
bounded live `client/scripts/latch_source.gd` helper; runtime resources must
not inherit from excluded offline `art/` scripts. The prepared live mesh is
`client/assets/models/latch_stylized.glb`, preserving the earlier candidate.
Do not introduce another preparation route.

Inspect the actual skeleton, root transform, feet, forward direction and hand
registration before selecting a rig file. Use native skin deformation for
travel, voluntary second-bay reach and actual carried-gun posing. Keep gesture
and expression derived from current presentation inputs. No authority, mission,
save, protocol, audio or shared GameManager changes belong here.

## Verification and success criteria

- Prepared source imports cleanly, has the reviewed topology, retained weighted
  skin and walking clip, bounded textures, stable foot registration and no
  prohibited author metadata or missing resources.
- Existing Latch identity, release, handoff, weapon and near-clip checks remain
  meaningful. Add focused source/skin checks for actual pose deformation,
  hand registration and material/actor-layer preservation.
- Run focused headless harnesses and full client checks with a matching native
  server. No new native implementation is planned.
- In a parent-coordinated GPU slot inspect actual ward, voluntary hand release,
  walking/following, confirmed weapon fire and near-distance transitions. Record
  exact source and capture hashes. A mannequin render cannot establish mission
  acceptance or fresh-player recognition.
- Record gates, failures and evidence here. Parent owns shared roadmap, index,
  credits, source-art receipts, final integration CI and release publication.

## Spend and scope limits

$0 new calls. Use only the existing downloaded candidates and helpers. No new
runtime or dependency. Own isolated processes and captures; never overwrite the
root native server or compete for the GPU. Commit scoped work as Nick Seal.
Fresh-player recognition, the entire character roster and future campaign poses
remain separate acceptance work.

## Current source and local evidence

The inspected rig exports are idle, walking and running respectively. Rig 1
retains one weighted mesh, 24 bones and a 1.8 metre mesh AABB with feet at zero.
Preparation and import pass with embedded 1K maps and only the walking clip.
The rig has no finger joints. The actual second-bay gesture raises both skinned
arms and rotates the palm; it cannot claim separately articulated fingers.
The existing ward test now measures real hand transforms and retry restoration
instead of the retired procedural finger pieces. Identity, ordered release,
handoff, late observer, skip and all mission assertions remain intact.

Logs live under this worktree's `.agents/`. `latch-source2.log`,
`latch-ward2.log`, `latch-actor2.log` and `latch-near-headless2.log` pass cleanly.
The added source test proves real weighted travel, rest restoration, palm
weapon registration, resolved flash expiry, independent bounded optics,
actor-layer propagation and retained normal/roughness/metallic maps through
the whole-figure near fade. `latch-install-editor.log` includes its intentional
missing-server negative fixture followed by the actual private native PASS.

`latch-export.log` builds a Windows desktop package. The owned exported
`--check-install` process exits zero, clean stderr and PASS in
`latch-packaged-install-owned.log`. Its new gate instantiates the packaged
live presenter and checks actual skin, hand and walking resources. The native
beside that package is the unchanged private capability-33 server, not the root
historical release binary. Runtime mesh SHA256:
`8b1ec57399ec51a70617a42c9777a04347170d5ddf78dc54b67649b3f6992951`.

The first raw inspector ran before scene-tree readiness, so its error log is
retained separately; the corrected deferred inspector is clean. The first
rendered pose inspection caught a head overlay using the rest rotation twice.
The correction uses the actual posed-to-rest head delta. Corrected close,
near fade and actual mission route inspection follow separately. The fitted
independent screen and actual idle, walking, raised palm, Tack and back source
frames are inspected in the Compatibility renderer on AMD Radeon 780M.

The first original-resolution near sweep passes hide, silhouette, coherent
coverage, monotonic fade and opaque distant gates, but its thin upward-offset
far source occupies 863 pixels against the old procedural rig's 1000 pixel
sample floor. Retain that failure. A wider sampling raster (384 by 216) passes
the same floor, but changes the floor as a share of raster area, so that number
alone is not equivalent acceptance strength. The final harness separately
compares the same unmasked and clipped source at the original 320 by 180
resolution, original cameras and both far offsets. It has exactly zero binary
shape mismatches and normalized coverage 1.0 (1121/1121 and 863/863). All close,
upward, translated-anchor, shadow and coverage assertions remain.
`latch-near-source-reference-render.log` passes cleanly and receipts live in
`.agents/m06-buildout-20261001/latch-near-corrected/source-reference.json`.

The final presenter removes obsolete empty leg, arm and hand markers. The
remaining `RightArm` weapon holder tracks the real skinned arm transform; the
gun remains registered at the real palm. The ward calls its actual release
presenter without changing an unused procedural arm. Focused source, ward,
actor and near checks pass in the `*-final2.log` files.

The full isolated checker parses 234 scripts and passes 107 harnesses, with two
accurately retained provenance failures: the parent Clerk helper refactor's
old enemy bake receipt, and the old model library's Latch source hash. Parent
owns real re-export and reconciliation of those shared files before combined
acceptance. This is not a clean whole-client pass.

The unchanged 22-state M02 support route reaches 16 states, real release,
second bay, Low Water, one-pawn handoff and three resolved allied Tack hits.
The finite support-fire throttle reduces human HP from 85 to 20; the next
crossfire correctly rejects participant death with three of four guards
defeated. Keep `.agents/m02-latch-live/` logs, manifest and hashes. Inspected
venue captures show coherent new Latch and the remaining procedural second-bay
captive. Full departure, adjusted ordinary finite-supply route and fresh-player
acceptance remain open. No map, grants or difficulty rules change here.
