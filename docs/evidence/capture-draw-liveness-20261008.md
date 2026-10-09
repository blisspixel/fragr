# Capture draw liveness

Status: **in flight**, 2026-10-08. Spend: $0. A bounded renderer test reproduces
the capture stall caused by minimizing the window: draw callbacks stop while
process frames and timers continue. Restoring the window completes the exact
inherited 30-frame timed strip. This proves a supported mechanism; the original
uninstrumented M08 attempt does not establish its actual window mode.
[The exact receipt](capture-draw-liveness-20261008.json) retains source identities,
timings, images, process receipts, failed controls and the incomplete mission.

The capture-only QaTour callback now reuses the non-presenting draw pattern
already used by retirement and local capture tools. It requests a draw only
after a quarter second without one, when the actual window cannot draw and the
engine is not headless. Normal controls request zero additional draws. Existing
timers, samples, combat deadlines and acceptance gates stay unchanged. The
[primary RenderingServer contract](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw)
and the installed 4.7.2 method metadata confirm the main-thread operation and
its buffer-swap argument. The call uses `false` without restoring the window.

The final test invokes the actual central callback rather than a duplicated
test pump. All five cases pass with 150 actual timed strip frames, nonblank
1280 by 720 originals and actual paused HUD measurement. Minimized cases remain
minimized throughout capture and measurement.

| Case | Strip frames | Forced strip draws | Forced HUD draws | Distinct animated samples |
| --- | --- | --- | --- | --- |
| Normal, unpaused | 30 | 0 | 0 | 30 |
| Normal, paused | 30 | 0 | 0 | 1 |
| Minimized, unpaused | 30 | 32 | 5 | 30 |
| Minimized, paused | 30 | 32 | 5 | 1 |
| Normal after restoration | 30 | 0 | 0 | 30 |

The paused scene deliberately remains static; its one sample value is expected.
The unpaused minimized scene changes in every retained sample, establishing
fresh image content. Actual HUD coverage is about 0.59%, with its real overlay
hidden and restored during measurement. A separate headless check invokes the
actual callback eight times past the undrawn threshold and requests zero draws.
Both final checks return numeric zero with clean logs and exact owned retirement.
The rendered control has an independent 45-second outer deadline.

Two rejected control attempts remain retained. The first tried `hide()` on the
main Window, which the engine refuses; its numeric zero does not pass the strict
log gate. Hidden launch is labelled separately from actual hiding. The first
pump probe set size before leaving inherited fullscreen and produced 1254 by 649
images; the original size gate rejects it. The corrected probe preserves that
gate and matches the real capture's windowed-then-size setup.

The incomplete M08 Rail attempt never reached the changed weapon selection.
Its partial mine-live image shows 100 HP and 50 armor, and the advancing native
record retains zero damage and deaths. Its verified owned renderer tree and
native child were intentionally retired, with no combat acceptance inferred.
Fresh ordinary mission routes and final whole-client composition remain pending.
This evidence establishes neither frame rates nor other-hardware behavior.
