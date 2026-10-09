# Habitat, launch works and multiplayer composition, October 8

Status: **in flight**, local development on `e4df1a0b`, with existing working
changes preserved. This records the combined verification of the bounded
[habitat map](../plans/m12-habitat-development-20261008.md),
[launch works](../plans/m14-vehicle-development-20261006.md) and
[spawn safety](../plans/vehicle-aware-spawns-20261008.md) work. Publication,
release packaging and human acceptance are separate gates.

## Implemented behavior

Terms of Cooperation has two greenhouse flanks, a maintenance bay, utility
bypass and pumping court, with 15 established enemies and finite supplies.
Its [native and rendered receipt](m12-habitat-development-20261008.md) records
seven native checks and a ten-state ordinary-input human route. Crop art,
pressure glazing, the Arc, Assessor and connected objectives remain unfinished.

Launch Authority develops a freight-lift arrival, depot, motor pool, broad
road circuit, supplied infantry routes and a visible launch gantry. A strict
optional authored fleet uses the existing jeep, seats, mounted fire and reset
seams. Its [level receipt](m14-launch-authority-development-20261008.md) records
the three fleet conditions and independent rendering acceptance.
The loader checks support, exposed occupants, parked hulls, reachable
boarding and required walking routes before readiness. Nonempty fleets are
restricted to static development worlds. Airborne enemy volumes and their gun
approaches are revalidated against the parked fleet, including elevated jeeps.
Ordered vehicle-map encounters leave
later groups unplaced until their predecessor clears. A real session check
boards, switches to the mount and resolves hits against a flying Notary.

Multiplayer admission and respawn use current authoritative collision and
retained vehicle hulls. Fixed bays retain normal stair clearance. Bounded
supported offsets provide alternatives, preserving a team's half when that
map has bays there. A fully blocked participant waits through the existing
respawn timer without a death, shield or respawn event. Shared eligibility
also prevents waiting participants from boarding, driving or mounted firing.
The [network receipt](vehicle-aware-spawns-20261008.md) distinguishes the
earlier fifteen-case regression sweep from the final Holdfast rerun and soak.

These maps use standalone `--map-file` entry, described in
[Playing](../PLAYING.md#standalone-development-maps). They add no campaign
mission identifier, readiness tool, saved-run promotion or completion claim.
The connected campaign retains eleven development prototypes. The Walker,
mission rescues, episode departure and the remaining connected levels are open.

## Composed gates

The standard visual tour and corrected launch-map replay are complete. The
launch replay passes all sixteen states and 66 walking waypoints with clean
logs, twenty kills, no deaths and no HP or armor lost. These checks predate the
subsequent [open-issue work](../plans/open-issues-20261008.md), whose final
composed verification is recorded separately.

| Check | Local result |
|---|---|
| Rust workspace | `cargo test --workspace --locked`: 1,845 passed, zero failed, three existing ignored generator/export checks. |
| Coverage | Frozen-source unfiltered workspace run passes the same 1,845 tests and the 90% floor: 93.30% lines, 75,471 lines with 5,054 missed. |
| Formatting and lint | `cargo fmt --all -- --check` and warnings-denied workspace/all-target clippy pass. |
| Release build | `cargo build --workspace --release --locked` passes. |
| Dependencies | Locked dependency, license, source and advisory checks pass. No dependency was added. |
| CPU benchmark | Final native build passes the deterministic asserted 16-bot, 1,200-tick, seed-42 benchmark. No renderer performance claim. |
| Client | Full checker passes 327 scripts and all 151 harnesses, with clean import/script/runtime logs. |
| Client verifier | All ten injected failure-detection scenarios pass. |
| Standard rendered tour | All 32 states pass with clean logs. All original stills and three effect strips were inspected. Fourteen stills were refreshed; the README initially retained its separately inspected earlier Multiplayer image. Later original-size review confirmed Back is fully visible in the combined frame, correcting the earlier clipping observation. |

The [refreshed gallery receipt](../screenshots/readme-20261008.json) binds the
new standard tour and the retained earlier intake and focused Multiplayer images.
Synthetic grounding is inconclusive from its still; small strip tiles cannot
prove seven separate Scatter impacts. No broader motion acceptance follows.

The final native server SHA-256 is
`8f6d7da7f8889b746024165f42cd361bfdb968001792f81ce7df76aa97f4824d`.
The preceding full-client run used
`07abf53206cd901fe9b0f7ec92bc291884d9a0301809b61e173f99dd4db99bb3`.
The normal tour wrapper rebuilt the native server, and its exact artifact
also passes the deterministic asserted benchmark. These are distinct recorded
artifacts; their owning receipts do not claim byte identity.
Raw combined logs remain in `.agents/parallel-build-20261008/`; owning map and
multiplayer receipts retain their distinct executable and source hashes.

## Retained corrections and limits

The initial combined Rust run failed the launch map's infantry authoring
helper. The corrected helper advances the actual session and enemy controllers,
counts resolved kills, follows reachable routes and acquires active opponents.
It no longer treats the underlying simulation tick alone as an enemy combat
clear. The earlier failure remains in `workspace-tests.log`.

Independent review also found an elevated parked jeep could overlap a Notary's
hover band because its original validation used the bare world. New strict-loader
regressions first reproduced the accepted overlap, then prove refusal against
the parked world and acceptance at exact legal hull-top clearance. The existing
ground-level map needs no geometry change. Final workspace gates include this fix.
The first coverage attempt for that fix compiled the legal-clearance fixture
before its assumed hull height was corrected to the shared `BODY_TOP` constant.
That owned job was stopped after the fixture failure; `coverage-final.log`
retains it. The final frozen-source coverage run is `coverage-composed.log`.

The launch work also corrected a stair-mouth collision, added visible physical
perimeter rims, and moved existing arrival ammunition behind cover after a
rendered human run died before reaching the next stock. The habitat's initial
direct waypoint crossed a cultivation bed and was replaced with the real
cross-passage. The spawn suite caught a fixed-bay stair compatibility regression;
the final check preserves its existing step allowance. No acceptance threshold
or assertion was weakened to admit these changes.

A launch repeat later exposed three apron stocks inside the final encounter's
activation region. Their unchanged quantities moved to the west side of that
region, with an ordinary approach below the freight blocks. Native and mirrored
walking regressions prove the held-fire resupply approach cannot awaken the
final guards; the explicit final push does. The final rendered route passes
cleanly. Earlier incomplete runs and the first completed route's Compatibility
shutdown warnings remain in the owning receipt.

The full client checker, map captures and multiplayer soak retain their own
executable hashes. The subsequent
strict authored-hover correction does not change either map's geometry or
built-in multiplayer. Mars presentation and direct launch-route regressions
run through the same registered client checker.

Automated aim, screenshots and same-machine network checks do not establish
fresh-player fun, difficulty balance, final art, target campaign duration,
physical LAN behavior, rendered hardware performance or large-server capacity.
The active sequence remains the roadmap's single full build order.

## Spend

$0 new cash, zero paid asset calls. Existing committed assets supply both maps.
Nick's reported $4.65 Higgsfield balance and included audio/model quotas remain
available for later bounded production. No top-up, overage or cloud work ran.
