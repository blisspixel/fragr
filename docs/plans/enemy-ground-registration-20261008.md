# Grounded enemy foot registration

Status: **in flight**, 2026-10-08. Spend: $0. This plan precedes the fix for
standing enemies appearing above their actual floor.

## Observed cause and intended behavior

`EnemyView.update` selects the atlas and sets the sprite's physical origin.
Standing atlases use a centre 0.9 m above authoritative feet, or -0.6 m
relative to the server pawn. `PlayerPawn` retains the scene's earlier -0.15 m
rest position. Its per-frame scale refresh restores that stale value and lifts
the visible body by 0.45 m. Hit feedback uses the same refresh. A Notary's
distinct registration is also subject to this overwrite.

Retain the rest position selected by the actual enemy presenter before any
scale, damage, broadcast or crouch refresh. Keep the existing atlas source,
physical dimensions and fixed-foot convention. Do not lower authoritative
positions, collision, gun aim, platforms or navigation to conceal a rendering
error. Live meshes, hovering drones and committed leaps retain their own
server-owned positions and presentation contracts.

## Verification

First reproduce the offset through an instantiated real pawn and ordinary
process frames. Cover all atlas enemy roles, both ground and elevated support,
phase changes, hit feedback, repeated snapshots and broadcast scaling. Inspect
actual alpha bounds against the correctly registered floor for standing and
settled corpse frames. Include a deliberately stale rest-position negative
control so a test cannot pass from comparing two copies of a constant.

After the fix, run the focused pawn, enemy, Notary, Assessor, player-body and
character presentation harnesses, then the complete client checks at shared
source freeze. Retain a controlled before/after player-height renderer fixture
with floor and 1.8 m reference, plus ordinary mission captures. Record source
hashes and distinguish pre-fix Edda M09 captures from subsequent routes.

The initial fix owns `player_pawn.gd`, a focused regression harness and its
rendered fixture. Other lanes own Arc weapon art, Edda runtime selection and
M12 mission logic. Coordinate source changes and renderer/import windows;
preserve earlier evidence and unrelated working-tree changes. No server,
wire, save, gameplay, paid asset, dependency, commit or deployment change is
required by this defect.

## Source-pose correction, planned before the rebake

The real-pawn check reproduces the stale-origin failure and passes every origin
refresh after the cache fix. Its stricter alpha-bound checks separately found
settled Heavy, Jammer and Crawler pixels 0.11-0.24 m below support. Keep those
failed logs. Correct their offline geometry instead of relaxing the floor gate
or adding per-frame pixel scans and hidden runtime offsets.

The Heavy's dropped cannon and collapsed upper body, and the Jammer's collapsed emitter, need actual mesh
support on the source floor while their anchored legs retain their existing
positions. A small offline pose-support helper measures transformed source
vertices and lifts only a penetrating attachment. The Crawler's excessive
death pitch drives its front cutter below support; reduce that final death
tilt while preserving its low chassis and anchored feet. Living poses and all
server movement remain unchanged. Bind the helper in the affected bake receipts.
Use the existing partial Heavy bake to retain Clerk, Sweeper and Turret bytes,
and rebake the two independent low-machine atlases. Verify floor bounds and
existing source/animation gates before the controlled and ordinary render checks.

## Rendered attachment correction, planned before the change

The first controlled before/after run completes eighteen states per mode with
real pawn frames. Its corrected Auditor corpse reveals a separate standing-height
repair lamp still visible above the collapsed plate. Hide those optional lamps
when the authoritative phase is dead, and throughout a repaired body's rising
recovery pose. Ordinary living recovery and channel lamps must remain visible.
Restore them after the rise ends. Extend the real-pawn regression through death,
repaired recovery and standing, then recapture the affected controlled states.
No server repair budget, enemy life or phase deadline changes. Wait for the
current ordinary M10 renderer to retire before editing its loaded presenter.

## Focused correction checkpoint

The stale-origin cache fix, three supported source-pose rebakes and Auditor
lamp retirement are implemented. The [presentation receipt](../evidence/presentation-corrections-20261008.md)
binds the exact source, retained prior atlases, controlled captures and checks.
Fourteen focused client harnesses pass, followed by fresh grounding, Auditor
and Auditor-source rechecks. The source support gate covers 63 death progress
samples and a transformed nested-mesh negative control.

Each controlled mode contains 18 real-pawn states and 60 measured samples.
Corrected opaque bottoms range from about -0.019 m to +0.038 m relative to
support; the explicitly stale control ranges from +0.206 m to +0.487 m.
All five unrelated retained atlas/normal files remain byte-identical. These
controlled views establish the registration correction, while ordinary
canonical mission review remains in flight alongside stair installation and
strict save compatibility. Whole-client and release composition remain separate.
