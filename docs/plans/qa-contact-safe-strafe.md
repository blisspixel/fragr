# QA contact-safe strafe

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. Contact-aware eight-tick dodge forecasts preserve map movement and original refusal bounds.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

## Observed failure and separate reproducer

The material tour `.agents/qa/m06-port-textures-final/` failed after 18 captured states, exit 1. Its customs walk requested `[0,3,31.5]` but the actual player ended near `[0.102,0,31.447]`, below the raised crossing. All seven customs guards were killed by ordinary travel defense. No gallery was published from this failed tour. The exact deciding peer and tick history were not persisted.

A separate deterministic diagnostic loads the actual M06 solids and uses shared `MoveStep` and `ActorContact`. Feet `[-8,3,30.05]`, right strafe at yaw `PI/2`, and a living stationary peer at `[-8.9,3,30.65]` reproduce the missing safety check: the existing world-only forecast accepts the dodge, but resolved contact deflects it off the crossing to z29.978 and y2.67 by the third step. Receipt `.agents/moon-surfaces-20261001/contact-strafe-scan.log` is clean exit 0. This proves an omitted contact path consistent with the observed fall, not that these exact peer coordinates occurred in the rendered run.

## Scope

Own `client/scripts/qa_combat.gd`, its existing focused harness and this plan. Reuse `ActorContact.read_snapshot` for bounded validated bodies and `ActorContact.resolve` inside the existing eight-tick forecast. Current authoritative peer poses are speculative stationary obstacles only. Preserve the existing 0.2m drop refusal and 0.1m useful-displacement threshold, ordinary movement input and empty-peer behavior. An invalid or detached body boundary cannot request a dodge; ordinary aiming/fire remains separate.

No server code, world geometry, collision authority, movement math, mission gates, health, inventory, tick timing, target requirements or waypoint tolerance changes. Existing noncombat descent routes remain unchanged.

## Required evidence

Add actual-map tests distinguishing the old world-only acceptance and resolved contact fall from corrected refusal. Prove the opposite inward strafe, open ground, absent/dead peers and malformed/detached snapshot handling. Run focused pinned headless checks. After source freeze and root's GPU handback, repeat the unchanged 25-state M06 tour with clean engine shutdown and inspect actual materials/combat. Root runs the final whole checker and standard publication after this correction. Earlier failed and pre-correction receipts remain historical.

## Focused correction receipt

The existing harness first failed exactly the new contact refusal assertion while retaining the actual-map world-only and shared-contact checks: `.agents/moon-surfaces-20261001/contact-strafe-regression-before.log`, exit 1. The optional peer argument was present but ignored in that diagnostic state, so the failure isolates the missing contact behavior rather than a compile error.

The correction narrows the actual snapshot through `ActorContact.read_snapshot`, excludes the local body from peers and suppresses dodge movement if the local body is dead/detached or the boundary is malformed. Each of the same eight forecast steps resolves shared contact against current stationary peer poses. The original 0.2m drop gate and 0.1m displacement gate remain unchanged. Tests now pass for corrected refusal, the safe opposite direction, absent/dead peers, detached/dead local bodies and malformed coordinates. Existing open-ground and roof-edge checks also remain green.

Pinned focused harness: `.agents/moon-surfaces-20261001/contact-strafe-focused.log`, clean PASS and exit 0. Final unchanged-route gameplay and the whole client checker remain pending. No authored map bytes, server executable or normal noncombat movement code changed.

## Actual unchanged-route rerun

The material retry `.agents/qa/m06-port-textures-second-final/` passes all 25 states and all 21 named guards, with actual shared departure, wrapper exit 0 and zero engine/script errors. The raised customs crossing remains supported through the previously failing handoff. Actual records report zero deaths, 45 HP lost, 100 armor lost and one secret supply claim, with all three secret locations visited. Health restoration comes from ordinary supplies. This successful route supports the bounded capture correction; it does not identify the exact peer from the earlier failure or establish every possible moving-crowd configuration.

The source receipt records QaCombat SHA256 `94C70D4026E52B40766C259F3311D17FFF032DF059022CCF8832B5EE48EA7076` with the matching unchanged server/map hashes. The first 18-state failure remains historical. All owned runtime processes closed before root's final whole-checker and standard-publication handback. No movement, collision, difficulty, waypoint tolerance or authority changes are introduced.

## Current integrated route receipts

The later `.agents/qa/m04-textures-eighth-final/` run passes all 23 states,
all 28 named guards and actual roof departure, with exit 0 and no engine errors.
The contact-aware dodge and corrected ordinary routes retain all requirements.
Actual records report zero deaths, 85 HP lost, 150 armor lost and three secret
claims. Patient release and walking are observed; the second patient is still
waiting behind the first at departure, not proved at its final endpoint.

The current `.agents/qa/m06-port-peek-final/` run also passes all 25 states,
21 named guards and actual transit departure, with a clean engine log. Its
explicit ordinary Turret peek adds recorded cancellation timing to the
contact-safe movement evidence; it is not the identical approach manifest of
the earlier unchanged-route material retry. Records report zero deaths,
25 HP lost, 125 armor lost and two secret claims, with all three secret
locations visited. Earlier failures and earlier run statistics remain history.

## Historical workspace checkpoint (2026-10-02, before final gates)

The following receipt records that checkpoint. Current merged integration and
completed local gates are recorded above; publication receipts are tracked in
[release closeout](m06-release-closeout.md).

Root's final serialized `cargo fmt --all -- --check` and workspace Clippy
with warnings denied pass. `cargo test --workspace --locked` passes 1,244
tests with three existing ignored tests and no failures. Exact receipts are
`.agents/m06-buildout-20261001/final-fmt.log`, `final-clippy.log` and
`final-workspace-tests.log`. The rendered tour receipts prove their recorded
helper/assets and server hashes; they do not claim a newly rebuilt release
binary. Coverage is running, and the final matching release rebuild, broad
serialized Godot checker, CI and release are still pending. No shipped claim
or fresh-player acceptance follows from these bounded authoring gates.
