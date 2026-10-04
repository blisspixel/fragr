# Latch live mesh presentation

**Status:** implemented locally, 2026-10-04. Full M02 departure acceptance remains
in flight. Main base `a8611d04`; shared cast preparation
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
captive. The separately labelled ordinary finite-supply route retains every
original combat, support-fire throttle, first-Crawler no-damage, release,
handoff and departure gate. No map, grants or difficulty rules change here.

The first adjusted run, `.agents/m02-latch-art-1/`, completes 18 states and all
four crossfire guards. Real owner events confirm eight `floor_shells` at feet
(-2.365398, 0, -4.9552794), snapshot tick 1478, and 40 HP from `floor_medkit`
at (11.994792, 0, 3.4636776), snapshot tick 1597. The following Crawler gate
correctly fails: the explicit Shotgun selection carries zero shells forward
while 26 bullets remain, and visible inactive bodies stop the search outside
the authored encounter trigger. The correction selects the owned Tack within
its actual 30 metre band and walks through the existing trigger before firing.
Shared movement reaches (0.018872, 0, 10.71742), with unchanged solids.

The next full repeat, `.agents/m02-latch-art-2/`, fails earlier at the original
pack gate: all three Crawlers fall, but the active Sweeper retains six HP at
2.388 metres with clear sight. The twelve starting shells have been consumed;
human HP is 50 and no other gun has been acquired. The existing eight-shell
`guard_room_shells` pad was never visited. The final ordinary art route adds
that finite arrival before the unchanged first-Crawler and pack probes.
Shared movement reaches (-2.268329, 3, -28.36091) on the existing gallery.
All failed manifests, diagnostics and logs remain.

The third attempt, `.agents/m02-latch-art-3/`, captures 20 of 24 states
through actual floor-Crawler activation and both required kills. It retains
the original first-Crawler no-damage and pack checks, real release, voluntary
second-bay gesture, one-pawn handoff, support cadence and all four crossfire
guards. Real owner events confirm eight `guard_room_shells` at feet
(-2.2476552, 3, -29.363184), snapshot tick 381; eight `floor_shells` at
(-2.2888281, 0, -4.836745), tick 1553; and 40 HP from `floor_medkit` at
(11.996079, 0, 3.4733381), tick 1773. These are authoritative pickup events
paired with the latest snapshot feet and tick, not independently simulated
arrival facts. Inspected second-bay and actual allied-fire frames show the
new Latch skin in the existing room lighting.

This attempt exits 1: strict pitch acknowledgements fail when framing the
nearby floor supply and after the floor-Crawler fight. The following walk
aborts on that retained failure before the final manifest writer, so this
attempt has captures, native/client logs, source hashes and the real active
service record, but no final `manifest.json`. The real record has zero deaths
and 19 human kills; the mission is still active. Do not call this a clean
whole-route pass or a completed departure. Gantry, dock, departure and fresh-player pacing
need their own acceptance, including the existing strict pitch gate.

Independent review identifies a checker defect: raw `look_at` angles can exceed
the actual 85 degree pitch limit, while the real camera and server correctly
clamp them. Dependency `1a4da5fa` (local cherry-pick `a2aed243`) normalizes the
setter target once and retains the 0.001 acknowledgement tolerance and explicit
pitch assertions. Its real setter regression and combined `test_qa_combat`
pass; an old-behavior mutation is rejected at both extremes. This actual code
correction authorizes one further byte-identical replay, not a route change.

The corrected replay, `.agents/m02-latch-art-4/`, preserves the archived
24-state manifest bytes, seed 42, Standard rules, unchanged map/native and
all finite claims. It passes the near-floor pitch acknowledgement, captures
18 states and retains real release, second-bay action, handoff, opening pack
and support gates. Owner events confirm eight upper shells at feet
(-2.2269588, 3, -29.319885), tick 402; eight floor shells at
(-2.373565, 0, -5.382889), tick 1611; and 40 HP at
(11.99522, 0, 3.4660058), tick 1731. The support probe takes HP from 100 to 15
with three resolved allied Tack hits, and the finite medkit restores HP to 55.
The next crossfire correctly fails on actual participant death with only two
of four required guards defeated. The native resets the mission to attempt 2.
The failure manifest, pickup receipts, diagnostics, source/helper hashes and
environment receipt are retained. This is not a clean full-route or departure
pass. No further route retries belong to this bounded mesh acceptance.

The final runtime and QA script hashes match the captured source receipt. The
exact captured route is archived as `m02-latch-art-3/capture-manifest.json`;
the public route is reformatted to compact LF text with identical parsed data.
Its semantic audit retains all original 22 states and assertions, adding two
finite supplies and the explicit supported selection/activation approaches.
Recorded private hashes refer to the exact capture bytes. Parent owns the
combined source, actual shared
model-library re-export, receipt reconciliation and fresh full CI. This source
change does not complete all ward character art: the second-bay captive still
uses the earlier procedural figure.
