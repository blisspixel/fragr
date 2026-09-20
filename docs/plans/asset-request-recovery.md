# Asset request recovery

Status: proven in PR #169, 2026-09-19. All five CI jobs passed across Linux,
Windows, and macOS. Merge: `1ae55df`.
Spend: $0. All verification uses fake transports or local files.

Follow-up, 2026-09-20: a live response exposed an additional gap before the
Submitted event. [Accepted request identity](asset-request-identity.md) preserves
the returned ID even when polling metadata is rejected. This earlier milestone
prevented duplicate submission but could still lose that recovery handle.

## Problem

The sprite generator records a frame only after downloading its output. An
interruption after submission, a missing image URL, or a failed download can lose
the paid request's identity and cause another submission on the next run. Torn
ledger records and read errors are silently skipped. The authenticated transport
also accepts an unchecked status URL from a response.

These are prerequisites for spending the remaining art credit. The spec already
passes `params.image_urls` through, so reference support is not entirely absent;
reference preparation and consistent multi-frame production still need a later pass.

## Design

- Keep one `ledger.jsonl` beside the output. Extend it with versioned typed events:
  reservation before POST, submitted request, completed result, and downloaded
  files. Preserve existing completed rows. Sync writes before advancing, and hold
  a standard-library file lock across generation to prevent concurrent duplicate
  submissions. Malformed, truncated, unreadable, or contradictory records fail closed.
- Record model, assembled request, and estimated cost with each reservation.
  Reject a changed request under an existing frame ID. Completed historical rows
  lack this provenance and remain explicitly legacy; do not invent it.
- Resume polling or downloading an existing submitted request. A reservation
  without a known request ID is uncertain and cannot automatically submit again.
  Provide an explicit local recovery command to attach an ID verified in the
  provider dashboard. It must never generate or infer that an unknown call was free.
- Reserve every newly submitted estimate against the approved run cap before
  making the call, including completions without usable outputs. Report estimates
  as estimates, not confirmed billing. Keep the $5 run ceiling and repository's
  $50 overall approval rule. Quota and provider billing still require verification
  before a paid run; a local estimate is not a provider-side spending limit.
- Bind authenticated requests to HTTPS on the official API origin. Validate
  status paths, disable redirects, and bound response/download reads. Downloads
  receive no API credentials. No new HTTP stack or dependencies.
- Keep command handling thin. Put recovery and ledger state in named modules
  within `tools/spritegen`, using its existing fakeable transport.

No new assets, paid requests, renderer changes, live-game dependency, or automatic
retry of an uncertain generation. Reference uploads and animation production are
subsequent work after recovery is proven.

## Current primary sources

Checked 2026-09-19: official
[request/polling guidance](https://docs.higgsfield.ai/docs/concepts/polling),
[SDK request lifecycle](https://github.com/higgsfield-ai/higgsfield-js),
[Rust file locks and syncing](https://doc.rust-lang.org/std/fs/struct.File.html),
and [reqwest redirect policy](https://docs.rs/reqwest/0.13.5/reqwest/redirect/struct.Policy.html).
The lockfile already uses reqwest 0.13.5. `File::try_lock` is stable since Rust 1.89;
the current project toolchain is newer. Preserve the existing direct REST path.

## Acceptance and verification

- [x] Interrupted submission never leads to an automatic second POST.
- [x] Poll/download failures resume the same request and conserve the cap.
- [x] Corrupt receipts, changed specs, duplicate IDs, and competing writers stop.
- [x] Legacy completed rows remain readable and cannot trigger regeneration.
- [x] Authenticated requests cannot follow a foreign status URL or redirect.
- [x] CLI checks, failure-injection tests, workspace checks, and 90 percent
  unfiltered coverage pass; platform CI verifies locking and file behavior.
- [x] Documentation explains recovery, estimated costs, reference parameters,
  remaining quota checks, and the limits of legacy receipts.

## Local evidence

Rust 1.98.1, Windows, 2026-09-19. Fake transports inject a lost POST response,
poll failure, absent URLs, empty/failed downloads, partial multi-image output,
write failure, changed estimates, and terminal provider errors. Tests verify no
repeat submission, preservation across reopening, and explicit keyless recovery.
Corrupt history and a competing writer are rejected. A loopback HTTP test checks
the real client's redirect policy. No provider is contacted by the suite.

Unfiltered workspace coverage: 95.00 percent, above the unchanged 90 percent gate.
The workspace has 564 passing tests and one existing ignored test; 84 passing
tests cover the sprite tool. Formatting, Clippy with warnings denied, release
builds, and dependency license/source/bans checks pass. The 1,200-tick benchmark
repeats deterministically within its budget. A four-agent real-wire smoke records
9 frags in 22.6 seconds. All twelve Godot harnesses pass. Linux/macOS/Windows CI
passed in run `35469217631`, including platform lock and file behavior.

Review boundaries: the cap covers estimates for new calls in one invocation,
not provider billing or shared account quota. Legacy rows lack request identity.
Lost reservations require reconciliation, never automatic resubmission. Preserve
and back up receipts; filesystem syncing cannot guarantee survival of disk failure.
