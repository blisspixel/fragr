# Shared authoritative jeep

Status: **in flight**, 2026-10-06. Nick explicitly requested the original island
and campaign vehicle work in this development round, advancing the staging in
[vehicles](vehicles.md). No shipped or played claim.

## Goal and scope

Make the same two-seat jeep driveable on Holdfast Atoll and the Launch Works
development battlefield through the ordinary action channel. Walking remains
available. This slice includes bounded arcade movement, safe entry/exit,
driver/gunner switching, mounted heat fire, damage and vehicle reset. Boats,
aircraft, motorcycle, jetpack and finished M14 story acceptance remain separate.

## Architecture and wire

`server/src/vehicles.rs` owns the shared pure movement kernel, geometry probes
and entities. A narrow simulation bridge owns seats, actor lifecycle, shared
hitscan/blast resolution and reset. Root map work registers validated jeep
spawn positions for runtime map IDs 7 (Holdfast) and 1014 (Launch Works).

`protocol/vehicle.rs` owns strict vehicle state. `Snapshot.vehicles` is empty
and omitted on ordinary maps. One jeep has a positive u32 `id`, `kind: jeep`,
ground-base `position: [x,y,z]`, server `yaw`, signed `speed`, vertical `vy`,
`hp` (0 to 400),
nullable `driver` and `gunner` IDs, `gun_heat` (0 to 1), `burning_ticks`
(0 to 40), and `control_ready_tick`. There are at most 32 vehicles. Occupancy derives from this one list.
`Action.seat` optionally requests `driver` or `gunner`. Existing interact enters
or exits; movement fields drive and existing aim/fire operates the mount.
Vehicle maps require capability 39; the combined island mode is allocated 40.
The root integration owns the final latest-version change after client support.

The jeep is 3.8 by 1.9 metres, top speed 16 m/s, reverse at most 6 m/s.
Entry and exit require at most 2 m/s. Seat changes take ten ticks. Driver feet
are local (0.55, 0.65, -0.40), gunner feet (-0.65, 0.95, 0), with +X forward.
The mounted gun uses existing Flechette traces and authoritative hit resolution
with a separate heat budget; no seventh inventory weapon or ammunition pool.
Optional `ShotTrace.vehicle_id` captures the resolved mount even if its gunner
leaves or dies before the snapshot arrives. Driver reconciliation pairs the
ordinary ACK sequence/tick with that tick's vehicle motion; ordinary pawn
movement remains unapplied while seated.
Occupied actors do not integrate ordinary walking or fire handheld weapons.
The client mirrors the pure kernel and reconciles the driver from matched
snapshot/ACK ticks. Seven shared vectors pass both implementations, with
maximum client error 0.00088303. Live rendered acceptance is still required.

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
Both maps remain playable on foot. M14 story completion and human vehicle feel
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
