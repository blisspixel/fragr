# fragr Network Protocol

WebSocket JSON protocol between clients and the authoritative server.

**Transport:** WebSocket JSON. The server binds `0.0.0.0:6767` by default; clients default to loopback (configurable).
**Format:** JSON text messages
**Tick rate:** ~20 Hz (50ms per tick)

Use matching client/server releases. The vertical-aim server accepts older actions
without pitch, and current readers accept older snapshots/recordings with pitch
defaulted to zero. Older servers can reject the new action field; this is not
protocol negotiation or a promise that mixed releases interoperate.

## Connection Flow

1. Client connects to WebSocket
2. Client sends `Hello` message with role and name
3. Server responds with `Welcome` message
4. Server begins broadcasting `Snapshot` messages at tick rate
5. Clients (human/agent roles) can send `Action` messages
6. Server may send `Event` messages for notable occurrences

**MCP agent-adapter session tools:** boot Hello-on-start remains valid. First-class tools `join` (Hello/Welcome, optional name, idempotent), `leave` (clean WebSocket disconnect; `isError` if not connected), and `round_state` (round fields from last snapshot + recent `round_start` / `round_end`) are documented in `agent-adapter/README.md`. There is no separate on-wire Leave message; leave is disconnect.

**Names and reconnect:** display names are not identity credentials. Joining
never evicts an existing fighter by name. The server removes control characters,
trims names to 24 Unicode scalars, uses `Player` for an empty result, and appends
` #2`, ` #3`, etc. on collisions, including collisions with rule bots. The final
label appears in snapshots and events; use player UUIDs for ownership. A reconnect
creates a new session. Only that connection's disconnect removes its fighter.
Authenticated session resumption remains planned.

## Message Types

### Client → Server

#### Hello

Initial handshake message. Must be sent immediately after connection.

```json
{
  "type": "hello",
  "role": "spectator" | "human" | "agent",
  "name": "PlayerName"
}
```

**Fields:**
- `role`: Connection role
  - `spectator`: Read-only, receives snapshots, cannot control a player
  - `human`: Keyboard/mouse player, receives snapshots, sends actions
  - `agent`: Bot/MCP agent, receives snapshots, sends actions
- `name`: Display name (shown in game and logs)
- `geometry_version`: Maximum understood solid format, including earlier formats.
  Current clients send `2`; omission means `1`. Before `Welcome`, the server sends
  `error` with code `unsupported_geometry` and closes connections below the
  selected map's requirement. Rotation uses the maximum across its whole roster.
  No player or spectator session is created on rejection. This is geometry
  compatibility, not general protocol or action-version negotiation.

#### Action

Sent by `human` or `agent` roles to control their player. All fields are optional booleans defaulting to `false`.

```json
{
  "type": "action",
  "forward": true,
  "back": false,
  "left": false,
  "right": false,
  "turn_left": false,
  "turn_right": false,
  "fire": false,
  "weapon_swap": "rail",
  "look_at": { "player_id": "550e8400-e29b-41d4-a716-446655440000" },
  "yaw": 1.5707963,
  "pitch": 0.25,
  "seq": 4123
}
```

World-point aim:

```json
{
  "type": "action",
  "look_at": { "x": 10.0, "z": -5.0 },
  "fire": true
}
```

**Fields:**
- `forward` / `back`: Move forward/backward
- `left` / `right`: Strafe left/right
- `turn_left` / `turn_right`: Rotate view left/right (incremental)
- `fire`: Fire weapon
- `jump`: Jump while grounded. The held value remains active until released;
  a press followed by release before the next tick is retained for that tick.
  The retained press is consumed once, including while airborne or dead, so it
  cannot create delayed jumps. Holding jump does not add thrust in the air.
- `weapon_swap`: (optional) Switch to weapon type: `"flechette"` | `"rail"` | `"scatter"`. The newest explicit choice is retained across input packets until a simulation tick consumes it once. A later packet without this field does not cancel an unconsumed choice.
- `look_at`: (optional) Authoritative target aim. Prefer `player_id` (UUID string),
  or both `x` and `z` with optional world `y`. A player target aims at the body
  centre, 0.9 units above its feet. A world point without `y` means horizontal aim.
  Valid target intent replaces yaw and pitch after movement. Missing targets,
  coincident points, and nonfinite coordinates leave the current aim unchanged.
- `yaw`: (optional) Client-owned absolute facing in radians. When present the server takes it as the fighter's yaw for this input, before movement, instead of turning at a fixed rate from the turn bits. Normalised into `[0, 2 pi)`; non-finite values are ignored and the turn bits apply as before. This is how a human client keeps the look axis off the network.
- `pitch`: (optional) Absolute vertical aim in radians, positive upward, clamped
  to +/-85 degrees. Missing or nonfinite values retain the last pitch, initially
  zero. Pitch does not redirect movement. Respawn resets it to zero.
- `seq`: (optional) Input sequence number. The server acknowledges the newest sequence it applied for this fighter in an `ack` message every tick. Clients that do not predict may omit it.

**Notes:**
- Continuous action fields use the latest held value. Weapon selection and a
  jump press survive intervening packets until one tick consumes them.
- All `true` fields are applied together on the next server tick
- Movement keys combine (e.g., forward + left = diagonal)
- `look_at` is applied after movement/turn so agents can strafe while locking aim
- `yaw` is applied **before** movement, so a fighter travels along the facing the client predicted for that same input
- Sending `yaw` disables the turn bits for that input; agents and older clients that send no `yaw` are unchanged
- Weapon swap is processed immediately on the next tick
- Server enforces rate limits and cooldowns (weapon-specific)
- Spectators that send actions are ignored
- Unknown fields are rejected (schema error). Sticky state is not overwritten by junk.
- MCP `act` returns `isError` on unknown keys, bad `weapon_swap`, or bad `look_at` (unknown nested keys, incomplete x/z, bad UUID). Empty/missing arguments are OK (all defaults).

#### SetDisplayBehavior

Agent-only observe chip. Echoed into Snapshot `PlayerState.behavior`. Never trusted for combat. Rule-bot behaviors still come from server `BotController`.

```json
{
  "type": "set_display_behavior",
  "behavior": "push_enemy"
}
```

**Rules:**
- `behavior` required; trimmed; max 32 Unicode scalars; no control characters; deny unknown fields
- Accepted only for `agent` role players that are not server rule bots
- Humans and spectators are ignored
- Brain clients publish stance names: `push_enemy`, `fall_back_heal`, `hold_angle`, `kite_distance`
- HUD short chips: PSH / HL / HLD / KIT

### Server → Client

#### Speak

Off-tick callout / taunt from a human or agent. Not sticky Action. Control-plane only.

```json
{
  "type": "speak",
  "text": "nice scrap"
}
```

**Rules:**
- `text` required; trimmed; max 80 Unicode scalars; no control characters; deny unknown fields
- Server rate-limits to one successful speak per player per 60 ticks (~3s)
- Rejected speaks emit no Speak event; the speaker receives a unicast `error` (`speak_rate_limited` or `speak_rejected`)
- MCP adapter mirrors the cooldown and returns tool `isError` (never a success toast on a no-op)
- Spectators cannot speak
- Named server rule bots may emit occasional Contested Frequency Speak events on frag/death/Warmup/killstreak via the same `try_speak` path (SPEAK_COOLDOWN applies; silent drop on rate-limit; Compliance boss excluded)


#### MapInfo

The arena's shape: its bounds and the solids that block movement and shots. Sent
to every connection on join, including spectators, and broadcast when the map
changes between rounds. It is not repeated every tick. Clients replace legacy
scene geometry with these solids so visible cover agrees with the server.

```json
{
  "type": "map_info",
  "map_id": 1,
  "map_name": "Arena Duel",
  "half_extent": 70.0,
  "solids": [
    {"min_x": 5.75, "max_x": 8.25, "min_z": -8.25, "max_z": -5.75, "top": 4.5},
    {"min_x": -8.6, "max_x": -5.4, "min_z": -7.2, "max_z": -5.2, "top": 0.5}
  ]
}
```

**Fields:**
- `half_extent`: half the width of the square arena, centred on the origin, so the playable area is `-half_extent` to `half_extent` on both axes. It varies by map: the roster runs from 55 to 160.
- `solids`: axis-aligned finite boxes shared by movement, shots and rendering.
- `bottom`: lower vertical bound, default zero. Nonzero values require geometry
  version 2, allowing rooms below balconies and ceilings.
- `top`: upper surface, default 4.5. Requires `0 <= bottom < top`. Ordinary steps
  are at most 0.6 high and require clearance for a 1.8-high standing body.
- `geometry_version`: required solid format. Omission means 1; ground-filled
  maps omit it and zero `bottom` fields to preserve legacy wire bytes. Raised
  volumes declare 2. Unknown versions and raised volumes declaring 1 are invalid.

Geometry bounds: finite half extent from 2 to 256; at most 2048 solids; finite
coordinates within -512 to 512; strictly increasing X and Z bounds. Navigation
also limits each grid column to eight walkable layers, total nodes to 524288,
edges to 4194304 and construction work. These are validation limits, not proven
playable map sizes or capacity claims. Invalid maps cannot replace live geometry.
Clients disconnect on malformed JSON or invalid map geometry rather than
continuing against a previous world. The decision brain and playtest controllers
also stop on messages that fail the shared server-message schema. The MCP adapter
retains its existing forward-compatible handling of unknown event objects.

Current built-in maps still use version 1. Version 2 support does not mean an
enclosed campaign mission is shipped.

Agents need this to tell a clear shot from a wall. Before it existed, the reference agents held the fire button through cover and their measured accuracy sat near 15 percent; with it, the same agents measure near 60. An agent that ignores `top` will think a stair tread is cover; one that reads it gets the same answer the server does. The Godot client builds the whole map from this message: the floor, the boundary and every solid at its own height. The MCP adapter stores it and returns it as `map` inside `observe`.

#### Ack

Unicast, once per tick, to a client whose input carried a `seq`. Carries the newest sequence the server applied to that client's fighter and the authoritative state it produced, which is what a predicting client reconciles against. Clients that send no `seq` (agents, spectators, older clients) never receive it.

```json
{
  "type": "ack",
  "seq": 4123,
  "tick": 88210,
  "x": 12.25,
  "z": -3.5,
  "yaw": 1.5707963,
  "pitch": 0.25
}
```

**Fields:**
- `seq`: the newest input sequence applied to this fighter
- `tick`: the server tick that applied it
- `x` / `z`: authoritative position after that tick
- `yaw`: authoritative horizontal facing after that tick
- `pitch`: authoritative vertical facing after that tick, default zero when
  reading older messages/recordings


### Solo Broadcast episode fields (Snapshot)

When the server runs `--solo-broadcast`, Snapshot may include:

- `episode_id` (e.g. `ep0`)
- `episode_title` (e.g. `Solo Broadcast: Calibration`)
- `episode_objective` (short objective chip)
- `episode_progress` (e.g. `NODS 2/5 | SEIZE JAMMER | AUDITOR`)
- `episode_phase` (`nods` / `jammer` / `auditor` / `won` / `failed`)

Events: `episode_start`, `episode_complete`, `episode_fail`. Omitted on normal MP.

### Welcome

Server response to `Hello`. Confirms connection and provides player ID.

```json
{
  "type": "welcome",
  "player_id": "550e8400-e29b-41d4-a716-446655440000" | null,
  "role": "spectator" | "human" | "agent",
  "mode_name": "Contested Frequency",
  "playlist": "Arena Duel"
}
```

**Fields:**
- `player_id`: UUID of the player entity (null for spectators)
- `role`: Echoed role from Hello
- `mode_name`: Named scrap-league identity (default Contested Frequency)
- `playlist`: Playlist under the league lie (default Arena Duel)

#### Error

Unicast control-plane rejection (not broadcast). Used when speak is dropped.

```json
{
  "type": "error",
  "code": "speak_rate_limited",
  "message": "speak rate limited; try again in a few seconds"
}
```

**Codes:** `speak_rate_limited`, `speak_rejected`

#### Snapshot

Periodic state broadcast containing all visible game entities. Sent at ~20 Hz.

```json
{
  "type": "snapshot",
  "tick": 12345,
  "players": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Bot1",
      "x": 10.5,
      "y": 1.5,
      "z": -5.2,
      "yaw": 1.57,
      "pitch": -0.1,
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
  "shot_results": [
    {
      "shooter_id": "550e8400-e29b-41d4-a716-446655440000",
      "shooter": "ArenaFox",
      "hit": true,
      "target_id": "660e8400-e29b-41d4-a716-446655440000",
      "target": "Bot1",
      "damage": 25,
      "target_hp_after": 75,
      "killed": false,
      "trace": {
        "weapon": "flechette",
        "origin": [10.5, 1.6, -5.2],
        "end": [15.0, 1.2, -5.2],
        "impact": {"kind": "fighter", "normal": [-1.0, 0.0, 0.0]}
      }
    }
  ],
  "mode_name": "Contested Frequency",
  "playlist": "Arena Duel",
  "pressure": "compliance",
  "host_line": "HOST: CONTINUANCE COMPLIANCE PING. APPROVED LANES ONLY.",
  "pickups": [
    {"id": "pad_rail", "kind": "weapon", "weapon": "Rail", "x": 12.0, "y": 0.4, "z": 12.0, "available": true},
    {"id": "pad_scatter", "kind": "weapon", "weapon": "Scatter", "x": -12.0, "y": 0.4, "z": -12.0, "available": false, "respawn_in": 80},
    {"id": "pad_flechette", "kind": "weapon", "weapon": "Flechette", "x": -12.0, "y": 0.4, "z": 12.0, "available": true},
    {"id": "pad_health_n", "kind": "health", "amount": 40, "x": 0.0, "y": 0.4, "z": 8.0, "available": true},
    {"id": "pad_health_s", "kind": "health", "amount": 40, "x": 0.0, "y": 0.4, "z": -8.0, "available": true},
    {"id": "pad_armor", "kind": "armor", "amount": 25, "x": 8.0, "y": 0.4, "z": 0.0, "available": true}
  ]
}
```

**Fields:**
- `tick`: Server tick counter
- `players`: Array of visible player states. A fighter waiting to respawn is not in it. There is no corpse on the wire: the server drops a player from the snapshot the moment it dies and puts it back three seconds later at its spawn point, so absence is how death looks to an agent. Watch for the `frag` and `respawn` events rather than inferring death from a health value, and do not read a missing fighter as one that has left the match.
  - `id`: Player UUID
  - `name`: Display name
  - `x`, `y`, `z`: Position in world space (arena is ±25 units)
  - `yaw`: Rotation in radians (0 = +X axis, counter-clockwise)
  - `pitch`: Vertical aim in radians, positive upward; defaults to zero in older
    messages. Eye spectators use this same value.
  - `hp`: Health points (0-100)
  - `armor`: Scrap armor (0-100, default 0); absorbs damage before HP
  - `just_fired`: True on the tick a weapon was fired (for muzzle flash)
  - `behavior`: (optional) Rule-bot tactics name, or Agent-set display label from `set_display_behavior`
  - `score`: Kills in current round
  - `weapon`: Current weapon name ("Flechette", "Rail", or "Scatter")
- `round_state`: (optional) Current round state ("Warmup", "Active", "Ended")
- `round_time_left`: (optional) Seconds left in Active (time limit) or Warmup countdown. Omitted while Ended.
- `frag_limit`: (optional) Frag limit for current round
- `shot_results`: (optional, omitted when empty) Every committed fire outcome on
  this tick, including shots from fighters killed during the same tick. Entries
  carry `shooter_id`, `shooter`, `hit`, optional `target_id`/`target`/`target_hp_after`,
  `damage`, `killed`, and `trace`. Do not join only against surviving `players` to
  count shots or infer their weapon.
- `mode_name`: Contested Frequency (scrap league that denies it exists)
- `playlist`: Arena Duel under the league lie
- `pressure`: (optional) Live pressure beat id. `"compliance_drone"` while the Compliance Drone is alive; `"compliance"` during Continuance compliance ping slow.
- `host_line`: Sticky Contested Frequency Host chrome for mid-join / mid-round observe. League Host line by default while Active (no pressure). During Warmup, Contested Frequency bumper names the map, dialed-in scrap roster (callsigns), and countdown seconds. Switches to the compliance Host line while pressure is live. While Ended, carries the MVP Host bumper. Clients show this on join without waiting for the next `round_start`.
- `mvp` / `mvp_frags`: (optional, present while Ended) Structured round MVP name and frag count for mid-join / `round_state` rehydrate. Omitted during Warmup and Active. Same selection as `round_end` MVP (top score / frags).
- `pickups`: (optional, omitted when empty) Scrap layout: `map_id` (1 Arena Duel / 2 Compliance Yard) and `map_name`. Mid-map pads (weapons, health, armor). Each entry: `id`, `kind` (`"weapon"` / `"health"` / `"armor"`, default `"weapon"`), optional `weapon` (weapon pads), optional `amount` (health/armor pads), `x`/`y`/`z`, `available`, optional `respawn_in` (ticks until the pad returns). Health pads heal +40 (cap max HP); armor scrap grants +25 (cap 100). Touch claim is authoritative on the server; clients only render.

**Notes:**
- Dead players (HP ≤ 0) are omitted from the snapshot
- Clients must handle players appearing/disappearing
- No delta compression in v1 (future optimization)
- Round fields present when round system is active

**Shot evidence:** current servers always include `trace`; old recordings omit
it and deserialize as absent. `trace.weapon` is the firing weapon in snake case.
`origin` and `end` are three finite world coordinates. `impact.kind` is `fighter`,
`solid`, or `range`. Fighter/solid impacts include an outward unit `normal`;
range exhaustion has no surface normal. The endpoint is the actual surface hit,
or the weapon range limit for a clear miss. A ray starting inside a body/solid
stops at its origin and uses the reverse ray direction as its presentation normal.

`hit` means the ray intersected a fighter. `damage` is incoming weapon damage
before armour absorption, including overkill; it is zero on a miss or when that
committed ray reaches a fighter already killed earlier in the same tick.
`killed` is true only for the shot that first takes the victim to zero HP. Older
records default it to false. Committed shots can trade kills; later hits cannot
award another frag for the same death. The following frag event reports the same
killer/victim pair. Clients render this evidence without resolving another hit.

#### Event

Notable game occurrences, broadcast after the snapshot for the tick that consumes
them. Connection-control unicasts may arrive between ticks.

**Frag Event:**
```json
{
  "type": "event",
  "event": "frag",
  "killer": "Bot1",
  "victim": "Bot2",
  "killer_score": 5
}
```

**Hit Event:** (damage applied; structured hit-confirm for agents)
```json
{
  "type": "event",
  "event": "hit",
  "shooter": "ArenaFox",
  "shooter_id": "550e8400-e29b-41d4-a716-446655440000",
  "target": "Bot1",
  "target_id": "660e8400-e29b-41d4-a716-446655440000",
  "damage": 25,
  "target_hp_after": 75
}
```

**Respawn Event:**
```json
{
  "type": "event",
  "event": "respawn",
  "player": "Bot2"
}
```

**Round Start Event:**
```json
{
  "type": "event",
  "event": "round_start",
  "round_number": 2,
  "frag_limit": 10,
  "time_limit": 180,
  "players": ["Bot1", "Bot2", "Bot3", "Bot4"],
  "previous_winner": "Bot1",
  "mode_name": "Contested Frequency",
  "playlist": "Arena Duel",
  "host_line": "HOST: CONTESTED FREQUENCY. ARENA DUEL. DEAD AIR DAN, NIGHTFALL ON THE SCRAP. FIGHT!"
}
```

**Speak Event:**

```json
{
  "type": "event",
  "event": "speak",
  "player": "ArenaFox",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "text": "nice scrap"
}
```

**Compliance Ping Event:** (mid-round Continuance pressure; fighters move at half speed while active)
```json
{
  "type": "event",
  "event": "compliance_ping",
  "message": "HOST: CONTINUANCE COMPLIANCE PING. APPROVED LANES ONLY.",
  "duration_ticks": 120
}
```

**Boss Spawn Event:** (mid-round Continuance Compliance Drone; killable Continuance actor)
```json
{
  "type": "event",
  "event": "boss_spawn",
  "name": "COMPLIANCE-DRONE",
  "boss_id": "550e8400-e29b-41d4-a716-446655440000",
  "message": "HOST: CONTINUANCE COMPLIANCE DRONE ON DECK. ARTICLE 7 ENFORCEMENT.",
  "hp": 200
}
```

**Boss Down Event:** (drone fragged; does not respawn)
```json
{
  "type": "event",
  "event": "boss_down",
  "name": "COMPLIANCE-DRONE",
  "boss_id": "550e8400-e29b-41d4-a716-446655440000",
  "killer": "Rusher",
  "message": "HOST: DRONE DOWN. CONTINUANCE DENIES THE INCIDENT. SCRAP ON."
}
```

**Killstreak Event:** (within-round multi-kill Host callout at streak 2 / 3 / 5)
```json
{
  "type": "event",
  "event": "killstreak",
  "player": "Rusher",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "streak": 2,
  "tier": "double",
  "message": "HOST: DOUBLE FREQUENCY. Rusher DENIES THE DENIAL."
}
```

Tiers: `double` (2), `triple` (3), `rampage` (5). Contested Frequency Host voice. Resets on death and round boundaries. Does not overwrite sticky Snapshot `host_line`.

**Pickup Event:** (player touched an available mid-map pad; weapon swap, heal, or armor scrap)
```json
{
  "type": "event",
  "event": "pickup",
  "player": "Rusher",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "kind": "weapon",
  "weapon": "Rail",
  "pickup_id": "pad_rail"
}
```

Health example:
```json
{
  "type": "event",
  "event": "pickup",
  "player": "Rusher",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "kind": "health",
  "amount": 40,
  "pickup_id": "pad_health_n"
}
```

**Round End Event:**
```json
{
  "type": "event",
  "event": "round_end",
  "winner": "Bot1",
  "reason": "Frag limit reached",
  "final_scores": [
    {"name": "Bot1", "score": 10},
    {"name": "Bot2", "score": 7},
    {"name": "Bot3", "score": 3},
    {"name": "Bot4", "score": 2}
  ],
  "winner_score": 10,
  "mvp": "Bot1",
  "mvp_frags": 10,
  "host_line": "HOST: ROUND MVP. Bot1 WITH 10 FRAGS. CONTINUANCE DENIES THE PODIUM."
}
```

MVP is the top scorer (same selection as `winner`). `mvp` / `mvp_frags` / `host_line` sell Contested Frequency Host podium chrome. While the round is Ended, Snapshot carries sticky `host_line` plus structured `mvp` / `mvp_frags` for mid-join / observe / `round_state` rehydrate. Default Ended linger is 8 seconds (160 ticks at 20 Hz) so the podium can be read.

**Player Joined Event:**
```json
{
  "type": "event",
  "event": "player_joined",
  "player": "NewPlayer",
  "role": "agent",
  "round_number": 2,
  "player_count": 5
}
```

**Player Left Event:**
```json
{
  "type": "event",
  "event": "player_left",
  "player": "OldPlayer",
  "score": 7,
  "round_number": 2,
  "player_count": 4
}
```

**Fields:**
- `event`: Event type (`frag`, `hit`, `respawn`, `round_start`, `round_end`, `player_joined`, `player_left`, `compliance_ping`, `boss_spawn`, `boss_down`, `speak`, `pickup`, `killstreak`)
- `kind`: (pickup only) Pad kind: `"weapon"` / `"health"` / `"armor"` (default `"weapon"`). Weapon pads also carry `weapon`; health/armor pads carry `amount`.
- `killer` / `victim`: Player names involved in frag
- `killer_score`: Killer's score after the frag
- `streak` / `tier` / `message`: Killstreak Host callout (tiers `double` / `triple` / `rampage`)
- `mvp` / `mvp_frags` / `host_line`: Round-end MVP Host bumper (top score / frags; Contested Frequency voice)
- `shooter` / `target` / `shooter_id` / `target_id` / `damage` / `target_hp_after`: Hit event fields
- `player`: Player name for respawn, join, or leave
- `role`: Role of joining player ("spectator", "human", "agent")
- `round_number`: Current round number (starts at 1)
- `player_count`: Current number of players after join/leave
- `score`: Player's score when leaving
- `players`: List of all player names in the match (round_start)
- `previous_winner`: Winner of the previous round (null for first round)
- `frag_limit`: (optional) Frag limit for the round (null if time-only)
- `time_limit`: (optional) Time limit in seconds (null if frag-only)
- `winner`: (optional) Winner name if any (null for draw/time)
- `winner_score`: (optional) Winner's final score
- `final_scores`: Array of PlayerScore objects (name, score) sorted by score descending
- `reason`: Round end reason ("Frag limit reached", "Time limit reached", etc.)

**Notes:**
- Events are sent asynchronously as they occur (off the snapshot tick)
- MCP clients receive events in two ways:
  - Buffered in the `recent_events` field of the `observe` tool response (last 50 events)
  - Via the dedicated `get_events` tool for explicit retrieval
- Events capture match drama (frags, respawns, rounds) without forcing agents onto the combat tick

## Implementation Notes

### Arena Bounds
- Size: 50×50 units (±25 from origin)
- Floor at Y=0
- Players spawn at Y=1.5
- Walls prevent movement outside bounds

### Combat
- **Weapon types**: Three roles, each killing an unarmoured fighter in a comparable time by a different route.
  - **Flechette** (default): Mid workhorse
    - Damage: 25 HP, four hits to kill
    - Cooldown: 4 ticks (0.20 s), so 0.60 s to kill
    - Dispersion: 0.045 radians (2.6 degrees)
    - Range: 40 units
  - **Rail**: Long precision
    - Damage: 80 HP, two hits to kill
    - Cooldown: 20 ticks (1.00 s), so 1.00 s to kill
    - Dispersion: 0.012 radians (0.7 degrees)
    - Range: 60 units
  - **Scatter**: Close shred
    - Damage: 40 HP, three hits to kill
    - Cooldown: 9 ticks (0.45 s), so 0.90 s to kill
    - Dispersion: 0.20 radians (11 degrees)
    - Range: 12 units
    - Falloff: full damage to 4 units, then linearly down to 35 percent at 12
- **Hitscan**: One unit 3D ray from the shooter's eye, 1.6 units above its feet.
  Two seeded samples select a uniform disk perpendicular to aim, projected inside
  the weapon's dispersion cone. The nearest finite fighter cylinder wins
  (radius 0.5, height 1.8), subject to weapon range and earlier solid/floor hits.
  Cover uses the same ray through volumes from ground to their authored top.
  No automatic vertical aim or aim-assist cone is applied. Falloff uses traveled
  3D distance to the hit surface. Combat RNG results change from the previous
  horizontal-only model; existing recorded messages remain readable.
- **Respawn delay**: 60 ticks (3 seconds)

### Movement
- **Speed**: 5 units/second
- **Turn speed**: 2 radians/second, used only when an input carries no `yaw`
- **Facing**: a client-owned absolute `yaw` on the Action wins and is applied before the move
- **Collision**: Simple AABB with 0.5 unit radius

### Round System
- **Warmup**: 2 seconds (40 ticks) with Contested Frequency Host countdown drama on Snapshot (`host_line` + `round_time_left`; Godot full-frame Warmup TV with GOES LIVE IN N)
- **Frag limit**: Default 10 kills
- **Time limit**: Default 180 seconds (3600 ticks)
- **End delay**: 8 seconds (160 ticks) between rounds
- **Scoring**: Per-round kills, reset each round
- **Tied podiums**: Score descending, then callsign ascending. MVP uses that same ordering.
- **Persistence**: Bots remain active when humans leave

## Example Session

```
// Client connects and identifies
C→S: {"type": "hello", "role": "agent", "name": "MyBot"}

// Server welcomes
S→C: {"type": "welcome", "player_id": "...", "role": "agent"}

// Round starts after warmup
S→C: {"type": "event", "event": "round_start", "round_number": 1, "frag_limit": 10, "time_limit": 180}

// Server sends periodic snapshots
S→C: {"type": "snapshot", "tick": 1, "players": [...], "round_state": "Active", "round_time_left": 180, "frag_limit": 10}
S→C: {"type": "snapshot", "tick": 2, "players": [...], "round_state": "Active", "round_time_left": 180, "frag_limit": 10}

// Client sends actions
C→S: {"type": "action", "forward": true, "fire": false}
C→S: {"type": "action", "turn_right": true, "fire": true}

// Server announces frag
S→C: {"type": "event", "event": "frag", "killer": "MyBot", "victim": "Bot1"}

// More snapshots (with updated scores)
S→C: {"type": "snapshot", "tick": 45, "players": [{"id": "...", "name": "MyBot", "score": 1, ...}], ...}

// Round ends when limit reached
S→C: {"type": "event", "event": "round_end", "winner": "MyBot", "reason": "Frag limit reached"}

// Next round starts after delay
S→C: {"type": "event", "event": "round_start", "round_number": 2, "frag_limit": 10, "time_limit": 180}
```

## Future Considerations (Post-Slice 1)

Offline recordings reuse these exact message types. Their versioned container,
verification, and CPU report schema are documented in [`BENCHMARK.md`](BENCHMARK.md).
Recording metadata is not sent on the live socket.

- **Binary protocol**: Replace JSON with efficient binary (bincode, flatbuffers)
- **Delta compression**: Send only changed fields
- **Interest management**: Filter snapshots by visibility/distance
- **UDP option**: Low-latency channels for actions (alongside WS for reliability)
- **Prediction**: Client-side movement prediction for smoother human play
