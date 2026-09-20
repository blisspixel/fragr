extends Node

# Version 4 adds physical mission controls and shared departure state.
const GAMEPLAY_VERSION: int = 4

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

var equipment: Dictionary = {}
var mission_geometry: Dictionary = {}
var mission: Dictionary = {}

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
	equipment.clear()
	mission.clear()
	mission_geometry.clear()

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

func disconnect_from_server():
	if connection_state != WebSocketPeer.STATE_CLOSED:
		socket.close()
	connection_state = WebSocketPeer.STATE_CLOSED
	player_id = null
	equipment.clear()
	mission.clear()
	mission_geometry.clear()
	set_process(false)
	disconnected_from_server.emit()

func send_hello():
	var hello = {
		"type": "hello",
		"role": role,
		"name": player_name,
		"geometry_version": MapGeometry.VERSION,
		"gameplay_version": GAMEPLAY_VERSION
	}
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
		elif state == WebSocketPeer.STATE_CLOSED:
			player_id = null
			equipment.clear()
			mission.clear()
			mission_geometry.clear()
			print("Disconnected from server")
			set_process(false)
			disconnected_from_server.emit()
	
	while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
		var packet = socket.get_packet()
		var text = packet.get_string_from_utf8()
		_handle_message(text)

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
			equipment.clear()
			mission.clear()
			mission_geometry.clear()
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
			mission.clear()
			mission_geometry = data["mission"] if data.get("mission") is Dictionary else {}
			map_info_received.emit(data)
			mission_received.emit({})
		"mission":
			var problem: String = MissionState.validation_error(data, mission_geometry, mission)
			if not problem.is_empty():
				disconnect_from_server()
				server_error.emit(problem)
				return
			mission = data
			mission_received.emit(data["state"])
		"loadout":
			var problem: String = EquipmentState.validation_error(data, player_id, equipment)
			if not problem.is_empty():
				disconnect_from_server()
				server_error.emit(problem)
				return
			equipment = data
			loadout_received.emit(data)
		"error":
			if data.get("code") == "party_full":
				disconnect_from_server()
				server_error.emit(tr("MISSION_PARTY_FULL"))
			if data.get("code") in ["unsupported_geometry", "unsupported_gameplay"]:
				disconnect_from_server()
				server_error.emit("This server needs a newer client. Update to join.")

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
