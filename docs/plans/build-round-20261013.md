# October 13 development round

Status: **implemented**. This is a bounded composition under the existing Full build order, not a second campaign or feature queue. Local and GitHub verification own delivery; generated candidates retain their separate acceptance gates.

## Goal and ownership

Nick authorized parallel asset, audio, level and core-game work, followed by GitHub review and consolidation to one clean main with passing CI before another round. Preserve the campaign contract, lore, art direction and server authority.

The campaign lane owns a bounded M13 foundation increment: real terminal use, active participant eligibility, encounter resets and supported freight-lift behavior. Mission identity, save promotion, controller and client connection remain the next larger increment. The audio lane prepares a small missing-effects batch and one instrumental candidate. The art lane improves live credit accounting and prepares a bounded useful model and texture increment. Integration owns shared documentation, Linux renderer readiness, the outstanding full-tour effects failure, combined verification and GitHub delivery. Each lane records its exact scope and evidence in its own plan before implementation. No duplicate changes to shared files without coordination.

## API and spend

The native Meshy balance check authenticated with 1,900 available credits. The absent historical local ledger does not clear its retained 15-credit uncertain hold. Higgsfield authenticated against a free estimate; its reported $4.12 plus $50 deposit remains unverified by the native checker. ElevenLabs authenticated as active Pro with 1,161,134 credits remaining of 1,185,132, resetting at Unix 1793976680. These readings precede production and must be refreshed before paid stages.

Use only native spritegen/audiogen. Serialize paid stages, retain receipts and download sources. Root reviews each exact spec, current price, live allowance and finite cap before submission. Initial round ceilings are 75 existing Meshy credits, $2 of existing Higgsfield balance, and 12,000 included ElevenLabs credits; these are maxima, not spending targets. Preserve each tool's per-run ceilings and unknown historical reservations. No automatic retries of uncertain submissions, no cash purchase, overage, top-up, cloud deployment or paid runtime. Music distribution must be supported by current terms before committing a candidate to a public repository.

## Verification and acceptance

Run focused native tests and client harnesses per lane. Validate new sources in Godot, inspect actual geometry and lighting, and listen to audio before runtime selection. Source production is not asset acceptance. M13 must preserve prior runs and refuse unbuilt M14; its plan owns ordinary-action route, carry and retry requirements.

Integration requires formatting, locked workspace lint/tests/release build, coverage at the existing floor, relevant playtests, complete client checks and an inspected published tour for visible changes. Characterize the existing FpMuzzle and ShotEffects tour failures without weakening assertions. CI includes portability, packaging and server checks. Use passing reviewed-head PRs and verify main after squash integration. Release only after applicable visual and package gates, then close the packaged-adapter issue against delivered archives.

Human fun, fresh-player understanding, two-machine LAN, final art and full-campaign completion remain separate gates. Record actual commands, failures, costs, selected outputs and remaining work before closing this round.

## Implemented slices and retained limits

The [foundry foundation](m13-round-20261013.md) uses the registered terminal's
reach, facing and sight checks, excludes inactive bodies, resets standalone gate
facts with the party, and preserves whole-step lift obstruction while ignoring
unrelated overlapping bystanders. Ordinary movement tests board and ride the
actual successor deck. M13 is still a development map, not a connected mission.

The [audio slice](audio-round-20261013.md) restores spatial Rocket launch feedback
from accepted projectile facts and suppresses predicted-local duplicates. Five
private candidates consumed 981 included credits by stable account delta,
leaving 1,160,153 and zero current overage. Raw effects touch full scale and one
has DC offset; none is selected. Listening and public raw-file distribution
acceptance remain open.

The [art slice](art-round-20261013.md) retains a four-sided inspected ladle source
with 10,605 actual triangles and two small surface comparisons outside runtime
imports. One model consumed 30 credits. Live balance is 1,870, with the historical
15-credit hold leaving 1,855 usable. Three image requests retain $0.185 in
estimated reservations, not itemized billing proof. No new cash, rig, revision,
top-up or overage was requested. Native account holds follow the canonical
credential location across output and working directories.

The first Linux full tour reproduced the missing muzzle and impact strips.
First-person shot animation previously consumed the preceding slow frame's delta
before drawing its new fire frame. The presenter now keeps that first draw, and
the tour saves the witnessed effect frame without extra settling draws. A second
tour passed all three strips but exposed a pawn death during still framing.
The final capture path reacquires the living requested pose before freezing and
checks the saved frame's facts. Failed evidence remains under
`.agents/round-20261013/`; assertions and timeouts remain enforced.

The complete Godot 4.7.2 headless checker
(361 scripts, 172 harnesses) and its ten verifier self-test scenarios passed on
Linux. The final 32-state tour passed, published 14 stills and passed contact-sheet
and effect-strip inspection. Flechette muzzle frames, the blue Rail impact and
clustered Scatter impacts are visible; menus and bodies retain the existing
pixel direction. Software-rendered evidence uses Mesa llvmpipe and does not
establish hardware performance. Workspace lint, the locked release build and
dependency licenses, bans and sources passed. Unfiltered workspace line coverage
passed at 92.91 percent, above the unchanged 90 percent floor, including the new
Rocket and account-hold regressions. All eight required network scenarios and
route checks, the seven-map mixed roster and the 120-second soak passed. The
existing roster limits still admit the recorded map 4, 5 and 6 spawn-death
warnings; those are retained, not treated as proof that spawn quality is finished.
The 16-bot, 1,200-tick release benchmark passed determinism and budget checks with
0.557 ms p99 and no ticks over budget. It ran alongside coverage, has no connected
clients, and establishes neither renderer performance nor network capacity.

Measurements used Linux x86-64 on an AMD Ryzen 7 7840U with 16 logical CPUs,
Rust 1.97.1 release builds and the existing seed 42 benchmark. These are bounded
local CPU and socket measurements, not isolated hardware baselines.

| Check | Workload | Result | Evidence |
| --- | --- | --- | --- |
| Deterministic CPU gate | 16 rule bots, 1,200 ticks, no clients; coverage running concurrently | p99 0.557 ms, max 0.935 ms, zero over-budget ticks, deterministic | `.agents/round-20261013/benchmark.log` |
| Local socket soak | 4 agents, 4 bots, 2 spectators, map rotation, 120 seconds; other checks running concurrently | 20.00 Hz, p99 1.11 ms, max 4.35 ms, RSS 60.2 to 61.7 MiB, nine samples, no disconnects | `.agents/round-20261013/playtests/soak.ndjson` |

One unbounded-concurrency workspace run hit an existing 30-second owned-server
startup deadline on a historical closed M08 save. No compatibility assertion
failed. The same test passed in the full coverage run and in a focused rerun
(17.82 seconds for all ten cases). The original failure remains in
`tests-final.log`; the separate two-thread workspace rerun passed, retaining the
same deadline and every assertion. No production or test timeout was relaxed.

This round prepares v0.82.1. Applicable reviewed-head PR checks, manual desktop
package checks and main CI must pass before tagging. Issue 391 stays open until
the tagged packages actually contain the adapter. No further production round
starts before that clean-main checkpoint.

[PR 401](https://github.com/blisspixel/fragr/pull/401) owns this composition;
its [checks](https://github.com/blisspixel/fragr/pull/401/checks) and the
[release workflow](https://github.com/blisspixel/fragr/actions/workflows/release.yml)
retain the delivery verdicts. Earlier local failures remain distinct from those
reviewed-head results.
