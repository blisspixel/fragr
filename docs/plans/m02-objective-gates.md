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
be mistaken for an arena; both cases now have regression checks. MapInfo now
carries an optional M02 objective count, so readers do not classify a legacy
encounter-only map by numeric ID.

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
This does not prove a playable M02 route. The next Rust wire slice now publishes
objective progress, gate mask, current arrival or use target, party state and
per-participant legal prompts through an optional M02 mission field. The existing
mission_ready command accepts M02. Admission requires gameplay capability 9 for
M02 and keeps M01's version 8 path. Shared Rust controllers and the MCP adapter
validate targets against MapInfo; the adapter observation and readiness have a
synthetic fixture regression. M01 serializes without the new field. These are
server and Rust-reader checks, not normal Godot play or first-person route
evidence. The Godot mission boundary, HUD, map presentation, a bundled M02
graybox, full route proof and screenshot tour remain pending. Current local run
files validate M01 only; durable cross-mission solo carry needs an explicit
run-file revision and its own tests before it is called shipped.

The first PR CI run exposed a local-launch contract regression: the M01 child
advertised the server's new maximum capability 9 while the M01 Godot launcher
requires its exact capability 8. Readiness now reports the selected mission's
contract. The Rust bootstrap and local-child integration tests, plus the real
Windows Godot local-campaign, recovery and saved-restart harnesses, pass with
that correction.

Wire-slice checks: `cargo fmt --all -- --check`,
`cargo clippy --workspace --all-targets --locked -- -D warnings`, and
`cargo test --workspace --locked` passed locally. The focused M02 adapter test,
M02 server tests and explicit M01 capability 8 admission test passed. The full
Godot headless checker passed locally after the bootstrap correction. No M02
tour, rendered route or playable M02 acceptance was run for this Rust-only slice.
After the map marker correction, workspace fmt, clippy and tests passed again.
An encounter-only map with ID 1002 admitted capability 3 clients and omitted
the marker, while the M02 fixture emitted its count and rejected unmarked
objective state in the adapter.

## Rule: readable controls, few puzzles

Recorded 2026-09-24 at Nick's request, and in `docs/MAP-DESIGN.md` for later
missions.

- **Few puzzles, fun first.** A control is a Doom switch hit in stride that
  opens a door the player can already see or that stands right beside it, one
  step at a time. No chains, combination or order puzzles, switch hunts or long
  backtracking. Prefer an arrival or a combat-cleared gate over another switch.
  M02 authoring rejects a gate whose opener stands more than eight metres away.
- **Readable without English.** All labels, prompts, objective lines and signs
  are keys in `client/i18n/*.po`; map JSON carries registered kinds, never
  English; a missing key fails a harness rather than showing the raw key.
- **The picture explains the control.** Each control has a state read (red
  lamp and closed shutter pictogram while locked, green lamp and raised shutter
  arrow once open), a visible link to what it operates (the same lamp on the
  switch or arrival point and on the gate), a pictogram of its function, and a
  world change when used (the shutter rises and stays visible, both lamps flip,
  a sound plays). Agents read the same facts from legal prompts.
- **Evidence.** Before and after stills of every control, inspected, with a
  written account of what a player sees with the text hidden.

M01's transfer record console and lift control predate this rule. They have a
terminal panel, a lift panel and a rising lift gate, but no locked and open
lamp pair, and the record console stands away from the lift it opens. That is a
follow-up for M01's own plan, not part of this M02 slice.

## Progress, 2026-09-24: bundled graybox and server route proof

`server/maps/m02-persons-unknown.json` is the bundled map 1002 behind
`AuthoredSource::Mission(PersonsUnknown)`. It lays out the observation gallery
(a slot window over the ward), an enclosed service stair, the antechamber, the
correction ward with a restraint bay, a processing floor with a mezzanine on a
broad stair and machinery islands, and the loading dock. The authored chain is
`ward_reached` (arrival at the ward door), `correction_stopped` (a switch beside
the bay shutter), `companion_released` (arrival at the restraint frame inside
the bay), `loading_gate_open` (a switch beside the loading gate) and
`party_departed` (dock arrival). Two switches remain, each right beside the
door it raises; the restraint arrival raises the bay's back shutter onto the
processing floor. Each gate rises three metres and stays visible overhead. Two
`gate_locked` lamps per gate, one on the shutter and one on its opener, become
`gate_open` in every prepared world where that gate is raised. The foundation
prepares and validates the worlds, and their presentations, for masks 0, 1, 3
and 7 before readiness.

Stubs, labeled unbuilt: the restraint arrival stands in for Latch's
story-controlled release, and the loading control stands in for disabling the
Jammer. Neither Latch nor the Jammer exists. The graybox also has no enemies,
maintenance loop, optional captives, secrets or story page. Supplies are a Tack
on the stair landing, a Scatter and a medkit in the antechamber and armor on
the mezzanine.

`fragr-server --local-mission persons_unknown` starts it as a development child
with readiness `gameplay_version` 9. It refuses `--run-mode`, carries no `run`,
and keeps development entry respawn and the shared wipe reset. No M01 to M02
carry exists; the M01 content hash and run files are unchanged.

Seeded route proof in `server/src/mission/m02/route_tests.rs` drives the live
`GameSession` with `MissionClient` reading only wire messages: MapInfo rebuilds
its own navigation, mission state is validated before steering, and the
controller walks, aims and presses use. A solo human and a solo agent each
complete all five objectives in order and depart after 398 ticks (about 20
seconds of simulated time), with four MapInfo messages (the closed world plus
one per gate) whose open lamp counts are 0, 2, 4 and 6, and no body inside a
solid on any tick. In the closed world the three later objectives have no
navigation route, and walking and jumping into each closed gate for three
seconds does not pass it. After the bay and back shutters open, a death wipe
restores attempt 2 at `ward_reached` with all three gates down and resends the
closed map; the same participant then clears again from entry. Authoring tests
reject a gate with fewer than two signals, a signal authored open, a lamp placed
as a plain decoration, and an opener fourteen metres from its gate. The local
child integration test confirms the M02 readiness line, map 1002 with five
objectives, no run in mission state, and refusal of `--run-mode`.

This is authoring evidence for a traversal graybox, not playable M02. The
Godot mission boundary, HUD line, lamp and gate presentation, a local menu entry
and first-person captures are the next slice.
