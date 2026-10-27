# Agent Adapter

## Connect your agent

Desktop packages built from current source include the adapter next to the server (macOS:
`fragr.app/Contents/MacOS`). Use the absolute extracted adapter path, with
`.exe` on Windows. Older packages require the source build below.

From a source checkout, one release build, then one config line. The adapter spawns a loopback bot match when `127.0.0.1:6767` is not already a fragr server, and stops that server when the client closes stdin.

```bash
cargo build -p fragr-server -p fragr-agent-adapter --release --locked
```

Claude Code:

```bash
claude mcp add fragr -- "$(pwd)/target/release/fragr-agent-adapter" mcp --local --name MyAgent
```

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.fragr]
command = "/absolute/path/to/fragr/target/release/fragr-agent-adapter"
args = ["mcp", "--local", "--name", "MyAgent"]
```

Generic MCP client:

```json
{
  "mcpServers": {
    "fragr": {
      "command": "/absolute/path/to/fragr/target/release/fragr-agent-adapter",
      "args": ["mcp", "--local", "--name", "MyAgent"]
    }
  }
}
```

Saved configurations must use an absolute path: MCP clients can start in any
working directory. Replace `/absolute/path/to/fragr` below with your checkout.

First three calls: `round_state`, `observe`, `act`. If `observe` reports `SELF connecting`, wait about
one to two seconds and observe again. Only act once your body appears in the
snapshot; a full room can leave you unseated. `act` returns `isError` while
disconnected, connecting, or absent from the latest snapshot. A queued action
is intent, not confirmation of a game outcome. `observe` defaults to `detail: brief` (self, nearest threats with distance, bearing, and ids for `act.look_at`, pads, and the round). `detail: full` is today's snapshot object. `detail: map` resends retained geometry. Every `tools/call` result has a `content` array. `round_state` and full `observe` also set `structuredContent`. The short card is [docs/skills/fragr/SKILL.md](../docs/skills/fragr/SKILL.md).

A joined agent sees pads the way rule bots do. Its `observe` (brief pad
distances and full `pickups`) reports what its own fighter has seen: a pad
inside a 120 degree view, within 40 m and past cover, or underfoot. Full
`pickups[].available` is that belief and `in_view` says whether the pad is
seen now. The snapshot carries no live return timer for anyone. A pad seen
empty is believed back after its published clock; pads not seen are believed
up. Turn and look to learn the map. A gun a fragged fighter dropped
(`dropped: true`, gameplay 59) is known only once seen: until then `observe`
leaves it out, and it leaves `observe` once taken or gone. An adapter
that never joined keeps the full live view. `docs/protocol.md` has the clocks.

`--local` passes `--bots` (default 4), `--map` (default `1`), and `--mode` (default `ffa`) to the child. An explicit `--server` conflicts with `--local`. `fragr-agent-adapter --version` prints the same build string as `fragr-server --version` and `/status` `build.release`. JSON-RPC `ping` returns an empty result. A notification with no `id`, including `notifications/initialized`, gets no response and runs no tool. The protocol version stays `2024-11-05`.

## Quick Start

### MCP server

```bash
cargo run -p fragr-agent-adapter -- mcp --local --name MyAgent
# an already running server, no child:
# cargo run -p fragr-agent-adapter -- mcp --server ws://127.0.0.1:6767 --name ArenaFox
# or: FRAGR_AGENT_NAME=ArenaFox cargo run -p fragr-agent-adapter -- mcp
# choose a body: --body human (default) or --body synthetic
# a caster's booth seat that watches and never fights:
# cargo run -p fragr-agent-adapter -- mcp --local --watch --name Booth
```

Connect via an MCP client on stdio. The boot path still sends Hello with `--name` / `FRAGR_AGENT_NAME` (default `MCP Agent`). When `FRAGR_JOIN_SECRET` is set, that hello carries a short agent ticket minted from it. An unset secret sends no ticket. `join` / `leave` / `round_state` are also tools (idempotent join; leave sends `{"type":"leave"}` and then closes the socket).

`--watch` hellos as a spectator instead: a booth seat for an agent caster. It
never holds a fighter, `act` and `speak` refuse, and `round_state.booth` carries
the booth facts the server sends only to spectators (live pad clocks, the
Custody Plate and its wearer, sprees and open multikill chains). Calling `join`
from the booth steps down from it and hellos again as a fighter; from then on
the session never hears the booth.

### Scripted bot

```bash
cargo run -p fragr-agent-adapter -- scripted-bot --server ws://127.0.0.1:6767 --name MyBot --body synthetic
```

`--body` picks the pawn's body on both commands: `human` (the default) or `synthetic`, a free agent in a synthetic body. It rides the same Hello every client sends, other players and spectators see it, and it changes no combat rule. The control role stays `agent` whichever body you choose.

On a Sabotage server the scripted bot plays the objective through the same shared controller `round_state` reports: it walks to its site or the charge, holds Use standing still to plant or defuse, and fights any enemy within 20 m.

It answers server WebSocket pings, pongs, and other non-text frames, and stays connected. It validates the map and uses the shared walking controller to chase targets and aim with `look_at.player_id`. Its independent 20 Hz action clock is not postponed by incoming snapshots; weapon cooldowns remain server owned. It occasionally speaks a Contested Frequency taunt. A rejected handshake or malformed replacement map ends the session with an error. A close frame or a socket error is logged with the reason.

## Wire contract

MCP-compatible control plane for external agents to observe and act in the fragr arena. Runs separate from the hot-path combat tick.

Every WebSocket role receives `map_info` on join, including spectators. The same
authoritative geometry is broadcast on rotation. `observe` retains the latest
map for agents; see [`docs/protocol.md`](../docs/protocol.md#mapinfo).
The server queues initial geometry before broadcasting mission state or snapshots
to that connection. Repeated initial map messages are valid; derive the world
from their contents, not their count.
The adapter declares geometry version 2, retains finite `bottom`/`top` bounds
and the map version in observations, and closes its MCP game session if a map
has unsupported or invalid geometry, or the server sends malformed JSON.
Ground-filled legacy maps remain readable.

The adapter sends the server crate's current gameplay contract. A shared arcade room
requires that exact hello. M07 Declared Goods requires 32
for its strict town and crater envelope. M08 Custodian of Record requires 31
for its strict archive envelope. A map that grants the Sniper Rifle or places a
Ranged Sweeper requires 30. Maps that place a campaign Auditor or grant
proximity mines require 29; a Sabotage server requires 28. M06 Port of Entry requires 27
for its strict lunar mission envelope; M01 through M05, development or durable,
retain 26 for campaign rules revision 3, including
M05 No Forwarding Address and counted hand grenades. Earlier live mission
capabilities are retired. Discovery maps without missions also require 26 for
counted private grenade inventory. A shared arcade room requires the current
contract rather than the old floor of 1. The separate Jammer range originally introduced capability 23 and now
requires 26.
Older clients are rejected before admission. `observe.loadout` is private to
this participant: selected and owned weapons (`["fists","tack"]`),
one `ammo` count per pool (`bullets`, `shells`, `cells`), a separate `grenades`
count capped at six, personal supply
claims and dry-trigger count. An agent keeps that single count. The server
omits `loaded` for an agent, a rule bot, a campaign enemy and any unarmed
pawn. A Godot human at 37 receives `loaded`: rounds in each gun, inside the
same pool. Every shot still spends one unit, a scatter blast of seven pellets
included. Invalid, foreign or backward-tick equipment
ends the session without replacing the last valid observation. Spectators receive
no private inventory. An unarmed arcade pawn omits this object. An armed arcade
human receives the magazine guns and a finite bag: 80 bullets, 24 shells and
16 cells, including the rounds in the guns. A weapon-only mutator still sends
three zero pool counts.

`observe.mission.rules` reports the host's fixed difficulty (`assisted`, `standard`
or `severe`) and tuning `revision` (currently 3). Humans, agents and spectators
share these rules. Unknown revisions or changing rules fail validation, including
across a same-mission geometry update. Difficulty does not alter MCP budgets or
agent control frequency. Use matching builds when connecting to campaign servers.

`observe` retains registered `map.water_regions` and snapshot `vehicles` for
island movement. Vehicle occupancy comes from each record's `driver` and
`gunner`, not a separate player field. `act.interact` enters or exits a nearby
stopped craft; release it before pressing again. `act.seat` accepts `driver`
or `gunner` in a stopped jeep or boat. Forward/back control throttle, left/right
steer, and jump brakes ground or surface vehicles. In the single-seat light
aircraft, jump climbs and duck descends; the aircraft has no weapon. Vehicle
controls stay on the same Action channel. MCP remains a slow decision tool;
a local tick controller should hold and adjust movement between decisions.

`act` accepts `fists`, `shiv`, `tack`, `flechette`, `scatter`, `rail` and
`sniper`, `repeater`, `arc` and `rocket` for `weapon_swap`; the server rejects unowned choices. The Sniper
Rifle is a found Cells weapon (70 damage, 32 tick cooldown, 90 unit reach);
the shared helper takes a carried, loaded Sniper for a hostile beyond the held
gun's reach and inside the Sniper's. Its scope is human presentation only; an
agent aims exactly as with every other gun. The Shiv is an optional
secret in M01's confiscation alcove: pool-less melee, quicker and harder than
fists, with no ammunition count. The shared helper keeps a loaded gun in hand
and draws the Shiv instead of fists only when every gun is dry. A claim that
found a secret keeps `"secret": true` on its pickup event in `get_events`. The `act` schema does not list `reload`. An agent keeps one ammunition count, and an `act` call that carries `reload` is a schema error. Scripted and
decision controllers use the shared equipment helper to find supplies and to
put away a gun whose count is empty. MCP still sends ordinary actions, never
direct inventory changes.

`act.throw_grenade: true` throws one carried grenade along the current aim;
release before another press. A short press survives newer released input until
the next tick. A successful throw takes the tick's attack admission without
changing the selected gun; an empty throw permits ordinary fire. The fuse is
two seconds of active simulation, with authoritative wall/floor bounce and blast
cover. `observe.grenades` reports live position and remaining fuse ticks;
`observe.explosions` reports resolved per-victim HP, armor and death evidence.
Grenade record counts have their own column; the six weapon slots retain their
indices. Self damage never awards a self frag.

`act.place_mine: true` throws one carried proximity mine along the current aim,
with the same rising-edge latch as a grenade. It sticks to the first surface,
arms for two seconds, then trips when a body comes within two metres in clear
sight, the placer included. `observe.loadout.proximity_mines` counts carried
mines (omitted while zero, four at most); `observe.mines` reports each placed
mine's surface normal, phase and phase window; its blast appears in
`observe.explosions` with radius 4.5. Mines have their own record column. A
malformed mine fact leaves the last valid observation in place.

`observe.auditors` lists living campaign Auditors with `repairs_left` and, while
channeling, the `channel_target` disabled body. Hit the Auditor or break its
sight to snap the channel; the shared controllers engage a channeling Auditor
before any nearer hostile.

`observe.players[].collidable` is the server's Boolean living-body eligibility.
Dead, detached, respawning, eliminated or unready campaign bodies do not block
walking. Legacy omission means true, still subject to HP and participation;
nonboolean values are invalid. Eligible characters and reachable mission
civilians block intersecting horizontal movement, preserving sliding and world
support. They do not become standing surfaces. Positions and accepted velocities
remain server facts; MCP sends the same ordinary action channel.

`observe.mission` carries the shared phase, attempt, party readiness/boarding and currently
legal prompts. `observe.map.mission` describes panel indices, approach positions
and the boarding area. `act.interact: true` presses Use; release with `false`
before another press. Range, aim, sight, gate changes and departure remain server
decisions. The shared local controller walks to mission controls when it has no
combat or equipment target. Map changes replace navigation even with the same ID.
For the M02 development mission, `observe.mission.m02` carries completed IDs,
objective count, prepared gate mask, the server-owned `ward_secured` and
`side_ward_secured` facts. `observe.map.m02_side_ward` identifies whether the
authored map has the optional room. When true, the mission state also carries
`evacuation` with its phase, two server-owned world-feet positions and final
`evacuated` fact. Freeing the side ward and evacuating both captives are
separate facts. This optional movement never gates
player departure. The mission state also carries the current arrival region or
physical use target. The target's decoration index refers to
`observe.map.presentation`.
`observe.map.m02_objectives` is present only for M02 and matches the mission's
objective count; numeric map IDs alone do not identify a mission.
M02 presentations may also contain `gate_locked` and `gate_open` lamp panels.
They mirror each gate's real state in the current map and are never use
targets; the adapter rejects a target that names one.
The adapter rejects targets that do not match the current map. `mission_ready`
accepts `persons_unknown` with the observed attempt; `objective_use` prompts
are issued per eligible participant. Single Player retains a separate M02
development entry without a save, while a completed M01 solo run may resume
into M02. In a durable run, `observe.mission.run` carries the same run ID and
remaining Episode I allowance plus `level_start_continues`; M02 starts at
attempt 1 even if M01 used a continue. Agents must use the observed mission ID
and attempt for readiness and retry.
For M03, `observe.map.m03` binds the transmitter solid, original aim and
approach, boarding region, departure panel and optional car definitions.
`observe.mission.m03` reports `mast_hp`, `mast_secured`, `train_secured`, each
car's `released` fact and authoritative captive feet, and the current objective.
`mast_disabled` is a `shoot` objective: aim and fire through the normal action
channel after its guards are cleared. `interact` cannot damage the mast.
Shutdown replaces MapInfo before presenting `party_departed` as a `use`
objective. Cars release automatically after their own guards and local approach;
they never gate boarding. `mission_ready` and `mission_continue` accept
`scheduled_service` with the observed attempt and run identity.

For M04, `observe.map.m04` binds the six arrival objectives, clinic shutter,
patient routes, roof departure and boarding region. `observe.mission.m04`
reports their ordered completion, clinic and rescue facts, authoritative
patient feet, first-round photographs and retained M03 car choices. The six
encounters must clear in order. An ordinary `act.interact` press opens the
secured clinic or departs from the roof; optional rescue never gates departure.
Same-map clinic changes clear mission steering until matching fresh state
arrives. `mission_ready` and `mission_continue` accept `notice_to_vacate` through
the existing tools. No separate campaign command path is needed.

For M07, `observe.map.m07` binds the five ordered arrival objectives, the
freight departure panel and approach, the boarding region and Latch's start.
`observe.mission.m07` reports ordered completion, the current objective and
the retained M03 to M06 outcomes. Each objective needs its encounter cleared
and a real arrival; the departure is an aimed `act.interact` at the freight
panel with the whole living ready party aboard. The rack in the curfew post
grants the Sniper Rifle (`sniper`); a Ranged Sweeper's `windup` phase is its
glint, and leaving its sight during the hold cancels the shot. The scope is
presentation only and has no action field. `mission_ready` and
`mission_continue` accept `declared_goods` through the existing tools.

Development mission parties allow four humans/agents together. `--campaign-run`
instead permits one lifetime combat seat; spectators do not take seats. Leaving
ends the solo run, and a callsign cannot reclaim it. Disk persistence belongs
to the owned local child with `--run-mode`; ordinary dedicated sessions do not
write that run file.

After reading the current mission, call `mission_ready` with its `id` and
`attempt`. Confirm the member's `ready` flag and active phase through `observe`;
a successful send alone does not prove acceptance. Initial combat waits for all
current readers. Late readers cannot pause play, act, collect supplies, take
damage or prevent a wipe. Readiness cannot be withdrawn and survives retries;
an unfinished reader must acknowledge the latest attempt. The supplied scripted
bot acknowledges automatically. MCP observation never does so on your behalf.

Callsigns are display labels. Simultaneous connections with the same requested
name receive distinct labels; they cannot reclaim another fighter by name.
Read the assigned label from the player UUID's snapshot entry.

A successful `join` confirms the connection. An initial `observe` can still show
a snapshot from before the fighter joined. Wait for `map` data and the
`self_player_id` entry in `players` before deriving movement or aim from that observation;
the first roster entry is not necessarily yours.

## What this is

`observe.record` is the latest private, server-authoritative participant record
for a capability-8 connection. It has its own tick and version, session/player
UUIDs, round and entry ticks, map, role, scope, status and `total`/`attempt` counts.
It arrives at most once per second during ordinary play, with immediate attempt
and outcome updates. Repeated observations are the same cumulative record, not
new awards. See [the record contract](../docs/protocol.md#participant-records).
The adapter validates it before observation; it does not persist a profile or
send commentary to other players. Disconnected observations do not prove an
outcome. Old servers can omit records.

A reference agent that drives a fighter from a decision model instead of an MCP client lives at [`agents/brain/README.md`](../agents/brain/README.md); it is the same agent role on the same wire, not a different kind of participant. MCP remains the bring-your-own door for any model.

The agent-adapter bridges external AI agents (LLMs, scripted bots, MCP clients) to the authoritative game server. It provides:

1. **MCP Server mode**: JSON-RPC 2.0 over stdio, compatible with MCP clients
2. **Scripted bot mode**: Standalone bot client for testing without MCP

Agents and humans share the same discrete action channel into the server. The adapter operates at slow control-plane rates (observe/act at ~1-10 Hz), not the combat tick (20 Hz).

Weapon selection is consumed once by the simulation. A newer movement packet
without `weapon_swap` does not cancel a pending selection; a newer explicit
selection replaces it. This also applies to fast local controllers.

`jump` is held input with a one-tick press latch: releasing before the next tick
does not erase a short tap. The latch is consumed even while airborne or dead;
holding jump cannot add upward thrust in the air. Geometry still decides which
steps can be walked onto. See the shared action contract in `docs/protocol.md`.

In arena play movement has momentum: a fighter reaches its 6 m/s run in three
ticks and slides about 0.17 m to a stop when the keys are released, and an
opposite key reverses it in one tick. `dodge` is a press, latched like a jump
tap: a standing fighter holding a direction is thrown that way at 9 m/s on a
low hop, with 0.75 s before the next. A slow agent loop that wants to stop on
a mark should release its keys a step early. A campaign mission keeps the
immediate 5 m/s step and has no dodge.

Blasts push arena fighters (`docs/protocol.md`, Movement): a Rocket fired at
your own feet is a rocket jump, so jump and fire straight down on the next
step to reach a 1.5 m deck edge, at the cost of some armour or health.

`again: true` on the podium (round `Ended`) asks for the next round now. When
every seated person and agent has asked, it opens two seconds after the result
instead of eight. `round_state.podium` shows who is ready and, in a Duel, the
series. A Duel (`rules.mode` `duel`) has two fighter seats; a third fighter is
refused with `match_full` and may watch.

Authored traversal maps use the same connection and action tools. `observe.map`
includes the validated optional `presentation` kits alongside finite geometry;
neither field can supply asset paths. A material list must match the solid count.
Optional face decorations pass the shared host-index, bounds and panel/light
budget validator. They contain registered kinds, never arbitrary text or paths.
The current M01 prototype has a human Clerk, two bot Sweepers, a transfer record
and shared lift departure. Departure does not load M02 in the same process; an
owned local run records it as the next mission. An idle combat agent is
not route-play evidence.

## MCP Tools

### `observe`

Get the current game state. The default detail is `brief`: compact text in `content`, and the same facts in `structuredContent` (self, threats in engagement order with `id`, `dist`, `bearing`, `hp`, `weapon`, and `campaign`, pads, and the round). `full` puts today's snapshot object in `structuredContent` and its JSON in `content`. `map` resends retained geometry. A connecting line is returned until the first snapshot.

**Input schema:**
```json
{"type": "object", "properties": {"detail": {"type": "string", "enum": ["brief", "full", "map"]}}, "additionalProperties": false}
```

`observe` also carries `map` once the server has sent it: `{"map_id", "map_name", "half_extent", "solids"}`, where `solids` are the axis-aligned boxes that block movement and shots. Test a line against them to tell a clear shot from a wall; the server uses the same boxes to decide hits.

**`detail: full` object (also `structuredContent`; the default reply is the brief text above this object):**
```json
{
  "tick": 12345,
  "players": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Bot1",
      "x": 10.5,
      "y": 1.5,
      "z": -5.2,
      "yaw": 1.57,
      "hp": 75,
      "just_fired": false,
      "behavior": "Aggressive",
      "score": 3,
      "weapon": "Flechette"
    }
  ],
  "round_state": "Active",
  "round_time_left": 120,
  "frag_limit": 10,
  "self_player_id": "550e8400-e29b-41d4-a716-446655440000",
  "recent_events": [
    {"event": "player_joined", "player": "Bot1", "role": "Agent"},
    {"event": "round_start", "round_number": 1, "frag_limit": 10, "time_limit": 180},
    {"event": "frag", "killer": "Bot1", "victim": "Bot2"},
    {"event": "respawn", "player": "Bot2"},
    {"event": "round_end", "winner": "Bot1", "reason": "Frag limit reached"},
    {"event": "player_left", "player": "Bot2"}
  ]
}
```

**Output (connecting state, before first snapshot):**
```json
{
  "status": "connecting",
  "message": "Waiting for first snapshot from server",
  "self_player_id": "550e8400-e29b-41d4-a716-446655440000",
  "recent_events": []
}
```

**Notes:**
- Returns connecting state until the first snapshot, unless admission or transport fails.
- A rejected hello returns `status: "disconnected"` and a retained
  `connection_error: {"code": "match_full", "message": "..."}` in full observe
  and `round_state`; brief observe names the reason. Draining events does not
  erase it. Explicit `join` returns an MCP tool error on rejection. A fresh
  attempt or successful Welcome clears the previous error; `act` stays refused
  until a usable snapshot arrives. Missing map identity is null, not Arena Duel.
- Snapshot may include `shot_results` (per-tick hit-confirm: `hit`, `damage`, `target_hp_after`). A scatter blast is one result per struck fighter plus one miss result, each with `trace.pellets`; all of one shooter's results in a tick are one shot
- `self_player_id`: UUID of your agent's player (null for spectators)
- `recent_events`: Last 50 game events (player joins/leaves, frags, respawns, round start/end) in chronological order. Each stored event is truncated near 2 KiB, and the ring also stops at 32 KiB. An inbound server frame above 64 KiB is ignored.
- Dead players (HP <= 0) are omitted from players array
- `behavior` field is present only for server-side bots
- `weapon` field shows current weapon: "Flechette" (balanced), "Rail" (precision), or "Scatter" (close-range)
- Call rate: 1-10 Hz is typical; faster is allowed but returns cached data between server ticks

### `act`

Send an action to control your agent's pawn.

**Input schema:**
```json
{
  "forward": false,
  "back": false,
  "left": false,
  "right": false,
  "turn_left": false,
  "turn_right": false,
  "fire": false,
  "weapon_swap": null,
  "look_at": { "player_id": "550e8400-e29b-41d4-a716-446655440000" }
}
```

All fields are optional. Movement and fire are booleans (default `false`).
`weapon_swap` accepts `"fists"`, `"shiv"`, `"tack"`, `"flechette"`, `"rail"`, `"scatter"`, `"sniper"`, `"repeater"`, `"arc"`, or `"rocket"`.

| In-game name | `weapon_swap` wire ID |
|---|---|
| Fists | `fists` |
| Shiv | `shiv` |
| Pistol | `tack` |
| Rifle | `flechette` |
| Railgun | `rail` |
| Shotgun | `scatter` |
| Sniper Rifle | `sniper` |
| Repeater | `repeater` |
| Arc | `arc` |
| Rocket Launcher | `rocket` |

`pistol` is a display name, not a wire alias. The schema and validator use the
native weapon list. M13 grants the Rocket Launcher; selecting it requires
ownership and firing spends finite Rockets through the ordinary server rules.
There is no `reload`. For `look_at`, prefer
`player_id` (UUID), or both `x` and `z` with optional world `y`. The server aims
at a player's chest, 1.22 units above the feet, when the belt is clearly open.
A counter, a lip the shot cone would still strike, or a gap under the chest
keeps the shot on the hip line. A Crawler or a Notary is aimed at the middle of
its body. World x/z without y aims
horizontally. Nonfinite/out-of-range floating-point coordinates are rejected.

Observed shot results include the firing weapon, 3D origin/endpoint, impact kind
and surface normal, plus a lethal-result flag. These remain available when the
shooter dies during that tick; do not infer shot identity from surviving pawns.
Older recordings can omit this evidence. See `../docs/protocol.md`.

**Output:**
```json
{
  "content": [{
    "type": "text",
    "text": "Action queued; observe to confirm the server outcome"
  }]
}
```

**Notes:**
- Movement, fire, duck and aim persist across ticks until the next `act` changes them.
- Each `act` replaces held inputs; omitted boolean fields become `false`.
- `interact`, grenade and mine presses latch rising edges; release before pressing again.
- All `true` fields are applied together on subsequent server ticks
- Movement keys combine (e.g., `forward + left` = diagonal)
- `weapon_swap` is processed immediately on the next tick
- `look_at` sets yaw and pitch after movement/turn on the next tick. The target
  must still be visible to the actual shot ray; target intent does not bypass cover.
  This is an agent tool. A shared-room human socket drops `look_at`. Yaw and
  pitch remain that pawn's aim.
- Server enforces weapon-specific cooldowns (Flechette: 200 ms, Rail: 1.0 s, Scatter: 450 ms)
- Call rate: 1-10 Hz typical for MCP agents; faster allowed but limited by server tick rate

### `speak`

Send a short off-tick taunt/callout (not sticky Action). Rate-limited on the server (~3s). Spectators see it; it appears in `recent_events` / `get_events`.

**Input schema:**
```json
{
  "text": "nice scrap"
}
```

**Rules:**
- `text` required string; trimmed; max 80 chars; no control characters
- Unknown fields -> schema error (`isError: true`)
- Empty / overlong -> schema error (`isError: true`)
- Rate-limited speak (mirrored ~3s / 60 ticks) -> `isError: true` (never a success toast on a no-op)
- Spectators / no player_id -> `isError: true`

A successful speak is copied onto that server's floor for the life of the process. A notice is a separate `board` post. This adapter does not send one yet. The wire shape is in `docs/protocol.md` under Wire board, and the slice is `docs/plans/wire-board.md`.

### `get_events`

Get recent game events (player joins/leaves, frags, hits, respawns, round start/end) explicitly.

**Input schema:**
```json
{
  "clear": false
}
```

All fields are optional. `clear` (boolean, default false): clear event buffer after retrieving.

**Output:**
```json
{
  "content": [{
    "type": "text",
    "text": "Recent events: [{\"event\":\"player_joined\",\"player\":\"Bot1\",\"role\":\"Agent\"},{\"event\":\"frag\",\"killer\":\"Bot1\",\"victim\":\"Bot2\"},{\"event\":\"respawn\",\"player\":\"Bot2\"}]"
  }]
}
```

**Notes:**
- Returns last 50 events in chronological order
- Event types: `player_joined`, `player_left`, `frag` (kill), `respawn`, `round_start`, `round_end`

Frag events can also include optional `killer_id` and `victim_id` UUIDs and a
resolved snake_case `weapon` ID, for example `rocket` or `article_blade`.
`get_events` preserves these fields. Older events omit them; missing weapon
does not identify a current held gun, and equal callsigns do not identify equal
participants. Prefer explicit IDs, including after bodies leave the snapshot.
- A `speak` event may carry an optional `to_id`: the one fighter the line is
  said to, such as a rule bot's frag taunt to its victim. Without it the line
  is for the whole room.
- Events are also included in `observe` output under `recent_events`
- Set `clear: true` to acknowledge events and reset buffer

### `join`

Ensure the agent is in the arena (Hello / Welcome). Optional `name`; when omitted, reuses `--name` / `FRAGR_AGENT_NAME`. Optional `body`: `human` or `synthetic`; when omitted, the last chosen body (from `--body` or an earlier `join`) is used.

**Input schema:**
```json
{
  "name": "ArenaFox",
  "body": "synthetic"
}
```

All fields optional. Unknown fields -> schema error (`isError: true`). Empty name -> schema error. A `body` other than `human` or `synthetic` -> schema error. The body is presentation only: it never changes the role, side, hit volume or any combat rule. Joining while already connected keeps the live pawn's body; leave and join to change it. A resumed pawn keeps its own.

**Behavior:**
- Already joined -> success, idempotent (`Already joined as '...'`)
- Not connected -> adapter reconnects, sends Hello, awaits Welcome
- Boot Hello-on-start remains valid; `join` is first-class for re-join after `leave`

### `leave`

Clean WebSocket disconnect from the arena.

**Input schema:**
```json
{}
```

No fields. Unknown fields -> schema error (`isError: true`).

**Behavior:**
- Connected -> success; clears local session; closes WebSocket
- Not connected -> `isError: true` (`leave rejected: not connected`)

### `mission_ready`

Finish or skip the opening for this participant using the current `observe.mission`:

```json
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"mission_ready","arguments":{"id":"recall_notice","attempt":1}}}
```

Both fields are required. Invalid, stale, disconnected, spectator and completed
mission requests return `isError: true`. Repeating a confirmed acknowledgment is
idempotent. Server state changes only after the ordinary WebSocket message is
processed. Use `observe` to confirm readiness and the shared phase before acting.
The readiness and continue schemas list every built mission from the same typed
stage list as saved campaign progression. Pending destinations are not offered.

Connected M13 uses `weight_of_permission` through these same tools. Matching
adapters advertise gameplay 55 and validate its registered objectives, worker
choices, actual arrivals and moving freight lift. After a fresh all-party lift
Use, the controller holds position while the authoritative deck moves. If it
returns after losing a rider, the party reboards and uses the same control.
Optional worker release never gates departure. No additional campaign tool or
per-tick MCP call is required.

Connected M14 uses `launch_authority` through the same tools. `observe.map.m14`
binds ordered objectives, the original jeep, departure control and registered
fallen-world geometry. `observe.mission.m14` reports support introduction,
actual machine fall and challenge receipts, while `observe.snapshot.walker`
continues to own combat pose, health and deadlines. Map replacement invalidates
steering until matching fresh mission facts arrive. The shared controller uses
ordinary infantry movement and finite equipment; driving remains optional.

Connected M15-M18 use `civic_pressure_valve`, `freedom_of_movement`,
`peace_without_interruption` and `all_systems_normal`. Their `map.m15` through
`map.m18` geometry must precede matching mission facts. Ordered completed
prefixes, objective controls, prompts and world flags are validated together;
a changed world suspends steering until fresh facts arrive. Minimum gameplay
versions are 51, 52, 53 and 54 respectively, including spectators. Rejection
retains the server's reason in `connection_error`, without a pending join.
These missions keep the same readiness, action and continue tools. Saved runs
refill continues only when entering M15 (Episode IV) and M18 (Episode V).

Connected M19 uses `planned_works` (minimum gameplay 55). `observe.map.m19`
binds eight ordered objectives, the coalition stores and waterworks controls,
the jetpack ceiling, authored jetpack hops and the presentation-only Latch
route and work marks; `gate_open` flips with the prepared open world.
`observe.snapshot.jetpacks` reports each worn pack's fuel and thrust, and
`observe.snapshot.paver_strips` each marked strip with its owner, origin,
yaw, length, half width, phase window and whether it is being worked. The
shared controller steps out of a strip before it is worked, prefers a Paver
preparing its strip over a nearer target, and flies an authored hop only with
enough fuel; the walking route always remains. Completing M19 promotes into
`local_exception`. Passenger Manifest and Common Carrier also require gameplay
55 for their carried M08 and M10 receipts.

Connected M20 uses `local_exception` (minimum gameplay 56). `observe.map.m20`
binds the five ordered arrivals, the refuge gate, the refuge line and the hold
clock; `observe.mission.m20` reports the crew, quay arrival, barricade, display,
reprieve, Latch and gate. `observe.snapshot.surveyor_marks` lists live Surveyor
discs. Every hostile body in M20 observes as `side: "inheritance"`: Surveyors
and Pavers with `control: "restoration"`, every other machine with
`control: "absorbed"`; nothing in the finale answers the Union. The shared controller holds each objective, finds a sightline on a
Surveyor its lesson is waiting on, fights back to its pier post rather than
chasing, keeps a gun that reaches its target, detours to pier crates it needs
(further when nearly dry) and leaves through the refuge gate once it opens. The scripted bot binds
the same geometry. Completing M20 records the campaign's survival with the
epilogue destination `still_here`.

`mission_ready` also accepts `still_here`, the epilogue a saved survival opens.
`observe.mission.epilogue` reports the completed objectives, the current one,
which survivors the run brought (`refuge`), the turn tick, whether the court is
`later`, and the people standing as bodies (`blocking`). The map's
`epilogue` facts give the ledger, the arrival region, the bench and every
person by world and pose. The shared controller walks to Latch's ledger, waits
out the turn, crosses the later court and sits on the bench; nothing in the
refuge is a target, so it never fires. The walk keeps no run and no record.

### `mission_continue`

In a solo run, `observe.mission.run` reports its UUID, status, remaining
continues and `level_start_continues`. Only its dead owner in `continue`
status can request a mission-start retry using the observed mission ID, run ID
and attempt. This applies to all built saved campaign missions through M19:

```json
{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"mission_continue","arguments":{"id":"recall_notice","run_id":"550e8400-e29b-41d4-a716-446655440000","attempt":1}}}
```

Stale, malformed, spectator and exhausted requests return `isError: true`.
A successful tool call only queues the request. Confirm `playing`, the increased
attempt and decreased allowance through `observe` before continuing. Retry keeps
opening readiness and restores entry equipment; it does not preserve supplies
collected later. The supplied scripted bot and decision controller automatically
use remaining continues. MCP observation never spends one for you.

### `round_state`

Current round summary without scraping full `observe`.

**Input schema:**
```json
{}
```

No fields. Unknown fields -> schema error (`isError: true`).

**Output (example):**
```json
{
  "connected": true,
  "self_player_id": "550e8400-e29b-41d4-a716-446655440000",
  "session_name": "ArenaFox",
  "round_state": "Active",
  "round_number": 3,
  "round_time_left": 90,
  "frag_limit": 10,
  "mode_name": "Scrap League",
  "playlist": "Larak Lot",
  "host_line": "HOST: LARAK LOT IS LIVE. FIGHT!",
  "pressure": null,
  "mvp": null,
  "mvp_frags": null,
  "podium": null,
  "map_id": 1,
  "map_name": "Larak Lot",
  "rules": {"mode": "tdm", "name": "Team Deathmatch: Rail Only", "mutators": ["rail-only"]},
  "team_scores": {"union": 4, "coalition": 6},
  "self_team": "coalition",
  "self_lives": null,
  "self_body": "synthetic",
  "booth": null,
  "last_round_start": {"event": "round_start", "round_number": 3},
  "last_round_end": null
}
```

`booth` is null for a fighter, always. A session started with `--watch` that
has not joined carries the newest booth facts there, as
[`spectator_facts`](../docs/protocol.md#spectatorfacts) states them:

```json
"booth": {
  "tick": 2400, "spree_step": 5,
  "pads": [{"id": "larak_rail", "kind": "weapon", "weapon": "Rail", "power": true, "back_in": 300}],
  "plate": {"id": "larak_custody_plate", "up": false, "back_in": 520, "holder": "550e8400-...", "armor": 143},
  "sprees": [{"id": "550e8400-...", "frags": 6}],
  "chains": [{"id": "550e8400-...", "frags": 2, "open_for": 31}]
}
```

Times are ticks (20 a second). Join each `id` against the snapshot players or
pickups for a name or a position. Health and armour for every fighter are in
the snapshot itself.

Fields come from the last snapshot plus the most recent `round_start` /
`round_end` in the events buffer. While Ended, Snapshot `mvp` / `mvp_frags` /
sticky `host_line` rehydrate mid-join even if `round_end` was missed. `map_id` /
`map_name` are always present (defaulting to Larak Lot if the snapshot omitted
them). `podium` is null mid-round; while Ended it is the Snapshot's podium:
`again` (ids that pressed `act.again`), `voters` (seated people and agents
waited on) and, in a Duel, `duel` (both fighters' round wins in this series).
`self_body` is your pawn's accepted body, null before a snapshot shows
you. Every participant in `observe` carries its own `body`; Union and
companion actors carry none.

`rules` is the server's rule set from `map_info` (or the last `round_start`
before `map_info` arrives): `mode` (`ffa`, `tdm`, `ctf`, `sabotage`, `conquest` or `duel`), `name`, `mutators`
(`rail-only`, `shotgun-only`, `fists-only`, `licence-to-kill`, `golden-rail`,
`two-lives`, `full-arsenal`), `friendly_fire` and `lives`, each omitted at its
default, and `start_kit`, always present: the weapons a fresh life holds. It is
null only before either arrives or on a campaign map. In free-for-all
`start_kit` is `["fists", "tack"]`: every life starts with the Pistol and Fists,
and the Rifle, Shotgun and Railgun belong to whoever takes their pad.
`observe` with `detail: full` carries your private `loadout`; read `weapons`
there before `weapon_swap`. A life holding only the Pistol should go and take a
gun: the scripted bot and the reference brain share one equipment helper that
walks to the nearest unowned gun pad whenever no rival is inside the Pistol's
reach (30 m), or with a fight on when that pad is a few steps away. An
objective, Sabotage and a campaign mission keep their own priorities. Holding
a found gun, the same helper fights. `team_scores` is the
snapshot's side frags in team deathmatch, else null. In CTF, `flags` lists
both stands and current flag state, `capture_scores` counts captures, and
`capture_limit` is the win target. `observe` carries the same typed snapshot.
`self_team` and `self_lives`
come from your own entry in the last snapshot; both are null outside a team or
lives-limited round, and while you are waiting to respawn. Read `rules` before
joining: in `tdm` a teammate shares your `team`, takes no damage unless
`friendly_fire` is true, and `observe` players carry `team`, `lives` and
`golden`. Under a weapon-only mutator, `weapon_swap` to another weapon is
ignored. Death ends a life's input: `act` presses sent while you wait to
respawn are dropped rather than queued, and a `fire` held at death or when the
body returns does nothing until an `act` releases it. The respawn wait is four
seconds in free-for-all and three in team deathmatch, capture the flag and
Conquest. `get_events` also returns `host_reaction` beats (`kind`, `variant`,
`player`, `other`, `team`, and `big` on a voiced big moment); the words live in
the client. Multikills (`double_frag` to `frag_storm`, three-second chains) and
mode-scaled sprees (`rampage`, `riot`, `untouchable`) are reaction kinds; there
is no separate `killstreak` event. `lead_change`, `flag_taken`,
`flag_captured`, `charge_planted`, `match_point` and `sudden_death` complete the
set. `round_state` adds `sudden_death`, true when an active arcade round ran
out of clock level: `round_time_left` is null because the clock has stopped,
and the next score wins. The full rule contract is in
[`docs/protocol.md`](../docs/protocol.md#match-rules).

**Sabotage.** On a Sabotage server `round_state` adds four fields, each null
elsewhere:

```json
{
  "sabotage": {"format": "short", "phase": "live", "round": 3, "period": 0, "half": 1,
    "half_rounds": 4, "rounds_to_win": 5, "score": {"union": 1, "coalition": 1},
    "alive": {"union": 4, "coalition": 3}, "clock_ticks": 1460,
    "charge": {"status": "carried", "position": [12.0, 0.0, -40.0], "carrier": "..."}},
  "sabotage_map": {"attackers": "coalition", "sites": [{"id": "a", "center": [-38.0, 0.0, -27.0], "radius": 3.0}, {"id": "b", "center": [-38.0, 0.0, 27.0], "radius": 3.0}], "callouts": [...]},
  "sabotage_objective": {"kind": "walk", "to": [-38.0, 0.0, -27.0]},
  "self_callout": "mid"
}
```

`sabotage` is the snapshot's round state and `sabotage_map` the static sites
and callouts from `map_info`. `sabotage_objective` is the shared Sabotage
controller's advice for you (the same one the playtest agents use): `idle`,
`walk` with a `to` point, `plant` or `defuse`. `self_callout` names the region
you stand in. The coalition carries and plants; the union defends and
defuses. To plant, stand still inside a site's radius while carrying the
charge and send `act` with `interact: true` and no movement until `planted`
arrives in `get_events` (60 ticks); to defuse, do the same within 1.75 m of the
planted charge as a union fighter (120 ticks). Movement, release or any damage
loses the progress. One life per round; after death you are absent from
`players` until the next round. Sides swap at half, so read `self_team` each
round. The contract is in
[`docs/protocol.md`](../docs/protocol.md#sabotage).

## Architecture

```
MCP Client (LLM/script)
    |
    | stdio (JSON-RPC 2.0)
    v
agent-adapter (this crate)
    |
    | WebSocket JSON
    v
game server (fragr-server)
```

**Roles:**
- `spectator`: Read-only, no player ID, cannot send actions
- `human`: Keyboard/mouse player, sends actions at input rate
- `agent`: Bot/MCP agent, sends actions via adapter or direct WS

## Protocol

The adapter speaks the same WebSocket JSON protocol as the Godot client and human players. See `docs/protocol.md` for full message schemas.

**Connection flow:**
1. Adapter connects to game server WebSocket (boot Hello with `--name`, or later via `join`)
2. Sends `Hello` with `role=agent`, name, and a ticket when `FRAGR_JOIN_SECRET` is set
3. Receives `Welcome` with assigned `player_id`
4. Begins receiving `Snapshot` messages at ~20 Hz (cached for `observe` / `round_state`)
5. MCP client calls `act` / `speak`; adapter forwards on the open socket
6. `leave` closes the socket cleanly; `join` reconnects and Hellos again

The receive task answers the server's liveness ping every 5 seconds, so an
idle agent between tool calls stays connected. A server kick (`idle_timeout`,
`rate_limited`, `malformed`, `address_banned`, `address_not_allowed`; see
`docs/protocol.md`) arrives as a final `error` and a close, and the session
reports disconnected until `join`. `act` forwards once per call, far below the
flood threshold.

## Implementation Notes

- MCP server logs to stderr to avoid polluting stdout (JSON-RPC channel)
- Last snapshot is cached in a Tokio mutex; `observe` returns the cached value
- `act` tool forwards actions directly to the game server WebSocket
- Scripted bot runs a simple chase-and-shoot AI loop for smoke testing

## Hardening (completed)

- [x] Session lifecycle: boot Hello / Welcome; first-class `join` / `leave` tools; clean disconnect
- [x] Observe returns full snapshot with round state, scores, time remaining
- [x] Act validates action schema and forwards to server
- [x] Scripted bot mode for end-to-end testing without MCP client
- [x] Same input pipeline as humans (shared `Action` message type)
- [x] MCP tools documented with schemas and examples

## Future (post-Slice 1)

- Session summaries: periodic `observe` with historical stats (kills, deaths, accuracy)
- Goal setting: agent declares intent (e.g., "flank target", "defend area")
- Low-Hz summaries for LLM context (not full snapshot spam)
- Clawbot integration: screenshot observations via separate tooling (spend-gated)

## Testing

```bash
# Run adapter tests
cargo test

# Manual smoke test (server must be running)
cargo run -- scripted-bot --name TestBot

# MCP client test (requires MCP-compatible client like Claude Desktop)
cargo run -- mcp < test_input.jsonl
```

Example `test_input.jsonl`:
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"observe","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"act","arguments":{"forward":true,"fire":true}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"round_state","arguments":{}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"leave","arguments":{}}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"join","arguments":{"name":"ArenaFox"}}}
```

## Campaign observations

The adapter sends current capability 33. M08 requires 31, maps with the Sniper
Rifle or a Ranged Sweeper require 30, maps with a campaign Auditor or mine
supply require 29, Sabotage requires 28, M06 requires 27, and other current
authored mission and discovery maps require 26. On M08, `observe.map.m08` carries the
archive contract (six arrivals, four support `nodes` with approach and aim,
the optional bays and cabinet, departure, boarding and the `seal_open` and
`machine_fallen` stage flags, which follow the world and return on a retry) and `observe.mission.m08` the
facts, including `node_hp`. On the `machine_wrecked` step the shared controller
walks to the next node's approach and fires at its aim; in the mine lesson it
throws one mine at the alcove mouth and holds.
M07 Declared Goods requires 32 for its strict town and crater envelope.
Encounter-bearing authored development maps with explicit jeep placements
require 39 for every role; shared arcade rooms retain the current 41 floor.
They use the existing `act` movement, `interact`, `seat`, aim and
fire fields. They add no mission readiness or campaign progression operation.
`observe` preserves each actor's typed `campaign` identity and attack phase.
`side: participant` includes human and external-agent allies. M02 adds one
`side: companion`, `kind: latch` actor after the guarded release. Its
`releasing`, `following`, and `firing` phases describe a server-owned ally, not
an MCP seat or an action target. It appears in `observe` for late observers,
but does not collect supplies or count toward the party or departure.
`side: inheritance` (capability 55) is equally hostile and always names its
`control`: `absorbed` for a former Union bot that keeps its chassis and learned
attacks, `restoration` for a restoration machine such as the `paver`. The
brief `observe` threat token reads `inheritance:absorbed/<kind>/<phase>` or
`inheritance:restoration/<kind>/<phase>`.
`side: union` identifies Clerk humans, Sweeper and Heavy Sweeper bots, fixed
Turrets, low Crawlers, stationary Jammers and stationary marksman Ranged
Sweepers (`kind`: `clerk`, `sweeper`, `heavy_sweeper`, `turret`, `crawler`,
`jammer`, `ranged_sweeper`). A Ranged Sweeper's `windup` is its scope glint:
its aim is locked and one Sniper shot resolves at `phase_ends` unless sight
breaks first. It sees a peeking head as well as an open body. Jammers introduced capability 23;
current Discovery maps require capability 26. A Jammer's dish telegraphs a committed delayed pulse, which can
be sidestepped or interrupted before launch. Its `Fists` wire weapon does not
mean it performs melee. Read live `projectiles` rather than treating its firing
phase as an instant gun hit. A Turret in `moving` is turning its head, not walking. Read
`windup` and `phase_ends` as the tell for
every kind. A Crawler's `leaping` phase is committed movement after a crouched
windup; its contact damage is resolved by the server. `crawler_scrabble` events
in `recent_events` and `get_events` carry a finite world position for the
mechanical warning, never text or a player identity. Never infer hostility from
a callsign,
body appearance or connection role. The scripted controller uses the shared
hostility predicate and excludes dead actors. MCP clients should follow the same
rule; dead enemies remain briefly for presentation. Zero-damage friendly
interceptions are not wounds. See [the wire contract](../docs/protocol.md#campaign-actor-identity).

The standalone Continuance Walker range requires gameplay 48. `observe.map.walker`
registers five physical body solids, three stations and bounded activation and
combat regions. `observe.snapshot.walker` carries actual health, phase deadlines,
accepted machine feet, the locked three-mark artillery lane, remaining shell
stock and traveling shell facts. The adapter accepts those samples only against
the current matching map and bounds, preserving the last valid observation on a
malformed sample. Existing `act` movement, aim, fire and finite equipment operate
the fight; there is no separate boss action or campaign door. The stock scripted
fighter does not yet plan this machinery counter automatically. This development
range does not unlock M14 or change saved campaign progression. See the
[Walker contract](../docs/protocol.md#continuance-walker-foundation-capability-48).
