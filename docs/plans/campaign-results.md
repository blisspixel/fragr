# Campaign completion results

**Status:** implemented, 2026-10-04. Based on main `a8611d04`.

## Goal and scope

Show a bounded end-of-level tally after actual authoritative mission departure:
kills, distinct secrets, deaths and elapsed time. Reuse private participant
records rather than reconstructing outcomes from rendered actors or shots.
Label the successful attempt separately from total effort across retries.
Show it after the existing departure story, before the existing onward prompt.
It is presentation only and sends no campaign control message.

Par comparisons remain deferred. Mission briefs contain proposed runner times,
but the authored runtime contract has no reviewed par field. Do not invent or
silently promote those proposals. Full fresh-player and difficulty acceptance,
durable campaign service history, party aggregate scoring and map changes are
outside this increment. No rim-health relocation belongs here.

## Existing seams and architecture impact

`statistics.rs` owns resolved counters and private `PlayerRecord` generation.
`MissionRun` owns readiness, attempts and departure. Add one readiness timestamp
to its existing lifecycle; use the terminal departure timestamp to freeze
elapsed time, including time spent dead within the attempt, excluding the
opening briefing and later story or results viewing. Accepted retry starts a
fresh attempt clock. No run-file version, retry authority or difficulty change.

`PlayerRecord` remains the strict client validation and history boundary. New
`campaign_result.gd` validates a completed mission record against the current
departed mission and selects its real attempt and total counts. New
`campaign_results.gd` presents that boundary using the shared menu theme.
GameManager coordinates either record/state arrival order, one tally per
session/round/attempt, departure story completion and input release before the
existing onward prompt. Missing older-server timing must never fabricate time
or block departure. Invalid records remain rejected by the owning boundary.

## Protocol and compatibility

Add optional `mission_elapsed_ticks` only to completed mission records. It is
an exact nonnegative JSON integer, bounded by the server tick, and immutable
once terminal. Existing version 1 records and their exact serialized shape
remain valid when this field is absent. Existing ticks-per-second stays 20.
Update protocol documentation and both validators. Current gameplay capability
becomes 33; mission admission requirements stay unchanged. The existing private
unicast seam strips the new field for recipients below 33, preserving their
strict old record shape. Agents keep their existing mission control door.

## Verification and success criteria

- Server tests prove readiness exclusion, exact elapsed ticks, frozen completion,
  accepted retry restart, late readiness, noncompletion omission and genuine
  resolved kill/secret/death counters.
- Strict Rust and GDScript validation rejects malformed/future timing, timing on
  active or arena records and terminal rewrites; historical records still work.
- Client tests prove real completed-only results, independent attempt/total
  counts, no fabricated par, either state order, duplicate suppression, story
  sequencing, held-input barrier, retry and teardown.
- Run focused checks, workspace fmt/clippy/tests and the full existing client
  checker with matching fresh isolated native server. Inspect a rendered actual
  completion tally in a parent-coordinated GPU slot. Retain logs under `.agents`.
- Record exact commands, results and limitations here before handoff. Parent
  owns shared roadmap/index/release integration; do not publish this branch.

## Spend and operational gates

$0. No paid services or new runtime/dependency. Use an isolated native target
and owned local processes/run files. Never touch the root release executable,
secrets or another renderer/process. Commit only scoped changes as Nick Seal.

## Local evidence and remaining gates

The implementation selects strict completed records, shows attempt and total
columns, and presents elapsed time once after the departure story. The existing
onward prompt waits for tally dismissal and release of all held controls.
Historical missing timing displays unavailable. Capability 33 adds optional
record timing; M07 still requires 32 and M08 still requires 31.

Logs live under `.agents/campaign-results-20261004/.agents`:

- `results-elapsed2.log`: three focused server tests pass, including exact
  readiness/departure timing, terminal immutability, malformed values and
  byte-identical legacy unicast delivery. The final validator also refuses a
  present null. `results-party-clock.log` proves partial readiness and late
  joins cannot start or restart the clock. `results-retry-clock.log` proves
  accepted continue restarts it and refused repeat cannot move it.
- `results-workspace-final.log`: full workspace passes, including 874 server
  tests and three existing ignored tests. The later party-clock test passes
  separately. Warning-denied workspace/all-target Clippy passes in
  `results-clippy-pass.log`, after fixing three unnecessary Copy clones in
  the new test. Workspace format and diff whitespace checks pass.
- `results-old-reader.log`: the actual `a8611d04` GDScript validator rejects
  the new field and accepts its stripped legacy shape. Its retained private
  source changes only the class name to avoid a global-class collision.
- `results-client-lifecycle2.log`: strict completion, actual viewport input
  consumption, held-input barriers, retry totals, gun/explosive kills, either
  wire order, story precedence, duplicate suppression and live retirement
  pass cleanly. `results-onward-copy.log` retains the existing copy/onward
  assertions and adds a guard against bypassing an unpresented result.
- `results-live1.log` and `results-live-1/manifest.json`: a genuinely owned
  Standard M01 child passes the unchanged 14-state ordinary-input records
  route, combat probes and departure. Its actual record has 20 kills, zero
  deaths, zero secrets and 2,745 elapsed ticks (2:17). The tally matches and
  native save retains pending M02 carry. Renderer exits zero, clean logs,
  owned child cleaned up. Accurate-aim authoring evidence is not fresh-player
  or difficulty acceptance.
- The initial screenshot exposed missing panel fill and an unanchored
  backdrop. An opaque panel and full-viewport dim scrim fix readability.
  `results-replay.log` and `results-live-1/results-corrected-replay.png` show
  the inspected correction using the exact retained completion record and
  captured world background. This is a recorded-completion presentation
  replay, not a second playthrough.

Combined checks use exact temporary audio dependencies from `d4e4fa01`, whose
blobs are recorded in `audio-dependency-blobs.txt`. Those module/assets/harness
files belong to the separate feedback change and are not committed here.
GameManager owns coordinated setup, map, shot and reset hooks, suppressing
feedback behind loading, briefing, story and results while retaining deliberate
final resolved damage. Combined import and both focused harnesses pass. This
branch requires the audio source integration to parse; these are combined local
checks, not standalone branch proof.

The first full combined checker found an older onward test's synthetic network
object lacked the required completion record. Its fixture now uses the shared
strict record without removing assertions. A subsequent repeat exposed an
out-of-tree viewport assumption in the coordinated feedback hook and a result
test's exact-frame retirement assumption. The hook now suppresses feedback with
no viewport, and the test bounds actual queued retirement across frame
boundaries. Both focused harnesses pass without removing their assertions.
Keep the failed logs as diagnostics.

`results-full-godot-final.log` is the clean full combined acceptance: exit zero,
238 script parses, 110 harness PASS markers and `Godot checks: PASS`, without
error lines. This includes the exact temporary audio dependency described above.
The scoped code checkpoints are `083671bb` and `74be01f2`. Parent owns combined
integration CI, shared capability docs and publication. Real authored par,
cross-process statistics, party aggregate results and fresh-player/difficulty
review remain open.
