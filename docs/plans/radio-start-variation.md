# Radio startup variation

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. Ordinary startup randomizes a populated station before the existing track picker.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** $0. Existing committed tracks only.

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

## Behavior and owning seam

Before this increment the ordinary radio randomized tracks but always started
on station index zero. Startup now selects a random station with tracks through
`radio.gd`, then reuses its existing random track picker and no-repeat history. Empty
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
clean exit and `test_radio: PASS`. The final whole client checker passes all
184 scripts and 86 harnesses with clean exit 0 in
`.agents/m06-buildout-20261001/client-whole-contact-final.log`. The matching
standard tour in `.agents/qa/m06-standard-contact-final/` uses ordinary startup,
passes 32 states and publishes 13 inspected stills. No named station or track is
claimed as a guaranteed random result. CI and release remain pending; subjective
listening and a campaign-specific song assignment remain outside this increment.
