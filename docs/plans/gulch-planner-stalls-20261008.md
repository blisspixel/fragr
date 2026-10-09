# Reclamation Gulch planner stalls

Status: **implemented** locally, 2026-10-08. Owns [issue 336](https://github.com/blisspixel/fragr/issues/336). Integration remains separate.

## Goal and baseline

Resolve the intermittent twelve-client mixed-roster stall on multiplayer map 5 without relaxing the five-second threshold. Retrieve the original failed run and retained reports, inspect the two recorded east-ridge positions, and distinguish the historical evidence from a reproduced current failure. The existing [static-corner recovery](static-corner-recovery.md) shipped a bounded recovery but explicitly retained the original episode's attribution as open.

The original [run 37116113333](https://github.com/blisspixel/fragr/actions/runs/37116113333) used commit `aa8b1a60937afa3c367645ae266c99a93d91034a` and seed 42. It reported planner-12 at (73.3, 21.4) and planner-6 at (54.6, 37.4). Reports and failed-job logs are retained under `.agents/open-issues-20261008/336/failed-run-artifacts/` and `failed-run.log`.

## Scope and architecture

Use the shared `navigation/controller.rs` route memory and local movement/contact forecasts. Inspect the planner policy and mixed-roster observation in `tools/playtest` before selecting a correction. Preserve physical collision, supported movement, search budgets, resolved shot evidence, combat intent and ordinary human inputs. Prefer a deterministic actual-map failure and a shared controller fix over a map-specific escape rule. Add bounded diagnostic evidence if historical artifacts omit the facts needed for attribution.

No geometry, weapon balance, transport, dependency, movement mirror or paid-service changes are planned. No wire or public API change is expected. Other dirty development changes remain intact. Root owns shared plan index, roadmap and integration checks.

## Verification and success criteria

- Retrieve and inspect the original report, seeds, exact coordinates and existing recovery controls.
- Establish current focused controller and map 5 mixed-roster baselines.
- Prove any identified failure in a deterministic regression using authoritative integration and actual Gulch geometry, retaining a before/after receipt.
- Preserve clear movement, recovery expiry/reset/jump/drop behavior, search cadence and crowd/stair controls.
- Repeat the unchanged twelve-agent seed-42 roster and additional recorded seeds against the final binary. Keep every report and failure; the five-second threshold remains unchanged.
- Request independent review of consequential shared changes, resolve material findings, and record exact local checks and remaining uncertainty before changing status.

Passing repeated asynchronous socket runs does not by itself explain the original historical episode. Original and final evidence must retain their source and binary scopes.

## Spend and safety

All work is local and reversible at $0. No commits, push, publication, paid calls or cloud operations. Serialize release executable rebuilds with other owners. Diagnostic artifacts live in `.agents/open-issues-20261008/336/`; promote durable findings here and into focused tests.

## Progress

Original issue, failed-run metadata, job log and published playtest artifacts retrieved. Four current socket baselines, including two repetitions of the original seed, pass unchanged. These asynchronous runs do not deterministically replay participant identities or admission order.

### Cause and correction

The historical controller returned ordinary combat movement unchanged when no nearby body existed. The shipped static recovery added the needed movement/contact forecast, but its immobility counter still required strictly adjacent snapshot ticks. The server's bounded outbound slot can replace ordinary movement snapshots (`net/outbound.rs` and its actual-moving-world regression). A wire controller observing every other authoritative tick therefore never accumulated stationary evidence, even though the server kept applying its blocked input.

The new actual-map regression reproduces this remaining failure through `GameState` and `Navigator::steer_snapshot`, with ordinary input held between observations. It explicitly starts an active round, uses a stationary unopposed target and high test HP to keep the movement fixture alive, and preserves target, fire, pitch, weapon and input sequence intent. It is a supported movement fixture, not normal-health combat balance evidence. Early fixture work incorrectly counted warmup and required an unchanged ground height instead of legal stair support; those fixture errors were corrected before recording the accepted counterfactual.

The shared counter now tolerates at most three intervening ticks while still requiring six distinct observed stationary positions. Duplicate observations add no evidence; reversed time and longer gaps start over. Existing movement/contact forecasts, finite recovery lease, collision, search budgets and the harness's five-second threshold are unchanged. Independent review requested an idle-input witness; it now proves that clearing an active escape and observing idle input at a coalesced cadence never creates movement.

The original CI artifact lacks height, target, action and delivery history. The newly reproduced failure is a concrete remaining cause at the recorded geometry, not a claim to have reconstructed every fact in that historical episode.

### Actual-map movement measurements

Each case runs the same authoritative active-round fixture for 120 ticks. The unmodified control was stopped after its first reproduced failing cadence; unmeasured counterfactual cells remain explicit.

| Start X, Z | Observation interval, ticks | Before: longest stationary, ticks | After: longest stationary, ticks | After: net horizontal progress, m |
|---|---:|---:|---:|---:|
| 73.28353, 21.406975 | 1 | 7 | 7 | 23.431 |
| 73.28353, 21.406975 | 2 | 120, no displacement | 14 | 21.690 |
| 73.28353, 21.406975 | 4 | Not separately measured | 28 | 18.213 |
| 54.56577, 37.4444 | 1 | Existing shipped manual-integration control only | 7 | 11.835 |
| 54.56577, 37.4444 | 2 | Not separately measured | 14 | 10.343 |
| 54.56577, 37.4444 | 4 | Not separately measured | 28 | 7.690 |

Accepted raw receipts: `coalesced-before.log`, `controller-after.log` and the final `navigation-after.log` under the private artifact directory. The final navigation run includes the added idle witness and every existing controller control.

### Repeated socket evidence

The baseline harness is SHA-256 `726da136080c69934e1db6f1e4cbd8dc8b1f5131cb7ab3933c68e6cd7c348452`. The corrected harness is SHA-256 `ba5678d41df41a724fcc4f689a0306e7c0ddf3a07cb113ca8b45535a33af0204`, built with `cargo build -p fragr-playtest --release --locked`. Each run uses the compiled harness's own server library over actual loopback sockets. These are native local functional measurements, not physical LAN, renderer, population-capacity or human-acceptance evidence.

Common command arguments remain exactly `--map 5 --agents 12 --tiers reflex,planner --rounds 1 --frag-limit 8 --time-limit-seconds 60 --max-seconds 75 --assert`, with the recorded `--seed` and separate `--report` paths. Every report and log is retained; no failed candidate socket run was discarded.

| Phase and report suffix | Seed | Rounds | Frags | Longest observed stall, s | Opening deaths | Respawn-window deaths | Assertions |
|---|---:|---:|---:|---:|---:|---:|---|
| Baseline `map5-seed42` | 42 | 1 | 44 | 0.40 | 0 | 1 | Pass |
| Baseline `repeat-map5-seed42` | 42 | 1 | 50 | 0.55 | 0 | 1 | Pass |
| Baseline `map5-seed19` | 19 | 1 | 46 | 0.55 | 0 | 0 | Pass |
| Baseline `map5-seed67` | 67 | 1 | 36 | 0.45 | 0 | 1 | Pass |
| Final `map5-seed42-a` | 42 | 1 | 38 | 0.40 | 0 | 1 | Pass |
| Final `map5-seed42-b` | 42 | 1 | 43 | 0.40 | 0 | 0 | Pass |
| Final `map5-seed42-c` | 42 | 1 | 47 | 0.35 | 0 | 0 | Pass |
| Final `map5-seed19` | 19 | 1 | 34 | 0.55 | 0 | 0 | Pass |
| Final `map5-seed67` | 67 | 1 | 35 | 0.55 | 0 | 1 | Pass |
| Final `map5-seed99` | 99 | 1 | 48 | 0.45 | 0 | 0 | Pass |

Final owning gates pass: all 27 navigation tests, all 12 bounded outbound-delivery tests and all 79 harness library tests. Formatting, whitespace and prohibited-prose checks pass. Independent review found no material runtime defect and its requested idle witness is included in the final navigation result. Raw command logs and report hashes are retained in `network-receipt.json` and `verification-receipt.json` under the private artifact directory.

No release executable remains running from this lane. Shared workspace/client/coverage and release composition belong to the current integration checkpoint, not these focused results. No hosted CI, physical LAN or unsteered human acceptance was performed. The recorded historical evidence limits remain intact.
