# Rust tip screenshot gate

Status: **shipped** in #239 (v0.47.1). Spend: $0. Checked 2026-09-24.

## Goal

Remove the last Python file from the repository. `tools/gate_tip_jammer_orange.py`
was the orange-footprint gate that `tools/capture_tip_screenshots.sh` runs after
a historical jammer tip capture, and it left a hole in the Rust and GDScript
rule. Port it faithfully, switch the caller, and delete it.

Non-goals: changing the thresholds, the stills it checks, or the capture
itself.

## Change

- New workspace crate `tools/tip-gate` (`fragr-tip-gate`), binary
  `gate-tip-jammer-orange OUT_DIR`. Its only dependency is `image` 0.25 with
  the `png` feature, already in `Cargo.lock` through `tools/spritegen`, so no
  new third-party crate enters the lockfile.
- Same stills and floors (20: 0.05, 22: 0.03, 23: 0.05), same sampling (every
  second row and column from the top left, alpha discarded), the same orange
  test, the same output lines and exit codes (0 pass, 1 fail or missing, 2
  usage). An unreadable PNG now reports `cannot read` and exits 1 where Python
  exited 1 with a traceback.
- `tools/capture_tip_screenshots.sh` calls it through
  `cargo run -p fragr-tip-gate --release --locked`.
- `AGENTS.md` and `docs/ROADMAP.md` no longer carry the Python exception. No
  other `*.py`, `*.pyc` or `__pycache__` path is tracked.

## Verification

The Python gate (Python 3.12.10, Pillow 11.3.0, local only) and the Rust binary
were run on the same directories, capturing stdout, stderr and exit code
separately:

| Case | Python exit | Rust exit | stdout | stderr |
|---|---:|---:|---|---|
| Committed `docs/screenshots` stills | 0 | 0 | identical | identical |
| Still 22 with three quarters of columns painted grey (orange 0.0000) | 1 | 1 | identical | identical |
| Only still 20 present | 1 | 1 | identical | identical |
| Still 23 replaced by non-PNG bytes | 1 | 1 | identical | traceback vs `cannot read` |

On the committed stills both report orange 0.2691, 0.0778 and 0.2899 and PASS.
Path separators were normalised before comparing, and line endings ignored.
Unit tests cover the colour boundaries, the sampling grid, pass, fail, missing,
unreadable and usage paths, with RGBA inputs whose orange is fully transparent.
Receipts: `.agents/spawnq/gatecases/`.

Repository checks, local Windows, logs under `.agents/verify-port/`: fmt,
strict Clippy, the release benchmark, release build, `cargo deny`, the playtest
smoke and the six-map roster pass, and `cargo llvm-cov --workspace` passes every
test at 93.97 percent of lines. Two `fragr-brain` bot tests
(`failed_calls_fall_back_and_still_count`,
`a_bad_key_switches_the_brain_off_after_one_call`) failed intermittently in
local `cargo test --workspace` runs and passed on rerun; the first also fails
intermittently on unchanged `main` here. This change does not touch that crate.
