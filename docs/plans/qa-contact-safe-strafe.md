# QA contact-safe strafe

**Status:** implemented, 2026-10-01. Focused regression, the unchanged full M06 route and refreshed standard publication pass. Final serialized whole-client verification and integration remain root-owned. No gameplay rule changes.

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
