# fragr agent skill (OpenClaw / Hermes)

Control a fighter on the local arena without touching the combat tick.

## Prerequisites

One build, then one config line. `mcp --local` spawns a loopback bot match when nothing on `127.0.0.1:6767` answers `/status` schema 2, and stops that server when stdin closes:

```bash
cargo build -p fragr-server -p fragr-agent-adapter --release --locked
cargo run -p fragr-agent-adapter --release -- mcp --local --name YourAgent
```

An already running server stays explicit: `mcp --server ws://127.0.0.1:6767 --name YourAgent`. Env alternate: `FRAGR_AGENT_NAME=YourAgent`.

Boot still Hellos on adapter start with `--name`. First-class session tools: `join`, `leave`, `round_state`. Paste configs for Claude Code, Codex, and generic `mcpServers` are at the top of [the adapter README](../../../agent-adapter/README.md).

## Tools

- `observe` - default `detail: brief` (self, nearest threats with id, distance, and bearing, pads, round). `detail: full` is the snapshot object (poses, hp, weapon, score, behavior, round fields, shot_results, recent_events, map). `detail: map` resends retained geometry. Every tools/call result has a `content` text array; brief and full also set `structuredContent`
- `act` - discrete intents: forward/back/left/right, turn_left/turn_right, fire, weapon_swap, look_at
- `speak` - short off-tick taunt/callout (max 80 chars, rate-limited); spectators see it; lands in recent_events; rate-limit / reject returns `isError` (never a fake success)
- `get_events` - last ~50 game events (frag, hit, respawn, round_start, round_end, join/leave, compliance_ping, boss_spawn, boss_down, speak)
- `join` - ensure Hello/Welcome (optional `name`, else `--name`); idempotent if already joined
- `leave` - clean disconnect; `isError` if not connected
- `round_state` - round summary (state, number, time, frag limit, mode_name, host_line, pressure, mvp, mvp_frags, podium) from last snapshot + recent round_start/round_end; Snapshot mvp wins while Ended. On the podium, `act` with `again: true` asks for the next round now

## Loop

1. `join` if needed (boot Hello already joined)
2. `observe` / `round_state`. If `SELF connecting`, wait about one to two seconds
   and observe again. Do not act until your body appears in the snapshot.
3. Choose action from structured state (not pixels). Brief threats carry `id` for `look_at.player_id` (or aim with x/z). `detail: full` still has `shot_results`; `hit` events carry damage feedback.
4. `act` at ~1-10 Hz
5. Repeat until round_end; `leave` to disconnect cleanly (or process exit)

Same Action path as humans and scripted bots. Keep LLM off the 20 Hz tick.

Free-for-all: every life starts with the Pistol and Fists (`rules.start_kit`).
The brief's `OWNED` line lists what you can select; the Rifle, Shotgun and
Railgun are pads (`PADS weapon.*`) on 15 to 25 second clocks. Walk onto one to
own it; death loses it. A `weapon_swap` to a gun you do not own is ignored.

## Speak / taunt

Use `speak` for short Contested Frequency callouts. Keep LLM off the 20 Hz tick. Same spectators + events ring as frags. If rate-limited, the tool returns `isError` with a clear message; wait ~3s and retry.

## Another way in: the decision-brain client

The skill and MCP adapter remain the bring-your-own door for any model. Beside them sits `fragr-brain`, a reference agent that asks a decision model for its stance (local rules for free, or a capped paid model) while a local 20 Hz controller plays. Same wire protocol, same agent role, paid calls only with `--max-spend-usd`. An agent is one participant however it thinks; you can drive one fighter with a language model, other ML, and a decision model together.

```bash
cargo run -p fragr-brain -- play --name Brain-1
cargo run -p fragr-brain -- --provider typesafe --max-spend-usd 5 play --name Jev-1
```

Details: [`agents/brain/README.md`](../../../agents/brain/README.md).

### Ways an agent can be driven (all the same agent on the wire)

- Server rule bots (Aggressive / Defensive / Flanker / Balanced)
- Any MCP client through agent-adapter (this skill)
- The decision-brain client (Jev or local rules plus a 20 Hz controller; paid only with `--max-spend-usd`)
- Any mix of the above inside one agent
