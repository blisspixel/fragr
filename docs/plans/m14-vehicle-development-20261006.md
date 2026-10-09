# Launch Authority vehicle development level

Status: **in flight**, 2026-10-08. Island water, boats and aircraft were explicitly
prioritized before this level. This is a practice battlefield for the
accepted [M14 brief](../campaign/l14-launch-authority.md), not campaign
completion or an unlocked episode route.

## Bounded slice

Build the freight-lift arrival, depot infantry defense, captured jeep motor
pool, parked-gunner Notary lesson, broad bermed circuit, infantry cut-through
and gantry defense. The launch gantry remains visible from arrival. Supplies
on both infantry flanks support clearing the field without the jeep or after
losing it. No required door, escort or vehicle timer is added. The Walker,
other-site flares, voiced coalition departure and episode completion remain
explicitly unfinished. Existing enemies retain their established identities;
no ordinary actor is relabelled as the Walker.

Use the existing strict authored discovery-map and ordered encounter seams.
The development file launches through `--map-file`; it does not add a mission
ID, readiness operation, save promotion or campaign unlock. The source map is
named Launch Authority (development). Its map ID may share the historical
1014 test fixture, so vehicle placement must be explicit authored data rather
than inferred from an authored map ID.

## Shared vehicle placement

Add optional bounded `vehicles` placements to the strict authored map. Each
entry has a unique local `id`, `feet` and normalized `yaw`, using the shared
jeep definition. Validate ground support, full exposed-occupant clearance,
other vehicle overlap, and reachable boarding approach before readiness.
Runtime map access supplies placements to the existing reset seam. Authored
vehicle maps require gameplay 39. Built-in Holdfast keeps its registered
placements. Initial load and encounter retry both restore the same fleet.

The first placement boundary supports static development maps only. Nonempty
vehicles alongside any registered mission objective document are rejected, so
staged collision worlds cannot silently inherit unchecked parked vehicles.
Vehicle identifiers share the map's strict namespace; at most 32 placements
are accepted. Boarding validation includes vehicle collision, not only a
route to its occupied center.

## Current implementation slice

`server/maps/test/launch_authority_development.json` is authored reproducibly
by `tools/author_launch_authority.gd`. A raised freight lift faces a 28-metre
gantry. The depot, covered motor pool, broad outer road circuit, alternating
berms, two independent supplied infantry flanks and gantry apron use 119 server
solids. Four 3.6-metre perimeter rims visibly bound the closed development
yard. Five ordered groups contain 20 established enemies and 20 finite supply
placements. The parked jeep faces two flying Notaries for the mounted-weapon
lesson; actual level-mounted acceptance remains separate from the shared mount
fixture. Named
`circuit_*` landmarks register the driving route for shared-kernel checks.
An explicit Mars launch venue uses existing offline materials and a dust-lit
sky; surrounding ridges and settlement logistics remain outside playable
bounds. No movement, gravity, hazard, Walker or campaign-completion rule is
implied by this presentation.

## Verification

Load the strict file, prove every supplied weapon, enemy approach and named
landmark reachable on foot, and reject invalid vehicle geometry. Drive the
shared kernel around the registered outer circuit, validate seat access and
the parked mount, and clear every ordered group using resolved normal fire.
Repeat the infantry clear with the jeep absent and destroyed. Test reset and
capability refusal. Renderer inspection must separately confirm the gantry,
depot, routes, enemies and jeep are readable. No completed M14, Walker or
four-hour campaign claim follows from these gates.

Implementation and local checks cost $0. This level reuses accepted geometry,
materials, enemies and the separately inspected jeep asset.

Three focused native tests pass: strict fleet and infantry authoring, a
457.93-metre driven circuit using the shared vehicle kernel, and all 20 guards
cleared with ordinary resolved gunfire in each of three fleet conditions.
Those conditions are present, absent throughout, and initially destroyed. The
existing abandonment timer may later restore the initially destroyed jeep;
the infantry driver never occupies a seat or uses a mounted trace. Its agent
inventory uses finite ammunition. The native route proves ordinary useful
stock claims in the western apron staging lane while the final group stays
asleep, then wakes that group only through an explicit final advance. Full
bags and full health correctly leave unneeded stock available. A separate
client regression walks all 66 straight QA waypoints through the shared
movement mirror with the parked hull and checks that the whole held-fire
resupply approach stays outside the actual gantry activation region.
The live human route separately exercises finite human magazines and reloads.
The [bounded evidence](../evidence/m14-launch-authority-development-20261008.md)
records all 16 rendered states and five combat groups completed, with 20
human kills and no deaths. The final corrected route also exits with clean
logs. Earlier attempts retain their failures, including pre-final stocks
inside the gantry trigger and intermittent Compatibility shutdown diagnostics.
The three existing stocks now use a western staging lane outside that trigger,
with an explicit final advance after held-fire resupply. The clean final run
does not establish a global fix for the older sky-retirement diagnostic.
Fresh-player balance, story understanding, actual level-mounted combat and
final Mars art remain open acceptance gates.
