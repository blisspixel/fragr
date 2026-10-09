# Client exit retirement, October 8

Status: **implemented** locally, integration and target-platform verification
remain separate. Tracks [#186](https://github.com/blisspixel/fragr/issues/186)
and the [bounded plan](../plans/client-exit-retention-20261008.md).

## Reproduced causes

Two distinct ownership defects reproduce on Windows with Godot 4.7.2-stable.

1. Play a WAV, stop and free its player, then quit on the same turn. Three
   minimal headless runs retain `AudioStreamPlaybackWAV` and `AudioStreamWAV`,
   reporting two ObjectDB instances and one resource. Pressing the actual boot
   menu's Quit button with active audio reproduces the same named owners in two
   runs. The stopped player no longer owns the decoder, but the mixer does.
2. Create and replace skies, then leave the real main scene before its first
   completed draw. Its environment retirement array dies with the scene, before
   the pending sky queue is consumed. The Compatibility renderer reports four
   349,524-byte textures for two prematurely released skies. Drawing first is
   clean. A same-map layout rebuild also removes its new WorldEnvironment
   before the first draw while GameManager remains alive. That narrower probe
   reports exactly two 349,524-byte textures. Keeping replacements only inside
   GameManager cannot cover either removal path.

Released `e4df1a0b` boot-menu and GameManager source also reproduce the respective
failures in normal and verbose runs. These comparisons replay those exact owner
scripts against the current imported assets and pinned engine, not an untouched
release package. Both defects predate this round. The layout-rebuild comparison
reproduces the earlier M14 allocation signature, but its original log does not
identify the removed owner. The original untyped September counts and that
specific earlier M14 event remain individually unattributed; matching counts or
allocation sizes alone cannot identify their owners.

Pinned primary source supports the observed ordering:

- [AudioServer](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_server.cpp)
  marks a stopped decoder for fade-out deletion. The mixer removes it and queues
  the final playback release for main-thread cleanup.
- [Compatibility sky storage](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)
  allocates radiance and raw-radiance textures while consuming dirty skies.
  Freeing a still-pending sky violates that ordering.
- [Main-loop draw selection](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp)
  skips ordinary drawing without a drawable window. The documented
  [force_draw](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw)
  call draws without presenting when passed `false`.

## Ownership correction

`ClientRetirement` belongs to the scene tree and survives menu transitions. It
observes removed audio players before their parents clear streams, retains weak
decoder references, and holds retiring environments through a completed draw
and the following resource-free draw. GameManager transfers pending replacements
before its own retirement array is cleared.

Menu, pause-menu, console and native window-close requests use the same exit
path. It releases the pointer, frees scene-tree children through their existing
owners, observes decoder and rendering release, then quits. LocalMatch and
LocalHost still stop only their owned native processes. Capture retirement and
the native campaign harness also await the shared owner before their direct
SceneTree exit.

An actual minimized-window regression first failed with three pending
environments at draw 8 of 10. Retirement now requests a non-presenting draw only
when an outstanding epoch cannot receive normal drawing, and waits for that
epoch's completion before requesting another. Headless runs never request a
rendering frame. A two-second bound reports retained owners and exits with
failure; it does not hide errors or substitute a guessed delay.

## Verification

The focused harness exercises all three audio-player types, real rapid main
scene replacement, ordinary quit controls and real owned native children.

- Twenty repeated headless exits cover menu, pause, console, window and owned
  child cases, normal and verbose, twice each. All exit 0 with clean logs.
- Current focused normal and verbose checks pass for client retirement, local
  campaign, frontend, capture audio retirement and M06 presentation. All ten
  logs are clean, including the added shared campaign drain.
- Twenty-four rendered exits cover OpenGL Compatibility and Vulkan Forward+,
  menu, two owned native children and actual minimized-window close, normal
  and verbose, twice each. All assertions pass and exit 0 without retention or
  error diagnostics. All twelve OpenGL logs and six normal Vulkan logs are
  fully clean. Each of the six verbose Vulkan logs retains a startup layer
  manifest registry warning and an RGB8-to-RGBA8 hardware conversion warning;
  those logs are not represented as warning-free.
- A deliberately retained decoder reports its owner and exits 1 after 2,002 ms.
  This negative receipt is an expected rejection, never a clean pass.
- The layout-rebuild probe fails on released GameManager source with exactly
  two texture leaks in both normal and verbose OpenGL runs. Both corresponding
  current-source runs exit 0 with clean logs, after the same ordinary layout
  replacement and observed draws. No source changed for this comparison.

The [machine-readable receipt](client-exit-retention-20261008.json) binds source,
baseline scripts and individual matrix log hashes. Full logs, original failures,
imported-source comparisons and pinned engine copies remain under
`.agents/open-issues-20261008/186/`. The headless matrix overlapped other native
checks and mission rendering, providing a loaded scheduling case without
establishing a connection to the historical intermittent reports.

After these checks, the standard tour exposed a separate aim-request race when
a live opponent killed the participant. Its QA helper now waits for a living
snapshot and resends ordinary camera aim across respawn, retaining the five-second
deadline and exact pitch assertions. The original matrix's `qa_tour.gd` hash
`f3a4e499892ac7150a2a414392362f941a8594b656855c5835cc8baaddb4c76a`
remains recorded. The later helper hash is
`b6fdcf1fb7a45e232a0492fc303c997e0b6ac388da8879733052d45578187c80`.
All nine other recorded source files still match. This separate QA change does
not alter retirement or retroactively change the twenty-four rendered runs;
the standard-tour retry is separate verification. That retry completed the
same thirty-two states with seed 42, exit 0 and no error or warning diagnostics.
Original states 17-32 and all three effect strips were inspected again at full
size. Menus and overlays fit, and the fresh incomplete service record correctly
shows zero deaths and zero HP lost. Strip samples show transient effects and
cycling, but their resolution cannot establish seven separate pellet impacts.

## Limits

Windows AMD Radeon 780M evidence does not prove Linux or macOS rendering,
uninspected hardware, forced process termination or every possible retained
owner. The historical macOS report needs its platform's normal CI coverage;
its old log does not identify the retained type. No diagnostic filter, clean-log
threshold, protocol, simulation, paid generation or engine pin changed. $0.
