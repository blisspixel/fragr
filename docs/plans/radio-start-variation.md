# Radio startup variation

**Status:** in flight, 2026-10-01. Explicitly requested startup variety.
Sequencing stays in the [roadmap](../ROADMAP.md#full-build-order-2026-09-27).
**Spend:** $0. Existing committed tracks only.

## Behavior and owning seam

The ordinary radio currently randomizes tracks but always starts on station
index zero. Select a random station with tracks during `radio.gd` startup,
then reuse its existing random track picker and no-repeat history. Empty
stations stay available through manual cycling but should not be the default
when a populated station exists. An empty catalog stays silent and safe.

Visual test runs use the same default. The existing explicit
`FRAGR_QA_RADIO_COMPARE=on` is a measured comparison mode that pins one track;
it is not normal startup. Keep that opt-in behavior. No campaign song is
currently assigned by this change; a future authored moment must request its
specific cue explicitly rather than changing the ordinary radio default.

## Verification

Extend the existing radio harness with seeded station-selection coverage,
empty and single-populated catalogs, and variation of both station and track.
Retain manual cycling, shuffle, volume, explicit comparison and decoder-retirement
checks. Run the focused harness and final whole client checker, and refresh
the standard visible tour before release. Unit seeds keep assertions repeatable;
normal startup retains the existing randomized generator.

Focused pinned-engine receipt
`.agents/m06-buildout-20261001/client-radio-startup-final.log` passes with a
clean exit and `test_radio: PASS`. Final client and published-tour gates remain
pending alongside the coordinated mission, art, sound and body-contact work.
