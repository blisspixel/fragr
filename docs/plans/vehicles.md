# Vehicles

**Status:** in flight, 2026-10-06. Jeep, boat and light aircraft have local
server and client implementations on Holdfast Atoll. Motorcycle is an inspected
source only. Jetpack and the campaign placements below remain planned. Composed
verification, rendered driving and human acceptance remain distinct gates.

**Spend:** $0 new cash for implementation. The separate
[source batch](vehicle-assets-20261006.md) records approved prepaid asset usage.
No new generation, renewal, top-up or overage is authorized by this plan.

Nick advanced island and vehicle work on October 6, including boats and flight.
The [full build order](../ROADMAP.md#full-build-order) remains the single sequence.
This umbrella plan records scope; bounded implementation and evidence belong to
the [jeep authority](jeep-authority-20261006.md),
[watercraft and flight](island-watercraft-flight-20261006.md),
[client](vehicle-client-20261006.md),
[water rendering](island-water-rendering-20261006.md) and
[Conquest](holdfast-conquest-20261006.md) plans.

## Goal and current scope

Walk up, use a seat, drive, park, switch to a mount where fitted, then leave and
keep fighting. Vehicles open routes and firing positions. Walking remains
available, and losing a vehicle must not make a mission unwinnable.

| Type | Local implementation | Remaining work |
|---|---|---|
| Jeep | Two seats, ground movement, driver prediction, exposed occupants and mounted heat gun; three registered on Holdfast. Rendered driving, mounted fire and safe exit pass. | Network feel, human acceptance and campaign placement. |
| Boat | Two seats, registered-water support, surface steering and braking, mounted heat gun and swimming exit; two on Holdfast. Rendered motion, mounted fire and swimming exit pass. | Dock usability and human acceptance. |
| Light aircraft | One driver, taxi, speed-dependent lift, climb/descent, stalls, ceiling, landing and crashes; one on Holdfast. Rendered takeoff, soft landing, taxi and safe exit pass. Upright arcade transport without a mounted weapon. | Cockpit detail, flight feel and human controls review. |
| Motorcycle | Inspected original source model. | Runtime preparation, single-seat movement, collision, controls and played proof. |
| Jetpack | Planned personal movement item. | Inventory/fuel contract, shared movement and prediction, presentation and played proof. |

Tanks, simulation suspension, part damage, destructible terrain and persistent
vehicle unlocks are outside this work. Motorcycle speed, durability and weapon
use, and jetpack fuel/thrust tuning, remain design decisions rather than current
game rules.

## Shared architecture

`server/src/vehicles.rs` and `vehicles/water_air.rs` own pure movement and hull
geometry. `sim/vehicle.rs` owns seats, safe entry and exit, mounted fire, damage,
destruction and unattended return. The ordinary simulation resolves hits and
blasts. Vehicle occupants skip walking integration and follow server seat facts.
The client never decides occupancy, damage, collision or capture progress.

The existing `Action` carries movement, aim, fire and Use. Optional `seat`
requests driver/gunner changes where supported. Jeep and boat Jump brakes;
aircraft Jump climbs and Duck descends. Switching has an authoritative control
delay. Entry and exit require low speed and a legal reachable body position.
The composed review found eye-ray passage checks could cross low barriers.
Boarding and exit now sweep a body through the existing geometry seam. Six
regressions cover low cover, overheads, other hulls, dock return and aircraft
access; all six pass in the composed native vehicle filter. Scoped formatting,
documentation links and whitespace checks pass.
Destruction has a warning before safe ejection and a shared blast; a blocked
occupant cannot remain alive inside a wreck indefinitely.

`Snapshot.vehicles` is the single occupancy source. The feature contracts were
introduced at capability 39 for jeeps, 40 for Conquest and 41 for registered
water, boats and aircraft. Shared arcade rooms require the current version, 41.
Driver prediction mirrors the native kernels and reconciles matched snapshot
and input-acknowledgement ticks. Other vehicles interpolate. Swimming uses the
same registered water as hull support; visual waves never affect outcomes.

Humans and external agents can issue the same seat and driving actions. An
autonomous route-driving controller, validated drive lanes and automatic allied
seat use are not implemented. Rule bots currently fight and capture on foot.

Current collisions stop against world geometry and bodies; fast impacts can
damage the moving vehicle. Runover resolves hostile damage through the shared
combat rules and stops at friendly bodies. Symmetric vehicle collision damage,
roll physics and sophisticated enemy reactions to approaching vehicles remain
outside this slice.

## Presentation

Prepared jeep, boat and aircraft models use compact nearest-filtered pixel
paint. Local preparation registers wheels, seats and the aircraft propeller;
the client retains a bounded fallback. Source completion is not motion or art
acceptance. Geometry, occupant alignment, cockpit visibility and motion must
agree with the authoritative hull and seat contract.

The current client provides seat-specific controls and vehicle state, first
person seating, mechanical audio and remote vehicle interpolation. A chase
camera, jetpack gauge and motorcycle presentation remain future work. Original
repaired civilian and coalition equipment and issued Union variants follow the
[art and story bible](../ART_STORY_BIBLE.md).

## Planned campaign placements

- **M14 jeep:** the optional rover circuit across depot, berm and gantry. The
  [development level](m14-vehicle-development-20261006.md) is planned, not a
  completed campaign mission. Validate explicit authored placement and infantry
  approaches before adding the Walker and mission completion.
- **M16 motorcycle:** the civic transit approach from staging to the foothold.
  Checkpoints and patrols must also permit the foot route, without a timer or
  required escort. Neither the vehicle runtime nor this placement is built.
- **M19 jetpack:** optional roof and waterworks routes during the changed-streets
  phase. The ground route must work. Item, mission placement and movement remain
  planned; any gravity change requires new shared movement evidence.

No vehicle adds a campaign door. Each mission keeps at most three.

## Verification and acceptance

The linked plans retain actual commands and receipts. Local evidence includes
native seat, reset, damage, water and flight tests, eighteen vehicle motion
vectors and six swimming vectors shared with the client. Headless ordinary-input
jeep and boat loops have exercised driving, braking, mounted fire and safe exit.
These checks do not establish flight feel, rendered quality or human enjoyment.

The later [October 7 rendered receipt](../evidence/vehicle-played-20261007.md)
records completed jeep and boat control loops and the centered-seat aircraft's
takeoff, soft landing, taxi and safe exit. Capture-related prediction fallbacks
are retained with their timing evidence. Cockpit detail and wider human driving
acceptance remain provisional.

Before playable acceptance, complete the composed native and client gates and
inspect ordinary-input motion for boarding, driving, gunning, swimming exit,
takeoff, landing and destruction. Record correction measurements independently
of renderer cost. The water renderer measurement and actual rule-bot CPU
measurements remain separate from vehicle-heavy match and network evidence.

Each future campaign placement must clear with the vehicle, without it and
after losing it. Multiplayer must preserve infantry access and fair capture.
Success is readable controls, stable local driving and useful optional routes,
with no seat leak or vehicle loss that blocks continued play.
