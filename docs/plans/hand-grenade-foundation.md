# Counted hand grenade foundation

**Status:** in flight, 2026-09-30. **Spend:** $0. Implements the combat lane of
[M05](m05-no-forwarding-address-prototype.md), using the existing discrete Action,
inventory, pickup, combat, controller, record and snapshot seams. No new dependency
or paid service. Guns retain their selection and six record slots.

## Contract and constants

`throw_grenade` is a held Action bit with ingress edge latching beside interact.
A short press and release before a tick survives once. Held input never repeats.
Only living active participants with carried grenades can throw. Weapon-only
mutators refuse the separate explosive inventory. Successful
launch consumes one count and the tick's attack admission, leaving gun selection
unchanged; an empty or refused throw does not block gun fire. Count cap is six;
authored grenade grants use the existing personal/contested claims.

| Constant | Value |
|---|---:|
| Carry cap | 6 |
| Fuse | 40 active ticks, two seconds at 20 Hz |
| Throw cooldown | 15 ticks |
| Initial speed along authoritative aim | 12 m/s |
| Added upward speed | 4 m/s |
| Radius | 0.12 m |
| Gravity | Existing 22 m/s squared |
| Normal restitution | 0.45 |
| Ground tangential retention | 0.72 |
| Settle normal speed | 1 m/s |
| Physics substeps | 4 per tick |
| Contact budget | 4 per substep, remaining travel discarded on exhaustion |
| Maximum live grenades | 3 per owner, 64 globally |
| Blast radius | 4 m |
| Maximum raw blast damage | 100, linear falloff to zero |
| Maximum resolved victim entries | 256 |

Sweep each travelled segment against radius-expanded current authoritative
solids, floor and bounds. Reflect at the earliest contact, offset outward and
continue only the remaining bounded distance. Never move through a contacted
solid when the contact budget ends. Fuse begins at launch and expires exactly
40 subsequent active ticks, including resting grenades. No impact damage or
actor-body collision. Current tram geometry owns cover and bounce every tick.

Distance uses the nearest point on the actual actor body: grounded cylinders or
the raised Notary box. Solid occlusion from blast center to that point blocks
damage. Armor and HP, death, encounter hit phases, flags and mission continues
use shared resolution. Self damage is permitted but never awards self score,
frag, killstreak or outgoing kill credit. Death does not erase a launched device;
explicit leave, retry, reset, map/round replacement and departure clear it.
Inactive mission time does not advance combat. Input latches clear with ordinary
readiness/death/retry/drop lifecycle. No future encounter can be damaged early.

Heavy Sweeper timings and the existing >=40 HP damage in one tick,
once-per-attack stagger remain unchanged. Campaign rules revision 3 stays current.
Gameplay capability 26 guards live authored missions and new equipment/effects.

## Wire and records

Private `LoadoutState` and saved equipment require `grenades: u16`. Root owns
strict save version 6 historical upgrades assigning zero only after old-schema
validation. `PickupState` uses kind `grenade`, existing amount, no weapon/pool.
Snapshot arrays `grenades` and `explosions` are defaulted and omitted while empty.
`GrenadeState` has id, owner_id, position, fuse_ticks and bounce_count. The contact
count advances only for real bounces at a normal speed of at least 1 m/s; floor
support does not invent repeated sound cues. Its contact budget bounds it at 640.
`ExplosionResult` has
id, owner_id, position, radius and bounded hits; each hit has target_id,
hp_damage, armor_damage, target_hp_after and killed. All are resolved facts,
never guessed weapon evidence. IDs share the monotonic projectile serial.

`CombatCounts.grenades` has separate attack/damaging attack/kill/effective HP and
armor counters. It defaults to zero for retained records and omits when unused.
Record version 1 and six gun slots retain their meanings. Aggregate totals and
validation include the separate grenade column, with blast victim bounds rather
than gun pellet bounds. Victim losses remain actual post-armor damage; outgoing
credit excludes self damage.

## Ownership and verification

This lane owns grenade/inventory/private loadout/pickup, Action/snapshot/effect
types, sim ingress and dispatch, shared damage support, statistics and external
agent readers/controller/tests. The server/map lane owns mission, tram and
current_arena; root owns save files, local launch and recovery. The client lane
mirrors strict fields, rebindable input, HUD and resolved effects. Coordinate
shared files by symbol; do not format unrelated files or overwrite release
executables during captures.

Seeded tests cover counted/full/empty inventory, claim caps, short taps, held
input, duplicate sequence, inactive/dead/refused/reset admission, wall/floor/roof
bounce and no tunneling, exact fuse, falloff, blocked blast, raised targets,
effective armor/HP, self death without credit, posthumous blast, Heavy stagger,
tram geometry and retry cleanup. Controllers retain explicit throws, never
invent counts, clear invalid targets and do not throw through stale mission
geometry. Real adapter schema and observe shapes expose the same Action.
Run focused tests and Clippy, then parent-coordinated full gates and input tour.

## Implementation evidence

Implemented counted inventory, strict wire fields, edge latch, fixed-fuse swept
physics, resolved cover-aware blast, self-damage policy, separate record column,
explicit controller throws and real MCP schema/observation. Playtest explosion
tallies use effective evidence and the grenade identity even after an owner or
victim disappears from the snapshot. The harness counts detonations; durable
participant records count launches. No paid call or dependency was added.

| Focused command | Actual result |
|---|---|
| `cargo check --workspace --all-targets --locked` | PASS |
| `cargo test -p fragr-server --lib grenade --locked` | PASS, 17 tests including parallel carry/retry tests |
| `cargo test -p fragr-agent-adapter -p fragr-brain -p fragr-playtest --locked` | PASS, 91 adapter, 114 brain library, 10 brain binary, 74 playtest library and 5 playtest binary tests |
| Focused four-package Clippy | One test-only useless conversion found and corrected; final serialized gate pending |

Logs are `.agents/m05-grenade-check.log`, `m05-grenade-tests.log`,
`m05-agent-reader-tests.log` and `m05-grenade-clippy.log`. The final self-only
blast/empty-throw regression and last controller guard are included in the
parent's upcoming full gate. Standard Heavy blast interruption is seed-tested;
the three historical timing tables are asserted unchanged. This does not claim
three-tier M05 acceptance. Rendered grenade/tram input evidence and final
workspace gates belong to the parent plan before mission completion.

Independent M05 review found stale panel visibility against parked tram solids,
nonfinite captive delta handling and an edge-rider mismatch with ordinary feet
support. The mission lane corrected these at their owning seams and added an
edge-support regression. Grenades already use `current_arena()` for admission,
movement and blast sight. Explicit leave cancels owned devices; owner death
retains them. Existing traveling-shot cleanup now clears all explosive attempt
state through the round/map/encounter reset seam.
