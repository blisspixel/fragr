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
near fade and actual mission route inspection remain pending. Full client
checks are running; these focused and exported gates are not whole acceptance.
