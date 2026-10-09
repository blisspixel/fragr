# Current stable Rust compatibility

Status: **implemented locally**, 2026-10-08. The first
[PR #375 test job](https://github.com/blisspixel/fragr/actions/runs/37867067745/job/113616231138)
uses Rust 1.99.0 and refuses a newly introduced warnings-denied lint in the
Assessor volley regression. Its constant `chunks_exact(3)` loop now uses
`as_chunks::<3>().0`, the fixed-size slice API. The existing assertion still
requires exactly thirty launches, and both six-tick interval checks remain.
No lint allowance, test threshold or runtime source changes.

The corrected actual volley test passes locally: one passed, zero failed,
1,354 unrelated cases filtered, with Rust 1.97.1. Local installation of the
explicit Rust 1.99.0 toolchain leaves the active toolchain and other in-flight
worktrees unchanged. The current-stable all-target lint and new PR CI remain
their own gates. Original logs and exact source hashes are retained under
`.agents/presentation-stairs-composition-20261008/`.

The [composition receipt](presentation-stairs-composition-20261008.md) retains
the preceding full native checks and distinct release artifacts. This test-only
compatibility correction does not replace their source identities or claim a
new full test run. [The standard slice documentation](https://doc.rust-lang.org/std/primitive.slice.html#method.as_chunks)
and [lint reference](https://rust-lang.github.io/rust-clippy/master/index.html#chunks_exact_to_as_chunks)
were checked on 2026-10-08. Spend is $0.
