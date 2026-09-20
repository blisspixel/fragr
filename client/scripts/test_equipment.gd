extends SceneTree

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_equipment: " + message)

func _state() -> Dictionary:
	return {"type": "loadout", "player_id": "self", "tick": 20, "selected": "tack",
		"weapons": [{"weapon": "fists", "magazine": null}, {"weapon": "tack", "magazine": 0}],
		"reserves": [{"pool": "tacks", "rounds": 36}, {"pool": "darts", "rounds": 0}, {"pool": "cores", "rounds": 0}],
		"reload": null, "personal_claims": ["bay_tack"], "dry_fire_count": 1}

func _run() -> void:
	var state: Dictionary = _state()
	_check(EquipmentState.validation_error(state, "self").is_empty(), "valid private state is accepted")
	_check(not EquipmentState.validation_error(state, "other").is_empty(), "another participant's ammunition is rejected")
	_check(not EquipmentState.validation_error(state, null).is_empty(), "spectators cannot receive private ammunition")
	_check(EquipmentState.cycle(state, "tack", 1) == "fists" and EquipmentState.cycle(state, "fists", -1) == "tack", "cycling wraps only owned weapons")
	for patch: Dictionary in [{"tick": -1}, {"tick": 1.5}, {"tick": NAN}, {"tick": "20"}, {"selected": "rail"},
		{"weapons": []}, {"weapons": [{"weapon": []}]}, {"weapons": [{"weapon": "fists", "magazine": 1}]},
		{"reserves": []}, {"reserves": [{"pool": []}, {}, {}]}, {"personal_claims": ["../bay"]},
		{"personal_claims": ["bay_tack", "bay_tack"]}, {"dry_fire_count": -1}, {"reload": []},
		{"reload": {"weapon": "fists", "complete_at": 21}}, {"reload": {"weapon": "tack", "complete_at": 39}}]:
		var invalid: Dictionary = state.duplicate(true)
		invalid.merge(patch, true)
		_check(not EquipmentState.validation_error(invalid, "self").is_empty(), "invalid state cannot enter presentation: " + str(patch))
	var reload: Dictionary = state.duplicate(true)
	reload["reload"] = {"weapon": "tack", "complete_at": 38}
	_check(EquipmentState.validation_error(reload, "self", state).is_empty(), "bounded reload accepted")
	_check(is_equal_approx(EquipmentState.reload_progress(reload, 29), 0.5), "reload progress follows authoritative ticks")
	var earlier: Dictionary = state.duplicate(true)
	earlier["tick"] = 19
	_check(not EquipmentState.validation_error(earlier, "self", state).is_empty(), "stale equipment cannot rewind the HUD")
	var network: CaptureNetwork = CaptureNetwork.new()
	network.player_id = "self"
	network._handle_message(JSON.stringify(state))
	_check(network.equipment.get("selected") == "tack" and EquipmentState.magazine(network.equipment, "tack") == 0 \
		and EquipmentState.reserve(network.equipment, "tack") == 36 and network.equipment["personal_claims"] == ["bay_tack"], "network publishes validated inventory")
	network._handle_message(JSON.stringify(earlier))
	_check(network.equipment.is_empty() and network.player_id == null, "invalid private state closes and clears the session")
	network.send_hello()
	_check(network.sent[0]["gameplay_version"] == 2 and network.sent[0]["geometry_version"] == MapGeometry.VERSION, "gameplay and geometry capabilities are independent")
	network.connection_state = WebSocketPeer.STATE_OPEN
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.net_client = network
	manager.is_human_player = true
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	_check(key.is_action_pressed("reload") and not key.is_action_pressed("radio_next_station"), "R reloads without changing station")
	manager._input(key)
	key.pressed = false
	manager._input(key)
	manager._process(0.001)
	_check(network.sent.back().get("reload", false), "short reload press survives until transmission")
	manager._process(0.001)
	_check(not network.sent.back().has("reload"), "reload is consumed exactly once and absent from legacy actions")
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.pressed = true
	button.button_index = JOY_BUTTON_X
	_check(button.is_action_pressed("reload") and not button.is_action_pressed("fire"), "X reloads without shooting")
	key.physical_keycode = KEY_C
	key.pressed = true
	_check(key.is_action_pressed("radio_next_station") and not key.is_action_pressed("reload"), "C retains radio access")
	manager.free()
	network.free()
	var display: EquipmentHud = EquipmentHud.new()
	root.add_child(display)
	display.apply(state)
	display.visible = true
	display._process(0.0)
	_check(display.counts.text == "00 / 36" and display.caption.text.contains("RELOAD"), "empty magazine tells the player how to reload")
	display.apply(reload)
	display.tick = 29
	display._process(0.0)
	_check(display.bar.visible and is_equal_approx(display.bar.size.x, 118.0), "reload bar uses server completion")
	display.apply({})
	_check(not display.visible and display.tick == 0, "disconnect clears private UI and timebase")
	display.free()
	if _failures == 0:
		print("test_equipment: PASS private boundary, reload input, owned cycling and HUD")
	quit(0 if _failures == 0 else 1)
