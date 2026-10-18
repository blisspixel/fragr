# All Systems Normal connected Recovery Square transit corridor

Status: **in flight**, 2026-10-17. Follows [m17-connected-office-20261017.md](m17-connected-office-20261017.md). This document defines the campaign increment in the [Full build order](../ROADMAP.md#full-build-order) and implements the accepted [level 18 brief](../campaign/m10-all-systems-normal.md#level-18-design-twenty-level-expansion). Spend for this increment: $0, using existing assets and local tools only.

## Goal and limits

Build connected **M18: All Systems Normal**: the Episode V opening across Recovery Square and the evacuation transit corridor. Implement the relief depot check-in, the synchronized bot diagnostic rupture and perimeter defense in Recovery Square, the Collector breach sealing the clinic avenue with concrete roadblock rubble, the maintenance flank bypass and stair tower ascent, the Upper Overlook console access surveying the planetary wipe horizon, the Evacuation Concourse defense against heavy security detachments, and the departure through the transit gate toward M19 Planned Works.

Arrival continues directly from M17's Forever Office conclusion, carrying the saved coalition party forward into Episode V. Continues refill to three at Episode V start (M18 entry). Completing M18 promotes into pending, unbuilt `planned_works` (M19), carrying all challenge outcomes without another episode refill.

This is a connected development mission, not an acceptance of final exterior kit art, fresh-player pacing, or finished Episode V. Existing enemy AI timings remain unchanged.

## Inspected starting point

The level 18 brief establishes:
- Recovery Square with civilian aid depot counter, relief tents, and cargo stacks.
- Diagnostic rupture event waking defensive bot swarms.
- Collector breach blocking the primary clinic avenue with heavy roadblock rubble.
- Maintenance flank alley with industrial transformers and stair tower.
- Upper Overlook commanding views of the planetary wipe event.
- Evacuation Concourse with turnstiles, pillars, and departure gates.

Current reusable systems:
- `server/src/sim.rs`, `sim/combat.rs`, and enemy controllers (Clerk, Sweeper, Heavy Sweeper, Notary, Turret, Auditor, Enforcer, Assessor).
- `server/src/mission.rs`, authored mission definitions in `maps/authored/`, and `mission/controller.rs`.
- `server/src/mission/run_file.rs` owning versioned saves (upgraded to version 22).
- Godot thin presenter architecture in `client/scripts/`.

## Bounded implementation and ownership

### 1. Spatial Sequence and Objectives
All Systems Normal features 6 sequential objectives:
1. **`aid_checkin`**: Interact with the relief depot counter at Recovery Square (`depot_station`).
2. **`square_defense`**: Defend Recovery Square and eliminate the initial ruptured bot uprising (`square_uprising`).
3. **`collector_breach`**: Advance to the clinic roadblock and clear the Collector heavy escort (`collector_escort`), triggering the rubble barrier world.
4. **`service_ascent`**: Flank through the maintenance alley and ascend the service stair tower (`stair_ambush`).
5. **`overlook_recon`**: Access the Upper Overlook survey console (`overlook_console`) and eliminate overlook sentries (`overlook_sentries`), observing the planetary wipe horizon.
6. **`concourse_evac`**: Fight through the concourse defenses (`concourse_defense`) to the evacuation gate.
Departure: Board the evacuation transit gate (`party_departed`).

### 2. Prepared Worlds and Dynamic Geometry
The map loader precomputes three prepared world variants:
- **World 0 (Initial):** Open avenue, clear transit corridor.
- **World 1 (Ruptured):** Roadblock rubble barrier active at the clinic avenue (`roadblock_rubble` solid present, blocking direct avenue passage and forcing the maintenance flank).
- **World 2 (Concluded):** Concourse departure gate unsealed for party extraction.

### 3. Mission Controller and Protocol Shapes
Implemented in:
- `server/src/protocol/m18.rs`: `M18MapGeometry`, `M18ChallengeState`, `M18ObjectiveState`, `M18_OBJECTIVE_IDS`.
- `server/src/maps/authored/m18.rs`: Authored map verification and navigation registration.
- `server/src/mission/m18.rs`: State progression, encounter gating, and objective advancement.
- `server/src/mission/controller/m18.rs`: Agent-adapter and wire steering.
- Canonical map file: `server/maps/m18-all-systems-normal.json`.

### 4. Persistence and Save Migration (Version 22)
Save file format upgraded to version 22:
- `RUN_FILE_VERSION = 22`.
- `server/src/mission/run_file/legacy_v21.rs`: Strictly upgrades historical version 21 documents, preserving exact historical bytes in archives.
- `server/src/mission/run_file/m18_outcome.rs`: Records completed M18 facts (`aid_delivered`, `square_defended`, `collector_neutralized`, `overlook_witnessed`, `concourse_secured`).
- Completing M17 promotes to `AllSystemsNormal` with an Episode V continue refill to 3 continues.
- Completing M18 promotes to pending `PlannedWorks` on the same continue allowance.

### 5. Client Presentation
Implemented in GDScript:
- `client/scripts/m18_mission_state.gd`: Validates geometry, objective sequencing, challenge consistency, and facts against `M18_ID`.
- `client/scripts/m18_transit.gd`: Visual presenter with warning beacons, barrier markers, departure lights, and feed notices.
- `client/scripts/test_m18_mission_state.gd`: Comprehensive headless test suite verifying all 8 lifecycle stages, contract invariants, and presenter notices.
- HUD, manager, menu, and localization integration in `game_manager.gd`, `mission_hud.gd`, `boot_menu.gd`, `local_match.gd`, `net_client.gd`, and `story.en.po`.
