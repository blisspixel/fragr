extends Node

# Version 9 understands M02 objective and gate state; version 8 added private
# participant records. Older servers remain playable.
const GAMEPLAY_VERSION: int = 9

signal connected_to_server
signal disconnected_from_server
signal server_error(message: String)
signal map_info_received(info: Dictionary)
signal snapshot_received(data)
signal event_received(data)
## Per-tick acknowledgement of the newest input the server applied to us.
signal ack_received(data)
signal loadout_received(data: Dictionary)
signal mission_received(data: Dictionary)
signal record_received(data: Dictionary)

var equipment: Dictionary = {}
var record: Dictionary = {}
var mission_geometry: Dictionary = {}
var mission: Dictionary = {}
var _mission_previous: Dictionary = {}

var socket = WebSocketPeer.new()
var connection_state = WebSocketPeer.STATE_CLOSED
var server_url = "ws://127.0.0.1:6767"

func _init():
	# Allow server URL override via environment variable for LAN/Tailscale
	var env_server = OS.get_environment("FRAGR_SERVER")
	if env_server != "":
		server_url = "ws://" + env_server if not env_server.begins_with("ws://") else env_server
		print("Using server from FRAGR_SERVER: ", server_url)

var role = "spectator"
var player_name = "Spectator"
var player_id = null
var _resume_token: String = ""
var _leaving: bool = false
var _resume_used: bool = false

signal session_resumed

func _ready():
	set_process(false)

func set_server_host(host: String) -> void:
	# Boot menu / solo path: host is host:port or full ws:// URL.
	var h = host.strip_edges()
	if h == "":
		return
	if h.begins_with("ws://") or h.begins_with("wss://"):
		server_url = h
	else:
		server_url = "ws://" + h
	print("Server host set to: ", server_url)

func connect_to_server(p_role: String = "spectator", p_name: String = "Player"):
	role = p_role
	player_name = p_name
	player_id = null
	_leaving = false
	_resume_used = false
	record.clear()
	equipment.clear()
	mission.clear()
	mission_geometry.clear()
	_mission_previous.clear()

	# Godot WebSocketPeer is not reliably reusable after close. Always start fresh
	# so J/L join-leave-reconnect cannot soft-prison on a dead peer.
	if connection_state != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()
	connection_state = WebSocketPeer.STATE_CLOSED

	var err = socket.connect_to_url(server_url)
	if err != OK:
		push_error("Failed to connect to server: " + str(err))
		return false

	connection_state = socket.get_ready_state()
	set_process(true)
	print("Connecting to ", server_url, " as ", role)
	return true

func leave_match() -> void:
	_leaving = true
	_resume_token = ""
	if connection_state == WebSocketPeer.STATE_OPEN:
		send_json({"type": "leave"})
	disconnect_from_server()

func disconnect_from_server():
	_leaving = true
	if connection_state != WebSocketPeer.STATE_CLOSED:
		socket.close()
	connection_state = WebSocketPeer.STATE_CLOSED
	player_id = null
	record.clear()
	equipment.clear()
	mission.clear()
	mission_geometry.clear()
	_mission_previous.clear()
	set_process(false)
	disconnected_from_server.emit()

func join_ticket(for_role: String, secret: String, exp: int) -> String:
	if for_role != "human" and for_role != "agent":
		return ""
	var key := secret.strip_edges().to_utf8_buffer()
	if key.size() < 16 or key.size() > 256:
		return ""
	var payload := "fragr-join-v1\n%d\n%s" % [exp, for_role]
	var ctx := HMACContext.new()
	if ctx.start(HashingContext.HASH_SHA256, key) != OK:
		return ""
	if ctx.update(payload.to_utf8_buffer()) != OK:
		return ""
	var mac := ctx.finish()
	if mac.is_empty():
		return ""
	return "v1.%d.%s.%s" % [exp, for_role, mac.hex_encode()]

func _try_resume() -> bool:
	if _leaving or _resume_used or _resume_token == "" or (role != "human" and role != "agent"):
		return false
	_resume_used = true
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(server_url)
	if err != OK:
		return false
	connection_state = socket.get_ready_state()
	set_process(true)
	return true

func send_hello():
	var hello = {
		"type": "hello",
		"role": role,
		"name": player_name,
		"geometry_version": MapGeometry.VERSION,
		"gameplay_version": GAMEPLAY_VERSION
	}
	var ticket := join_ticket(role, OS.get_environment("FRAGR_JOIN_SECRET"), int(Time.get_unix_time_from_system()) + 60)
	if ticket != "":
		hello["ticket"] = ticket
	if role == "human" or role == "agent":
		hello["resume"] = _resume_token
	send_json(hello)

func send_action(action: Dictionary):
	var msg = {
		"type": "action",
		"forward": action.get("forward", false),
		"back": action.get("back", false),
		"left": action.get("left", false),
		"right": action.get("right", false),
		"turn_left": action.get("turn_left", false),
		"turn_right": action.get("turn_right", false),
		"fire": action.get("fire", false),
		"jump": action.get("jump", false)
	}
	# This rebuilds the action field by field rather than sending the dictionary
	# it was given, which means a new field has to be added in two places. Jump
	# was set by the input code and silently dropped here for exactly that
	# reason. Anything added to the action must be added to this list too.
	# Same Action path as keyboard; optional weapon_swap when cycling.
	var swap = action.get("weapon_swap", null)
	if action.get("reload", false):
		msg["reload"] = true
	if action.get("interact", false):
		msg["interact"] = true
	if swap != null and str(swap) != "":
		msg["weapon_swap"] = str(swap)
	# Client-owned facing and the input number the server acknowledges. Both are
	# optional on the wire; agents and older clients send neither.
	if action.has("yaw"):
		msg["yaw"] = float(action["yaw"])
	if action.has("pitch"):
		msg["pitch"] = float(action["pitch"])
	if action.has("seq"):
		msg["seq"] = int(action["seq"])
	send_json(msg)

func send_mission_ready() -> bool:
	if connection_state != WebSocketPeer.STATE_OPEN or player_id == null or mission.is_empty():
		return false
	var state: Dictionary = mission["state"]
	if state["phase"] == "departed":
		return false
	for member: Dictionary in state["party"]:
		if member["id"] == player_id and not member["ready"]:
			send_json({"type": "mission_ready", "id": state["id"], "attempt": int(state["attempt"])})
			return true
	return false

func send_mission_continue() -> bool:
	if connection_state != WebSocketPeer.STATE_OPEN or player_id == null or mission.is_empty():
		return false
	var state: Dictionary = mission["state"]
	if not state.get("run") is Dictionary or state["run"]["status"] != "continue":
		return false
	for member: Dictionary in state["party"]:
		if member["id"] == player_id and not member["alive"]:
			send_json({"type": "mission_continue", "id": state["id"], "run_id": state["run"]["id"], "attempt": int(state["attempt"])})
			return true
	return false

func send_speak(text: String) -> void:
	var line = text.strip_edges()
	if line == "":
		return
	send_json({"type": "speak", "text": line})

func send_json(data: Dictionary):
	var json = JSON.stringify(data)
	socket.send_text(json)

func _process(_delta):
	socket.poll()
	var state = socket.get_ready_state()
	
	if state != connection_state:
		connection_state = state
		
		if state == WebSocketPeer.STATE_OPEN:
			print("Connected to server!")
			send_hello()
			connected_to_server.emit()
			if _resume_used:
				session_resumed.emit()
	
	# A rejection and close frame may arrive in the same poll. Drain the final
	# messages before retiring the session so the useful error is not discarded.
	while socket.get_available_packet_count() > 0:
		var packet = socket.get_packet()
		var text = packet.get_string_from_utf8()
		_handle_message(text)
		if not is_processing():
			return
	if state == WebSocketPeer.STATE_CLOSED:
		var reason: String = socket.get_close_reason()
		if _admission_error(reason):
			return
		# idle_timeout keeps the plain-drop resume path below; it only needs
		# its message shown, never a hard stop.
		if reason == "idle_timeout":
			server_error.emit(_close_message(reason))
		if _try_resume():
			return
		print("Disconnected from server")
		disconnect_from_server()

## Localized text for a stable close/error code, or "" when the code is not
## one of ours. Shared by the hard-stop path below and the idle_timeout drop,
## which shows the same message without blocking a resume attempt.
func _close_message(code: String) -> String:
	match code:
		"run_seat_closed": return tr("RUN_SEAT_CLOSED")
		"party_full": return tr("MISSION_PARTY_FULL")
		"unsupported_geometry", "unsupported_gameplay": return "This server needs a newer client. Update to join."
		"connection_limit": return "This server is not taking more connections."
		"address_limit": return "Too many connections from this address."
		"join_rejected": return "This server refused the join."
		"resume_rejected": return "The previous pawn is gone."
		"idle_timeout": return tr("NET_IDLE_TIMEOUT")
		"rate_limited": return tr("NET_RATE_LIMITED")
		"malformed": return tr("NET_MALFORMED")
		"address_banned": return tr("NET_ADDRESS_BANNED")
		"address_not_allowed": return tr("NET_ADDRESS_NOT_ALLOWED")
	return ""

## A hard stop: disconnects, shows the message, and never attempts to resume.
## idle_timeout is deliberately excluded here even though it has a message;
## a dropped-for-idleness pawn still gets its one automatic resume attempt,
## same as a plain drop. rate_limited, malformed, address_banned and
## address_not_allowed remove the pawn server-side, so an automatic resume
## would only be bounced; the client never makes that attempt.
func _admission_error(code: String) -> bool:
	if code == "idle_timeout":
		return false
	var message: String = _close_message(code)
	if message.is_empty():
		return false
	disconnect_from_server()
	server_error.emit(message)
	return true

func _handle_message(text: String):
	var json = JSON.new()
	var error = json.parse(text)
	if error != OK:
		disconnect_from_server()
		server_error.emit("The server sent an unreadable message. Connection closed.")
		return
	
	var data = json.data
	if not data is Dictionary:
		disconnect_from_server()
		server_error.emit("The server sent an invalid message. Connection closed.")
		return
	
	var msg_type = data.get("type", "")
	
	match msg_type:
		"welcome":
			if data.get("resume") is String and str(data["resume"]) != "":
				_resume_token = str(data["resume"])
			_resume_used = false
			equipment.clear()
			mission.clear()
			mission_geometry.clear()
			_mission_previous.clear()
			player_id = data.get("player_id")
			print("Welcome received! Role: ", data.get("role"), " Player ID: ", player_id, " Mode: ", data.get("mode_name", "Contested Frequency"), "/", data.get("playlist", "Arena Duel"))
		
		"map_info":
			var problem: String = MapGeometry.validation_error(data)
			if problem.is_empty():
				problem = MissionState.map_error(data)
			if problem != "":
				disconnect_from_server()
				server_error.emit(problem)
				return
			var geometry: Dictionary = MissionState.geometry_for(data)
			if geometry.is_empty() or geometry.get("id") != mission_geometry.get("id"):
				_mission_previous.clear()
			mission.clear()
			mission_geometry = geometry
			map_info_received.emit(data)
			mission_received.emit({})
		"mission":
			var problem: String = MissionState.validation_error(data, mission_geometry, _mission_previous)
			if not problem.is_empty():
				disconnect_from_server()
				server_error.emit(problem)
				return
			mission = data
			_mission_previous = data.duplicate(true)
			mission_received.emit(data["state"])
		"loadout":
			var problem: String = EquipmentState.validation_error(data, player_id, equipment)
			if not problem.is_empty():
				disconnect_from_server()
				server_error.emit(problem)
				return
			equipment = data
			loadout_received.emit(data)
		"record":
			var problem: String = PlayerRecord.validation_error(data, player_id, record)
			if not problem.is_empty():
				disconnect_from_server()
				server_error.emit(problem)
				return
			record = data.duplicate(true)
			record_received.emit(record)
		"error":
			if data.get("code") is String:
				_admission_error(data["code"])

		"snapshot":
			var problem: String = ActorState.validation_error(data)
			if not problem.is_empty():
				disconnect_from_server()
				server_error.emit(problem)
				return
			snapshot_received.emit(data)
		
		"ack":
			ack_received.emit(data)
		
		"event":
			event_received.emit(data)
			var event_type = data.get("event", "")
			if event_type == "frag":
				print("FRAG: ", data.get("killer"), " → ", data.get("victim"))
			elif event_type == "respawn":
				print("Respawn: ", data.get("player"))
