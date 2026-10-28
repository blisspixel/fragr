# Peace Without Interruption connected Forever Office

Status: **in flight**, 2026-10-17. Follows [m16-connected-avenue-20261017.md](m16-connected-avenue-20261017.md). This document defines the campaign increment in the [Full build order](../ROADMAP.md#full-build-order) and implements the accepted [level 17 brief](../campaign/l17-peace-without-interruption.md#level-17-design-twenty-level-expansion). Spend for this increment: $0, using existing assets and local tools only.

## Goal and limits

Build connected **M17: Peace Without Interruption**: the Episode IV climax inside the Forever Office. Implement the entry breach through the chamber doors, the battle through the tiered Assembly Hall under its grand dome, the sweep of the administrative ring with the custody of Registrar Kessel, the command galleries with city overlook, the breach of the security core with its defensive turrets and heavy units, the confrontation in Chancellor Voss's private chamber where she is taken alive, and the departure through the liberated public hall into Episode V.

Arrival continues directly from M16's foothold departure, carrying the saved coalition party forward into the Forever Office. Continues remain shared within Episode IV (no episode refill during M17; refilled at M15 entry). Completing M17 concludes Episode IV and promotes into pending, unbuilt `all_systems_normal` (M18), granting the Episode V continue refill to 3 continues.

This is a connected development mission, not an acceptance of final interior kit art, fresh-player pacing, or finished Episode IV. Existing enemy AI timings remain unchanged.

## Inspected starting point

The [October 9 graybox](m17-peace-without-interruption-20261009.md) created `server/maps/test/m17_forever_office_development.json` (map 1017). Its integration test (`server/tests/m17_development.rs`) proves parsing, static geometry, and walking routes across landmarks (`civic_approach`, `occupied_public_hall`, `administration_ring`, `command_galleries`, `assembly_chamber`, `frontal_kill_lane`, `flank_bypass`, `later_exit`).
The graybox has no mission controller, no save promotion, no dynamic door lifting, and no connected departure.

Current reusable systems:
- `server/src/sim.rs`, `sim/combat.rs`, and enemy controllers (Clerk, Sweeper, Heavy Sweeper, Notary, Turret, Auditor, Enforcer, Assessor).
- `server/src/mission.rs`, authored mission definitions in `maps/authored/`, and `mission/controller.rs`.
- `server/src/mission/run_file.rs` owning versioned saves (current version 20).
- Godot thin presenter architecture in `client/scripts/`.

## Bounded implementation and ownership

### 1. Spatial Sequence and Doors
The Forever Office features three authoritative door states:
1. **Chamber Doors:** Threshold from the civic approach into the occupied assembly hall. Open at mission start.
2. **Core Seal:** Heavy security barrier between the command galleries and the security core. Unlocks once the administration ring and gallery defenders are cleared.
3. **Secured Chamber Doors:** Blast doors protecting Voss's inner executive office. Unlocks once the security core defense is neutralized.

### 2. Registrar Kessel Custody
In the administrative ring committee room, Registrar Kessel (whose signature authorized the civilian recalls) stands at his desk. Interacting with the desk panel secures the custody forms and commits the `kessel_custody` challenge fact without violence.

### 3. The Security Core Breach
The final combined combat set piece before the Chancellor:
- Turret batteries in flanking alcoves, an Assessor overhead, a Heavy Sweeper holding the central dais, and an Auditor maintaining repair channels.
- Defeating the security core defense deactivates the inner perimeter and opens the secured chamber doors.

### 4. Chancellor Voss Confrontation & Surrender
Inside the secured chamber:
- Chancellor Voss stands before the executive screen still displaying "Continuity assured".
- Her composure cracks into cold, quiet anger; she does not shout or switch languages.
- Interacting with the command terminal places her into custody (`voss_captured`).
- Latch remarks quietly: "That's everyone's."
- The exit route unlocks through the public hall to conclude Episode IV.

### 5. Mission Controller and Protocol Shapes
Create `server/src/protocol/m17.rs`, `server/src/maps/authored/m17.rs`, `server/src/mission/m17.rs`, and `server/src/mission/controller/m17.rs`:
- Map ID: `17`. Canonical map file: `server/maps/m17-peace-without-interruption.json`.
- Prepared worlds: Initial hall, unsealed core, open executive chamber.
- MapInfo precedes matching mission facts.

### 6. Persistence and Save Migration (Version 21)
Upgrade save file format to version 21:
- `RUN_FILE_VERSION = 21`.
- `server/src/mission/run_file/legacy_v20.rs` strictly upgrades historical version 20 documents.
- `server/src/mission/run_file/m17_outcome.rs` records completed M17 facts (`kessel_custody`, `core_defeated`, `voss_captured`).
- Completing M16 promotes to `PeaceWithoutInterruption` with exact resource carry and prior outcomes.
- Completing M17 promotes to pending `AllSystemsNormal` with an Episode V continue refill to 3 continues.

### 7. Client Boundaries
- `client/scripts/m17_mission_state.gd`: Validates geometry, challenge facts, and objective states.
- `client/scripts/m17_office.gd`: Visual presenter for core seal, chamber doors, executive screen notice, and key receipt desks.
- `client/scripts/test_m17_mission_state.gd`: Headless validation harness.
- Update `mission_state.gd`, `net_client.gd` (`GAMEPLAY_VERSION = 53`), `game_manager.gd`, `boot_menu.gd`, `local_match.gd`, `mission_hud.gd`, `player_record.gd`.

## Verification

1. `cargo test --locked` runs unit and integration tests cleanly.
2. `server/tests/m17_connected.rs` validates connected lifecycle from M16 entry, stage transitions, and departure.
3. Save upgrade tests verify strict migration from v20 to v21 without rewinding.
4. Client test harness passes without errors.
5. Benchmark check passes with golden hash match.
