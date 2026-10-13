# Connected foundry development round

Status: **implemented**, 2026-10-13. Delivery is tracked in
[PR #402](https://github.com/blisspixel/fragr/pull/402); merge and release require
the passing checks below.
This follows shipped v0.82.1 and the existing
Full build order. Spend: $0, using retained assets and local tools.

## Contract and ownership

Connect The Weight of Permission as campaign level 13, map 1013 and mission
`weight_of_permission`. Follow the accepted level 13 section of
[the foundry brief](../campaign/m08-weight-of-permission.md), the
[campaign contract](../CAMPAIGN.md), [art bible](../ART_STORY_BIBLE.md),
[Mars direction](../design/mars.md) and current lore. The Walker and launch
works belong to M14. Worker choices are voluntary and never an exit key.
The town feed remains protected. Preserve the historical practice map exactly.

The server lane owns strict map/wire definitions, encounters, objective facts,
actual worker and overseer behavior, machinery and supported freight lift.
The save lane owns bundled mission registration, owned local launch, strict
version 17 migration and progression. The client lane owns validation,
presentation, localized framing, menus and authoritative platform prediction.
Integration owns the shared mission controller, its adapter and harness callers,
socket routes, documentation, review, visual inspection and GitHub delivery.
Coordinate shared shapes before implementation; do not create a second campaign
controller, persistence path or objective authority.

## Runtime and persistence

Use gameplay capability 47 with unchanged campaign rules revision 4. Reuse
MissionState and MapInfo with strict M13 geometry and facts. Progress from actual
arrival and encounter clears through a resolved finite Rocket Launcher claim,
the freight lesson and counterattack, a resolved relay face hit, gallery clear,
fresh supported all-party lift use and actual ridden arrival. Replicate machinery
warnings and current platform position from the server. Workers have separate
choices and actual grounded travel facts; a surrendered overseer is an actual
retained state, not an inferred story caption.

Version 17 carries M12 outcomes and mission-entry resources without an Episode
III continue refill. Explicit retry restores entry resources and foundry state
through the existing reset owner without rewinding ticks or input revisions.
Strict historical decoders reject forged future facts and retain original-byte
archives under the existing writer lock. Completed M13 awaits `launch_authority`;
unimplemented M14 remains refused. Closed failed and abandoned runs stay closed.

## Acceptance

Prove strict source and wire negatives, ordered actual-action progression,
finite ammunition and Rocket splash, protected-feed immunity, voluntary release,
hazard effective-loss accounting, party eligibility and whole-step platform
obstruction. Exercise actual network readiness, fresh geometry/state ordering,
ordinary full mission traversal, supported lift travel and departure. Test saves,
retry and historical migrations causally. Inspect client presentation and motion
in the real renderer, including warning readability and the rising platform.

Run locked workspace formatting, lint, tests, coverage at the existing 90 percent
floor, release build, dependency checks, required network/roster/soak gates, all
Godot harnesses and an inspected published visual tour. Independent review must
cover runtime, strict boundaries, saves and lore consistency. Merge a reviewed
passing PR, verify main CI, then package and release the player-facing change.
Return to one clean main before another production round.

This is a connected development increment. Final art, human comprehension,
first-run pacing, difficulty balance and full-campaign acceptance remain distinct
from automated clears. Record failures and remaining acceptance work honestly.

## Composition evidence, October 13

The native ordinary-input route walks the same 23-state manifest as rendered QA.
It grants no resources, removes no defenders and teleports no player. Its seeded
Standard pass completes in 4,692 simulation ticks with 25 defender deaths,
20 enemy attacks, five actual traveling Rockets and eleven reload deadlines.
The Rocket's resolved explosion removes effective enemy HP or armor; the final
living registered gallery guard retains the incomplete support receipt. These
are authoring observations under accurate aim, not a first-player completion
time or difficulty acceptance.

One hundred run-file regression tests pass, including exact historical archives,
M12 outcome and resource carry without refill, actual launcher pickup followed
by reopen/retry, and refusal of pending M14. Twenty-eight focused M13 tests and
five historical development-map tests pass. The standalone practice map retains
SHA-256 `4995b14d93670ff3b5e3711f3b0977205a3c28700d93662c4515047511d31943`.
The live socket boundary checks all three reader roles: capability 46 is refused
and 47 receives validated map geometry before mission facts. Isolated controller
tests separately cover stale maps, invalid facts, lift return and obstruction,
real ray-weapon selection, reload and ammunition seeking.

Review corrected two worker destination tolerances that could disagree with
strict arrival facts, an unsafe route alongside a restraint frame, insufficient
Use-distance margin, and relay steering that could retain the Rocket Launcher.
Client validation also accepts sparse lift observations without inventing the
direction of unobserved intermediate motion. Absolute displacement remains
bounded by elapsed ticks and actual lift speed.

Worker arrivals prove grounded travel from the quarters to registered safe
points. They do not claim off-map evacuation or allied deployment. Existing
civilian strips and coarse retained foundry art remain development presentation.
Moving-platform presentation follows authoritative snapshots; speculative local
carry is deliberately not claimed. The completed ordinary traversal and visual
checks are recorded below. GitHub integration follows the final client check.

The first real client join exposed a JSON numeric-type comparison in briefing
validation. Field-wise validation now accepts the server's decoded zero, and a
new owned M13 launch harness covers human admission, scene dismissal, readiness,
successive facts and child shutdown. Worker arrival validation uses the same
registered route and coordinate tolerances as the native boundary.

A rendered route then defeated the freight lesson during an earlier unfiltered
travel segment and died while recording the Rocket shot against the already
active counterattack. The manifest now disables travel combat by default and
enables only explicitly named encounter targets. A focused manifest check keeps
that restriction mechanical. The native harness accepts whole JSON tick counts
whether decoded as integer or floating-point numbers. Worker response text now
wraps inside its HUD bounds; the complete sentence was inspected in a real frame.

A later route exposed quarters guards during an undefended machine-hall capture
and took lethal Assessor canisters in the central freight aisle. Named quarters
defense now covers the transition. The freight route uses the existing eastern
office approach, clears the first three Sweepers, spends remaining finite rockets
against the Assessor, then advances against the remaining ground guards. It
changes no enemy, damage, supply or timing rule. The native route holds evasion
through a visible committed tell instead of periodically reversing into a locked
blast, and previews ordinary supported movement. It finishes with 100 HP and
75 armor, actual worker arrivals `[true, true, false]` and no hazard loss. The
earlier deaths remain evidence that first-player positioning and pacing need
review; a successful scripted strategy does not close that gate.

The next rendered pass reached the actual finite Rocket launch and failed its
visible muzzle assertion. The foundation had no first-person Rocket entry in
the weapon-art table, so the held tube and local flash were absent despite the
accepted projectile. Connecting the first campaign pickup also requires that
presentation gap to be fixed and inspected; audio-only launch checks do not
establish a visible first-person weapon. The fix adds an original cached
224x160 tube viewport with support and trigger cuffs, plus local and followed
first-person launch feedback. The generic muzzle flash survives its first draw
on a slow renderer. Focused checks cover accepted launch, prediction deduplication,
first-person versus third-person observation, expiry and rejected-cue cleanup.
Isolated rest and fire frames were inspected for the silhouette, cropped cuffs
and projected muzzle alignment. This remains coarse development geometry, not
accepted final weapon art.

The corrected [ordinary rendered route](../screenshots/m13-connected-20261013.json)
passes all 23 states through actual departure. All 25 guards are defeated, with
zero deaths or dry triggers. The record retains 80 HP lost and 50 armor lost;
ordinary supplies restore the final body to 100 HP and 50 armor. Five Rockets
produce four damaging attacks, 292 effective HP damage and one kill. The first
lesson shot alone records one damaging attack and 44 effective HP damage in
the next state, after its traveling projectile resolves. Hazard loss is zero;
worker arrivals are `[true, true, false]`, and the supported lift arrives at
14.6 m. The whole contact sheet, first Rocket frame and strip, eight-frame live
lift ascent and upper arrival were inspected. No grants, enemy deletions,
teleports or simulation freezes are used.

Review moved the relay status from its invisible top indicator onto the
approached housing face, with fitted, keyed ACTIVE/OFFLINE signs. Separately
arranged renderer fixtures and the focused M13 client check cover that final
cosmetic change. They are not mislabeled as played frames. The normal published
32-state tour also passes again after the Rocket presentation fix, with all
three transient strips inspected. Captures use Linux Xvfb and Mesa llvmpipe;
they establish software-rendered presentation, not hardware performance.

The full locked Rust workspace suite, formatting, clippy, release build and
dependency checks pass. The full unfiltered coverage run passes at 92.92 percent
of lines; adding the final ordinary-route run gives 92.94 percent in the
unfiltered workspace report.
The first Godot checker passes 366 scripts and all 175 harnesses. After the
Rocket viewmodel addition, the checker covers 367 scripts. That run found one
local-launch harness exiting before the audio mixer released its queued
resources. Its teardown now uses the same bounded drain as the earlier mission
harnesses; the focused verbose rerun passes without resource leaks. The final
clean whole-client rerun passes import, all 367 scripts and all 175 harnesses,
including the actual local M13 launch, with no reported resource leaks.
Older native and
client save assertions needed the current version 17 expectation; their original
historical input bytes remain unchanged. The 32-state arena tour passes, with
14 published stills and inspected world, menus and transient effect strips.
All eight required network scenarios, seven mixed-roster maps and ten Godot
verifier fault-injection cases pass. The contested CTF sample ends 0-0 with no
flag takes; its passing gate is not capture-completion evidence. The separate
CTF route smoke completes a capture, and the Sabotage route smoke plants and
defuses. Every roster sample records zero spawn deaths.

| Rotating soak observation | Result |
|---|---|
| Scope | 120 seconds, four agents, four bots, two spectators, local loopback under concurrent verification load |
| Sampling | Nine samples, approximately 20 Hz |
| Queue overflows, degraded samples, over-budget ticks | Zero |
| End-window tick p99 / observed maximum | 2.228 ms / 24.604 ms |
| RSS, start / end | 64.76 MB / 66.11 MB |

These measurements establish this bounded local check, not network capacity,
remote latency, GPU support or a larger-server claim. Exact commands, fixed
binary hashes and reports remain under `.agents/round2-20261013/playtests/`.

The release CPU benchmark passes its deterministic replay and budget assertions.
It runs faster than real time without network clients and establishes no
renderer frame rate.

| CPU benchmark observation | Result |
|---|---|
| Scope | Linux x86_64 release build, 16 bots, 1,200 ticks, seed 42 |
| Timing scope | Session and encoding, no network clients |
| Mean / p99 / maximum | 0.204 ms / 0.950 ms / 1.597 ms |
| Deterministic replay and budget assertions | Passed |

Independent runtime, protocol, controller and save reviews found no blocking
composition issue. Two incidental changes to older mission prompt comparisons
were removed, keeping their existing exact-stage validation.
