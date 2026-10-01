# Responsive local brain and objective control

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Package and full workspace verification
passed locally; package artifact evidence remains separate. Recorded evidence belongs to the
[current development round](campaign-and-feel-buildout.md).
**Spend:** $0. Fake model transports and local matches only.

## Goal

Keep the reference fighter responsive while a slow decision model runs. Reduce
Ollama play to the stance question so one decision needs one scoring request.
Keep equipment and danger on local rules, and preserve full diagnostic `ask`.

## Scope and architecture

Use the existing brain loop, typed questions, local controller and shared
inventory seam. Refresh local plans while a model request is outstanding.
Reject successful answers from an earlier map, life, round or mission progress
state, or flag ownership. Report discarded answers separately from failures and
model decisions.
Preserve CTF objective routes through optional equipment resupply.

Extend the brain's existing CTF controller with one defender per side, and one
escort during an allied carry when the side has at least three compatible
controllers. The existing server-enforced external-agent-only stance chip
advertises compatible intent. Humans cannot publish it, and server rule bots
retain their own labels. Include the local controller's own known identity while
awaiting its first chip echo. This uses controller compatibility for coordination
only; faction and hostility still come from authoritative team and actor state.
Elect roles by participant identity within the server's authoritative team,
independent of snapshot order and callsigns. Dead fighters and carriers yield
their role. Carriers with a living compatible defender return home even when
their own flag is stolen; defenders recover it while attackers continue their
route. A lone carrier or carrier without a compatible living defender retains
its own dropped-flag recovery and stolen-flag interception. Escorts trail four
units behind the carrier and hold six units short of the scoring stand. A side
of two retains its existing noncarrier recovery policy. Only eligible teammates
share this role election. Combat must respect world visibility and preserve the
carrier's return route. This changes reference brain policy only, not server
rule bots or harness policy. Add focused role and transition tests.

No wire, dependencies, model contract, provider pins, server outcomes or client
presentation changes. Paid providers and self-hosted openjev keep their existing
question sets. Paid accounting continues even when an answer becomes obsolete.
No human feedback gate blocks this work. Automated evidence does not establish
human comprehension, balance or enjoyment.

Final independent review found that lone-carrier interception selected only a
walking goal and never aimed or fired at the thief. Add ordinary weapon-range
aim and fire against a visible hostile holding the carrier's own flag, while
keeping interception movement. Extract the shared actor geometry visibility
check so CTF does not inherit the campaign's separate twenty-unit engagement
policy. Keep campaign behavior and coordinated carrier home return unchanged.
Verify visible/in-range movement and fire, occlusion, range refusal and an
available compatible defender before the final source freeze.

## Verification

Focused question and delayed fake-model tests cover one-request play, fresh
fallback during inference and stale-answer rejection. Run all brain tests,
package Clippy with warnings denied, formatting and diff checks. The root round
of work owns full workspace verification. No external service is called.

## Success criteria

- Ollama play asks stance once; diagnostic ask retains all three questions.
- Slow inference does not freeze tactical intent or refresh obsolete plans.
- Map, life, round, mission, flag ownership and compatible-roster transitions
  invalidate earlier model success.
- CTF traversal retains a usable ranged weapon without optional supply detours.
- Failure backoff, malformed reply policy and paid budget enforcement remain.

## Evidence

`cargo test -p fragr-brain --locked` passed 114 library tests and ten binary
tests. `cargo clippy -p fragr-brain --all-targets --locked -- -D warnings`,
`cargo fmt -p fragr-brain -- --check` and `git diff --check` passed. Package logs
are under `.agents/brain-responsive-local/package-tests-final.log` and
`package-clippy-final.log`. The focused delayed-model socket fixture proves a new
low-health snapshot selects the health route while inference is held, and an
answer released after death and round transition is discarded without a
provider failure or charge. Epoch tests also cover map/life transitions and
compatible roster changes without treating ordinary movement, stance changes
or snapshot order as lifecycle changes. Diagnostic `ask` still passes its
warmup-plus-three-questions test.

The package binary suite initially found an older test fixture's PID-only
temporary path colliding with an unresolved ledger reservation from an earlier
process. Test paths now use existing UUID support; no accounting policy or
reservation was weakened. The corrected ten-test binary suite passed.

Eight CTF policy tests cover one defender per side, death yielding, team and
identity filtering, dropped and stolen flags, escort spacing, home-touch
clearance, compatible mixed rosters, lone-carrier recovery, visibility and
escort combat without chase. The live reference loop applies the same visibility
filter to inventory control and preserves active objectives through optional
resupply. Team telemetry excludes allied scores from the rival comparison.

### Six-controller socket smoke

The initial smoke ran `cargo test -p fragr-brain --lib ctf --locked -- --nocapture`, with its
output saved to `.agents/brain-responsive-local/ctf-socket-smoke.log`. Eight
tests passed, including `six_free_brains_play_ctf_on_real_sockets`. This uses
the actual `run_server` and six reference brains over ephemeral loopback
WebSockets on Arena Duel, plus a spectator. The action window starts only once
the spectator receives all six controller chips, three participants on each
authoritative side and both flags, then waits forty actual server ticks.

| Controller | Snapshots | Actions | Model calls | Charge |
|---|---:|---:|---:|---:|
| Roster-1 | 41 | 42 | 0 | $0 |
| Roster-2 | 41 | 42 | 0 | $0 |
| Roster-3 | 41 | 42 | 0 | $0 |
| Roster-4 | 41 | 42 | 0 | $0 |
| Roster-5 | 41 | 42 | 0 | $0 |
| Roster-6 | 41 | 42 | 0 | $0 |

This short smoke proves roster, flag replication and controller delivery. It
does not prove capture conversion, completed-round pacing, human balance, LAN
performance or a new hardware latency for the single-question model path.
No actual model, asset service or cloud resource was called.

A separate external-process smoke launcher was rejected before execution by
automatic command approval, and a subsequent Windows PTY attempt reported
CreateProcess access denied. The in-process runner above provides the socket
evidence without external-process cleanup. No external server was started by
either rejected command.

### Final interception correction

Independent review identified the non-firing lone-carrier interception and
triggered the correction described in scope. The reference controller now
targets the visible hostile thief by participant ID, advances toward it and
fires inside the selected weapon's normal range. CTF inventory filtering uses
actor visibility without the campaign engagement radius; campaign retains its
existing range policy. A hidden thief remains a navigation goal without a shot.
A living compatible defender still lets the carrier return home without
shooting. Both focused lone-carrier tests passed, including real navigator
movement, range refusal, occlusion, mixed-controller eligibility and defender
availability. Evidence: `.agents/brain-responsive-local/lone-carrier-tests.log`.
