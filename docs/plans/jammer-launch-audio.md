# Jammer launch audio

Status: shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Integration belongs to
[campaign-and-feel-buildout.md](campaign-and-feel-buildout.md).

## Goal

Give each server-confirmed Jammer launch one distinct spatial cue. Pulse attacks
have no weapon ShotResult, so the normal gunshot path does not play a launch
sound. Reuse the Effects bus and existing spatial-audio conventions.

## Architecture and scope

Add a bounded four-voice spatial pool owned by GameManager. Consume the current
snapshot's `just_fired` fact only for Union Jammer identities, with a finite
position inside the coordinate bound. Deduplicate ticks and actor IDs, including
out-of-order snapshots. Play only within the listener's 24 metre radius, then
let the audio engine attenuate by distance. A spectator uses their actual camera
position. No callsign, inferred aim, phase progression or client collision can
produce a cue. A Jammer killed on its launch tick can still have confirmed fire.

MapInfo and disconnect stop all voices and clear deduplication. The pool and
deduplication state remain bounded. No new wire message, simulation effect,
combat trace or dependency. Existing weapon audio is unaffected.

Create a short original PCM cue with deterministic GDScript synthesis following
the existing M02 offline bake pattern. Store the source, WAV, import settings and
manifest together under `client/assets/audio/jammer/`. The receipt records source
and output hashes, sample format, duration, peak and RMS. This is an offline
developer bake, never synthesis or a service call at player runtime.

## Verification

Pinned Godot tests prove confirmed launches, silence for false fire and wrong
identity, duplicate and older snapshots, near/far and invalid coordinates,
bounded concurrent voices, reset, and GameManager integration. Verify source
freshness, PCM format, finite duration, nonzero samples and no clipping. Tests
require successful exit, clean logs and their PASS marker. Coordinating checks
include the full headless suite and live rendered/audio route.

## Research

[Godot's official AudioStreamPlayer3D reference](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html)
was checked 2026-09-30 for pool playback, Effects routing and distance
attenuation. Reuse APIs already present in the client and keep the pinned engine
unchanged. `max_distance` bounds audibility and each node's `max_polyphony` is one.

## Spend and non-goals

$0 external spend. No paid generation, weapon identity substitution, new attack
outcome, infinite voice allocation or claim of hardware listening acceptance.

## Evidence

The helper, GameManager hooks, original source/manifest/WAV and dedicated
`test_jammer_audio.gd` are implemented. The cue was baked with:

```powershell
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script res://assets/audio/jammer/bake_launch.gd
```

The bake passed, producing the original 0.48 second mono 24 kHz 16-bit cue. Its
receipt reports 11,520 samples and 23,084 bytes, with peak 0.5727 and RMS 0.0951.
These are decoded PCM levels, not perceived loudness or hardware measurements.
Godot initially imported the new WAV with its default compression. The asset
test caught that mismatch; the committed import now explicitly disables
compression, normalization, trimming and looping.

The pinned import and dedicated audio harness passed with exit 0, clean error
logs and the harness's PASS marker. Tests decode the actual imported PCM and
check amplitude, format, duration, source/output hashes and no clipping. They
exercise one confirmed launch, duplicates, old snapshots, wrong identity,
nonboolean fire, invalid or distant coordinates, a missing listener, an emitter
killed on its launch tick, repeated voice reuse, and the actual GameManager
MapInfo/disconnect reset handlers. The unchanged Crawler cue, local prediction,
remote presentation and Jammer animation harnesses also passed after integration.
Logs live under `.agents/buildout-20260930/test_jammer_audio.log` and the
`test_*-audio.log` files.

The full checker and eight-state rendered Jammer route passed. The isolated
software capture in `.agents/qa/jammer-buildout-polished/04_live_audio.wav` contains
one confirmed launch with radio muted and no player shots. Captured observation
counts increase from zero to one across that recording. Decoded output is
6.933 seconds, RMS 0.001763 and peak 0.035065, without clipping. These quieter
output levels include the actual Effects mix and spatial attenuation. They prove
live routing, not hardware listening acceptance. Final integration evidence
belongs to the parent buildout plan.
