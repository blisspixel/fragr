# Vehicle client presentation

Status: **in flight**, 2026-10-06. Nick explicitly advanced the vehicle and
island work on this date. The campaign target remains
[Launch Authority](../campaign/l14-launch-authority.md), using the existing
[vehicle design](vehicles.md) and its optional walking route.

## Goal and boundaries

Present the first server-owned jeep through the existing match and Action
seams: read a seat, use it, drive or gun, and leave safely. The player must be
able to read the vehicle body, occupied seat, health and gun heat. Preserve
the chunky pixel look, nearest textures, original coalition utility design
and authoritative outcomes. Local fire feedback must never mistake a driver
or mounted gun for a handheld weapon.

The Rust vehicle owner defines exact map placement, Snapshot facts, supported
Action keys and capability floor. The client validates them before emitting
the snapshot, renders bounded interpolated nodes, and follows server seat
positions. Any driving prediction requires the actual Rust motion kernel,
matching golden vectors and explicit reconciliation evidence. Ordinary pawn
prediction cannot stand in for a demonstrated vehicle implementation.

The same round expanded to a utility launch and a flyable single-seat light
aircraft after Nick explicitly requested actual water, boats and planes.
There is no second network channel, client physics authority or mission
progression shortcut. Motorcycle and jetpack remain separate work.
The model presenter retains a clear local fallback until an inspected model
meets runtime geometry and texture budgets.

## Implementation

- Strict `VehicleState` boundary, with bounded arrays, unique vehicle and
  occupant identities, finite coordinates and legal seat/state combinations.
- One world presenter owned by GameManager, with reset on map, role and
  connection changes and shared pixel material conventions.
- Existing Use input enters or exits. Only the server-supported seat request
  is emitted. Occupancy suppresses handheld fire cues, scope and pawn
  prediction. Existing first-person camera follows the server seat.
- A compact vehicle HUD uses authoritative values and context-specific
  controls. No vehicle message covers the aiming area during ordinary play.
- The pure `vehicle_step.gd` mirror and seven Rust-generated motion fixtures
  cover acceleration, reverse steering, braking, a thin wall and falling.
  `VehiclePrediction` reuses the existing bounded replay history, same-tick
  snapshot plus consumed-input ACK pairing, and correction measurements.
  Three ticks is the maximum speculation horizon. Nearby unseated actors and
  other jeep hulls enter the same conservative collision world. Each replay
  step retains its observed blockers rather than replacing history with a
  later world. A seat switch stays neutral until `control_ready_tick`.
- Mounted traces carry optional `vehicle_id`. Their effects use this resolved
  source even after the occupant leaves or dies. Handheld prediction never
  predicts mounted impacts, heat, seats or damage.

The wire capability is 39 for jeeps, 40 for Conquest, and the current joined
client is 41 for registered water, boats and aircraft. Vehicle state includes chassis ground position, yaw, speed,
vertical velocity, health, driver, gunner, heat, burning ticks and the exact
seat-control ready tick. A mounted result remains the existing Flechette
trace, with no extra inventory slot.

All three registered kinds share the twelve-field vehicle facts. The boat's
six support probes require registered water deep enough for its draft. The
aircraft uses explicit throttle, turn, climb and descend inputs; its first
increment is transport-only. The server owns stalls, impacts and safe exits.
`VehicleMediumStep` mirrors the native medium dispatch. The aircraft offers
its single driver seat within six metres, outside its registered wing hull;
the jeep and boat keep two metres. Cached quiet mechanical loops use the
normal Effects audio bus and stop when unoccupied or destroyed.

The reviewed boat source retains 11,884 triangles. The aircraft retains
10,633 source triangles and replaces 1,124 fused nose/propeller triangles with
120 authored triangles, giving 10,753 triangles. The 115 retained windshield
triangles receive clear glass so the actual pilot can see the runway. Its first partial propeller
partition failed rendered inspection and is not selected. The replacement
uses a complete balanced rotor and tapered cowl. Both models use a quantized
512-pixel albedo, nearest filtering and matte material without PBR maps.
Receipts under `client/assets/vehicles/` retain source and prepared hashes,
exact geometry counts and an explicitly open motion acceptance gate.

## Verification

Headless boundary and lifecycle tests, meaningful GameManager ingress/input
checks and inspected render captures. Exercise driver and gunner, entry and
safe-exit refusal, empty/dead vehicle, role changes and reconnect. Confirm
no speculative hits, seat ownership or health changes. Run the full client
checker and publish the visual tour once the composed server build is ready.
Driving feel, real network correction and human island balance remain
separate played acceptance gates.

Focused boundary, lifecycle and ordinary GameManager input checks pass.
The eighteen native motion fixtures pass within 0.001, with a maximum error of
0.00088303. The thin-wall check exposed scalar precision at an expanded f32
collision edge; the client rounds that edge consistently rather than relaxing
the fixture tolerance. The sustained aircraft turn similarly rounds yaw to
the native f32 precision. These deterministic checks do not establish network
driving feel. `qa_vehicle.gd` is the bounded real-input rendered proof through
walking, entering, driving, braking, switching, firing and leaving, followed
by an ordinary capture-point hold.

The initial jeep live run drove 33.875 metres and braked through normal input.
Its 84 same-tick correction samples had a maximum of 0.02 metres with no
fallbacks. The run caught a missing seat field in actual Action serialization;
that path is repaired and tested. This partial run is not the completed
acceptance sequence. The new land height, water, driver stance and all three
prepared models require a fresh composed run.

The composed capability-41 native debug server completed the full Jeep input
sequence in a headless Godot client: ordinary walking and Use boarding,
36.275 metres of driving, braking, seat change, five authoritative mounted
shots, safe exit and Airfield capture. The 84 correction samples peaked at
0.0000000112 metres, with no prediction fallbacks. This is functional loopback
evidence, not rendered driving feel or performance evidence. The QA script
waits for the spectator world reveal before using the normal Join handoff.

The boat also completed its native debug loop: 18.135 metres of surface
motion, held braking, seat change, authoritative mounted fire and a safe
swimming exit. Its 60 correction samples had zero measured drift and no
fallbacks. Rendered motion and pilot acceptance remain separate checks.

The six native swimming fixtures pass at a maximum error of 0.00000057.
The same temporary water-support surfaces as the native movement wrapper
let ordinary collision step up onto shore. A post-step height clamp alone
does not prove that exit path, so the fixtures include an actual shore step.

## Spend and evidence

Client implementation and checks cost $0. Model production remains with the
bounded native asset pipeline and its separate credit receipts. No paid calls
are made by this work item. Live rendered evidence remains in flight.
