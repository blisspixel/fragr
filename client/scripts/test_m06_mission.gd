extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://m06-mission-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _finalize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(get_meta("fragr_settings_path"))))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m06_mission: " + message)

static func _arrival(id: String, x: float) -> Dictionary:
	return {"id": id, "action": {"kind": "arrival", "feet": [x, 0, 0],
		"region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}}}

static func fixture_map() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(6):
		objectives.append(_arrival(M06MissionState.OBJECTIVES[index], -20.0 + index * 6.0))
	return {"type": "map_info", "map_id": 1006, "map_name": "Port of Entry", "geometry_version": 2, "half_extent": 48,
		"solids": [{"min_x": -35, "max_x": -34, "min_z": 10, "max_z": 25, "bottom": 0.9, "top": 4.5},
			{"min_x": 9, "max_x": 11, "min_z": 24, "max_z": 25, "top": 2.0}],
		"presentation": {"ground": "concrete", "solids": ["inspection_glass", "lift_panel"], "decorations": [
			{"solid": 1, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "m06_transit_departure"},
			{"solid": 0, "face": "east", "center": [0, 0], "size": [3, 1], "kind": "m06_family_window"},
			{"solid": 1, "face": "south", "center": [0, 0], "size": [1.5, 0.8], "kind": "m06_service_six"}]},
		"m06": {"objectives": objectives, "service": _arrival(M06MissionState.SERVICE, -30),
			"departure": {"decoration": 0, "approach": [10, 0, 23]},
			"boarding": {"min": [8, 0, 20], "max": [12, 2, 24]}, "companion_start": [-25, 0, 0]}}

static func fixture_state(info: Dictionary, count: int = 0, marked: bool = false, tick: int = 20) -> Dictionary:
	return {"type": "mission", "tick": tick, "state": {"id": MissionState.M06_ID, "rules": {"difficulty": "standard", "revision": 3},
		"attempt": 1, "phase": "in_progress", "changed_at": 10,
		"party": [{"id": PLAYER, "name": "Traveller", "ready": true, "alive": true, "aboard": count == 6}], "prompts": [],
		"m06": {"completed": M06MissionState.OBJECTIVES.slice(0, count), "current": info["m06"]["objectives"][count] if count < 6 else {
			"id": "party_departed", "action": {"kind": "use", "target": info["m06"]["departure"]}}, "prisoner_route_marked": marked,
			"carried_recall_cars": ["roof_car", "platform_car"], "carried_patients": ["edda_team_a"], "carried_photos": 2,
			"carried_released_workers": ["workshop_agent_b", "splice", "workshop_agent_a"], "carried_evacuated_workers": ["workshop_agent_a", "splice"]}}}

func _run() -> void:
	var info: Dictionary = fixture_map()
	var geometry: Dictionary = MissionState.geometry_for(info)
	var first: Dictionary = fixture_state(info)
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "registered lunar window and six objectives accepted")
	_check(MissionState.validation_error(first, geometry).is_empty(), "actual unsorted historical outcomes preserve carried identities")
	for field: String in ["m05", "m04", "m03"]:
		var conflicting: Dictionary = info.duplicate(true)
		conflicting[field] = {}
		_check(not MissionState.map_error(conflicting).is_empty(), "mixed mission envelope rejected: " + field)
	var bad: Dictionary = info.duplicate(true)
	bad["m06"]["objectives"][1]["id"] = "freight_cleared"
	_check(not MissionState.map_error(bad).is_empty(), "duplicate objective cannot replace the long lane")
	bad = info.duplicate(true)
	bad["m06"]["service"]["action"]["feet"][0] = INF
	_check(not MissionState.map_error(bad).is_empty(), "nonfinite optional approach rejected")
	bad = info.duplicate(true)
	bad["solids"][0]["max_z"] = 26
	_check(not M06MissionState.same_contract(geometry, MissionState.geometry_for(bad)), "static port cannot replace collision under retained facts")
	for patch: Dictionary in [{"completed": ["rail_lane_cleared"]}, {"prisoner_route_marked": "true"},
		{"carried_released_workers": ["splice"]}, {"carried_evacuated_workers": ["unknown"]},
		{"carried_patients": ["edda_team_a", "edda_team_a"]}, {"carried_photos": -1}, {"current": null}]:
		bad = first.duplicate(true)
		bad["state"]["m06"].merge(patch, true)
		_check(not MissionState.validation_error(bad, geometry).is_empty(), "strict lunar facts refuse " + str(patch))
	_check(not MissionState.validation_error(fixture_state(info, 2, true), geometry).is_empty(), "optional route cannot precede loading clearance")
	var marked: Dictionary = fixture_state(info, 3, true, 21)
	_check(MissionState.validation_error(marked, geometry, first).is_empty(), "optional marker does not replace the required objective")
	bad = marked.duplicate(true)
	bad["state"]["m06"]["prisoner_route_marked"] = false
	_check(not MissionState.validation_error(bad, geometry, marked).is_empty(), "same attempt cannot forget a marked route")
	bad = marked.duplicate(true)
	bad["state"]["m06"]["carried_evacuated_workers"] = ["splice"]
	_check(not MissionState.validation_error(bad, geometry, first).is_empty(), "retry or progress cannot silently replace actual passengers")
	bad = first.duplicate(true)
	bad["tick"] = 19
	_check(not MissionState.validation_error(bad, geometry, first).is_empty(), "out-of-order mission facts rejected")
	var retry: Dictionary = fixture_state(info, 0, false, 22)
	retry["state"]["attempt"] = 2
	retry["state"]["phase"] = "briefing"
	_check(MissionState.validation_error(retry, geometry, marked).is_empty(), "retry resets marker and prefix while retaining previous outcomes")
	var end: Dictionary = fixture_state(info, 6, true, 30)
	end["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(MissionState.validation_error(end, geometry, marked).is_empty(), "fresh departure prompt requires the completed living ready party")
	bad = end.duplicate(true)
	bad["state"]["party"][0]["aboard"] = false
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "departure refuses absent party member")
	end["state"]["phase"] = "departed"
	end["state"]["prompts"] = []
	end["state"]["m06"]["completed"].append("party_departed")
	end["state"]["m06"].erase("current")
	_check(MissionState.validation_error(end, geometry, marked).is_empty(), "resolved departure omits current and preserves carried choices")
	await _presentation(info, first, marked, end)
	if failures == 0:
		print("test_m06_mission: PASS strict geometry/facts/carry/retry, genuine HUD transitions and lunar presenter lifecycle")
	quit(0 if failures == 0 else 1)

func _presentation(info: Dictionary, first: Dictionary, marked: Dictionary, end: Dictionary) -> void:
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	var notices: Array[String] = []
	hud.notice_requested.connect(func(copy: String) -> void: notices.append(copy))
	hud.apply(first["state"], PLAYER)
	_check(hud._copy.text == tr("M06_OBJECTIVE_FREIGHT_CLEARED"), "HUD follows the authoritative first objective")
	hud.apply(marked["state"], PLAYER)
	_check(hud._evac_badge.text == tr("M06_SERVICE_MARKED"), "optional marker gets a separate corner status")
	var customs: Dictionary = fixture_state(info, 5, true)
	hud.apply(customs["state"], PLAYER)
	hud.apply(customs["state"], PLAYER)
	_check(notices == [tr("WORLD_M06_TERN_LINE")], "actual customs transition emits Tern's localized text once")
	hud.apply({}, PLAYER)
	hud.apply(customs["state"], PLAYER)
	_check(notices.size() == 1, "redundant map handoff does not replay customs dialogue")
	var retry_start: Dictionary = first["state"].duplicate(true)
	retry_start["attempt"] = 2
	hud.apply(retry_start, PLAYER)
	var retry_customs: Dictionary = customs["state"].duplicate(true)
	retry_customs["attempt"] = 2
	hud.apply(retry_customs, PLAYER)
	_check(notices.size() == 2, "fresh attempt can deliver the real customs transition again")
	hud.apply(end["state"], PLAYER)
	_check(hud._copy.text.contains("ESC") and not hud._copy.text.contains("{pause}"), "departure resolves keyboard control token")
	var stage_time: float = hud._stage_left
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	InputDevice.note(pad)
	hud._process(0.0)
	_check(not hud._copy.text.contains("ESC") and hud._stage_left == stage_time, "device switch refreshes departure without restarting card")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputDevice.note(key)
	hud._process(0.0)
	var port: M06Port = M06Port.new()
	root.add_child(port)
	port.configure_map(info)
	_check(port.residents.size() == 2 and port._root.find_child("EarthDrawing", true, false) != null, "safe glass presents two provisional neighbours and the Earth drawing")
	port._process(0.25)
	_check(port._water_material != null and float(port._water_material.get_shader_parameter("ripple_time")) >= 0.25, "contained labelled recycling water uses actual ripple clock")
	port.apply_state(marked["state"])
	_check((port._service_lamp.material_override as StandardMaterial3D).albedo_color == Color("c3d0ae"), "registered service lamp follows actual marker")
	port.configure_map({})
	_check(port._root == null and port.residents.is_empty() and port._water_material == null and port._water_seconds == 0.0, "map handoff cleans neighbours, water clock and service cues")
	hud.queue_free()
	port.queue_free()
	await process_frame
