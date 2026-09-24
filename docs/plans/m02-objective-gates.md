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
The graybox's sequence is `companion_released` ("Find Latch") then
`party_departed` ("Get out"), both by arrival, with no gates (revised
2026-09-24, see the last progress section). Latch and the Jammer stay unbuilt
and are labeled so; the graybox is not called the finished mission.

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

## Rule: fights first, few doors, readable without English

Recorded 2026-09-24 at Nick's request, and in `docs/MAP-DESIGN.md` for later
missions. It replaced an earlier readable-controls rule the same day.

- **A boomer shooter, not a door simulator.** Progress is fighting through
  rooms. Objectives advance by arrival, two or three short verb lines per
  level ("Find Latch", "Get out"). A level has at most three doors and at most
  one simple switch, beside the door it opens with the door in view. No
  puzzle chains, order puzzles, switch hunts or long backtracking. Authoring
  rejects a second required use switch and an opener more than eight metres
  from its gate.
- **Readable without English.** Labels, prompts, objective lines and signs are
  keys in `client/i18n/*.po`; map JSON carries registered kinds, never
  English; a missing key fails a harness rather than showing the raw key. A
  door or switch that does exist must read from the picture.

M01's transfer record console and lift control predate this rule; whether M01
keeps them is a follow-up for M01's own plan.

## Progress, 2026-09-24: bundled graybox and server route proof

*Superseded by the fights revision below; kept as the record of what was
built and measured at the time.*

`server/maps/m02-persons-unknown.json` is the bundled map 1002 behind
`AuthoredSource::Mission(PersonsUnknown)`. It lays out the observation gallery
(a slot window over the ward), an enclosed service stair, the antechamber, the
correction ward with a restraint bay, a processing floor with a mezzanine on a
broad stair and machinery islands, and the loading dock. The authored chain is
`ward_reached` (arrival at the ward door), `correction_stopped` (a switch beside
the bay shutter), `companion_released` (arrival at the restraint frame inside
the bay), `loading_gate_open` (a switch beside the loading gate) and
`party_departed` (dock arrival). As merged in #234 it had two switches, each
beside the door it raised (both removed later the same day); the restraint arrival raises the bay's back shutter onto the
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

## Progress, 2026-09-24: Godot boundary, readable controls and stills

*Superseded by the fights revision below; kept as the record of what was
built and measured at the time.*

The Godot client now advertises gameplay capability 9. `mission_state.gd`
validates the optional `m02_objectives` marker and the strict `m02` mission
field (objective IDs, count, gate mask, current arrival region or use target on
a registered console panel, `objective_use` prompts, no run) and rejects
rewound progress within an attempt, including across a gate MapInfo resend.
`player_record.gd` accepts M02 mission records without a run. The M01 path and
its launcher contract (capability 8) are unchanged.

Presentation is keyed and quiet. `mission_hud.gd` shows at most one M02 line:
the use prompt while it is legal, otherwise the objective for eight seconds after
it changes, and one persistent line at departure. Every line is a catalog key;
a missing key logs an error and shows nothing, and `world_sign.gd` does the same
for world copy, so a harness fails instead of a player reading a raw key. The
lamp panels draw a red lamp over a closed slatted shutter, or a green lamp over
a raised shutter and up arrow, so shape and colour both carry the state.
`objective_beacon.gd` pulses an amber lamp on the console that is the current
use target. `gate_feedback.gd` plays a short code-built shutter clank at each
solid a validated M02 MapInfo raised. The console copy reads WARD CONTROL and
LOADING CONTROL from keys. Single Player has a development entry,
"Persons Unknown: ward graybox", which starts the M02 child with no run mode and
no story page; the match menu says leaving keeps no progress.

What a player sees with all text hidden (`.agents/qa/m02-graybox/*_world.png`,
first-person, local tour of 2026-09-24, not published):

1. Gallery: a slot window over the ward; the bay shutter is visible below.
2. Ward door: ahead, a dark shutter with a red lamp and closed-shutter
   pictogram, and beside it a low console with a pulsing amber lamp under a
   matching red lamp on the wall.
3. After the switch: the shutter hangs raised over an open doorway, and both
   lamps show green with an up arrow. Through the doorway the next shutter
   already shows a red lamp.
4. In the bay: the back shutter and the restraint frame share red lamps.
   Walking up to the frame raises the back shutter; both lamps turn green and
   the processing floor is visible through it.
5. Processing floor: across the floor, the loading gate and the switch beside
   it both show red lamps, the switch pulsing amber.
6. After the loading switch: the gate hangs raised and both lamps are green;
   the dock is beyond.

Each step asks for one door the player can already see. The HUD stills show a
single objective or prompt line. Limits: the gallery view shows the shutter but
its lamps are too small to read at that distance; the terminal faces are plain
dark screens when copy is hidden, so the function pictogram lives on the lamp
above each switch; the clank was verified by a harness, not by listening; and
the shutter jumps up on the MapInfo resend instead of animating.

Checks: `test_m02_mission.gd` (marker and state boundary, late and rewound
state, gate MapInfo refresh, one-line HUD, beacon placement, lamp styles, every
world and HUD key present, moved-solid detection and a positioned clank),
`test_m02_local.gd` (the Single Player entry starts the real M02 child, the human
becomes ready without a story page, every objective line fits one card line, the
match menu note, no run file), `test_local_match.gd` (per-mission readiness
contract and arguments), `test_player_records.gd`, `test_arena_sky.gd` (the ward
uses the facility fill) and the M02 tour `client/qa/m02-graybox.json`
(16 states, before and after both switches and the restraint arrival, departure).
The tour holds Use for 0.15 s: a press and release in the same frame travels in
one action message, which the server's inbound rate limit can drop at high
frame rates. A person's press spans many frames.

M02 is still not playable as a mission: Latch, the Jammer, encounters, the
maintenance loop, optional captives, secrets, the story page, M01 to M02 carry
and human acceptance remain.

## Progress, 2026-09-24: fights, not doors

Nick asked three times for fewer mechanics: "stop making puzzles and so many
doors... this is a boomer shooter, not a door simulator." The switch, shutter,
lamp and gate work above was dropped from the graybox.

**Route.** The map has no switches and no gates, so one world is prepared.
Gallery (a slot window over the ward's guards), service stair (Tack, bullets),
antechamber (Scatter, shells, medkit), then straight into the correction ward.
The ward's north wall has an offset opening to the processing floor, placed so
the floor crew is not visible from the ward; a Sweeper waits beside it. The
floor has a mezzanine (armor), press islands and a conveyor, then a wide
opening onto the loading dock. Supplies use the existing supply seam only.

| Objective | Advances by | HUD line |
|---|---|---|
| `companion_released` | arriving at the restraint frame in the ward (Latch stand-in, unbuilt) | FIND LATCH |
| `party_departed` | arriving on the loading dock | GET OUT |

Encounters, all existing Clerks and Sweepers: `ward_guards` (2 Clerks, 1
Sweeper, woken at the ward door), `floor_crew` (2 Clerks, 2 Sweepers, woken at
the floor opening, after the ward), `dock_watch` (1 Clerk, 1 Sweeper, woken at
the dock opening, after the floor). Nine enemies in all.

**Server proof** (`server/src/mission/m02/route_tests.rs`, seed 67). The
walker reads only wire messages, fights the nearest visible hostile within 24
metres, passes that through the shared equipment controller
(`control_action_with_objective`) and routes with `MissionClient`. A solo human
and a solo agent each defeat all nine and depart after 1014 ticks (about 51
seconds), at 80 hp, 50 shots fired, 19 enemy shots. One MapInfo is sent: no
world change. A wipe after "Find Latch" restores attempt 2 at the first
objective with all nine enemies back and every supply available, and the same
agent then clears again. This is accurate-aim authoring evidence, not a
difficulty acceptance.

**Tour** (`client/qa/m02-graybox.json`, 8 states, local 2026-09-24, exit 0,
stills under `.agents/qa/m02-fights/`, not published). A live human picks up
the Tack and Scatter and fights each room through ordinary input: the ward
(3 defeated, 28 shots), the floor (4 defeated, 15 shots, 7 enemy shots) and the
dock (2 defeated, 10 shots, 5 enemy shots), then departs with GET OUT on the
HUD. Inspected stills show a Clerk firing a tracer across the ward beside the
correction machine, a Sweeper winding up at the foot of the mezzanine stair,
and the dock pair behind crates. The tour fights with the Tack because the
Scatter only reaches 12 metres and the ward is wider; with the Scatter selected,
the ward fight stalled at range. Earlier layouts let dormant guards be seen
through long doorway lines, which stalled the tour's travel combat; the offset
opening and the relocated floor guards fixed that. One of four runs failed
only on the engine's intermittent OpenGL texture leak at exit
([#186](https://github.com/blisspixel/fragr/issues/186)).

**Client.** One keyed HUD line (the objective for eight seconds after it
changes, or a use prompt if a map ever has one), strict M02 wire validation,
the Single Player development entry and the match menu note stay. The
current-switch beacon, gate clank, shutter animation and lamp glow were removed.
The `gate_locked` and `gate_open` kinds stay registered and drawn, unused by
this map.

**The lost Use tap was a real client bug** and matters for M01's record
console. Instrumented tour runs (debug lines not committed; summaries under
`.agents/press-evidence/`) showed the client rendering at 434 to 509 fps and
sending one action per frame. The server's inbound budget (256 per second,
burst 64) dropped 7639 to 8530 messages per run, about half. A press and
release inside one frame rides exactly one message, so it had roughly even
odds of being dropped; the client latch never collapsed it, and the server
accepted every tap that arrived. `game_manager.gd` now paces local actions at
120 per second and keeps jump, reload, Use and weapon choices latched until a
message carries them. `test_input_pacing.gd` drives 500 fps for two seconds
through a mirror of the server budget: about 240 sends, none dropped, a
sub-frame tap delivered exactly once, and a tap on a skipped frame carried by
the next send.

M02 remains a development graybox: Latch as an actor, the Jammer, Crawlers,
the maintenance loop, captives, secrets, the story page, M01 to M02 carry and
human acceptance are pending.
