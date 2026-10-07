# Rendered target and authoritative shot alignment

Status: **in flight**, 2026-10-06. A diagnostic under current-match quality.

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
