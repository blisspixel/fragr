//! MCP request dispatch for observation, controls, party readiness and session tools.
//! (and initialize / tools/list).
//! Kept free of stdin/WebSocket I/O so behavioral unit tests can cover the real tool paths.

use fragr_server::protocol::{self as protocol, Action, Speak};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
pub struct McpRequest {
    pub jsonrpc: String,
    pub id: Option<Value>,
    pub method: String,
    pub params: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct McpResponse {
    pub jsonrpc: String,
    pub id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<McpError>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct McpError {
    pub code: i32,
    pub message: String,
}

/// Mirrored speak cooldown (~3s at 20 Hz). Same as server SPEAK_COOLDOWN_TICKS.
pub const SPEAK_COOLDOWN_TICKS: u64 = 60;

/// In-memory MCP tool state mirrored from the WebSocket receive loop.
#[derive(Debug, Clone)]
pub struct ToolState {
    pub last_snapshot: Option<Value>,
    pub loadout: Option<protocol::LoadoutState>,
    pub record: Option<protocol::PlayerRecord>,
    pub mission: fragr_server::mission::MissionClient,
    pub recent_events: Vec<Value>,
    pub player_id: Option<Uuid>,
    /// Tick of last MCP speak that was accepted for send (rate-limit honesty).
    pub last_speak_tick: Option<u64>,
    /// True after Welcome / successful join; false after leave or before join.
    pub connected: bool,
    /// Display name from `--name` / `FRAGR_AGENT_NAME` (join reuses when args omit name).
    pub default_name: String,
    /// Name used for the current joined session.
    pub session_name: Option<String>,
    /// The arena's shape, from the server's MapInfo: bounds and the solids
    /// that block movement and shots. An agent needs it to tell a clear shot
    /// from a wall. Sent once on join, and again when the map changes.
    pub map: Option<Value>,
}

impl Default for ToolState {
    fn default() -> Self {
        Self {
            last_snapshot: None,
            loadout: None,
            record: None,
            mission: Default::default(),
            recent_events: Vec::new(),
            player_id: None,
            last_speak_tick: None,
            connected: false,
            default_name: "MCP Agent".to_string(),
            session_name: None,
            map: None,
        }
    }
}

/// Outcome of handling one MCP request.
/// `pending_action` is set when `act` validated; `pending_speak` when `speak` validated.
/// `pending_join` / `pending_leave` drive WebSocket Hello reconnect / clean disconnect in main.
#[derive(Debug)]
pub struct HandleOutcome {
    pub response: McpResponse,
    pub pending_action: Option<Action>,
    pub pending_mission_ready: Option<protocol::MissionReady>,
    pub pending_mission_continue: Option<protocol::MissionContinue>,
    pub pending_speak: Option<Speak>,
    pub pending_join: Option<String>,
    pub pending_leave: bool,
}

fn empty_outcome(response: McpResponse) -> HandleOutcome {
    HandleOutcome {
        response,
        pending_action: None,
        pending_mission_ready: None,
        pending_mission_continue: None,
        pending_speak: None,
        pending_join: None,
        pending_leave: false,
    }
}

const ACT_ALLOWED_KEYS: &[&str] = &[
    "forward",
    "back",
    "left",
    "right",
    "jump",
    "turn_left",
    "turn_right",
    "fire",
    "reload",
    "interact",
    "weapon_swap",
    "look_at",
];

const LOOK_AT_ALLOWED_KEYS: &[&str] = &["x", "y", "z", "player_id"];

const JOIN_ALLOWED_KEYS: &[&str] = &["name"];

fn validate_mission_ready(
    arguments: Value,
    state: &ToolState,
) -> Result<Option<protocol::MissionReady>, String> {
    let ready: protocol::MissionReady = serde_json::from_value(arguments)
        .map_err(|error| format!("schema error: invalid mission readiness: {error}"))?;
    let mission = state
        .mission
        .state
        .as_ref()
        .ok_or("No current mission; observe first")?;
    if !state.connected || state.player_id.is_none() {
        return Err("Mission readiness requires a connected participant".into());
    }
    if ready.id != mission.id
        || ready.attempt != mission.attempt
        || mission.phase == protocol::MissionPhase::Departed
    {
        return Err("Mission readiness does not match the active attempt; observe again".into());
    }
    let member = mission
        .party
        .iter()
        .find(|member| Some(member.id) == state.player_id)
        .ok_or("Not a member of this mission party")?;
    Ok((!member.ready).then_some(ready))
}

/// Validate MCP `act` arguments. Empty/missing args are OK (all defaults).
/// Unknown keys and bad weapon_swap values are schema errors (do not coerce).
pub fn validate_act_arguments(arguments: &Value) -> Result<Action, String> {
    if arguments.is_null() {
        return Ok(Action::default());
    }

    let obj = match arguments.as_object() {
        Some(o) => o,
        None => return Err("schema error: act arguments must be an object".to_string()),
    };

    let mut unknowns: Vec<&str> = obj
        .keys()
        .filter(|k| !ACT_ALLOWED_KEYS.contains(&k.as_str()))
        .map(|k| k.as_str())
        .collect();
    unknowns.sort();
    if !unknowns.is_empty() {
        let listed = unknowns
            .iter()
            .map(|k| format!("'{}'", k))
            .collect::<Vec<_>>()
            .join(", ");
        if unknowns.len() == 1 {
            return Err(format!("schema error: unknown act field {}", listed));
        }
        return Err(format!("schema error: unknown act fields {}", listed));
    }

    let weapon_swap = if let Some(v) = obj.get("weapon_swap") {
        if v.is_null() {
            None
        } else {
            let s = v.as_str().ok_or_else(|| {
                "schema error: weapon_swap must be a string (fists|tack|flechette|rail|scatter)"
                    .to_string()
            })?;
            match s {
                "fists" => Some(protocol::WeaponType::Fists),
                "tack" => Some(protocol::WeaponType::Tack),
                "flechette" => Some(protocol::WeaponType::Flechette),
                "rail" => Some(protocol::WeaponType::Rail),
                "scatter" => Some(protocol::WeaponType::Scatter),
                other => {
                    return Err(format!(
                    "schema error: weapon_swap must be fists|tack|flechette|rail|scatter, got '{}'",
                    other
                ))
                }
            }
        }
    } else {
        None
    };

    let bool_field =
        |key: &str| -> bool { obj.get(key).and_then(|v| v.as_bool()).unwrap_or(false) };

    let look_at = if let Some(v) = obj.get("look_at") {
        if v.is_null() {
            None
        } else {
            let look_obj = v
                .as_object()
                .ok_or_else(|| "schema error: look_at must be an object".to_string())?;
            let mut unknowns: Vec<&str> = look_obj
                .keys()
                .filter(|k| !LOOK_AT_ALLOWED_KEYS.contains(&k.as_str()))
                .map(|k| k.as_str())
                .collect();
            unknowns.sort();
            if !unknowns.is_empty() {
                let listed = unknowns
                    .iter()
                    .map(|k| format!("'{}'", k))
                    .collect::<Vec<_>>()
                    .join(", ");
                return Err(format!("schema error: unknown look_at field(s) {}", listed));
            }

            let num_field = |key: &str| -> Result<Option<f32>, String> {
                match look_obj.get(key) {
                    None => Ok(None),
                    Some(val) if val.is_null() => Ok(None),
                    Some(val) => val
                        .as_f64()
                        .map(|n| n as f32)
                        .filter(|n| n.is_finite())
                        .map(Some)
                        .ok_or_else(|| {
                            format!("schema error: look_at.{} must be a finite f32 number", key)
                        }),
                }
            };
            let player_id = match look_obj.get("player_id") {
                None => None,
                Some(val) if val.is_null() => None,
                Some(val) => {
                    let s = val.as_str().ok_or_else(|| {
                        "schema error: look_at.player_id must be a uuid string".to_string()
                    })?;
                    Some(Uuid::parse_str(s).map_err(|_| {
                        format!(
                            "schema error: look_at.player_id must be a valid uuid, got '{}'",
                            s
                        )
                    })?)
                }
            };
            let x = num_field("x")?;
            let y = num_field("y")?;
            let z = num_field("z")?;
            if player_id.is_none() && (x.is_none() || z.is_none()) {
                return Err("schema error: look_at requires player_id or both x and z".to_string());
            }
            Some(protocol::LookAt { x, y, z, player_id })
        }
    } else {
        None
    };

    Ok(Action {
        forward: bool_field("forward"),
        back: bool_field("back"),
        left: bool_field("left"),
        right: bool_field("right"),
        turn_left: bool_field("turn_left"),
        turn_right: bool_field("turn_right"),
        fire: bool_field("fire"),
        reload: match obj.get("reload") {
            None => false,
            Some(value) => value
                .as_bool()
                .ok_or("schema error: reload must be a boolean")?,
        },
        jump: bool_field("jump"),
        interact: match obj.get("interact") {
            None => false,
            Some(value) => value
                .as_bool()
                .ok_or("schema error: interact must be a boolean")?,
        },
        weapon_swap,
        look_at,
        // MCP agents aim with look_at and the turn bits; they do not own a
        // facing and do not predict, so absolute angles and seq are unset.
        yaw: None,
        pitch: None,
        seq: None,
    })
}

pub const SPEAK_MAX_CHARS: usize = 80;

/// Validate MCP `speak` arguments. Returns a Speak payload or a clear schema error.
pub fn validate_speak_arguments(arguments: &Value) -> Result<Speak, String> {
    let obj = match arguments.as_object() {
        Some(o) => o,
        None => return Err("schema error: speak arguments must be an object".to_string()),
    };

    let mut unknowns: Vec<&str> = obj
        .keys()
        .filter(|k| k.as_str() != "text")
        .map(|k| k.as_str())
        .collect();
    unknowns.sort();
    if !unknowns.is_empty() {
        let listed = unknowns
            .iter()
            .map(|k| format!("'{}'", k))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!("schema error: unknown speak field(s) {}", listed));
    }

    let text_val = obj
        .get("text")
        .ok_or_else(|| "schema error: speak requires 'text'".to_string())?;
    let raw = text_val
        .as_str()
        .ok_or_else(|| "schema error: speak.text must be a string".to_string())?;
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("schema error: speak.text must be non-empty".to_string());
    }
    if trimmed.chars().count() > SPEAK_MAX_CHARS {
        return Err(format!(
            "schema error: speak.text max length is {} characters",
            SPEAK_MAX_CHARS
        ));
    }
    if trimmed.chars().any(|c| c.is_control()) {
        return Err("schema error: speak.text must not contain control characters".to_string());
    }

    Ok(Speak {
        text: trimmed.to_string(),
    })
}

/// Validate MCP `join` arguments. Optional `name`; otherwise reuse default_name.
pub fn validate_join_arguments(arguments: &Value, default_name: &str) -> Result<String, String> {
    if arguments.is_null() {
        return Ok(default_name.to_string());
    }

    let obj = match arguments.as_object() {
        Some(o) => o,
        None => return Err("schema error: join arguments must be an object".to_string()),
    };

    let mut unknowns: Vec<&str> = obj
        .keys()
        .filter(|k| !JOIN_ALLOWED_KEYS.contains(&k.as_str()))
        .map(|k| k.as_str())
        .collect();
    unknowns.sort();
    if !unknowns.is_empty() {
        let listed = unknowns
            .iter()
            .map(|k| format!("'{}'", k))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!("schema error: unknown join field(s) {}", listed));
    }

    match obj.get("name") {
        None => Ok(default_name.to_string()),
        Some(v) if v.is_null() => Ok(default_name.to_string()),
        Some(v) => {
            let s = v
                .as_str()
                .ok_or_else(|| "schema error: join.name must be a string".to_string())?;
            let trimmed = s.trim();
            if trimmed.is_empty() {
                return Err("schema error: join.name must be non-empty".to_string());
            }
            Ok(trimmed.to_string())
        }
    }
}

/// Validate MCP `leave` / `round_state` arguments: empty object or null only.
pub fn validate_no_arg_tool(tool: &str, arguments: &Value) -> Result<(), String> {
    if arguments.is_null() {
        return Ok(());
    }
    let obj = match arguments.as_object() {
        Some(o) => o,
        None => {
            return Err(format!(
                "schema error: {} arguments must be an object",
                tool
            ))
        }
    };
    if !obj.is_empty() {
        let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
        keys.sort();
        let listed = keys
            .iter()
            .map(|k| format!("'{}'", k))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!(
            "schema error: {} takes no fields; unknown field(s) {}",
            tool, listed
        ));
    }
    Ok(())
}

pub fn build_observe_result(state: &ToolState) -> Value {
    match state.last_snapshot.as_ref() {
        Some(snapshot) => {
            let mut observation = snapshot.clone();
            if let Some(obj) = observation.as_object_mut() {
                obj.insert(
                    "recent_events".to_string(),
                    serde_json::json!(state.recent_events.clone()),
                );
                obj.insert(
                    "self_player_id".to_string(),
                    serde_json::json!(state.player_id.map(|id| id.to_string())),
                );
                if let Some(map) = state.map.as_ref() {
                    obj.insert("map".to_string(), map.clone());
                }
                if let Some(loadout) = state.loadout.as_ref() {
                    obj.insert("loadout".into(), serde_json::json!(loadout));
                }
                if let Some(record) = state.record.as_ref() {
                    obj.insert("record".into(), serde_json::json!(record));
                }
                if let Some(mission) = state.mission.state.as_ref() {
                    obj.insert("mission".into(), serde_json::json!(mission));
                }
            }
            observation
        }
        None => serde_json::json!({
            "status": "connecting",
            "message": "Waiting for first snapshot from server",
            "self_player_id": state.player_id.map(|id| id.to_string()),
            "recent_events": state.recent_events.clone()
        }),
    }
}

pub fn build_get_events_result(state: &mut ToolState, clear: bool) -> Value {
    let events_copy = state.recent_events.clone();
    if clear {
        state.recent_events.clear();
    }
    serde_json::json!({
        "content": [{
            "type": "text",
            "text": format!("Recent events: {}", serde_json::to_string_pretty(&events_copy).unwrap())
        }]
    })
}

fn snap_field(snap: Option<&Value>, key: &str) -> Value {
    snap.and_then(|s| s.get(key))
        .cloned()
        .unwrap_or(Value::Null)
}

/// Round summary from last snapshot + recent round_start / round_end (no observe scrape).
pub fn build_round_state_result(state: &ToolState) -> Value {
    let snap = state.last_snapshot.as_ref();
    let mut round_number = Value::Null;
    let mut last_round_start = Value::Null;
    let mut last_round_end = Value::Null;

    for ev in state.recent_events.iter().rev() {
        match ev.get("event").and_then(|e| e.as_str()) {
            Some("round_start") if last_round_start.is_null() => {
                last_round_start = ev.clone();
                if let Some(n) = ev.get("round_number") {
                    round_number = n.clone();
                }
            }
            Some("round_end") if last_round_end.is_null() => {
                last_round_end = ev.clone();
            }
            _ => {}
        }
    }

    // Prefer live snapshot mode/host/pressure; fall back to last round_start fields.
    let mode_name = match snap_field(snap, "mode_name") {
        Value::Null => last_round_start
            .get("mode_name")
            .cloned()
            .unwrap_or(Value::Null),
        other => other,
    };
    let host_line = match snap_field(snap, "host_line") {
        Value::Null => last_round_end
            .get("host_line")
            .cloned()
            .or_else(|| last_round_start.get("host_line").cloned())
            .unwrap_or(Value::Null),
        other => other,
    };
    let frag_limit = match snap_field(snap, "frag_limit") {
        Value::Null => last_round_start
            .get("frag_limit")
            .cloned()
            .unwrap_or(Value::Null),
        other => other,
    };
    // Prefer Snapshot MVP while Ended (mid-join); fall back to buffered round_end.
    let mvp = match snap_field(snap, "mvp") {
        Value::Null => last_round_end.get("mvp").cloned().unwrap_or(Value::Null),
        other => other,
    };
    let mvp_frags = match snap_field(snap, "mvp_frags") {
        Value::Null => last_round_end
            .get("mvp_frags")
            .cloned()
            .unwrap_or(Value::Null),
        other => other,
    };

    let map_id = match snap_field(snap, "map_id") {
        Value::Null => Value::from(crate::protocol::default_map_id()),
        other => other,
    };
    let map_name = match snap_field(snap, "map_name") {
        Value::Null => Value::from(crate::protocol::default_map_name()),
        other => other,
    };

    serde_json::json!({
        "connected": state.connected,
        "self_player_id": state.player_id.map(|id| id.to_string()),
        "session_name": state.session_name,
        "round_state": snap_field(snap, "round_state"),
        "round_number": round_number,
        "round_time_left": snap_field(snap, "round_time_left"),
        "frag_limit": frag_limit,
        "mode_name": mode_name,
        "playlist": snap_field(snap, "playlist"),
        "host_line": host_line,
        "pressure": snap_field(snap, "pressure"),
        "mvp": mvp,
        "mvp_frags": mvp_frags,
        "map_id": map_id,
        "map_name": map_name,
        "last_round_start": last_round_start,
        "last_round_end": last_round_end
    })
}

fn tools_list_result() -> Value {
    serde_json::json!({
        "tools": [
            {
                "name": "observe",
                "description": "Get current game state observation including self_player_id, recent events, shot_results (hit-confirm), and pickups (mid-map weapon / health / armor pads; pickup events carry kind). Returns connecting state until first snapshot arrives.",
                "inputSchema": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            {
                "name": "act",
                "description": "Send ordinary input. Movement and fire are held until changed. Reload and weapon_swap are consumed once; later omitted fields do not erase a pending request. Weapon selection requires ownership. look_at aims in three dimensions.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "forward": {"type": "boolean", "default": false, "description": "Move forward"},
                        "back": {"type": "boolean", "default": false, "description": "Move backward"},
                        "left": {"type": "boolean", "default": false, "description": "Strafe left"},
                        "right": {"type": "boolean", "default": false, "description": "Strafe right"},
                        "turn_left": {"type": "boolean", "default": false, "description": "Turn left"},
                        "turn_right": {"type": "boolean", "default": false, "description": "Turn right"},
                        "fire": {"type": "boolean", "default": false, "description": "Fire weapon"},
                        "jump": {"type": "boolean", "default": false, "description": "Jump. A grounded fighter leaves the floor; holding it does not fly"},
                        "weapon_swap": {"type": "string", "enum": ["fists", "tack", "flechette", "rail", "scatter"], "description": "Select an owned weapon"},
                        "reload": {"type": "boolean", "description": "Request one reload of the selected weapon"},
                        "interact": {"type": "boolean", "description": "Press to use an aimed mission panel when observe supplies your prompt. Release before another press."},
                        "look_at": {
                            "type": "object",
                            "description": "Aim at player_id (preferred) or world x/z with optional y. Missing y aims horizontally.",
                            "properties": {
                                "player_id": {"type": "string", "description": "Target player UUID"},
                                "x": {"type": "number", "description": "World X target"},
                                "y": {"type": "number", "description": "World Y target, optional"},
                                "z": {"type": "number", "description": "World Z target"}
                            },
                            "additionalProperties": false
                        }
                    },
                    "required": []
                }
            },
            {
                "name": "get_events",
                "description": "Get recent game events (player joins/leaves, frags, killstreaks, respawns, round start/end, speaks). Includes last 50 events.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "clear": {"type": "boolean", "default": false, "description": "Clear events after retrieving"}
                    },
                    "required": []
                }
            },
            {
                "name": "speak",
                "description": "Send a short off-tick taunt/callout (rate-limited, max 80 chars). Not on the combat Action tick. Spectators see it; it appears in recent_events/get_events.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "text": {"type": "string", "description": "Callout text (trimmed, max 80 chars, no control characters)"}
                    },
                    "required": ["text"],
                    "additionalProperties": false
                }
            },
            {
                "name": "join",
                "description": "Join the arena as an agent (Hello/Welcome). Optional name reuses --name / FRAGR_AGENT_NAME when omitted. Idempotent if already joined.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string", "description": "Display name for Hello (optional; defaults to adapter --name)"}
                    },
                    "required": [],
                    "additionalProperties": false
                }
            },
            {
                "name": "leave",
                "description": "Leave the arena with a clean WebSocket disconnect. Returns isError if not connected.",
                "inputSchema": {
                    "type": "object",
                    "properties": {},
                    "required": [],
                    "additionalProperties": false
                }
            },
            {
                "name": "mission_ready",
                "description": "Finish or skip the campaign briefing for this participant. Read the mission id and attempt from observe first. Readiness cannot be withdrawn; initial combat waits for the party, late arrivals do not pause it. Observe confirms server acceptance.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string", "enum": ["recall_notice"]},
                        "attempt": {"type": "integer", "minimum": 1, "maximum": u32::MAX}
                    },
                    "required": ["id", "attempt"],
                    "additionalProperties": false
                }
            },
            {
                "name": "mission_continue",
                "description": "Spend one remaining continue in an explicit solo run. Restarts the current mission with entry equipment. Read id, run.id and attempt from observe. Only the dead run owner can continue; observe confirms acceptance.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string", "enum": ["recall_notice"]},
                        "run_id": {"type": "string", "format": "uuid"},
                        "attempt": {"type": "integer", "minimum": 1, "maximum": u32::MAX}
                    },
                    "required": ["id", "run_id", "attempt"],
                    "additionalProperties": false
                }
            },
            {
                "name": "round_state",
                "description": "Current round summary (state, number, time left, frag limit, mode_name, host_line, pressure) from last snapshot plus recent round_start/round_end. Prefer this over scraping observe.",
                "inputSchema": {
                    "type": "object",
                    "properties": {},
                    "required": [],
                    "additionalProperties": false
                }
            }
        ]
    })
}

fn snapshot_tick(state: &ToolState) -> u64 {
    state
        .last_snapshot
        .as_ref()
        .and_then(|s| s.get("tick"))
        .and_then(|t| t.as_u64())
        .unwrap_or(0)
}

fn speak_rate_limited(state: &ToolState, tick: u64) -> bool {
    match state.last_speak_tick {
        Some(last) => tick.saturating_sub(last) < SPEAK_COOLDOWN_TICKS,
        None => false,
    }
}

fn tool_error_result(message: &str) -> Value {
    serde_json::json!({
        "content": [{
            "type": "text",
            "text": message
        }],
        "isError": true
    })
}

fn tool_ok_text(message: &str) -> Value {
    serde_json::json!({
        "content": [{
            "type": "text",
            "text": message
        }]
    })
}

/// Dispatch one JSON-RPC MCP request against tool state.
pub fn handle_mcp_request(request: McpRequest, state: &mut ToolState) -> HandleOutcome {
    let id = request.id.clone().unwrap_or(Value::Null);

    match request.method.as_str() {
        "initialize" => empty_outcome(McpResponse {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(serde_json::json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "fragr-agent-adapter",
                    "version": "0.1.0"
                }
            })),
            error: None,
        }),

        "tools/list" => empty_outcome(McpResponse {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(tools_list_result()),
            error: None,
        }),

        "tools/call" => {
            let tool_name = request
                .params
                .as_ref()
                .and_then(|p| p.get("name"))
                .and_then(|n| n.as_str())
                .unwrap_or("");

            let mut pending_action = None;
            let mut pending_mission_ready = None;
            let mut pending_mission_continue = None;
            let mut pending_speak = None;
            let mut pending_join = None;
            let mut pending_leave = false;
            let result = match tool_name {
                "observe" => build_observe_result(state),

                "mission_continue" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);
                    match serde_json::from_value::<protocol::MissionContinue>(arguments) {
                        Ok(request) if state.connected && state.mission.continuation(state.player_id) == Some(request) => {
                            pending_mission_continue = Some(request);
                            tool_ok_text("Continue submitted; observe to confirm server acceptance")
                        }
                        _ => tool_error_result("Continue requires the current run id and attempt for its dead participant; observe first"),
                    }
                }

                "mission_ready" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|params| params.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);
                    match validate_mission_ready(arguments, state) {
                        Ok(Some(ready)) => {
                            pending_mission_ready = Some(ready);
                            tool_ok_text(
                                "Readiness submitted; observe to confirm server acceptance",
                            )
                        }
                        Ok(None) => tool_ok_text("Already ready for this mission attempt"),
                        Err(error) => tool_error_result(&error),
                    }
                }

                "act" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);

                    match validate_act_arguments(&arguments) {
                        Ok(action) => {
                            pending_action = Some(action);
                            serde_json::json!({
                                "content": [{
                                    "type": "text",
                                    "text": "Action sent successfully"
                                }]
                            })
                        }
                        Err(msg) => serde_json::json!({
                            "content": [{
                                "type": "text",
                                "text": msg
                            }],
                            "isError": true
                        }),
                    }
                }

                "speak" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);

                    match validate_speak_arguments(&arguments) {
                        Ok(speak) => {
                            if state.player_id.is_none() {
                                tool_error_result(
                                    "speak rejected: not connected as a player (spectators cannot speak)",
                                )
                            } else {
                                let tick = snapshot_tick(state);
                                if speak_rate_limited(state, tick) {
                                    tool_error_result(
                                        "speak rate limited; try again in a few seconds",
                                    )
                                } else {
                                    state.last_speak_tick = Some(tick);
                                    pending_speak = Some(speak);
                                    tool_ok_text("Speak sent successfully")
                                }
                            }
                        }
                        Err(msg) => tool_error_result(&msg),
                    }
                }

                "join" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);

                    match validate_join_arguments(&arguments, &state.default_name) {
                        Ok(join_name) => {
                            if state.connected {
                                let who = state
                                    .session_name
                                    .clone()
                                    .unwrap_or_else(|| join_name.clone());
                                tool_ok_text(&format!("Already joined as '{}'", who))
                            } else {
                                pending_join = Some(join_name.clone());
                                tool_ok_text(&format!("Joining as '{}'; Hello pending", join_name))
                            }
                        }
                        Err(msg) => tool_error_result(&msg),
                    }
                }

                "leave" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);

                    match validate_no_arg_tool("leave", &arguments) {
                        Ok(()) => {
                            if !state.connected {
                                tool_error_result("leave rejected: not connected")
                            } else {
                                state.connected = false;
                                state.player_id = None;
                                state.session_name = None;
                                state.last_snapshot = None;
                                state.loadout = None;
                                state.record = None;
                                state.last_speak_tick = None;
                                pending_leave = true;
                                tool_ok_text("Left arena; disconnecting")
                            }
                        }
                        Err(msg) => tool_error_result(&msg),
                    }
                }

                "round_state" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);

                    match validate_no_arg_tool("round_state", &arguments) {
                        Ok(()) => build_round_state_result(state),
                        Err(msg) => tool_error_result(&msg),
                    }
                }

                "get_events" => {
                    let arguments = request
                        .params
                        .as_ref()
                        .and_then(|p| p.get("arguments"))
                        .cloned()
                        .unwrap_or(Value::Null);

                    let should_clear = arguments
                        .get("clear")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);

                    build_get_events_result(state, should_clear)
                }

                _ => serde_json::json!({
                    "content": [{
                        "type": "text",
                        "text": format!("Unknown tool: {}", tool_name)
                    }]
                }),
            };

            HandleOutcome {
                response: McpResponse {
                    jsonrpc: "2.0".to_string(),
                    id,
                    result: Some(result),
                    error: None,
                },
                pending_action,
                pending_mission_ready,
                pending_mission_continue,
                pending_speak,
                pending_join,
                pending_leave,
            }
        }

        _ => empty_outcome(McpResponse {
            jsonrpc: "2.0".to_string(),
            id,
            result: None,
            error: Some(McpError {
                code: -32601,
                message: format!("Method not found: {}", request.method),
            }),
        }),
    }
}

/// Buffer a parsed or soft-prison raw event into recent_events (cap 50).
pub fn push_recent_event(state: &mut ToolState, event_value: Value) {
    state.recent_events.push(event_value);
    if state.recent_events.len() > 50 {
        state.recent_events.remove(0);
    }
}

/// Apply an inbound server JSON text frame into tool state (snapshot / event / soft prison).
pub fn ingest_server_text(state: &mut ToolState, text: &str) -> Result<(), &'static str> {
    if text.len() > 1_000_000 {
        return Err("server message exceeds size limit");
    }

    match serde_json::from_str::<protocol::ServerMessage>(text) {
        Ok(protocol::ServerMessage::Mission {
            tick,
            state: mission,
        }) => {
            state.mission.observe(tick, mission)?;
        }
        Ok(protocol::ServerMessage::Loadout(loadout)) => {
            loadout.validate_for(state.player_id, state.loadout.as_ref())?;
            state.loadout = Some(loadout);
        }
        Ok(protocol::ServerMessage::Record(record)) => {
            record.validate_for(state.player_id, state.record.as_ref())?;
            state.record = Some(record);
        }
        Ok(protocol::ServerMessage::Snapshot(snapshot)) => {
            if let Ok(snapshot_value) = serde_json::to_value(snapshot) {
                state.last_snapshot = Some(snapshot_value);
            }
        }
        // Acks go only to predicting clients; the adapter ignores them.
        Ok(protocol::ServerMessage::Ack { .. }) => {}
        Ok(protocol::ServerMessage::MapInfo {
            map_id,
            map_name,
            half_extent,
            solids,
            geometry_version,
            presentation,
            mission,
        }) => {
            fragr_server::protocol::validate_map_geometry(half_extent, &solids, geometry_version)?;
            protocol::validate_map_presentation(presentation.as_ref(), &solids)?;
            state.mission.replace_map(
                mission.as_ref(),
                half_extent,
                &solids,
                presentation.as_ref(),
            )?;
            state.map = Some(serde_json::json!({
                "map_id": map_id,
                "map_name": map_name,
                "half_extent": half_extent,
                "solids": solids,
                "geometry_version": geometry_version,
                "presentation": presentation,
                "mission": mission,
            }));
        }
        Ok(protocol::ServerMessage::Event(event)) => {
            if let Ok(event_value) = serde_json::to_value(event) {
                push_recent_event(state, event_value);
            }
        }
        Ok(protocol::ServerMessage::Welcome { player_id, .. }) => {
            state.loadout = None;
            state.record = None;
            state.mission = Default::default();
            state.player_id = player_id;
            state.connected = true;
        }
        Ok(protocol::ServerMessage::Error { code, .. }) => {
            if code == "party_full" {
                return Err("mission party is full");
            }
            if code == "unsupported_gameplay" {
                return Err("server requires a newer gameplay format");
            }
            if code == "unsupported_geometry" {
                return Err("server requires a newer geometry format");
            }
            // Unicast speak rejection; MCP speak path already mirrors cooldown as isError.
        }
        Err(_) => {
            let raw = serde_json::from_str::<Value>(text).map_err(|_| "invalid server JSON")?;
            if !raw.is_object() {
                return Err("invalid server message object");
            }
            if raw.get("type").and_then(|v| v.as_str()) == Some("map_info") {
                return Err("invalid map geometry message");
            }
            if raw.get("type").and_then(|v| v.as_str()) == Some("loadout") {
                return Err("invalid loadout message");
            }
            if raw.get("type").and_then(|v| v.as_str()) == Some("record") {
                return Err("invalid record message");
            }
            if raw.get("type").and_then(|v| v.as_str()) == Some("mission") {
                return Err("invalid mission message");
            }
            if raw.get("type").and_then(|v| v.as_str()) == Some("event") {
                push_recent_event(state, raw);
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod mcp_tests {
    use super::*;

    #[test]
    fn participant_record_is_validated_and_shared_with_observe() {
        let record: protocol::PlayerRecord =
            serde_json::from_str(include_str!("../../client/golden/player_record.json")).unwrap();
        let mut state = ToolState {
            player_id: Some(record.player_id),
            connected: true,
            last_snapshot: Some(serde_json::json!({"tick": record.tick, "players": []})),
            ..Default::default()
        };
        let message =
            serde_json::to_string(&protocol::ServerMessage::Record(record.clone())).unwrap();
        ingest_server_text(&mut state, &message).unwrap();
        ingest_server_text(&mut state, &message).unwrap();
        assert_eq!(
            build_observe_result(&state)["record"],
            serde_json::to_value(&record).unwrap()
        );
        let mut invalid = record.clone();
        invalid.total.weapons[0].kills = 10;
        assert!(ingest_server_text(
            &mut state,
            &serde_json::to_string(&protocol::ServerMessage::Record(invalid)).unwrap()
        )
        .is_err());
        assert_eq!(state.record, Some(record));
        assert!(ingest_server_text(&mut state, r#"{"type":"record","version":99}"#).is_err());
        ingest_server_text(
            &mut state,
            r#"{"type":"welcome","role":"spectator","player_id":null}"#,
        )
        .unwrap();
        assert!(state.record.is_none());
        assert!(
            ingest_server_text(&mut state, &message).is_err(),
            "spectators cannot receive participant records"
        );
    }

    #[test]
    fn continue_tool_requires_current_dead_owner_and_server_confirmation() {
        let map = fragr_server::maps::AuthoredSource::Mission(protocol::MissionId::RecallNotice)
            .load()
            .unwrap();
        let mut sim = fragr_server::sim::GameState::with_authored_map(map);
        sim.enable_campaign_run().unwrap();
        let id = Uuid::new_v4();
        sim.add_player(id, "Runner".into(), protocol::Role::Agent);
        sim.acknowledge_mission(
            id,
            protocol::MissionReady {
                id: protocol::MissionId::RecallNotice,
                attempt: 1,
            },
        );
        let mut state = ToolState {
            player_id: Some(id),
            connected: true,
            ..Default::default()
        };
        ingest_server_text(&mut state, &serde_json::to_string(&sim.map_info()).unwrap()).unwrap();
        sim.players[0].hp = 0;
        sim.tick(0.05);
        ingest_server_text(
            &mut state,
            &serde_json::to_string(&sim.mission_message().unwrap()).unwrap(),
        )
        .unwrap();
        let args = serde_json::to_value(state.mission.continuation(Some(id)).unwrap()).unwrap();
        let call = |args| McpRequest {
            jsonrpc: "2.0".into(),
            id: Some(1.into()),
            method: "tools/call".into(),
            params: Some(serde_json::json!({"name":"mission_continue", "arguments":args})),
        };
        for patch in [
            serde_json::json!({"attempt":2}),
            serde_json::json!({"run_id":Uuid::nil()}),
            serde_json::json!({"extra":true}),
        ] {
            let mut invalid = args.clone();
            for (key, value) in patch.as_object().unwrap() {
                invalid[key] = value.clone();
            }
            let result = handle_mcp_request(call(invalid), &mut state);
            assert!(result.pending_mission_continue.is_none());
            assert_eq!(result.response.result.unwrap()["isError"], true);
        }
        for (connected, player_id) in [
            (false, Some(id)),
            (true, None),
            (true, Some(Uuid::new_v4())),
        ] {
            let mut denied = state.clone();
            denied.connected = connected;
            denied.player_id = player_id;
            assert!(handle_mcp_request(call(args.clone()), &mut denied)
                .pending_mission_continue
                .is_none());
        }
        let request = handle_mcp_request(call(args.clone()), &mut state)
            .pending_mission_continue
            .unwrap();
        assert_eq!(
            state.mission.state.as_ref().unwrap().run.unwrap().continues,
            3
        );
        assert!(sim.continue_mission(id, request));
        assert!(!sim.continue_mission(id, request));
        ingest_server_text(
            &mut state,
            &serde_json::to_string(&protocol::ServerMessage::Snapshot(sim.snapshot())).unwrap(),
        )
        .unwrap();
        ingest_server_text(
            &mut state,
            &serde_json::to_string(&sim.mission_message().unwrap()).unwrap(),
        )
        .unwrap();
        assert_eq!(
            build_observe_result(&state)["mission"]["run"]["continues"],
            2
        );
        assert!(handle_mcp_request(call(args), &mut state)
            .pending_mission_continue
            .is_none());
    }

    #[test]
    fn mission_observe_and_use_share_the_server_contract() {
        let map = fragr_server::maps::AuthoredMap::load(
            &std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../server/maps/m01-recall-notice.json"),
        )
        .unwrap();
        let mut sim = fragr_server::sim::GameState::with_authored_map(map);
        sim.set_campaign_difficulty(fragr_server::protocol::CampaignDifficulty::Assisted)
            .unwrap();
        let id = Uuid::from_u128(1);
        sim.add_player(id, "Partner".into(), protocol::Role::Agent);
        let mut state = ToolState {
            player_id: Some(id),
            connected: true,
            ..Default::default()
        };
        ingest_server_text(&mut state, &serde_json::to_string(&sim.map_info()).unwrap()).unwrap();
        ingest_server_text(
            &mut state,
            &serde_json::to_string(&sim.mission_message().unwrap()).unwrap(),
        )
        .unwrap();
        ingest_server_text(
            &mut state,
            &serde_json::to_string(&protocol::ServerMessage::Snapshot(sim.snapshot())).unwrap(),
        )
        .unwrap();
        let observed = build_observe_result(&state);
        assert_eq!(observed["mission"]["phase"], "briefing");
        assert_eq!(
            observed["mission"]["rules"],
            serde_json::json!({"difficulty":"assisted","revision":1})
        );
        assert_eq!(observed["mission"]["party"][0]["ready"], false);
        assert_eq!(observed["mission"]["party"][0]["id"], id.to_string());
        assert_eq!(observed["map"]["mission"]["id"], "recall_notice");
        let request = |arguments| McpRequest {
            jsonrpc: "2.0".into(),
            id: Some(serde_json::json!(1)),
            method: "tools/call".into(),
            params: Some(serde_json::json!({"name":"mission_ready","arguments":arguments})),
        };
        let arguments = serde_json::json!({"id":"recall_notice","attempt":1});
        for invalid in [
            Value::Null,
            serde_json::json!({}),
            serde_json::json!({"id":"unknown","attempt":1}),
            serde_json::json!({"id":"recall_notice","attempt":0}),
            serde_json::json!({"id":"recall_notice","attempt":2}),
            serde_json::json!({"id":"recall_notice","attempt":"1"}),
            serde_json::json!({"id":"recall_notice","attempt":1,"ready":false}),
        ] {
            let result = handle_mcp_request(request(invalid), &mut state);
            assert!(result.pending_mission_ready.is_none());
            assert_eq!(result.response.result.unwrap()["isError"], true);
        }
        for (connected, player) in [
            (false, Some(id)),
            (true, None),
            (true, Some(Uuid::new_v4())),
        ] {
            let mut rejected = state.clone();
            rejected.connected = connected;
            rejected.player_id = player;
            let result = handle_mcp_request(request(arguments.clone()), &mut rejected);
            assert!(result.pending_mission_ready.is_none());
            assert_eq!(result.response.result.unwrap()["isError"], true);
        }
        let outcome = handle_mcp_request(request(arguments.clone()), &mut state);
        assert!(
            !state.mission.state.as_ref().unwrap().party[0].ready,
            "sending is not acceptance"
        );
        assert!(sim.acknowledge_mission(id, outcome.pending_mission_ready.unwrap()));
        ingest_server_text(
            &mut state,
            &serde_json::to_string(&sim.mission_message().unwrap()).unwrap(),
        )
        .unwrap();
        assert_eq!(
            build_observe_result(&state)["mission"]["phase"],
            "find_transfer"
        );
        let repeat = handle_mcp_request(request(arguments), &mut state);
        assert!(repeat.pending_mission_ready.is_none());
        assert_ne!(repeat.response.result.unwrap()["isError"], true);
        assert!(
            validate_act_arguments(&serde_json::json!({"interact":true}))
                .unwrap()
                .interact
        );
        assert!(
            !validate_act_arguments(&serde_json::json!({"interact":false}))
                .unwrap()
                .interact
        );
        for value in [
            serde_json::json!("true"),
            serde_json::json!(1),
            serde_json::Value::Null,
        ] {
            assert!(validate_act_arguments(&serde_json::json!({"interact":value})).is_err());
        }
        assert!(ingest_server_text(&mut state, r#"{"type":"mission","state":[]}"#).is_err());
        let legacy = fragr_server::sim::GameState::new().map_info();
        ingest_server_text(&mut state, &serde_json::to_string(&legacy).unwrap()).unwrap();
        assert!(state.mission.state.is_none());
        assert!(ingest_server_text(
            &mut state,
            &serde_json::to_string(&sim.mission_message().unwrap()).unwrap()
        )
        .is_err());
    }

    #[test]
    fn map_versions_are_validated_before_observation_is_replaced() {
        let mut state = ToolState::default();
        let mut map = serde_json::json!({"type":"map_info", "map_id":67, "map_name":"Balcony",
        "half_extent":12.0, "geometry_version":2, "solids":[
            {"min_x":-2.0,"max_x":2.0,"min_z":-2.0,"max_z":2.0,"bottom":2.4,"top":3.0}
        ]});
        ingest_server_text(&mut state, &map.to_string()).unwrap();
        assert_eq!(state.map.as_ref().unwrap()["geometry_version"], 2);
        assert_eq!(
            state.map.as_ref().unwrap()["solids"][0]["bottom"],
            serde_json::json!(2.4_f32)
        );
        map["presentation"] = serde_json::json!({"ground":"concrete","solids":["enamel"]});
        ingest_server_text(&mut state, &map.to_string()).unwrap();
        assert_eq!(
            state.map.as_ref().unwrap()["presentation"]["solids"][0],
            "enamel"
        );
        let panel = serde_json::json!({"solid":0,"face":"north","center":[0.0,0.0],
            "size":[1.0,0.5],"kind":"property_sign"});
        map["presentation"]["decorations"] = serde_json::json!([panel]);
        ingest_server_text(&mut state, &map.to_string()).unwrap();
        assert_eq!(
            state.map.as_ref().unwrap()["presentation"]["decorations"][0],
            panel
        );
        let previous = state.map.clone();
        for change in [
            serde_json::json!({"solid":1}),
            serde_json::json!({"size":[1,1]}),
            serde_json::json!({"kind":"res://untrusted"}),
        ] {
            let mut invalid = map.clone();
            invalid["presentation"]["decorations"][0]
                .as_object_mut()
                .unwrap()
                .extend(change.as_object().unwrap().clone());
            assert!(ingest_server_text(&mut state, &invalid.to_string()).is_err());
            assert_eq!(state.map, previous);
        }
        let mut invalid = map.clone();
        invalid["presentation"]["solids"] = serde_json::json!([]);
        assert!(ingest_server_text(&mut state, &invalid.to_string()).is_err());
        assert_eq!(state.map, previous);
        for version in [0, 1, 3] {
            map["geometry_version"] = version.into();
            assert!(ingest_server_text(&mut state, &map.to_string()).is_err());
            assert_eq!(state.map, previous);
        }
        assert!(ingest_server_text(&mut state, r#"{"type":"map_info","solids":"bad"}"#).is_err());
        assert!(ingest_server_text(
            &mut state,
            r#"{"type":"error","code":"unsupported_geometry","message":"Update"}"#
        )
        .is_err());
        assert!(ingest_server_text(&mut state, &"x".repeat(1_000_001)).is_err());
        for malformed in ["{broken", "[]", "null"] {
            assert!(ingest_server_text(&mut state, malformed).is_err());
            assert_eq!(state.map, previous);
        }
    }

    fn req(method: &str, params: Option<Value>) -> McpRequest {
        McpRequest {
            jsonrpc: "2.0".into(),
            id: Some(Value::from(1)),
            method: method.into(),
            params,
        }
    }

    #[test]
    fn private_equipment_reaches_observation_and_invalid_updates_preserve_it() {
        use fragr_server::inventory::Inventory;
        use protocol::{EquipmentPolicy, WeaponType};
        let id = Uuid::nil();
        let mut state = ToolState {
            player_id: Some(id),
            last_snapshot: Some(serde_json::json!({"tick":10})),
            ..Default::default()
        };
        let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
        inventory.grant_weapon(WeaponType::Tack);
        inventory.try_fire(WeaponType::Tack);
        inventory.begin_reload(WeaponType::Tack, 10);
        let loadout = inventory.state(id, WeaponType::Tack, 10).unwrap();
        let wire = serde_json::to_value(protocol::ServerMessage::Loadout(loadout.clone())).unwrap();
        ingest_server_text(&mut state, &wire.to_string()).unwrap();
        assert_eq!(build_observe_result(&state)["loadout"]["selected"], "tack");
        assert_eq!(
            build_observe_result(&state)["loadout"]["reload"]["complete_at"],
            28
        );
        for patch in [
            serde_json::json!({"player_id":Uuid::new_v4()}),
            serde_json::json!({"tick":9}),
            serde_json::json!({"weapons":[]}),
            serde_json::json!({"reload":{"weapon":"tack","complete_at":29}}),
            serde_json::json!({"personal_claims":["bad/path"]}),
            serde_json::json!({"reserves":"bad"}),
        ] {
            let mut invalid = wire.clone();
            invalid
                .as_object_mut()
                .unwrap()
                .extend(patch.as_object().unwrap().clone());
            assert!(ingest_server_text(&mut state, &invalid.to_string()).is_err());
            assert_eq!(state.loadout, Some(loadout.clone()));
        }
        for weapon in ["fists", "tack", "flechette", "scatter", "rail"] {
            let action =
                validate_act_arguments(&serde_json::json!({"weapon_swap":weapon,"reload":true}))
                    .unwrap();
            assert_eq!(action.weapon_swap.unwrap().name().to_lowercase(), weapon);
            assert!(action.reload);
        }
        for reload in [
            serde_json::json!(1),
            serde_json::json!("true"),
            serde_json::json!([]),
        ] {
            assert!(validate_act_arguments(&serde_json::json!({"reload":reload})).is_err());
        }
        assert!(ingest_server_text(
            &mut state,
            r#"{"type":"error","code":"unsupported_gameplay","message":"Update"}"#
        )
        .is_err());
    }

    #[test]
    fn observe_connecting_until_snapshot() {
        let mut state = ToolState {
            player_id: Some(Uuid::nil()),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req("tools/call", Some(serde_json::json!({"name":"observe"}))),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["status"], "connecting");
        assert!(result["self_player_id"].is_string());
    }

    #[test]
    fn observe_includes_snapshot_events_and_self_id() {
        let mut state = ToolState {
            last_snapshot: Some(serde_json::json!({"tick": 3, "players": []})),
            recent_events: vec![serde_json::json!({"event":"frag"})],
            player_id: Some(Uuid::nil()),
            last_speak_tick: None,
            ..Default::default()
        };
        let out = handle_mcp_request(
            req("tools/call", Some(serde_json::json!({"name":"observe"}))),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["tick"], 3);
        assert_eq!(result["recent_events"].as_array().unwrap().len(), 1);
        assert!(result["self_player_id"].is_string());
    }

    #[test]
    fn act_valid_sets_pending_action() {
        let mut state = ToolState::default();
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "act",
                    "arguments": {"forward": true, "fire": true, "weapon_swap": "rail"}
                })),
            ),
            &mut state,
        );
        let action = out.pending_action.expect("pending");
        assert!(action.forward && action.fire);
        assert_eq!(action.weapon_swap, Some(protocol::WeaponType::Rail));
        let text = out.response.result.unwrap()["content"][0]["text"]
            .as_str()
            .unwrap()
            .to_string();
        assert!(text.contains("Action sent successfully"));
    }

    #[test]
    fn act_schema_error_sets_is_error() {
        let mut state = ToolState::default();
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "act",
                    "arguments": {"laser": true}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_action.is_none());
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("schema error"));
    }

    #[test]
    fn get_events_lists_and_optional_clear() {
        let mut state = ToolState {
            recent_events: vec![
                serde_json::json!({"event":"player_joined","player":"A"}),
                serde_json::json!({"event":"round_start","round_number":1}),
            ],
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"get_events","arguments":{"clear":false}})),
            ),
            &mut state,
        );
        let text = out.response.result.unwrap()["content"][0]["text"]
            .as_str()
            .unwrap()
            .to_string();
        assert!(text.contains("player_joined"));
        assert_eq!(state.recent_events.len(), 2);

        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"get_events","arguments":{"clear":true}})),
            ),
            &mut state,
        );
        assert!(out.response.result.is_some());
        assert!(state.recent_events.is_empty());
    }

    #[test]
    fn initialize_and_tools_list_and_unknown_method() {
        let mut state = ToolState::default();
        let init = handle_mcp_request(req("initialize", None), &mut state);
        assert!(init.response.result.unwrap()["serverInfo"]["name"]
            .as_str()
            .unwrap()
            .contains("fragr-agent-adapter"));

        let list = handle_mcp_request(req("tools/list", None), &mut state);
        let list_result = list.response.result.unwrap();
        let tools = list_result["tools"].as_array().unwrap();
        let names: Vec<_> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();
        assert!(names.contains(&"observe"));
        assert!(names.contains(&"act"));
        assert!(names.contains(&"get_events"));

        let bad = handle_mcp_request(req("nope", None), &mut state);
        assert_eq!(bad.response.error.unwrap().code, -32601);
    }

    #[test]
    fn ingest_snapshot_event_and_soft_prison() {
        let mut state = ToolState::default();
        ingest_server_text(
            &mut state,
            r#"{"type":"snapshot","tick":9,"players":[],"round_state":"active","round_time_left":100,"frag_limit":10}"#,
        ).unwrap();
        assert_eq!(state.last_snapshot.as_ref().unwrap()["tick"], 9);

        ingest_server_text(
            &mut state,
            r#"{"type":"event","event":"player_joined","player":"X","role":"agent","round_number":1,"player_count":3}"#,
        ).unwrap();
        assert_eq!(state.recent_events.len(), 1);

        // Soft prison: unknown event shape still buffers when type=event.
        ingest_server_text(
            &mut state,
            r#"{"type":"event","event":"future_thing","payload":1}"#,
        )
        .unwrap();
        assert_eq!(state.recent_events.len(), 2);
    }

    #[test]
    fn push_recent_event_rotates_at_50() {
        let mut state = ToolState::default();
        for i in 0..55 {
            push_recent_event(&mut state, serde_json::json!({"i": i}));
        }
        assert_eq!(state.recent_events.len(), 50);
        assert_eq!(state.recent_events[0]["i"], 5);
    }

    #[test]
    fn hello_name_resolution_used_in_client_message() {
        // Behavioral: Hello payload carries the resolved --name (not the default).
        let name = "ArenaFox";
        let hello = protocol::ClientMessage::Hello {
            gameplay_version: fragr_server::protocol::GAMEPLAY_VERSION,
            geometry_version: fragr_server::protocol::GEOMETRY_VERSION,
            role: protocol::Role::Agent,
            name: name.to_string(),
        };
        let json = serde_json::to_string(&hello).unwrap();
        assert!(json.contains("ArenaFox"));
        assert!(!json.contains("MCP Agent"));
    }

    #[test]
    fn look_at_player_id_ok() {
        let id = Uuid::new_v4();
        let args = serde_json::json!({"look_at": {"player_id": id.to_string()}, "fire": true});
        let action = validate_act_arguments(&args).expect("valid look_at");
        assert!(action.fire);
        let look = action.look_at.expect("look_at");
        assert_eq!(look.player_id, Some(id));
    }

    #[test]
    fn look_at_xz_ok() {
        let args = serde_json::json!({"look_at": {"x": 1.5, "z": -2.0}});
        let action = validate_act_arguments(&args).expect("valid look_at xz");
        let look = action.look_at.expect("look_at");
        assert_eq!(look.x, Some(1.5));
        assert_eq!(look.z, Some(-2.0));
        assert_eq!(look.y, None);
    }

    #[test]
    fn look_at_accepts_world_height_and_rejects_float_overflow() {
        let args = serde_json::json!({"look_at":{"x":1.0,"y":4.5,"z":2.0}});
        let action = validate_act_arguments(&args).unwrap();
        assert_eq!(action.look_at.unwrap().y, Some(4.5));
        for bad in [serde_json::json!(1e100), serde_json::json!("high")] {
            let args = serde_json::json!({"look_at":{"x":1.0,"y":bad,"z":2.0}});
            assert!(validate_act_arguments(&args).is_err());
        }
    }

    #[test]
    fn look_at_unknown_field_errors() {
        let args = serde_json::json!({"look_at": {"x": 1.0, "z": 2.0, "laser": true}});
        let err = validate_act_arguments(&args).unwrap_err();
        assert!(err.contains("look_at"), "{err}");
        assert!(err.contains("laser") || err.contains("unknown"), "{err}");
    }

    #[test]
    fn look_at_incomplete_xz_errors() {
        let args = serde_json::json!({"look_at": {"x": 1.0}});
        let err = validate_act_arguments(&args).unwrap_err();
        assert!(err.contains("look_at"), "{err}");
    }

    #[test]
    fn speak_valid_sets_pending_speak() {
        let mut state = ToolState {
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({"tick": 10})),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": "  nice scrap  "}
                })),
            ),
            &mut state,
        );
        let speak = out.pending_speak.expect("pending speak");
        assert_eq!(speak.text, "nice scrap");
        assert!(out.pending_action.is_none());
        let result = out.response.result.unwrap();
        assert!(result.get("isError").is_none() || result["isError"] == false);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("Speak sent successfully"));
        assert_eq!(state.last_speak_tick, Some(10));
    }

    #[test]
    fn speak_rate_limited_sets_is_error() {
        let mut state = ToolState {
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({"tick": 100})),
            last_speak_tick: Some(90),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": "again"}
                })),
            ),
            &mut state,
        );
        assert!(
            out.pending_speak.is_none(),
            "rate-limited must not queue speak"
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        let text = result["content"][0]["text"].as_str().unwrap();
        assert!(text.contains("rate limited"), "{text}");
        assert!(!text.contains("Speak sent successfully"), "{text}");
    }

    #[test]
    fn speak_after_cooldown_ok() {
        let mut state = ToolState {
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({"tick": 200})),
            last_speak_tick: Some(100),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": "back"}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_speak.is_some());
        let result = out.response.result.unwrap();
        assert!(result.get("isError").is_none() || result["isError"] == false);
    }

    #[test]
    fn speak_overlong_sets_is_error() {
        let mut state = ToolState {
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({"tick": 1})),
            ..Default::default()
        };
        let long = "x".repeat(SPEAK_MAX_CHARS + 1);
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": long}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_speak.is_none());
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(state.last_speak_tick.is_none());
    }

    #[test]
    fn speak_spectator_sets_is_error() {
        let mut state = ToolState {
            player_id: None,
            last_snapshot: Some(serde_json::json!({"tick": 1})),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": "hi"}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_speak.is_none());
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(
            result["content"][0]["text"]
                .as_str()
                .unwrap()
                .contains("spectator")
                || result["content"][0]["text"]
                    .as_str()
                    .unwrap()
                    .contains("not connected")
        );
    }

    #[test]
    fn speak_schema_errors() {
        let mut state = ToolState::default();
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": "hi", "laser": true}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_speak.is_none());
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("schema error"));

        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": ""}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_speak.is_none());

        let long = "x".repeat(SPEAK_MAX_CHARS + 1);
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "speak",
                    "arguments": {"text": long}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_speak.is_none());
    }

    #[test]
    fn tools_list_includes_speak() {
        let mut state = ToolState::default();
        let list = handle_mcp_request(req("tools/list", None), &mut state);
        let result = list.response.result.unwrap();
        let tools = result["tools"].as_array().unwrap();
        let names: Vec<_> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();
        assert!(names.contains(&"speak"), "names={:?}", names);
    }

    #[test]
    fn tools_list_includes_join_leave_round_state() {
        let mut state = ToolState::default();
        let list = handle_mcp_request(req("tools/list", None), &mut state);
        let result = list.response.result.unwrap();
        let tools = result["tools"].as_array().unwrap();
        let names: Vec<_> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();
        assert!(names.contains(&"join"), "names={:?}", names);
        assert!(names.contains(&"leave"), "names={:?}", names);
        assert!(names.contains(&"round_state"), "names={:?}", names);
    }

    #[test]
    fn join_idempotent_when_connected() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            session_name: Some("ArenaFox".into()),
            default_name: "ArenaFox".into(),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"join","arguments":{}})),
            ),
            &mut state,
        );
        assert!(out.pending_join.is_none());
        assert!(!out.pending_leave);
        let result = out.response.result.unwrap();
        assert!(result.get("isError").is_none() || result["isError"] == false);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("Already joined"));
    }

    #[test]
    fn join_pending_when_not_connected() {
        let mut state = ToolState {
            default_name: "MCP Agent".into(),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "join",
                    "arguments": {"name": "  ScrapFox  "}
                })),
            ),
            &mut state,
        );
        assert_eq!(out.pending_join.as_deref(), Some("ScrapFox"));
        let result = out.response.result.unwrap();
        assert!(result.get("isError").is_none() || result["isError"] == false);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("Joining as 'ScrapFox'"));
    }

    #[test]
    fn join_reuses_default_name() {
        let mut state = ToolState {
            default_name: "FromFlag".into(),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"join","arguments":{}})),
            ),
            &mut state,
        );
        assert_eq!(out.pending_join.as_deref(), Some("FromFlag"));
    }

    #[test]
    fn join_schema_unknown_field_errors() {
        let mut state = ToolState::default();
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "join",
                    "arguments": {"name": "A", "laser": true}
                })),
            ),
            &mut state,
        );
        assert!(out.pending_join.is_none());
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("schema error"));
    }

    #[test]
    fn leave_when_connected_sets_pending_leave() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            session_name: Some("ArenaFox".into()),
            last_snapshot: Some(serde_json::json!({"tick": 1})),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"leave","arguments":{}})),
            ),
            &mut state,
        );
        assert!(out.pending_leave);
        assert!(!state.connected);
        assert!(state.player_id.is_none());
        assert!(state.last_snapshot.is_none());
        let result = out.response.result.unwrap();
        assert!(result.get("isError").is_none() || result["isError"] == false);
    }

    #[test]
    fn leave_when_not_connected_is_error() {
        let mut state = ToolState::default();
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"leave","arguments":{}})),
            ),
            &mut state,
        );
        assert!(!out.pending_leave);
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("not connected"));
    }

    #[test]
    fn leave_schema_unknown_field_errors() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "leave",
                    "arguments": {"force": true}
                })),
            ),
            &mut state,
        );
        assert!(!out.pending_leave);
        assert!(state.connected);
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("schema error"));
    }

    #[test]
    fn round_state_from_snapshot_and_events() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({
                "tick": 42,
                "round_state": "Active",
                "round_time_left": 90,
                "frag_limit": 10,
                "mode_name": "Contested Frequency",
                "playlist": "Arena Duel",
                "host_line": "HOST: LIVE.",
                "pressure": "compliance"
            })),
            recent_events: vec![
                serde_json::json!({
                    "event": "round_start",
                    "round_number": 3,
                    "frag_limit": 10,
                    "mode_name": "Contested Frequency",
                    "host_line": "HOST: START."
                }),
                serde_json::json!({
                    "event": "frag",
                    "killer": "A",
                    "victim": "B"
                }),
            ],
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"round_state","arguments":{}})),
            ),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["round_state"], "Active");
        assert_eq!(result["round_number"], 3);
        assert_eq!(result["round_time_left"], 90);
        assert_eq!(result["frag_limit"], 10);
        assert_eq!(result["mode_name"], "Contested Frequency");
        assert_eq!(result["host_line"], "HOST: LIVE.");
        assert_eq!(result["pressure"], "compliance");
        assert_eq!(result["connected"], true);
        assert_eq!(result["last_round_start"]["round_number"], 3);
        assert!(result["mvp"].is_null());
        assert!(result["mvp_frags"].is_null());
        // Soft: map fields always present (defaults when snapshot omits them).
        assert_eq!(result["map_id"], crate::protocol::default_map_id());
        assert_eq!(result["map_name"], crate::protocol::default_map_name());
    }

    #[test]
    fn round_state_surfaces_map_from_snapshot() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({
                "tick": 7,
                "round_state": "Warmup",
                "map_id": 2,
                "map_name": "Compliance Yard"
            })),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"round_state","arguments":{}})),
            ),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["round_state"], "Warmup");
        assert_eq!(result["map_id"], 2);
        assert_eq!(result["map_name"], "Compliance Yard");
    }

    #[test]
    fn round_state_surfaces_warmup_host_drama() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({
                "tick": 3,
                "round_state": "Warmup",
                "round_time_left": 2,
                "map_id": 1,
                "map_name": "Arena Duel",
                "host_line": "HOST: CONTESTED FREQUENCY. ARENA DUEL TUNES IN. DEAD AIR DAN ON THE SCRAP. 2."
            })),
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"round_state","arguments":{}})),
            ),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["round_state"], "Warmup");
        assert_eq!(result["round_time_left"], 2);
        assert!(result["host_line"]
            .as_str()
            .unwrap()
            .contains("CONTESTED FREQUENCY"));
        assert!(result["host_line"].as_str().unwrap().contains("ARENA DUEL"));
        assert!(result["host_line"]
            .as_str()
            .unwrap()
            .contains("ON THE SCRAP"));
    }

    #[test]
    fn round_state_surfaces_mvp_from_round_end() {
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({
                "tick": 99,
                "round_state": "Ended",
                "host_line": "HOST: ROUND MVP. Rusher WITH 10 FRAGS. CONTINUANCE DENIES THE PODIUM."
            })),
            recent_events: vec![serde_json::json!({
                "event": "round_end",
                "winner": "Rusher",
                "reason": "Frag limit reached",
                "mvp": "Rusher",
                "mvp_frags": 10,
                "host_line": "HOST: ROUND MVP. Rusher WITH 10 FRAGS. CONTINUANCE DENIES THE PODIUM.",
                "final_scores": [{"name": "Rusher", "score": 10}]
            })],
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"round_state","arguments":{}})),
            ),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["round_state"], "Ended");
        assert_eq!(result["mvp"], "Rusher");
        assert_eq!(result["mvp_frags"], 10);
        assert!(result["host_line"].as_str().unwrap().contains("ROUND MVP"));
        assert_eq!(result["last_round_end"]["mvp"], "Rusher");
        assert_eq!(result["last_round_end"]["mvp_frags"], 10);
    }

    #[test]
    fn round_state_prefers_snapshot_mvp_for_mid_join() {
        // Mid-join during Ended: Snapshot carries structured mvp; no buffered round_end.
        let mut state = ToolState {
            connected: true,
            player_id: Some(Uuid::nil()),
            last_snapshot: Some(serde_json::json!({
                "tick": 120,
                "round_state": "Ended",
                "mvp": "Anchor",
                "mvp_frags": 7,
                "host_line": "HOST: ROUND MVP. Anchor WITH 7 FRAGS. CONTINUANCE DENIES THE PODIUM."
            })),
            recent_events: vec![],
            ..Default::default()
        };
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({"name":"round_state","arguments":{}})),
            ),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["round_state"], "Ended");
        assert_eq!(result["mvp"], "Anchor");
        assert_eq!(result["mvp_frags"], 7);
        assert!(result["host_line"].as_str().unwrap().contains("Anchor"));
        assert!(result["last_round_end"].is_null());
    }

    #[test]
    fn round_state_schema_unknown_field_errors() {
        let mut state = ToolState::default();
        let out = handle_mcp_request(
            req(
                "tools/call",
                Some(serde_json::json!({
                    "name": "round_state",
                    "arguments": {"extra": 1}
                })),
            ),
            &mut state,
        );
        let result = out.response.result.unwrap();
        assert_eq!(result["isError"], true);
        assert!(result["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("schema error"));
    }

    #[test]
    fn ingest_welcome_sets_connected() {
        let mut state = ToolState::default();
        assert!(!state.connected);
        ingest_server_text(
            &mut state,
            r#"{"type":"welcome","player_id":"00000000-0000-0000-0000-000000000000","role":"agent","mode_name":"Contested Frequency","playlist":"Arena Duel"}"#,
        ).unwrap();
        assert!(state.connected);
        assert!(state.player_id.is_some());
    }
}
