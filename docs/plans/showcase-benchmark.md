# Plan: a benchmark that pushes the machine and shows off the game

**Status:** rung 1 in flight (2026-09-19); rendered showcase remains planned.
**Branch:** `feat/showcase-bench-*` (one PR per rung)
**Spend:** $0. Local only, no service, no telemetry.

## What exists, stated plainly

The benchmark that ships today is a headless, server-side simulation timer. It builds a session, seeds it, runs rule bots for a set number of ticks, and records two things per tick: how long the tick took and how many bytes the broadcast would have been. It never opens a window, never loads a scene, never presents a frame.

The current check compares only final scores, omits serialization from the timed
step, and silently treats serialization failures as zero bytes. Its histogram
documentation also understates the percentile error. Those defects must be fixed
before its numbers become a basis for further work.

## Current increment: trustworthy recording

Branch: `feat/benchmark-trace`. Keep the existing server and client seams. Export
versioned NDJSON containing a header, every tick's typed broadcasts and unicasts,
final scores, and a completion record. Stream it without retaining the whole match.
Use SHA-256 over the exact header/tick/score bytes, excluding timings and completion.
Seeded benchmark entity identifiers must also repeat, including spawned drones;
normal sessions retain random UUIDs. Compare complete recordings, including
intermediate movement and effects, rather than only scores. This proves observable
trace repeatability on the tested build, not equality of every hidden sim field.

Report session and serialization distributions separately, total measured CPU
step time, both payload classes, sample counts, and the scope excluded from timing.
Record OS, architecture, build profile, and available parallelism. Do not infer
network capacity, GPU performance, or cross-architecture bit identity. Invalid
thresholds, zero-length runs, write failures, and serialization errors fail loudly.
Existing trace files must not be overwritten. No runtime wire change is needed.

Verification: exact histogram edge cases, budget boundaries, trace round-trip and
content mutation, a repeated run that reaches drone/round events, writer failures,
CLI validation, all repository checks, and a measured 16/64/128-fighter table.
No paid services or telemetry. The new dependency is the stable RustCrypto `sha2`
crate rather than a local hash implementation; its MIT/Apache licensing, portable
backend, and stable 0.11 API were checked on 2026-09-19 against the
[crate documentation](https://docs.rs/sha2/0.11.0/sha2/) and
[release history](https://github.com/RustCrypto/hashes/blob/master/sha2/CHANGELOG.md).
Timing uses monotonic [`Instant`](https://doc.rust-lang.org/std/time/struct.Instant.html).

Acceptance for this increment:

- [x] Same-seed runs have identical complete trace hashes; changed movement is detected.
- [x] A trace can be parsed through the shared wire types and proves completion.
- [x] CPU phase and payload accounting are explicit and independently tested.
- [x] Invalid input and failed output cannot produce a passing benchmark.
- [ ] Platform CI and the local scale measurements pass.

## Recording increment evidence (2026-09-19)

Local Windows 11, Ryzen 7 7840U, Rust 1.98.1 release profile. Each row is 12,000
measured ticks plus a complete repeat, seed 42. Measurements were run serially;
no GPU workload ran beside them. No disk trace was written during these runs.
Source: `feat/benchmark-trace` on parent `da09dbb`; integration history identifies
the reviewed implementation. Local JSON receipts are in `.agents/bench/`.

| Fighters | Map | Session p99 ms | Encode p99 ms | Total p99 ms | Maximum ms | At/over 50 ms | Trace repeats |
|---|---|---:|---:|---:|---:|---:|---|
| 16 | Arena Duel | 0.019455 | 0.014335 | 0.030719 | 0.1923 | 0 | yes |
| 64 | Directive 17 | 0.086015 | 0.032767 | 0.110591 | 0.9983 | 0 | yes |
| 128 | Tripoint Works | 0.147455 | 0.073727 | 0.204799 | 1.5437 | 0 | yes |

Phase percentiles are separate distributions and must not be added. These rows
measure CPU session/encoding headroom, not network or GPU capacity. The historical
table in `local-excellence.md` measured session work only and is not a direct
before/after comparison.

A separate 1,200-tick, 16-fighter recording was written and independently verified
through the CLI: 5,527,890 bytes, SHA-256
`9d19742bb065603e6e0ae2bb255b105f9e45486c188eaaf89950a6ac967af128`.
Unit coverage includes a 4,000-tick recording with drone spawns and round endings,
changed intermediate positions, altered scores, targeted payloads, reordered and
truncated records, unsupported headers, and failed writes/flushes. CLI tests prove
overwrite refusal and nonzero exit for an impossible timing budget.

The stronger recording check exposed nondeterministic tied podium ordering.
Scores now sort descending, then callsign ascending, and MVP uses that same list.
Normal sessions still allocate random UUIDs. `docs/BENCHMARK.md` owns report and
trace formats; no live network message shape changed.

Local validation: 545 Rust tests pass with one ignored (544 in the full workspace
run, then the final targeted server suite adds the header/unicast contract test).
Unfiltered workspace line coverage was 94.28 percent before that last test-only
addition. Warnings-denied Clippy, formatting, release builds, dependency policy,
11 Godot harnesses, and all 6 verifier fault cases pass. The four-agent loopback
smoke passed in 22.6 seconds with 9 frags and no spawn deaths. The OpenGL visual
tour passed all 15 states and its current stills were inspected and published.
Public-server load and renderer scoring remain unmeasured.

The remaining sections describe the future rendered showcase, not shipped behavior.

The historical scale ladder found simulation headroom at 256 fighters, but it
did not measure real network fan-out or rendering. Bandwidth remains a capacity
hypothesis to test, not a proven bottleneck. CPU regression gates and a rendered
showcase answer different questions; both are needed.

The client side is not thin, it is absent. Nothing in the client times a frame.

## The prerequisite nobody names

A benchmark that renders a different world on every run is not a benchmark.

The client renders whatever a live server sends over a socket, so scheduling jitter, connection timing and roster order mean two runs show different matches. Before any camera path or overlay matters, **the content has to come from a file**. The server already serialises exactly the right bytes every tick and then throws them away; writing them to a trace file is a small change to code that exists, and it is what makes everything else possible.

Two more determinism requirements sit alongside it:

**Everything advances on wall time, never per frame.** The camera and the trace cursor are both functions of scene time in seconds. If either steps per frame, a fast machine walks a different path than a slow one and there is nothing to compare.

**Smoothing prerequisite already shipped:** pawn interpolation uses exponential
smoothing, with a headless frame-rate check. A replay still needs to drive its
cursor and camera from elapsed scene time and prove consistent content at the
same timestamp across different rendering rates.

## The flow

Nine scenes, two hundred seconds of scored time, escalating monotonically so a machine that falls over does so late and visibly, and the per-scene split says why.

| Scene | Time | Stresses |
|---|---|---|
| 0. Prime, discarded | 10 s | Nothing. It compiles every pipeline so a shader hitch is not recorded as stutter |
| 1. Cold open, empty arena | 20 s | Geometry, one shadowed light, fog, tonemap. The floor |
| 2. The scrap, 16 fighters | 25 s | Draw calls, nameplates, HUD, audio. The number a player actually cares about |
| 3. Muzzle storm, 32 firing | 20 s | Clustered dynamic lights and alpha overdraw |
| 4. Full server, 64 fighters | 25 s | Node count and per-node script cost. Where CPU-bound separates from GPU-bound |
| 5. Overdraw pit | 20 s | Fill rate, from a far pose where every billboard scales up and overlaps, then a push to point blank |
| 6. Compliance pressure | 20 s | The 2D layer, runtime node construction, and the only scene with a story in it |
| 7. Massive arena, 256 | 30 s | Everything at once, beyond anything retail does. The shot people screenshot |
| 8. Resolution ladder | 20 s | Scene 2 replayed at three render scales |
| 9. Score screen | static | |

Scene 8 is the most diagnostic thing in the flow and is not optional. If frame time is flat across the ladder the machine is CPU or draw-call bound; if it scales with pixel count it is GPU bound. That is what turns a score into an explanation.

**What this renderer actually is**, so the flow stresses the real thing rather than borrowing from benchmarks for other games: about thirty meshes, one shadowed directional light, four static point lights, fighters as alpha-scissor billboards with a point light on each muzzle, a canvas layer for the HUD, and no particle systems anywhere. So the honest stressors are draw calls, dynamic lights in the cluster, alpha overdraw, canvas throughput, render scale, the shadow atlas, and per-node script cost. Tessellation, ray tracing, probe-based global illumination and destruction are not realistic here, and adding a particle system purely to make the benchmark look hard would measure something the game does not ship. When muzzle sparks and impact debris become real content, the benchmark gains a particle scene then and not before.

## The statistics

**The rule everyone gets wrong, first: compute in frame time and convert to frames per second only at print.** The mean of per-frame rates is not the reciprocal of the mean frame time, and it flatters fast frames. Average is frame count over elapsed time, and nothing else.

Per scene and overall: count, min, the first and fifth percentiles, median, mean, ninety-fifth, ninety-ninth, ninety-nine-point-nine, max, standard deviation, and median absolute deviation, which a single hitch does not move.

**The one percent and point one percent lows, all three conventions, each labelled.** Three definitions circulate and people quietly compare across them: the plain percentile, the mean of the worst one percent of frames by count, and the mean of the worst frames by accumulated time. Publish all three and name each. The composite uses the time-weighted one, because it is the one that penalises what actually ruins a session.

All three need the raw frame-time array rather than a histogram. Twelve thousand frames is forty-eight kilobytes. Keep the array.

**Stutter, which is where the nerd analysis is earned.** Consecutive-frame delta at median, ninety-ninth and max, which separates slow-but-smooth from fast-but-juddery. A windowed stutter count, where a frame counts when it exceeds twice the median of the trailing second, so a scene transition is not counted but an in-scene hitch is. Total time spent in frames over 33 and over 50 milliseconds, as a share of the run, which is how much of it felt bad. And frames over budget against a declared target, mirroring the server's vocabulary so both reports read alike.

The smoothness headline is the ratio of the ninety-ninth percentile to the median, reported directly. It needs no clamping and no explanation, unlike an invented index.

**The composite score** is a weighted geometric mean of per-scene median frame rates, multiplied by a penalty derived from the ratio of median to ninety-ninth percentile, calibrated so a named reference machine scores exactly a thousand. Geometric because it is unit-invariant and stops one enormous scene dominating. Median per scene because it does not chase the tail, which the penalty handles separately. The raw score, the penalty and the final score all print separately, alongside every per-scene figure and every weight, so a reader can watch a machine averaging a higher rate lose to one that holds a lower rate flat.

**Confidence intervals, honestly.** Frame times are strongly autocorrelated, so a naive interval on twelve thousand frames is far too narrow and would be rigour-shaped nonsense. Proportions use the Wilson interval that already exists in the playtest harness, reused rather than reimplemented. Within a run, batch means: split each scene into ten equal-time blocks and put an interval on those ten block means, because blocks are long enough to be near-independent. Across runs, run the flow three times and report the median with the range. And never put an interval on a maximum, which the output should say out loud.

## Comparability

A result is comparable only if it carries its environment: engine version and rendering driver, adapter name, vendor and API version, processor and core count, operating system, memory, peak video memory, display resolution and refresh, whether the machine was on battery, the preset, and hashes of the flow manifest and the trace.

A result missing any field is flagged unverified and the comparison tool refuses it. That is mechanical rather than a note in a document.

Four presets, and only same-preset results compare. Pinned per preset: resolution, render scale, rendering method, anti-aliasing, shadow atlas, fog, texture filter, frame cap off, vertical sync off, and window mode, because exclusive fullscreen and windowed do not compare.

The prime scene is discarded, and a declared number of frames after each transition is discarded too, so pipeline compilation is never recorded as stutter. The number goes in the result.

## Zero cost, and one honest limit

Nothing here touches a paid service. The engine is free and already pinned, the trace is a local file, results are local JSON and CSV, the published table is a committed markdown file whose history is the git log, and comparison is a subcommand of the server binary. No telemetry leaves the machine, which the stats plan already forbids.

The limit worth stating before anyone tries: **the scored flow cannot run in CI.** The runner has no GPU and the existing capture path already falls back to software rendering, which would take hours for two hundred seconds of sixty-four-fighter rendering. CI gates the pure-function statistics and the determinism checks. The score is a local artifact published as a table. Nobody should gate a pull request on a frame rate.

## Rungs

1. **Trace export.** The server writes the per-tick broadcast it already serialises to a file, with a header carrying the config and a content hash. While in there, count the unicast bytes instead of discarding them, and make the determinism check compare the trace hash rather than only the frag list, which finally delivers what the stats plan promised.
2. **A frame-time meter as pure functions**, with a headless harness asserting exact answers on a canned array. No rendering, so it runs in the existing CI job.
3. **Trace playback, and the smoothing fix.** The client feeds itself from the trace file instead of a socket. Accepted when a headless replay ends with a scoreboard matching the server's own frags for that seed, which means client and server agree on the match with no socket between them.
4. **Camera path and flow manifest.** Accepted when the camera transform at three points is identical across two runs driven at deliberately different simulated frame rates.
5. **The run itself:** overlay, per-scene banner, score screen, and export. Every number on screen read from the same structure the file is serialised from.
6. **Determinism, presets, environment stamping,** including the refusal to compare unverified results. Accepted when three consecutive runs show a composite coefficient of variation under two percent.
7. **Score, intervals, and the comparison subcommand.** Accepted when comparing a run against itself reports zero delta and an interval containing zero.
8. **The escalation scenes and the published table,** with at least two machines in it.
9. **Trailer capture,** optional and never scored.

Three small corrections to fold in along the way: the threshold check is called twice where once would do, the documented command line disagrees with the actual flags in two places, and the snapshot byte figure silently becomes wrong the moment interest management lands, because it counts broadcast only.

## Related

- `benchmark-and-stats.md`: the statistics this implements, and the overlay it describes.
- `massive-arenas.md`: the measured table proving the simulation is not the wall.
- `visual-qa-tour.md`: the tour already measures frame time per state and is the natural place the flow manifest borrows from.
- `look-pass-boomer.md`: the renderer switch that changes every number here, so the first published table should predate it and the second should follow it.
