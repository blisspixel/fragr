# Holdfast boats and light aircraft

Status: **implemented**, 2026-10-07. Nick explicitly requested real water,
usable boats and flyable aircraft on the original island. This work advances
those vehicles ahead of the M14 practice battlefield.

Use the existing authoritative vehicle list, Action input, seat lifecycle,
damage and bounded delivery. Extend vehicle kind with `boat` and
`light_aircraft`. The boat has driver and exposed gunner seats, bounded
surface movement and registered water support. The light aircraft has one
driver, ground taxi, speed-dependent lift, climb/descent, safe landing,
stall descent, a world ceiling, swept collision and fatal water contact.
The current movement state remains position, yaw, speed and vertical speed.
Aircraft attitude is upright arcade physics; bank/propeller presentation
must not change collision authority.

Root island work owns strict map water regions, coastline collision,
safe infantry boundaries and rendered water. Vehicle code samples those
same registered regions. Dry land never becomes boat support. The client
mirrors each pure movement kernel and matches new shared golden vectors.
No new transport, input channel, runtime service or paid operation is added.

Tests cover water boundaries, depth, walls and shoreline refusal; boat entry,
driving, stopping and dock exit; plane taxi, takeoff, turn, ceiling, stall,
landing and crash; hostile damage and seat release; and bounded snapshot
delivery during movement. A real socket driving/flying pass and rendered
motion are required independently of kernel tests. The composed client has
rendered boat and aircraft input receipts, including a soft landing, taxi,
braking and safe exit. Original source-model preparation and water rendering
have separate inspected receipts; human feel is not established by automated
routes.

Initial native evidence: 28 vehicle tests and three swimming tests pass,
including the full registered fleet, actual island boat entry/drive/exit,
aircraft takeoff/water crash, blocked destruction and return to swimming.
The six swimming vectors match the client within 0.00000057; the eighteen
jeep, boat and aircraft vectors match within 0.00088303, below the unchanged
0.001 tolerance. The shoreline regression exposed and fixed missing buoyant
ground support, so a swimmer can step back onto land through the existing
collision rule. These checks do not establish renderer quality or human feel.

The native boundary, Conquest fairness, strict adapter and same-binary 16/64
rule-bot CPU results are recorded in
[native island evidence](../evidence/native-island-quality-20261006.md).

The later [October 7 rendered route](../evidence/vehicle-played-20261007.md)
completes boat driving, mounted fire and swimming exit, plus aircraft takeoff,
soft landing, taxi and safe exit through ordinary live input. The final driver
seat preserves the canopy frame and clears the forward view. Capture-related
prediction fallbacks are recorded separately from uninterrupted driving.
Human flight feel, cockpit detail and wider match acceptance remain open.
