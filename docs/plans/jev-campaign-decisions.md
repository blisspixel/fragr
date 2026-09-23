# Campaign-aware decision brain

Status: **in flight**.

## Goal

Make the existing decision-brain agent useful and measurable in Recall Notice
before spending on a Jev trial. Its paid questions must describe the actual
mission stakes and carried equipment. The local controller must pursue the
server-owned objective when an occluded guard is not a current fight. A run
summary must report the authoritative mission outcome, not infer success from
frags or elapsed time.

## Scope and seams

Keep one action channel and the existing MissionClient, inventory controller,
navigation budget, provider budget gate, and spend ledger. Choose arena or
campaign questions from validated MapInfo and private loadout state. Include
the current phase, attempt, limited continues, and usable equipment in the
decision state. Use short atomic questions with the same typed answer contract.
Make only a visible, reachable hostile a combat priority in campaign control;
otherwise let MissionClient walk toward its current approach and use prompt.

Do not add a combat-tick provider call, a second mission door, model-specific
game rules, new wire fields, paid test calls, or a different runtime language.
Arena play and local-rule fallback must retain their current behavior.

## Verification

- Unit tests for arena and campaign question wording, carried-weapon choices,
  and decision state from validated mission/loadout messages.
- A deterministic controller test with a living but occluded guard must walk
  toward the record. A visible nearby guard must still receive combat priority.
- A live local-rule M01 matrix over fixed seeds and campaign difficulties must
  report the server's phase, run status, attempt, and remaining continues.
  Record survival, stalls, fallback decisions, and first-person observations.
- Preserve paid refusal, pending reservation, and cap tests with fake
  transports. Run full Rust/Godot checks and mixed arena playtests before PR.

Success is an interpretable free campaign clear or a diagnosed, reproducible
failure with no fabricated completion, plus no arena regression.

## Local evidence, 2026-09-22

The brain now reads validated mission and loadout messages for its campaign
questions and receipt. A living guard behind cover no longer takes over the
mission route; a visible guard can. A deterministic test covers both cases.
The free-rule runs below used the authored M01 file, a solo campaign run, and
the same 20 Hz server. No provider call or ledger charge occurred.

| Difficulty | Seed | Limit | Latest server result | Observed course |
|---|---:|---:|---|---|
| Standard | 67 | 120 s | Complete, attempt 1, three continues | Departed around 104 s, no deaths, 40 HP at receipt. |
| Assisted | 19 | 150 s | Complete, attempt 1, three continues | Departed around 70 s, no deaths, 100 HP at receipt. |
| Severe | 42 | 150 s | Playing, attempt 4, no continues | Three deaths in sorting and stacks; still returning through the mission when the timer ended. This is not a clear or a terminal failure. |

The Severe run exposed an observability defect: campaign deaths did not emit
arena frag events, so the original JSON `deaths` count stayed at zero. The
brain now takes total deaths and kills from the validated participant record.
A focused test checks three deaths without frag events. The next live Severe
run must confirm the corrected receipt and inspect whether sorting's pressure
or the local route causes the repeated losses.

Focused brain tests and clippy passed. The full workspace test suite passed
after two attempts to rebuild `fragr-server.exe` collided with the live M01
processes on Windows; stopping those exact processes removed the lock. Godot,
coverage, benchmark, release build, and mixed playtest checks still need to
run on the integrated branch.

## Spend and later trial

Spend: $0 in this increment. No live provider calls in CI or local verification.
Only after the free matrix and watcher are credible: inspect the shared ledger,
reject unresolved reservations, check current Jev price and the key's lifetime
limit without automatic reset, then run a small OpenRouter trial with explicit
per-run and total caps below the user's $20 evaluation budget. No top-ups.
