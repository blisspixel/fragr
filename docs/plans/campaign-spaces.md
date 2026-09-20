# Enclosed and layered campaign spaces

**Status:** in progress, 2026-09-19. Finite-volume movement and shots are under
local verification; layered routes and network compatibility remain unbuilt.
**Goal:** support the intake hall, service stairs and records balcony in
[M01](../campaign/m01-recall-notice.md) without fake ceilings or blocked space
beneath upper floors. Spend: $0. No new dependency or renderer.

## Current constraint

The shipped `movement::Solid` stores an XZ footprint and `top`; every solid fills the volume
from ground to that top. `combat::Ray::solid` uses the same ground assumption.
`navigation::Navigation` stores one height per grid cell, and `arena_cover.gd`
renders the corresponding ground-filled boxes. This is coherent for the existing
roster but cannot represent an accessible room beneath a balcony or ceiling.

Do not author JSON claiming those spaces until collision, shooting, navigation
and presentation all support them. The existing six-map behavior and ledge escape
regressions remain the compatibility baseline.

## Bounded implementation

First complete [shared body integration](shared-body-integration.md), removing
the duplicate live-server movement solver while preserving its current controls.
This prerequisite shipped in #174 and v0.21.1.

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

## Working implementation

Branch: `feat/enclosed-campaign-spaces`, based on the shared-body change. Local
code adds a default-zero `bottom`, omitted when zero so legacy wire bytes stay
unchanged. Movement tests cover underpasses, upper-floor support and landing,
head strikes, thin ceilings, slab edges, airborne side contact and stair headroom.
Shots use the exact lower bound and face normals; the presenter draws finite
height and center. Standing body height is shared by movement and shot targets.

Nine new golden cases exercise this geometry through Rust and GDScript. The
twenty legacy cases compare unchanged in every field against the parent file.
Focused Rust movement tests, warnings-denied workspace Clippy, and all seventeen
Godot harnesses pass, including the raised-mesh check and new vectors. Receipts:
`.agents/enclosed-*.log`. This is local engineering evidence, not a built level.
The workspace suite also passes: 606 tests and the existing ignored generator.

Next: replace the one-height topology with bounded layered routes, enforce
geometry compatibility at connection and map boundaries, validate untrusted
client map data, and add actual-player plus rendered enclosed-space evidence.
No built-in map exposes raised slabs yet. Do not publish this intermediate
geometry implementation until those paths agree and full verification passes.
