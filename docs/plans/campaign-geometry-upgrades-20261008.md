# Exact campaign geometry upgrades

Status: **implemented**, 2026-10-08. All four final installed replacements,
including both exact M09 predecessors, pass local store and owned-launch checks.
The composed M09 guard regression is corrected with a bounded opening and actual
original/blocked/corrected charge-fall proof. Complete native, unfiltered
coverage, strict lint and formatting pass. Client, package and mission
presentation acceptance remain separate work. Spend: $0.

The [stair architecture correction](stair-architecture-correction-20261008.md)
owns the authored walls, landings and guards. This plan owns safe local run
compatibility when those exact canonical bytes change. It covers the M10
interior descent, M09 office access, M08 tower flights and M12 bridge access.
Dated development maps and their evidence remain unchanged.

## Source identity and scope

Preserve exact predecessor map bytes as test fixtures before replacement:

| Mission | Exact predecessor SHA-256 |
| --- | --- |
| M08 Custodian of Record | `b9964704b9bf51e837118f25fbec9d93574d16634b1d281caf694181f44de666` |
| M09 Passenger Manifest | `4f45d0c5132dbc741537f83e541a97c8a4f8dd130ed0d74bde45f73eecff7381` |
| M10 Common Carrier | `d767c07691a88d810d945db952b7cda6c67ab968b2e1b6161a1f00790eeda49d` |
| M12 Terms of Cooperation | `8f84cca779909790d23c8af2fa59db38bb25c9b94f4422a969e79180a137c78d` |

Each successor must be a concrete strict-loaded source reviewed by the map
owner, with its own exact hash, unchanged objectives, supplies, entry spawn and
outcome semantics. A geometry candidate is not registered compatibility. No
arbitrary content hash, future replacement or same-named local map is accepted.
The preserved bytes also retain the actual worlds used for earlier receipts.

The exact originals now live under
`server/src/mission/run_file/store/fixtures/stair-predecessors-20261008/`.
The reader registers the map owner's four exact installed successors below.
Registration remains dormant unless the caller's expected canonical source is
the exact registered successor. The ten-case canonical stair suite passes;
full mission QA routes and inspected presentation remain separate gates.

| Mission | Installed successor SHA-256 |
| --- | --- |
| M08 | `00ec523f6f9ced8cd426023247370d0f478f004570e82c9d756f52ff61829864` |
| M09 | `3197bbcf7a48ede2dea0a06a20ea62e8367c552cc39d671a96d625d860287c85` |
| M10 | `dcc8e4c1039feec32ef956bba05b94271ad7350658358880df097cafc9407557` |
| M12 | `c30871c5e11f9792eb8353158b94e27335b4d14a7c65ee5ac28b1c0f99a91431` |

The full first native composition retains three failures, including a causal
M09 production regression: the new continuous east landing guard blocks the
first Enforcer's committed charge at `z=-31`. Retain that installed source
`01471a5f...` as exact intermediate history. The bounded candidate splits only
that guard around a visible three-metre opening and has source identity
`3197bbcf7a48ede2dea0a06a20ea62e8367c552cc39d671a96d625d860287c85`.
It now passes the actual causal seven-case mission gate, ten candidate and ten
canonical stair checks and source-view review and is installed. Retain the same
actual windup, locked charge,
dodge, lethal descent, single charge-fall count and zero player frags in the
original and corrected worlds, with the continuous guard as the refusing
control. Keep stair walking and the protected edges outside the opening.

Both original `4f45d0c5...` and exact intermediate `01471a5f...` may upgrade to
the accepted final source. The intermediate first existed at save version 15;
historical versions cannot claim it. Keep completed and closed intermediate
history on its actual hash, archive exact bytes, and rerun actual owned launch,
promotion and continue checks for both predecessors. No general hash allowance
or document version increment is required.

Keep save version 15 and campaign rules revision 4. Geometry does not change the
document's fields or difficulty timing. The planned Rocket version 16 remains
separate. Historical save versions still pass their original strict shapes,
equipment guards and exact historical rules before their existing upgrade.

## Explicit reader and durable replacement

Add a small content-upgrade module beside `mission/run_file/store.rs`. It maps
only a registered mission, exact predecessor and exact successor pair. Inspect
the source identity before ordinary historical decoding so an old map hash is
validated against its actual predecessor, rather than rejected prematurely or
treated as the successor. Validate the entire decoded run, including its stage,
status, outcomes, finite inventory, historical shape and continues. A predecessor
hash claiming another mission, malformed document, unknown hash or changed
successor remains incompatible. Do not broaden `RunDocument::validate` into a
general hash allowlist.

For `MissionEntry` and `PendingContinue`, normalize only the content identity to
the registered successor after that validation. Preserve the run ID, body,
rules, HP, armor, selected weapon, exact finite pools and devices, personal
claims, attempt status, prior outcomes and all continue counters. No pickup,
healing, refill, award or new outcome is added. A pending continue remains
pending and still spends its normal continue. Failed and abandoned runs remain
closed; a content upgrade cannot revive either.

Completed `AwaitingMission` history keeps its actual predecessor content hash.
It must never become a claim that the new stairs were completed. Preserve its
actual exit equipment and outcome values. The normal mission-promotion path may
consume that validated predecessor history, archive its exact bytes, and create
the next mission's current entry. Episode refill occurs only at the existing
promotion edge. Closed failed or abandoned predecessor documents likewise retain
their original content identity and status until explicit New Run.

An unlocked preview is read-only. Under the existing writer lock, re-read the
source and use the existing content-addressed exact-byte archive, fsync and
atomic replacement. Extend upgrade detection to include the exact entry content
case, including same-version 15 documents. Preserve whitespace and unknown
original byte layout in the archive, rather than reserializing a backup. A
failure before replacement leaves the original at `run.json`; retry reuses the
same verified archive. Refuse a changed source or conflicting archive. New Run
retains its existing separate exact-byte archive behavior.

Disk `SavedEntry` stores HP, armor and equipment, not position or facing. A new
process therefore constructs a fresh ordinary spawn and retry anchor from the
validated successor map. Prove that spawn and its initial routes clear the new
walls, at full standing height. In-process retry also stores position and facing;
never replace its map or anchor beneath a living process. No live hot upgrade,
teleport or unsupported old-world resume is introduced.

## Meaningful verification

- Hash the retained predecessor fixtures and strict-load their actual worlds.
  Strict-load each successor and its mission collision variants before enabling
  the corresponding exact upgrade pair.
- Exercise actual predecessor M08, M09, M10 and M12 entry documents through unlocked
  preview, locked load, byte archive and replacement. Retain rules and every
  finite count, selected weapon, HP, armor, body, prior rescue receipt and
  continue counter. Include each existing supported historical document shape
  that can reach the stage, plus current version 15.
- Prove a pending continue stays pending, restores the successor's safe entry
  through the real continue path, spends one continue, and does not replay an
  episode refill. Failed and abandoned controls remain unplayable.
- Preserve completed predecessor hash and actual outcomes through ordinary
  promotion and retry in the next mission. Do not relabel an old completion as
  new-map evidence or derive a rescue from presence alone.
- Reject a one-byte map alteration, unknown predecessor, old hash attached to
  another stage, malformed inventory, forged historical rules, unsafe successor
  entry or changed successor registration. Existing historical Arc rejection
  remains strict.
- Inject a pre-replace failure and source/archive conflicts under the existing
  store test seam. Assert exact source bytes survive and repeated migration is
  idempotent. Preview alone never writes.
- Run the owning focused save and real-entry tests through the coordinated
  native compiler. The map owner proves ordinary stair walking, finite combat
  and inspected eye-height descent separately. Compose full gates only after
  both sources freeze.

The save owner edits the content reader, upgrade detection, historical completion
validation, store tests and minimal local launch integration. The map owner owns
the new authoritative architecture and route evidence. No dependency, paid call,
schema expansion, combat adjustment or acceptance-threshold change is required.
Unknown geometry remains refused by strict content validation and its bytes
remain recoverable.

## Local reader verification

The initial six focused geometry checks pass, followed by all 65 local-run
store checks. An expanded seven-case run passes with the revised final M08/M09
candidate identities, and the corrected full local-child suite passes all 18
cases. Server all-target strict clippy also passes for that reader snapshot.
The new cases strict-load the four exact predecessor worlds,
preserve every current entry and pending-continue field except the content
identity, exercise all historical document versions that can actually reach
these missions (M08 v9-v14, M09 v10-v14 and M10 v13-v14), keep completed and
closed history on its original world, and prove exact archival and injected
replacement/conflict recovery. M12 first exists in version 15.

The first focused run failed a test-fixture assumption that zero remote mines
must always be serialized. The corrected fixture verifies the actual zero
count and removes the field only when present, preserving strict historical
absence. The following focused and full store runs pass. Logs are retained in
`.agents/stair-architecture-20261008/save-geometry-focused-second.log` and
`save-store-composed-first.log`.

The expanded log is `save-geometry-expanded-third.log`; actual owned-child
checks are in `local-child-after-save-reader-second.log`. These remain explicit
pre-install source snapshots. Native successor route checks and standing-camera
preview acceptance belong to the stair plan. The installed-source launch and
continue checks below supersede those pre-install snapshots for current behavior.

These checks establish the reader and durable replacement behavior. Canonical
successor installation, actual successor entry/continue walking and real local
runner launch now pass. The final installed-source full store suite passes 71
cases, including all 12 geometry cases and both M09 predecessor identities,
followed by all 18 owned-child integration cases and all seven canonical M09
actor cases. The [local receipt](../evidence/campaign-geometry-upgrades-20261008.md)
records source bindings and retained fixture failures. Inspected ordinary
interior descents and final composed checks remain the stair and integration
owners' gates.

The final default-concurrency native workspace, after the separately documented
Conquest test correction, passes 1,952 cases with zero failures, four existing
ignored cases and zero filtered tests. Final strict workspace lint and
formatting pass. Unfiltered coverage also passes all 1,952 cases with two
concurrent tests and 93.29% lines above the unchanged 90% threshold. No test,
existing ignore or actual runner/wire deadline changes. Regions are 92.79% and
functions 91.52%. The retained release is unchanged.

The first corrected store run retains a first-M08 owned-runner timeout before
the run lock or archive existed. Added test-only case, phase and elapsed
diagnostics keep the same 30-second individual-runner deadline. The complete
following 71-case run passes, with first M08 launch taking 9.3976 seconds and
the slowest observed individual launch 13.7726 seconds. No timing bound,
production startup path or save acceptance guard was relaxed.

The complete renewed native workspace run passes 1,951 cases with zero failures
and four existing ignored cases, using the ordinary default test concurrency.
The final release workspace builds successfully. Instrumented coverage remains
separate: its first attempt stops with two readiness timeouts and one unexpected
wire command. The retained diagnostic phases support a complete coverage rerun
with two concurrent tests, preserving every test, existing ignore, actual
deadline and the 90% line threshold. The later complete coverage and strict lint
pass as bound above; client and inspected presentation remain separate gates.
