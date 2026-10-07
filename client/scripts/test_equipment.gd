extends SceneTree

class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		last_send_ok = true
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
		"weapons": ["fists", "tack"],
		"ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}],
		"personal_claims": ["bay_tack"], "dry_fire_count": 1, "grenades": 0}

func _run() -> void:
	var state: Dictionary = _state()
	_check(EquipmentState.validation_error(state, "self").is_empty(), "valid private state is accepted")
	var remote_stock: Dictionary = state.duplicate(true)
	remote_stock["remote_mines"] = 6
	remote_stock["proximity_mines"] = 4
	_check(EquipmentState.validation_error(remote_stock, "self").is_empty(), "remote and proximity stock remain independent bounded counts")
	for value: Variant in [-1, 0, 7, 1.5, NAN, "2", null]:
		var bad_remote: Dictionary = state.duplicate(true)
		bad_remote["remote_mines"] = value
		_check(not EquipmentState.validation_error(bad_remote, "self").is_empty(), "remote stock requires a positive bounded wire integer: " + str(value))
	for value: Variant in [-1, 7, 1.5, NAN, "2"]:
		var bad_stock: Dictionary = state.duplicate(true)
		bad_stock["grenades"] = value
		_check(not EquipmentState.validation_error(bad_stock, "self").is_empty(), "counted grenade stock requires bounded integer: " + str(value))
	var absent_stock: Dictionary = state.duplicate(true)
	absent_stock.erase("grenades")
	_check(not EquipmentState.validation_error(absent_stock, "self").is_empty(), "current private wire requires explicit grenade stock")
	_check(not EquipmentState.validation_error(state, "other").is_empty(), "another participant's ammunition is rejected")
	_check(not EquipmentState.validation_error(state, null).is_empty(), "spectators cannot receive private ammunition")
	_check(EquipmentState.cycle(state, "tack", 1) == "fists" and EquipmentState.cycle(state, "fists", -1) == "tack", "cycling wraps only owned weapons")
	var ladder: Dictionary = state.duplicate(true)
	ladder["weapons"] = ["fists", "tack", "flechette", "scatter", "rail"]
	_check(EquipmentState.cycle(ladder, "tack", 1) == "scatter" and EquipmentState.cycle(ladder, "scatter", 1) == "flechette" and EquipmentState.cycle(ladder, "flechette", 1) == "rail" and EquipmentState.cycle(ladder, "rail", 1) == "fists", "the wheel walks fists, pistol, shotgun, rifle, railgun")
	_check(EquipmentState.slot_if_owned(EquipmentState.carried_names(state), 2) == "tack" and EquipmentState.slot_if_owned(EquipmentState.carried_names(state), 3) == "" and EquipmentState.slot_if_owned(EquipmentState.carried_names(ladder), 4) == "flechette", "number keys select a carried gun and ignore the rest")
	var automatic: Dictionary = ladder.duplicate(true)
	automatic["weapons"].append("repeater")
	automatic["selected"] = "repeater"
	_check(EquipmentState.validation_error(automatic, "self").is_empty(), "real Repeater is a distinct owned gun")
	var family: Array[String] = EquipmentState.carried_names(automatic)
	_check(EquipmentState.slot_if_owned(family, 4, "flechette") == "repeater" and EquipmentState.slot_if_owned(family, 4, "repeater") == "flechette", "key four cycles the two owned automatic guns")
	_check(EquipmentState.slot_if_owned(family, 3, "repeater") == "scatter" and EquipmentState.SLOTS.size() == 6, "shotgun key three and all six physical slots stay unchanged")
	_check(EquipmentState.cycle(automatic, "flechette", 1) == "repeater" and EquipmentState.cycle(automatic, "repeater", 1) == "rail", "wheel places Repeater after Rifle")
	family.erase("flechette")
	_check(EquipmentState.slot_if_owned(family, 4, "tack") == "repeater" and EquipmentState.slot_if_owned(family, 4, "repeater") == "repeater", "sole automatic family ownership always selects the real gun")
	_check("repeater" not in EquipmentState.ARCADE and EquipmentState.WEAPONS.find("repeater") == 7, "arcade kit and seven historical indices remain unchanged")
	var found: Dictionary = state.duplicate(true)
	found["weapons"] = ["fists", "tack", "shiv"]
	found["selected"] = "shiv"
	_check(EquipmentState.validation_error(found, "self").is_empty(), "a found Shiv is carried equipment")
	_check(EquipmentState.shots(found, "shiv") == -1 and EquipmentState.display_name("shiv") == "Shiv", "the Shiv needs no ammunition")
	var carried: Array[String] = EquipmentState.carried_names(found)
	_check(EquipmentState.slot_if_owned(carried, 1, "tack") == "shiv" and EquipmentState.slot_if_owned(carried, 1, "shiv") == "fists", "slot one draws the Shiv, then fists, like Doom's chainsaw")
	_check(EquipmentState.slot_if_owned(EquipmentState.carried_names(state), 1, "tack") == "fists", "slot one is fists until a Shiv is found")
	_check(EquipmentState.cycle(found, "fists", 1) == "shiv" and EquipmentState.cycle(found, "shiv", 1) == "tack" and EquipmentState.cycle(found, "tack", 1) == "fists", "the wheel keeps the Shiv beside the fists")
	var marksman: Dictionary = state.duplicate(true)
	marksman["weapons"] = ["fists", "tack", "flechette", "scatter", "rail", "sniper"]
	marksman["selected"] = "sniper"
	marksman["ammo"] = [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 9}]
	_check(EquipmentState.validation_error(marksman, "self").is_empty(), "a found Sniper Rifle is carried equipment")
	_check(EquipmentState.shots(marksman, "sniper") == 9 and EquipmentState.shots(marksman, "rail") == 9, "the Sniper Rifle and Railgun share Cells")
	_check(EquipmentState.display_name("sniper") == "Sniper Rifle" and "sniper" not in EquipmentState.ARCADE, "the Sniper Rifle reads by name and stays out of the arcade arsenal")
	var marksman_carried: Array[String] = EquipmentState.carried_names(marksman)
	_check(EquipmentState.slot_if_owned(marksman_carried, 6) == "sniper" and EquipmentState.slot_if_owned(EquipmentState.carried_names(ladder), 6) == "", "key six draws only a carried Sniper Rifle")
	_check(EquipmentState.cycle(marksman, "rail", 1) == "sniper" and EquipmentState.cycle(marksman, "sniper", 1) == "fists", "the wheel places the Sniper Rifle after the Railgun")
	_check("sniper" in EquipmentState.SCOPED and "rail" not in EquipmentState.SCOPED, "only the Sniper Rifle offers a scope")
	_check(SniperScope.active_for("sniper", true, true) and not SniperScope.active_for("rail", true, true) and not SniperScope.active_for("sniper", false, true) and not SniperScope.active_for("sniper", true, false), "the scope opens only when held with the Sniper Rifle in a live view")
	var unknown: Dictionary = found.duplicate(true)
	unknown["weapons"] = ["fists", "chainsaw"]
	unknown["selected"] = "fists"
	_check(not EquipmentState.validation_error(unknown, "self").is_empty(), "an unknown melee weapon is refused")
	for patch: Dictionary in [{"tick": -1}, {"tick": 1.5}, {"tick": NAN}, {"tick": "20"}, {"selected": "rail"},
		{"weapons": []}, {"weapons": [[]]}, {"weapons": ["tack"]}, {"weapons": ["fists", "fists", "tack"]},
		{"weapons": [{"weapon": "fists", "magazine": null}, {"weapon": "tack", "magazine": 0}]},
		{"ammo": []}, {"ammo": [{"pool": []}, {}, {}]}, {"ammo": [{"pool": "bullets", "rounds": 201}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}]},
		{"ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 51}, {"pool": "cells", "rounds": 0}]},
		{"ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 101}]},
		{"ammo": [{"pool": "tacks", "rounds": 0}, {"pool": "darts", "rounds": 0}, {"pool": "cores", "rounds": 0}]},
		{"ammo": [{"pool": "bullets", "rounds": 0}, {"pool": "bullets", "rounds": 0}, {"pool": "cells", "rounds": 0}]},
		{"personal_claims": ["../bay"]}, {"personal_claims": ["bay_tack", "bay_tack"]}, {"dry_fire_count": -1},
		{"reload": null}, {"reserves": []}, {"loaded": []}]:
		var invalid: Dictionary = state.duplicate(true)
		invalid.merge(patch, true)
		_check(not EquipmentState.validation_error(invalid, "self").is_empty(), "invalid state cannot enter presentation: " + str(patch))
	var missing: Dictionary = state.duplicate(true)
	missing.erase("ammo")
	_check(not EquipmentState.validation_error(missing, "self").is_empty(), "a loadout without counts is refused")
	var armed: Dictionary = state.duplicate(true)
	armed["weapons"] = ["fists", "tack", "flechette", "scatter"]
	armed["ammo"] = [{"pool": "bullets", "rounds": 108}, {"pool": "shells", "rounds": 11}, {"pool": "cells", "rounds": 0}]
	_check(EquipmentState.validation_error(armed, "self", state).is_empty(), "one count per type is accepted")
	_check(EquipmentState.shots(armed, "tack") == 108 and EquipmentState.shots(armed, "flechette") == 108, "pistol and rifle share bullets")
	_check(EquipmentState.shots(armed, "scatter") == 11 and EquipmentState.shots(armed, "rail") == 0 and EquipmentState.shots(armed, "fists") == -1, "shells and cells stay separate and fists need nothing")
	_check(EquipmentState.pellets("scatter") == 7 and EquipmentState.pellets("Scatter") == 7 and EquipmentState.pellets("rail") == 1, "only the shotgun fires pellets")
	var earlier: Dictionary = state.duplicate(true)
	earlier["tick"] = 19
	_check(not EquipmentState.validation_error(earlier, "self", state).is_empty(), "stale equipment cannot rewind the HUD")
	var network: CaptureNetwork = CaptureNetwork.new()
	network.player_id = "self"
	network._handle_message(JSON.stringify(state))
	_check(network.equipment.get("selected") == "tack" and EquipmentState.shots(network.equipment, "tack") == 0 \
		and network.equipment["personal_claims"] == ["bay_tack"], "network publishes validated inventory")
	network._handle_message(JSON.stringify(earlier))
	_check(network.equipment.is_empty() and network.player_id == null, "invalid private state closes and clears the session")
	network.send_hello()
	_check(network.sent[0]["gameplay_version"] == network.GAMEPLAY_VERSION and network.sent[0]["geometry_version"] == MapGeometry.VERSION, "gameplay and geometry capabilities are independent")
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
	_check(key.is_action_pressed("reload"), "R reloads")
	manager._input(key)
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(not network.sent.back().has("reload"), "R stays off the wire until a magazine loadout arrives")
	key.physical_keycode = KEY_C
	_check(key.is_action_pressed("radio_next_station"), "C retains radio access")
	key.physical_keycode = KEY_N
	_check(key.is_action_pressed("radio_next_track"), "N skips the track")
	key.physical_keycode = KEY_M
	_check(key.is_action_pressed("radio_toggle"), "M plays or pauses the radio")
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	pad.button_index = JOY_BUTTON_DPAD_UP
	_check(not pad.is_action_pressed("radio_next_station"), "D-pad up is not the radio")
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	_check(not pad.is_action_pressed("radio_next_track"), "D-pad down is not the radio")
	pad.button_index = JOY_BUTTON_DPAD_LEFT
	_check(not pad.is_action_pressed("radio_toggle"), "D-pad left is not the radio")
	var scope_key := InputEventKey.new()
	scope_key.physical_keycode = KEY_Z
	scope_key.pressed = true
	_check(scope_key.is_action_pressed("scope"), "Z holds the scope")
	var scope_mouse := InputEventMouseButton.new()
	scope_mouse.button_index = MOUSE_BUTTON_RIGHT
	scope_mouse.pressed = true
	_check(scope_mouse.is_action_pressed("scope"), "right mouse holds the scope")
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
	var magazine: Dictionary = state.duplicate(true)
	magazine["tick"] = 21
	magazine["ammo"] = [{"pool": "bullets", "rounds": 50}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}]
	magazine["loaded"] = [{"weapon": "tack", "rounds": 12}]
	_check(EquipmentState.validation_error(magazine, "self").is_empty(), "a pistol magazine inside the bullet pool is accepted")
	_check(EquipmentState.shots(magazine, "tack") == 12 and EquipmentState.count_text(magazine, "tack") == "12|38", "the pistol shows rounds in the gun and the reserve")
	var overfilled: Dictionary = magazine.duplicate(true)
	overfilled["loaded"] = [{"weapon": "tack", "rounds": 13}]
	_check(not EquipmentState.validation_error(overfilled, "self").is_empty(), "a magazine cannot hold more than its size")
	var over_pool: Dictionary = magazine.duplicate(true)
	over_pool["weapons"] = ["fists", "tack", "flechette"]
	over_pool["loaded"] = [{"weapon": "tack", "rounds": 12}, {"weapon": "flechette", "rounds": 20}]
	over_pool["ammo"] = [{"pool": "bullets", "rounds": 30}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}]
	_check(not EquipmentState.validation_error(over_pool, "self").is_empty(), "magazines cannot add rounds the pool does not hold")
	var two_reloads: Dictionary = magazine.duplicate(true)
	two_reloads["weapons"] = ["fists", "tack", "flechette"]
	two_reloads["ammo"] = [{"pool": "bullets", "rounds": 50}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}]
	two_reloads["loaded"] = [{"weapon": "tack", "rounds": 0, "ready_at": 40}, {"weapon": "flechette", "rounds": 10, "ready_at": 41}]
	_check(not EquipmentState.validation_error(two_reloads, "self").is_empty(), "only one gun reloads at a time")
	var arcade: Dictionary = state.duplicate(true)
	arcade["tick"] = 22
	arcade["selected"] = "flechette"
	arcade["weapons"] = ["flechette", "scatter", "rail"]
	arcade["personal_claims"] = []
	arcade["dry_fire_count"] = 0
	arcade["loaded"] = [{"weapon": "flechette", "rounds": 20}, {"weapon": "scatter", "rounds": 6}, {"weapon": "rail", "rounds": 4}]
	_check(EquipmentState.validation_error(arcade, "self").is_empty() and EquipmentState.count_text(arcade, "flechette") == "20", "a zero-pool arcade loadout shows only the rounds in the gun")
	var finite: Dictionary = arcade.duplicate(true)
	finite["tick"] = 23
	finite["ammo"] = [{"pool": "bullets", "rounds": 80}, {"pool": "shells", "rounds": 24}, {"pool": "cells", "rounds": 16}]
	_check(EquipmentState.validation_error(finite, "self").is_empty() and EquipmentState.count_text(finite, "flechette") == "20|60" and EquipmentState.count_text(finite, "scatter") == "6|18" and EquipmentState.count_text(finite, "rail") == "4|12", "a finite arcade bag shows rounds in the gun and what is left to load")
	var short_bag: Dictionary = finite.duplicate(true)
	short_bag["ammo"] = [{"pool": "bullets", "rounds": 10}, {"pool": "shells", "rounds": 24}, {"pool": "cells", "rounds": 16}]
	_check(not EquipmentState.validation_error(short_bag, "self").is_empty(), "arcade magazines cannot outrun the bag")
	var huge: Dictionary = finite.duplicate(true)
	huge["ammo"] = [{"pool": "bullets", "rounds": 201}, {"pool": "shells", "rounds": 24}, {"pool": "cells", "rounds": 16}]
	_check(not EquipmentState.validation_error(huge, "self").is_empty(), "an arcade bag stays inside the pool cap")
	network.equipment = magazine
	var reload_key: InputEventKey = InputEventKey.new()
	reload_key.physical_keycode = KEY_R
	reload_key.pressed = true
	manager.reload_armed = true
	manager._input(reload_key)
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(network.sent.back().get("reload") == true and not manager.pending_reload, "R reaches a server that sent magazines")
	manager._last_action_usec = -1000000000
	manager._process(0.001)
	_check(not network.sent.back().has("reload"), "one press sends one reload")
	network.equipment = {}
	manager.pending_weapon_swap = null
	_check(manager._next_weapon_swap(1) == "rail" and manager._next_weapon_swap(-1) == "scatter", "arcade wheel walks shotgun, rifle, and railgun")
	manager.free()
	camera.free()
	pawn.free()
	network.free()
	var early: EquipmentHud = EquipmentHud.new()
	early.apply({})
	var early_stock: Dictionary = state.duplicate(true)
	early_stock["grenades"] = 4
	early_stock["remote_mines"] = 3
	early.apply(early_stock)
	root.add_child(early)
	_check(early.grenade_counts.visible and early.grenade_counts.text == "4", "inventory applied before ready hydrates the later counter safely")
	_check(early.remote_counts.visible and early.remote_counts.text == "3", "remote stock hydrates independently before ready")
	early.apply({})
	_check(not early.grenade_counts.visible and not early.remote_counts.visible and not early.visible, "before-ready clear and later disconnect share the same lifecycle")
	early.free()
	var display: EquipmentHud = EquipmentHud.new()
	root.add_child(display)
	display.apply(state)
	display.visible = true
	display._process(0.0)
	_check(display.counts.text == "0" and display.glyph_pool == "bullets" and display.counts.modulate != Color.WHITE, "an empty pistol shows a dimmed bullet and a red zero")
	_check(display.get_child_count() == 4 and not display.grenade_counts.visible and not display.mine_counts.visible and not display.remote_counts.visible, "gun number and independent hidden grenade, proximity and remote counters, no caption words")
	var stocked: Dictionary = state.duplicate(true)
	stocked["grenades"] = 4
	stocked["remote_mines"] = 2
	display.apply(stocked)
	_check(display.grenade_counts.visible and display.grenade_counts.text == "4" and display.counts.text == "0", "grenade stock appears independently from bullet ammunition")
	_check(display.remote_counts.visible and display.remote_counts.text == "2" and not display.mine_counts.visible,
		"remote stock never appears as proximity stock")
	var decoded: Variant = JSON.parse_string(JSON.stringify(stocked))
	_check(decoded is Dictionary and EquipmentState.validation_error(decoded, "self").is_empty(), "a wire round trip keeps the stock valid")
	if decoded is Dictionary:
		display.apply(decoded)
		_check(display.grenade_counts.text == "4", "a JSON-decoded grenade count prints a whole number, got " + display.grenade_counts.text)
		_check(display.remote_counts.text == "2", "JSON-decoded remote stock prints a whole count")
	stocked["grenades"] = 0
	stocked.erase("remote_mines")
	display.apply(stocked)
	_check(display.grenade_counts.visible and display.grenade_counts.text == "0", "after discovery empty grenade stock stays visible")
	_check(display.remote_counts.visible and display.remote_counts.text == "0", "omitted depleted remote stock remains a visible distinct zero")
	_check(EquipmentState.display_name("flechette") == "Rifle" and EquipmentState.display_name("Flechette") == "Rifle" and EquipmentState.display_name("tack") == "Pistol" and EquipmentState.display_name("scatter") == "Shotgun" and EquipmentState.display_name("rail") == "Railgun", "guns use familiar names")
	_check(EquipmentState.pool_name("bullets") == "Bullets" and EquipmentState.pool_name("shells") == "Shells" and EquipmentState.pool_name("cells") == "Cells", "ammo uses familiar names")
	armed["selected"] = "scatter"
	display.apply(armed)
	display._process(0.3)
	_check(display.counts.text == "11" and display.glyph_pool == "shells" and display.counts.modulate == Color.WHITE and display.counts.get_theme_font_size("font_size") == 40, "the held shotgun shows its shell count")
	armed["selected"] = "flechette"
	display.apply(armed)
	display._process(0.0)
	_check(display.counts.text == "108" and display.glyph_pool == "bullets", "the rifle reads the shared bullet count")
	armed["selected"] = "fists"
	display.apply(armed)
	display._process(0.0)
	_check(display.counts.text == "" and display.glyph_pool == "", "fists show no ammunition")
	var shown: Dictionary = state.duplicate(true)
	shown["tick"] = 21
	shown["ammo"] = [{"pool": "bullets", "rounds": 50}, {"pool": "shells", "rounds": 0}, {"pool": "cells", "rounds": 0}]
	shown["loaded"] = [{"weapon": "tack", "rounds": 12}]
	display.apply(shown)
	display._process(0.0)
	_check(display.counts.text == "12|38" and display.counts.get_theme_font_size("font_size") == 32 and display.glyph_pool == "bullets", "a magazine reads loaded rounds, then the reserve")
	var arcade_hud: Dictionary = state.duplicate(true)
	arcade_hud["tick"] = 22
	arcade_hud["selected"] = "rail"
	arcade_hud["weapons"] = ["flechette", "scatter", "rail"]
	arcade_hud["personal_claims"] = []
	arcade_hud["dry_fire_count"] = 0
	arcade_hud["loaded"] = [{"weapon": "flechette", "rounds": 20}, {"weapon": "scatter", "rounds": 6}, {"weapon": "rail", "rounds": 4}]
	display.apply(arcade_hud)
	display._process(0.0)
	_check(display.counts.text == "4" and display.counts.get_theme_font_size("font_size") == 40 and display.glyph_pool == "cells", "an arcade railgun shows only the magazine")
	display.apply({})
	_check(not display.visible and display.tick == 0, "disconnect clears private UI and timebase")
	display.free()
	if _failures == 0:
		print("test_equipment: PASS private boundary, magazines, owned cycling and HUD")
	quit(0 if _failures == 0 else 1)
