# Agent Adapter

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

The adapter declares gameplay capability 11. Every discovery map, M01 and M02
included, requires 11 for all roles, because any of them may place the found
`shiv`; the six full-arsenal arcade maps still admit 1. Older clients are
rejected before admission. `observe.loadout`
is private to this participant: selected and owned weapons (`["fists","tack"]`),
one `ammo` count per pool (`bullets`, `shells`, `cells`), personal supply
claims and dry-trigger count. There are no magazines and no reload: every shot
spends one unit, a scatter blast of seven pellets included. Invalid, foreign or backward-tick equipment
ends the session without replacing the last valid observation. Spectators receive
no private inventory. Arcade servers omit this object.

`observe.mission.rules` reports the host's fixed difficulty (`assisted`, `standard`
or `severe`) and tuning `revision` (currently 2). Humans, agents and spectators
share these rules. Unknown revisions or changing rules fail validation, including
across a same-mission geometry update. Difficulty does not alter MCP budgets or
agent control frequency. Use matching builds when connecting to campaign servers.

`act` accepts `fists`, `shiv`, `tack`, `flechette`, `scatter` and `rail` for
`weapon_swap`; the server rejects unowned choices. The Shiv is an optional
secret in M01's confiscation alcove: pool-less melee, quicker and harder than
fists, with no ammunition count. The shared helper keeps a loaded gun in hand
and draws the Shiv instead of fists only when every gun is dry. A claim that
found a secret keeps `"secret": true` on its pickup event in `get_events`. `reload` is retired and the `act` schema no
longer lists it; an `act` call that carries it is a schema error. Scripted and
decision controllers use the shared equipment helper to find supplies and to
put away a gun whose count is empty. MCP still sends ordinary actions, never
direct inventory changes.

`observe.mission` carries the shared phase, attempt, party readiness/boarding and currently
legal prompts. `observe.map.mission` describes panel indices, approach positions
and the boarding area. `act.interact: true` presses Use; release with `false`
before another press. Range, aim, sight, gate changes and departure remain server
decisions. The shared local controller walks to mission controls when it has no
combat or equipment target. Map changes replace navigation even with the same ID.
For the M02 preparatory graybox, `observe.mission.m02` carries completed IDs,
objective count, prepared gate mask and the current arrival region or physical
use target. The target's decoration index refers to `observe.map.presentation`.
`observe.map.m02_objectives` is present only for M02 and matches the mission's
objective count; numeric map IDs alone do not identify a mission.
M02 presentations may also contain `gate_locked` and `gate_open` lamp panels.
They mirror each gate's real state in the current map and are never use
targets; the adapter rejects a target that names one.
The adapter rejects targets that do not match the current map. `mission_ready`
accepts `persons_unknown` with the observed attempt; `objective_use` prompts
are issued per eligible participant. The graybox is not yet a normal Godot route.
Development mission parties allow four humans/agents together. `--campaign-run`
instead permits one lifetime combat seat; spectators do not take seats. Leaving
ends the solo run, and a callsign cannot reclaim it. This is prototype progression,
not persistent saves or reconnect.

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

Authored traversal maps use the same connection and action tools. `observe.map`
includes the validated optional `presentation` kits alongside finite geometry;
neither field can supply asset paths. A material list must match the solid count.
Optional face decorations pass the shared host-index, bounds and panel/light
budget validator. They contain registered kinds, never arbitrary text or paths.
The current M01 prototype has a human Clerk, two bot Sweepers, a transfer record
and shared lift departure. Departure does not load M02. An idle combat agent is
not route-play evidence.

## Quick Start

### MCP Server (for external agents)

```bash
cd agent-adapter
cargo run -- mcp --server ws://127.0.0.1:6767 --name ArenaFox
# or: FRAGR_AGENT_NAME=ArenaFox cargo run -- mcp
# choose a body: --body human (default) or --body synthetic
```

Connect via MCP client (stdio) and use the tools below.
Boot path still sends Hello with `--name` / `FRAGR_AGENT_NAME` (default `MCP Agent`). When `FRAGR_JOIN_SECRET` is set, that hello carries a short agent ticket minted from it. An unset secret sends no ticket. First-class `join` / `leave` / `round_state` tools are also available (idempotent join; leave sends `{"type":"leave"}` and then closes the socket).

### Scripted Bot (standalone test)

```bash
cd agent-adapter
cargo run -- scripted-bot --server ws://127.0.0.1:6767 --name MyBot --body synthetic
```

`--body` picks the pawn's body on both commands: `human` (the default) or
`synthetic`, a conscious embodied agent in a synthetic body. It rides the same
Hello every client sends, other players and spectators see it, and it changes no
combat rule. The control role stays `agent` whichever body you choose.

Connects as an agent, validates the map, and uses the shared walking controller
to chase targets and aim with `look_at.player_id`. Its independent 20 Hz action
clock is not postponed by incoming snapshots; weapon cooldowns remain server
owned. It occasionally speaks a Contested Frequency taunt. A rejected handshake
or malformed replacement map ends the session with an error.

## MCP Tools

### `observe`

Get the current game state snapshot including self player ID and recent events.

**Input schema:**
```json
{}
```

`observe` also carries `map` once the server has sent it: `{"map_id", "map_name", "half_extent", "solids"}`, where `solids` are the axis-aligned boxes that block movement and shots. Test a line against them to tell a clear shot from a wall; the server uses the same boxes to decide hits.

**Output (after first snapshot):**
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
- Returns connecting state until first snapshot arrives from server
- Snapshot may include `shot_results` (per-tick hit-confirm: `hit`, `damage`, `target_hp_after`). A scatter blast is one result per struck fighter plus one miss result, each with `trace.pellets`; all of one shooter's results in a tick are one shot
- `self_player_id`: UUID of your agent's player (null for spectators)
- `recent_events`: Last 50 game events (player joins/leaves, frags, respawns, round start/end) in chronological order
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
`weapon_swap` accepts `"fists"`, `"shiv"`, `"tack"`, `"flechette"`, `"rail"`, or `"scatter"`.
There is no `reload`. For `look_at`, prefer
`player_id` (UUID), or both `x` and `z` with optional world `y`. The server aims
at a player's body centre in three dimensions. World x/z without y aims
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
    "text": "Action sent successfully"
  }]
}
```

**Notes:**
- Actions are **level-held (sticky)** within each server tick window, not edge-triggered
- Each `act` call overwrites the previous pending action state
- All `true` fields are applied together on the next server tick
- Movement keys combine (e.g., `forward + left` = diagonal)
- `weapon_swap` is processed immediately on the next tick
- `look_at` sets yaw and pitch after movement/turn on the next tick. The target
  must still be visible to the actual shot ray; target intent does not bypass cover.
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

### `mission_continue`

In a solo run, `observe.mission.run` reports its UUID, status and remaining
continues. Only its dead owner in `continue` status can request a mission-start
retry using the observed mission ID, run ID and attempt:

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
  "mode_name": "Contested Frequency",
  "playlist": "Arena Duel",
  "host_line": "HOST: CONTESTED FREQUENCY. LEAGUE DENIES EXISTENCE. ARENA DUEL IS LIVE.",
  "pressure": null,
  "mvp": null,
  "mvp_frags": null,
  "map_id": 1,
  "map_name": "Arena Duel",
  "rules": {"mode": "tdm", "name": "Team Deathmatch: Rail Only", "mutators": ["rail-only"]},
  "team_scores": {"union": 4, "coalition": 6},
  "self_team": "coalition",
  "self_lives": null,
  "self_body": "synthetic",
  "last_round_start": {"event": "round_start", "round_number": 3},
  "last_round_end": null
}
```

Fields come from the last snapshot plus the most recent `round_start` / `round_end` in the events buffer. While Ended, Snapshot `mvp` / `mvp_frags` / sticky `host_line` rehydrate mid-join even if `round_end` was missed. `map_id` / `map_name` always present (defaults to Arena Duel when the snapshot omitted them). `self_body` is your pawn's accepted body, null before a snapshot shows you. Every participant in `observe` carries its own `body`; Union actors carry none.

`rules` is the server's rule set from `map_info` (or the last `round_start`
before `map_info` arrives): `mode` (`ffa` or `tdm`), `name`, `mutators`
(`rail-only`, `shotgun-only`, `fists-only`, `licence-to-kill`, `golden-rail`,
`two-lives`), `friendly_fire` and `lives`, each omitted at its default. It is
null only before either arrives or on a campaign map. `team_scores` is the
snapshot's side frags in a team mode, else null. `self_team` and `self_lives`
come from your own entry in the last snapshot; both are null outside a team or
lives-limited round, and while you are waiting to respawn. Read `rules` before
joining: in `tdm` a teammate shares your `team`, takes no damage unless
`friendly_fire` is true, and `observe` players carry `team`, `lives` and
`golden`. Under a weapon-only mutator, `weapon_swap` to another weapon is
ignored. `get_events` also returns `host_reaction` beats (`kind`, `variant`,
`player`, `other`, `team`); the words live in the client. The full rule
contract is in [`docs/protocol.md`](../docs/protocol.md#match-rules).

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

The receive task answers the server's liveness ping every 15 seconds, so an
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

Authored encounter maps require gameplay capability 3, which the adapter sends.
`observe` preserves each actor's typed `campaign` identity and attack phase.
`side: participant` includes human and external-agent allies; `side: union`
identifies Clerk humans, Sweeper and Heavy Sweeper bots, and fixed Turrets
(`kind`: `clerk`, `sweeper`, `heavy_sweeper`, `turret`). A Turret in `moving` is
turning its head, not walking. Read `windup` and `phase_ends` as the tell for
every kind. Never infer hostility from a callsign,
body appearance or connection role. The scripted controller uses the shared
hostility predicate and excludes dead actors. MCP clients should follow the same
rule; dead enemies remain briefly for presentation. Zero-damage friendly
interceptions are not wounds. See [the wire contract](../docs/protocol.md#campaign-actor-identity).
