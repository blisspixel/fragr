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
	_check_patient_capture_detour()
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
		print("test_m04_town: PASS registered fixtures, authoritative patient feet, gait, teardown and actual-map contact detour")
	quit(0 if failures == 0 else 1)

func _check_patient_capture_detour() -> void:
	var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m04_notice_to_vacate.json"))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m04-market.json"))
	_check(authored is Dictionary and manifest is Dictionary, "patient detour loads actual authored map and capture route")
	if not authored is Dictionary or not manifest is Dictionary:
		return
	var patients: Array[Dictionary] = []
	for patient: Dictionary in authored["m04"]["patients"]:
		var endpoint: Array = patient["route"].back()
		patients.append(ActorContact.stationary("m04/" + patient["id"], Vector3(endpoint[0], endpoint[1], endpoint[2])))
	_check(patients.size() == 2, "regression uses both actual released patients")
	var routes: Dictionary = {}
	for stage: Dictionary in manifest["states"]:
		if stage["name"] in ["repair_bench_supplies", "awning_service_stairs"]:
			routes[stage["name"]] = stage["walk_to"]
		if stage["name"] == "market_wave_b":
			routes["market_search"] = stage["combat"]["search_route"]
	_check(routes.size() == 3 and manifest["states"].size() == 23, "all three affected legs retain the full 23-state capture")
	if routes.size() != 3:
		return
	# A direct desired leg collides with real patients. Do not mask it by
	# increasing the arrival disk or exempting civilians from body contact.
	var old: Dictionary = ActorContact.stationary("human", Vector3(-18, 0, 10))
	old["proposed"]["x"] = -19.0
	old["proposed"]["z"] = 0.75
	var hit: bool = false
	for patient: Dictionary in patients:
		hit = hit or ActorContact.sweep_time(old, patient) >= 0.0
	_check(hit, "old straight corridor leg intersects a real released body")
	for opened: bool in [false, true]:
		var solids: Array[Dictionary] = []
		for solid: Dictionary in authored["solids"]:
			var lift: float = float(authored["m04"]["clinic"]["gate"]["lift"]) if opened and solid["id"] == authored["m04"]["clinic"]["gate"]["solid"] else 0.0
			solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2],
				"max_z": solid["max"][2], "bottom": float(solid["min"][1]) + lift, "top": float(solid["max"][1]) + lift})
		var arena: Dictionary = {"half": authored["half_extent"], "solids": solids}
		_check_capture_handoff(authored, manifest, patients, arena)
		_check_court_capture_approach(authored, manifest, patients, arena)
		_check_notice_capture_approach(authored, manifest, patients, arena)
		var former: Dictionary = _walk_patient_detour(MoveStep.make_state(-18.0, 0.75, 0.0), Vector3(-18, 0, 10), patients, arena)
		_check(absf(float(former["z"]) - 1.0) < 0.001,
			"former repair return leg stops at the actual patient summed radius with ordinary input")
		for route_name: String in routes:
			var body: Dictionary = MoveStep.make_state(-18.0, 10.0, 0.0)
			if route_name == "awning_service_stairs":
				body = MoveStep.make_state(-12.0, 8.5, 0.0)
			for waypoint: Array in routes[route_name]:
				var goal: Vector3 = Vector3(waypoint[0], waypoint[1], waypoint[2])
				body = _walk_patient_detour(body, goal, patients, arena)
				_check(Vector3(body["x"], body["y"], body["z"]).distance_to(goal) < 0.3,
					"actual detour waypoint is reachable in both clinic worlds: " + route_name + " " + str(goal))
		var recovered: Dictionary = MoveStep.make_state(-18.61106, 2.92126, 0.0)
		recovered = _walk_patient_detour(recovered, Vector3(-19.75, 0, 10), patients, arena)
		_check(Vector2(float(recovered["x"]) + 19.75, float(recovered["z"]) - 10.0).length() < 0.3,
			"ordinary detour recovers from the actual failed capture feet")

func _walk_patient_detour(start: Dictionary, goal: Vector3, patients: Array[Dictionary], arena: Dictionary, allow_fall: bool = false, trace: Array[Dictionary] = []) -> Dictionary:
	var body: Dictionary = start.duplicate()
	for _tick: int in range(300):
		var delta: Vector2 = Vector2(goal.x - float(body["x"]), goal.z - float(body["z"]))
		if delta.length() < 0.2 and absf(float(body["y"]) - goal.y) < 0.03:
			break
		var action: Dictionary = MoveStep.make_input(true, false, false, false, atan2(delta.y, delta.x))
		var proposed: Dictionary = MoveStep.live_step(body, action, MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
		var bodies: Array[Dictionary] = [{"key": "human", "from": body, "proposed": proposed,
			"height": MoveStep.BODY_HEIGHT, "radius": MoveStep.RADIUS, "jump": false}]
		bodies.append_array(patients)
		body = ActorContact.resolve(bodies, MoveStep.DT_LIVE, arena)[0]
		if allow_fall:
			trace.append(body.duplicate())
		var support: float = MoveStep.arena_support_height(arena, float(body["x"]), float(body["z"]), float(body["y"]) + MoveStep.STEP_UP)
		var supported_or_falling: bool = float(body["y"]) >= support - 0.03 if allow_fall else absf(float(body["y"]) - support) < 0.03
		_check(supported_or_falling and not MoveStep.arena_blocked_body_at(arena, float(body["x"]), float(body["z"]), float(body["y"]), float(body["y"]) + MoveStep.STEP_UP),
			"detour preserves real supported body clearance: " + str(body) + " support=" + str(support))
		for patient: Dictionary in patients:
			if float(body["y"]) < float(patient["from"]["y"]) + float(patient["height"]):
				_check(Vector2(float(body["x"]) - float(patient["from"]["x"]), float(body["z"]) - float(patient["from"]["z"])).length() >= MoveStep.RADIUS + float(patient["radius"]) - 0.0001,
					"detour never walks through a living patient")
	return body

func _check_capture_handoff(authored: Dictionary, manifest: Dictionary, patients: Array[Dictionary], arena: Dictionary) -> void:
	var stages: Dictionary = {}
	for stage: Dictionary in manifest["states"]:
		stages[stage["name"]] = stage
	var mixed: Dictionary = {}
	var lesson: Dictionary = {}
	for encounter: Dictionary in authored["encounters"]:
		if encounter["id"] == "sweep_advance":
			mixed = encounter
		if encounter["id"] == "notary_lesson":
			lesson = encounter
	_check(not mixed.is_empty() and not lesson.is_empty(), "handoff uses actual lesson and mixed encounter definitions")
	if mixed.is_empty() or lesson.is_empty():
		return
	var body: Dictionary = MoveStep.make_state(-5.0, -14.0, 0.0)
	for name: String in ["notary_lesson_observation", "street_mixed_advance"]:
		for waypoint: Array in stages[name]["walk_to"]:
			var goal: Vector3 = Vector3(waypoint[0], waypoint[1], waypoint[2])
			body = _walk_patient_detour(body, goal, patients, arena)
			_check(Vector3(body["x"], body["y"], body["z"]).distance_to(goal) < 0.3, "safe capture handoff waypoint is ordinarily reachable " + str(goal))
			for region: Dictionary in mixed["regions"]:
				_check(not _capture_region_contains(region, Vector3(body["x"], body["y"], body["z"])), "quiet lesson and mixed approach stay outside next activation region")
		if name == "notary_lesson_observation":
			var feet: Array = lesson["enemies"][0]["feet"]
			var target: Vector3 = Vector3(feet[0], float(feet[1]) + AimAssist.NOTARY_HEIGHT * 0.5, feet[2])
			_check(AimAssist.line_of_sight(Vector3(body["x"], float(body["y"]) + MoveStep.EYE_HEIGHT, body["z"]), target, arena["solids"]), "new southern stance can actually see the lone Notary through world geometry")
	_check(stages["street_mixed_advance"]["combat_travel"] == false, "capture walks the safe approach before shooting the newly placed mixed guards")
	var approach: Array = stages["street_mixed_advance"]["combat"]["approach_route"]
	var west_sweeper: Dictionary = {}
	for enemy: Dictionary in mixed["enemies"]:
		if enemy["id"] == "advance_sweeper_a":
			west_sweeper = enemy
	_check(not west_sweeper.is_empty(), "western entry checks the actual closest fighter")
	if west_sweeper.is_empty():
		return
	var guard_feet: Array = west_sweeper["feet"]
	var approach_bodies: Array[Dictionary] = patients.duplicate()
	approach_bodies.append(ActorContact.stationary("advance_sweeper_a", Vector3(guard_feet[0], guard_feet[1], guard_feet[2])))
	var drop_trace: Array[Dictionary] = []
	for waypoint: Array in approach:
		var goal: Vector3 = Vector3(waypoint[0], waypoint[1], waypoint[2])
		body = _walk_patient_detour(body, goal, approach_bodies, arena, true, drop_trace)
		_check(Vector3(body["x"], body["y"], body["z"]).distance_to(goal) < 0.3, "observer's ordinary drop clears real stairs and nearest fighter")
	var first_entry: int = -1
	for index: int in range(drop_trace.size()):
		var feet: Vector3 = Vector3(drop_trace[index]["x"], drop_trace[index]["y"], drop_trace[index]["z"])
		for region: Dictionary in mixed["regions"]:
			if first_entry < 0 and _capture_region_contains(region, feet):
				first_entry = index
	_check(first_entry >= 0 and drop_trace.size() - first_entry < 14, "ordinary vertical arrival finishes before the existing fourteen-tick Standard Sweeper windup")
	var entered: bool = false
	for region: Dictionary in mixed["regions"]:
		entered = entered or _capture_region_contains(region, Vector3(body["x"], body["y"], body["z"]))
	_check(entered, "ordinary short approach genuinely enters the mixed encounter")
	_check(_capture_arrival_disk_inside(mixed["regions"], approach.back()), "unchanged half-metre mixed arrival disk stays inside actual encounter region")
	var west_drone: Dictionary = mixed["enemies"][0]
	var drone_feet: Array = west_drone["feet"]
	var drone_aim: Vector3 = Vector3(drone_feet[0], float(drone_feet[1]) + AimAssist.NOTARY_HEIGHT * 0.5, drone_feet[2])
	_check(not AimAssist.line_of_sight(Vector3(body["x"], float(body["y"]) + MoveStep.EYE_HEIGHT, body["z"]), drone_aim, arena["solids"]),
		"real southwest awning shelters the western drop from the high drone")
	_check(AimAssist.line_of_sight(Vector3(body["x"], float(body["y"]) + MoveStep.EYE_HEIGHT, body["z"]), Vector3(guard_feet[0], float(guard_feet[1]) + MoveStep.BODY_HEIGHT * 0.5, guard_feet[2]), arena["solids"]),
		"actual entry stance has a shot line to the closest western Sweeper")
	var search: Array = stages["street_mixed_advance"]["combat"]["search_route"][0]
	var peek: Vector3 = Vector3(search[0], search[1], search[2])
	body = _walk_patient_detour(body, peek, approach_bodies, arena)
	_check(Vector3(body["x"], body["y"], body["z"]).distance_to(peek) < 0.3, "existing first search point is ordinarily reachable from western cover")
	_check(AimAssist.line_of_sight(Vector3(body["x"], float(body["y"]) + MoveStep.EYE_HEIGHT, body["z"]), drone_aim, arena["solids"]),
		"existing grounded search exposes the covered western Notary")

func _capture_region_contains(region: Dictionary, feet: Vector3) -> bool:
	return feet.x >= float(region["min"][0]) and feet.x <= float(region["max"][0]) and feet.y >= float(region["min"][1]) and feet.y <= float(region["max"][1]) and feet.z >= float(region["min"][2]) and feet.z <= float(region["max"][2])

func _check_court_capture_approach(authored: Dictionary, manifest: Dictionary, patients: Array[Dictionary], arena: Dictionary) -> void:
	var stage: Dictionary = {}
	var encounter: Dictionary = {}
	for candidate: Dictionary in manifest["states"]:
		if candidate["name"] == "court_watch_ground":
			stage = candidate
	for candidate: Dictionary in authored["encounters"]:
		if candidate["id"] == "court_watch":
			encounter = candidate
	_check(not stage.is_empty() and not encounter.is_empty(), "court approach binds to actual capture and authored encounter")
	if stage.is_empty() or encounter.is_empty():
		return
	var required: Array[String] = []
	var authored_names: Array[String] = []
	var court_names: Array[String] = []
	var review: Dictionary = {}
	for group: Dictionary in authored["encounters"]:
		for enemy: Dictionary in group["enemies"]:
			authored_names.append(enemy["id"])
			if group["id"] == "court_watch":
				court_names.append(enemy["id"])
	for candidate: Dictionary in manifest["states"]:
		if candidate.has("combat"):
			for name: String in candidate["combat"]["required"]:
				_check(name not in required, "every actual required death appears exactly once")
				required.append(name)
		if candidate["name"] == "court_balcony_clerks":
			review = candidate
	required.sort()
	authored_names.sort()
	_check(required.size() == 28 and required == authored_names, "capture preserves all twenty-eight actual named guards")
	var captured_court: Array = stage["combat"]["required"].duplicate()
	captured_court.sort()
	court_names.sort()
	_check(captured_court.size() == 8 and captured_court == court_names and stage["combat"]["target_required_only"] == true, "court probe requires and permits all eight actual attackers")
	var objective_ids: Array[String] = []
	for objective: Dictionary in authored["m04"]["objectives"]:
		objective_ids.append(objective["id"])
	_check(not review.has("combat") and review.get("expect_m04_completed") == objective_ids,
		"later ordinary balcony review confirms actual completed prefix without demanding already-recorded fresh deaths")
	_check(stage["combat_travel"] == false, "court approach reaches finite supplies before waking guards with travel shots")
	var body: Dictionary = MoveStep.make_state(0.06970008, 14.961853, 0.0)
	var visits: Array[Vector3] = []
	for waypoint: Array in stage["walk_to"]:
		var goal: Vector3 = Vector3(waypoint[0], waypoint[1], waypoint[2])
		body = _walk_patient_detour(body, goal, patients, arena)
		var feet: Vector3 = Vector3(body["x"], body["y"], body["z"])
		_check(feet.distance_to(goal) < 0.3, "ordinary court supply approach remains supported " + str(goal))
		visits.append(feet)
		for region: Dictionary in encounter["regions"]:
			_check(not _capture_region_contains(region, feet), "court preparation remains outside actual activation region")
	for supply: Dictionary in authored["supplies"]:
		if supply["id"] in ["court_armor", "court_bullets", "court_shells"]:
			var pickup: Vector3 = Vector3(supply["feet"][0], supply["feet"][1], supply["feet"][2])
			var visited: bool = false
			for feet: Vector3 in visits:
				visited = visited or feet.distance_to(pickup) < 0.3
			_check(visited, "ordinary route reaches the actual finite court supply " + supply["id"])
	for waypoint: Array in stage["combat"]["approach_route"]:
		var goal: Vector3 = Vector3(waypoint[0], waypoint[1], waypoint[2])
		body = _walk_patient_detour(body, goal, patients, arena)
		_check(Vector3(body["x"], body["y"], body["z"]).distance_to(goal) < 0.3, "court observer approach remains ordinarily reachable " + str(goal))
	var feet: Vector3 = Vector3(body["x"], body["y"], body["z"])
	var entered: bool = false
	for region: Dictionary in encounter["regions"]:
		entered = entered or _capture_region_contains(region, feet)
	_check(entered, "court combat begins from a genuine ordinary region entry")
	_check(_capture_arrival_disk_inside(encounter["regions"], stage["combat"]["approach_route"].back()), "unchanged half-metre court arrival disk stays inside actual encounter region")
	var hostile: Dictionary = encounter["enemies"][0]
	var aim: Vector3 = Vector3(hostile["feet"][0], float(hostile["feet"][1]) + AimAssist.NOTARY_HEIGHT * 0.5, hostile["feet"][2])
	_check(AimAssist.line_of_sight(feet + Vector3.UP * MoveStep.EYE_HEIGHT, aim, arena["solids"]), "court entry stance can really aim at the western Notary")

func _capture_arrival_disk_inside(regions: Array, goal: Array) -> bool:
	for region: Dictionary in regions:
		if float(goal[0]) - 0.5 >= float(region["min"][0]) and float(goal[0]) + 0.5 <= float(region["max"][0]) and float(goal[2]) - 0.5 >= float(region["min"][2]) and float(goal[2]) + 0.5 <= float(region["max"][2]):
			return true
	return false

func _check_notice_capture_approach(authored: Dictionary, manifest: Dictionary, patients: Array[Dictionary], arena: Dictionary) -> void:
	var stage: Dictionary = {}
	var encounter: Dictionary = {}
	for candidate: Dictionary in manifest["states"]:
		if candidate["name"] == "notice_board_fight":
			stage = candidate
	for candidate: Dictionary in authored["encounters"]:
		if candidate["id"] == "notice_board_guards":
			encounter = candidate
	_check(not stage.is_empty() and not encounter.is_empty(), "notice entry binds to actual authored encounter and capture stage")
	if stage.is_empty() or encounter.is_empty():
		return
	var from: Array = stage["walk_to"].back()
	var body: Dictionary = MoveStep.make_state(from[0], from[2], 0.0)
	for region: Dictionary in encounter["regions"]:
		_check(not _capture_region_contains(region, Vector3(from[0], from[1], from[2])), "notice ordinary walking ends outside encounter before observer starts")
	for waypoint: Array in stage["combat"]["approach_route"]:
		var goal: Vector3 = Vector3(waypoint[0], waypoint[1], waypoint[2])
		body = _walk_patient_detour(body, goal, patients, arena)
		_check(Vector3(body["x"], body["y"], body["z"]).distance_to(goal) < 0.3, "notice observer entry uses ordinary supported movement")
	_check(_capture_arrival_disk_inside(encounter["regions"], stage["combat"]["approach_route"].back()), "unchanged half-metre notice arrival disk stays inside actual encounter region")
