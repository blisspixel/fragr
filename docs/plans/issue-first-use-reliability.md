# First-use and hosted-match reliability

Status: implemented and locally tested; hosted packaging and coverage pending. Issues #391 through #399.

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
warning; the CI pin passes. Local cargo-llvm-cov is unavailable; the hosted
90-percent coverage gate must pass before integration. Windows and macOS
archive qualification remains hosted evidence.

The complete 32-state Linux Xvfb llvmpipe tour failed the FpMuzzle and two
ShotEffects visibility assertions. Rail and Scatter receipts observed an effect
before the later strip frames, while Flechette reported no visible frame. The
failed receipt remains preserved. No assertion was weakened and no complete
tour pass is claimed. The actual multiplayer-menu frame and two explicitly
synthetic owner-state menu renders were inspected and retained. A new release
waits for the complete visual gate to be characterized and passed.
