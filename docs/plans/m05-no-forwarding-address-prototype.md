# M05 No Forwarding Address prototype

**Status:** in flight, 2026-09-30. Continues the locally implemented
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
the existing snapshot. Keep six gun/statistic slots unchanged. Private equipment
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
