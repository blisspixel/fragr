extends SceneTree

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

const PLAYER: String = "00000000-0000-0000-0000-000000000001"
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_mission: " + message)

func _map() -> Dictionary:
	return {"type": "map_info", "map_id": 1001, "map_name": "Mission fixture", "geometry_version": 2, "half_extent": 8,
		"solids": [{"min_x": -4, "max_x": -2, "bottom": 0, "top": 1.2, "min_z": -3, "max_z": -2},
			{"min_x": 2, "max_x": 4, "bottom": 0, "top": 1.2, "min_z": 4, "max_z": 5}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "service_steel"], "decorations": [
			{"solid": 0, "face": "up", "center": [0, 0], "size": [1.8, 0.8], "kind": "terminal"},
			{"solid": 1, "face": "up", "center": [0, 0], "size": [1.8, 0.8], "kind": "lift_control"}]},
		"mission": {"id": "recall_notice", "record": {"decoration": 0, "approach": [-3, 0, -4]},
			"departure": {"decoration": 1, "approach": [3, 0, 3]}, "boarding": {"min": [-6, 0, 1.5], "max": [6, 0.5, 7]}}}

func _message() -> Dictionary:
	return {"type": "mission", "tick": 10, "state": {"id": "recall_notice", "attempt": 1, "phase": "find_transfer", "changed_at": 0,
		"party": [{"id": PLAYER, "name": "Visitor", "ready": true, "alive": true, "aboard": false}],
		"prompts": [{"player_id": PLAYER, "kind": "transfer_record"}]}}

func _run() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/decoration_points.json"))
	for expected: Dictionary in golden["points"]:
		var detail: Dictionary = {"face": expected["face"], "center": golden["center"]}
		var point: Vector3 = MapDecoration.placement(golden["host"], detail).origin
		_expect(point.is_equal_approx(Vector3(expected["point"][0], expected["point"][1], expected["point"][2])),
			"visible panel matches the physical use point: " + expected["face"])
	var info: Dictionary = _map()
	_expect(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "registered mission geometry is valid")
	for patch: Dictionary in [{"id": "unbuilt"}, {"boarding": null}, {"boarding": {"min": [0, 0, 0], "max": [0, 1, 1]}},
		{"record": {"decoration": 1, "approach": [0, 0, 0]}}, {"record": {"decoration": 0, "approach": [NAN, 0, 0]}},
		{"departure": {"decoration": 1, "approach": [3, 0, -3]}}, {"script": "anything"}]:
		var bad: Dictionary = info.duplicate(true)
		bad["mission"].merge(patch, true)
		_expect(not MissionState.map_error(bad).is_empty(), "invalid mission geometry rejected: " + str(patch))
	var message: Dictionary = _message()
	_expect(MissionState.validation_error(message, info["mission"]).is_empty(), "valid prompt accepted")
	for patch: Dictionary in [{"attempt": 0}, {"attempt": 1.5}, {"changed_at": 11}, {"phase": "invented"},
		{"party": [null]}, {"party": [{"id": PLAYER, "name": "bad\nname", "ready": true, "alive": true, "aboard": false}]},
		{"party": [{"id": PLAYER, "name": "Visitor", "ready": true, "alive": false, "aboard": true}]},
		{"prompts": [{"player_id": PLAYER, "kind": "lift_departure"}]}, {"phase": "departed"}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"].merge(patch, true)
		_expect(not MissionState.validation_error(bad, info["mission"]).is_empty(), "invalid mission state rejected: " + str(patch))
	var network: CaptureNetwork = CaptureNetwork.new()
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(message))
	_readiness(network, info)
	_expect(network.mission.get("state", {}).get("phase") == "find_transfer" \
		and network.mission.get("state", {}).get("prompts", []).size() == 1,
		"network retains validated late mission state: " + str(network.mission))
	var invalid: Dictionary = message.duplicate(true)
	invalid["state"]["attempt"] = 0
	network._handle_message(JSON.stringify(invalid))
	_expect(network.mission.is_empty() and network.mission_geometry.is_empty(), "rejected mission closes and clears")
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(message))
	var legacy: Dictionary = info.duplicate(true)
	legacy.erase("mission")
	network._handle_message(JSON.stringify(legacy))
	_expect(network.mission.is_empty() and network.mission_geometry.is_empty(), "map replacement clears old mission")
	await _input_and_hud(network, message["state"])
	network.free()
	if failures == 0:
		print("test_mission: PASS map/state boundary, late state, short use, pause ownership and localized HUD")
	quit(0 if failures == 0 else 1)

func _readiness(network: CaptureNetwork, info: Dictionary) -> void:
	var message: Dictionary = _message()
	message["state"]["phase"] = "briefing"
	message["state"]["party"][0]["ready"] = false
	message["state"]["prompts"] = []
	_expect(MissionState.validation_error(message, info["mission"]).is_empty(), "briefing permits unread members")
	for patch: Dictionary in [{"ready": "yes"}, {"aboard": true}]:
		var invalid: Dictionary = message.duplicate(true)
		invalid["state"]["party"][0].merge(patch, true)
		_expect(not MissionState.validation_error(invalid, info["mission"]).is_empty(), "readiness and boarding are strict")
	var forbidden: Dictionary = _message()
	forbidden["state"]["party"][0]["ready"] = false
	_expect(not MissionState.validation_error(forbidden, info["mission"]).is_empty(), "unread member cannot have a use prompt")
	network._handle_message(JSON.stringify(message))
	network.connection_state = WebSocketPeer.STATE_OPEN
	network.player_id = PLAYER
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.net_client = network
	manager.is_human_player = true
	manager.current_map_info = info
	manager._opening_finished = true
	manager._opening_release = true
	_expect(manager.controls_blocked(), "finishing locally does not unlock combat")
	manager._submit_mission_readiness()
	_expect(network.sent.is_empty(), "held dismissal waits for release")
	manager._opening_release = false
	# A queued pre-admission state must not consume the attempt's send slot.
	network.mission["state"]["party"] = []
	manager._submit_mission_readiness()
	_expect(manager._readiness_attempt_sent == 0, "missing own member cannot acknowledge")
	network._handle_message(JSON.stringify(message))
	manager._submit_mission_readiness()
	_expect(network.sent == [{"type": "mission_ready", "id": "recall_notice", "attempt": 1}], "exact mission attempt is acknowledged")
	manager._submit_mission_readiness()
	_expect(network.sent.size() == 1, "waiting does not spam readiness")
	message["state"]["party"][0]["ready"] = true
	network._handle_message(JSON.stringify(message))
	_expect(manager.controls_blocked(), "one ready member still waits for the shared phase")
	message["state"]["phase"] = "find_transfer"
	network._handle_message(JSON.stringify(message))
	_expect(not manager.controls_blocked(), "server activation releases gameplay")
	message["state"]["attempt"] = 2
	message["state"]["party"][0]["ready"] = false
	network._handle_message(JSON.stringify(message))
	manager._submit_mission_readiness()
	_expect(network.sent.back()["attempt"] == 2, "reader completion follows a party retry")
	network.player_id = null
	_expect(not network.send_mission_ready(), "spectators cannot submit readiness")
	manager.free()
	network.sent.clear()
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(_message()))

func _input_and_hud(network: CaptureNetwork, state: Dictionary) -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.net_client = network
	manager.is_human_player = true
	network.connection_state = WebSocketPeer.STATE_OPEN
	network.player_id = PLAYER
	var pawn: Node3D = Node3D.new()
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	camera.fp_mode = true
	camera.fp_target = pawn
	manager.camera = camera
	manager.players[PLAYER] = pawn
	manager.local_fp_pawn_id = PLAYER
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	manager._input(press)
	manager._input(release)
	manager._process(0.001)
	_expect(network.sent.back().get("interact", false), "short press survives transmission")
	manager._process(0.001)
	_expect(not network.sent.back().has("interact"), "released use is absent from the next action")
	manager._input(press)
	manager.role_transition = true
	manager._input(release)
	manager.role_transition = false
	manager.pending_interact = false
	manager._process(0.001)
	_expect(not network.sent.back().has("interact"), "release is observed while controls are blocked")
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	_expect(button.is_action_pressed("interact") and not button.is_action_pressed("fire"), "B uses without shooting")
	var display: MissionHud = MissionHud.new()
	root.add_child(display)
	display.apply(state, PLAYER)
	await process_frame
	_expect(display.visible and display._prompt.text.contains("READ") and display._copy.text.contains("Latch"), "local objective and physical prompt are readable")
	display.apply(state, "")
	_expect(display._prompt.text.is_empty(), "spectators see state without another player's use prompt")
	var arrival: Dictionary = state.duplicate(true)
	arrival["phase"] = "reach_lift"
	arrival["prompts"] = []
	display.apply(arrival, PLAYER)
	_expect(display._copy.text.contains("correction ward") and display._copy.text.contains("Visitor"), "record and awaited party member remain visible")
	var translated: Translation = Translation.new()
	translated.locale = "de"
	translated.add_message("MISSION_REACH_LIFT", "ERREICHE DEN GEFANGENENTRANSPORT")
	TranslationServer.add_translation(translated)
	TranslationServer.set_locale("de")
	await process_frame
	_expect(display._copy.text.contains("GEFANGENENTRANSPORT"), "runtime locale refreshes existing state")
	TranslationServer.set_locale("en")
	TranslationServer.remove_translation(translated)
	display.apply({}, "")
	_expect(not display.visible, "disconnect clears mission UI")
	display.free()
	manager.free()
	pawn.free()
	camera.free()
