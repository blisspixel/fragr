class_name M04MissionState
extends RefCounted

## Notice to Vacate facts remain authoritative; this validates presentation data.
const MAP_ID: int = 1004
const MAX_PATIENTS: int = 4
const MAX_ROUTE: int = 16
const ROUTE_EPSILON: float = 0.05
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const OBJECTIVES: Array[String] = ["notice_board_cleared", "first_notary_cleared", "street_wave_cleared",
	"market_wave_a_cleared", "market_wave_b_cleared", "court_cleared"]
const DEPARTURE: String = "party_departed"

static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("m04")
	if not M03MissionState._exact(value, ["clinic_open", "clinic", "patients", "objectives", "departure", "boarding", "companion_start"]) \
		or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null or info.has("m03") \
		or info.get("m02_side_ward", false) != false or not MapGeometry._number(info.get("half_extent")) \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	if half < 2.0 or half > MapGeometry.MAX_HALF or not value["clinic_open"] is bool \
		or not M03MissionState._exact(value["clinic"], ["control", "release"]) \
		or not _control(value["clinic"]["control"], decorations, half, ["terminal", "lift_control", "m04_clinic_control"]) \
		or not M03MissionState._region(value["clinic"]["release"], half) \
		or not M03MissionState._region(value["boarding"], half) \
		or not _control(value["departure"], decorations, half, ["lift_control", "m04_roof_departure"]) \
		or int(value["clinic"]["control"]["decoration"]) == int(value["departure"]["decoration"]) \
		or not M03MissionState._inside(value["departure"]["approach"], value["boarding"]) \
		or not MissionState._point(value["companion_start"], half) \
		or not value["objectives"] is Array or value["objectives"].size() != OBJECTIVES.size() \
		or not value["patients"] is Array or value["patients"].is_empty() or value["patients"].size() > MAX_PATIENTS:
		return MissionState.INVALID
	for index: int in range(OBJECTIVES.size()):
		var objective: Variant = value["objectives"][index]
		if not M03MissionState._exact(objective, ["id", "action"]) or objective["id"] != OBJECTIVES[index] \
			or not M03MissionState._exact(objective["action"], ["kind", "region", "feet"]) \
			or objective["action"]["kind"] != "arrival" \
			or not M03MissionState._region(objective["action"]["region"], half) \
			or not MissionState._point(objective["action"]["feet"], half) \
			or not M03MissionState._inside(objective["action"]["feet"], objective["action"]["region"]):
			return MissionState.INVALID
	var ids: Array[String] = []
	for patient: Variant in value["patients"]:
		if not M03MissionState._exact(patient, ["id", "held", "route"]) or not MissionState.valid_objective_id(patient["id"]) \
			or patient["id"] in ids or not MissionState._point(patient["held"], half) \
			or not patient["route"] is Array or patient["route"].size() < 2 or patient["route"].size() > MAX_ROUTE:
			return MissionState.INVALID
		ids.append(patient["id"])
		for point: Variant in patient["route"]:
			if not MissionState._point(point, half) or absf(float(point[1]) - float(patient["held"][1])) > 0.01:
				return MissionState.INVALID
		if not M03MissionState._same_point(patient["held"], patient["route"][0]) or not _unambiguous_route(patient["route"]):
			return MissionState.INVALID
	return ""

## Match the server's 0.05 m walking corridor without ambiguous progress.
static func _unambiguous_route(route: Array) -> bool:
	var points: Array[Vector2] = []
	for point: Array in route:
		points.append(Vector2(float(point[0]), float(point[2])))
	for index: int in range(points.size() - 1):
		if points[index].distance_to(points[index + 1]) <= 0.1:
			return false
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var end: Vector2 = points[index + 1]
		if index + 2 < points.size() and absf((end - start).cross(points[index + 2] - start)) <= 0.0001 \
			and (end - start).dot(points[index + 2] - end) < 0.0:
			return false
		for other: int in range(index + 2, points.size() - 1):
			var a: Vector2 = points[other]
			var b: Vector2 = points[other + 1]
			if (end - start).cross(a - start) * (end - start).cross(b - start) < 0.0 \
				and (b - a).cross(start - a) * (b - a).cross(end - a) < 0.0:
				return false
			if minf(minf(_segment_distance(start, a, b), _segment_distance(end, a, b)),
				minf(_segment_distance(a, start, end), _segment_distance(b, start, end))) <= 0.1:
				return false
	return true

static func _segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	return point.distance_to(start + segment * clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0))

static func _control(value: Variant, decorations: Array, half: float, kinds: Array[String]) -> bool:
	return M03MissionState._exact(value, ["decoration", "approach"]) and not decorations.is_empty() \
		and EquipmentState.integer(value["decoration"], decorations.size() - 1) \
		and decorations[int(value["decoration"])] is Dictionary \
		and decorations[int(value["decoration"])].get("kind") in kinds and MissionState._point(value["approach"], half)

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M04_ID, "map_id": int(info["map_id"]), "half_extent": float(info["half_extent"]), "m04": info["m04"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M04_ID or second.get("id") != MissionState.M04_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m04") is Dictionary or not second.get("m04") is Dictionary:
		return false
	var before: Dictionary = first["m04"].duplicate(true)
	var after: Dictionary = second["m04"].duplicate(true)
	before.erase("clinic_open")
	after.erase("clinic_open")
	return before == after

## Nearest cumulative route distance, or negative when the registered path misses.
static func route_progress(point: Array, route: Array) -> float:
	var current: Vector3 = _vector(point)
	var walked: float = 0.0
	var best: float = INF
	var progress: float = -1.0
	for index: int in range(1, route.size()):
		var start: Vector3 = _vector(route[index - 1])
		var segment: Vector3 = _vector(route[index]) - start
		var length: float = segment.length()
		var fraction: float = clampf((current - start).dot(segment) / segment.length_squared(), 0.0, 1.0) if length > 0.0 else 0.0
		var distance: float = current.distance_to(start + segment * fraction)
		if distance < best:
			best = distance
			progress = walked + length * fraction
		walked += length
	return progress if best <= ROUTE_EPSILON else -1.0

static func _vector(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m04"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M04_ID or geometry.get("id") != MissionState.M04_ID \
		or not geometry.get("m04") is Dictionary or not MissionState.valid_rules(value["rules"]) \
		or not value["phase"] is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m04"]
	var progress: Variant = value["m04"]
	var departed: bool = value["phase"] == "departed"
	var progress_keys: Array[String] = ["completed", "clinic_secured", "clinic_open", "patients_released", "patients", "photos_completed", "carried_recall_cars"]
	if not departed:
		progress_keys.append("current")
	if not M03MissionState._exact(progress, progress_keys) or not progress["completed"] is Array \
		or not progress["clinic_secured"] is bool or not progress["clinic_open"] is bool or progress["clinic_open"] != bound["clinic_open"] \
		or (progress["clinic_open"] and not progress["clinic_secured"]) \
		or not progress["patients_released"] is bool or (progress["patients_released"] and (not progress["clinic_secured"] or not progress["clinic_open"])) \
		or not EquipmentState.integer(progress["photos_completed"], 1000000) \
		or not progress["patients"] is Array or progress["patients"].size() != bound["patients"].size() \
		or not progress["carried_recall_cars"] is Array or progress["carried_recall_cars"].size() > 4:
		return MissionState.INVALID
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append(DEPARTURE)
	var completed: Array = progress["completed"]
	if completed.size() > order.size() or departed != (completed.size() == order.size()):
		return MissionState.INVALID
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return MissionState.INVALID
	if not departed:
		var expected: Dictionary = bound["objectives"][completed.size()] if completed.size() < OBJECTIVES.size() else {
			"id": DEPARTURE, "action": {"kind": "use", "target": bound["departure"]}}
		if progress["current"] != expected:
			return MissionState.INVALID
	if value["phase"] == "briefing" and (not completed.is_empty() or progress["clinic_secured"] or progress["clinic_open"] \
		or progress["patients_released"] or int(progress["photos_completed"]) != 0):
		return MissionState.INVALID
	var cars: Array[String] = []
	for id: Variant in progress["carried_recall_cars"]:
		if not MissionState.valid_objective_id(id) or id in cars:
			return MissionState.INVALID
		cars.append(id)
	for index: int in range(progress["patients"].size()):
		var patient: Variant = progress["patients"][index]
		var definition: Dictionary = bound["patients"][index]
		if not M03MissionState._exact(patient, ["id", "feet"]) or patient["id"] != definition["id"] \
			or not MissionState._point(patient["feet"], float(geometry["half_extent"])) \
			or (not progress["patients_released"] and not M03MissionState._same_point(patient["feet"], definition["held"])) \
			or (progress["patients_released"] and route_progress(patient["feet"], definition["route"]) < 0.0):
			return MissionState.INVALID
	var party: Dictionary = {}
	var aboard: bool = not value["party"].is_empty()
	for member: Variant in value["party"]:
		if not M03MissionState._exact(member, ["id", "name", "ready", "alive", "aboard"]) or not MissionState._uuid(member["id"]) \
			or party.has(member["id"]) or not member["name"] is String or member["name"].is_empty() or member["name"].length() > 48 \
			or not member["ready"] is bool or not member["alive"] is bool or not member["aboard"] is bool \
			or (member["aboard"] and (not member["ready"] or not member["alive"] or value["phase"] == "briefing")):
			return MissionState.INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return MissionState.INVALID
		party[member["id"]] = member
		aboard = aboard and member["ready"] and member["alive"] and member["aboard"]
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if value["phase"] != "in_progress" or not M03MissionState._exact(prompt, ["player_id", "kind"]) \
			or prompt["kind"] not in ["objective_use", "clinic_shutter"] or not prompt["player_id"] is String \
			or not party.has(prompt["player_id"]) or prompt["player_id"] in prompted \
			or not party[prompt["player_id"]]["alive"] or not party[prompt["player_id"]]["ready"]:
			return MissionState.INVALID
		# A legal clinic control is optional, independently of the current encounter.
		if (prompt["kind"] == "objective_use" and (completed.size() != OBJECTIVES.size() or not aboard)) \
			or (prompt["kind"] == "clinic_shutter" and (not progress["clinic_secured"] or progress["clinic_open"])):
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M04_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")) \
			or progress["carried_recall_cars"] != old["m04"]["carried_recall_cars"]:
			return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			var before: Dictionary = old["m04"]
			if completed.size() < before["completed"].size() or int(value["changed_at"]) < int(old["changed_at"]) \
				or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(progress["photos_completed"]) < int(before["photos_completed"]):
				return MissionState.INVALID
			for flag: String in ["clinic_secured", "clinic_open", "patients_released"]:
				if before[flag] and not progress[flag]:
					return MissionState.INVALID
			if progress["patients_released"] and before["patients_released"]:
				for index: int in range(progress["patients"].size()):
					var route: Array = bound["patients"][index]["route"]
					if route_progress(progress["patients"][index]["feet"], route) + ROUTE_EPSILON < route_progress(before["patients"][index]["feet"], route):
						return MissionState.INVALID
	return ""
