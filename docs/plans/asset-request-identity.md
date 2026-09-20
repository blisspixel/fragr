# Preserve accepted asset request identity

Status: implemented, 2026-09-20. Task: [#190](https://github.com/blisspixel/fragr/issues/190).
Integration pending.

## Failure and scope

A successful image submission can include an unusable polling address. The
previous tool rejected that address before saving the returned request ID, losing
the recovery handle for an accepted paid job. Preserve the ID before validating
polling metadata. Keep the existing origin guard, reservations and spending caps.
This cannot reconstruct the response lost by the earlier live Clerk request.
That reservation remains uncertain until its dashboard identity is reconciled.

## Contract and implementation

Keep one request ledger in `tools/spritegen/ledger.rs`. Add an Accepted event
between Reserved and Submitted, containing only the validated request ID. Sync
that event before validating the returned URL. Invalid, absent or ambiguous IDs
leave the reservation uncertain. Invalid polling metadata leaves Accepted intact;
generation must refuse to create a replacement POST. Explicit local `recover`
can attach the documented fixed status endpoint to the same verified ID, never
substitute another ID. Preserve existing and legacy ledger formats.

One validator governs submission IDs, status paths and recovery. Both returned
polling URLs and status responses must identify the same job. Never persist
arbitrary response bodies or rejected URLs, and never forward credentials to a
new host. No dependency, runtime pin, game protocol or player presentation change.

## Current sources

Checked 2026-09-20: the official [request lifecycle](https://docs.higgsfield.ai/docs/concepts/requests)
requires storing the accepted `request_id` and prefers returned polling URLs.
The [status endpoint](https://docs.higgsfield.ai/docs/api-reference/requests/get-request-status)
documents `GET https://api.higgsfield.ai/requests/{request_id}/status`, allowing
explicit recovery when a known ID's returned URL is unusable. The live rejected
URL's origin was not saved; no host migration is assumed or authorized here.

## Verification and completion

Use offline fake transports to prove identity survives malformed or foreign
polling metadata, reruns never resubmit, recovery cannot change a known ID, and
conflicting status responses never download another job. Exercise interruption
at Accepted and Submitted, malformed IDs, old ledgers and unchanged budget/file
guards. Run focused tests, strict workspace checks and unfiltered coverage. CI
must pass before integration. No paid call is needed to prove this repair.
Record verification here and update the roadmap and plan index when integrated.

## Local evidence

All 696 workspace tests pass, with two existing ignored generators. Unfiltered
line coverage is 95.83 percent against the unchanged 90 percent floor. Formatting,
strict workspace Clippy, release build, licenses/bans/sources, and the existing
CPU determinism/budget gate pass. Logs: `.agents/asset-identity-*.log`.

The 89 generator tests include recovery after foreign, missing, malformed and
conflicting polling metadata; duplicate identity/state fields; refusal to replace
an accepted ID; unchanged receipts after rejected recovery; and resume without
another POST. Old ledger cases remain covered. CLI help and keyless prompt output
were exercised using the release binary. Runtime/client CI gates remain required
before merge. No paid calls were made to implement or verify this repair. The
earlier Clerk reservation remains unresolved and must not be resubmitted.
