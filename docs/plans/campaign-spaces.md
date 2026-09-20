# Enclosed and layered campaign spaces

**Status:** shipped in #176, 2026-09-19. Finite-volume movement, layered routes
and geometry compatibility passed all five PR CI jobs. No enclosed mission ships.
**Goal:** support the intake hall, service stairs and records balcony in
[M01](../campaign/m01-recall-notice.md) without fake ceilings or blocked space
beneath upper floors. Spend: $0. No new dependency or renderer.

## Original constraint

Before this change, `movement::Solid` stored an XZ footprint and `top`; every solid filled the volume
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

Branch: `feat/enclosed-campaign-spaces`, following #174 and the #175 spawn repair.
The authored map definitions now use `movement::Solid` directly. A default-zero
`bottom` is omitted on the wire, preserving legacy bytes. Movement, shots,
rendering and bounded navigation use the same finite volumes and body height.
Nine added Rust/GDScript golden cases cover these volumes; the twenty legacy
cases remain unchanged in every field.

Layered topology preserves legacy primary indices and bounds layers, nodes,
edges and construction work. Routes cover underpasses, stairs to the overlapping
upper floor, one-way drops and exact headroom. Coordinate-only goals respect
target height instead of silently selecting a ceiling. Tests also drive actual
`GameState` players through its production active-frame core: ordinary actions
walk both levels, queued jumps hit the underside, and shot damage respects the
slab. These fixture tests do not claim a complete network campaign mission.

Connections declare maximum geometry version 2; legacy omission means 1. The
server rejects insufficient capabilities before Welcome or roster mutation,
including a rotating roster's maximum requirement. All map consumers validate
before replacement. Invalid or unreadable maps stop controllers and close client
sessions instead of allowing stale-world navigation. Existing legacy map bytes
and supported sessions remain compatible.

Local verification passes 622 Rust tests, warnings-denied Clippy and 18 Godot
harnesses. Unfiltered workspace coverage reports 95.63 percent of lines.
Review found a remaining scripted-adapter path:
it ignored maps, unwrapped a rejected Welcome, and restarted its action timer
whenever a snapshot arrived. It now validates geometry, uses the shared navigator
and keeps an independent action clock. Two added socket tests pass for rejection,
raised geometry, continuous incoming traffic and malformed replacement. Final
workspace coverage/tests, release build and dependency policy checks pass after
this controller fix. A 25-second loopback smoke on Compliance Yard produced two
scripted-agent frags and one death against four local bots.

The active-frame fixture renders 250 recorded frames in OpenGL compatibility
and Vulkan Forward+ on Windows with an AMD Radeon 780M. Thirty samples per path
cover the underpass, ordinary stairs, upper exit, head contact and underside shot.
Contact sheets and full-size critical views were inspected, including the exact
head-contact apex at frame 220. Captures: `.agents/qa/enclosed-{opengl,vulkan}`.
This is a replay of authoritative active-frame output, not a live network test,
finished level, frame-rate benchmark or cross-vendor certification. The room
exposes repetitive materials that need authored variation in M01.

Reproduce the capture with a real framebuffer after importing the client:

```bash
cargo test -p fragr-server export_enclosed_capture --locked -- --ignored
FRAGR_QA_DIR="$PWD/.agents/qa/enclosed-opengl" "$GODOT_BIN" --path client --rendering-driver opengl3 --windowed --resolution 1280x720 --script res://scripts/qa_enclosed.gd
```

Use `--rendering-driver vulkan` and a separate output directory for the second
path. Require a clean log and inspect the stills; Godot can return success after
an image operation fails. The capture normalizes image formats before montage
composition, since the two rendering paths return different formats. API checked
against the [Godot RenderingServer reference](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
on 2026-09-19 and the installed binary.

CPU comparison after the active-frame extraction, seed 42, 12,000 ticks:

| Bots / map | p99 tick ms | Maximum tick ms | Full trace matches #175 |
|---|---:|---:|---|
| 16 / Arena Duel | 0.655 | 2.059 | yes |
| 64 / Reclamation Gulch | 1.507 | 3.453 | yes |
| 128 / Tripoint Works | 4.063 | 6.576 | yes |

Reports: `.agents/bench/enclosed-{16,64,128}.json`. Each run also passes its own
repeat-trace determinism and performance gate. The six-map mixed-client network
roster passes with 2/6/6/8/12/16 external clients. Reports live under
`.agents/playtest/enclosed/`. The 21-state tour passes, and its contact sheet,
first-person view and both effect strips were inspected before publishing the
current stills. GitHub run `35489587263` passed all five jobs before integration,
including Linux, Windows and macOS checks.

No built-in map exposes raised slabs yet. External map data, explicit indoor
spawns and full live M01 routes follow this foundation. The ring-spawn policy and
legacy roster flood fill are not suitable campaign authoring contracts. Keep
those limitations visible rather than labeling a fixture as a completed level.

Build continuity: use separate Cargo target directories for worktrees with
different source states. Sharing one produced stale dependency metadata; a
package clean and full rebuild restored the correct API. Temporary receipts
live in `.agents/`; source, tests and this plan own the durable state.
