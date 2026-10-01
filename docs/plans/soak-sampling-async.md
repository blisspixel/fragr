# Nonblocking soak memory sampling

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. **Spend:** $0.

## Problem and change

The final full workspace run exposed the short in-process soak collecting three
samples instead of the required four. Its server advanced only four ticks in
3.856 seconds despite individual tick times staying below four milliseconds.
The Windows memory probe invokes synchronous `tasklist` inside the async sampler.
On the single-thread test runtime, a slow operating-system subprocess prevents
the same runtime's server and clients from advancing. Concurrent build load made
this defect observable; the isolated 120-second release-process soak passed.

Move the existing OS probe onto the existing runtime's blocking worker pool.
Keep the same parsers, source labels, unavailable-memory reporting, sample
schedule, measurement thresholds and assertions. Do not add dependencies,
alter sim behavior or substitute invented memory values. Join failures stay
observable as unavailable-memory reasons.

## Verification

A deterministic dependency test releases a blocked OS-style probe through an
async task on the same single-thread runtime. The probe must yield so the task
can release it; a synchronous probe cannot satisfy that condition. Retain the
actual short in-process soak and its original sample/tick/traffic assertions.
Run focused tests, full workspace tests and unfiltered coverage, then rebuild
the affected release harness and repeat the real 120-second soak. Record the
initial failure and final results without turning a loaded failure into a pass.

## Final evidence and limits

Focused soak tests passed, followed by 1167 workspace tests and 94.47 percent
unfiltered line coverage. The coverage run includes the new deterministic
single-thread regression and the unchanged real short-soak assertions. Full
workspace formatting, Clippy with warnings denied and release build also passed.
Logs are `soak-async-focused.log`, `tests-verified.log`, `coverage-verified.log`,
`fmt-verified.log`, `clippy-verified.log` and `release-verified.log` under
`.agents/m04-buildout-20260930/`.

The rebuilt external release-process soak passed its unchanged assertions:
`.agents/soak/m04-verified.ndjson`, summarized in the parent prototype's measurement
table. Independent review found no new defect. A slow OS probe is still awaited
before that sampler's next iteration and can reduce its sample count. The fix
preserves runtime progress; it does not promise an OS-independent sampling cadence.
