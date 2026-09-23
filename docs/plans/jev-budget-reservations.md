# Jev paid-call reservations

Status: in flight, 2026-09-22. This is a developer tooling prerequisite for
bounded Jev playtests, not a player-facing feature.

## Goal

Keep a crash, concurrent process, or replayed provider receipt from silently
exceeding the local Jev ledger cap. Every paid request must leave durable
evidence before it is sent, and the next request must wait until that evidence
is settled or reconciled. A completed response is charged once.

## Scope and architecture

`agents/brain/src/budget.rs` owns the reservation beside the existing JSONL
ledger. `provider.rs` reserves before transport and settles after response or
failure. The CLI rejects `--no-ledger` for paid `play` and `ask`, and `spend`
reports a pending request. The local rule provider remains free. No game wire,
server, MCP, or player runtime API changes. No new dependency or ledger format
replacement is needed; old charge lines remain readable.

The reservation contains no credential. Its exclusive file creation admits one
paid request per shared ledger at a time. A separate file lock makes recovery
and cleanup atomic across processes. A leftover receipt blocks further spend
unless a matching fully settled ledger line proves cleanup was interrupted.
All failed replies and successful replies without complete billing evidence
retain the receipt even after their estimated charge is recorded. An unresolved
call requires provider usage reconciliation before the receipt is removed.
This deliberately favors a stopped playtest over an
unknown bill.

## Verification and spend

Tests use fake transports only. They cover the pre-send receipt, concurrent
budget instances, restart after an unresolved call, restart after a synced
settlement, total cap, receipt replay, and paid CLI refusal without a ledger.
Run Rust formatting, lint, workspace tests, coverage, build and the normal
CI checks. No paid request runs in CI or in this plan's validation.

Nick approved less than $20 total for later OpenRouter Jev validation, with
the repository's $50 total cap and $5 per-run ceiling still binding. Before a
real trial, compare the current provider key limit, balance, model price, and
ledger total; pass explicit run, aggregate and call caps. The provider key's
lifetime limit remains a separate backstop.

## Success criteria

An interrupted or uncertain request cannot be followed by another paid call
through the same ledger without reconciliation. A synced settlement can
recover automatically without double charge. The full validation suite passes
and the change reaches a green `main` through its own PR.

## Local evidence, 2026-09-22

The focused brain tests passed (70 library, 7 CLI) with fake transports only.
`cargo fmt --all -- --check`, workspace Clippy with warnings denied, workspace
tests, release build, benchmark assertion, four-agent playtest, six-map mixed
roster sweep, `cargo deny check licenses bans sources`, the Godot 4.7.2 headless
checks, and the Godot checker self-test passed in the isolated worktree.
The final budget revision passed the workspace lint, tests and release build
again. Final workspace line coverage was 95.33 percent, above the unfiltered
90 percent floor. The roster sweep logged spawn-death evidence on maps 2
through 6, including four on map 4; its thresholds passed. This branch does
not change spawn behavior. GitHub CI remains the integration gate before
merging.
