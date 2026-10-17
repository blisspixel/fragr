# Freedom of Movement connected avenue

Status: **planned**, 2026-10-17. Follows [m15-connected-stadium-20261015.md](m15-connected-stadium-20261015.md) shipped in v0.86.0. This document refines the next campaign increment in the [Full build order](../ROADMAP.md#full-build-order) and implements the accepted [level 16 brief](../campaign/l16-freedom-of-movement.md). Spend for this increment: $0, using existing assets and local tools only.

## Goal and limits

Build connected **M16: Freedom of Movement**: the ceremonial avenue charge from the stadium's ceremonial gate to the Forever Office forecourt. Implement the motorcycle mechanic with high-speed weaving evasion against Notary bursts, the Green Wave traffic signal sequence, the transit station foot fallback with the prison bus rescue, the dismounted forecourt battle over the civic fountain, and the foothold arrival at the closed Forever Office chamber doors.

Arrival continues directly from M15's ceremonial gate departure, carrying the saved coalition party forward into the night assault. Continues remain shared within Episode IV (no episode refill; refilled at M15 entry). Completing M16 promotes into pending, unplayable `peace_without_interruption` (M17).

This is a connected development mission, not an acceptance of final avenue kit art, fresh-player pacing, or finished Episode IV. Existing enemy AI timings remain unchanged.

## Inspected starting point

The [October 9 graybox](m16-freedom-of-movement-20261009.md) created `server/maps/test/m16_freedom_development.json` (map 1016). Its integration test (`server/tests/m16_development.rs`) proves parsing, static geometry, and walking routes across landmarks (`ride_start`, `side_pocket_barricade`, `side_pocket_checkpoint`, `side_pocket_transit`, `forecourt`, `office_threshold`).
The graybox has no motorcycle entity, no mission controller, no save promotion, no dynamic gate lifting, and no connected departure.

Current reusable systems:
- `server/src/sim.rs`, `sim/movement.rs`, and vehicle handling in `sim/jeep.rs`.
- `server/src/encounters.rs` and enemy controllers (Notary, Clerk, Turret, Enforcer, Heavy Sweeper, Assessor).
- `server/src/mission.rs`, authored mission definitions in `maps/authored/`, and `mission/controller.rs`.
- `server/src/mission/run_file.rs` owning versioned saves (current version 19).
- Godot thin presenter architecture in `client/scripts/`.

## Bounded implementation and ownership

### 1. Motorcycle Foundation
Add the motorcycle through the server's authoritative vehicle subsystem:
- High-agility single-rider vehicle: 14.0 m/s top speed, rapid linear acceleration, tight angular turning, and authoritative swept-cylinder collision.
- The player mounts and dismounts with the standard `Use` action.
- The motorcycle carries no mounted gun. Dodging and weaving past committed Notary burst fire is the verb.
- Jumping over toppled barricades and launching off grandstand ramps uses heightfield and ramp kinematics.
- Taking critical damage disables the motorcycle, forcing the player onto foot.

### 2. The Green Wave Infrastructure Event
The subtle first manifestation of the Inheritance in urban infrastructure:
- Mid-avenue trigger: Crossing the primary checkpoint activates the Green Wave sequence.
- Sequential signal lights along the axial avenue cycle to green.
- Heavy automated security gates lift automatically on their own schedule without player intervention.
- Audio / narrative bark: Mara radios over the coalition frequency: "That wasn't us." Nobody answers.

### 3. Transit Station & Prison Bus Rescue
The intact foot route if the bike is lost or bypassed:
- Side transit pocket featuring a Union prison transport bus guarded by two Clerks.
- Eliminating the guards and interacting with the bus emergency release unlocks the doors, committing the `transit_bus_freed` mission fact.
- Rescued prisoners disembark and move autonomously toward the rear avenue crowd. No escort chore, no fail state.

### 4. Forecourt Assault & Foothold Climax
Dismounted combat before the grand civic fountain:
- Forecourt defenders: Enforcers dug into the entrance steps, Turrets in the portico arches, a Heavy Sweeper in the center aisle, and an Assessor drone hovering over the fountain.
- Eliminating the defenders secures the forecourt.
- Moving to the entrance terrace establishes the `office_foothold` arrival state at the sealed Forever Office doors.

### 5. Mission Controller and Protocol Shapes
Create `server/src/protocol/m16.rs`, `server/src/maps/authored/m16.rs`, `server/src/mission/m16.rs`, and `server/src/mission/controller/m16.rs`:
- Map ID: `16`. Canonical map file: `server/maps/m16-freedom-of-movement.json`.
- Prepared worlds: Intact barriers, lifted green wave gates, secured forecourt.
- MapInfo precedes matching mission facts.

### 6. Persistence and Save Migration (Version 20)
- Bump `RUN_FILE_VERSION` from 19 to 20 in `server/src/mission/run_file.rs`.
- Upgrade existing version 2..19 saves strictly, preserving exact historical bytes in archive records.
- Carry forward M15 entrant rescue, booth takeover, and blade usage facts.
- Promote completed M15 saves into playable M16.
- Promote completed M16 saves into pending, unplayable M17 (`peace_without_interruption`).
- Episode IV continue count carries forward without refill (refill occurred at M15 entry).

### 7. Client Presentation and Internationalization
- Add `client/scripts/m16_mission_state.gd` and `client/scripts/m16_avenue.gd`.
- Present motorcycle camera interpolation, engine audio loop, and speedometer / gear HUD indicators.
- Localize mission briefings, objective updates, and barks in `client/i18n/story.en.po`.

---

## Verification Gates

1. **Rust fmt & Clippy:** `cargo fmt --check` and `cargo clippy --workspace --all-targets -- -D warnings`.
2. **Unit & Integration Tests:**
   - `server/tests/m16_connected.rs` verifying full route, motorcycle controls, green wave trigger, bus rescue, and forecourt assault.
   - `server/src/mission/run_file/migration.rs` verifying v2..v19 strict upgrade to v20.
3. **Headless Godot Check:** `tools/godot_check.sh` passing all client scripts and harnesses.
4. **Package & CI Verification:** Standard local CI pipeline passing 100%.

## Spend and Safety

- Total cash spend: $0.
- Reuses existing models, audio, and textures.
- Zero AI attribution anywhere. Nick Seal strictly author.
