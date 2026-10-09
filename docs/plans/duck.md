# Crouch

Status: core **shipped** in `e4df1a0b` (v0.79.0); control presentation
**implemented locally**, 2026-10-08. Hold Left Ctrl to crouch. The server shortens the
body and slows the walk. Right Ctrl still fires beside the arrows. The
October 8 request calls for a clear Counter-Strike-style crouch. The existing
mechanic already supplies the shorter body, lowered eye and ceiling clearance;
its held control is now explicit in settings, loading instructions and play hints.
This presentation update does not change combat or bindings.

## Goal

A held crouch, in the Counter-Strike sense: shorter, slower, and stuck short
while a ceiling will not allow standing. The server publishes the resolved
stance. Shots, contact, and the first-person eye use that height.

## Non-goals

No gameplay-version bump, transport change or tick change. Campaign enemies,
Notaries, Crawlers, and bosses do not crouch. Bots do not crouch on their own.
They aim at the short chest, so a crouched torso is still a body shot. Reuse
the current live character poses, camera and prediction seams. Do not replace
existing saved bindings or invent a second stance action.

## Design

Standing height is 1.8 m and the eye is 1.6 m. The crouch is 1.35 m, three
quarters of that, with the eye at 1.15 m. Horizontal speed is 0.34 of the
speed the sim already chose, including compliance. Jump still works. Releasing
the key stands up at once unless the body does not fit.

`Welcome.duck` is true on this server and omitted by an older one. The client
sends `Action.duck` only after that flag, and only while the key is down.
`PlayerState.ducking` is the resolved stance, omitted while standing. A false
value is absent on the wire.

Left Ctrl is the default crouch. Fire's keyboard binding is Right Ctrl, so a
left-hand crouch does not shoot. Mouse fire and the right trigger stay. The
pad slot is empty. Keyboard-only play still fires with the Ctrl beside the
arrows. The action is called `duck` internally and remains remappable through
the existing three-slot settings. Present it as `CROUCH (HOLD)` to players.
Use the actual rebound key in the existing loading and HUD prompt templates.

A worn participant body stores its floor height as the scale rest. Crouch
and far-camera scale restore that rest. The scene default belongs to the
legacy strip, and writing it back lifts the worn feet off the floor.

## Verification

The October 8 composed server library run passes all four existing crouch
cases: shortened hit volume, lowered chest aim, reduced speed and published
stance, absent-field compatibility, and ordinary movement beneath a low slab
that refuses standing. That run has a separate admission-fixture failure;
it is not a full workspace pass. The admission fixture has its own passing
focused recheck.

Fresh keyboard-only, rebinding, local prediction, spectator camera, live-body
and loading harnesses pass after the copy changes. Actual loading and settings
components were captured and inspected at 960x720 and 1280x720.

A four-state ordinary socket check holds physical Left Ctrl while walking,
then releases it. The observed eye changes from 1.60 m to 1.15 m, measured
movement changes from 5.000 m/s to 1.700 m/s across server ticks, and release
restores standing. No fire action is held. It injects no stance, inventory or
outcome facts. The first diagnostic's incorrect camera-controller cast remains
retained as a failure; the corrected check exits cleanly with both owned
processes retired. The [presentation receipt](../evidence/presentation-corrections-20261008.md)
binds those observations, source hashes and inspected originals. Final
whole-client and workspace gates remain part of the shared composition.
Spend is $0.
