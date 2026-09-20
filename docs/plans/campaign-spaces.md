# Enclosed and layered campaign spaces

**Status:** in progress, 2026-09-19. Finite-volume movement, layered routes and
geometry compatibility are under local verification. No enclosed mission ships.
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

The next local increment adds multiple walkable layers per grid cell, preserving
legacy primary indices and bounding layers, nodes, edges and construction work.
Shared-movement route tests pass for underpasses, stairs to the overlapping upper
floor, one-way drops, exact headroom and invalid surfaces. Coordinate-only goals
use their target height or the fighter's current eye height instead of silently
selecting a roof. Actual `GameState` traversal of raised geometry remains pending.

The connection declares maximum geometry version 2; legacy omission means 1.
The server rejects insufficient capabilities before Welcome or roster mutation,
including the maximum requirement of a rotating roster. Ground-only maps omit
version 1 and zero bottoms, preserving their old map bytes. Local socket tests
cover rejected roles, supported joins and unsupported server configuration.
Rust consumers share geometry-bound validation. The MCP session closes on a bad
map; the Godot network validates before emission and presents a connection error.
Eighteen Godot harnesses pass, including malformed maps, the version gate and
geometry replacement when a server reuses a map ID. The workspace suite and
warnings-denied Clippy pass after the new adapter socket tests. Receipts remain
under `.agents/enclosed-wire-*` and `.agents/enclosed-map-godot.log`.

Next: finish verification and review of these changes, measure legacy CPU traces
and the mixed roster, and add actual-player plus rendered enclosed-space evidence.
Review malformed-message handling in all controller paths before integration.
No built-in map exposes raised slabs yet. Do not publish this intermediate
geometry implementation until those paths agree and full verification passes.

Parallel maintenance: PR #175 fixes a benchmark threshold test that accidentally
asserted debug/coverage speed. Its next CI run exposed excessive early deaths on
Tripoint Works. A separate worktree under `.agents/worktrees/benchmark-thresholds`
holds a reproduced warmup-join defect and fix: warmup previously bypassed cover
selection unless a fixed ring slot was occupied. The existing cover fixture fails
with a warmup join at (approximately 0, 0, 92), then passes when all joins use the
same policy. Complete that focused main-branch repair before publishing this
geometry branch. Do not weaken the spawn-death or release benchmark gates.
The maintenance worktree is now detached at `1d03cc8`; its branch is
`fix/benchmark-threshold-fixtures`. Do not share a Cargo target directory between
different worktree source states: doing so produced stale dependency metadata
during this session. A package clean followed by a full rebuild restored the
correct geometry API and the complete workspace suite passed.
