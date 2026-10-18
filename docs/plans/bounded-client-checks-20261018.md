# Bounded client checks

Status: **in flight**, integration repair for the #412 status bar round.

## Problem and scope

Main CI 39135842942 attempt 1 passed every job except the Windows client
checker, which stopped reporting progress after `test_m02_ward` at 14:53:19 UTC.
It was canceled at 15:52 UTC. The next discovered harness is `test_m03_local`.
The same source passed the earlier Windows PR run and main's Linux and macOS
checks. These facts do not identify the blocking engine or process operation.
Attempt 2 reruns the unfinished Windows job for additional evidence.

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
terminate the owned command's descendant tree on deadline; on Unix the shell
executes the engine in place. Preserve the owned server's stdin shutdown lease.
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

Source implementation and independent review are complete. Six locked native
guard tests and twelve shell verifier fault-injection scenarios pass locally.
Focused clippy with warnings denied, rustfmt and diff whitespace checks pass.
The existing playtest command still selects its original binary. The full
pinned client checker and actual four-agent playtest are running; PR and main
CI, including Windows native process-tree cleanup, remain integration gates.
No source dependency or lockfile changed. The Windows stall's root cause remains
unproven; deadlines make future stalls bounded and diagnosable. Work uses $0.
