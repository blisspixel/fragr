# Auditor source and registered hardware

2026-10-04, bounded source checkpoint. No new generation calls or charges.
Main `a8611d04` plus the shared prepared-cast dependency `a48fd5b4` supplies
the existing skin, gait and pose seam. Full combined CI and release selection
remain separate gates.

The reviewed officer replaces the procedural body with a long black coat,
peaked red-band cap, angular face and compact back spool. The independent
held shield, glove emitter and cable use actual solved joints. The channel
wrist remains 1.35 m above the feet; shield sockets remain within 3.5 cm of
the live lamp registrations. Combat, damage, repair timing and map geometry
are unchanged. The prepared GLB retains the 24-joint skin and walking clip,
with embedded uncompressed 1K materials and nearest sampling.

![Front, profile and back pose cells](screens/auditor-source-20261004/poses.png)

Columns are idle, mid-stride walk, resolved-fire pose, repair channel and final
corpse. Rows are front, profile and back. This is an atlas inspection,
not a live combat recording.

| Gate | Evidence |
| --- | --- |
| Physical source | `test_auditor_source: PASS`, clean exit 0: skin, gait/root, grip/recoil/recovery, melee, first hit, raised wrist, lowered channel pistol, lamp sockets, cable outlet/coupling and corpse |
| Complete bake | `auditor_bake: PASS`, clean exit 0, all 55 poses in eight directions, 440 paired cells |
| Atlas | `test_auditor: PASS`, clean exit 0: source/PNG hashes, portable layout, all unclipped cells, matching normal alpha, shaped normals, exact feet, readable cap band, frontal plate and channel-only emitter at beam height |
| Moving-light diagnostic | `qa_auditor_lighting: PASS`, clean exit 0, 2,642 changed pixels with luminance difference above 0.035 when the point light moves |
| Actual world | Existing Standard custody range, normal human movement and discovered equipment, real first Sweeper defeat and repair snapshots with live normal atlas bound; full range clear remains open |

Both current human sources wear peaked caps. The obsolete comparison with a
shorter Clerk helmet becomes equal supported body height and at least eight
visible red-band pixels near the cap crown. Original feet, bounds, plate,
emitter and corpse assertions remain. The paired normal atlas uses the shared
normal shader. The two-line live normal-texture hook belongs to the parent
integration; it was copied temporarily for the combined world evidence and
is excluded from this source commit.

![Runtime pixel material at six metres under left and right light](screens/auditor-source-20261004/lighting.png)

This isolated diagnostic uses the runtime shader, matching paired atlases and
a six-metre camera. It establishes surface response and silhouette readability,
not room-wide lighting or performance on other hardware. Renderer: pinned
4.7.2, Windows OpenGL 3.3 Compatibility, integrated Radeon 780M. Albedo SHA256
`ae7ee3bf8fa1f1bf4a8d398dc74b23e36224cb86bb710436e12f8625cc96ef9a`;
normal SHA256
`930038f90e46b8e1236c783ad13d18a0334f6aab8ec73e8f553a3729f6e826ef`.

![Actual officer after an ordinary cover peek](screens/auditor-source-20261004/live-officer.png)

The playing-distance officer is a real server actor. The player is alive at
30 HP; this still is after the channel ends, so it proves the held shield,
cap/coat and live lamps rather than the raised-hand channel pose. The camera
peek uses ordinary walking, not actor repositioning. The native SHA256 is
`a54543c362f3c89e2e2d9636d22dd1d5cda2dc320646c0ba52d239939c6bcd3f`.

Private diagnostics stay under `.agents/auditor-source-diagnostics-20261004`.
The original Standard Flechette trial failed on participant death during its
first fight. A discovered Scatter/held-cover trial passed the first named
Sweeper kill with no death, recorded 38 real channel ticks, then failed during
the unattended original 3.2-second watch. Explicit Assisted was refused before
play because this range has no mission. The subsequent ordinary peek/short
watch retained 40 real channel ticks and reached the shown live frame, then
failed the unchanged remaining-guard clear on participant death. A malformed
diagnostic waypoint was rejected before play and corrected; that rejected
launch is not acceptance evidence. All failures remain retained. No full range,
M08 completion, settled runtime corpse or whole-cast acceptance is claimed.

The remaining source-role view uses a separately labelled diagnostic camera
in the same actual world, triggered by a real repair snapshot. It does not
replace the open original range clear. Focused import and owned script parse
checks are clean; the parent owns the fresh full client checker and integration
CI.
