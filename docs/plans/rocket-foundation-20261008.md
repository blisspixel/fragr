# Rocket Launcher foundation

Status: **in flight**, 2026-10-09. The composed Arc, Assessor, connected M12
and live Edda gates are on `main` through
[PR #375](https://github.com/blisspixel/fragr/pull/375) and are recorded as
v0.80.0. This change adds server flight, inventory, records, save migration
and client presentation. No mission grants the launcher. The optional M12
secret and connected M13 stay out of this increment. The [weapon brief](../WEAPONS.md),
[readable arsenal](readable-arsenal.md),
[M12 secret](../campaign/m07-terms-of-cooperation.md#level-12-design-twenty-level-expansion)
and [M13 introduction](../campaign/m08-weight-of-permission.md#level-13-design-twenty-level-expansion)
own the purpose. No paid calls, dependency changes or release claim are part of
this plan.

## Proposed bounded behavior

The accepted bounded foundation gives 65 direct damage plus covered splash,
a sixteen-tick firing cycle (0.8 seconds) and four Rockets per weapon pickup.
The shared design review approved these initial constants on 2026-10-08:

| Concern | Proposed value |
|---|---|
| Wire identity and appended weapon index | `rocket`, index 9 |
| Ammunition | New `rockets` pool, index 3, capacity 20 |
| Arcade spawn stock and ownership | Zero Rockets, no Rocket Launcher |
| Human tube and reload | One round, sixteen ticks, ordinary rising-edge R |
| Flight | Straight, 18 m/s, 0.12 m collision radius |
| Lifetime and maximum free travel | Eighty ticks, 72 m |
| Collision work | Four bounded swept substeps per tick |
| Live projectile limits | Sixty-four total, eight per owner |
| Splash | Four metres, linear falloff from 45, ordinary solid occlusion |
| Direct and splash relationship | Direct 65 plus actual covered splash, combined once per body |
| Head bands and armor | No head multiplier; actual-face plate on direct component, carried armor once |
| Reserved compatibility allocation | Gameplay 46, participant record 4, save 16, rules 4 |

One successful discharge spends one Rocket and loads no replacement without the
human's ordinary reload input. Agents retain the shared single ammunition count.
First discovery loads only from its actual four rounds; a duplicate adds finite
bag stock without changing a partial magazine. A dry trigger creates no
projectile, cooldown success or random outcome. A reached live-projectile limit
refuses the discharge before ammunition or statistics change.

The projectile commits the server aim on launch. It travels through time, has
no homing and cannot damage a distant target on the launch tick. Sweeps choose
the earliest actual world or body collision, including raised flying bodies,
ducking bodies, current vehicle hulls, civilians and moving mission collision.
The launch segment must be checked too, preventing a close wall from being
skipped by a cosmetic muzzle offset. A lifetime expiry retires it without an
invented distant blast. Covered blast damage cannot pass through the impact
surface. An explicit leave removes owned projectiles; death retains committed
shots. Round, map and mission retry resets clear them without rewinding serials,
input sequences or inventory revisions.

Direct damage and blast damage reuse server-owned eligibility, immunity, side,
companion and armor handling. Apply a registered role plate only to the 65-point
direct component, using the actual impact face. Covered splash bypasses those
plates under the established blast policy. A protected body can stop the rocket
while taking no damage. Splash can hurt its owner under the existing self-damage
policy. The direct victim may also receive actual covered splash. Sum those
eligible components before one carried-armor debit, effective damage result and
death/statistic commit per body. Several bodies may lose HP to one blast; no
victim is committed twice. No launch or blast fabricates a hitscan `ShotResult`
or `ShotTrace`.

## Authority, wire and records

Own a focused `sim/rocket.rs` module, reusing the existing swept geometry and
blast helpers where their contract fits. Extend the shared damage seam only as
needed to combine the direct and covered splash components before a single
damage commit per body, with explicit source attribution. A resolved impact must carry projectile serial,
owner, Rocket Launcher identity, actual impact kind and position, optional direct
target and bounded effective per-target damage. Snapshots carry bounded live
position, velocity and age facts; the client never decides a collision.

Count one Rocket attack on accepted launch. At resolution, aggregate direct and
splash effective HP, armor and kills into its new weapon column once. A connect
means an actual direct body contact or damage from that rocket's blast; heads
stay zero. Multikills need an explicit Rocket-specific bounded validator, using
the existing 256-recipient blast limit. Do not raise another gun's pellet count,
turn splash victims into separate attacks, infer effective damage from raw
damage or assign the result to grenade counts. Dead-owner impacts still update
the original owner's actual record.

Append the new weapon and ammunition indices. Preserve all nine existing gun
indices, three existing ammunition indices, six physical keys and established
default arcade stock. Repeated existing family selection and the wheel must
reach the owned launcher without replacing an older gun. The shared equipment
controller may select it only with finite stock and an ordinary valid target;
it must respect nearby self-splash and avoid overriding a usable explicit choice.

Record revision 4 proposes exactly ten gun columns. Retain strict revision 3
nine-column, revision 2 eight-column and revision 1 historical widths. Never
truncate actual Rocket facts for an older recipient. Older admitted recipients
receive only representable facts. All Rocket-bearing venues require its agreed
capability for every role, including spectators and resume. Existing rule
revision 4 evidence retains its exact revision unless a separately approved
enemy timing change requires a new rules revision.

## Saves and mission placement

Save 16 proposes an exact version 15 reader with original-byte archival under
the existing lock. Every pre-16 decoder must reject selected or owned Rocket
Launcher and any Rockets pool, including zero-valued forged ownership or stock.
Strict historical three-pool shapes stay independent of the wider current enum.
Current four-pool entries require all unique bounded counts without silently
inventing ammunition. Historical compatible entry equipment upgrades to zero
Rockets through the explicit migration only.

The canonical M12 maintenance hatch may offer the early four-round launcher as
an optional real secret. It does not gate M12 departure or its main Arc lesson.
M13's ordinary route remains the teaching introduction. Persist only actual
ownership and stocks, and restore the mission-entry kit on continue, putting an
in-mission secret back on the floor after a pre-departure death. M12 entry from
M11 rejects ownership before the find; a completed M12 may carry an actually
found launcher. No M13 MissionId, departure, challenge receipt or promotion is
added until the connected M13 contract and acceptance are implemented.

Adding the M12 secret changes canonical content bytes. Preserve exact content
binding and archives; do not silently rebind an old save to new map bytes.
Any known historical M12 content-hash migration requires an explicit bounded
policy and regression before that map edit can be accepted.

## Presentation and verification

Use independent authored geometry or local pixel assets for the launch tube,
loaded/empty state, reload and visible traveling rocket, plus distinct committed
offline launch, flight and impact cues at zero service cost. Presentation follows
actual serials and resolved impacts, including dead owners, and ends on reset.
The client displays the new finite Rockets pool, world pickup, held launcher,
records and supported local finish without borrowing another weapon's identity.

Focused checks must prove delayed damage, moving-target misses, earliest contact,
thin-wall and muzzle obstruction, body and vehicle collision, covered splash,
falloff boundaries, combined direct-and-splash single commits, normal armor, owner harm, friendly
fire, immunity, dead-owner attribution, leave/reset, lifetime and live caps.
Include a single launch killing several actual victims while recording one
attack and exact effective damage. Inventory checks cover four-round discovery,
duplicates, capacity, the one-round tube, rising-edge reload, dry fire and real
death/continue/carry. Compatibility checks cover exact old shapes, forged old
ownership, historical record retention and original-byte save replacement.

Only after those gates, play a bounded actual human lesson with ordinary input,
finite pickups, real reloads, actual traveling impacts and a readable safe splash
space. Retain failed runs, logs, source/native hashes and full-size inspected
captures. That lesson proves its bounded mechanism, not final balance, fresh
player comprehension, final art, a completed M13 or all-platform support.

Root owns shared sequencing and composition documents. This weapon lane owns the
Rocket foundation with the approved constants and compatibility seams above.
The implementation is in this change. Campaign placement, the optional M12
secret, final art and a played human lesson remain ahead. No paid calls.

Local evidence before integration, 2026-10-09: `cargo test --workspace --locked`
passed. Formatting and warnings-denied clippy passed before the final M09
harness edit. The full Godot check passed every harness except `test_m09_local`,
whose historical retry still looked for save version 15, and `test_desktop_host`,
whose Conquest resume timed out while that full run was loading. Both passed
when run alone after the version-16 marker fix. Coverage, the bench and the
playtest roster were not re-run for this change.

## Existing seam review, 2026-10-08

`sim/grenade.rs` owns bounded sphere/world contact, stance-aware blast points,
covered falloff and source-specific explosive records. `sim/assessor.rs` already
sweeps a finite projectile against bodies, current vehicle hulls, civilians and
tableau collision. Reuse those contracts where applicable without borrowing
canister gravity or grenade fuse behavior.

`sim.rs::resolve_fighter_hit_for` commits armor, effective loss, death and mode
consequences once. Its registered plate calculation currently consumes a real
`ShotTrace`; do not manufacture a trace to make a rocket pass through it.
Extract the existing actual-origin/impact-face plate calculation into a shared
direct-component helper, preserving Auditor angle and Assessor face/recovery
semantics and all existing pellet behavior. Compute Rocket direct damage through
that helper, add eligible covered splash, then commit once with an explicit
Rocket source and no hitscan result. Keep each gun's actual armor policy intact.

The same rule applies to a directly struck vehicle: calculate its direct and
eligible covered splash share before one hull-damage commit. Calling both the
ordinary direct path and a second blast path would risk duplicate vehicle
consequences. Retain earliest world/body/hull contact and serial ownership even
after the shooter switches weapons or dies. These are implementation constraints
from source review, not newly implemented projectile evidence.
