extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m04_town: " + message)

func _map() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(6):
		var x: float = -20.0 + float(index) * 6.0
		objectives.append({"id": M04MissionState.OBJECTIVES[index], "action": {"kind": "arrival",
			"region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}, "feet": [x, 0, 0]}})
	return {"type": "map_info", "map_id": 1004, "map_name": "Notice to Vacate", "geometry_version": 2,
		"half_extent": 40, "solids": [
			{"min_x": 0, "max_x": 2, "bottom": 0, "top": 1.2, "min_z": 4, "max_z": 5},
			{"min_x": 9, "max_x": 11, "bottom": 0, "top": 1.2, "min_z": 24, "max_z": 25},
			{"min_x": -15, "max_x": -9, "bottom": 2.8, "top": 3, "min_z": -7, "max_z": -2},
			{"min_x": -18, "max_x": -15, "bottom": 3, "top": 4.5, "min_z": 35, "max_z": 38},
			{"min_x": 25, "max_x": 32, "top": 2.5, "min_z": -15, "max_z": -9}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "lift_panel", "enamel", "service_steel", "enamel"],
			"decorations": [
				{"solid": 0, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "m04_clinic_control"},
				{"solid": 1, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "m04_roof_departure"},
				{"solid": 2, "face": "up", "center": [0, 0], "size": [5, 4], "kind": "m04_market_canvas"},
				{"solid": 3, "face": "north", "center": [0, 0], "size": [2, 1], "kind": "m04_water_tank"},
				{"solid": 4, "face": "west", "center": [0, 0], "size": [4, 1], "kind": "m04_tram_vote"}]},
		"m04": {"clinic_open": true, "clinic": {"control": {"decoration": 0, "approach": [1, 0, 3]},
			"release": {"min": [1, 0, 6], "max": [7, 2, 12]}},
			"patients": [{"id": "edda_team_a", "held": [3, 0, 8], "route": [[3, 0, 8], [3, 0, 14], [8, 0, 14]]}],
			"objectives": objectives, "departure": {"decoration": 1, "approach": [10, 0, 23]},
			"boarding": {"min": [8, 0, 20], "max": [12, 2, 24]}, "companion_start": [-25, 0, 0]}}

func _state(info: Dictionary, feet: Array, released: bool) -> Dictionary:
	return {"id": MissionState.M04_ID, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION},
		"attempt": 1, "phase": "in_progress", "changed_at": 10, "prompts": [],
		"party": [{"id": "00000000-0000-0000-0000-000000000002", "name": "Neighbour", "ready": true, "alive": true, "aboard": false}],
		"m04": {"completed": [], "current": info["m04"]["objectives"][0].duplicate(true),
			"clinic_secured": true, "clinic_open": true, "patients_released": released, "photos_completed": 0,
			"carried_recall_cars": [], "patients": [{"id": "edda_team_a", "feet": feet}]}}

func _run() -> void:
	var info: Dictionary = _map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "fixture is a strict delivered map")
	var town: M04Town = M04Town.new()
	root.add_child(town)
	town.configure_map(info)
	_check(town.get_child_count() == 1 and town._views.size() == 1, "one bounded root and exact authored patient")
	var tank: MeshInstance3D = town._root.get_node("CommunalWaterTank")
	_check(tank.position.is_equal_approx(Vector3(-16.5, 5.1, 36.5)) and tank.layers == ArenaSky.WORLD_LAYERS,
		"tank follows the registered host and world lighting layer")
	var canvases: int = 0
	for child: Node in town._root.get_children():
		_check(not child is CollisionObject3D, "town detail never creates a collision body")
		if child is MeshInstance3D:
			_check(child.layers == ArenaSky.WORLD_LAYERS, "all town geometry uses authored venue lighting")
			if child.name.begins_with("CanvasStripe"):
				canvases += 1
	_check(canvases == 8, "registered awning has eight bounded colour bands")
	var windows: int = 0
	for child: Node in town._root.get_children():
		if child.name.begins_with("TramWindow"):
			windows += 1
	_check(windows == 4, "live wire omitted ground bottom uses the shared geometry default")
	var view: Sprite3D = town._views["edda_team_a"]
	_check(view.position == Vector3(3, EnemyAnimation.CENTRE_HEIGHT, 8), "patient begins at authoritative held feet")
	var walking: Dictionary = _state(info, [3, 0, 11], true)
	_check(MissionState.validation_error({"tick": 20, "state": walking}, town._geometry).is_empty(), "walking fixture is valid")
	town.apply_state(walking)
	_check(view.position == Vector3(3, EnemyAnimation.CENTRE_HEIGHT, 11) and is_equal_approx(float(view.get_meta("walked")), 3.0),
		"released patient follows the delivered route sample without predicting feet")
	var recorded_time: int = int(view.get_meta("last_move_ms"))
	town.apply_state(walking)
	_check(int(view.get_meta("last_move_ms")) == recorded_time, "unchanged samples do not prolong gait")
	town._process(0.25)
	_check(view.frame == PlayerBody.frame(town._clock, 3.0, 2.0), "walking pose uses actual recorded distance")
	var bad: Dictionary = _state(info, [4, 0, 10], true)
	town.apply_state(bad)
	_check(view.position == Vector3(3, EnemyAnimation.CENTRE_HEIGHT, 11), "invalid route shortcut cannot move patient presentation")
	view.set_meta("last_move_ms", Time.get_ticks_msec() - 1000)
	town._process(0.0)
	_check(view.frame < PlayerBody.IDLE_FRAMES and view.position.z == 11, "stationary patient stops animating without extrapolation")
	var moved: Dictionary = info.duplicate(true)
	moved["solids"][3]["min_x"] += 2
	moved["solids"][3]["max_x"] += 2
	town.configure_map(moved)
	tank = town._root.get_node("CommunalWaterTank")
	_check(tank.position.x == -14.5 and town.get_child_count() == 1,
		"reconfiguration derives new tank anchor and replaces prior presentation")
	_check(is_zero_approx(float(town._views["edda_team_a"].get_meta("walked"))), "reconfiguration clears patient gait history")
	moved["solids"][3]["top"] = NAN
	town.configure_map(moved)
	_check(town._geometry.is_empty() and town.get_child_count() == 0, "malformed replacement tears down old presentation")
	town.configure_map(info)
	town.configure_map({"map_id": 1})
	_check(town._views.is_empty() and town.get_child_count() == 0, "legacy map removes town fixtures and patients")
	town.queue_free()
	await process_frame
	if failures == 0:
		print("test_m04_town: PASS registered fixtures, nonblocking geometry, authoritative patient feet, gait and teardown")
	quit(0 if failures == 0 else 1)
