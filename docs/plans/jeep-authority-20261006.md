# Shared authoritative jeep

Status: **implemented**, 2026-10-07. Native authority, client prediction and
automated played island routes are verified locally. Integration is tracked
by [vehicles](vehicles.md); campaign placement and human feel remain separate.

## Goal and scope

Make the shared two-seat jeep driveable on Holdfast Atoll through the ordinary
action channel. Walking remains available. The
[Launch Works development level](m14-vehicle-development-20261006.md) remains
planned after the island water and flight priority. This slice includes
bounded arcade movement, safe entry/exit,
driver/gunner switching, mounted heat fire, damage and vehicle reset. Boats,
aircraft, motorcycle, jetpack and finished M14 story acceptance remain separate.

## Architecture and wire

`server/src/vehicles.rs` owns the shared pure movement kernel, geometry probes
and entities. A narrow simulation bridge owns seats, actor lifecycle, shared
hitscan/blast resolution and reset. Validated spawns are registered only for
runtime map ID 7 (Holdfast). Campaign placement needs its own validated
authored layout; no development test-map ID is treated as Launch Works.

`protocol/vehicle.rs` owns strict vehicle state. `Snapshot.vehicles` is empty
and omitted on ordinary maps. One jeep has a positive u32 `id`, `kind: jeep`,
ground-base `position: [x,y,z]`, server `yaw`, signed `speed`, vertical `vy`,
`hp` (0 to 400),
nullable `driver` and `gunner` IDs, `gun_heat` (0 to 1), `burning_ticks`
(0 to 40), and `control_ready_tick`. There are at most 32 vehicles. Occupancy derives from this one list.
`Action.seat` optionally requests `driver` or `gunner`. Existing interact enters
or exits; movement fields drive and existing aim/fire operates the mount.
Vehicle facts require capability 39; Conquest requires 40 and the current
water island requires 41. The client and server share latest capability 41.

The jeep is 3.8 by 1.9 metres, top speed 16 m/s, reverse at most 6 m/s.
Entry and exit require at most 2 m/s. Seat changes take ten ticks. Driver feet
are local (0.20, 0.65, -0.40), gunner feet (-0.65, 0.95, 0), with +X forward.
The mounted gun uses existing Flechette traces and authoritative hit resolution
with a separate heat budget; no seventh inventory weapon or ammunition pool.
Optional `ShotTrace.vehicle_id` captures the resolved mount even if its gunner
leaves or dies before the snapshot arrives. Driver reconciliation pairs the
ordinary ACK sequence/tick with that tick's vehicle motion; ordinary pawn
movement remains unapplied while seated.
Occupied actors do not integrate ordinary walking or fire handheld weapons.
The client mirrors the pure kernel and reconciles the driver from matched
snapshot/ACK ticks. Seven shared vectors pass both implementations, with
maximum client error 0.00088303. The client has separate rendered entry,
drive, brake, mounted-fire and safe-exit receipts.

## Verification and safety

Deterministic tests cover speed bounds, turning, gravity/support, swept wall
stops, denied entry at speed, occupied-seat exclusion, safe/blocked exit,
switch delay, heat and cooldown, exposed occupants, damage/destruction,
disconnect/death/reset and capability boundaries. Shared movement golden
vectors support a separate client mirror. A live socket session and rendered
driving/gunning evidence are required for playable acceptance. The client
validator rejects malformed facts before building scenes. The latest-world
queue preserves seat, HP, burn-phase and control-lock changes while replacing
quiet vehicle motion and cooling, covered by a moving-jeep queue test.
Tests and local work cost $0. Asset generation stays with the existing
bounded production pipeline; this code adds no paid calls.

## Acceptance

A player walks up, enters, drives, parks, switches to the mount, shoots a target,
exits safely and continues on foot. Another player can gun while the first
drives. Losing or leaving a jeep does not strand a fighter or leak a seat.
The island remains playable on foot. M14 story completion and human vehicle feel
remain open until separately inspected and played.

## Local evidence and boundaries

The focused native run passed nineteen vehicle and queue tests. Native
tests cover ordinary action entry, driving, stopping, switching, safe exit,
mounted trace identity after departure, suppression of handheld/device fire,
dead-seat removal, burning destruction, blocked exit, full seats, unattended
wreck return, hostile runover and friendly-body stops. The pure kernel tests
cover bounds, speed, brake, support, heat and oriented shot geometry.
Additional negatives cover stale input sequences, matched vehicle ACK ticks,
control locks, blocked boarding and exposed-occupant ceiling clearance.

Holdfast registers three jeeps; the subsequent
[water and flight slice](island-watercraft-flight-20261006.md) adds boats and
an aircraft. Launch Works placement awaits its
validated development layout. Empty, displaced or destroyed vehicles return
after 600 unattended ticks only when their registered spawn is clear. A burning
vehicle attempts safe ejection at the end of its warning. An occupant with no
legal exit is destroyed in place, so wrecks cannot hold a living seat forever.
Arcade chassis movement remains upright, with gravity and stepped ground
support. Roll physics, boats and aircraft are outside this slice. Vehicle
runover uses shared health/frag resolution; dedicated vehicle record counters
are not added to existing gun or grenade statistics.

## Composed collision and navigation review

The native walking world now retains live vehicle hulls and buoyant support
through actor-contact projection. Snapshot collision eligibility excludes seated
occupants, and runover checks use each victim's actual stance height. Boarding
and exit sweep a whole standing body through cover and other chassis, with the
occupied chassis excluded. The client retains the same hull history and water
support for bounded replay.

The seven-map actual movement gate exposed a parked aircraft that short local
avoidance could not pass. The existing bounded route search now filters cached
edges and endpoint connections against current physical obstacles, without
building topology on a tick or changing its search allowance. Temporary hulls
also invalidate blocked route segments. Verification includes a temporary wide
hull, overhead clearance, finite search work, obstacle removal, and every native
spawn-to-centre and centre-to-supply route with the actual registered fleet.
The composed movement, boarding and seven-map network roster checks pass. Final gate and measurement results are recorded in [native quality evidence](../evidence/native-island-quality-20261006.md).
