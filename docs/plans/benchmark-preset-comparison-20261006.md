# Benchmark preset comparison

Status: in flight.

## Goal

The in-game Benchmark page offers the current graphics preset or a comparison
of Performance, Balanced and High. Every compared preset plays the same
captured ten-bot Arena Duel snapshots and the same time-based camera path.
Average FPS, one clearly defined 1% low and frame-time spikes help the player
choose a setting. No large-match or server-capacity claim follows from it.

## Implementation

Reuse `BenchmarkRun`, `BenchmarkCamera`, `FrameStats`, the owned `LocalHost`
process and the existing snapshot presenter. Capture one bounded 28-second
authoritative sequence, then stop that owned host and replay the same frames
for every preset. Exclude eight seconds of warm-up and measure twenty seconds
per preset. The temporary graphics draft is never saved; completion, Escape,
scene exit and failure restore the user's presentation settings.

Frame intervals use monotonic `Time.get_ticks_usec()`, checked against the
[current Time documentation](https://docs.godotengine.org/en/stable/classes/class_time.html)
on 2026-10-06. They measure whole rendered frame cadence, not GPU execution
time. Headless runs cannot produce hardware performance results. Metadata
includes renderer, adapter, output and world resolution, selected settings,
engine version, sample count and replay digest. No protocol changes.

The 1% low is `1000 / mean(slowest ceil(frame_count * 0.01) frame times in ms)`.
Percentiles use the existing inclusive linear interpolation. Save JSON and
CSV under the local benchmark result directory with average FPS, 1% low,
p50/p95/p99/max milliseconds and counts above 33 and 50 milliseconds.

## Verification and acceptance

Use deterministic quantile and hitch fixtures, replay identity checks,
quality restoration on completion/cancellation and real menu ingress tests.
Run an isolated actual renderer comparison and inspect the result screen and
saved artifacts. Scene trees used for automation set `fragr_automated` and
never capture the desktop pointer. A live match is captured once per run, so
cross-run recordings can differ; compared presets within one run cannot.

## Scope and spend

Local-only, $0. No dependencies, external service, new network channel or
simulation authority. A representative authored campaign/island showcase,
64-player server capacity and broad hardware evidence remain separate work.
