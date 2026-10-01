# M05 No Forwarding Address prototype

**Status:** shipped, 2026-09-30. Merged in
[PR #314](https://github.com/blisspixel/fragr/pull/314). Continues the
[M04 prototype](m04-notice-to-vacate-prototype.md). Full twelve-minute pacing,
the five-minute par and fresh-player/difficulty acceptance remain separate gates.
**Spend:** $0 planned new charges. This continues the same authorized $20 round
within the $50 total cap, with $0 new cash charges. The capped
[audio batch](m05-audio-batch.md) brings this round to 693 included credits
consumed and a separate conservative $3 equivalent reserve. No new paid
generation, top-up or cloud apply is authorized by this plan. Nick additionally
authorized keeping GitHub current with one green main branch and updated releases
on 2026-09-30. After local convergence, commit with the permitted identity, open
a PR, wait for required CI, squash merge and publish a player-visible release.
Release packaging must pass its own workflow before claiming artifacts available.

## Goal

Build the accepted [level 5 design](../campaign/m03-no-forwarding-address.md#level-5-design-twenty-level-expansion)
as a playable Episode I finale: Low Water roofs and water tanks, crane walk,
paint-bay grenade lesson, optional Splice/captive rescue, tram trench, isolated
Heavy Sweeper introduction, freight hold and deliberate ship boarding. Retain
earlier rescue choices through entry/retry and the pending lunar destination.
Improve environmental activity and detail through the existing
[world and character guides](../design/README.md), rather than a new visual style.

## Scope and decisions

- Six ordered fights: roof crossing, paint bay, workshop watch, trench watch,
  solo Heavy and mixed freight watch. Required groups do not spawn early. The
  proposed compact roster is 21 guards: six Notaries, four Clerks, nine Sweepers
  and two Heavies. Keep a physical walking route through all required regions.
- Grenades are counted equipment, cap six, separate from gun selection and
  Bullets/Shells/Cells. One rising-edge throw travels along server-owned aim,
  bounces, expires on a fixed fuse and blasts with distance falloff and solid
  occlusion. Owner damage must not award a self frag. Existing Heavy timing and
  once-per-attack heavy-hit stagger stay unchanged, so rules revision 3 remains.
- The same discrete Action carries human and agent throws. Ingress latches the
  edge before replacing latest movement input, retaining a press/release between
  simulation ticks. No new hot-path control channel or frame-rate throw repetition.
- Grounded Splice and captive release uses actual party presence after workshop
  clearance. No release animation or civilian arrival gates the required exit.
  Rescue stays optional across prototype tiers. The full briefs disagree on
  Assisted requirements; retain that discrepancy as a later authored difficulty
  acceptance item, without silently changing canon or introducing a hard gate.
- One freight gate has closed/open geometry prepared before readiness. Its open
  MapInfo precedes changed mission facts; controls wait for matching replacement
  state. Departure requires actual fresh Use and the living party at boarding.
- Implement a separately bounded real tram mechanic if its isolated contract
  passes: one registered solid on a cleared linear lane, fixed authoritative
  speed/start/end, riding by supported feet, actual collision/shot cover, unchanged
  walking access and no topology rebuild each tick. It must reset with the attempt
  and provide current collision geometry to prediction and presentation. A visual
  tram alone is never claimed as moving cover or a ride. Record any remaining
  mechanic gap explicitly; full mission acceptance requires the promised ride.
- Three supply detours: second-tank armor, service-pit shells/grenade, and a real
  return to the market supply shortcut. Prove stairs and ordinary body clearance;
  no claim of optional jump/runner acceptance from ideal coordinates.
- Earlier car, clinic and photograph outcomes remain explicit retained facts.
  Do not invent Sorrel's proposed death, establish final character voices, revive
  a missing survivor or infer identity from a chassis. The ship can be a stationary
  boarding landmark; interplanetary flight is not vehicle simulation in this gate.

## Architecture and ownership

Reuse `mission`, strict authored maps, registered geometry, encounter lifecycle,
inventory and shared controllers. Server/map lane owns M05 protocol, definition,
mission/controller, world preparation, bounded tram contract and encounter tests.
Combat lane owns grenade inventory, Action ingress, authoritative projectiles,
resolved explosions, pickup/controller and adapter/brain integration. Client lane
owns strict M05/equipment boundaries, controls, HUD, world/scene presentation,
prediction's actual tram collider and focused harnesses. Local-run lane owns
versioned save upgrades, retained outcomes, local CLI and actual child tests.
Coordinate shared glue by symbol; preserve all previous uncommitted work.

## Wire and persistence

Gameplay capability 26 is the new live authored-campaign boundary. All five
authored missions reject older readers before state delivery. Missionless arcade
compatibility stays explicit. Add M05 mission/map/state through the existing
MapInfo/Mission channel; use strict typed grenade and resolved explosion facts in
the existing snapshot. Keep six weapon/statistic slots unchanged. Private equipment
has an authoritative grenade count. Document exact fields and bounded arrays.

Run version 6 preserves M04 choices through playable M05 and its retries, retains
M05 rescue outcomes at pending Port of Entry, and adds the independent grenade
count. Keep explicit historical readers in `mission/run_file/legacy.rs`, separate
from the current document and locked store. Strict v2/v3/v4/v5 readers validate original shape, rules, hashes
and supported stages before assigning historical zero grenades. Archive exact
source bytes before locked replacement. Unknown future versions and forged old
M05/grenade fields are rejected. Preserve body, HP, armor, guns, ammunition,
episode allowance and identity; retire only old-map personal supply claims.
Episode II refill belongs the future M06 transition, not M05 retry or completion.

## Verification and success criteria

Baseline is 1167 Rust tests, 94.47 percent workspace lines, clean formatting,
Clippy/release/license gates, 163 client scripts and 76 harnesses, corrected CTF,
six-map roster, CPU benchmark, actual 120-second soak and inspected final tours.

Focused tests must distinguish discovery/full/empty grenade counts, short taps,
held input, duplicate sequence, inactive/dead/reset refusal, continuous flight,
wall/floor/ceiling bounce, fixed fuse, cover/falloff/raised drone geometry,
self damage without self credit, effective damage and Heavy stagger. Validate
new wire fields on both sides and maintain missing-asset fallback.

Authoring tests traverse actual support/collision with tolerance, both gate worlds
and the real runtime map. Mission tests cover ordered groups, optional rescue,
living-party departure, reset and controller invalidation. Tram tests cover actual
rider transport, dismount, jump, obstruction/clearance, cover, reset, lane bounds
and shared prediction geometry. No cosmetic mesh changes authority.

Local tests upgrade a real completed v5 M04 save into M05 with exact carried body,
equipment, allowance and earlier outcomes, verify archive bytes and held-input
release readiness, then exercise retry without clock/revision rewind. Failure
paths preserve the prior save and reject incompatible historical shapes.

Run the repository's full relevant verification and an actual input-driven M05
clear, plus `tools/qa_tour.sh --publish`. Inspect world, menus, grenade arc/bounce/
blast, Notary phases, tram movement, patients and departure. Each capture must
prove its named state. Record failures without weakening checks, commands/results,
measurement tables, renderer, untested combinations and the next step here.

Primary pinned client APIs checked on 2026-09-30:
[InputMap](https://docs.godotengine.org/en/4.7/classes/class_inputmap.html),
[ImmediateMesh](https://docs.godotengine.org/en/4.7/classes/class_immediatemesh.html)
and [Shader](https://docs.godotengine.org/en/4.7/classes/class_shader.html).

## Work record

Research confirmed the existing Heavy stagger and found missing moving-platform
support. The older arsenal plan's mission numbers and disk-save statements are
historical and must be updated with this increment. Implementation follows the
contracts above; no current M01-M04 authored bytes are to be rewritten.

Focused persistence checks passed 30 tests before the final completion-projection
addition. The actual native child reopened a strict historical v5 M04 exit into
M05 twice with one exact-byte archive, preserving body, health, ammunition,
allowance and earlier choices. Independent source review found no consequential
save/local-launch defect; it identified the missing live M05 completion projection
case, which now tests a spent grenade, distinct released/aboard workers and
refusal to replay M05 from pending M06. Final serialized checks must include it.

GitHub CLI identity is `blisspixel`; the repository is public and main requires
the strict `test` check. Existing Linux, Windows and macOS jobs use standard
hosted runner labels. Their public-repository usage is free under the current
[official runner contract](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
checked 2026-09-30. No larger runner, cloud service or billing setting is enabled.

The first reviewable checkpoint is commit `84cfd21` on
[PR #314](https://github.com/blisspixel/fragr/pull/314). It contains the accumulated
campaign, design, asset and presentation work. Main remains protected while local
M05 verification and the CI/package checks run. No release is claimed by this
checkpoint. Independent review identified conservative tram routing being reused
as combat visibility. The correction keeps the cached route reservation but uses
the tram's actual translated solids for firing, including external controllers.

The frozen-source checkpoint `fb2dfe3` also validates actual decision intent,
strict historical fixtures, scoped capture input and an ordinary high grenade
throw. Its seeded test reads the same feet and aim as the rendered manifest,
clears the chassis with the real swept projectile and requires positive HP damage
to a guarded Sweeper. An earlier shallow throw settled on the roof; a first high
throw overshot after bouncing. Both failures remain in the diagnostics. The
final ordinary aim is about 58 degrees, with no equipment grant, enemy weakening
or forced combat phase. The capture follows the confirmed owned projectile after
launch; it cannot change its trajectory.

M05 authored bytes are frozen at SHA-256
`04764f0d665818454ddedaaf67f1e7984bfea571eaed0181cf521f7fc56d09fe`.
M01-M04 authored bytes remain unchanged. Prior M05 partial tours are historical
diagnostics, not completed mission evidence. A carried QA travel-fire setting
prematurely killed the Heavy before its observer began. The shared capture helper
now restores each stage from the manifest default and rejects nonboolean values.
The Heavy approach stays inside the observer, with its windup and complete burst
requirements intact. The service-pit clue now faces its accessible room.

## Final verification record

Logs live under `.agents/m05-buildout-20260930/`; rendered and client receipts
are linked by their owning child plans. No local Docker engine is available, so
local container verification is unavailable. The GitHub container job supplies
the actual build, unprivileged runtime, notices and health-probe evidence.

| Gate | Actual result |
|---|---|
| Final workspace formatting and warnings-denied Clippy | PASS, final formatting check and `clippy-final.log` |
| Final instrumented workspace tests and unfiltered coverage | PASS, 1206 tests, three existing ignored, 94.25 percent workspace lines, `coverage-final.log` |
| Focused final M05 authoring and route checks | PASS, 17 tests, `m05-lob-and-route-final.log` |
| Full workspace release build | PASS, `release-verified.log` |
| License, ban and source checks | PASS, `deny-converged.log` |
| Deterministic 16-bot CPU benchmark | PASS, `bench-verified.log`, zero over-budget ticks |
| Actual native historical M04-to-M05 run launch | PASS, exact carried body/equipment/outcomes and archive, `test_m05_local-converged.log` |
| Checker fault injection | PASS, all ten cases, `checker-verifier-final.log` |
| Free-for-all, team deathmatch, rail-only and licence-to-kill | PASS, current release binary, `playtest-final-*.log` |
| Contested Sector 9 CTF | PASS, two takes, one drop, one return and one capture, `playtest-final-ctf-contested.log` |
| Uncontested real-input CTF route | PASS, one take and one capture, `playtest-final-ctf-route-corrected.log` |
| Final pinned client checker | PASS after modal and approach corrections, 174 scripts and 81 harnesses, `.agents/m05-client-buildout-20260930/godot-full-approach-final.log` |
| Actual 120-second release soak | PASS, nine samples, four agents, four bots, two spectators and map rotation, `soak-final.log` |
| Six-map mixed-client roster | PASS, 2/6/6/8/12/16 agents, exact `playtest_roster.sh` cases on the already built binary, `roster-final-*.log` |
| GitHub source checkpoint `41e982d` | All CI and three desktop package checks PASS, [CI run](https://github.com/blisspixel/fragr/actions/runs/36817795082), 1206 tests and 94.23 percent unfiltered Linux workspace lines |
| Final ordinary-input M05 capture | PASS, 25 states, `.agents/qa/m05-rooftops-sixth/manifest.json`, inspected Windows/OpenGL/AMD Radeon 780M |
| Final standard published tour | PASS, 32 states and 13 selected stills, `.agents/qa/m05-standard-modal-final/manifest.json`, inspected same renderer |

### CPU measurement

`cargo run -p fragr-server --release --locked -- --bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42`
ran on this Windows development machine without a rendered tour running. These
are server CPU measurements, not a GPU, hardware frame-rate or large-server claim.

| Accounting | Mean (ms) | p99 (ms) | Maximum (ms) | Over-budget ticks |
|---|---:|---:|---:|---:|
| Session simulation | 0.130778 | 0.688127 | 2.1028 | 0 |
| Session plus encoding | 0.139342 | 0.688127 | 2.1143 | 0 |

The final soak ran alongside other local verification, with no executable
replacement. Its record is `.agents/soak/m05-final.ndjson`, with the owned
server's log alongside it. This remains a short local robustness measurement.

| Soak measurement | Actual result |
|---|---:|
| Duration and samples | 120 seconds, nine samples |
| Observed tick rate | 20.00 Hz |
| Lifetime tick p99 / maximum | 0.69 / 1.86 ms |
| Resident memory start / end / maximum | 38.4 / 39.1 / 39.2 MiB |
| Outbound / inbound bytes per client per second | 50523 / 2411 |

The fourth actual M05 tour passed all 25 states at
`.agents/qa/m05-rooftops-fourth/manifest.json`. It cleared all 21 guards with no
death and visited all three secret locations. Three secret supplies were claimed
at the tank and service pit; the market medkit stayed available at full health. The actual
Heavy completed its windup and four-shot burst before dying. All three freed
workers walked to boarding. An ordinary jump boarded the tram; 97 supported
samples recorded equal 4.860018 m rider and tram displacement. The physical
passenger dialog cancelled without queuing Use, reopened and required fresh
confirmation before the server reported departure.

The recorded grenade stock changed from four to three. Serial 1 traveled and
bounced on real geometry with fuse 40, then produced its matching radius-four
explosion at `[-0.7519517, 1.0545083, -9.860239]`. Its hit list is empty and its
effective damage is zero. This is real flight, cover clearance and blast
presentation evidence; the separate seeded test proves positive guarded-side
damage. The capture cannot establish fresh-player grenade timing.

Visual review found the passenger dialog below the HUD canvas, with the ordinary
departure prompt overlapping its cancel instruction. The client lane corrects
modal layering and repeats the focused/full client checks and both tours before
publishing the final gallery. The fourth mechanics remain a valid receipt; its
overlapping dialog is retained as a diagnostic, not a polished modal still.

The fifth replay stopped after the Heavy clear: the freight group activated on
the next server tick, and its live Notary killed the participant while the capture
paused for a post-clear still. Its Heavy phase evidence is valid, but it is not a
25-state pass. The capture lane corrects this tactical handoff with ordinary
movement or defensive input, preserving the roster, activation rules, health and
phase assertions. No simulated pause or invulnerability hides the failure.

The final sixth tour passed after the corrected approach and modal. All 21 guards
died with no participant death. The Heavy fired four rounds before seven Rifle
shots cleared it; the attempt lost 100 armor and no HP. All three workers were
physically aboard. The actual ride produced 99 supported samples and equal
4.800017 m tram/rider displacement. Grenade effective damage remained zero.
Three locations were reached; tank armor and both service secret supplies were
claimed, while the market medkit remained available at full health. The physical
passenger review is now readable, with successful cancel/reopen/fresh confirmation.
The named Heavy windup image faces away from the attacker, so only its actual
firing frame is published as visual phase evidence. Required windup remains typed
server evidence. M05's other phase probes are post-clear; separate M04 captures
provide live Notary presentation evidence. No caption turns those into new proof.

The standard tour was regenerated after the last visible change, passed all 32
states and published 13 selected stills. Eleven inspected M05 stills/strips are
separate from the four README images, with honest captions in
[the screenshot index](../screenshots/README.md). All owned native children closed.
The bounded source increment merged in [PR #314](https://github.com/blisspixel/fragr/pull/314).
The final PR head `a9b284b` passed all checks in
[CI run 36821422845](https://github.com/blisspixel/fragr/actions/runs/36821422845)
and all three desktop package checks in
[run 36821422868](https://github.com/blisspixel/fragr/actions/runs/36821422868).
Linux CI measured 94.22 percent unfiltered line coverage (48,714 lines,
2,815 missed); the Windows local 94.25 percent result remains a separate receipt.
The tagged [release workflow](https://github.com/blisspixel/fragr/actions/runs/36823111467)
passed all three package installation smokes at merge `008abd08`.
[v0.65.0](https://github.com/blisspixel/fragr/releases/tag/v0.65.0) is published
with Windows, Linux and macOS packages plus `SHA256SUMS.txt`. Its checksum entries
match GitHub's recorded asset digests. Full twelve-minute pacing, the five-minute par,
fresh-player and difficulty acceptance, later missions, two-machine feel and
hardware listening remain separate work after this bounded prototype increment.
The next development rung is the planned
[M06 Port of Entry increment](m06-port-of-entry-prototype.md), with explicit
lunar identity, found Railgun/Turret teaching and a once-only Episode II refill.
