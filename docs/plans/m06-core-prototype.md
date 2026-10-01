# M06 core prototype

**Status:** in-flight, 2026-10-01. Parent scope:
[M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** $0. No paid calls, dependencies or new control channel.

## Goal and boundary

Implement the static lunar-port mission through the existing authoritative
mission, encounter, inventory, navigation and local-control seams. Preserve
M01-M05 authored bytes, rules revision 3 and all existing combat timings.
Save version 7, historical migrations, episode refill, local process ownership
and external readers belong to the parent lane.

## Contract

Map 1006 and `port_of_entry` require capability 27. Geometry has six ordered
Arrival objectives, a `prisoner_route_marked` service Arrival, registered
departure Use target, boarding region and supported companion start. Required
groups are freight_ingress, rail_lane, loading_heavy, turret_intro, customs_hold
and exit_watch. Optional service_branch follows loading_heavy without becoming
a required predecessor. Future groups remain absent until their prerequisites
clear. The marker requires the optional clear and a living ready participant
inside its actual registered region.

Mission facts expose the completed prefix, current objective, optional marker,
and immutable carried recall cars, patients, photograph count, released workers
and evacuated workers. Released workers remain distinct from passengers.
Historical car and patient identities retain the existing bounded save contract
(up to four unique valid identifiers), including legitimate older fixtures.
Worker identities use the three registered M05 identifiers, with evacuated
workers restricted to the released set. The optional marker cannot precede the
third required objective.
Departure requires all living ready party members aboard and a fresh physically
aimed Use after all required encounters. Retry resets local objectives, marker,
guards and limited companion support while retaining earlier outcomes.

`inspection_glass` is permitted only on M02/M06 registered solid surfaces,
never ground. One static navigation topology is prepared before readiness.
The open dock bulkhead never becomes a moving collision world. Ten bounded M06
decoration kinds register authored signs and departure, without resource paths.

Latch uses existing finite support and following. The registered rail_lane and
turret_intro enemies receive no companion fire, preserving both player lessons.
Rail spread and range remain unchanged: a seeded real long-lane hit does not
prove every imperfect aim succeeds. Dormant guards do not acquire patrol merely
from an authored placement. No fresh-player pacing or full difficulty brief
acceptance is inferred from accurate-aim tests.

## Ownership and verification

Core modules: protocol/m06, maps/authored/m06, mission/m06 and
mission/controller/m06, their existing glue, registered decoration kinds,
encounter staging, companion support, server CLI and focused M06 tests.
Parent owns persistence, recovery, local.rs, run admission and shared readers.
Map lane owns JSON and route captures; client lane owns strict Godot mirrors.

Verify strict unknown fields, exact prefixes and targets, stale-map barriers,
carry identity/subset/immutability, optional independence and retry reset,
multi-participant departure and no spectator progress. Test actual finite Rail
and Turret shots, real glass cover and supported movement. Coordinate focused
checks during edits; parent serializes complete gates and rendered tours.

## Evidence

Research confirmed existing Turret 100 HP, Standard 26-tick charge, front
acquisition, cover cancellation and once-per-cycle heavy-hit interruption.
Rail remains 80 damage, 60-metre range and 0.012-radian spread. Existing
heavy_turret tests remain the foundational timing evidence.

The focused server command `cargo test -p fragr-server --lib tests::m06 --locked`
completed on 2026-10-01 with 15 passed and one failed route preflight. Its log is
`.agents/m06-buildout-20261001/core-focused-final.log`. All ten core tests passed:
strict authoring and wire refusal, stale-map and immutable carry boundaries,
ordered absent future guards, optional actual arrival, whole-party departure,
finite discovered Rail cells and real misses, glass shot and grenade collision,
companion lesson exclusions, socket admission for all three roles, and the real
authored Turret charge, resolved shot, cover cancellation, interruption and rear
flank. Three parent persistence tests and two map checks also passed.

The remaining map check caught the declared loading-recovery segment crossing
the recovery locker/gallery stairs. The map lane added a ground detour below
the obstacle without changing map geometry or weakening the preflight. Parent
verification must rerun that route and all complete gates. Core Rust source is
frozen for those checks. Rendered mission acceptance, fresh-player pacing and
cross-difficulty acceptance remain pending.

Independent read-only review found no consequential defect in the integrated
strict historical v6 decode, exact source-byte archive, replacement failure
path, M05-to-M06 promotion, retry restoration, live exit projection or shared
reader dispatch. The episode refill exists only on the completed M05 promotion
edge, while reopening the M06 entry preserves spent continues. The new native
child fixture also checks actual carried body, HP, armor, ammunition, grenade
count, outcomes and a single historical archive across reopening; its execution
belongs to the parent's matching-binary verification.

The matching-binary verification now passes the native child fixture, all
1226 workspace tests and unfiltered 94.12 percent workspace line coverage.
Formatting, warning-denied clippy, full release build, license checks,
deterministic benchmark, six mixed-map rosters, contested CTF and the
120-second soak also pass. Exact receipts and measurement scope live in the
[parent plan](m06-port-of-entry-prototype.md#completed-engineering-gates).
The subsequent strict map preflight passes all 144 final ordinary route
segments. No earlier failure is removed from the evidence record.

The third rendered mission attempt independently observes the real named
Turret firing, then a distinct charge cancelled by actual cover: blocked,
in-range Windup at tick 3108, early twelve-tick Recovery at 3109, unchanged
enemy HP and no named resolved shot through the original deadline 3129,
verified through tick 3130. That attempt later fails the required rear-flank
death gate after the QA driver steers off a correctly climbed gallery. This
is partial combat evidence, not a completed mission tour. The driver fix and
full ordinary-input departure remain pending in the presentation lane.
