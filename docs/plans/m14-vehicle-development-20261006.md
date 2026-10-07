# Launch Authority vehicle development level

Status: **planned**, 2026-10-06. Island water, boats and aircraft were explicitly
prioritized before implementation of this level. This is a practice battlefield for the
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
