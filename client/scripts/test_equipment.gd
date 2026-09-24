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
	var ladder: Dictionary = state.duplicate(true)
	ladder["weapons"] = [{"weapon": "fists", "magazine": null}, {"weapon": "tack", "magazine": 12}, {"weapon": "flechette", "magazine": 30}, {"weapon": "scatter", "magazine": 6}, {"weapon": "rail", "magazine": 4}]
	_check(EquipmentState.cycle(ladder, "tack", 1) == "scatter" and EquipmentState.cycle(ladder, "scatter", 1) == "flechette" and EquipmentState.cycle(ladder, "flechette", 1) == "rail" and EquipmentState.cycle(ladder, "rail", 1) == "fists", "the wheel walks fists, pistol, shotgun, rifle, railgun")
	_check(EquipmentState.slot_if_owned(EquipmentState.carried_names(state), 2) == "tack" and EquipmentState.slot_if_owned(EquipmentState.carried_names(state), 3) == "" and EquipmentState.slot_if_owned(EquipmentState.carried_names(ladder), 4) == "flechette", "number keys select a carried gun and ignore the rest")
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
	_check(network.sent[0]["gameplay_version"] == 9 and network.sent[0]["geometry_version"] == MapGeometry.VERSION, "gameplay and geometry capabilities are independent")
	network.connection_state = WebSocketPeer.STATE_OPEN
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.net_client = network
	manager.is_human_player = true
	network.player_id = "self"
	var pawn: Node3D = Node3D.new()
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	camera.fp_mode = true
	camera.fp_target = pawn
	manager.camera = camera
	manager.players["self"] = pawn
	manager.local_fp_pawn_id = "self"
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	_check(key.is_action_pressed("reload") and not key.is_action_pressed("radio_next_station"), "R reloads without changing station")
	manager._input(key)
	key.pressed = false
	manager._input(key)
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(network.sent.back().get("reload", false), "short reload press survives until transmission")
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(not network.sent.back().has("reload"), "reload is consumed exactly once and absent from legacy actions")
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.pressed = true
	button.button_index = JOY_BUTTON_X
	_check(button.is_action_pressed("reload") and not button.is_action_pressed("fire"), "X reloads without shooting")
	key.physical_keycode = KEY_C
	key.pressed = true
	_check(key.is_action_pressed("radio_next_station") and not key.is_action_pressed("reload"), "C retains radio access")
	network.equipment = state.duplicate(true)
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_check(wheel.is_action_pressed("weapon_next") and not wheel.is_action_pressed("fire"), "wheel up is the next gun")
	manager._input(wheel)
	_check(manager.pending_weapon_swap == "fists", "one notch leaves the pistol for the fists")
	manager._input(wheel)
	_check(manager.pending_weapon_swap == "tack", "the next notch continues from the gun already chosen")
	var pistol_key: InputEventKey = InputEventKey.new()
	pistol_key.physical_keycode = KEY_2
	pistol_key.pressed = true
	_check(pistol_key.is_action_pressed("weapon_2"), "2 is the pistol")
	manager.pending_weapon_swap = null
	network.equipment["selected"] = "fists"
	manager._input(pistol_key)
	_check(manager.pending_weapon_swap == "tack", "2 selects the carried pistol")
	var shotgun_key: InputEventKey = InputEventKey.new()
	shotgun_key.physical_keycode = KEY_3
	shotgun_key.pressed = true
	manager.pending_weapon_swap = null
	manager._input(shotgun_key)
	_check(manager.pending_weapon_swap == null, "3 does nothing until the shotgun is carried")
	var fists_key: InputEventKey = InputEventKey.new()
	fists_key.physical_keycode = KEY_1
	fists_key.keycode = KEY_1
	fists_key.pressed = true
	network.equipment["selected"] = "tack"
	_check(fists_key.is_action_pressed("weapon_1"), "1 maps to fists")
	manager._input(fists_key)
	_check(manager.pending_weapon_swap == "fists", "1 selects fists from the carried pistol")
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(network.sent.back().get("weapon_swap") == "fists", "1 reaches the server action as fists")
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(not network.sent.back().has("weapon_swap"), "the discrete fists choice is transmitted once")
	network.equipment = {}
	manager.pending_weapon_swap = null
	_check(manager._next_weapon_swap(1) == "rail" and manager._next_weapon_swap(-1) == "scatter", "arcade wheel walks shotgun, rifle, and railgun")
	manager.free()
	camera.free()
	pawn.free()
	network.free()
	var display: EquipmentHud = EquipmentHud.new()
	root.add_child(display)
	display.apply(state)
	display.visible = true
	display._process(0.0)
	_check(display.counts.text == "00 / 36" and display.caption.text.contains("RELOAD"), "empty magazine tells the player how to reload")
	_check(EquipmentState.display_name("flechette") == "Rifle" and EquipmentState.display_name("Flechette") == "Rifle" and EquipmentState.display_name("tack") == "Pistol" and EquipmentState.display_name("scatter") == "Shotgun" and EquipmentState.display_name("rail") == "Railgun", "guns use familiar names")
	_check(EquipmentState.pool_name("darts") == "Shells" and EquipmentState.pool_name("tacks") == "Bullets" and EquipmentState.pool_name("cores") == "Cells", "ammo uses familiar names")
	var rifle: Dictionary = state.duplicate(true)
	rifle["selected"] = "flechette"
	rifle["weapons"].append({"weapon": "flechette", "magazine": 30})
	display.apply(rifle)
	display._process(0.0)
	_check(display.caption.text == "RIFLE", "the held dart gun reads as a rifle")
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
