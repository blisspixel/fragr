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

**MCP agent-adapter session tools:** boot Hello-on-start remains valid. First-class tools `join` (Hello/Welcome, optional name, idempotent), `leave` (clean WebSocket disconnect; `isError` if not connected), and `round_state` (round fields from last snapshot + recent `round_start` / `round_end`) are documented in `agent-adapter/README.md`. Leave sends `{"type":"leave"}` and closes the WebSocket, marking that teardown as nonresumable.

**Names and resume:** display names are not identity credentials. Joining
never evicts an existing fighter by name. The server removes control characters,
trims names to 24 Unicode scalars, uses `Player` for an empty result, and appends
` #2`, ` #3`, etc. on collisions, including collisions with rule bots. The final
label appears in snapshots and events; use player UUIDs for ownership. A client
that sends `resume` keeps that same pawn across a dropped socket for 200 ticks
(ten seconds). Input stops while the socket is gone. The body can still be shot.
An explicit Leave followed by socket close removes the pawn at teardown rather
than parking it. A hello without `resume` still removes the pawn
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
  Current clients send `2`; omission means `1`. A shared arcade room requires `2`.
  A campaign map keeps that map's floor. Before `Welcome`, the server sends
  `error` with code `unsupported_geometry` and closes a hello below the floor
  or above `2`. The message names the version this process speaks when the
  client is newer, and the floor when the client is older. No player or
  spectator session is created on rejection.
- `body`: optional. `human` or `synthetic`: the participant's chosen body, a
  human or a free agent in a synthetic body. Both share one
  personal story, and the body does not establish moral status. Omission or
  `null` means `human` for every role. It is identity only: it never selects
  the control role, side, faction, spawn, equipment, hit volume, speed or
  health. Any other value, including a resource path, fails Hello parsing and
  the connection closes before `Welcome`. A spectator's body is ignored. A
  resume keeps the parked pawn's body even if this hello names another.
  Changing the body means leaving and joining again.
- `gameplay_version`: maximum understood gameplay contract. Updated Rust readers
  and the Godot client send `37`; omission means `1`. Discovery-only maps first
  required 2, authored encounters 3, and mission sequences 6 for shared difficulty.
  Current discovery and campaign admission requires 26 as described below.
  Versions 4 and 5 introduced physical controls and party readiness respectively;
  they cannot enter current missions. Solo runs require 7 for explicit continues.
  Version 8 adds private participant records. Record delivery is gated by the
  client's advertised capability; earlier clients keep their existing messages.
  Version 9 introduced M02 objective and gate state, including spectators. Version 10
  replaces magazines, reserves and reload with one ammunition count per type and
  adds scatter pellet traces. Every discovery map, M01 and M02 included, now
  requires 10 for every role, because the private loadout shape changed and
  older readers would refuse it. Records are delivered only to 10 or later.
  Version 11 adds the pool-less `shiv` weapon to loadouts, actions and shot
  traces, the optional `secret` flag on pickup events, and a sixth record weapon
  slot plus an optional `secrets` count. Every discovery map, M01 and M02
  included, now requires 11 for every role, because any authored map may place
  the Shiv and a version 10 reader would refuse a loadout naming it. Records still
  go to 10 or later: arena and full-arsenal records never carry the new fields.
  Version 12 adds match rule sets ([Match rules](#match-rules)): sides, lives,
  the golden Railgun, side scores and keyed `host_reaction` events, and raises
  the Cells cap from 50 to 100. Every discovery map requires 12, because a
  version 11 reader would refuse a loadout above 50 cells, and so does any
  arena running rules other than plain free-for-all, because a team match shown
  without teams misleads. A shared arcade room speaks gameplay 37. That floor
  is above capability 4, and the arcade roster stays open. The four-seat
  mission party stays on campaign doors. Sabotage keeps its own seat pool.
  Version 13 adds the chosen participant `body` on Hello, Welcome and snapshot
  players. It is additive: no map requires it, older readers ignore the field,
  and an older client's pawn is human.
  Version 14 adds typed flag state, capture scores and flag events. Capture
  the flag arrived at 14. A shared room now requires the current contract
  under Protocol version, so a reader cannot sit in that room on 14 alone.
  Version 15
  adds optional `seated: true` to the Union Clerk campaign identity.
  Version 16 adds the low Union Crawler, its timed leap and the positional
  `crawler_scrabble` event. Version 17 adds the M02 `ward_secured` fact, which
  distinguishes guard victory and machine halt from the later restraint use
  that frees Latch. Version 18 adds the solo run's per-level continue baseline
  and permits a durable M02 run. Durable local M01 requires 18. Version 19 adds
  the M02 companion identity, movement and bounded support fire. Durable M02
  and its development party require 19. Version 20 adds the M02
  `side_ward_secured` fact, derived from the optional side ward encounter.
  Version 21 adds the M02 `evacuation` state and the matching
  `map_info.m02_side_ward` marker for maps with an authored side ward. Version 22
  adds M02's ballistic inspection glass, which older strict surface readers
  cannot render. M02 development and durable sessions now require 22; arcade
  maps keep their earlier requirements. Version 23 adds the stationary Union
  Jammer and its live delayed interference pulses. Any authored map containing
  a Jammer requires 23 for every role. M01 and M02 retain their existing minimum
  requirements. Version 24 adds Scheduled Service's strict M03 geometry,
  guarded shoot objective, car liberation and train departure. Version 25 adds
  Notice to Vacate, the raised Union Notary and campaign rules revision 3.
  Version 26 adds No Forwarding Address, the authoritative translating tram,
  counted grenades and resolved explosions. All authored mission and discovery
  equipment roles now require 26, including M01 through M05.
  Version 27 adds Port of Entry's strict M06 geometry, ordered objectives,
  optional prisoner-route marker and immutable prior rescue context. Only M06
  requires 27; existing authored and discovery maps retain 26. Pressure glass
  remains a real ballistic solid and is now permitted on M02 and M06 only.
  Version 28 adds the Sabotage round objective ([Sabotage](#sabotage)).
  Version 29 adds the counted Proximity Mine (`place_mine`, loadout
  `proximity_mines`, pickup kind `proximity_mine`, snapshot `mines`, record
  `mines`) and the campaign Auditor (actor kind `auditor`, phase `channeling`,
  snapshot `auditors`). Only maps that place an Auditor or grant mines require
  29; every other map keeps its earlier requirement.
  Version 30 adds the found `sniper` weapon to loadouts, actions, pickups and
  shot traces, a seventh record weapon slot, and the stationary
  `ranged_sweeper` Union kind. A map that grants the Sniper Rifle or places a
  Ranged Sweeper requires 30 for every role, because an older reader would
  refuse a loadout or actor naming them. Other maps keep their requirements.
  Version 31 adds Custodian of Record's strict `m08` geometry and mission facts
  and the `custodian_of_record` mission id. Only M08 requires 31.
  Version 32 adds Declared Goods' strict M07 geometry and ordered objectives
  with immutable carried outcomes from M03 through M06. Only M07 requires 32.
  Version 33 adds frozen completion elapsed time on private mission records.
  This adds no map admission requirement. The existing private unicast seam
  omits the optional field for earlier recipients so their strict readers keep
  the original version-1 shape.
  Version 34 adds the human powered-armor `enforcer` Union kind and its
  committed `charging` phase. Every map placing an Enforcer requires 34 for
  humans, agents and spectators. Other maps retain their earlier requirements.
  Passenger Manifest uses the same capability for its strict `m09` geometry,
  ordered crew release and all-party berth departure.
  Version 35 adds the genuine `repeater` weapon, finite Bullets and server-owned
  held-fire warmup, plus participant record revision 2 with eight weapon
  columns. Every map granting a Repeater requires 35 for all roles before
  Welcome. Existing arcade kits and campaign stages through M09 never grant it.
  Older admitted readers on compatible maps receive revision 1 only when actual
  Repeater counts are zero; unsupported ownership or nonzero counts refuse
  delivery rather than losing facts. Warmup state remains private; no new action,
  cycle fact or borrowed weapon presentation is introduced.
  Version 36 adds Common Carrier's strict m10 map and ordered mission facts,
  current pilot/passengers and explicit transit history. Every role requires 36
  before Welcome on that map. It adds no Repeater art, automatic grant or new
  combat channel.
  Version 37 gives a joined human a magazine in each gun. The ammunition count
  stays the total carried, including those rounds. `loadout.loaded` lists
  `{weapon, rounds}` and an optional `ready_at` tick while that gun is
  reloading. The corner reserve is the pool minus every magazine of that pool.
  `Action.reload` is a rising edge and is omitted unless pressed. A loadout
  that still carries the old keys `reserves` or `reload` is refused whole.
  Agents, rule bots, campaign enemies and an unarmed pawn keep the single
  count and send no `loaded`. An armed arcade human lists the magazine guns
  and the finite spawn kit: 80 bullets, 24 shells and 16 cells, including the
  rounds already in the guns. Death restores that kit. A weapon pad adds the
  same pickup amount as discovery, up to the pool cap. A weapon-only mutator
  still sends three zero counts and reloads from an unlimited reserve.
  Only a shared arcade room requires 37. Campaign floors stay where they were.
  A client omits `reload` until a loadout from this server includes `loaded`.
  A process that never sends `loaded` rejects an action that contains the key.
  The revision 2 live campaign contract is retired; compatible historical
  saves and retained service records remain readable. Use matching campaign builds.
  Older clients of every role are rejected before `Welcome`
  with `unsupported_gameplay`. This capability is separate from geometry. A
  shared arcade room requires the same 37, as stated under Protocol version.
  The arcade roster stays open. The four-seat mission party stays on campaign
  doors.

Admission rejection also places its stable error code in a WebSocket policy-close
reason. Clients may receive the final text and close in one poll; use that reason
if the text has already been retired. The server bounds the close handshake at
two seconds and never admits rejected connections.

Development mission servers admit at most four participants, sharing slots across human and
agent roles. Spectators do not take slots. A full party rejects additional
participants with `party_full` before `Welcome`; disconnect returns the seat.
An opt-in `--sabotage-five-v-five` host shares ten fighter seats between human,
agent and rule-bot roles, with five per side. Overflow receives the existing
`error` shape with `match_full` before `Welcome`; spectators do not consume a
fighter seat. A resumable drop holds that seat for the existing 200-tick grace.
Explicit leave or grace expiry frees it. The client maps `match_full` to a
localized hard stop and Return, with no automatic fighter retry; Watch may
connect as a spectator. No new capability or discovery field is added.

Optional `--bot-policy auto --bots 0 --fill-target N` hosts use plain TDM or
Sabotage without mutators. Their desired total counts fighters and reserved
resume seats, but not spectators. Only trusted server-owned rule bots may yield
to validated humans or external agents. The existing `error` shape uses
`bot_fill_next_round` when a full active Sabotage room has no safely replaceable
bot. Ordinary late admission retains zero lives until the next Muster. Failed
or expired prepared admission uses `bot_fill_cancelled`; preparation may already
have delivered Welcome, so the client discards its offered pawn/token and
hard-stops automatic fighter resume. Watch remains available. These codes add
no snapshot fields or gameplay capability. A successful admission followed by
an ordinary drop retains the existing resume semantics.

Local campaign and `--campaign-run` hosts reserve one lifetime combat seat instead.
After its first successful admission, additional fighters receive `run_seat_closed`,
including after the owner disconnects. Spectators remain admissible. Callsigns
cannot reclaim the owner. A failed handshake before admission does not consume it.

Each connection is also bounded before that seat exists. Incoming text is capped
at 64 KiB per frame and per message. The WebSocket handshake and the first
hello each have five seconds. The process holds at most 64 connections, and
32 from one address. Past either cap the server sends `connection_limit` or
`address_limit` and closes. A stalled handshake or a client that never says
hello releases its slot. Further inbound text, including actions, is limited
to a burst of 64 and 256 per second. Extra messages are dropped and the player
stays connected. A client that asked for resume keeps its pawn for ten seconds
after a drop. Send `{"type":"leave"}` and close the socket to remove that pawn
without resume grace. Sending Leave alone marks the eventual teardown; it does
not release a seat while the socket remains open. The grace
does not rewind the simulation. When it ends, the leave is the same as a
disconnect: a solo run whose owner is gone becomes abandoned.

**Liveness and conduct.** After `Welcome` the server sends a WebSocket ping
every 15 seconds. Any frame from the client, including the pong every
WebSocket library sends automatically while it reads, keeps the session.
A quiet spectator that reads is never idle. No frame at all for 45 seconds
closes the session with `idle_timeout`; a fighter that asked for resume keeps
its pawn for the usual ten seconds. The server also closes a session with a
stable code when it:

- keeps flooding: dropped messages fill a strike level that drains at 4096 per
  second and closes past 8192 (`rate_limited`). Only a sustained rate above about
  4352 messages per second reaches it. The inbound budget above is unchanged.
- keeps sending unreadable frames: binary frames, or text that is not a JSON
  object with a string `type`. One per second is forgiven; past 16 the session
  closes (`malformed`). A well-formed message of an unknown `type` is ignored
  and never counts, so a newer client is not closed for it.

`rate_limited` and `malformed` remove the pawn and its resume token.

**Address lists.** A host may start the server with `--ban-list` and
`--allow-list` files of IP addresses and CIDR ranges. A listed or unlisted
address receives `address_banned` or `address_not_allowed` before any slot
check, seat, or `GET /status` answer, whatever its role. When an edit bans the
address of a live session, that session closes with `address_banned` and its
pawn is removed. Lists never match callsigns.

Every close in this section, like an admission rejection, is an `error`
message and then a policy close whose reason is the same code:

| Code | When | Pawn |
|---|---|---|
| `idle_timeout` | no frame for 45 seconds | parked if resume was asked |
| `rate_limited` | sustained flood past the budget | removed |
| `malformed` | repeated unreadable frames | removed |
| `address_banned` | address on the ban list, at accept or after an edit, or a venue-desk ban | removed |
| `address_not_allowed` | allow list set and address not on it | removed |
| `venue_kick` | the venue desk asked that seat to leave | removed |

**Protocol version.** There is no single `protocol_version` in `Hello`.
`gameplay_version` and `geometry_version` are the two contracts. A shared
arcade room, including free-for-all, team play, capture the flag, Sabotage,
and the night list, requires gameplay `37` and geometry `2`. An older hello
and a newer hello are both refused before `Welcome`, with
`unsupported_gameplay` or `unsupported_geometry`. The message names version
37 or geometry 2. An older hello is also sent to
`https://github.com/blisspixel/fragr/releases/latest` and told to check the
archive against `SHA256SUMS.txt` on that page. Join does not fetch the page.
The join page can offer to download that archive after the player asks.
That offer is not a status field, and a host that omits its version is not
fetched. A newer hello is told which version this process speaks. A campaign or local
mission keeps its content floor, so a reader between that floor and 37 can
still enter that mission, and a hello above 37 or geometry above 2 is refused
there too. The envelope itself
(JSON text frames tagged by `type`) has not changed. A breaking envelope
change would add that field then, with its own rejection. `GET /status` may
include both versions. A missing field does not make the host unreadable,
and the client does not refuse to join only because the field is absent.

`GET /status` on the game port, before any WebSocket upgrade, returns a JSON
`LiveStatus` (`schema_version` 2): `kind` (`arena` or `campaign`), map name,
round, tick, fighters, humans, agents, bots, and connections. A missing `kind`
is not an arena. Additive to schema 2, `mode` names the rule set's mode (`ffa`
or `tdm`; a missing `mode` means `ffa`) and `mutators` lists its mutator ids,
omitted when none, so a server list can show what a server plays. Additive
`gameplay_version` and `geometry_version` name the contracts this process
speaks, and are omitted by an older host. It does not list callsigns or addresses, and it does not take
a connection slot. It is a host probe. Watching and playing happen in the Godot
app, which reads only those fields and accepts exactly schema 2.

The snapshot is copied out of its lock before it is serialized. If that copy
does not finish within 50 ms, the probe answers HTTP 503 with
`{"schema_version":2,"busy":true}` and does not invent a map. It does not
answer schema 1 or `{}`. The process requests this line on its own loopback
address before it reports ready. Startup fails when the reply is missing,
the wrong schema, unnamed, or larger than 4096 bytes, which is what the
client reads. A wildcard bind also probes this computer's other non-virtual
IPv4 addresses and logs each result. That log may name those addresses.
`/status` itself still does not. A check from this computer does not prove
another computer can connect. A new socket waits up to one second for its
first bytes. A `GET /status` inside that wait is still this probe. A line
that is clearly not status is a game handshake at once.

A process that is not bound to loopback also broadcasts UDP `6768` every two
seconds. The packet is exactly `FRAGR/1 <tcp-port>\n`. It names the game port
and nothing else: no map, callsign, ticket, or token. It is not a join and not
the game transport. A loopback bind does not send it. The client listens only
while the join page is open, then confirms the host with `GET /status`.

Schema 2 changes only when one of those fields changes meaning or is removed.
Two additive blocks follow them once the tick loop has refreshed once (about a
second after start); a reader that does not know them ignores them:

- `health`: `{status, reasons}`. `status` is `ok` or `degraded`. `reasons` lists
  every rule that currently holds: `tick_p99_over_budget` (window p99 at or
  above the 50 ms budget with at least 100 window ticks), `tick_rate_low` (the
  loop ran under 19 ticks per second over a window of at least 30 s, so ticks
  were skipped), `outbound_drops` (a
  slow reader's outbound queue overflowed inside the window), `stale` (the
  served snapshot is more than 2 s older than the process clock, so the tick
  loop stopped refreshing it).
- `ops`, versioned by `ops.version` (1), bumped when an `ops` field changes
  meaning or is removed:
  - `build`: `crate_version` (the server crate, not the release tag), `release`
    and `commit` baked in at build time from `FRAGR_BUILD_VERSION` and
    `FRAGR_BUILD_COMMIT` (release builds set both; otherwise `null` and
    `unknown`).
  - `process`: `started_unix_s` (wall clock at start) and `uptime_s`
    (monotonic, when the snapshot was taken).
  - `tick`: `budget_ms` (50), `rate_hz` (ticks the loop actually ran per second
    over the window, `null` until it spans 30 s), `scope` (`tick_handler`: expiry, simulation, run
    save, broadcast and unicast enqueue, and this refresh), `window_s` (60),
    and `window` and `lifetime` summaries of `count`, `p50_ms`, `p95_ms`,
    `p99_ms`, `max_ms` and the exact `over_budget` count. The window is six ten
    second slots, so it covers the last 50 to 60 s. Percentiles are
    upper-bucket values from the bench histogram and overstate by under 6.25
    percent; `max_ms` is exact.
  - `connections`: `total`, `spectators`, `humans`, `agents` among admitted
    sessions (rule bots have no connection).
  - `traffic`: text payload only, excluding WebSocket framing and TCP.
    `out_bytes_per_s`, `in_bytes_per_s`, `out_msgs_per_s` and `in_msgs_per_s`
    over the window, `per_client_out_bytes_per_s_mean` and `_max` over live
    sessions, cumulative `out_bytes`, `in_bytes`, `out_msgs` and `in_msgs`
    since start (closed sessions included), and `queue_overflows_window` and
    `queue_overflows_total`. Outbound counts every text frame a session writer
    delivered, welcome included. Inbound counts every data frame read after
    admission, hello included, before the inbound budget drops any.
  - `night`: `rounds_finished`, `peak_humans`, and `peak_fighters` for this
    process. A round is counted when it ends. Peaks are the busiest
    participant room seen: humans, and fighters (humans, joined agents, and
    rule bots). Spectators are not fighters. Counts only, with no callsigns.
    `ops.version` stays 1 because the block is additive. An older body that
    omits `night` reads as zeros.
  - `clients`: only for `GET /status?clients=1` from a loopback address.
    An IPv4-mapped IPv6 loopback counts as loopback. Another computer
    receives the plain body. One anonymous entry per
    session, ordered human, agent, spectator, longest connected first:
    `role`, `connected_s`, the four window rates, cumulative `out_bytes` and
    `in_bytes`, and the current outbound `queue_depth`. No ids, names or
    addresses.

The plain body stays under 2048 bytes at the 64 connection cap (a test pins
it), well inside the client's 4096 byte read limit. The operator block is
rebuilt once a second; the match fields are fresh every tick. The `STATUS` log
line keeps its own bench-shaped report (session scope). Health changes are
logged: `warn` when it degrades or its reasons change, `info` when it recovers.

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

- `id`: `recall_notice` for M01, `persons_unknown` for the M02 preparatory
  graybox, `scheduled_service` for M03, or `notice_to_vacate` for M04;
  `attempt`: positive retry revision; `changed_at`: tick of
  the last phase change/reset, no later than the message tick.
- `phase`: M01 uses `briefing`, `find_transfer`, `reach_lift`, or `departed`.
  M02, M03 and M04 use `briefing`, `in_progress`, or `departed`.
- `rules`: required `{difficulty,revision}`. Difficulty is `assisted`, `standard`
  or `severe`; revision is exactly `3`. Unknown fields/revisions are invalid.
  Revision 2 (2026-09-24) removed reload pauses for guards and players and made
  the scatter a seven-pellet blast; revision 1 was the magazine era.
  Revision 3 (2026-09-30) adds Notary windup/recovery rows of 24/36, 16/26
  and 12/20 ticks for Assisted, Standard and Severe. Earlier enemy rows remain
  unchanged. Revision 2 is accepted only in historical records and explicit
  versioned save upgrades, never in a live mission state.
  The host chooses once before admission. Geometry changes, death, retries and
  joining participants preserve these rules. Clients cannot change them through
  actions or readiness; agent observations contain the same rules as human UI.
- `party`: up to four `{id,name,ready,alive,aboard}` members. Names are display labels.
- `prompts`: `{player_id,kind}` for currently legal interactions. Kinds are
  `transfer_record` and `lift_departure` for M01, or `objective_use` for an M02
  or M03/M04 use objective, and `clinic_shutter` for M04's optional shutter.
  These are not localized strings.
- `run`: present only in durable solo mode:
  `{id,status,continues,level_start_continues}`. `id` is a nonnil UUID;
  `status` is `playing`, `continue`, `failed`, `complete` or `abandoned`. Allowance
  starts at 3 for Episode I and only decreases. A new level records the
  remaining allowance as `level_start_continues`, so its first attempt is 1
  even if a previous level used a continue. During that level, `attempt` equals
  `level_start_continues - continues + 1`. Starting M02, M03 or M04 never refills the pool;
  zero remaining continues still permits its first attempt, then exhaustion.
  State has at most one party member. Waiting requires its dead owner; failed
  retains a dead owner until they leave, then an empty party.
  abandonment has no member, and completion requires `departed`. Nonplaying states
  contain no use prompts. Run identity and rules survive geometry changes.
- `m02`: present only for `persons_unknown`, absent from the M01 JSON. It has
  `completed` (ordered stable objective IDs), `total` (1 to 8), `gate_mask`
  (three low bits for prepared gate variants; M02 uses bit 0 for the ward exit
  shutter raised on `companion_released`), `ward_secured` (server-owned
  `ward_guards` completion, which stops correction before release),
  `side_ward_secured` (optional `side_ward_guards` completion), optional
  `evacuation`, and
  `current`.
  Both facts are derived from encounter state on each projection, not stored
  as second mission flags. `side_ward_secured` implies `ward_secured` and is
  monotonic within one attempt; Continue resets it. It says the captives can
  free themselves, not that they have evacuated. `evacuation` is present exactly
  when the preceding `map_info.m02_side_ward` is true; legal M02 maps without
  that room omit it. When present it is
  `{phase,captives,evacuated}`. `phase` is `held`, `freeing`, `ready`,
  `moving`, `waiting`, or `evacuated`. `captives` contains exactly two stable-order
  `[x,y,z]` world-feet positions, bay A then bay B. The Rust server owns their
  movement and sends bounded samples to every role, including late observers.
  The figures have no fighter seats, combat state, score, or spectator target.
  `evacuated` is true exactly when both reach the safe dock and `phase` is
  `evacuated`. `side_ward_secured` alone never means evacuated. Departure can
  precede evacuation and then freezes the current state. Continue starts a new
  attempt with both captives held. The current
  objective is null or omitted only after departure. An arrival objective has
  `{"id":"ward_reached","action":{"kind":"arrival","region":{"min":[x,y,z],"max":[x,y,z]},"feet":[x,y,z]}}`.
  A physical-use objective has
  `{"id":"companion_released","action":{"kind":"use","target":{"decoration":0,"approach":[x,y,z]}}}`.
  Arrival uses the participant's feet inside the region. Use targets name a
  registered `map_info.presentation.decorations` panel and a reachable approach.
  The server validates range, aim, sight, party eligibility and the authored
  `ward_guards` prerequisite before offering or accepting the release use. Each gate change
  sends a new `map_info` before the changed mission state. The bundled M02
  graybox (`server/maps/m02-persons-unknown.json`) authors `ward_reached`
  arrival, `companion_released` use and `party_departed` arrival. The visible
  frame release derives from
  completed `companion_released`; late readers receive both facts in the
  current mission state. Its independent development child has no run; a
  resumed solo run may carry the same identity and Episode I allowance from M01.

M03 carries `m03` exactly for `scheduled_service`, never `m02`. Its strict
object is `{mast_hp,mast_secured,train_secured,cars,current}`. Mast HP is 0 to
40; damage is accepted only from resolved ordinary shots striking the registered
pod after its authored guard encounter completes. `mast_secured` and
`train_secured` derive from their encounters. `cars` is a bounded stable-order
list of `{id,released,captives}` with two authoritative world-feet positions
per car. Held positions match the map definition; released captives walk the
validated held-to-safe segment at server tick rate. A release requires that
car's encounter clear and a living ready participant in its approach region.
It never gates train departure. These facts cannot regress within an attempt.

While the mast is intact, `current` is
`{"id":"mast_disabled","action":{"kind":"shoot","solid":34,"approach":[22,2.5,13],"aim":[22,7.5,17]}}`.
The solid index, approach and aim bind exactly to `map_info.m03.mast`.
Shutdown sends the precomputed fallen MapInfo before mission state, then
`current` becomes `party_departed` with a `use` action naming the exact
departure target. A deliberately pressed, in-range, aimed Use requires the
final guards cleared and all living ready party members aboard. Departure
omits `current`. Retry restores the intact mast, guards and unreleased cars.

M04 carries `m04` exactly for `notice_to_vacate`, mutually exclusive with
`m02` and `m03`. Its strict object is
`{completed,current?,clinic_secured,clinic_open,patients_released,patients,photos_completed,carried_recall_cars}`.
`completed` is a prefix of `notice_board_cleared`, `first_notary_cleared`,
`street_wave_cleared`, `market_wave_a_cleared`, `market_wave_b_cleared` and
`court_cleared`. Only departure appends `party_departed` and omits `current`.
While fighting, `current` binds to the corresponding registered arrival
objective; after the sixth encounter it is the registered roof departure Use.
Future encounter bodies do not appear until the preceding encounter clears.

`clinic_secured` follows the third encounter. A deliberate ordinary Use at the
registered clinic panel then opens its precomputed world. The replacement
MapInfo is queued before the changed Mission and Snapshot. Local arrival in
the release region frees the optional patients; their `{id,feet}` samples
remain on the registered, unambiguous grounded routes and cannot move backward
within an attempt. Patient walking never gates roof departure. Departure
requires all living, ready party members aboard and all six encounters clear.
Retry closes the clinic, restores guards and patients, and clears photograph
and rescue attempt facts. Carried M03 liberation IDs remain immutable.

`photos_completed` counts only the first resolved burst round hitting its
original live, active, ready participant, once per burst. Misses, locked-aim
dodges, intervening cover, dry fire and prior interruption add nothing; later
burst rounds never count. A committed shot traded in the same simulation frame
still has its resolved evidence. The counter is bounded at 1,000,000.
`carried_recall_cars` contains at most four unique registered-form ASCII IDs.

M05 carries `m05` exactly for `no_forwarding_address`, mutually exclusive with
`m02`, `m03` and `m04`. Its strict object is
`{completed,current?,workshop_secured,group_released,captives,freight_open,tram,carried_recall_cars,carried_patients,carried_photos}`.
`completed` is a prefix of `roof_crossed`, `grenade_lesson_cleared`,
`workshop_cleared`, `trench_cleared`, `heavy_cleared`, `freight_secured`, then
`party_departed`. The current objective is the matching arrival, or the final
registered ship Use. Required encounter bodies appear in order. The workshop
releases all three captives only after clearance and actual party presence in
the release region. Stable IDs are `splice`, `workshop_agent_a` and
`workshop_agent_b`; grounded `{id,feet}` samples follow registered routes.
Release is distinct from physical arrival inside boarding. Captive arrival
never gates departure. Car, clinic and photograph carry is immutable per attempt.

`tram` is `{phase,feet,tick}` with `parked`, `boarding`, `moving`, `blocked` or
`arrived`. Feet name the lower-face centre of the registered solid. After release
and party presence in its activation region, the tram allows three seconds for
boarding, then moves along its bounded Z lane. Current collision, projectile and
cover checks use this translated solid. Supported living riders receive its
displacement before ordinary movement; jumping or leaving support stops carry.
Swept obstructions refuse the entire step. Walking access remains available.
Retry restores the parked tram, closed freight gate, guards and held captives.
Freight clearance sends the prepared open MapInfo before changed state. Clients
wait for matching fresh facts before steering. Departure requires all required
encounters, living ready party members at boarding, and a fresh aimed Use.

M06 carries `m06` exactly for `port_of_entry`, mutually exclusive with earlier
mission envelopes. Its strict facts are
`{completed,current?,prisoner_route_marked,carried_recall_cars,carried_patients,carried_photos,carried_released_workers,carried_evacuated_workers}`.
The required prefix is `freight_cleared`, `rail_lane_cleared`, `loading_cleared`,
`turret_cleared`, `customs_cleared`, `exit_cleared`, then `party_departed`.
Each of the first six objectives requires its corresponding encounter clear
and active ready party arrival at the registered region. Future required
guards remain absent until their predecessor clears. The optional service
encounter becomes available after loading clearance and never gates the next
required encounter. Its marker requires that optional clear and real party
arrival. Latch follows and has bounded support ammunition, but does not fire
into the isolated Rail or Turret lesson groups.

Car and patient carry retains historical unique registered-form IDs and order,
at most four each; photographs remain bounded at 1,000,000. Released workers
are empty or all three registered workshop IDs, and evacuated workers are a
unique subset. These are immutable previous outcomes, not new port actors or
assumed ship passengers. Departure requires all living ready participants
aboard and a fresh aimed Use. Retry resets the port, guards, grants, ally and
optional marker while retaining earlier outcomes and the M06 entry.

M08 carries `m08` exactly for `custodian_of_record`, mutually exclusive with
every earlier mission envelope. Its strict facts are
`{completed,current?,node_hp,seal_open,machine_fallen,custodian_joined,custody_released,recovered_mind_secured,transfer_evidence,captives_evacuated}`.
The required prefix is `hall_cleared`, `lower_gallery_cleared`,
`mines_cleared`, `auditor_cleared`, `machine_wrecked`, `evidence_taken`,
`exit_cleared`, then `party_departed`. Every step but `machine_wrecked` is an
Arrival that needs its own group cleared and active ready party arrival; future
groups stay absent until their predecessor clears. When the upper gallery
Auditor's group clears, the server swaps to the precomputed lifted-seal world
and resends MapInfo before the changed facts. `machine_wrecked` is a Shoot
objective naming the next intact support node. Each node has 50 health and
takes only resolved ray impacts on its registered face while the machine is
the current step; `node_hp` lists the four in geometry order. The last break
swaps to the precomputed fallen world. `custodian_joined` follows the lower
gallery step and `transfer_evidence` the evidence step. `custody_released` and
`recovered_mind_secured` are optional arrivals at the lower bays and the cold
cabinet, available only after the seal lifts; neither gates departure.
`captives_evacuated` is set at departure only when the bays were released.
Departure requires all living ready participants aboard and a fresh aimed Use.
Retry restores the sealed world, every node, the guards and every fact.

M09 carries `m09` exactly for `passenger_manifest`, mutually exclusive with
other mission envelopes. Its strict facts are
`{completed,current?,crew_released,crew,hatch_open,charge_falls,carried_archive?}`.
The prefix is `loading_cleared`, `lesson_cleared`, `crew_freed`,
`gantry_one_cleared`, `gantry_two_cleared`, `gantry_three_cleared`,
`clamps_released`, `hatch_cleared`, then `party_departed`. Crew release is a
fresh aimed Use after the office guards clear; every fight arrival requires
its actual group clear and participating party arrival. Gantry guards cannot
activate before crew release. Clearing the gallery prepares the raised hatch
world and sends MapInfo before changed facts. `crew` contains strict
`{id,feet,aboard}` records: Tern and two berth crew, then optional Edda and
Splice in that order. Edda's authored appearance uses nonempty recorded M04
clinic-team rescue; it adds no historical individual survival fact. Splice
requires actual M05 evacuation, not release alone. Crew feet follow supported
held routes with ordinary living-body contacts; their timing never gates exit.
`charge_falls` counts only actual lethal Enforcer charge descents, at most seven.
Severe exposes a fall as an optional challenge; zero falls never blocks a
prompt, controller or departure. All departures require every
ready living participant aboard and a fresh aimed Use. Retry restores the closed
world, entry inventory and guards, preserving carried history and cast.
`carried_archive` is the immutable tagged v10 M08 outcome described below;
it is absent in independent development parties and never blocks boarding.

M07 carries `m07` exactly for `declared_goods`, mutually exclusive with
other mission envelopes. Its strict facts are
`{completed,current?,carried_recall_cars,carried_patients,carried_photos,carried_released_workers,carried_evacuated_workers,carried_prisoner_route_marked}`.
The required prefix is `ring_cleared`, `plaza_cleared`, `post_cleared`,
`window_cleared`, `cut_cleared`, then `party_departed`. Each of the first five
objectives requires its corresponding encounter clear and active ready party
arrival at the registered region. Future required guards remain absent until
their predecessor clears. There is no optional branch. Latch follows and has
bounded support ammunition, but does not fire into the isolated roof-window
marksman lesson. The carried fields are the immutable earlier outcomes,
including the M06 route marker. Departure requires all living ready
participants aboard the freight boarding region and a fresh aimed Use. Retry
resets the town, guards, grants and ally while retaining earlier outcomes and
the M07 entry.

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

The current `departed` state freezes that mission's simulation and shows a
result; it does not load the next map in the same process. A durable solo M01
child saves M02 as pending, and the menu can start a new local M02 child from
that exit. Development party mode retains entry respawn and allows a new party
after everyone leaves. It has no disk save. Neither path has a mid-mission
checkpoint. A dropped socket can rebind the same pawn for ten seconds. Text is
localized; voice/radio is optional.

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

Retry restores that level's entry position, facing, health, armor, selected
weapon, carried weapons, ammunition counts and personal claims; later pickups
are discarded. Original geometry, supplies, enemies and objectives return
together. M02's entry carries M01's exit health, armor, weapons, ammunition
and selection but starts with M02's own pickup claims and attempt count.
Motion, a latched dry trigger and queued actions are cleared; input sequence, inventory revision and simulation
tick never rewind. The owner remains ready, so the opening does not replay.
Leaving an unfinished solo run sets `abandoned`; its seat cannot be reused.
A dropped socket can rebind that same owner for ten seconds, and the run stays
in progress while the pawn is parked. When the grace ends, the run is abandoned.
Completion and exhaustion retain their outcomes after departure. Starting again requires a new
server/run. A wire run status alone does not imply a disk save. The owned local
child persists only when launched with `--run-mode new|resume` as described
under Desktop process bootstrap.

MCP exposes an explicit `mission_continue` tool. Supplied scripted/playtest/brain
controllers retry automatically within the same allowance. Human UI waits for
held controls to release and a fresh Enter/controller A press. Shared readers
reject changed run identity or increasing allowance across same-map updates.

#### Action

Sent by `human` or `agent` roles to control their player. Movement, firing, jump
and interaction flags are optional booleans defaulting to `false`. `reload`
is one of those booleans for an armed human, omitted while false. Optional
aim, sequence and weapon fields use the types described below.

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
- `reload`: Optional boolean, omitted while false. A rising edge starts one
  reload of the selected gun. Holding it does not start another until a packet
  omits the key. An unarmed pawn, an agent, melee, a full magazine, a bag with
  nothing left for that gun, and a gun that is already reloading ignore it.
  Starting a reload blocks that gun until `ready_at`. Death and a real weapon
  change cancel it. A client sends the key only after this server has included
  `loaded` on a loadout, and erases it when the control is up.
- `throw_grenade`: Optional held boolean, omitted while false. A rising edge
  latches one counted throw, including a press and release between ticks.
  Holding it does not repeat. The launch uses authoritative aim, consumes one
  of at most six grenades and takes that tick's attack admission while retaining
  gun selection. An empty or refused throw still permits gun fire. The separate
  throw cooldown is 15 ticks; fuse is 40 subsequent active ticks.
- `place_mine`: Optional held boolean, omitted while false. A rising edge
  latches one counted placement, like `throw_grenade`. The mine leaves the eye
  at 8 m/s along authoritative aim plus 2 m/s upward and sticks to the first
  solid, floor or bound it touches. It consumes one of at most four mines and
  that tick's attack admission; a grenade throw on the same tick wins. The
  placement cooldown is 15 ticks. A placement over the live cap (three per
  owner, 32 in the world), from a dead, detached or inactive body, or with no
  mine in hand is refused and spends nothing.
- `jump`: Jump while grounded. The held value remains active until released;
  a press followed by release before the next tick is retained for that tick.
  The retained press is consumed once, including while airborne or dead, so it
  cannot create delayed jumps. Holding jump does not add thrust in the air.
- `duck`: Optional held boolean, omitted while false. This server advertises
  the key with `Welcome.duck`. A client must not send it until that flag is
  present, because an older `Action` rejects unknown fields and would drop the
  whole input. While it is set, a participant fighter is 1.35 m tall, the eye
  is at 1.15 m, and horizontal speed is 0.34 of the speed already chosen.
  Releasing it stands back up unless the ceiling will not allow 1.8 m. The
  snapshot field is the resolved stance, not the raw key. Campaign enemies,
  Notaries, Crawlers, and bosses ignore it. Jump is unchanged.
- `weapon_swap`: (optional) `"fists"` | `"shiv"` | `"tack"` | `"flechette"` | `"rail"` | `"scatter"` | `"sniper"` | `"repeater"`.
  The newest explicit choice survives later packets until one tick consumes it.
  Discovery rejects unowned choices; full-arsenal maps permit their three guns.
  Switching releases a latched dry trigger. A dry weapon creates no shot result,
  cooldown or RNG draw.
- `look_at`: (optional) Agent target aim. A shared-room human socket drops
  the field, so the server does not aim that pawn. Yaw and pitch remain the
  human aim. A campaign socket and an in-process controller may still send
  it. Prefer `player_id` (UUID string),
  or both `x` and `z` with optional world `y`. A player target aims at the chest,
  1.22 units above the feet, when the belt is clearly open. A counter that hides
  the hips, a lip the shot cone would still strike, or a gap that shows
  the hips but not the chest keeps the shot on the hip line. A Crawler or a
  Notary is aimed at the middle of its shorter body. A world point without `y`
  means horizontal aim.
  Valid target intent replaces yaw and pitch after movement. Missing targets,
  coincident points, and nonfinite coordinates leave the current aim unchanged.
- `yaw`: (optional) Client-owned absolute facing in radians. When present the server takes it as the fighter's yaw for this input, before movement, instead of turning at a fixed rate from the turn bits. Normalised into `[0, 2 pi)`; non-finite values are ignored and the turn bits apply as before. This is how a human client keeps the look axis off the network.
- `pitch`: (optional) Absolute vertical aim in radians, positive upward, clamped
  to +/-85 degrees. Missing or nonfinite values retain the last pitch, initially
  zero. Pitch does not redirect movement. Respawn resets it to zero.
- `seq`: (optional) Input sequence number. For a numbered human, the server accepts only numbers newer than the last admitted sample in u32 half-range order, including wrap. The Godot sender uses 1 through 4294967295 and wraps back to 1. Duplicate and stale samples do not replace continuous input or latch a jump, interaction or weapon choice. Once a human sends a numbered Action, an unnumbered Action on that pawn is ignored. Humans that never number Actions, agents, and older clients retain their unnumbered path. The server echoes the selected sequence in an `ack` every tick after the first numbered movement step.

**Notes:**
- Continuous action fields use the latest admitted value at the game-loop tick
  boundary. This boundary is when the server applies the Action command, not
  the client's send time or raw socket arrival. The selected value is held on
  later ticks until a newer Action replaces it. Weapon selection and a jump
  press survive intervening packets until an active tick consumes them.
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

#### Jeep control and facts (capability 39)

Vehicle maps use the existing `Action` and snapshot channel. Optional `seat`
accepts `driver` or `gunner`, selecting a free seat in the currently occupied
stopped jeep. Its request survives an intervening Action that omits it until
the next active tick consumes it. A rising `interact` enters the nearest free
seat within 2 m horizontally and 2 m vertically with clear line of sight,
driver first, or exits the current jeep to clear reachable ground. Entry,
exit and switching require absolute speed at most 2 m/s. A refused exit
retains the seat. Enemy team occupants cannot share the same jeep.

The driver uses `forward`/`back` for throttle, `left`/`right` for steering and
`jump` for braking. Steering follows chassis yaw; aim remains free. The gunner
uses the ordinary aim and fire fields. Occupants cannot walk, fire handheld
weapons, throw grenades or place mines. Switching locks both vehicle controls
and the mount for ten ticks, through `control_ready_tick`.

Optional `Snapshot.vehicles` is omitted when empty and contains at most 32
strict records: `{id,kind,position,yaw,speed,vy,hp,driver,gunner,gun_heat,
burning_ticks,control_ready_tick}`. IDs are positive u32 values and `kind` is
`jeep`. Position is chassis ground-base `[x,y,z]` in metres, yaw is normalized
server +X-forward radians, speed is signed (forward at most 16 m/s, reverse
at most 6 m/s), and `vy` is vertical metres per second. HP is 0 to 400, heat
is 0 to 1, and burning lasts at most forty ticks. Driver and gunner are
nullable live player UUIDs; this list is the sole occupancy authority.
The body is 3.8 by 1.9 m with a 1.35 m high shot box and 2.75 m clearance
for exposed occupants. Driver feet are local `[0.55,0.65,-0.40]`, gunner feet
`[-0.65,0.95,0]`. Vehicle bodies use server collision and damage resolution.

Mounted fire emits an ordinary Flechette `ShotTrace` with optional positive
`vehicle_id`, recorded when the shot resolves. It does not change the carried
weapon or inventory ammunition. Heat and the four-tick fire interval limit
the mount; overheating requires cooling to 0.25 before firing resumes.
Driver prediction pairs the existing ACK's sequence, epoch and tick with
the same snapshot's vehicle motion. The ordinary movement ACK has
`applied:false` while seated. Quiet world snapshots may be superseded, so a
client must wait for a matching tick before reconciling a vehicle.
Seat, HP, burn-phase and control-lock changes remain reliable facts in the
bounded outbound queue; vehicle motion and cooling may coalesce.

The island water increment (capability 41) extends `kind` with `boat` and
`light_aircraft`, retaining the same twelve state fields and 400 HP maximum.
Boats have driver and gunner seats, a 4.8 by 2.2 m hull, 14 m/s forward and
4 m/s reverse limits, and 0.6 m draft. Their complete footprint must remain
in registered water of sufficient depth; dock and shore solids still block
them. The same mounted gun and heat limits apply to the boat's gunner.

The 8 by 9.2 m light aircraft has one driver seat and no weapon in this slice.
Its boarding radius is 6 m to reach the cockpit from outside the wings;
exits sample beyond the complete hull.
Forward adds throttle, back brakes, left/right steer, jump climbs and duck
descends. It gains lift at 12 m/s, reaches 32 m/s, targets at most 6 m/s
vertical travel, and has a 60 m altitude ceiling. Below lift speed it falls
under gravity. Water contact, hard landing or a high-speed obstruction can
destroy it; a burning aircraft falls during its warning. Destruction attempts
safe ejection, with lethal damage in place if no legal exit exists. The
collision body remains upright. Driver crouch is a resolved seat posture,
independent of the aircraft's descend input. Water exits use the same
authoritative swimming support as ordinary infantry.

#### Registered water and island Conquest (capabilities 40 and 41)

`MapInfo.water_regions` is absent for dry maps. It contains at most 32 strict
`{min:[x,z],max:[x,z],level,depth}` records. Coordinates and values are finite;
positive rectangles remain within `half_extent` and do not overlap internally.
Depth is positive and at most 64 m. The registered surface cannot be below its
depth or above twice the map half extent. Holdfast currently uses five regions
at 2.2 m above the common seabed, with land at 3 m. Shared arcade admission is
41. Visual waves do not modify these bounds or combat outcomes.

Surface swimming uses the ordinary collision step with a 3.2 m/s speed ceiling
and feet 0.9 m below the water level. Bounded temporary water support permits
stepping back to dry land. The client mirrors this kernel for prediction.
No separate swimming Action, underwater combat mode or per-client water physics
is introduced.

`GameMode` adds `conquest`, permitted on Holdfast Atoll (map 7). Optional
`Snapshot.conquest` is null outside that mode, or contains
`{tickets:{union,coalition},initial_tickets,capture_ticks,points}`. Each point is
`{id,position:[x,y,z],radius,owner,capturing,progress,contested}`. The five IDs are
`harbour`, `village`, `airfield`, `server_halls` and `lighthouse`. Owner and
capturing are nullable team values. Position names ground level, radius is 8 m,
and progress is a bounded tick count below the advertised 160-tick stage.

An uncontested side spends eight seconds neutralizing an enemy site, then eight
seconds capturing it. Opposing presence freezes progress; empty or defending
presence unwinds it. Bodies do not multiply capture speed. Both sides start
with 200 tickets. A resolved participant death debits one; owning more than two
sites debits the other side once per second by the number above two. Exhaustion
ends the round; simultaneous zero draws. The default ten-minute clock compares
remaining tickets. Warmup and new rounds reset sites, tickets and vehicles.
The retained state and ordinary `RoundEnd.winning_team` convey the result.
Point, ticket and occupancy transitions remain reliable outbound facts even
when quiet movement snapshots are coalesced.

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

#### Wire board

The process-local board. Humans, free agents, and spectators share it. It is
not a combat fact and it does not change gameplay version. An older server
ignores the message. An older client never receives it unless that client
asked, because the answer is a unicast.

```json
{ "type": "board", "op": "list" }
{ "type": "board", "op": "read", "board": "floor" }
{ "type": "board", "op": "post", "board": "notices", "text": "still here" }
```

`op` is `list`, `read`, or `post`. `board` is `floor` or `notices` when the
op needs one. `text` is the notice. Unknown fields are refused. The same 80
scalar and control-character rules as speak apply to a notice. A notice waits
60 ticks, counted on its own, so a callout does not spend it.

`floor` is the room. Successful speaks and a venue sentence are copied onto
it. A post to `floor` comes back `board_closed`: a seated human or agent
speaks, and that is the floor. `notices` keep what was posted until this
process ends. Each board holds 40 lines and drops the oldest. Nothing is
written to disk. A round change does not clear the board.

The answer is one unicast, not a broadcast:

```json
{
  "type": "board",
  "op": "read",
  "board": "notices",
  "lines": [{ "tick": 4, "name": "Wire", "text": "still here" }]
}
```

`list` returns `boards` with `id` and `count`. A refusal sets `code` to
`board_unknown`, `board_closed`, `board_rejected`, or `board_rate_limited`
and omits empty lists. The name on a line is the callsign the server
assigned. The client does not choose a second name for the post.

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
  the same order. IDs are `concrete`, `enamel`, `service_steel`, `records_tile`,
  `lift_panel` and `inspection_glass`. The last is a transparent visual over a
  normal ballistic and movement solid, used by M02 under gameplay capability 22.
  Older strict surface readers are refused before MapInfo. Unknown IDs and
  mismatched cardinality are rejected. Materials
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
  `vent`, `terminal`, `lift_control`, `strip_light`, `gate_locked`,
  `gate_open`, and the M03 kinds `m03_schedule_board`, `m03_schedule_cancelled`,
  `m03_platform_car`, `m03_siding_car`, `m03_roof_car`, `m03_mast_sign` and
  `m03_board_train`, plus `m04_clinic_care`, `m04_clinic_sign`,
  `m04_field_printer`, `m04_market_canvas`, `m04_meal_six`, `m04_noodle_six`,
  `m04_notice_board`, `m04_paint_locker`, `m04_repair_bench`, `m04_tram_vote`,
  `m04_water_tank`, `m04_workshop`, `m04_clinic_control` and
  `m04_roof_departure`. Text keys and assets belong to the client;
  map data cannot provide scripts, arbitrary text, paths or URLs. These thin
  panels cannot create collision or interactions. Old payloads omit the array;
  older presenters can ignore it without changing geometry or gameplay versions.
  `gate_locked` and `gate_open` are M02 gate signal lamps (red over a closed
  shutter pictogram, green over a raised shutter and up arrow). Only an M02 gate
  places them, so they appear only on maps that require gameplay capability 9.
  Each prepared gate world carries its own presentation: the `map_info` resent
  after a gate rises shows that gate's lamps as `gate_open`, on the gate and on
  whatever opened it. They carry the gate's real state, not decoration.
- `rules`: the arena's rule set, omitted on authored campaign maps. See
  [Match rules](#match-rules).
- `m02_objectives`: optional objective count (1 to 8), present only on an M02
  map. It identifies the M02 contract independently of `map_id` and must match
  the subsequent `mission.state.m02.total`. Legacy maps omit it, including
  encounter-only maps whose numeric ID happens to be 1002.
- `m02_side_ward`: true only when an M02 map authors `side_ward_guards`.
  Omitted means false. This is the presence contract for the two-person
  `mission.state.m02.evacuation` state. A client rejects a mission state whose
  evacuation presence disagrees with the current map marker.
- `m03`: present only on Scheduled Service, map ID 1003 and geometry version 2.
  The strict object contains `mast:{solid,approach,aim}`, `mast_shutdown`,
  `departure:{decoration,approach}`, `boarding:{min,max}`, `companion_start`
  and one to four `cars:{id,release:{min,max},held,safe}`. Held and safe each
  contain two stable-order world-feet positions on the same-height validated
  evacuation segments. The mast solid index binds the real shoot target;
  original approach and aim remain unchanged after shutdown. The server
  prepares exactly two mast worlds before readiness. Optional car release
  changes no collision world. `mast_shutdown` must match subsequent zero
  mast HP. The fallen world's schedule sign becomes `m03_schedule_cancelled`.
  Same-map replacements cannot rebind any static M03 contract field. Every
  role now requires capability 26 under campaign rules revision 3.
- `m04`: present only on Notice to Vacate, map ID 1004 and geometry version 2.
  Its strict object contains `clinic_open`, `clinic:{control,release}`,
  `patients:[{id,held,route}]`, six ordered arrival `objectives`, `departure`,
  `boarding` and `companion_start`. Controls are registered `UseTarget`
  objects; regions have finite `min`/`max` feet bounds. There are one to four
  patients, each with a stable ID and two to sixteen grounded route points
  starting at `held`. Routes reject loops, reversal and ambiguous overlapping
  tolerance corridors. The server prepares exactly two clinic worlds before
  readiness. Same-map replacements cannot rebind the static contract. Clients
  discard current mission steering until fresh state matching the replacement
  world arrives. Every role requires capability 26.
- `m05`: present only on No Forwarding Address, map ID 1005 and geometry version
  2. Its strict object contains `freight_open`, `rescue:{release,captives}`,
  six ordered arrival `objectives`, `departure`, `boarding`, `companion_start`
  and `tram:{solid,start,end,speed,activation}`. Three stable-order captives have
  registered `id`, `held` and two to sixteen grounded route points, ending at
  boarding. `tram.solid` binds the real baseline solid; start/end are its
  lower-face centre with identical X/Y, Z travel from 2 to 24 metres and speed
  from 0.1 to 1.5 metres per second. The server prepares closed/open freight
  worlds and conservative navigation excluding the swept tram lane before
  readiness. Moving the tram does not rebuild topology or replace MapInfo each
  tick. Same-map replacement cannot rebind its static contract. Current tram
  state supplies collision for presentation and prediction. Every role requires
  capability 26, with unchanged campaign rules revision 3.
- `m06`: present only on Port of Entry, map ID 1006 and geometry version 2.
  The strict object contains six ordered Arrival `objectives`, optional-route
  `service` (the registered `prisoner_route_marked` Arrival objective),
  `departure`, `boarding` and `companion_start`. It has one static world,
  supported routes and real pressure-glass solids. Same-map replacement cannot
  rebind this contract; controllers wait for matching fresh facts. Every M06
  role requires capability 27, with campaign rules revision 3 unchanged.
- `m08`: present only on Custodian of Record, map ID 1008 and geometry version
  2. The strict object contains six ordered Arrival `objectives` (every chain
  step but `machine_wrecked`), four `nodes` (`solid`, supported `approach`,
  `aim`), the `machine` and `seal` solid indices, the optional `bays`
  (`custody_released`) and `cabinet` (`recovered_mind_secured`) arrivals,
  `departure`, `boarding`, `companion_start`, and the world's `seal_open` and
  `machine_fallen` stage flags. Only those flags may change on a same-map
  replacement: forward with the world, and back on a retry. Every M08 role
  requires capability 31, with
  campaign rules revision 3 unchanged.
- `m07`: present only on Declared Goods, map ID 1007 and geometry version 2.
  The strict object contains five ordered Arrival `objectives`, `departure`
  (a registered `m07_depot_freight` panel and its approach), `boarding` and
  `companion_start`. One static world; pressure glass is permitted. Same-map
  replacement cannot rebind this contract. Every M07 role requires capability
  32, with campaign rules revision 3 unchanged.
- `m09`: present only on Passenger Manifest, map ID 1009 and geometry version
  2. Seven ordered Arrival `objectives` accompany the physical `crew_release`
  and `departure` controls, `boarding`, `companion_start`, five authored `crew`
  routes with per-point `held_until` gates, the `hatch` solid index and
  `hatch_open`. Only the hatch's registered vertical bounds and stage flag may
  change on a same-map replacement; all other collision and contract fields
  remain exact. The raised world is prepared before readiness and sent before
  changed mission facts. Actual crew presence depends on retained outcomes,
  not the five reserved authoring routes. Every role requires capability 34.
  The crew control binds registered `m09_crew_manifest` decoration; departure
  binds `m09_board_carrier`. Generic custody controls cannot replace these
  physical manifest and carrier labels. Older strict readers of every role
  are refused before these new kinds are sent.
  Campaign rules revision 3 remains unchanged.

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
sent to spectators. An unarmed full-arsenal pawn sends no loadout. An armed
arcade human receives the magazine guns, the finite spawn kit and `loaded`.
A weapon-only mutator sends three zero counts instead, because that one gun
has no bag. Selection remains public in `Snapshot.players[].weapon`; ammunition does not.

```json
{
  "type": "loadout",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "tick": 100,
  "selected": "tack",
  "weapons": ["fists", "tack"],
  "ammo": [{"pool":"bullets","rounds":0},{"pool":"shells","rounds":0},{"pool":"cells","rounds":0}],
  "grenades": 0,
  "personal_claims": ["bay_tack"],
  "dry_fire_count": 1
}
```

`weapons` lists owned weapons exactly once, including fists, in the order
fists, tack, flechette, scatter, rail, shiv, sniper, repeater. Earlier indices
never change. The `shiv` is found, not issued: a
pool-less melee weapon (35 damage, 6 tick cooldown, 2.2 unit reach) that spends
nothing and has no ammunition count. Picking it up again adds nothing. The
`sniper` (capability 30) is also found, never issued: hitscan with 70 damage,
a 32 tick cooldown, a 0.004 radian cone and 90 unit reach, spending one Cell per
shot. It shares the Cells pool with the Railgun but never its damage or its
beam; its scope is client presentation and changes no action field.
The `repeater` requires capability 35. Its CPU prototype holds existing `fire`
for six warmup ticks before ordinary traced shots with a two-tick cooldown,
14 direct damage, 35 unit reach and a 0.035-radian cone. Each actual shot spends
one Bullet; warmup spends nothing. Release, accepted weapon change, inactivity,
death, leave and attempt reset clear the private cycle. These constants await
played feel and real art/audio acceptance. No current campaign find or default
arcade kit grants the weapon. Six physical keys remain unchanged: key 3 selects
Shotgun, and repeated key 4 cycles the owned Rifle/Repeater family. The existing
wheel includes Repeater beside Rifle without changing wire or record indices.
`ammo` contains
all three unique pools: `bullets` (Tack, Flechette and Repeater, cap 200), `shells`
(Scatter, cap 50) and `cells` (Rail and Sniper, cap 100 since capability 12). One shot, including a seven-pellet scatter blast, spends one unit from
its pool, and fists need nothing. On an armed human that unit also leaves the
selected magazine. `loaded` is omitted when the pawn has no magazines. Each
entry is `{weapon, rounds}` with optional `ready_at`. Rounds cannot exceed the
magazine, entries are unique and owned, at most one gun is reloading, and the
sum of magazines in a pool cannot exceed that pool. An arcade magazine loadout
has one entry per listed gun. A finite bag sends the real counts. Three zeros
mean a weapon-only gun with no bag. Discovery still
requires fists. A weapon pickup adds Tack 50, Flechette 60,
Scatter 12, Rail 10, Sniper 8 or Repeater 60 units to the pool. A gun acquired
for the first time then fills its magazine from that pool without adding more.
A later pickup adds to the pool only. The loadout keys `reserves` and `reload`
stay refused whole. Magazine sizes and reload ticks live on `WeaponType`:
Tack 12 and 16, Flechette 20 and 22, Repeater 30 and 22, Scatter 6 and 14,
Rail 4 and 28, Sniper 5 and 28. Fists and the Shiv have none.
`personal_claims` hides introductory supplies only for their claimant. IDs follow
the authored map contract. `dry_fire_count` advances once per held empty trigger,
resets with a development life, and drives feedback without generating shots.
Clients validate ownership, unique entries, bounded counts and nondecreasing
ticks before replacing their observation. Limits and timings
come from `protocol/loadout.rs`; the Godot boundary mirrors them.

`grenades` is a required separate integer from zero through six. It is neither
a weapon slot nor an ammunition pool. A grant with `kind: "grenade"` and bounded
`amount` uses ordinary personal or contested claims; its pickup carries kind
`grenade`, actual amount, no weapon and no pool. A throw changes the private
count, with no magazines or reload. Weapon-only mutators refuse grenades.

`proximity_mines` is a separate optional integer from one through four,
omitted while zero, so earlier readers keep every map without mines. It is
neither a weapon slot nor a grenade. A grant with `kind: "proximity_mine"` and
an `amount` from one through four uses ordinary personal or contested claims;
its pickup carries kind `proximity_mine`, actual amount, no weapon and no pool.
Weapon-only mutators refuse mines. Current saved run equipment stores its own
bounded actual mine count, independently of grenades, and carries it through
M08 and M09 entry and retry.

Pickup entries additionally support `kind: "ammo"`, `pool` (`bullets`, `shells`,
`cells`) and a round `amount`. `claim` defaults to `contested` and is omitted in
legacy snapshots. A `personal` weapon supply stays publicly available while each
participant claims it independently once per development life. Contested stock
has one authoritative winner and reports the actual received amount in the pickup
event. On campaign maps, claimed stock stays unavailable with no `respawn_in`
until the authoritative party reset. Outside campaign play, ammo returns after
200 ticks and other arcade pads retain their existing timers. Claims require proximity and, on authored
maps, unobstructed sight. Current development death resets inventory and claims.
A resumed pawn keeps the claims it still holds. A new hello does not restore a pawn that already left.

#### Ack

Unicast after each server tick to a human whose Action carried a `seq`. The root fields keep their existing shape. The optional `movement` version 1 object carries the final 3D body state and whether that tick produced a replayable movement step. The Godot client predicts the local human pawn from these Acks. The server snapshot remains authority. Clients that never send `seq` (agents, spectators, older clients) do not receive Acks.

```json
{
  "type": "ack",
  "seq": 4123,
  "tick": 88210,
  "x": 12.25,
  "z": -3.5,
  "yaw": 1.5707963,
  "pitch": 0.25,
  "movement": {
    "version": 1,
    "epoch": 2,
    "applied": true,
    "y": 1.8,
    "vx": 0.0,
    "vy": 6.0,
    "vz": 5.0,
    "effective_speed": 5.0,
    "jump_input": true
  }
}
```

**Fields:**
- `seq`: the newest selected numbered input sequence. It can skip samples or
  repeat across ticks while the same held Action is reused. During a tick that
  does not apply movement, it remains the last selected sequence. After input
  ownership resets, it may remain historical even on the first active tick
  stepping neutral input. The new epoch invalidates replay of that old Action.
- `tick`: the server tick after which this state was captured. This is the
  authoritative movement-step identity; `seq` is a sampled Action identity.
- `x` / `z`: authoritative position after that tick
- `yaw`: authoritative horizontal facing after that tick
- `pitch`: authoritative vertical facing after that tick, default zero when
  reading older messages/recordings
- `movement.version`: 1 for this optional extension. An older Ack omits
  `movement`; a newer client then uses authoritative snapshots. No new Action
  field or global gameplay requirement is introduced by this outbound block.
- `movement.epoch`: per-pawn movement baseline revision. It advances on a
  round transition, respawn, input ownership reset, or campaign continue.
  A reconnect, role change, MapInfo, death, changed epoch or unapplied tick
  clears any client replay history. Server tick and input sequence do not rewind.
- `movement.applied`: true only if this pawn completed a replayable movement
  step and remains active at the end of the tick. Warmup, ended rounds, frozen
  missions, death and respawn ticks are false. The final pose still comes in
  the Ack. The zeroed `vx`, `vz`, `effective_speed` and `jump_input` on a false
  tick must not be replayed as an Action.
- `movement.y`: authoritative world-reference position, the same coordinate
  as `Snapshot.players[].y`. The movement integrator uses feet height
  `y - PLAYER_FLOOR_Y` internally.
- `movement.vx`, `vy`, `vz`: post-collision body velocities in world units per
  second. The current live step replaces horizontal velocity immediately on
  each active tick; these fields preserve the complete resulting state.
- `movement.effective_speed`: pre-collision speed selected for that tick,
  including the compliance modifier, or zero when `applied` is false.
- `movement.jump_input`: the latched or held jump request sent into the
  movement integrator for this tick. It is not proof of takeoff: an airborne
  body or low ceiling can prevent a new jump.

The server builds the Ack after simulation. It queues MapInfo, Mission,
Snapshot and events before the same-tick Ack unicast. An unsent quiet world
may be replaced by a newer world, so an Ack can arrive without its same-tick
Snapshot. Snapshots carrying resolved shots or explosions remain in order
before the same-tick Ack. A client must accept Snapshot before Ack, skipped
world ticks, and a missing Ack after connection loss. Godot
validates finite body numbers, exact JSON integer values, monotonic tick and
epoch, and u32 sequence progression before exposing a version 1 Ack.


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
  "playlist": "Arena Duel",
  "body": "human" | "synthetic",
  "duck": true
}
```

**Fields:**
- `player_id`: UUID of the player entity (null for spectators)
- `role`: Echoed role from Hello
- `body`: the accepted body of a human or agent pawn: the requested one on a
  fresh join, except that a bound solo run keeps its saved body. A resume keeps
  the parked pawn's own body. Omitted for a spectator and by
  servers before capability 13; a reader then treats the pawn as human rather
  than inferring a body from the role or name.
- `duck`: present and true only when this server accepts a held `Action.duck`
  and publishes the resolved stance. Omitted by older servers. Absence means
  the client must not send the key.
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

Periodic state broadcast containing all visible game entities. Produced at ~20 Hz.
Each client holds at most one replaceable unsent world in a bounded 64-message
queue. A newer world can replace it when exact discrete facts are unchanged.
Motion and countdowns may skip ticks; resolved shots, explosions, score and
roster changes, round transitions, and other discrete facts remain ordered.
MapInfo and Mission form barriers even when the map ID stays the same. Events,
inventory and acknowledgements are never replaced. A full reliable queue or
a write stalled for two seconds disconnects that client. An in-progress write
cannot be replaced, and combat-heavy queues can still reach this bound.

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
- `grenades`: Optional live array, omitted when empty. Each strict entry has
  `id` (monotonic u32), `owner_id`, finite three-component `position`, remaining
  `fuse_ticks` (1 through 40), and `bounce_count` (0 through 640). The count
  advances for actual impacts with at least 1 m/s normal speed; settled support
  is not a bounce. Initial observations never replay earlier contact cues.
- `explosions`: Optional resolved array for this tick, omitted when empty.
  Each strict entry has `id`, `owner_id`, finite `position`, `radius` (4), and
  up to 256 unique `hits`. A hit has `target_id`, actual `hp_damage`,
  `armor_damage`, `target_hp_after` and `killed`. Damage uses nearest actual
  body distance, linear 100-to-zero falloff and current solid occlusion. It
  respects armor, raised bodies and real tram cover. Self damage has no self
  frag or outgoing credit. A dead owner retains a launched grenade; explicit
  leave, retry, map/round replacement or departure clears it. Gun traces are
  not invented for grenades.
- `mines`: Optional live array, omitted when empty. Each strict entry has `id`
  (from the same monotonic serial as grenades), `owner_id`, finite `position`,
  unit `normal` of the surface it stuck to (zero while flying), `phase` and the
  `phase_started` and `phase_ends` ticks. Phases: `flying` (window zero),
  `arming` (exactly 40 ticks after sticking), `armed` (window zero) and
  `tripped` (exactly 4 ticks to the blast). An armed mine trips when its owner,
  or any living active body the owner's damage would land on, is within 2 m of
  its centre with clear sight. A companion or teammate the owner cannot hurt
  never trips it. A mine that has not stuck within 100 ticks leaves without a
  blast. Unlike a thrown grenade, a placed mine is an owned device: the owner's
  death, explicit leave, retry, reset, map/round replacement and departure
  clear it. A mine blast appears in `explosions` with `radius` 4.5 and a 130
  peak with the same linear falloff, occlusion and self-damage rules; the radius
  names the device.
- `auditors`: Optional array of living campaign Auditors, omitted when empty.
  Each strict entry has `id`, `repairs_left` (zero through two) and, only while
  that Auditor is channeling, `channel_target`: the disabled Sweeper or Heavy
  Sweeper its repair reaches. The channel window is the Auditor's own
  `channeling` phase. A channel starts on a disabled bot from its own group
  within 18 m and clear sight; a damaging hit, broken sight, a missing body or a
  living body standing on it at the end snaps it without spending a repair. A
  completed channel stands the bot up at half its spawn health in a 20-tick
  `recovery`. Clerks and Auditors are never repaired; a third repair never
  happens. A held disabled body's window never exceeds 100 ticks.
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
  - `deaths`, `attacks`, `connects`, `heads`, `damage`: (optional) This fighter's
    round counts, omitted while zero. `attacks` is gun and fist shots.
    `connects` is shots whose pellets found a body, including a shield or a
    teammate that lost nothing. `heads` is connects with a pellet in the head
    band. `damage` is HP plus armor removed by guns, grenades and mines, with
    overkill excluded. Grenades and mines are not part of `attacks` or
    `connects`. Each value is a saturating `u32` copy of the private record.
    The hold-Tab board reads these fields. The frag event does not increment
    them. A missing field is zero. Older readers ignore the keys.
  - `weapon`: Current weapon name ("Flechette", "Rail", or "Scatter")
  - `team`: (optional) `union` or `coalition` in a team mode, omitted otherwise
  - `lives`: (optional) lives left this round, this one included, when lives are limited
  - `golden`: (optional) true while holding the golden Railgun, omitted otherwise
  - `ducking`: (optional) resolved crouch, omitted while standing. True while
    the duck key is held or the ceiling will not allow the 1.8 m body. The
    shot volume, eye, and contact height follow it. Older readers ignore it.
  - `collidable`: Boolean server-owned living-body eligibility. New servers
    always include it. Dead, detached, eliminated, respawning and unready
    campaign bodies report false. Legacy omission defaults to true, still
    subject to HP and mission participation; a present nonboolean is invalid.
  - `body`: (optional) `human` or `synthetic`, the participant's accepted body.
    Every human, agent and rule-bot participant carries it; rule bots take
    bodies by roster slot (human, synthetic, synthetic, human, repeating),
    independent of name and behavior, so both sides of a team match field both. Omitted for Union campaign
    actors and the arena boss, which keep their own authored identity. Fixed for
    the pawn's life: respawn, resume and continue keep it.
- `round_state`: (optional) Current round state ("Warmup", "Active", "Ended")
- `round_time_left`: (optional) Seconds left in Active (time limit) or Warmup countdown. Omitted while Ended.
- `frag_limit`: (optional) Frag limit for current round
- `shot_results`: (optional, omitted when empty) Every committed fire outcome on
  this tick, including shots from fighters killed during the same tick. Entries
  carry `shooter_id`, `shooter`, `hit`, optional `target_id`/`target`/`target_hp_after`,
  `damage`, `killed`, and `trace`. Do not join only against surviving `players` to
  count shots or infer their weapon.
- `projectiles`: (optional, omitted when empty) Points still in flight. Each entry
  is `id`, `x`, `y`, `z` in world metres. The server steps them. A reader that
  does not know the key ignores it. An empty list is the same as a missing key.
  This is not a weapon trace. The additive point list does not itself change
  admission; capability 23 introduced the Jammer's actor identity and delayed
  attack. Current discovery and campaign maps require 26. The client places bright markers at these
  server positions without predicting collision or damage.
- `mode_name`: Contested Frequency (scrap league that denies it exists)
- `playlist`: Arena Duel under the league lie
- `pressure`: (optional) Live pressure beat id. `"compliance_drone"` while the Compliance Drone is alive; `"compliance"` during Continuance compliance ping slow.
- `host_line`: Sticky Contested Frequency Host chrome for mid-join / mid-round observe. League Host line by default while Active (no pressure). During Warmup, Contested Frequency bumper names the map, dialed-in scrap roster (callsigns), and countdown seconds. Switches to the compliance Host line while pressure is live. While Ended, carries the MVP Host bumper. Clients show this on join without waiting for the next `round_start`.
- `team_scores`: (optional) `{"union": n, "coalition": n}`, side frags this round, present only in team deathmatch.
- `flags`: (CTF only) exactly two entries, Union then Coalition. Each has `team`, `stand` and `position` as `[x, floor, z]` metres, `status` (`home`, `carried`, `dropped`), optional `carrier` UUID only when carried, and `return_ticks` only when dropped. Stands stay fixed for the round; carried positions follow the authoritative fighter. Present during warmup, active play and intermission.
- `capture_scores`: (CTF only) side capture counts, independent of fighter and team frags. `capture_limit` is the host's capture target (default 3).
- `mvp` / `mvp_frags`: (optional, present while Ended) Structured round MVP name and frag count for mid-join / `round_state` rehydrate. Omitted during Warmup and Active. Same selection as `round_end` MVP (top score / frags).
- `pickups`: (optional, omitted when empty) Scrap layout: `map_id` (1 Arena Duel / 2 Compliance Yard) and `map_name`. Mid-map pads (weapons, health, armor). Each entry: `id`, `kind` (`"weapon"` / `"health"` / `"armor"`, default `"weapon"`), optional `weapon` (weapon pads), optional `amount` (health/armor pads), `x`/`y`/`z`, `available`, optional `respawn_in` (ticks until the pad returns). Health pads heal +40 (cap max HP); armor scrap grants +25 (cap 100). Touch claim is authoritative on the server; clients only render.

**Notes:**
- Ordinary dead fighters are omitted; campaign corpses remain for their bounded
  death presentation and report `collidable: false`.
- Clients must handle players appearing/disappearing
- No delta compression in v1 (future optimization)

Living eligible characters block ordinary horizontal movement when their
0.5-metre radii and registered vertical spans intersect. Fighter and civilian
height is 1.8 metres, Crawler height is 0.8 and Notary height is 0.7. Contact
preserves sliding, map support and escape from pre-existing overlap; it does
not make characters standing surfaces. Reachable mission civilians use their
published feet while the mission is in progress. Combat remains independently
resolved: an already committed Crawler leap contact can damage on its frame,
and body blocking does not replace shot geometry. Tram obstruction refuses the
whole platform step. This additive snapshot fact does not change capability
27 or campaign rules revision 3.

The local human presenter mirrors contact math using validated, recent static
snapshot bodies for at most three speculative ticks, with a bounded four-sample
history. Moving peers are not extrapolated and can require an ACK correction.
Invalid or stale contact input suspends speculative movement until fresh
authoritative state arrives. ACKs, never predicted body contacts, decide actual
positions and velocities.
- Round fields present when round system is active

**Shot evidence:** current servers always include `trace`; old recordings omit
it and deserialize as absent. `trace.weapon` is the firing weapon in snake case.
`origin` and `end` are three finite world coordinates. `impact.kind` is `fighter`,
`solid`, or `range`. Fighter/solid impacts include an outward unit `normal`;
range exhaustion has no surface normal. The endpoint is the actual surface hit,
or the weapon range limit for a clear miss. A ray starting inside a body/solid
stops at its origin and uses the reverse ray direction as its presentation normal.

**Scatter pellets:** a scatter blast is seven seeded rays from one `origin`. The
server groups them by what they struck and publishes one result per struck
fighter, in the order of each fighter's first pellet, then one `hit: false`
result for every pellet that hit cover or ran out of range. Each of those
results carries `trace.pellets`, the pellets it covers in firing order, each an
`end` and an `impact` with the shape above; `trace.end` and `trace.impact`
repeat its first pellet so a reader that ignores pellets still draws one honest
trace. A blast has at most seven pellets across all its results. Other weapons
omit `pellets`. A result's `damage` is the sum of its pellets, each with its
own falloff, applied once so armour absorbs once and one death is one frag; its
`killed` is true when that sum first takes the fighter to zero. A shooter fires
at most once a tick, so all of one shooter's results in a tick are one shot.

```json
{"shooter_id":"550e8400-e29b-41d4-a716-446655440000","shooter":"ArenaFox","hit":true,
 "target_id":"660e8400-e29b-41d4-a716-446655440000","target":"Bot1","damage":40,"target_hp_after":60,"killed":false,
 "trace":{"weapon":"scatter","origin":[0.0,1.6,0.0],"end":[2.5,1.55,0.1],"impact":{"kind":"fighter","normal":[-1.0,0.0,0.0]},
  "pellets":[{"end":[2.5,1.55,0.1],"impact":{"kind":"fighter","normal":[-1.0,0.0,0.0]}},
             {"end":[2.5,1.62,-0.2],"impact":{"kind":"fighter","normal":[-1.0,0.0,0.0]}},
             {"end":[2.5,1.4,0.3],"impact":{"kind":"fighter","normal":[-0.9,0.0,0.44]}},
             {"end":[2.51,1.7,0.0],"impact":{"kind":"fighter","normal":[-1.0,0.0,0.0]}}]}}
```

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

```json
{"side":"companion","kind":"latch","phase":"following","phase_started":240}
```

M02 spawns one server-owned Latch pawn when `companion_released` completes. They
appear at the second ward bay in `releasing` for 240 ticks, then follow the
nearest ready living participant. `firing` marks a bounded Tack support shot at
an active visible Union enemy, with `phase_started` set to that transition tick.
Their resolved shots use the ordinary `shot_results` channel. They are present in
snapshots for late observers and reconnects, but never take a party seat, score,
participant record or supply claim. They are not a departure requirement or bullet
shield, and ordinary combat cannot kill them. A centered preflight avoids firing
through a participant's known position. If movement or Tack spread later crosses
that participant, the companion ray ignores their body and cannot report a hit
on them. M02 attempt reset removes Latch and
a later lawful release spawns one fresh pawn.

An M02 Clerk can initially include `"seated":true` while idle in the guard
room. The server omits the field when false and clears it when the encounter
wakes or a dormant Clerk is hit. No other Union kind uses this posture. It
changes presentation only, not the authoritative body or shot geometry.

`Role` describes the connection's controller, not faction or fictional anatomy.
Human and external-agent participants are allies. Union `kind` is `clerk` (human
security), `sweeper` (bot), `heavy_sweeper` (armored bot), `turret` (fixed
equipment), `crawler` (low constrained bot), `jammer` (stationary service
transmitter), `notary` (flying Office patrol equipment), `auditor` (human custody
officer with a shield plate), `ranged_sweeper` (stationary marksman bot,
capability 30) or `enforcer` (human elite in issued powered armor, capability
34). Names are labels, never a
targeting rule. Current
campaign identity describes these introductory encounters; it does not implement
Inheritance takeover, additional companions or the complete co-op lifecycle.

Phases are `idle`, `moving`, `windup`, `leaping`, `firing`, `recovery`, `hit`, `dead`
and, for an `auditor` only, `channeling`, or for an `enforcer` only, `charging`.
Their start/end are authoritative simulation ticks at 20 Hz. Idle and moving
have no fixed duration (`phase_ends == phase_started`); other phases may be
interrupted by hits, lost sight or death. A firing animation never causes damage.
Resolved `shot_results` still supply the actual weapon, ray and outcome.

Kind-specific phase meaning, same wire shape. A `heavy_sweeper` fires a
four-round burst after its windup and, after each recovery while it still sees
a target, spends up to 24 ticks in `moving` shuffling sideways. Ordinary hits
do not interrupt it: `hit` appears only when one tick deals at least 40 damage,
at most once per attack cycle, for 16 ticks. A `turret` never changes position.
In `idle` it sweeps its head around the authored yaw; in `moving` it is turning
its head toward a target (the actor yaw is the head). Its `windup` is the
charge before one Rail shot, and broken sight during `windup` or `firing` ends
the attack in `recovery` without a shot. Its `hit` follows the same heavy-hit
rule for 10 ticks. Windup and recovery durations per difficulty are in
[the difficulty plan](plans/difficulty-and-rewards.md).

An `enforcer` has 140 HP and uses Fists for its actual contact attack. It
approaches at 0.45 times ordinary player speed. With supported feet, clear
target sight within 8 m and a feet-height difference at most 0.5 m, its
windup locks one horizontal bearing. Windup lasts 32, 24 or 20 ticks on
Assisted, Standard or Severe. Its 14-tick charge moves at 1.6 times ordinary
player speed, never follows a dodge, and lands at most one 30-damage contact.
Normal cover and living-body sweeps bound its 1.5 m knockback. Recovery lasts
44, 36 or 30 ticks. Ordinary hits leave the charge committed; a heavy 40-damage
tick interrupts into a 16-tick hit, at most once per attack cycle. A real
descent over 2.5 m after a supported charge launch defeats the suit through
normal self-damage, with no invented participant frag. An already falling
body cannot launch or claim this counter. The client presents these ticks and
resolved contact facts; provisional poses are not final role art acceptance.

A `ranged_sweeper` has 70 HP and carries the `Sniper`. It never changes
position. It sees a participant within 90 units when either the chest or
the head is in clear line of sight, notices a new target only within 1.0 radian
of its authored yaw, and engages within 88 units. Its `windup` is the scope
glint and hold: the aim locks on the first windup tick and one Sniper shot
resolves on the tick `phase_ends`. Windup lasts 40, 30 or 24 ticks on
Assisted, Standard and Severe, recovery 50, 40 or 32. Broken sight during the
windup cancels it into a 12 tick `recovery` without a shot, and any damaging
hit enters a 6 tick `hit` that also cancels it. With no Cells it stays `idle`.

A `crawler` uses a server-owned 0.8 m body, including movement clearance, shot
volume and target centre. Its `windup` is a 12-tick crouch that locks the target
position and bearing. The `leaping` phase lasts at most 16 ticks and moves the
body along that bearing without homing. Server movement resolves at most one
contact hit per leap against a hostile body; a wall, lateral dodge or a miss
prevents it. The Crawler then spends 20 ticks in `recovery`. These provisional
durations are the same across difficulty tiers and do not change the campaign
rules revision. A contact resolved during movement can trade with a shot fired
later in the same tick. Presentation frames do not apply damage.

A `jammer` has 90 HP, no locomotion and no carried gun. Its wire weapon is
`Fists`, but it does not perform a fists attack. Its dish unfolds during a
24-tick `windup`, then its `firing` phase launches one traveling pulse along
the aim committed at windup entry. Broken sight and ordinary hits interrupt the
tell. It spends 40 ticks in `recovery`, and cannot launch another pulse while
its previous one is in flight. These timings are identical across difficulties,
leaving existing difficulty tables and rules revision unchanged. A pulse travels
at 2.5 metres per second, deals 12 damage through the shared combat resolver,
and expires after 240 ticks (12 seconds). A solid or the first eligible body
ends its flight; a sideways dodge can avoid it. Firing poses do not resolve an
instant hitscan attack and produce no gun `shot_results` trace. Pulse positions
appear in `projectiles`; resolved damage still emits the existing hit event.
Campaign retry and party reset clear all in-flight points. Killing the emitter
does not cancel an already launched pulse.

A `notary` has 50 HP and a raised 1.3 by 1.3 by 0.7 m axis-aligned shot box.
Snapshot position retains the shared eye-height convention; its underside is
`position.y - 1.5`, with its target centre 0.35 m above that. Alive bodies hover
within authored clear volumes and short patrol segments, separately from ground
navigation. Windup freezes its position and commits aim. The three-round Tack
burst has five-tick spacing; positive damage interrupts it. It keeps horizontal
separation at least as large as its elevation above a target, avoiding direct
overhead attacks. The first resolved round supplies the photograph evidence
described in M04 state. Firing poses alone never imply a shot or photograph.
Death applies server gravity onto actual ground or solid support, then leaves
a short harmless, nonblocking wreck. Retry removes it. The original directional
client atlas, shadow, fan loop, shutter and supported crash cue follow these
facts; late-joined corpses do not replay crash cues.

An `auditor` has 120 HP, the Pistol with its own finite Bullets and 0.4 of
participant top speed. Its one-shot attack uses windup 22, 14 or 12 and recovery
32, 22 or 18 ticks on Assisted, Standard and Severe, and any damaging hit staggers
it for 6 ticks. Its shield plate halves traced shot damage (rounded up) arriving
within 60 degrees of its facing; blasts wrap the plate. Its `channeling` phase
lasts 60, 44 or 36 ticks and holds still facing the disabled body named by the
snapshot's `auditors` entry; see that field for start, snap and repair rules. A
repaired Sweeper returns from `dead` straight to `recovery` with positive HP.
These rows are part of rules revision 3 from their first build.

Campaign participants cannot damage one another. Participant and Union allies
intercept rays with `hit: true`, `damage: 0` and `killed: false`; zero damage must
not show a hit-confirm or wound. The M02 companion does not intercept bullets or
collect supplies. Dead enemies remain in snapshots for
40 ticks with nonpositive HP and phase `dead`, then disappear. A dead Jammer is
retained longer while its launched pulse needs the original combat owner. It
disappears after that pulse resolves. A dead Notary falls to support before its
wreck hold expires. Other dead enemies cannot move. None can fire, collect
supplies or intercept shots, and none use arcade respawn. Exclude
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
state until an accepted continue resets the entire attempt. Local solo runs now
persist mission-entry state as described under Desktop process bootstrap; the
mission contract above owns shared lift departure.

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
  "killer_score": 5,
  "killer_team": "union",
  "victim_team": "coalition"
}
```

`killer_team` and `victim_team` appear only in a team mode. A frag where both
name the same side is a team kill under friendly fire: it scores nothing and
`killer_score` is unchanged.

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

**Crawler Scrabble Event:** (one positional warning when an authored Crawler
group's entry region alarms; the client chooses a localized caption and spatial
sound)
```json
{"type":"event","event":"crawler_scrabble","position":[-12,0,-27]}
```

`position` is a world-space source near the first Crawler in that group. It is
not an asset path, caption, player identity or damage instruction. A preemptive
shot at a visible dormant Crawler can wake it before region entry without this
event. Clients validate its finite three-component shape before playback; the event remains
available to sound-muted players through the caption and visible attack tell.

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

**Venue notice.** The person at a dedicated `--console` desk, not a player
and not the on-air Host. The text already begins `The venue: `.

```json
{
  "type": "event",
  "event": "venue_notice",
  "text": "The venue: doors at the bell"
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

A claim that found an authored secret adds `"secret": true`; the field is
omitted otherwise. Like other pickup notices, the Godot client shows its cue only
for its own participant, or for the fighter a spectator is following:
```json
{
  "type": "event",
  "event": "pickup",
  "player": "Visitor",
  "player_id": "550e8400-e29b-41d4-a716-446655440000",
  "kind": "weapon",
  "weapon": "Shiv",
  "pickup_id": "alcove_shiv",
  "secret": true
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
- `event`: Event type (`frag`, `hit`, `crawler_scrabble`, `respawn`, `round_start`, `round_end`, `flag`, `player_joined`, `player_left`, `compliance_ping`, `boss_spawn`, `boss_down`, `speak`, `venue_notice`, `pickup`, `killstreak`, `host_reaction`)
- `position`: (`crawler_scrabble` only) three finite world coordinates for the spatial sound source
- `kind`: (pickup only) Pad kind: `"weapon"` / `"health"` / `"armor"` / `"golden_rail"` (default `"weapon"`). Weapon and golden pads also carry `weapon`; health/armor pads carry `amount`.
- `rules`: (round_start, optional) the arena's rule set, repeated each round for event readers
- `winning_team`: (round_end, team modes) the winning side, omitted for a draw. `team_scores` is the final side frags for TDM; `capture_scores` is the final captures for CTF. A CTF round can have an MVP by frags while its winning side is decided by captures.

CTF emits `{"event":"flag","kind":"taken|dropped|returned|captured","flag":"union|coalition","player":name,"player_id":uuid,"capture_scores":{"union":n,"coalition":n}}`. `player` and `player_id` are omitted on automatic return. The flag field names the flag's owner side, which can differ from the carrier's side. Events follow authoritative combat and objective resolution for that tick.
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

### Match rules

A server started with one mode runs that rule set until it stops
(`--mode ffa|tdm|ctf|sabotage`, repeatable `--mutator`, `--friendly-fire`, `--frag-limit` for FFA/TDM, `--capture-limit` for CTF or `--sabotage-format short|match` for Sabotage).
`--playlist` replaces that fixed choice with the built-in night list: the same
process changes map and mode when a show ends, and each `map_info` carries the
show now in play, including when the map id does not change. Sabotage plays
its full short match before the list moves. A playlist file is not on the wire.
`map_info.rules` carries the current rule set to every connection, `round_start` repeats it,
`GET /status` names it, and the MCP adapter returns it from `round_state`.

```json
{
  "mode": "tdm",
  "name": "Team Deathmatch: Rail Only, Two Lives",
  "mutators": ["rail-only", "two-lives"],
  "friendly_fire": true,
  "lives": 2
}
```

- `mode`: `ffa` (free-for-all), `tdm` (team deathmatch), `ctf` (capture the
  flag), or `sabotage` (round-based plant and defuse, below).
- `name`: an English label for logs and agents. Clients key their own labels.
- `mutators`: sorted, unique ids, omitted when none: `rail-only`,
  `shotgun-only`, `fists-only`, `licence-to-kill`, `golden-rail`, `two-lives`.
  A Rust reader refuses an unknown id; the Godot client drops it.
- `friendly_fire`: present and true when team damage lands. Off by default.
- `lives`: lives per fighter per round when limited (Two Lives sends 2,
  Sabotage sends 1).

Rules the server enforces:

- **Team deathmatch.** Sides are `union` and `coalition`. Every join, human,
  agent or rule bot, takes the smaller side (ties go to the side behind on
  frags, then the coalition). At a round start a side two or more ahead gives
  up rule bots first, then its most recent joiners, who respawn on the new
  side. The Union spawns in the negative X half and the coalition in the
  positive X half, through the same spawn safety as free-for-all, counting only
  enemies as threats. With friendly fire off, a shot stops on a teammate, who
  takes no damage (`shot_results` shows `hit: true`, `damage: 0`). A frag of an
  enemy adds one to the killer and one to the side; `frag_limit` is the side
  limit. At the clock the higher side wins or the round is a draw. Weapon pads
  respawn after 30 s in team modes. `PlayerState` hostility helpers treat a
  teammate as not hostile.
- **Capture the flag.** A staged league scenario on Arena Duel, Directive 17,
  or Sector 9. Each of those maps has a Union stand in the negative X back
  third and a Coalition stand in the positive X back third. Compliance Yard,
  Reclamation Gulch and Tripoint Works have no stands, and a rotating playlist
  is refused. Touch the enemy flag to carry it. A
  living owner-side fighter touching a dropped friendly flag returns it. A
  carrier can shoot. Death, leave, disconnect parking or side reassignment
  drops the flag; an untouched dropped flag returns home after 400 ticks (20 s).
  The carrier scores only by touching the own stand while the own flag is home.
  A grounded flag cannot be returned or retaken for its first 10 ticks (0.5 s)
  after a drop. This makes the drop visible in replicated snapshots even when
  the defender is standing on the fallen carrier. The 400-tick return clock
  starts at the drop and includes this touch window. Combat resolves before
  objective touches, and eligible touches use Union then Coalition side order,
  followed by ascending participant UUID within each side. Parked resume pawns
  cannot touch flags until the socket resumes. Dropped flags rest on the
  reachable support below the carrier rather than hanging in the air.
  Captures, not frags, decide the winner at the capture limit or clock. Equal
  captures at the clock draw. The default capture limit is 3. `--frag-limit`
  and the Two Lives mutator are refused in CTF. The Compliance slow and Drone
  arena events do not run in CTF.
- **Sabotage.** See [Sabotage](#sabotage) below.
- **Rail Only, Shotgun Only, Fists Only.** Everyone holds that one weapon with
  unlimited ammunition, `weapon_swap` to anything else is ignored, and weapon
  and ammunition pads are removed. Health and armour pads stay. No private
  loadout is sent, as on any full-arsenal arena.
- **Licence to Kill.** Any hit that deals damage kills: `damage` is at least the
  victim's health plus armour.
- **Golden Rail.** One pickup with `kind` `golden_rail` and `id` `golden_rail`
  replaces the map's Railgun pad (the centre when a map has none). Touching it
  takes it: `golden` becomes true on the holder, who switches to the Railgun, and
  a `pickup` event with kind `golden_rail` follows. The holder's Railgun hits
  kill. When the holder dies or leaves, the pickup is available again.
- **Two Lives.** `lives` starts at 2 each round (1 for a fighter who joins a
  live round). A fighter whose lives reach zero leaves `players` until the round
  ends, like a fighter waiting to respawn, but does not return. When one fighter
  (or one side) is left with a life, having started with two or more, the round
  ends: `reason` is `Last fighter standing` (with that fighter as `winner`) or
  `Last side standing` (with `winning_team`). The mid-round Compliance Drone is
  off on a lives-limited server.

Plain free-for-all servers send `rules` with `mode` `ffa` and no mutators, and
none of the team, lives or golden fields.

#### Sabotage

The first flagship round mode, on Sector 9 only. The free coalition
(`coalition`) always attacks: it carries a charge to one of two Union sites and
plants it with a held Use. The Union (`union`) defends the sites or defuses a
planted charge. One life per round, no shop and no loadouts. A server with
`--mode sabotage` on any other map, or with rotation, refuses to start. A
Sabotage server is a shared room: it speaks gameplay 37 and geometry 2 for
every role, spectators included. Capability 28 is when the objective arrived.

**`map_info.sabotage`** carries the static layout once, never per tick:

```json
{
  "attackers": "coalition",
  "sites": [
    {"id": "a", "center": [-38.0, 0.0, -27.0], "radius": 3.0},
    {"id": "b", "center": [-38.0, 0.0, 27.0], "radius": 3.0}
  ],
  "callouts": [
    {"id": "a_frame", "min": [-44.0, -33.0], "max": [-32.0, -21.0]},
    {"id": "mid_doors", "min": [-30.0, -5.0], "max": [30.0, 5.0]}
  ]
}
```

- `sites`: exactly two, `a` then `b`. `center` is feet height; `radius` (1 to
  8 m) is the horizontal plant area. A is the correction frame under the Sort
  Deck, B the registry server between the West Hall freight stacks.
- `callouts`: at most 32 named x/z rectangles, most specific first; a reader
  names a point by the first region that contains it. Ids are short
  snake_case; clients key their own words. Sector 9 sends `a_frame`,
  `b_server`, `sort_deck`, `mid_doors`, `defender_hall`, `attacker_yard`,
  `north_mid`, `south_mid`, `mid`, `west_hall`, `east_hall` and `service`.

**`snapshot.sabotage`** is the round, from the first round on:

```json
{
  "format": "short",
  "phase": "planted",
  "round": 6,
  "period": 0,
  "half": 2,
  "half_rounds": 4,
  "rounds_to_win": 5,
  "score": {"union": 3, "coalition": 2},
  "alive": {"union": 2, "coalition": 1},
  "clock_ticks": 412,
  "charge": {"status": "planted", "position": [-37.2, 0.0, -26.1], "site": "a"},
  "progress": {"kind": "defuse", "player_id": "...", "site": "a", "ticks": 40, "needed": 120}
}
```

- `phase`: `muster` (10 s held in the spawn zones; pickups work, fire and
  throws do not, and a step that would leave the zone is refused), `live`
  (1:45), `planted` (the charge's 35 s clock replaces the round clock), `over`
  (decided; the result card is up).
- `round` counts from 1 within the match. `period` is 0 in regulation and
  counts extra periods. `half` is 1 or 2 within the period, `half_rounds` its
  length, `rounds_to_win` the round wins that take the match from here.
- `score`: round wins by current uniform. At a side swap every fighter changes
  uniform and the two numbers swap with them, so the score follows the people.
- `alive`: fighters still standing per side.
- `clock_ticks`: ticks left on the clock that matters now. `round_time_left`
  carries the same clock in whole seconds while the round is active.
- `charge`: absent only when no attacker is in the match. `status` is
  `carried` (with `carrier`), `dropped`, `planted` (with `site`), `defused` or
  `detonated`; `position` is feet height. The carrier is present for every
  reader; clients show it only to teammates and spectators until per-recipient
  interest filtering exists.
- `progress`: a held Use under way, with `kind` `plant` or `defuse`.
  Interruption removes it and loses all progress.
- `swap_after`: present and true when this round ends a half.

Rules the server enforces, in tick order after combat:

- **Muster and spawns.** Every round, each side spawns in its zone: the Union
  in the West Hall's defender hall, the coalition in the attacker yard inside
  the East Hall's center door. Survivors keep every weapon, their ammunition
  and armour, with health restored; anyone who fell, and everyone at the start
  of a match, starts with fists. A personal Tack pad in each zone is within two
  seconds of every spawn point and can be claimed once per round. Map pads stay
  on. The equipment is the discovery inventory, so private `loadout` messages
  flow as on a campaign map.
- **The charge** starts with a seeded random attacker. It drops at the feet of
  a carrier who dies, leaves, parks or changes side, and any living attacker
  touching it within 1.5 m (and 2 m vertically) takes it after a 10-tick drop
  window. Defenders never carry it. A death in Sabotage also leaves the
  victim's best primary (the held one if it is a primary, then Rail, Scatter,
  Flechette) as a one-time `dropped_<n>` weapon pickup, cleared at the next
  round; weapon-only mutators drop nothing.
- **Plant.** The carrier, inside a site's radius with feet within 1 m of its
  floor, holding `interact` with no movement keys while grounded, plants after
  60 ticks (3 s). Releasing, any movement key or displacement, leaving the
  area, death, or any loss of health or armour interrupts it.
- **Defuse.** One defender at a time, within 1.75 m of the planted charge
  horizontally and 1 m vertically, holding `interact` still, defuses after 120
  ticks (6 s). Interruption loses all progress; the first eligible defender in
  join order starts.
- **Outcome**, checked in this order: a completed defuse (Union); detonation
  (coalition); elimination when both sides have fighters (before a plant the
  side with nobody standing loses, a same-tick double wipe going to the Union;
  after a plant only the Union can be eliminated, so killing every attacker
  still needs a defuse); the live clock running out before a plant (Union). A
  plant completing on the clock's last tick counts. A defuse completing on the
  detonation tick counts. A defuser killed on that tick does not.
- **Format.** `short` (default): halves of 4, first to 5; at 4-4 one extra
  pair, one round a side, then a draw. `match`: halves of 8, first to 9; at
  8-8 extra periods of two halves of 3, first to win 4 of the period,
  repeating while level. Sides swap after every half except entering an extra
  period. Frags carry across the rounds of a match. After a decided match the
  next round starts a new match.
- **Joining.** A joiner takes the smaller side, then the side behind on
  rounds. Joining during muster spawns in the zone; joining later sits out the
  round with `lives` 0 and returns next round.
- `--frag-limit` and the Two Lives mutator are refused; the arena's Compliance
  slow and Drone do not run.

**`event: sabotage`** reports every fact, with `kind`, optional `player`,
`player_id` and `site`, and `score` (round wins by current uniform):

| `kind` | When |
|---|---|
| `live` | Muster ends and weapons go live |
| `charge_taken` | An attacker picks up the loose charge |
| `charge_dropped` | The carrier died, left, parked or changed side |
| `plant_started`, `plant_interrupted`, `planted` | The plant begins, stops, or completes |
| `defuse_started`, `defuse_interrupted`, `defused` | The defuse begins, stops, or completes |
| `detonated` | The charge's clock ran out |
| `sides_swapped` | Every fighter changed uniform; sent at the next round's start |

**`round_end.sabotage`** carries the result; `winning_team` names the round's
winner and `winner` is omitted:

```json
{"reason": "defused", "round": 4, "score": {"union": 3, "coalition": 1}, "sides_swap": true}
```

`reason` is `elimination`, `detonation`, `defused` or `time`. `score` is by the
uniform each side wore in that round. `sides_swap` is present when the next
round swaps; `match_over` is present when this round decided the match, with
`match_winner` naming the uniform that won it (absent for a draw). The card
holds 5 s, or 8 s before a swap or after a match.


#### Host reactions

```json
{
  "type": "event",
  "event": "host_reaction",
  "kind": "streak_ended",
  "variant": 1,
  "player": "Dead Air Dan",
  "other": "Nightfall",
  "team": "union"
}
```

A Host beat from an authoritative fact. The server sends no words: the client
renders `HOST_REACTION_<KIND>_<VARIANT>` from `client/i18n/match.en.po`, filling
`{player}`, `{other}` and `{team}`. `variant` is 0 to 2 and rotates per kind
across the session. `player`, `other` and `team` are each omitted when they do
not apply. No reaction lands within eight seconds of the last one, except
`golden_rail`.

| `kind` | When | Names |
|---|---|---|
| `first_blood` | The first frag of a round | `player` the killer, `other` the victim, `team` the killer's side |
| `streak_ended` | A fighter on a streak of three or more is killed (not on first blood) | `player` the streak's owner, `other` who ended it, `team` the owner's side |
| `last_standing` | A lives-limited team round leaves a side of two or more with one fighter against two or more | `player` that fighter, `team` the side |
| `comeback` | A side that trailed by four or more draws level | `team` the side |
| `golden_rail` | Somebody takes the golden Railgun | `player` the holder, `team` their side |

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
- **Frag limit**: Default 10 kills; 25 side frags in team deathmatch. `--frag-limit` overrides either
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

The desktop menu supplies `--run-mode new|resume`. New starts at M01, archives
prior run bytes under a unique name and saves the initial run before readiness.
Resume locks and validates the versioned run against the exact authored
content bytes and campaign rules before readiness. An M01 exit waiting for M02
is checked against the M01 content it names, then promoted once to an M02 entry
under the same lock. M02 promotes to M03, M03 to M04 and M04 to M05 without
refilling continues or equipment. Compatible v2 M01, v3 M01/M02 and v4
M01/M02/M03 documents migrate to v13 after validating their historical revision
2 rules and exact content hash. The upgrade promotes rules to revision 3 with
exact original bytes retained. Strict v5 M01 through M04 documents retain revision
3 and upgrade to v13 with zero historical grenades. Strict v6 documents preserve
their real grenade counts and M05 release/boarding outcomes; they cannot forge
playable M06 or its future route outcome. Old shapes reject grenade
fields and forged M05 stages. Exact source bytes are archived before replacement;
v1 magazine-era saves remain incompatible. A second
child cannot own the same file. Omitting `--run-mode` retains independent
development behavior. The read-only `--local-run-preview` identifies the saved
mission, instead of using the launcher's guessed map. It prints one bounded
JSON status line for the menu: `missing`, `ready` (mission, difficulty, attempt,
continues, pending_continue, nullable body), `failed`, `abandoned`,
`awaiting_mission` (mission, difficulty, continues, nullable body),
`incompatible`, or `corrupt`. `awaiting_mission` identifies M02 after M01 or
M03 `scheduled_service` after M02, M04 `notice_to_vacate` after M03, or the
M05 `no_forwarding_address` after M04, M06 `port_of_entry` after M05, M07
`declared_goods` after M06, M08 `custodian_of_record` after M07, or the pending
M09 `passenger_manifest` after M08, or pending M10 `common_carrier` after M09.
M09 and the in-flight M10 prototype are supported; pending M11 `right_of_search` cannot launch.
Version 13 retains completed
M03 optional liberation IDs in `m03_outcome:{liberated_cars:[...]}` at the
pending M04 edge and throughout M04 entry, retry and terminal states. Completed
M04 adds `m04_outcome:{rescued_patients:[...],photos_completed}` exactly at
the pending M05 edge and throughout M05 entry/retry/terminal states. M05 adds
`m05_outcome:{released_workers:[...],evacuated_workers:[...]}` exactly at the
pending M06 edge and throughout M06 entry, retry and terminal states. Release contains either no workers or all three registered
IDs, and evacuated workers are a unique subset physically inside boarding.
Every v6 through v13 saved equipment object requires independent `grenades`
from zero to six. Versions 9 through 13 require actual `proximity_mines` from zero
to four. Historical v2 through v8 equipment never has a mine field; an explicit
strict upgrade assigns zero, rather than accepting a forged historical count.
M06 adds `m06_outcome:{prisoner_route_marked}` at its completed pending M07
edge and throughout M07 entry, retry and terminal states. Earlier outcomes
persist through every later edge. An M07 exit and later stages may carry the
Sniper Rifle; an M07 entry never does. M08 entry, continue and retry restore
the mission-entry equipment anchor, including its independent mine count.
M08 completion stores actual remaining counts at its M09 edge. The locked
promotion carries HP, armor, equipment, grenades and mines without an episode
refill; only old-map personal supply claims clear. M09 retry restores that
entry anchor and retains all earlier outcomes. Completion stores the actual
exit at pending M10; no Episode III refill or playable M10 is implied.
Version 12 retains version 10's required `m08_outcome` at that completed edge. Native
completion emits `{"kind":"recorded","custody_released":bool,
"recovered_mind_secured":bool,"captives_evacuated":bool}` from actual mission
progress. Evacuation requires release. The cabinet fact says a copy was
secured; it makes no claim that a mind was restored or is the same person.
Strict v9 completion upgrades to `{"kind":"historical_unrecorded"}` because
its old shape never recorded those choices. Earlier or unfinished stages
have no M08 outcome. Both tagged forms refuse extra fields. Historical
absence never becomes invented false values, counts or a mission gate.
At completed M09's pending-M10 edge, version 12 requires private `m09_outcome`.
Native completion captures `{"kind":"recorded","released_crew":[...],
"aboard_at_departure":[...]}` once at the accepted physical departure. Released
crew follow the actual canonical present roster: Tern and two berth crew,
plus Edda only with the authored recorded clinic rescue and Splice only with
actual recorded workshop evacuation. Aboard-at-departure is an ordered unique
subset whose real feet were inside the hatch region at confirmation. Later
body observations cannot rewrite it or the finite player exit.
Strict v10/v11 completed-M09 upgrades retain `{"kind":"historical_unrecorded"}`;
missing old choices do not become invented crew or empty boarding counts.
Both old readers refuse `m09_outcome`, even null, and both tagged current forms
refuse extra fields. Earlier/unfinished M09 has no crew outcome. This receipt
does not mark transit complete, grant any arrival or implement M10; released
crew's distinct short transition belongs to the future canonical promotion.
No live M09 wire field, capability or optional crew wait gate changes here.
Episode II continues refill
only in the locked completed-M05-to-M06 promotion, never on a format upgrade.
Strict v7 documents upgrade to v13 and cannot forge an M07 stage or a carried
Sniper Rifle. Strict v8 documents retain the completed M07 edge and its
Sniper, then promote into M08 without a refill. V8 refuses playable M08.
Strict v9 preserves all actual equipment and earlier outcomes. Its exact
shape refuses `m08_outcome`, even null, and any playable M09 stage before upgrade.
Strict v10/v11 upgrade through their exact historical shape, preserving recorded or
historically unrecorded M08 outcomes and actual equipment counts. Versions 2
through 11 refuse Repeater selection or ownership, including forged historical
fields. Historical v12 likewise refuses Repeater ownership throughout supported
stages through M09 and the pending M10 edge; no authored M10 find is implied.
Every writable upgrade archives the exact old bytes under the existing lock;
format migration grants no gun, ammunition, grenade, mine or continue refill.
Read-only preview preserves source bytes; writable migration archives exact
bytes under the existing writer lock before atomic replacement. Unknown future
versions, forged older M04/M05/M06/M07/M08 states and
changed source hashes are rejected before replacement. An absent body on a legacy
save is bound by the player's visible body choice on admission; a bound body
remains the server-owned run identity despite later profile changes.
The menu treats preview as advisory; launch validates again under the lock.

The optional `--difficulty assisted|standard|severe` defaults to `standard` on
a new run. A resume uses the saved difficulty and echoes it below. Bootstrap
version 2 requires that field; it is separate from
the on-wire campaign rules revision. No parent command changes it during a run.

```json
{"version":2,"mission":"recall_notice","difficulty":"standard","url":"ws://127.0.0.1:49152","gameplay_version":26}
```

The readiness record names the selected mission's current client contract.
M01 through M05, development or durable, name capability 26 for
campaign rules revision 3. Their older 18/22/24/25 bootstrap contracts are retired.
The local launcher checks this value exactly.

`--local-mission persons_unknown` without a run mode starts the bundled M02
graybox as a development child. It writes the same readiness line with
`"mission":"persons_unknown"` and `"gameplay_version":26`, carries no
`run`, and keeps development entry respawn and the shared wipe reset. With
`--run-mode resume`, M02 receives the saved solo run from M01 or resumes its
own entry; it requires capability 26. A new durable run must start at M01.

`--local-mission scheduled_service` without a run mode starts the independent
bundled M03 prototype with capability 26 and no durable save. With
`--run-mode resume`, it promotes a compatible completed M02 run under the same
writer lock or reopens an M03 entry. Health, armor, body, weapons, ammunition,
selected weapon and remaining continues carry unchanged; old-map claims clear.
Retry restores the M03 entry, mast and car releases. A failed migration keeps
the prior live file and exact content-addressed archive recoverable.

`--local-mission notice_to_vacate` without a run mode starts the independent
bundled M04 prototype with capability 26 and no durable save. Resume promotes
a completed M03 exit once under the writer lock or reopens its M04 entry.
Run identity, body, difficulty, exact equipment, HP, armor and remaining
continues carry unchanged; old-map personal claims clear. Completed M03 car
choices remain available through M04 retries. A pending destination plays its
arrival scene before readiness; restarting an existing entry skips that scene.
Dismissal consumes the input and waits for release before acknowledging.

`--local-mission no_forwarding_address` without a run mode starts the independent
bundled M05 prototype with capability 26 and no durable save. Resume promotes
a completed M04 exit once under the writer lock or reopens M05. It retains
body, difficulty, HP, armor, gun ammunition, independent grenades, remaining
continues and earlier car/clinic/photo choices, clearing only old-map personal
claims. Explicit Continue restores the M05 entry and all attempt state without
rewinding ticks, action sequence or inventory revisions. Completion saves the
pending Port of Entry boundary and separate release/physical boarding outcomes;
the next mission can be entered through the normal local resume path.

`--local-mission port_of_entry` without a run mode starts the independent
bundled M06 prototype with capability 27 and no personal save. Resume promotes
a completed M05 exit under the writer lock, preserving exact body, difficulty,
HP, armor, equipment and Earth outcomes and clearing only old-map claims.
That one promotion refills Episode II to three continues and a three-continue
level baseline. Read-only preview, historical-format upgrade, Practice,
reopening M06, retry, failure and abandonment do not grant another refill.
The arrival scene precedes readiness only for the pending M05 entry; resuming
an existing M06 attempt skips it. M06 completion saves `declared_goods` as a
pending destination.

`--local-mission declared_goods` without a run mode starts the independent
bundled M07 prototype with capability 32 and no personal save. Resume promotes
a completed M06 exit under the writer lock, preserving exact body, difficulty,
HP, armor, equipment, remaining continues and every earlier outcome, clearing
only old-map claims. Episode II was refilled entering M06, so this promotion
grants no refill and sets the level baseline to the continues that remain.
The arrival scene precedes readiness only for the pending M06 entry. M07
completion saves `custodian_of_record` as the supported next destination.

`--local-mission custodian_of_record` without a run mode starts the independent
bundled M08 development prototype with capability 31 and no personal save.
Resume promotes a completed M07 exit under the existing writer lock, retaining
actual independent mine and grenade counts, earlier outcomes and the remaining
Episode II allowance. Retry restores the M08 entry anchor. Actual completion
records the archive custody, cabinet and evacuation facts separately and saves
the supported `passenger_manifest` destination.

`--local-mission passenger_manifest` without a run mode starts the independent
bundled M09 development prototype with capability 34 and no personal save.
Resume promotes completed M08 under the same lock without an episode refill.
Actual inventory, body and archive outcomes carry; historical v9 choices remain
explicitly unknown. Readiness does not activate the loading fight at spawn.
Ordinary movement obtains the Tack before crossing its authored activation
boundary. Completion saves pending `common_carrier`; the prototype promotes it under the same writer lock.

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
- **Prediction**: Local human movement prediction and Ack reconciliation shipped on the WebSocket client. The local presentation increment interpolates remote fighters on a bounded 100 ms timeline, clears discontinuities and keeps shots tied to resolved traces. Campaign-enemy timeline interpolation and bounded lag compensation remain later work.

## Participant records

A `record` message is private to the participant and sent only to clients that
advertise gameplay capability 10 or later (8 before the ammunition contract,
whose multi-kill scatter records an older reader would refuse). Spectators
receive no private record.
Ordinary updates are bounded to once per 20 ticks; a new round, mission attempt
or status change sends immediately. The record's tick can precede the latest
snapshot. No record is delivered during initial arena warmup or to someone who
joins after a round has already ended without participating.

The current version-2 record includes `session_id`, `player_id`, `round`, `tick`,
`entered_at`, `round_started_at`, `ticks_per_second` (20), `map_id`, `map_name`,
`role`, `scope`, `status`, `total` and `attempt`. Its identity is the session UUID,
player UUID and round number, never a callsign. `entered_at` is the admission tick
or the latest round start for an existing participant. A late arena join has
`entered_at > round_started_at`. Mission attempts share one record identity.
The [shared format fixture](../client/golden/player_record.json) is read by Rust,
MCP and client tests; the [Shiv fixture](../client/golden/player_record_shiv.json)
covers the sixth slot and a found secret on both sides, and the
[Sniper fixture](../client/golden/player_record_sniper.json) the seventh.
Those fixtures retain historical revision 1. Current revision 2 requires exactly
eight weapon entries, with Repeater appended after Sniper. Revision 1 accepts
only its strict five/six/seven-column shapes and refuses an eighth even when
zero. Unknown revisions and a revision change within one record are refused.
The private per-recipient sender uses revision 2 for capability 35 or later;
earlier compatible readers receive revision 1 only when total and attempt
Repeater counts are genuinely empty. Nonzero new counts close incompatible
delivery instead of being truncated or assigned to Rifle. The unversioned
standalone CombatCounts format stays historical five/six/seven columns and
refuses serialization with nonzero Repeater counts; eight columns belong to
the explicit revision 2 record envelope.

Scopes are `arena` or `practice` with `round`, or `mission` with `mission`,
`attempt`, `rules` and nullable `run` (the solo run contract above). Calibration
and non-mission authored test maps are practice. Status is `active`, `continue`,
`complete`, `failed` or `abandoned`. A completed arena record means the round
finished, not that this participant won. A completed M01 or M02 record means
that mission's route finished, not that the unbuilt campaign finished. A
missing final update must be shown as incomplete; transport loss is not
evidence of failure or victory.

Completed mission records delivered to capability 33 or later optionally include
`mission_elapsed_ticks`, an exact
nonnegative integer in server ticks at `ticks_per_second` (20). It measures the
successful attempt from the party's readiness to authoritative departure,
including time spent dead within that attempt, excluding briefing and later
story/results viewing. Accepted retry starts a fresh clock. Completion freezes
this value. It cannot exceed `tick - round_started_at`, appear on a noncompleted
or nonmission record, or change after terminal delivery. Earlier historical
records omit it and retain their exact shape. Revision 1 delivery to capability
33 or 34 may include it; earlier recipients omit it. Absence means unavailable time,
not zero. No runtime par is currently authored. The completion tally uses the
existing attempt and total resolved counts, and never counts client-side kills.

Each count set contains `alive_ticks`, `deaths`, `hp_lost`, `armor_lost`,
`dry_triggers` and eight `weapons` entries in fists, Tack, flechette, scatter,
rail, Shiv, Sniper and Repeater order. A historical revision 1 writer sends
the shortest five/six/seven-entry prefix holding every nonzero old entry.
Revision 1 readers treat missing later old entries as zero, so retained history
keeps its shape and no slot changes meaning. `secrets`, present only when nonzero,
counts distinct authored secrets found: `total` over the whole run, `attempt`
this attempt. Finding a restored secret again after a continue raises `attempt`
but not `total`. It cannot exceed `alive_ticks`. Weapon counts are `attacks`, `damaging_attacks`, `kills`, `hp_damage` and
`armor_damage`, plus optional `connects` and `heads`. Every resolved gun shot counts one attack; Repeater warmup
counts none and held fire counts each actual shot separately. The
scatter's attack is seven pellets and counts once, as one connect when any
pellet found a body and one damaging attack when any pellet hurt anyone. One
shot is one connect and one head however many bodies it struck. A head is a
pellet in the head band, including a shield that stopped the damage. Fists
have no band test, so a fist head is refused. The scatter's kills are bounded by seven per damaging attack; every
other weapon's kills are bounded by its damaging attacks.
Fists and Shiv cuts count as attacks. A damaging attack removes positive HP or armor from a
hostile living target. Protected/friendly bodies, scenery, range misses and a
body killed by an earlier committed ray do not count as damaging attacks. A
body that was found still counts as a connect, including the shield, the
teammate and the body the earlier ray had already reached.
`connects` and `heads` are omitted while zero. A column that dealt damage and
omits both predates connect accounting. That omission is not a measured zero,
and `damaging_attacks <= connects` is enforced only once either count is present.
Heads are a subset of connects, and connects are a subset of attacks.
Effective damage excludes overkill. Simultaneous trades keep both attacks, and
one shot receives each death credit. Dry triggers are latched pulls on an empty
count, separate from accepted attacks; cooldown denials are neither.
Presenters derive rates from these integers. The server does not send percents,
Wilson bounds, or per-minute figures. A percent is
`1000 * numerator / denominator`, rounded half away from zero, shown to one
decimal (`2/3` is 66.7%). The product of the numerator and the scale is formed
in 128 bits. A rounded result that does not fit in an unsigned 64-bit integer
is omitted. A zero denominator is omitted, not printed as 0%. The hold-Tab
percent is printed beside its count (`66.7 (2/3)`). Damage per shot, damage
per body found, and damage per hurt use the same rounding at tenths (`scale` 10).
A gun line always shows damage per shot. It adds per body only when connects
were measured, are positive, and differ from the shot count. It adds per hurt
only when that count is positive and is a different denominator. Three equal
denominators print only per shot. Shots per kill use gun and fist attacks and
kills, so a grenade kill is not called a shot. A 95% Wilson interval is the
separate claim about how little a small sample means. It is labeled as an
interval and is not a substitute for the counts. On the record card it sits
on the headline rate: bodies over shots when connect accounting is present,
otherwise hurt over shots for an older damaging column. A second labeled
interval covers heads over those bodies whenever the head line is shown,
including zero heads. Per minute is `count * 1200 / alive_ticks` at tenths
(`scale` 12000, because the record ticks at 20 Hz and one decimal needs
another factor of 10). Zero alive ticks omit the pace. The clock in that
sentence is the window that was actually lived.

An optional `grenades` column has the same five original count fields, defaults to zero
for historical record version 1 and is omitted while unused. It does not carry
`connects` or `heads`: a blast is not a body ray. It leaves existing
gun indices unchanged. Aggregate totals include this column. One launch counts
one attack, one blast that damages any other eligible body counts one damaging
attack, and at most 256 kills can belong to it. Actual self HP/armor loss counts
only on the victim side. Successful throws suppress gun fire for that tick, so
aggregate attacks remain bounded by active ticks. Retained records keep their
existing byte shape when the grenade column is zero.

An optional `mines` column has the same five original count fields and rules beside the
grenade column: one placement is one attack, one blast that damages another
eligible body is one damaging attack, it carries no connect or head count, and it is omitted while unused.

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
### Common Carrier prototype contract

Capability 36 gates all roles before Welcome on Common Carrier (map 1010),
and on any authored source exposing registered `m10_ship_confirmation`,
`m10_cargo_deck`, `m10_passenger_deck` or `m10_command_deck` panels. A panel
alone never creates mission authority. M10 confirmation binds only the registered
ship control, not a generic lift panel. The sealed command window uses existing
ballistic inspection-glass solids; there is no exterior route or vacuum rule.
MapInfo carries strict `m10` with four ordered arrival objectives, a physical
`departure` Use target and `boarding` region, current `pilot` feet,
`companion_start`, and four canonical passenger markers. It cannot share
another mission map. MapInfo precedes corresponding mission facts; controller
steering stays blocked until fresh matching facts arrive. The static geometry
and actor markers cannot change within that map contract.

Mission id `common_carrier` uses `briefing`, `in_progress` and `departed`.
Its strict `m10` facts contain `completed`, `current` until departed, `transit`,
current `pilot`, the actual `passengers` subset and optional `carried_archive`.
Four ordered native encounter clears and actual arrival precede fresh physical
confirmation by every ready living participant aboard. Crew waiting and
optional difficulty challenges do not gate confirmation. Current Tern is the
ship's pilot even when historical transit facts are unknown; this is a current
appearance, never a fabricated recorded release or evacuation. Optional Edda
and Splice markers require actual Recorded arrivals. A secured cabinet does
not establish restored Orrin or continuity of a person.

Strict local save version 13 preserves immutable v12 `m09_outcome` and adds
`m10_transit` only with actual M10 entry and subsequent states. `Recorded`
arrivals equal the already-recorded actual released crew set. The original
`aboard_at_departure` subset remains unchanged. `HistoricalUnrecorded` retains
unknown old history, never empty invented arrivals or eligibility-derived
travel. This canonical locked M09-to-M10 promotion completes boarding during
the short transition, clears old-map personal claim IDs and refills Episode III
continues to three once. Actual HP, armor, body, selection, weapons, ammunition,
grenades and mines carry unchanged; retry anchors that M10 entry.

The exact strict v12 reader and v10/v11 and earlier readers retain byte
archives. Historical M10 stages, new transit fields, null future fields and
Repeater ownership refuse. Current M10 entry cannot forge a gun from completed
M09; only actual completed M10 equipment may carry the Repeater onward.
M10 completion retains pending `right_of_search` honestly. Full played combat,
actual Repeater source/cues and final ship presentation remain acceptance gates.
