# Bounded client checks

Status: **shipped** through [PR #422](https://github.com/blisspixel/fragr/pull/422),
main `8ecbb99c77a74dbb28ff8090fc86f5b58d36a881`.
Main CI [39150766048](https://github.com/blisspixel/fragr/actions/runs/39150766048)
passes. v0.88.0 is published after release run 39153610159 passed, three
downloaded archive digests/integrity checks and the downloaded Linux
installation/local-match/build-metadata checks.

## Problem and scope

Main CI 39135842942 attempt 1 passed every job except the Windows client
checker, which stopped reporting progress after `test_m02_ward` at 14:53:19 UTC.
It was canceled at 15:52 UTC. The next discovered harness is `test_m03_local`.
The same source passed the earlier Windows PR run and main's Linux and macOS
checks. These facts do not identify the blocking engine or process operation.
Attempt 2 passed the unfinished Windows job at 16:19:28 UTC. The earlier stall's
root cause remains unproven.

The shell checker captures each engine invocation through a command substitution
with no outer deadline. Add a native process guard using the existing playtest
crate and clap dependency. Keep output in individual files, print BEGIN and END
markers, and retain diagnostics on failure. A bounded child must exit and retain
the existing nonzero-exit, engine-error and required-PASS checks. Continue other
checks after a failed invocation, except failed import.

## Architecture and compatibility

No game, protocol, save, asset or dependency changes. The guard runs only during
developer checks. Use a finite positive command deadline, inherited stdin and
file-backed stdout/stderr. Never wait for inherited output pipe EOF. On Windows,
terminate the owned command's descendant tree on deadline. Launch native Godot
directly so the retained handle owns its engine or Windows console wrapper.
Shell fixtures explicitly select their interpreter, without an emulated exec.
Preserve the owned server's stdin shutdown lease.
Add an outer CI step budget as a last resort. No paid calls or player runtime
integration.

The [pinned Windows console wrapper](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/console_wrapper_windows.cpp)
waits for its engine and descendant job to empty. This is a blocking seam to
measure, not a proven cause of this stall. The inherited-output test establishes
that our guard does not wait on pipe EOF; it does not establish descendant
cleanup after an otherwise successful parent exit. Timeout cleanup has its own
native descendant test. Keep the original `fragr-playtest` default executable
explicit so existing `cargo run -p fragr-playtest -- ...` callers still work.

## Verification and acceptance

- Native guard tests cover success, nonzero exit, invalid deadlines, timeout,
  PASS followed by a hang and inherited output handles.
- Fault-inject the actual shell checker, including a timed-out harness followed
  by another harness. A PASS must never hide a timeout or engine diagnostic.
- Verify Windows descendant termination on the Windows runner, including a
  child holding output handles. Preserve failure logs as CI artifacts.
- Run rustfmt, clippy, locked native tests, verifier fixtures and the full
  pinned client checker. Independently review the final patch. Return to green
  main before advancing #413, then package and verify v0.88.0.

## Current evidence

The initial implementation and independent review passed six locked native
guard tests and twelve shell verifier fault-injection scenarios locally.
Focused clippy with warnings denied, rustfmt and diff whitespace checks pass.
The existing playtest command still selects its original binary; its actual
four-agent asserted smoke passed with eight frags and zero spawn deaths.
PR #422 run 39143469866 passed native tests, 92.74 percent workspace line
coverage, Linux and macOS checks. Windows native process-tree cleanup passed,
then all 585 actual Godot checks (187 harnesses) passed at 16:39:41 UTC.
The following fault verifier passed ten scenarios and stalled in its first
timeout scenario until the 35-minute CI deadline. The retained fixture includes
`test_second: PASS`, proving the checker advanced beyond the timed-out harness.
The outer command substitution still exposed the verifier to inherited pipe
EOF; its missing transcript prevents a definitive process diagnosis.

The repair puts each scenario behind a separate 30-second native deadline and
a retained regular-file transcript. Only exact checker exits 0 or 1 are valid;
an outer timeout cannot pass a negative scenario. Delete fixtures only after
the complete suite succeeds. Windows fault checks run before its full client
suite, so this failure is detected sooner. Native launches also gain a focused
executable/output path-with-spaces test. Fresh local checks, independent review,
PR and main CI remain integration gates. No dependency or lockfile changed.
Work uses $0.

The revised seven native tests, twelve fault scenarios, focused clippy with
warnings denied, rustfmt, action pins and whitespace checks pass locally.
Independent review found no remaining blocker. Final local and PR/main checks
pass: 585 client checks with 187 harnesses, seven native guard tests and twelve
fault scenarios. Main's Windows fault suite passed at 18:00:31 UTC and its full
client suite at 18:16:20 UTC; macOS passed at 18:05:34 UTC. Linux client checks
passed at 17:54:16 UTC. Workspace line coverage is 92.74 percent. The reviewed
PR head and merged main trees were identical. The original stall's root cause
remains unproven; the shipped repair bounds and retains future failures.
