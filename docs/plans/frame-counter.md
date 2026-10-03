# Frame counter

**Status:** shipped in [PR #330](https://github.com/blisspixel/fragr/pull/330), 2026-10-03, with inspected rendered evidence below.
**Spend:** $0.

## Goal

An optional frame counter in the top right corner, as Counter-Strike's
`cl_showfps` offered, available on the boot menu, in campaign and in
multiplayer. Nick asked for it on 2026-10-02 alongside a benchmark mode and
richer graphics settings, which are separate plans:
[graphics options and lighting](graphics-options-and-lighting.md) and the
[rendered showcase benchmark](showcase-benchmark.md).

## Behaviour

- **Display > SHOW FPS** offers OFF, FPS, and FPS + FRAME TIME. It is stored as
  `video/show_fps` (0, 1 or 2; anything else falls back to 0) and saved with the
  other settings.
- The tilde console accepts `cl_showfps 0|1|2` (alias `showfps`). It saves
  through the same settings store, and with no argument it reports the current
  mode. The one-shot `fps` command is unchanged.
- Mode 1 draws `144 FPS`. Mode 2 draws `144 FPS  6.9 MS  1% LOW 118`:
  - The average is frame count over elapsed time across the last 600 frames.
  - The 1% low is the rate across the slowest one percent of those frames by
    count (at least one frame). This is one of the three conventions the
    [showcase plan](showcase-benchmark.md) names; the counter labels it rather
    than mixing conventions.
- Intervals are wall-clock time between drawn frames, so time scale and pause
  cannot flatter them. A single interval is clamped at one second so a load or
  debugger stop stays readable. The text refreshes four times a second.

## Architecture

`client/scripts/performance_overlay.gd` (`PerformanceOverlay`) is a CanvasLayer
at layer 127, just under the console. The boot menu and the match manager each
mount one beside their console, give it the shared `FragrSettings`, and it
follows the store's `changed` signal. It reads only engine timing and never
touches the match, the wire or the server. In arena play the corner sits above
the combat feed's top edge; in campaign the feed is bottom left.

## Non-goals

- Network graphs. Ping, loss and snapshot age wait for the transport work.
- GPU and CPU frame split; that belongs to the rendered benchmark.
- Any upload or telemetry. The counter only draws.

## Verification

- `test_performance_overlay.gd`: the summary math (mean, reciprocal and 1% low on
  a known sample), the readout text per mode, dropped and clamped intervals, the
  bounded window, settings commits reaching a live counter, real frames drawing
  a rate, and console `cl_showfps` saving, ignoring invalid values and persisting.
- `test_settings.gd` covers the default and its validation;
  `test_settings_panel.gd` covers the Display option and persistence.
- `client/qa/frame-counter.json` renders modes 2, 1 and off over an arena match
  at 1920 by 1080, for inspection against the combat feed and HUD.

## Evidence

`client/qa/frame-counter.json` ran on 2026-10-03 on Windows with the OpenGL
renderer, 1920 by 1080, in an Arena Duel match with five bots: three states,
clean logs, HUD coverage at 2.9 and 3.1 percent. The stills were inspected:
- Mode 2 reads `244 FPS  4.1 MS  1% LOW 56` in the top right corner, above the
  combat feed's first line, with no overlap.
- Mode 1 reads `253 FPS` over a first-person view.
- Off draws nothing.

The low 1% figure at the start of a capture reflects scene warm-up rather than
steady play.
