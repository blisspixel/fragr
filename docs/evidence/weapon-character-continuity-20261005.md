# Weapon and character continuity audit

Status: in flight, 2026-10-05. This read-only audit uses the proposed Pistol
selection snapshot `8879b5ee`, not a claim that its artwork has shipped.
Other selected pictures are retained unchanged. No runtime art, source, scale,
hand rig, story image or provider request changes in this lane.

## Method

Inspect the seven selected idle pictures, actual HUD canvas and control
transforms, including the separate Fists presenter and Shiv rest scale. Build
a CPU contact sheet from the unchanged pictures at a common native scale and
at the actual HUD layout scale. Mark visible palm and wrist spans manually,
separating pose and perspective differences from obvious disproportion or
material mismatch. These are editorial measurements, not a new automatic
personhood or anatomy threshold.

Inventory every selected story image through the scene manifests and distinguish
existing images, missing-file text fallback and unselected character references.
Compare named characters only against their current canonical identity and
source. The opening workshop image is owned by a separate correction lane;
this audit does not edit it. Actual gameplay and GPU HUD captures remain separate
evidence from a CPU picture/layout study.
