# Enclosed and layered campaign spaces

**Status:** scoped for implementation, 2026-09-19. No new geometry is implemented.
**Goal:** support the intake hall, service stairs and records balcony in
[M01](../campaign/m01-recall-notice.md) without fake ceilings or blocked space
beneath upper floors. Spend: $0. No new dependency or renderer.

## Current constraint

`movement::Solid` stores an XZ footprint and `top`; every solid fills the volume
from ground to that top. `combat::Ray3::solid` uses the same ground assumption.
`navigation::Navigation` stores one height per grid cell, and `arena_cover.gd`
renders the corresponding ground-filled boxes. This is coherent for the existing
roster but cannot represent an accessible room beneath a balcony or ceiling.

Do not author JSON claiming those spaces until collision, shooting, navigation
and presentation all support them. The existing six-map behavior and ledge escape
regressions remain the compatibility baseline.

## Bounded implementation

1. Extend the shared solid to an explicit lower and upper vertical bound, keeping
   a missing lower bound equivalent to today's ground-filled volume. Establish
   one fighter-body height shared by movement and combat. Reject invalid bounds,
   non-finite values and excessive content before topology allocation.
2. Make body clearance and swept head contact explicit. Walking beneath a deck,
   jumping into its underside, stepping under low headroom, landing on its top
   and leaving its side must agree. Preserve outward recovery from an inflated
   ledge overlap without permitting passage through a real wall.
3. Update finite ray intersections and impact normals through the canonical
   combat seam. A shot can pass beneath a balcony and hit its underside; an upper
   floor occludes bodies above it. No second special campaign raycaster.
4. Extend bounded topology to multiple legal foot heights at a grid position.
   Require headroom, connect only physically walkable transitions, preserve
   one-way drops and budgeted searches, and bound both node and construction
   work before allocation. Controller advice still moves through ordinary input.
5. Mirror movement in GDScript, regenerate golden vectors from Rust and render
   box height/center from both vertical bounds. Fixtures use the same server
   geometry as the presenter. Do not add a decorative ceiling with no collision.
6. Before any map using these volumes can be served to old clients, define and
   enforce geometry capability/version compatibility in the shared protocol,
   adapter and decision brain. An older client must not silently render a closed
   block where the server allows an underpass. Document the rejection/migration.

Validated external map loading follows this contract in a separate bounded
change. It will own stable content IDs, materials, placements and objective links.
Moving lifts, sloped brushes, arbitrary mesh collision, crouching, doors and the
full M01 mission are outside this geometry increment.

## Evidence and completion

- Deterministic movement cases for underpass, both balcony levels, stair access,
  low ceiling, head strike, underside edge, landing and outward ledge recovery.
- Rust/GDScript golden agreement and unchanged legacy cases except any separately
  reproduced defect. Never regenerate expected output merely to bless a failure.
- Rays below/through/above each slab, including impact point and normal checks.
- Actual server players follow routes to both levels and cannot choose a route
  through a floor, ceiling or insufficient headroom. Malformed geometry and
  exceeded construction budgets fail before readiness.
- A rendered enclosed fixture shows walking below, ascending, looking/shooting
  across levels and jumping into the ceiling. Inspect motion and both renderer
  paths. The fixture is engineering evidence, never a finished campaign level.
- Full verification, six-map mixed roster, CPU measurements, shared protocol
  documentation and current screenshots before integration. Then update
  [campaign build order](campaign-build-order.md) with the implemented contract.
