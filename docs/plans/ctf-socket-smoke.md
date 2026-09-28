# Sector 9 socket smoke gate

**Status:** implemented, 2026-09-28, [draft #295](https://github.com/blisspixel/fragr/pull/295). Stacked after [carry episode evidence](ctf-carry-episodes.md). Exact-head CI passed; the human and spectator gate remains open.

## Goal and failure evidence

The [exact-head CI run](https://github.com/blisspixel/fragr/actions/runs/36423976452/job/108933276723) observed four mixed external agents for one 181.9-second Sector 9 round. They fought 12 frags but took no flag, so the existing `--assert` check correctly reported no pickups and no captures. The earlier passing four-agent match used the same command shape. A simulation seed does not fix socket scheduling, process-local IDs or combat choices. This CI failure says the match outcome is too variable to serve as a capture contract, not that the observer changed game rules.

## Contract and approach

- Keep capture as a required, server-authored end-to-end gate. Drive a controlled fighter over a real loopback WebSocket, through normal server movement and flag rules, with zero opponents. Assert the joined fighter's flag take, carried snapshot, capture event, final capture score and capture-limit round end. Keep the existing 5-second server-bind and 205-second overall wall bounds; the route has no separate movement-progress timeout. No direct position mutation, fake server event or lowered CTF score check.
- Keep a contested four-agent socket match in CI for combat, two-side roster, round completion, a typed authoritative flag snapshot and no team kills. It reports captures and carries for trend inspection but does not require a pickup or capture in every random match. Retain the existing general frustration and rule assertions. The capture requirement moves to the controlled gate; it is not removed from the suite.
- Reuse `fragr-playtest` server, protocol, observer and navigation seams. The controlled gate must be a distinct explicit CLI mode so ordinary `--assert` semantics and existing report JSON stay stable. Avoid a second protocol or a new scripting runtime.

## Verification and limits

First establish a baseline with the present socket harness and inspect the CI report. Write deterministic tests for the controlled gate's acceptance and failure cases, then run it repeatedly on Windows and under the Linux CI command. Run formatting, workspace Clippy, tests, unfiltered 90 percent coverage, and the relevant live socket gates. Record exact command, result and limits here. An uncontested capture proves transport, action, server authority, event and observer wiring. It does not prove contested pacing, human clarity or fun; keep the five-seed carry sample and human/spectator gate open.

External spend is $0. No asset service, cloud resource or Terraform apply.

## Local implementation evidence, 2026-09-28

The existing one-agent Reflex baseline, `--agents 1 --rounds 1 --mode ctf --map 4 --tiers reflex --capture-limit 1 --time-limit-seconds 100 --max-seconds 110 --seed 42`, reached the 100-second clock with zero flag takes. That policy chooses the only fighter as its own defender and cannot serve as the controlled objective proof.

The new `--ctf-route-smoke` uses one route probe and no rule bots. Its fixed configuration is Sector 9, one capture to end, seed 42 and a 180-second match clock. It rejects conflicting match and soak options rather than silently overriding them; `--report` remains configurable. The probe receives normal snapshots, selects the enemy stand then its home stand, and sends actions through the existing WebSocket client task and shared navigator. The server owns all movement and flag transitions. The gate checks the same player ID on take and capture, a carried snapshot, the capture event's side score, the final side score, and a matching capture-limit round end. A missing or mismatched fact fails. The existing generic CTF `--assert` still requires takes and captures.

The contested `--ctf-contested --assert` gate retains common frustration and team-rule checks and additionally requires at least one frag, a typed authoritative flag snapshot and a final capture score. It accepts a scoreless contested match as a valid combat and replication sample because the separate route gate always requires a capture. CI runs both commands and uploads both reports.

| Run | Agents | Match s | Frags | Takes | Captures | Final score Union:Coalition | Exit |
|---|---:|---:|---:|---:|---:|---:|---:|
| Controlled route 1 | 1 | 61.0 | 0 | 1 | 1 | 0:1 | 0 |
| Controlled route 2 | 1 | 61.0 | 0 | 1 | 1 | 0:1 | 0 |
| Controlled route 3 | 1 | 61.0 | 0 | 1 | 1 | 0:1 | 0 |
| Contested match | 4 | 60.8 | 4 | 1 | 1 | 0:1 | 0 |

Each controlled run recorded 29.0 carrier seconds and ended with `Capture limit reached`. The third also passed after the gate began checking the capture event's side score. The contested run had two fighters per side, no team kills and a server-owned capture. All four used the debug harness on the Windows AMD Ryzen 7 7840U host. Exact controlled command: `cargo run -p fragr-playtest --locked -- --ctf-route-smoke --report .agents/playtest/ctf-route-NAME.json`, where NAME was `first`, `second` or `third`. Exact contested command: `cargo run -p fragr-playtest --locked -- --agents 4 --rounds 1 --mode ctf --map 4 --tiers reflex,planner --capture-limit 1 --time-limit-seconds 180 --max-seconds 240 --assert --ctf-contested --report .agents/playtest/ctf-contested-local.json`. JSON reports are ignored local diagnostics. No paid call was made.

Focused pure tests exercise a complete take, carried snapshot, capture and score chain; a mismatched fighter ID, missing carried frame and wrong event/final score fail. The contested test accepts a scoreless match with combat and a typed flag snapshot, then rejects absent combat, absent flag state and a missing side. CLI tests keep the two gate configurations distinct and reject conflicting route options. `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, `cargo test --workspace --locked` and `git diff --check` passed locally. The workspace test included 72 passing playtest library tests, five playtest CLI tests and 537 passing server library tests with two ignored. `cargo llvm-cov --workspace --locked --fail-under-lines 90` passed locally at 93.56 percent unfiltered workspace line coverage (60,250 lines, 3,882 missed).

The [Linux exact-head CI run](https://github.com/blisspixel/fragr/actions/runs/36429123173) passed all six jobs on `74578d4`. Its `test` job passed both new socket gates, the mixed-client roster, unfiltered coverage and release build. The separate Godot, soak, audit, Windows and macOS jobs also passed. A Godot visual tour was not relevant to this observer and CI-gate-only patch. Human and spectator CTF clarity, contested pacing and fun remain open product gates.
