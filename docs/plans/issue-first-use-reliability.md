# First-use and hosted-match reliability

Status: **shipped on main** in [PR #400](https://github.com/blisspixel/fragr/pull/400), with hosted checks passed. Updated 2026-10-13. The next published desktop release and complete visual tour remain pending. Issues #392 through #399 are closed; #391 still tracks the adapter missing from the published v0.82.0 archives.

## Goal and scope

Bundle the matching adapter in desktop archives with combined license notices.
Use absolute MCP paths and explain initial snapshots, held input and weapon IDs.
Reject actions when the current session has no observed body. Preserve server
simulation authority; a queued action is not a confirmed outcome.

Keep an owned match visible on the boot menu, avoid an automatic unrelated Join
probe while it runs, and retain the last session settings when returning from a
match. Give Sabotage automatic fill a ten-fighter default while retaining explicit
per-mode counts. Clarify the announcer Host versus Run a match.

No protocol change, paid operation, cloud deployment or campaign scope change.

## Verification and open evidence

Run Rust formatting, adapter and license tests, workspace checks and the existing
Godot host-menu harness, followed by repository CI. Packaging runs the three OS
archive builds and checks both bundled executables. Native packaging and rendered
menu evidence remain separate from Rust and headless harness results. Existing
v0.82.0 archives are unchanged until a new verified release is published.

Local evidence: workspace tests pass, including 1,392 server tests; CI-pinned
Rust 1.97.1 Clippy and locked workspace release build pass. Every Godot script
and harness passes. The host-menu harness verifies actual menu replacement,
stop and automatic-fill persistence. Linux adapter `--version` and `mcp --help`
run, and combined server/adapter notices cover 95 linked crates. Actual Xvfb
1280x720 Mesa llvmpipe renders of the running-match and ten-fighter forms were
inspected. The local default Rust 1.99 emits an untouched large-error Clippy
warning; the CI pin passes. The original local pass did not have cargo-llvm-cov.
The subsequent [PR CI](https://github.com/blisspixel/fragr/actions/runs/38353035253)
passed the required test/coverage gate and portability checks; the
[PR package workflow](https://github.com/blisspixel/fragr/actions/runs/38353035301)
passed Linux, Windows and macOS packages without publishing. The
[merged main CI](https://github.com/blisspixel/fragr/actions/runs/38379828754)
also passed. These results do not turn the unpublished packages into a release.

The complete 32-state Linux Xvfb llvmpipe tour failed the FpMuzzle and two
ShotEffects visibility assertions. Rail and Scatter receipts observed an effect
before the later strip frames, while Flechette reported no visible frame. The
failed receipt remains preserved. No assertion was weakened and no complete
tour pass is claimed. The actual multiplayer-menu frame and two explicitly
synthetic owner-state menu renders were inspected and retained. A new release
waits for the complete visual gate to be characterized and passed.
