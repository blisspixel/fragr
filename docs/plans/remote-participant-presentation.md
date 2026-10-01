# Remote participant presentation

Status: implemented, 2026-09-30. Integration belongs to
[campaign-and-feel-buildout.md](campaign-and-feel-buildout.md).

## Goal

Render remote participant movement at one coherent buffered server time instead
of continuously chasing the newest position with an exponential lerp. Spectator
eyes use the rendered position, yaw and pitch together. Chase cameras behave the
same at different frame rates.

## Design and architecture

Keep a bounded history of validated participant positions and facing at the
existing 20 Hz server cadence. Estimate the tick clock from the earliest arrival
offset in a bounded observation window and render 100 ms behind that clock.
Never move the presentation cursor backwards. Interpolate position and pitch
linearly and yaw along its shortest arc. Hold at the newest known position when
the buffer runs dry. Do not extrapolate beyond authoritative positions.

Snap the first state, death, respawn, a large position discontinuity and recovery
from an eight-tick gap. Ignore duplicate and older ticks. MapInfo clears history,
including gate transitions that retain the same pawns. Disconnect already frees
the pawns. Local prediction takes precedence and its camera continues using the
existing direct predicted position or authoritative fallback.

Campaign enemies and Latch keep their existing movement and animation clocks.
Their server phase and resolved-shot timing must be integrated together before
adding them to this buffer. Health, weapon, score, flags and shot feedback remain
latest authoritative facts. This increment aligns participant transform only;
it does not delay combat events or implement server lag compensation.

The selected buffer is a bounded starting value, comparable to the existing
movement smoother's delay, not a proven latency target. Linear interpolation can
cut a corner between sparse positions. A collision-aware path, authoritative
velocity and a measured adaptive buffer belong to a later increment.

## Research

Primary references checked 2026-09-30:

- [Snapshot interpolation](https://gafferongames.com/post/snapshot_interpolation/)
  explains buffering, linear transforms, velocity-aware Hermite interpolation
  and extrapolation failures around collision. This increment uses linear
  interpolation and holds when stale.
- [Godot GlobalScope](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html)
  documents `lerp_angle` and the math used by the current Godot client.

## Scope and protocol

Own `remote_presentation.gd`, `player_pawn.gd`, `spectator_cam.gd` and their
focused harnesses. Integration adds one GameManager MapInfo reset hook. No wire,
server simulation, movement mirror, dependency or engine version changes.

## Verification and acceptance

Deterministic Godot tests cover cadence, burst arrivals, missing snapshots,
stale hold, bounded memory, duplicate/older ticks, shortest-arc facing,
death/respawn/teleport and local prediction precedence. Exercise the live pawn
and spectator paths, not only helper arithmetic. Compare chase camera transforms
after equal wall time at multiple frame rates. Require each harness PASS marker,
successful exit and clean error logs with pinned Godot 4.7.2.

The coordinating lane runs the full headless checker and regenerates and
inspects the rendered tour. No human feedback prerequisite for this round.
Human feel, two-machine network behavior and 1.0 controls acceptance remain
unproven until those separate measurements exist.

## Spend

Local work only, $0 external spend. No asset or provider calls.

## Evidence

Implemented the bounded helper, participant transform path, same-time spectator
eyes and exponential chase/frag camera smoothing. The GameManager MapInfo reset
hook is integrated by the coordinating lane. The existing checker automatically
discovers `test_remote_presentation.gd` by its filename and PASS marker.

Focused checks on 2026-09-30 used the pinned Windows Godot 4.7.2 console binary:

```powershell
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script res://scripts/test_remote_presentation.gd
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script res://scripts/test_spectator_camera.gd
```

Both harnesses passed with exit 0, their own PASS markers and no script or engine
errors. The unchanged local prediction, player body, far-camera scale, enemy
animation, campaign recovery and shot-effects harnesses also passed. Recovery
launched a real local server and completed three input-driven retries and
exhaustion. Logs are under `.agents/buildout-20260930/test_*.log`.

The timeline harness checks constant movement at 30, 60 and 144 rendered frames
per second, arrival bursts, angle wrap, pitch alignment, starvation, bounded
history, bad transforms, duplicate/older ticks and lifecycle discontinuities.
The live pawn test verifies prediction precedence and buffered aim; spectator
tests verify buffered observed facing versus authoritative join facing and chase
translation, static-origin orientation and frag-chase translation after equal
elapsed time at those three frame rates. These are deterministic behavior
checks, not measured hardware frame rate or input latency.

The coordinating lane's final pinned checker passed all 64 harnesses after the
camera correction below. The regenerated standard tour passed 32 states and
published thirteen selected stills locally. Independent inspection of spectator
eyes, chase, participant bodies and join/leave frames found no concrete clipping,
pose or HUD regression. Receipts are `.agents/qa/buildout-publish-final/` and
`.agents/buildout-20260930/godot-final.log`. This is local Windows evidence;
two-machine and unsteered human controls acceptance remain open.

## Rendered review correction: near-camera shot effects

The 2026-09-30 Jammer range mixed-fight capture
`.agents/qa/jammer-buildout-final/jammer_mixed_fight_jammer_hit.png` exposed large
flat impact polygons around the first-person camera. Resolved incoming hits can
end close to the predicted eye position. The shot mesh previously allowed
impact quads and beam strips to cross the camera's near plane.

Clip only cosmetic shot geometry against a plane 0.6 metres in front of the
actual active viewport camera, respecting a larger configured camera near
distance. Recompute the plane on every mesh rebuild so prediction, camera
movement and spectator changes do not use an authoritative pawn as a listener
proxy. Keep the distant part of crossing beams and sparks. Retain resolved-shot
evidence, event counts, expiry, HUD feedback and depth-tested world occlusion.
No simulation, wire or GameManager change. This correction owns only
`shot_effects.gd` and `test_shot_effects.gd` in addition to this plan.

Focused regression checks will inspect emitted mesh vertices for an incoming
hit at the listener, an eye moving into a still-live impact, camera rotation and
close melee or beam geometry. Distant impacts must still render, no-camera
harnesses retain their geometry, and fully clipped effects must not create an
empty ImmediateMesh surface. Success requires clean pinned Godot harnesses and
the coordinating lane's regenerated mixed-fight inspection. Local spend is $0.
Official [Camera3D documentation](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
and [ImmediateMesh documentation](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html)
were checked for camera transforms and mesh construction on 2026-09-30.

The correction is implemented. Pinned Godot 4.7.2 focused checks passed with
exit 0, individual PASS markers and clean error logs:
`test_shot_effects.gd`, `test_spectator_camera.gd` and
`test_local_prediction.gd`. The shot harness inspects actual emitted mesh
vertices rather than only the clipping arithmetic. It also verifies invisible
effects keep their expiry clock and no empty surface is submitted. Logs:
`.agents/buildout-20260930/test_shot_effects-camera.log`,
`test_spectator_camera-clip.log` and `test_local_prediction-clip.log`.
`git diff --check` passed. The final full checker and eight-state range tour
passed after this correction. Independent review of
`.agents/qa/jammer-buildout-polished/` found the previous large polygons absent,
normal world beams retained and readable targets/HUD. The new still is a
different combat instant; the emitted-mesh incoming-hit regression directly
proves listener clipping. The closer lateral strip now visibly shows pulse
travel. The parent buildout plan records the final retained screenshots.
