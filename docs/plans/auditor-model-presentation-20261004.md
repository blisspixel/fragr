# Auditor source and custody poses

**Status:** in flight, 2026-10-04.
**Spend:** $0 new calls. Reuse the reviewed local source and completed rigs.

## Goal and scope

Replace the Auditor's procedural body with the reviewed stylized black/red
officer while preserving the custody silhouette and every existing combat and
repair fact. Keep the long coat, peaked cap, frontal plate, cable/spool, lowered
pistol during a channel and visible raised emitter. The emitter must physically
reach 1.35 m above fixed feet, matching `AuditorChannels`. Broad mission art,
new enemy behavior and overall campaign acceptance are outside this increment.

## Existing seams

Use main `a8611d04` and the prepared-cast helper dependency `a48fd5b4`.
The unique source presenter derives from `client/art/models/clerk_source.gd`
with an Auditor source path and pose name. Reuse its skin, walk sampling and
arm solve; add custody-specific hand/plate/channel posing without editing that
shared source. Prepare embedded 1K materials offline with the approved helper.
Retain required legal notices and the existing nearest, pixel presentation.

The selected walking source is prepared to embedded uncompressed 1K maps.
The skin and weapon poses reuse the shared centimetre-to-metre transform;
the held plate, cable and emitter use the actual solved forearm and wrist.
Both current human sources wear peaked caps, so the retired requirement that
an officer's cap rise above a Clerk helmet is replaced with equal supported
body height and a visible red cap band. Exact feet registration stays required.

`auditor_rig.gd` and `auditor_bake.gd` own this character alone. Preserve the
55-pose, eight-direction EnemyAnimation layout, fixed feet, armed/unarmed
combat, readable hit and supported death poses. The seated cell remains the
channel cell. Source and baked output hashes must agree in the receipt. No
protocol, collision body, repair budget, channel timing or gameplay rules change.

The bake now writes paired unlit albedo and view-normal atlases using the
existing normal shader. Root owns the two-line `enemy_view.gd` normal-texture
hook; a temporary exact copy is permitted only for the combined live proof.
Keep that shared hook out of this source commit.

The runtime lamp and beam sockets in `enemy_view.gd` and `auditor_channels.gd`
remain authoritative presentation registrations. Fit source hardware to those
registrations; request a small coordinated shared hook if an unavoidable change
is found. General character/reference README files and cast receipts remain
outside this lane.

## Acceptance and evidence

Inspect source skin, bone hierarchy and walk before selection. Add meaningful
source checks for gait, weapon grip and recoil, unarmed action, raised emitter
height, lowered channel pistol, frontal plate and cable attachment, and a
supported corpse. Preserve the existing atlas checks for fresh source receipt,
all unclipped poses, feet registration, visible cap/plate, channel-only emitter
and floor collapse. Checks tied to the old procedural colors must become
equivalent geometric or silhouette checks, not disappear.

Use a coordinated GPU slot for the complete bounded bake and inspect standing,
walking, attack, channel and corpse frames from multiple directions. Inspect
actual custody presentation at playing distance when a suitable owned route is
available. Record source-only and atlas evidence separately from live combat.
Keep the source a candidate until its own registered-pose and rendered gate
passes; full integration CI, main and release selection remain separate work.

## Checkpoint

The source harness passes skin, physical gait/root registration, grip/recoil,
recovery, melee, first hit, actual 1.35 m wrist, lowered channel pistol, held
plate, live lamp registration, cable coupling and supported corpse. The full
440-cell paired bake passes its source hashes, matching alpha/layout, nearest
imports, cap band, front-only plate, channel-only glow and emitter-height gate.
Front, profile and back idle/walk/fire/channel/corpse cells were inspected.

The ordinary development range is still in flight. An unchanged Standard
Flechette trial died during the first engagement. A subsequent ordinary
Scatter/held-cover trial passed the first Sweeper fight without a death and
recorded 38 actual channel ticks with the paired atlas bound, then died during
the original unattended 3.2-second watch. Explicit Assisted launch is rejected
because the range has no mission. These remain separate failed histories,
not a full range or campaign acceptance. The next source-role retry uses an
ordinary peek and shorter fixed capture timing while preserving combat gates.

Do not spend credits, modify shared documentation, change the server, or claim
the whole cast or room acoustics complete from this source increment.
