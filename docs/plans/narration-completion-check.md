# Narration completion check

**Status:** shipped, [PR #315](https://github.com/blisspixel/fragr/pull/315),
2026-09-30. Its protected head and resulting main `74520b4` pass CI across all
three platforms. Main's [run](https://github.com/blisspixel/fragr/actions/runs/36830668467)
records the integration verdict; the final Linux line coverage is 94.23 percent.
**Spend:** $0.

## Goal and scope

Diagnose and fix the macOS narration-completion failure in the final campaign
status follow-up. The actual `m04_arrival` final-caption assertion failed. Its
aggregate diagnostic does not establish which predicate or deadline failed.
The previously released game and its
three-platform checks passed; that does not explain this later failure.

Preserve the real decoded audio, Voice bus, caption preference, final-page
reader hold, explicit completion and missing-asset fallback assertions. Do not
weaken error detection, replace real completion with a direct callback, or widen
the deadline without evidence. No new assets, paid calls or protocol changes.

## Architecture and verification

Use the existing `ScenePlayer` narration signal and `test_campaign_audio.gd`
seams. Distinguish audio-backend state from main-thread signal delivery. Inspect
the pinned engine implementation before choosing the readiness condition.

Run the focused actual-audio harness with a clean exit, clean error log and PASS
marker, then the existing full client checker. The final protected PR head must
pass Linux, Windows and macOS CI. A runtime change also requires rendered evidence
and a new player-visible release; a harness-only synchronization fix does not.

## Failure evidence and completion criteria

[CI run 36824736387](https://github.com/blisspixel/fragr/actions/runs/36824736387)
failed macOS `test_campaign_audio.gd:143` on the final-caption assertion. The
receipt is `.agents/m05-buildout-20260930/ci-b73dd62-macos-110247812734.log`.

Finish when the cause is established, the bounded check observes actual
completion reliably, all original behavior assertions remain, and the final
head passes the required platform checks. Record the fix and results here.

## Established cause and fix

The pinned engine's
[audio player implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/audio/audio_stream_player_internal.cpp)
reads backend playback activity in `is_playing` (lines 265-271), while its
internal main-thread process later removes inactive playback and emits `finished`
(lines 61-79). An inactive backend therefore does not establish signal delivery.

The original macOS log cannot retrospectively prove the individual failed
predicate. The engine ordering and controlled real-clip probe below establish
the invalid synchronization assumption; final platform CI must validate the fix.

An ignored probe used the real committed clip with only the audio node's internal
processing temporarily disabled. The mixer finished with zero signals, voiced
state still true and captions hidden. Re-enabling that processing delivered one
real signal and exposed captions. The clean exit-0 receipt is
`.agents/narration-completion-20260930/reproduce-clean.log`.

The harness now counts the actual `finished` signal before seeking near the
clip's end and waits for it within the original two-second deadline. It asserts
exactly one signal and retains the original stopped playback, visible caption,
reader hold, deliberate skip and missing-asset fallback checks. Failure messages
identify the scene and observed state. `ScenePlayer` and every shipped asset are
unchanged; this is a test synchronization fix, not a new player-visible release.

The first focused run and ten repeated actual-clip runs passed with clean logs
and exit 0 in `.agents/narration-completion-20260930/focused-first.log` and
`focused-repeat-1.log` through `focused-repeat-10.log`. Independent review
confirmed signal ordering, observer lifetime and all retained assertions.

## Local server prerequisite

The first full checker also rejected the local M04/M05 historical preview
fixtures. Both native harnesses passed on Windows and macOS CI at the same
source head. The local release server still embedded the pre-checkout authored
map bytes, while checkout had normalized the files to the repository's LF rule.
Raw content digests therefore differed even though the authored definitions were
unchanged. These strict content checks correctly rejected mismatched bytes.

Rebuilding the required local server with
`cargo build -p fragr-server --release --locked` passed in
`.agents/narration-completion-20260930/release-prerequisite.log`. Both focused
native harnesses then passed with clean exit-0 logs
`focused-m04-after-build.log` and `focused-m05-after-build.log`. No map, migration,
preview, runtime or fixture change was needed.

The final full checker with that matching binary passed all 174 scripts and 81
harnesses with exit 0 and no severity error lines in
`.agents/narration-completion-20260930/godot-full-after-prerequisite.log`.
Owned native and client processes closed. Final Linux, Windows and macOS CI gates
belong to the linked integration PR; its result determines shipping.
