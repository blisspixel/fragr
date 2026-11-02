extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m04_mission: " + message)

func _map(open: bool = false) -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(M04MissionState.OBJECTIVES.size()):
		var x: float = -20.0 + float(index) * 6.0
		objectives.append({"id": M04MissionState.OBJECTIVES[index], "action": {"kind": "arrival",
			"region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}, "feet": [x, 0, 0]}})
	return {"type": "map_info", "map_id": 1004, "map_name": "Notice to Vacate: Low Water prototype", "geometry_version": 2,
		"half_extent": 40, "solids": [{"min_x": 0, "max_x": 2, "bottom": 0, "top": 1.2, "min_z": 4, "max_z": 5},
			{"min_x": 9, "max_x": 11, "bottom": 0, "top": 1.2, "min_z": 24, "max_z": 25}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "lift_panel"], "decorations": [
			{"solid": 0, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "lift_control"},
			{"solid": 1, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "lift_control"}]},
		"m04": {"clinic_open": open, "clinic": {"control": {"decoration": 0, "approach": [1, 0, 3]},
			"release": {"min": [1, 0, 6], "max": [7, 2, 12]}},
			"patients": [{"id": "edda_team_a", "held": [3, 0, 8], "route": [[3, 0, 8], [3, 0, 14], [8, 0, 14]]}],
			"objectives": objectives, "departure": {"decoration": 1, "approach": [10, 0, 23]},
			"boarding": {"min": [8, 0, 20], "max": [12, 2, 24]}, "companion_start": [-25, 0, 0]}}

func _state(info: Dictionary, count: int = 0, phase: String = "in_progress", released: bool = false, feet: Array = [],
		attempt: int = 1, tick: int = 20) -> Dictionary:
	var completed: Array[String] = M04MissionState.OBJECTIVES.slice(0, mini(count, 6))
	if phase == "departed":
		completed.append(M04MissionState.DEPARTURE)
	var progress: Dictionary = {"completed": completed, "clinic_secured": info["m04"]["clinic_open"],
		"clinic_open": info["m04"]["clinic_open"], "patients_released": released, "photos_completed": 0,
		"carried_recall_cars": ["platform_car"], "patients": [{"id": "edda_team_a", "feet": feet if not feet.is_empty() else [3, 0, 8]}]}
	if phase != "departed":
		progress["current"] = info["m04"]["objectives"][count].duplicate(true) if count < 6 else {
			"id": M04MissionState.DEPARTURE, "action": {"kind": "use", "target": info["m04"]["departure"].duplicate(true)}}
	return {"type": "mission", "tick": tick, "state": {"id": MissionState.M04_ID, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION},
		"attempt": attempt, "phase": phase, "changed_at": 10, "m04": progress,
		"party": [{"id": PLAYER, "name": "Neighbour", "ready": phase != "briefing", "alive": true, "aboard": count == 6 and phase != "briefing"}], "prompts": []}}

func _invalid(message: Dictionary, geometry: Dictionary, description: String, previous: Dictionary = {}) -> void:
	_check(not MissionState.validation_error(message, geometry, previous).is_empty(), description)

func _run() -> void:
	var info: Dictionary = _map()
	var open: Dictionary = _map(true)
	var geometry: Dictionary = MissionState.geometry_for(info)
	var opened: Dictionary = MissionState.geometry_for(open)
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "strict M04 geometry validates")
	_check(MissionState.map_error(open).is_empty() and M04MissionState.same_contract(geometry, opened), "clinic flag may change without replacing the mission")
	var rebind: Dictionary = opened.duplicate(true)
	rebind["m04"]["patients"][0]["route"][1] = [4, 0, 14]
	_check(not M04MissionState.same_contract(geometry, rebind), "same-map handoff cannot rebind a patient route")
	for patch: Dictionary in [{"clinic_open": 1}, {"patients": []}, {"objectives": []}, {"extra": true}, {"companion_start": [NAN, 0, 0]},
		{"boarding": {"min": [0, 0, 0], "max": [0, 1, 1]}}, {"departure": {"decoration": 0, "approach": [1, 0, 3]}}]:
		var bad: Dictionary = info.duplicate(true)
		bad["m04"].merge(patch, true)
		_check(not MissionState.map_error(bad).is_empty(), "malformed M04 map refused: " + str(patch))
	for patch: Dictionary in [{"m03": {}}, {"m02_objectives": 3}, {"mission": {}}, {"map_id": 1003}, {"m04": null}]:
		var bad: Dictionary = info.duplicate(true)
		bad.merge(patch, true)
		_check(not MissionState.map_error(bad).is_empty(), "mixed M04 identity refused")
	for route: Array in [[[3, 0, 9], [3, 0, 14]], [[3, 0, 8]], [[3, 0, 8], [3, 1, 14]], [[3, 0, 8], [41, 0, 14]], [[3, 0, 8], [INF, 0, 14]],
		[[3, 0, 8], [3, 0, 8]], [[3, 0, 8], [3.05, 0, 8]], [[3, 0, 8], [3, 0, 14], [3, 0, 10]],
		[[3, 0, 8], [9, 0, 14], [3, 0, 14], [9, 0, 8]], [[3, 0, 8], [3, 0, 14], [3.05, 0, 14], [3.05, 0, 8]]]:
		var bad: Dictionary = info.duplicate(true)
		bad["m04"]["patients"][0]["route"] = route
		_check(not MissionState.map_error(bad).is_empty(), "patient routes require held-first, bounded same-height points")
	var terminal: Dictionary = info.duplicate(true)
	terminal["presentation"]["decorations"][0]["kind"] = "terminal"
	_check(MissionState.map_error(terminal).is_empty(), "optional clinic accepts existing authored terminal compatibility")
	var duplicate: Dictionary = info.duplicate(true)
	duplicate["m04"]["patients"].append(duplicate["m04"]["patients"][0].duplicate(true))
	_check(not MissionState.map_error(duplicate).is_empty(), "duplicate patient IDs refused")
	var malformed_objective: Dictionary = info.duplicate(true)
	malformed_objective["m04"]["objectives"][0]["id"] = "first_notary_cleared"
	_check(not MissionState.map_error(malformed_objective).is_empty(), "required arrival order cannot change")
	var before: Dictionary = _state(info, 0, "briefing")
	_check(MissionState.validation_error(before, geometry).is_empty(), "briefing allows retained car carry and held patients")
	for count: int in range(7):
		var step: Dictionary = _state(info, count, "in_progress", false, [], 1, 21 + count)
		_check(MissionState.validation_error(step, geometry, before).is_empty(), "ordered encounter prefix and exact next action " + str(count))
		before = step
	var message: Dictionary = _state(info)
	for patch: Dictionary in [{"id": MissionState.M03_ID}, {"phase": "reach_lift"}, {"attempt": 0}, {"changed_at": 21}, {"extra": true},
		{"rules": {"difficulty": "standard", "revision": 2}}, {"party": [null]}, {"m03": {}}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"].merge(patch, true)
		_invalid(bad, geometry, "malformed outer mission refused")
	for patch: Dictionary in [{"completed": ["court_cleared"]}, {"current": null}, {"clinic_open": true}, {"patients_released": true},
		{"photos_completed": -1}, {"photos_completed": 1000001}, {"photos_completed": true}, {"patients": []}, {"carried_recall_cars": ["a", "a"]},
		{"carried_recall_cars": ["UPPER"]}, {"extra": true}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"]["m04"].merge(patch, true)
		_invalid(bad, geometry, "malformed progress refused: " + str(patch))
	var rebound: Dictionary = message.duplicate(true)
	rebound["state"]["m04"]["current"]["action"]["feet"][0] += 0.1
	_invalid(rebound, geometry, "current arrival binds exactly to the registered objective")
	var clinic: Dictionary = _state(info, 3)
	clinic["state"]["m04"]["clinic_secured"] = true
	clinic["state"]["prompts"] = [{"player_id": PLAYER, "kind": "clinic_shutter"}]
	_check(MissionState.validation_error(clinic, geometry).is_empty(), "typed optional clinic Use is independent of the encounter objective")
	var opened_state: Dictionary = _state(open, 3, "in_progress", false, [], 1, 30)
	_check(MissionState.validation_error(opened_state, opened, clinic).is_empty(), "ordered open world accepts secured clinic facts")
	_invalid(opened_state, geometry, "open clinic cannot arrive before its MapInfo")
	var walking: Dictionary = _state(open, 3, "in_progress", true, [3, 0, 11], 1, 31)
	_check(MissionState.validation_error(walking, opened, opened_state).is_empty(), "released patients walk the first registered segment")
	var turned: Dictionary = _state(open, 3, "in_progress", true, [5, 0, 14], 1, 32)
	_check(MissionState.validation_error(turned, opened, walking).is_empty(), "patients may turn a route corner and advance cumulative distance")
	for feet: Array in [[4, 0, 10], [3, 0.1, 11], [41, 0, 14], [3, 0, 9]]:
		var bad: Dictionary = _state(open, 3, "in_progress", true, feet, 1, 33)
		_invalid(bad, opened, "patient cannot cut route corners, leave bounds or reverse authoritative progress", turned)
	var photo: Dictionary = turned.duplicate(true)
	photo["tick"] = 33
	photo["state"]["m04"]["photos_completed"] = 2
	_check(MissionState.validation_error(photo, opened, turned).is_empty(), "actual photograph count advances without deciding damage locally")
	var backward_photo: Dictionary = turned.duplicate(true)
	backward_photo["tick"] = 34
	_invalid(backward_photo, opened, "photograph count cannot decrease within an attempt", photo)
	var retry: Dictionary = _state(info, 0, "briefing", false, [], 2, 35)
	_check(MissionState.validation_error(retry, geometry, photo).is_empty(), "new attempt resets all local mission progress and patient poses")
	retry["state"]["m04"]["carried_recall_cars"] = []
	_invalid(retry, geometry, "retry cannot erase retained M03 car choices", photo)
	var ready: Dictionary = _state(info, 6)
	ready["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(MissionState.validation_error(ready, geometry).is_empty(), "roof departure does not require optional clinic rescue")
	for patch: Dictionary in [{"alive": false}, {"ready": false}, {"aboard": false}, {"name": "bad\nname"}]:
		var bad: Dictionary = ready.duplicate(true)
		bad["state"]["party"][0].merge(patch, true)
		_invalid(bad, geometry, "roof Use requires living ready boarded party")
	var early: Dictionary = message.duplicate(true)
	early["state"]["prompts"] = ready["state"]["prompts"]
	_invalid(early, geometry, "roof Use cannot skip the required encounters")
	var departed: Dictionary = _state(info, 6, "departed", false, [], 1, 40)
	_check(MissionState.validation_error(departed, geometry, ready).is_empty(), "departure appends exact final prefix without requiring the clinic")
	departed["state"]["m04"]["current"] = null
	_invalid(departed, geometry, "terminal current is omitted rather than null")
	departed["state"]["m04"].erase("current")
	var durable: Dictionary = message.duplicate(true)
	durable["state"]["run"] = {"id": "00000000-0000-0000-0000-000000000003", "status": "playing", "continues": 2, "level_start_continues": 2}
	_check(MissionState.validation_error(durable, geometry).is_empty(), "M04 durable entry retains the M03 allowance")
	var continued: Dictionary = _state(info, 0, "briefing", false, [], 2, 41)
	continued["state"]["run"] = durable["state"]["run"].duplicate(true)
	continued["state"]["run"]["continues"] = 1
	_check(MissionState.validation_error(continued, geometry, durable).is_empty(), "M04 retry consumes one remaining continue without refill")
	continued["state"]["run"]["continues"] = 2
	_invalid(continued, geometry, "retry cannot retain or increase its spent continue", durable)
	var returned: Dictionary = ready.duplicate(true)
	returned["tick"] = 42
	_invalid(returned, geometry, "departure is terminal within the same attempt", departed)
	await _hud(message, clinic, ready, departed)
	await _notice(info)
	_network(info, open, clinic, opened_state)
	if failures == 0:
		print("test_m04_mission: PASS strict map/state, clinic ordering, patient routes, prefix, retry, carry, prompts and device HUD")
	quit(0 if failures == 0 else 1)

func _hud(message: Dictionary, clinic: Dictionary, ready: Dictionary, departed: Dictionary) -> void:
	var display: MissionHud = MissionHud.new()
	root.add_child(display)
	await process_frame
	display.apply(message["state"], PLAYER)
	_check(display._copy.text == "CLEAR THE NOTICE BOARD" and display.prompt_text.is_empty(), "first objective is readable without an invented control")
	display._process(MissionHud.STAGE_SECONDS + 0.1)
	display.apply(message["state"], PLAYER)
	_check(not display._card.visible, "repeated mission packet never restages an expired objective")
	display.apply(clinic["state"], PLAYER)
	_check(display.prompt_text == "F: OPEN THE CLINIC SHUTTER" and not display._card.visible, "clinic prompt accurately names optional local control")
	display.apply(ready["state"], PLAYER)
	_check(display.prompt_text == "F: LEAVE BY THE ROOF STAIR", "roof prompt is distinct from clinic")
	display.apply(departed["state"], PLAYER)
	_check(display._copy.text == "THE ROOF STAIR IS CLEAR\nESC: RETURN TO MENU", "departure uses supported pause glyph")
	await process_frame
	await process_frame
	_check(not display._card.get_rect().intersects(display._evac_badge.get_rect()), "departure card and authoritative clinic/photo status occupy separate space")
	display._process(0.25)
	var timer: float = display._stage_left
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	display._process(0.0)
	_check(display._copy.text == "THE ROOF STAIR IS CLEAR\nMENU: RETURN TO MENU" and display._stage_left == timer,
		"device change updates the same terminal card without a packet or restage")
	InputDevice.reset()
	display._process(0.0)
	_check(display._copy.text.ends_with("ESC: RETURN TO MENU"), "keyboard return updates current departure copy")
	display.free()

func _network(info: Dictionary, open: Dictionary, clinic: Dictionary, opened: Dictionary) -> void:
	var network: Node = load("res://scripts/net_client.gd").new()
	var errors: Array[String] = []
	network.server_error.connect(func(text: String) -> void: errors.append(text))
	network.player_id = PLAYER
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(clinic))
	_check(network.mission.get("state", {}).get("m04", {}).get("clinic_secured", false), "NetClient retains validated closed-world clinic prompt")
	network._handle_message(JSON.stringify(open))
	_check(network.mission.is_empty() and not network._mission_previous.is_empty(), "world handoff clears stale clinic prompt but keeps monotonic facts")
	network._handle_message(JSON.stringify(opened))
	_check(errors.is_empty() and network.player_id == PLAYER and network.mission["state"]["m04"]["clinic_open"], "ordered clinic MapInfo then facts reaches presentation")
	var rebind: Dictionary = open.duplicate(true)
	rebind["m04"]["patients"][0]["route"][1] = [4, 0, 14]
	network._handle_message(JSON.stringify(rebind))
	_check(errors.size() == 1 and network.player_id == null and network.mission.is_empty(), "same map cannot secretly replace its bound patient route")
	network.free()
	var out_of_order: Node = load("res://scripts/net_client.gd").new()
	out_of_order.player_id = PLAYER
	out_of_order._handle_message(JSON.stringify(info))
	out_of_order._handle_message(JSON.stringify(opened))
	_check(out_of_order.player_id == null and out_of_order.mission.is_empty(), "new clinic facts before the geometry fail closed")
	out_of_order.free()

func _notice(info: Dictionary) -> void:
	var display: MissionHud = MissionHud.new()
	root.add_child(display)
	var notices: Array[String] = []
	display.notice_requested.connect(func(text: String) -> void: notices.append(text))
	display.apply(_state(info, 4)["state"], PLAYER)
	display.apply({}, PLAYER)
	display.apply(_state(info, 5)["state"], PLAYER)
	_check(notices == ["Mara: They are still arguing over the trucks. Get everyone up."], "observed second market clear delivers the accepted corner warning once")
	display.apply(_state(info, 5)["state"], PLAYER)
	display.apply({}, PLAYER)
	display.apply(_state(info, 5)["state"], PLAYER)
	_check(notices.size() == 1, "duplicates and geometry clears do not replay Mara")
	display.apply(_state(info, 0, "briefing", false, [], 2)["state"], PLAYER)
	display.apply(_state(info, 5, "in_progress", false, [], 2)["state"], PLAYER)
	_check(notices.size() == 2, "explicit new attempt resets the story cue latch")
	display.reset_notices()
	display.apply(_state(info, 5)["state"], PLAYER)
	_check(notices.size() == 2, "late join to an already completed market invents no transition")
	display.free()
