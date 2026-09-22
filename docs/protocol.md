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

`Welcome` assigns the session identity; it does not guarantee that the first
snapshot already contains that fighter. A queued snapshot can predate the join.
Wait for validated map data and a snapshot containing the welcomed `player_id`
before initializing position or aim. Match by UUID, never roster index or name.

**MCP agent-adapter session tools:** boot Hello-on-start remains valid. First-class tools `join` (Hello/Welcome, optional name, idempotent), `leave` (clean WebSocket disconnect; `isError` if not connected), and `round_state` (round fields from last snapshot + recent `round_start` / `round_end`) are documented in `agent-adapter/README.md`. There is no separate on-wire Leave message; leave is disconnect.

**Names and resume:** display names are not identity credentials. Joining
never evicts an existing fighter by name. The server removes control characters,
trims names to 24 Unicode scalars, uses `Player` for an empty result, and appends
` #2`, ` #3`, etc. on collisions, including collisions with rule bots. The final
label appears in snapshots and events; use player UUIDs for ownership. A client
that sends `resume` keeps that same pawn across a dropped socket for 200 ticks
(ten seconds). Input stops while the socket is gone. The body can still be shot.
`leave` removes it immediately. A hello without `resume` still removes the pawn
on close, which is what older clients do. The resume token is not a join ticket
and does not rewind ticks, input sequence, or inventory.

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
- `ticket`: optional. Absent when the server has no join secret. When
  `FRAGR_JOIN_SECRET` is set, a `human` or `agent` hello must carry
  `v1.<unix exp>.<human|agent>.<64 lowercase hex>`. The hex is HMAC-SHA256 over
  `fragr-join-v1`, the expiry, and the role, using that secret. The server
  accepts an expiry from 15 seconds ago through 75 seconds ahead. A spectator
  hello is not ticketed. A bad ticket is `join_rejected` before a seat is taken.
  The same ticket can be presented again until it expires. It does not name the
  player and it does not by itself resume a dropped pawn.
- `resume`: optional. Absent means a dropped socket removes the pawn. An empty
  string asks for a resume token on `Welcome`. A token rebinds the parked pawn
  and the server answers with a new token. A bad or expired token is
  `resume_rejected` and does not create a second pawn. Spectators omit it.
- `geometry_version`: Maximum understood solid format, including earlier formats.
  Current clients send `2`; omission means `1`. Before `Welcome`, the server sends
  `error` with code `unsupported_geometry` and closes connections below the
  selected map's requirement. Rotation uses the maximum across its whole roster.
  No player or spectator session is created on rejection. This is geometry
  compatibility, not general protocol or action-version negotiation.
- `gameplay_version`: maximum understood gameplay contract. Current clients send
  `8`; omission means `1`. Discovery-only maps require 2, maps with authored
  encounters require 3, and mission sequences require 6 for shared difficulty.
  Versions 4 and 5 introduced physical controls and party readiness respectively;
  they cannot enter current missions. Solo runs require 7 for explicit continues.
  Version 8 adds private participant records. Record delivery is gated by the
  client's advertised capability; earlier clients keep their existing messages.
  Use matching campaign server/client builds.
  Older clients of every role are rejected before `Welcome`
  with `unsupported_gameplay`. This capability is separate from geometry. The six
  full-arsenal arcade maps still accept 1.

Admission rejection also places its stable error code in a WebSocket policy-close
reason. Clients may receive the final text and close in one poll; use that reason
if the text has already been retired. The server bounds the close handshake at
two seconds and never admits rejected connections.

Development mission servers admit at most four participants, sharing slots across human and
agent roles. Spectators do not take slots. A full party rejects additional
participants with `party_full` before `Welcome`; disconnect returns the seat.
Local campaign and `--campaign-run` hosts reserve one lifetime combat seat instead.
After its first successful admission, additional fighters receive `run_seat_closed`,
including after the owner disconnects. Spectators remain admissible. Callsigns
cannot reclaim the owner. A failed handshake before admission does not consume it.

Each connection is also bounded before that seat exists. Incoming text is capped
at 64 KiB per frame and per message. The WebSocket handshake and the first
hello each have five seconds. The process holds at most 64 connections, and
32 from one address. Past either cap the server sends `connection_limit` or
`address_limit` and closes. A stalled handshake or a client that never says
hello releases its slot. A quiet spectator is not dropped for silence: after
hello, snapshots are the server's traffic, and an idle kick would end watch
mode. Further inbound text, including actions, is limited to a burst of
64 and 256 per second. Extra messages are dropped and the player stays
connected. A client that asked for resume keeps its pawn for ten seconds
after a drop. `{"type":"leave"}` removes that pawn immediately. The grace
does not rewind the simulation. When it ends, the leave is the same as a
disconnect: a solo run whose owner is gone becomes abandoned.

`GET /status` on the game port, before any WebSocket upgrade, returns a JSON
`LiveStatus` (`schema_version` 2): `kind` (`arena` or `campaign`), map name,
round, tick, fighters, humans, agents, bots, and connections. A missing `kind`
is not an arena. It does not list callsigns or addresses, and it does not take
a connection slot. It is a host probe. Watching and playing happen in the Godot
app. The timing percentiles stay on the server log.

### Mission sequence

Mission maps include optional `mission` metadata in `MapInfo`: registered `id`
(`recall_notice`), `record` and `departure` targets, and a `boarding` feet-position
box with finite `min`/`max`. Each target has a `decoration` index into the validated
presentation and a supported `approach: [x,y,z]`. The actual use point is the
centre of that visible panel, including its face offset. The record uses
`terminal`; departure uses `lift_control`. Targets never contain scripts or text.

`Action.interact` is an optional boolean, false by default. Its rising edge is
latched through newer released input until the simulation consumes it. A held
button does not activate another target. A living participant must aim within
18 degrees of the panel, within 2.5 metres from their eye, with unobstructed sight.
The server selects the legal target; clients cannot submit an interaction ID.

The authority sends `{"type":"mission","tick":42,"state":{...}}` after map data
and before the corresponding snapshot whenever shared state changes. `state` is:

- `id`: `recall_notice`; `attempt`: positive retry revision; `changed_at`: tick of
  the last phase change/reset, no later than the message tick.
- `phase`: `briefing`, `find_transfer`, `reach_lift`, or `departed`.
- `rules`: required `{difficulty,revision}`. Difficulty is `assisted`, `standard`
  or `severe`; revision is exactly `1`. Unknown fields/revisions are invalid.
  The host chooses once before admission. Geometry changes, death, retries and
  joining participants preserve these rules. Clients cannot change them through
  actions or readiness; agent observations contain the same rules as human UI.
- `party`: up to four `{id,name,ready,alive,aboard}` members. Names are display labels.
- `prompts`: `{player_id,kind}` for currently legal interactions. Kinds are
  `transfer_record` and `lift_departure`; these are not localized strings.
- `run`: present only in solo mode: `{id,status,continues}`. `id` is a nonnil UUID;
  `status` is `playing`, `continue`, `failed`, `complete` or `abandoned`. Allowance
  starts at 3 and only decreases. The current M01 attempt equals `4 - continues`.
  State has at most one party member. Waiting requires its dead owner; failed
  retains a dead owner until they leave, then an empty party.
  abandonment has no member, and completion requires `departed`. Nonplaying states
  contain no use prompts. Run identity and rules survive geometry changes.

Participants finish or skip their opening by sending
`{"type":"mission_ready","id":"recall_notice","attempt":1}` using the current
mission ID and attempt. Both fields are required; extra fields are rejected.
The server owns readiness. Spectators, unknown participants, stale attempts and
completed missions cannot acknowledge. Repeated acknowledgments do nothing.
Observation alone is never acknowledgment for an MCP participant.

Initial combat waits in `briefing` until every currently admitted participant is
ready. Disconnect removes that member's wait. A late reader cannot pause active
play: until ready, their body cannot move, use equipment, claim supplies, trigger
encounters, attract enemies, block shots, take damage or prevent a party wipe.
Readiness cannot be withdrawn. Queued input is cleared on first acknowledgment;
duplicate acknowledgments cannot erase an active player's input. Ready members
stay ready across retries; departed IDs are pruned. If no acknowledged members
remain, reset restores the briefing for the next party. A reader finishing during a
retry must acknowledge the new attempt. Supplied scripted controllers acknowledge
automatically and defer combat and optional paid decisions until participation.

Reading the record opens a real gate by selecting a geometry/navigation variant
prepared before server readiness. `MapInfo` is resent even though `map_id` stays
the same; clients must rebuild geometry and clear route caches before accepting
the new mission state. Late players and spectators receive map and shared state.
Departure requires all current participants ready, alive and inside the boarding box,
plus an explicit use press. One participant disconnecting does not reset the
remaining players' progress. In development party mode, a wipe or the last participant leaving resets the gate, supplies
and encounters together, once. NPCs and spectators never count as party members.

The current `departed` state freezes the prototype simulation and shows a result;
it does not load M02. Development party mode retains entry respawn and allows a
new party after everyone leaves. Neither mode has disk saves or mid-mission
checkpoints. A dropped socket can rebind the same pawn for ten seconds. Text is localized; voice/radio is optional.

#### Solo run recovery

Death freezes outcomes and sets `continue` when allowance remains, otherwise
`failed`. A fatal frame cannot also depart. Only the dead owner may send:

```json
{"type":"mission_continue","id":"recall_notice","run_id":"550e8400-e29b-41d4-a716-446655440000","attempt":1}
```

All three fields are required; unknown fields are rejected. Spectators cannot
forward this command. The server validates ownership, run/mission/attempt identity
and waiting state before consuming one continue. A duplicate, stale or invalid
command changes nothing and returns `continue_rejected`. Confirm acceptance in
the next mission state, never from the send result alone.

Retry restores mission-entry position, facing, health, armor, selected weapon,
magazines, reserves and personal claims; later pickups are discarded. Original
geometry, supplies, enemies and objectives return together. Reloads, motion and
queued actions are cleared; input sequence, inventory revision and simulation
tick never rewind. The owner remains ready, so the opening does not replay.
Leaving an unfinished solo run sets `abandoned`; its seat cannot be reused.
A dropped socket can rebind that same owner for ten seconds, and the run stays
in progress while the pawn is parked. When the grace ends, the run is abandoned.
Completion and exhaustion retain their outcomes after departure. Starting again requires a new
server/run. No disk save is implied by this in-memory state.

MCP exposes an explicit `mission_continue` tool. Supplied scripted/playtest/brain
controllers retry automatically within the same allowance. Human UI waits for
held controls to release and a fresh Enter/controller A press. Shared readers
reject changed run identity or increasing allowance across same-map updates.

#### Action

Sent by `human` or `agent` roles to control their player. Movement, firing, jump,
reload and interaction flags are optional booleans defaulting to `false`.
Optional aim, sequence and weapon fields use the types described below.

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
- `weapon_swap`: (optional) `"fists"` | `"tack"` | `"flechette"` | `"rail"` | `"scatter"`.
  The newest explicit choice survives later packets until one tick consumes it.
  Discovery rejects unowned choices; full-arsenal maps permit their three guns.
  Switching cancels an unfinished reload without consuming reserve.
- `reload`: optional boolean, default false and omitted when false. A true request
  is latched across newer input until one tick consumes it. Dead fighters cannot
  reload. Full magazines, insufficient reserve and an existing reload reject it.
  Completion happens before that tick's input, allowing a shot on the completion
  tick. Dry or reloading weapons create no shot result, cooldown or RNG draw.
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

After `welcome`, the initial `map_info` is queued before mission state or any
broadcast snapshot/event for that connection. Connections awaiting Session
registration do not receive broadcasts. A join before the first tick may receive
the same map twice; message count is not a geometry revision number. Gate changes
also send `map_info` before shared progress, even when the map ID stays the same.

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
- `presentation`: optional registered material mapping, omitted on legacy maps.
  Contains `ground` and `solids`, with exactly one entry per collision solid in
  the same order. IDs are `concrete`, `enamel`, `service_steel`, `records_tile` and
  `lift_panel`. Unknown IDs and mismatched cardinality are rejected. Materials
  cannot load arbitrary paths or change collision. A presenter predating this
  optional field may retain its default appearance without changing geometry.
  Optional `decorations` describes at most 128 cosmetic panels, including at most
  eight `strip_light` fixtures. Each strict object has `solid` (zero-based solid
  index), `face`, `center` (two finite metres from the face centre), `size` (two
  finite dimensions from 0.125 to 16 metres) and a registered `kind`. The entire
  rectangle must fit its host face. Faces are `west`, `east`, `down`, `up`,
  `north` (-Z) and `south` (+Z). Face right/up axes are respectively
  (+Z,+Y), (-Z,+Y), (+X,+Z), (+X,-Z), (-X,+Y), (+X,+Y).
  Kinds are `property_sign`, `intake_sign`, `records_sign`, `maintenance_sign`,
  `transfer_sign`, `lift_sign`, `complaint_notice`, `union_seal`, `lockers`,
  `vent`, `terminal`, `lift_control` and `strip_light`. Text keys and assets belong to the client;
  map data cannot provide scripts, arbitrary text, paths or URLs. These thin
  panels cannot create collision or interactions. Old payloads omit the array;
  older presenters can ignore it without changing geometry or gameplay versions.

Geometry bounds: finite half extent from 2 to 256; at most 2048 solids; finite
coordinates within -512 to 512; strictly increasing X and Z bounds. Navigation
also limits each grid column to eight walkable layers, total nodes to 524288,
edges to 4194304 and construction work. These are validation limits, not proven
playable map sizes or capacity claims. Invalid maps cannot replace live geometry.
Clients disconnect on malformed JSON or invalid map geometry rather than
continuing against a previous world. The decision brain and playtest controllers
also stop on messages that fail the shared server-message schema. The MCP adapter
retains its existing forward-compatible handling of unknown event objects.

Current built-in arcade maps still use version 1. The opt-in M01 traversal map
uses version 2 and registered surfaces. It is a blockout, not a finished mission.
Authoring format and startup limits live in [`server/maps/README.md`](../server/maps/README.md).

Agents need this to tell a clear shot from a wall. Before it existed, the reference agents held the fire button through cover and their measured accuracy sat near 15 percent; with it, the same agents measure near 60. An agent that ignores `top` will think a stair tread is cover; one that reads it gets the same answer the server does. The Godot client builds the whole map from this message: the floor, the boundary and every solid at its own height. The MCP adapter stores it and returns it as `map` inside `observe`.

#### Loadout

Discovery maps send `type: "loadout"` only to the owning human or agent when its
equipment changes, including an initial state. It is never broadcast and never
sent to spectators. Full-arsenal maps send no loadout. Selection remains public
in `Snapshot.players[].weapon`; ammunition does not.

```json
{
  "type": "loadout",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "tick": 100,
  "selected": "tack",
  "weapons": [{"weapon":"fists","magazine":null},{"weapon":"tack","magazine":0}],
  "reserves": [{"pool":"tacks","rounds":36},{"pool":"darts","rounds":0},{"pool":"cores","rounds":0}],
  "reload": {"weapon":"tack","complete_at":118},
  "personal_claims": ["bay_tack"],
  "dry_fire_count": 1
}
```

`weapons` lists owned weapons exactly once, including fists. Fists alone have a
null magazine; gun magazines are loaded shots. `reserves` contains all three
unique pools. `reload` is null or the selected gun and its completion tick.
`personal_claims` hides introductory supplies only for their claimant. IDs follow
the authored map contract. `dry_fire_count` advances once per held empty trigger,
resets with a development life, and drives feedback without generating shots.
Clients validate ownership, unique entries, bounded counts, reload consistency
and nondecreasing ticks before replacing their observation. Limits and timings
come from `protocol/loadout.rs`; the Godot boundary mirrors them.

Pickup entries additionally support `kind: "ammo"`, `pool` (`tacks`, `darts`,
`cores`) and a round `amount`. `claim` defaults to `contested` and is omitted in
legacy snapshots. A `personal` weapon supply stays publicly available while each
participant claims it independently once per development life. Contested stock
has one authoritative winner and reports the actual received amount in the pickup
event. On campaign maps, claimed stock stays unavailable with no `respawn_in`
until the authoritative party reset. Outside campaign play, ammo returns after
200 ticks and other arcade pads retain their existing timers. Claims require proximity and, on authored
maps, unobstructed sight. Current development death resets inventory and claims.
A resumed pawn keeps the claims it still holds. A new hello does not restore a pawn that already left.

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

#### Campaign actor identity

On encounter maps, each entry in `Snapshot.players` includes `campaign`:

```json
{"side":"participant"}
```

```json
{"side":"union","kind":"clerk","phase":"windup","phase_started":10,"phase_ends":22}
```

`Role` describes the connection's controller, not faction or fictional anatomy.
Human and external-agent participants are allies. Union `kind` is `clerk` (human
security) or `sweeper` (bot). Names are labels, never a targeting rule. Current
campaign identity describes these introductory encounters; it does not implement
Inheritance takeover, companions or the complete co-op lifecycle.

Phases are `idle`, `moving`, `windup`, `firing`, `recovery`, `hit` and `dead`.
Their start/end are authoritative simulation ticks at 20 Hz. Idle and moving
have no fixed duration (`phase_ends == phase_started`); other phases may be
interrupted by hits, lost sight or death. A firing animation never causes damage.
Resolved `shot_results` still supply the actual weapon, ray and outcome.

Campaign participants cannot damage one another. Allies intercept rays with
`hit: true`, `damage: 0` and `killed: false`; zero damage must not show a hit-confirm
or wound. Union allies follow the same rule. Dead enemies remain in snapshots for
40 ticks with nonpositive HP and phase `dead`, then disappear. They cannot move,
fire, collect supplies or intercept shots, and never use arcade respawn. Exclude
Union actors from participant counts, scoreboards and spectator-player selection.
Campaign kills do not emit arcade frags, streaks or Host taunts.

Shared Rust readers use `PlayerState::is_hostile_to`; legacy entries omit
`campaign` and retain free-for-all behavior. Mixing a legacy and campaign identity
does not imply hostility. Controllers must exclude nonpositive-HP targets. The
client validates identities and phase bounds before publishing a snapshot.

The bounded enemy roster is placed when the first active participant starts the
attempt. Dormant groups remain idle until an entry region activates them;
activation retains each actor's ID and can depend on an earlier group's defeat.
Attacking a dormant guard wakes that group at the struck guard's location,
without revealing an unseen attacker's position. A later entry alarm dispatches
that group once to the entered threshold. In development party mode, last departure
or total party death clears encounters and entry respawn permits retry. Individual
death while an ally survives does not reset groups. Solo mode retains the defeated
state until an accepted continue resets the entire attempt. Saves remain unbuilt;
the mission contract above owns shared lift departure.

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

## Desktop process bootstrap

`fragr-server --local-mission recall_notice` is a child-process contract, separate
from WebSocket messages. It loads the registered map from the committed JSON
embedded at build time, binds `127.0.0.1:0`, and writes one ASCII JSON line to
stdout after map preparation and bind:

The optional `--difficulty assisted|standard|severe` defaults to `standard` and
is echoed below. Bootstrap version 2 requires that field; it is separate from
the on-wire campaign rules revision. No parent command changes it during a run.

```json
{"version":2,"mission":"recall_notice","difficulty":"standard","url":"ws://127.0.0.1:49152","gameplay_version":8}
```

The port is chosen by the OS. Diagnostics use stderr. The parent validates the
exact version, mission, requested difficulty, gameplay capability and loopback endpoint before using
the normal Hello path. Readiness is capped at 4096 bytes and 15 seconds. Stdin EOF
or `{"type":"shutdown"}` followed by a newline stops the child; invalid or overlong
control records also stop it with an error. Control records are capped at 256 bytes.
This lease applies only to explicit local-child mode. Dedicated hosts retain
their independent lifetime. The client gives shutdown three seconds, then
disposes only the PID it created. No process-name or port-based cleanup is used.

## Future Considerations (Post-Slice 1)

Offline recordings reuse these exact message types. Their versioned container,
verification, and CPU report schema are documented in [`BENCHMARK.md`](BENCHMARK.md).
Recording metadata is not sent on the live socket.

- **Binary protocol**: Replace JSON with efficient binary (bincode, flatbuffers)
- **Delta compression**: Send only changed fields
- **Interest management**: Filter snapshots by visibility/distance
- **UDP option**: Low-latency channels for actions (alongside WS for reliability)
- **Prediction**: Client-side movement prediction for smoother human play

## Participant records

A `record` message is private to the participant and sent only to clients that
advertise gameplay capability 8 or later. Spectators receive no private record.
Ordinary updates are bounded to once per 20 ticks; a new round, mission attempt
or status change sends immediately. The record's tick can precede the latest
snapshot. No record is delivered during initial arena warmup or to someone who
joins after a round has already ended without participating.

The version-1 record includes `session_id`, `player_id`, `round`, `tick`,
`entered_at`, `round_started_at`, `ticks_per_second` (20), `map_id`, `map_name`,
`role`, `scope`, `status`, `total` and `attempt`. Its identity is the session UUID,
player UUID and round number, never a callsign. `entered_at` is the admission tick
or the latest round start for an existing participant. A late arena join has
`entered_at > round_started_at`. Mission attempts share one record identity.
The [shared format fixture](../client/golden/player_record.json) is read by Rust,
MCP and client tests.

Scopes are `arena` or `practice` with `round`, or `mission` with `mission`,
`attempt`, `rules` and nullable `run` (the existing solo run contract). Calibration
and non-mission authored test maps are practice. Status is `active`, `continue`,
`complete`, `failed` or `abandoned`. A completed arena record means the round
finished, not that this participant won. A completed M01 record means the mission
finished, not that the unbuilt campaign finished. A missing final update must be
shown as incomplete; transport loss is not evidence of failure or victory.

Each count set contains `alive_ticks`, `deaths`, `hp_lost`, `armor_lost`,
`dry_triggers` and five `weapons` entries in fists, Tack, flechette, scatter, rail
order. Weapon counts are `attacks`, `damaging_attacks`, `kills`, `hp_damage` and
`armor_damage`. The current weapons each resolve one ray per accepted attack.
Fists count as attacks. A damaging attack removes positive HP or armor from a
hostile living target. Protected/friendly bodies, scenery, range misses and a
body killed by an earlier committed ray do not count as damaging attacks.
Effective damage excludes overkill. Simultaneous trades keep both attacks, and
one shot receives each death credit. Dry triggers are latched empty-magazine
pulls, separate from accepted attacks; cooldown and reload denials are neither.

Living active ticks exclude intro/readiness, dead respawn waiting, continue
choice and terminal waiting. The lethal frame counts. This is not wall-clock
session duration. A continue resets `attempt` but retains `total`; new arena
rounds reset both. Administrative removal is not a combat death. Counts are
nonnegative exact JSON integers; totals, identity and participation clocks cannot
regress within a record. Terminal results cannot be rewritten by later updates.

The desktop service record stores the latest 256 observations by record identity,
with local-process versus external-server provenance. Its own format version is
separate from wire capabilities. Local files and external hosts are not an
authenticated public ranking or achievement authority. No background telemetry
or paid runtime generation is involved.
