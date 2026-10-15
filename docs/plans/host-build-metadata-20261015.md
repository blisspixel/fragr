# Fresh local host build identity

Status: **implemented**, integration pending, 2026-10-15. The composed release check exposed an additional
shared-target worktree cache defect; its correction passes final verification. Developed on
`fix/host-build-metadata-20261015`, based on main `fd8c527`, then integrated into
`feat/launch-authority-20261015`.

## Problem and scope

The shared build script only watches Git HEAD. On a branch, committing updates
the branch ref while HEAD still names the same branch. Adding a release tag
also leaves HEAD unchanged. An incremental build can retain an older release
and commit in `--version`, `/status` and MCP serverInfo, misleading a host
checking which build is running. This is build invalidation, not a new runtime
version protocol or evidence that a running process upgrades itself.

Watch the per-worktree HEAD and shared Git refs and packed refs. Let Git resolve
the administrative paths, including linked worktrees, rather than assuming
`.git` is a directory. Preserve explicit build-version/commit environment
overrides and source-archive fallback. Do not watch the object database or
force every unchanged build to rerun. No third-party dependencies, transport changes,
gameplay changes, paid services or cloud work.

The composed build retains an old absolute out-of-package include path when
two worktrees reuse one target directory. The first new regression reproduces
that defect; anchoring the include with `env!("CARGO_MANIFEST_DIR")` also fails
because Cargo does not invalidate on that supplied value. Retain both failures.
Move the same implementation into a private std-only `fragr-build-metadata`
workspace package and make the seven binary build scripts call it through
ordinary path build-dependencies. Cargo then owns the shared source as a package
instead of an include outside the consumer package. Resolve the consumer's
`CARGO_MANIFEST_DIR` at runtime as before. This adds no third-party dependency,
network operation, runtime service or external license obligation. The workspace
manifest, lockfile, license policy and package notices must be checked normally.

## Verification

Use offline temporary Cargo packages containing the actual build wrapper and
shared path-dependency source, with independent test output and no third-party
dependencies. Build the consumer,
advance its branch without changing source/HEAD, and build again; confirm the
baked commit and release change. Add/delete/pack tags, build a linked worktree,
and verify explicit environment overrides. A no-change rebuild must remain
fresh. Fixture Git operations touch only temporary repositories, never this
checkout. Retain the failing baseline and passing focused run. Root owns
review and integration; no independent push or merge.

Primary references checked 2026-10-15: Cargo's
[build-script change detection](https://doc.rust-lang.org/cargo/reference/build-scripts.html#change-detection)
uses declared file paths and modification times, and scans directories when
declared. Git's [rev-parse path resolution](https://git-scm.com/docs/git-rev-parse)
distinguishes per-worktree and common administrative paths. Keep the established
Rust edition and single-colon Cargo instruction syntax.

Success is fresh baked metadata after relevant repository changes and stable
metadata on a no-change rebuild, with explicit release overrides unchanged.
This does not establish that a package was published or that a live host has
restarted into it. Spend: $0.

## Local evidence

The actual Cargo-cache regression fails against the previous script: after the
fixture advances its branch, the executable still prints the first commit and
`v1.0.0`. With the fix it passes branch advances, loose tag addition, packed tag
deletion, a branch update after packing, linked-worktree commits/tags, detached
HEAD, environment overrides and removal, and source-archive fallback. No-change
builds stay fresh with and without packed refs. The final fixture run uses Rust
1.97.1, offline/locked Cargo and its own temporary target directory; it takes
about three seconds. The test is also a normal server integration-test target.

Focused command: compile `server/tests/build_version.rs` with
`rustc +1.97.1 --edition=2021 -D warnings --test`, then run the resulting harness
with `RUSTUP_TOOLCHAIN=1.97.1`. This avoids rebuilding the server while the M14
lane runs. Formatting and `git diff --check` pass. Retained ignored diagnostics
are `.agents/host-build-metadata-before.log` and
`.agents/host-build-metadata-after.log` in the isolated worktree, also retained
under `.agents/launch-authority-20261015/` in the integration checkout. Full
composed gates and package verification remain with integration, not this
focused proof.

## Composed cache failure

The first composed release rebuild still advertises `v0.83.0` at current HEAD
`fd8c527` (`v0.84.0`). The active Cargo dep-info names an absolute helper source
inside the older `/tmp/fragr-sabotage-20261015` worktree, plus its old HEAD watch
path. The helper include lives outside its consumer package. Reusing the target
directory therefore keeps that cached helper even when the current worktree's
copy changes. Both the workspace fingerprint trace and old output are retained;
no cache cleaning substitutes for a reproduction.

A new normal integration test first builds the linked worktree, edits only the
main worktree's shared metadata implementation, then rebuilds through the same
target directory and switches back. The old include and a trial wrapper using
`env!("CARGO_MANIFEST_DIR")` both fail the expected changed-source assertion.
The final design uses the private build dependency described above. The test
exercises its actual package topology, retained source, unchanged-build cache
and both switch directions. Existing branch/tag/packed-ref/archive/override
checks now use that same wrapper and dependency implementation.

Diagnostics remain under `.agents/launch-authority-20261015/`, including
`metadata-workspace-cache.log`, `metadata-shared-target-before.log` and the
rejected wrapper result `metadata-shared-target-after.log`. Both tests pass with
the build dependency, including shared-target source changes and switches in
both directions. The complete workspace reports 2,099 passing tests and five
intentional ignores, with no failures or filtered tests. Formatting, strict
workspace Clippy and release workspace compilation also pass. The metadata
source's unfiltered workspace coverage passes at 92.99% lines, above the
unchanged 90% gate, with all 2,099 tests passing again and no filtered tests.
The subsequent final MCP Rocket correction adds one test: the complete native
chain passes again with 2,100 tests, five intentional ignores and unfiltered
line coverage of 93.01%. The final release rebuild preserves the corrected
server identity and hash below.

The actual rebuilt release now says `fragr-server v0.84.0`; a fresh owned
loopback `/status` returns the matching release and full `fd8c527` commit.
This checks the original shared target without cleaning it. Its server SHA-256
is `c5a5b28502f01847e5f2b71f469c439c225fdec11fc0089e291d43c07df8411a`.
Lockfile changes add only the private package and seven dependency edges.
Explicit `0.1.0` requirements on the path dependencies satisfy existing policy;
the earlier omitted-version policy failure remains retained. The real notice
generator still emits 95 third-party crate notices. No third-party additions or
license-policy exceptions are needed. The composed native receipt records the
final coverage result and the separate earlier gameplay evidence.
