# Radio scene retirement

**Status:** proven, 2026-09-23 ([#231](https://github.com/blisspixel/fragr/pull/231), v0.45.0).
This repairs the Linux Godot check on the
main run for the local campaign save. The saved-run restart harness passed its
gameplay assertions but Godot reported an MP3 playback and stream still in use
at process exit after repeated gameplay-to-menu transitions.

## Goal

Release the active radio playback and stream when its scene leaves the tree,
including rapid campaign restarts. Keep the radio audible and its track
selection unchanged while the scene is active.

## Scope

The presentation-only radio owns its decoder teardown in `_exit_tree`. A
headless Godot check starts a real MP3, removes the radio from the scene, and
checks that playback stopped and the stream reference was cleared. The
saved-run restart harness tracks playbacks before each gameplay-to-menu scene
change and waits for their mixer references to retire before quitting. No
server, wire, save-file, or audio asset contract changes. No paid service is
used.

## Verification and success

- Run the radio harness and the full Godot checker with the pinned Godot binary.
- Require the saved-run restart harness to pass without an exit-time resource
  error on Linux CI. Windows and macOS client checks must stay green.
- Inspect the diff for scene lifecycle and unrelated changes before merging.

The issue is complete when the main branch CI is green and no decoder leak is
reported by the repeated restart harness.

## Local evidence

Godot 4.7.2-stable imported the project. The focused radio harness started and
retired three MP3 playbacks without exit errors. The saved-run restart harness
passed without exit errors after tracking each outgoing scene's playback. The
full `tools/godot_check.sh` run passed, including all script checks and
harnesses. Radio teardown alone had reproduced the leak in the full checker;
the transition tracking and retirement wait closed that failure.

[CI run 35862073777](https://github.com/blisspixel/fragr/actions/runs/35862073777)
passed audit, Rust tests and checks, and Linux, Windows and macOS Godot jobs.
