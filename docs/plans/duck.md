# Duck

Status: **implemented** in source, 2026-10-06. Not merged. Hold Left Ctrl to
crouch. The server shortens the body and slows the walk. Right Ctrl still
fires beside the arrows. Gameplay version stays 37. An old server never
receives the key, because `Action` rejects unknown fields. The night process
does not duck. The named server and Godot checks passed. The full client
checker was not re-run.

## Goal

A held crouch, in the Counter-Strike sense: shorter, slower, and stuck short
while a ceiling will not allow standing. The server publishes the resolved
stance. Shots, contact, and the first-person eye use that height.

## Non-goals

No gameplay-version bump. No UDP and no higher tick. Campaign enemies,
Notaries, Crawlers, and bosses do not duck. Bots do not crouch on their own.
They do aim at the short chest, so a ducked torso is still a body shot. No
new art rig. The night binary stays the 07:39 build.

## Design

Standing height is 1.8 m and the eye is 1.6 m. The crouch is 1.35 m, three
quarters of that, with the eye at 1.15 m. Horizontal speed is 0.34 of the
speed the sim already chose, including compliance. Jump still works. Releasing
the key stands up at once unless the body does not fit.

`Welcome.duck` is true on this server and omitted by an older one. The client
sends `Action.duck` only after that flag, and only while the key is down.
`PlayerState.ducking` is the resolved stance, omitted while standing. A false
value is absent on the wire.

Left Ctrl is the default duck. Fire's keyboard binding is Right Ctrl, so a
left-hand crouch does not shoot. Mouse fire and the right trigger stay. The
pad slot is empty. Keyboard-only play still fires with the Ctrl beside the
arrows.

A worn participant body stores its floor height as the scale rest. Crouch
and far-camera scale restore that rest. The scene default belongs to the
legacy strip, and writing it back lifts the worn feet off the floor.

## Verification

`cargo test -p fragr-server --locked duck_shortens` and the movement beam
test. Godot 4.7.2: `test_keyboard_only.gd`, `test_rebinding.gd`,
`test_local_prediction.gd`, `test_spectator_camera.gd`. Spend is $0.
