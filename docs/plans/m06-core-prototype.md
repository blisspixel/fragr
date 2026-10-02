# M06 core prototype

**Status:** shipped in [PR #317](https://github.com/blisspixel/fragr/pull/317), 2026-10-02. Strict lunar mission facts, ordered encounters, optional service and real departure are integrated.
Parent integration: [M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** $0. No paid calls, dependencies or new control channel.

Merged in [PR #317](https://github.com/blisspixel/fragr/pull/317), with passing
[final-source CI](https://github.com/blisspixel/fragr/actions/runs/36981473008) and
[package/install checks](https://github.com/blisspixel/fragr/actions/runs/36981473010).
Local gates pass 1244 workspace tests, 94.31 percent unfiltered line coverage and
188 scripts/88 harnesses. The [inspected capture evidence](../evidence/2026-10-01-m06-textures.md)
records the current routes. Source-main CI and desktop publication receipts
are tracked in [release closeout](m06-release-closeout.md). Fresh-player, difficulty,
subjective listening and final character acceptance remain open.

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

The pre-contact matching-binary verification passes the native child fixture, all
1226 workspace tests and unfiltered 94.12 percent workspace line coverage.
Formatting, warning-denied clippy, full release build, license checks,
deterministic benchmark, six mixed-map rosters, contested CTF and the
120-second soak also pass. Exact receipts and measurement scope live in the
[parent plan](m06-port-of-entry-prototype.md#completed-engineering-gates).
The subsequent strict map preflight passes all 144 final ordinary route
segments. These receipts predate the living-body contact increment and are
historical baselines, superseded by the final local receipts below. No earlier
failure is removed from the evidence record.

The third rendered mission attempt independently observes the real named
Turret firing, then a distinct charge cancelled by actual cover: blocked,
in-range Windup at tick 3108, early twelve-tick Recovery at 3109, unchanged
enemy HP and no named resolved shot through the original deadline 3129,
verified through tick 3130. That attempt later fails the required rear-flank
death gate after the QA driver steers off a correctly climbed gallery. This
is partial combat evidence, not a completed mission tour. The driver correction
subsequently passed its focused tests and the fourth tour's gameplay route.

That fourth tour completed 25 states, all 21 guards and actual departure, with
a measured 52.8996-metre resolved Rail hit and a distinct causally verified
Turret cover cancellation. Its wrapper failed on two shutdown texture leaks.
The focused sky-retention fix passed isolated checks before the final clean
ordinary-input tour following the contact, art and audio freeze. This failed
fourth-run receipt remains separate from the final local verification below.

## Final local verification

The final frozen increment has 1240 passing workspace tests, with zero failures and
three existing ignored tests, plus unfiltered 94.27 percent line coverage.
Formatting, warning-denied Clippy, matching release build and dependency
license/ban/source checks pass. Fourteen matching-release socket, roster, mode,
benchmark and soak cases also pass with unchanged binary hashes; the parent
plan records their measurements and host-load limits. The container build and
unprivileged, read-only, no-new-privileges runtime pass the legal-notice and
`health.status: ok` probes, followed by cleanup in the `wrap-container` receipts.

The corrected ordinary-input tour in `.agents/qa/m06-port-contact-second-final/`
passes all 25 states and all 21 named guards, actual optional marker and shared
departure with clean wrapper and engine exit 0. The record reports zero deaths,
zero HP loss, 45 armor loss and one actual secret supply claim across three
visited locations. Its resolved Rail kill measures 52.015735 meters, separate
from authored initial spacing. Actual blocked Windup 3114 precedes Recovery
3115; no same-Turret shot occurs through original deadline 3135, verified at 3136.

The matching standard tour in `.agents/qa/m06-standard-contact-final/` passes
32 states and publishes 13 inspected stills. The final pinned client checker
passes all 184 scripts and 86 harnesses with clean exit 0 in
`.agents/m06-buildout-20261001/client-whole-contact-final.log`. All owned native
and renderer processes closed. All ten injected fault-verifier scenarios also
pass in `wrap-client-verifier.log`. CI and release remain pending.
Fresh-player clarity, difficulty acceptance, pacing,
subjective listening and final character performance remain open.
