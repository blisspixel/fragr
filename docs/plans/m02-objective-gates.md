# M02 objective and gate foundation

**Status:** in flight, 2026-09-23. This is the first M02 seam after the
[durable run](campaign-run-file.md), in the [full build order](../ROADMAP.md#full-build-order-2026-09-22).

## Goal

Author a bounded sequence of physical objectives and precomputed gate worlds
for Persons Unknown. A player or agent sees the same server-owned objective
facts and can complete each required interaction alone. The first M02 graybox
must prove the observation gallery, ward, processing floor, and loading exit
are reachable in the intended order. M01 stays playable and existing M01 saves
stay compatible with its exact committed content bytes.

## Boundaries

- Keep `server/src/mission.rs` authoritative for objective progress and uses.
  M01's record and lift remain the regression fixture, with the same wire
  behavior and JSON bytes. Add a separate, strictly validated M02 authoring
  shape rather than rewriting M01's content just to fit a new schema.
- Author stable objective IDs, prerequisites, physical controls or arrival
  regions, and completion conditions. A bounded objective set has no cycles,
  ambiguous IDs, hidden mandatory controls, or progress from a dead or unready
  participant. One accepted use advances at most one objective; retries reset
  transient mission progress without changing run identity or allowance.
- Prepare every allowed gate state, collision world and navigation graph before
  readiness. Use a small explicit gate limit and reject combinations that
  exceed the preparation budget. A runtime transition selects a prepared
  `RuntimeMap`; it never bakes geometry on the combat tick. Validate the use
  point, panel host, standing clearance and route reachability in every state
  in which an objective or exit is required.
- Send current objective IDs, completion state and legal prompts over the
  existing mission wire. The Rust mission controller, agent observations,
  adapter, Godot boundary and HUD read that same validated state. If the wire
  shape changes, bump the gameplay capability and update `docs/protocol.md`
  and `agent-adapter/README.md` in the same change. Keep M01 readers strict.
- Use visible physical feedback for a gate transition. A cosmetic panel cannot
  block movement; blocking props are authoritative solids. A solo player can
  always reach the next mandatory control without an NPC occupying a doorway.

This increment does not implement Latch as an actor, the Jammer pulse, Crawler
combat, a finished M02 encounter budget, M02 save migration, co-op, new
transport, or cloud hosting. Those use the foundation after it is validated.
M02's final sequence remains `ward_reached`, `correction_stopped`,
`companion_released`, `loading_gate_open`, `party_departed`; this increment may
stub the later actor and projectile gates in the graybox, but must label them
unbuilt rather than call the mission playable.

## Build order

1. Freeze an M01 content hash fixture and run/route regression. Trace the
   callers of `MissionGeometry`, `MissionState`, `opened_route` and readiness.
   Record the current wire example before changing it.
2. Add strict authored objective and gate definitions with a bounded prepared
   state table. Reject duplicate IDs, unknown prerequisites, cycles, bad panel
   hosts, excessive state combinations, invalid collision, unreachable
   required routes and an exit that opens before its prerequisites.
3. Give the server one objective transition function for region arrival and
   physical use. Project one validated mission observation and one legal
   interaction list to all client roles. Keep the M01 path behavior equivalent.
4. Author a minimal M02 geometry slice around the gallery, ward and loading
   route. Give each gate an immediately readable consequence. Connect the
   Godot presenter and agent controller to the new facts, without granting
   either authority.
5. Run seeded route, malformed-authoring, retry, wire, Godot and first-person
   checks. Inspect a muted capture of the progression. Update this plan and
   the single roadmap rung with evidence and gaps.

## Acceptance

- The exact M01 JSON hash and a saved M01 run remain compatible. M01's normal
  and retry clears, controls, gate transition and client state still pass.
- M02 authoring rejects invalid objective graphs and gate worlds before
  readiness. Every required control and exit has a server-proven walking route
  in its intended gate state; a shut gate actually blocks the premature route.
- A real solo or agent-controlled route reaches the graybox objectives in
  order. Duplicate use does not advance twice, dead or unready actors cannot
  advance, and mission-start retry restores the original objective and gate
  state. Human and agent observations agree on the objective and prompts.
- Godot headless checks, the visual tour, relevant wire and adapter tests,
  full CI, and a measured navigation and snapshot cost pass. Capture claims
  distinguish a preparatory graybox from finished M02 play.

Local tests and LAN cost $0. No paid generation or cloud apply is needed.
Human acceptance remains near 1.0 as requested; automated checks and
first-person inspection are the gate for this increment.

## Progress, 2026-09-23

The first preparatory slice adds strict objective and gate authoring for map
1002, validates a linear prerequisite chain and bounded gate worlds before
readiness, and keeps the exact M01 content hash under test. It exposes a
prepared collision and navigation world selector without publishing M02 mission
wire state or making M02 playable. A review found
that arrival regions could span a closed barrier and an M02-only graybox could
be mistaken for an arena; both cases now have regression checks. The next
slice is the M02 wire contract, followed by a real M02 graybox and first-person
route evidence.

The server transition slice now carries complete arrival regions and use targets
into mission authority. It checks arrival each tick, consumes invalid presses,
advances one objective at most per tick, selects a prepared gate world, and
restores the first objective and closed world on retry. Focused deterministic
tests use a synthetic three-objective map and direct internal readiness. They
cover early, unready, dead and mis-aimed interaction attempts, duplicate use,
and the gate transition. A two-participant test verifies that departure waits
until every current participant is ready, alive and inside the exit region,
matching M01's shared exit rule. The workspace Rust tests and clippy passed
locally before this follow-up; focused M02 tests and fmt/clippy were rerun after it.
This does not prove a playable M02 route or a wire observation. M02 network
readiness, objective state and prompts are still absent, so the graybox remains
unplayable through a normal client. The next slice must publish progress without
changing M01's serialized shape. Current local run files validate M01 only;
durable cross-mission solo carry needs an explicit run-file revision and its
own tests before it is called shipped.
