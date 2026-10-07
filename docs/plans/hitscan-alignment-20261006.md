# Rendered target and authoritative shot alignment

Status: **implemented**, diagnostic only, 2026-10-06. Integration follows the
current-match quality branch. Lag compensation is not implemented by this work.

## Goal

Measure the difference between the actual client transform timeline and the
server's finite shot volume before selecting a compensated hit rule. The
existing 100 ms interpolation buffer is part of the measured path.

## Method and limits

A headless GDScript exporter runs the actual `RemotePresentation` timeline at
60 rendered samples per second. It feeds fixed 20 Hz target positions with
explicit inbound and outbound delay, samples the displayed feet, and records
the current target position at the tick when the input would resolve. Static,
crouch-speed and full-speed targets cross lanes at several distances.

The Rust playtest example reads those bounded samples and uses the production
`combat::aim_at` and `Ray::actor_stance` functions to compare a centre-body ray
against the shown and current bodies. It reports counts, distances and errors.
No copied hit geometry or second interpolation implementation is introduced.

This is a controlled transform/geometry diagnostic, not a network benchmark,
live GameState combat result, weapon accuracy estimate, or human LAN review.
It has no spread, packet loss, jitter, cover or shooter movement. Input delay
and snapshot delay are stated separately; server tick quantization remains
visible. A physical two-machine baseline is still required before final rewind
tuning. No wire or gameplay rule changes belong to this measurement.

## Verification

Reject malformed, nonfinite, oversized and inconsistent input. Require samples
and successful shown-body control hits. Static targets should agree regardless
of delay; a moving target displaced beyond its shot radius must expose a miss.
Record exact commands, file hashes and actual output after running both sides.

## Spend

Zero. Reuses installed tools and local code only.

## Local result

The actual exporter and analyzer completed 6,480 samples in 27 rows on
October 6. Each row contains 240 samples after startup. All shown-body control
rays hit; all static targets agree. The [complete report](../evidence/hitscan-alignment-20261006.json)
retains the three distances. This representative 15 m table records the
displacement between the displayed body and its position when input resolves:

| Speed m/s | Delay each way ms | Current-body hits / 240 | Mean displacement m | Maximum displacement m |
|---|---:|---:|---:|---:|
| 0 | 0 | 240 | 0 | 0 |
| 0 | 40 | 240 | 0 | 0 |
| 0 | 80 | 240 | 0 | 0 |
| 1.7 | 0 | 240 | 0.1983 | 0.2267 |
| 1.7 | 40 | 240 | 0.3513 | 0.3797 |
| 1.7 | 80 | 193 | 0.4760 | 0.5043 |
| 5.0 | 0 | 92 | 0.5833 | 0.6667 |
| 5.0 | 40 | 0 | 1.0333 | 1.1167 |
| 5.0 | 80 | 0 | 1.4000 | 1.4833 |

The zero-delay moving cases still contain the existing presentation buffer
and next-tick input resolution. Delay here is an explicit synthetic input,
not measured network latency. The slow row uses crouch movement speed with
the analyzer's standing-body control volume; it does not test a crouched
hitbox. These counts establish the mismatch in this controlled crossing
experiment, not a player's hit rate. A bounded server history proposal needs
live timing, obstruction, trust-boundary and moving-shooter tests before it
can change combat.

Reproduce with the pinned engine and existing native example:

```text
godot --headless --path client --script ../tools/measure_hitscan_alignment.gd -- ABSOLUTE_SAMPLES_PATH
cargo run -p fragr-playtest --locked --example hitscan_alignment -- ABSOLUTE_SAMPLES_PATH REPORT_PATH
```

Private source samples are `.agents/hitscan-alignment-20261006.json`, SHA-256
`635be262795a10d55995670fd4d42b8cb4857a4b349232164fe55f171ff3cc86`.
The report SHA-256 is
`655536106ece982616b5feb521185d1491abc417e6384360a94dabb972437b5b`.
No shader, movement or combat policy was changed to produce these results.
