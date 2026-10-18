class_name M16MissionState
extends RefCounted

## Freedom of Movement facts bind the connected avenue progression, motorcycle traversal and departure.
const MAP_ID: int = 1016
const OBJECTIVES: Array[String] = [
	"ride_started",
	"barricade_broken",
	"green_wave_triggered",
	"bus_freed",
	"forecourt_secured",
	"doors_reached",
]
const DEPARTURE_OBJECTIVE_ID: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("m16")
	if not M03MissionState._exact(g, ["objectives", "departure", "boarding", "bus_release", "motorcycle", "checkpoint_lifted", "doors_open"]) \
		or not g["checkpoint_lifted"] is bool or not g["doors_open"] is bool \
		or not g["objectives"] is Array or g["objectives"].size() != OBJECTIVES.size():
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	# Objectives 0, 1, 2, 4, 5: Arrival
	for idx: int in [0, 1, 2, 4, 5]:
		if not M06MissionState._arrival(g["objectives"][idx], OBJECTIVES[idx], half):
			return MissionState.INVALID
	# Objective 3: bus_freed (use bus_release target)
	if not _use(g["objectives"][3], OBJECTIVES[3], g["bus_release"], decorations, half, ["terminal", "lift_control", "union_seal"]):
		return MissionState.INVALID
	if not M03MissionState._region(g["boarding"], half) \
		or not M04MissionState._control(g["departure"], decorations, half, ["terminal", "lift_control", "union_seal"]) \
		or not M03MissionState._inside(g["departure"]["approach"], g["boarding"]):
		return MissionState.INVALID
	if not M04MissionState._control(g["bus_release"], decorations, half, ["terminal", "lift_control", "union_seal"]):
		return MissionState.INVALID
	var moto: Variant = g.get("motorcycle")
	if not moto is Dictionary or not M03MissionState._exact(moto, ["feet", "yaw"]) \
		or not MissionState._point(moto["feet"], half) \
		or not (moto["yaw"] is int or moto["yaw"] is float):
		return MissionState.INVALID
	return ""

static func _use(value: Variant, id: String, expected_target: Dictionary, decorations: Array, half: float, kinds: Array[String]) -> bool:
	return M03MissionState._exact(value, ["id", "action"]) and value["id"] == id \
		and M03MissionState._exact(value["action"], ["kind", "target"]) \
		and value["action"]["kind"] == "use" \
		and value["action"]["target"] == expected_target \
		and M04MissionState._control(value["action"]["target"], decorations, half, kinds)

static func geometry_for(info: Dictionary) -> Dictionary:
	return {
		"id": MissionState.M16_ID,
		"map_id": MAP_ID,
		"half_extent": float(info["half_extent"]),
		"m16": info["m16"].duplicate(true),
		"solids": info["solids"].duplicate(true),
		"presentation": info["presentation"].duplicate(true)
	}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M16_ID or second.get("id") != MissionState.M16_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m16") is Dictionary or not second.get("m16") is Dictionary:
		return false
	var before: Dictionary = first["m16"].duplicate(true)
	var after: Dictionary = second["m16"].duplicate(true)
	for flag: String in ["checkpoint_lifted", "doors_open"]:
		before.erase(flag)
		after.erase(flag)
	return before == after

static func challenge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, ["ride_started", "green_wave_triggered", "bus_freed"]):
		return MissionState.INVALID
	for key: String in value:
		if not value[key] is bool:
			return MissionState.INVALID
	return MissionState.INVALID if value["green_wave_triggered"] and not value["ride_started"] else ""

static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value["ride_started"] and (difficulty == "assisted" or (value["green_wave_triggered"] and (difficulty != "severe" or value["bus_freed"])))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "checkpoint_lifted", "doors_open", "bus_freed", "forecourt_secured"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if not M03MissionState._exact(value, keys):
		return MissionState.INVALID
	if not MissionState.ordered_facts_error(value, OBJECTIVES, [3], phase, tick).is_empty():
		return MissionState.INVALID
	for key: String in ["checkpoint_lifted", "doors_open", "bus_freed", "forecourt_secured"]:
		if not value[key] is bool:
			return MissionState.INVALID
	var challenge_problem: String = challenge_error(value.get("challenges"))
	if not challenge_problem.is_empty():
		return challenge_problem
	var n: int = value["completed"].size()
	if value["bus_freed"] != value["challenges"]["bus_freed"] or (n >= 1) != value["challenges"]["ride_started"] \
		or (n >= 3) != value["checkpoint_lifted"] or value["checkpoint_lifted"] != value["challenges"]["green_wave_triggered"] \
		or (n >= 5) != value["forecourt_secured"] or (n >= 6) != value["doors_open"]:
		return MissionState.INVALID
	if not value.get("completed") is Array or value["completed"].size() > OBJECTIVES.size() + 1:
		return MissionState.INVALID
	for i: int in range(value["completed"].size()):
		if i < OBJECTIVES.size():
			if value["completed"][i] != OBJECTIVES[i]:
				return MissionState.INVALID
		elif i == OBJECTIVES.size():
			if value["completed"][i] != DEPARTURE_OBJECTIVE_ID:
				return MissionState.INVALID
		else:
			return MissionState.INVALID
	var current: Variant = value.get("current")
	if phase == "departed":
		if current != null or value["completed"].size() != OBJECTIVES.size() + 1:
			return MissionState.INVALID
		if not value["doors_open"] or not value["forecourt_secured"] or tick == 0:
			return MissionState.INVALID
	elif phase == "briefing":
		if not value["completed"].is_empty() or value["checkpoint_lifted"] or value["doors_open"] or value["bus_freed"] or value["forecourt_secured"]:
			return MissionState.INVALID
	elif current != null:
		if value["completed"].size() < OBJECTIVES.size():
			var expected_id: String = OBJECTIVES[value["completed"].size()]
			if not current is Dictionary or current.get("id") != expected_id:
				return MissionState.INVALID
		elif value["completed"].size() == OBJECTIVES.size():
			if not current is Dictionary or current.get("id") != DEPARTURE_OBJECTIVE_ID:
				return MissionState.INVALID
		else:
			return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not message.get("state") is Dictionary:
		return MissionState.INVALID
	var value: Dictionary = message["state"]
	if geometry.get("id") != MissionState.M16_ID or value.get("id") != MissionState.M16_ID \
		or not MissionState.valid_rules(value.get("rules")) \
		or not value.get("phase") is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value.get("attempt"), 4294967295) or int(value["attempt"]) == 0 \
		or not EquipmentState.integer(value.get("changed_at"), int(message["tick"])) \
		or not value.get("party") is Array or value["party"].size() > 4 \
		or not value.get("prompts") is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var run: Variant = value.get("run")
	if run != null and not MissionState.valid_run_identity(run, value["attempt"]):
		return MissionState.INVALID
	if not previous.is_empty() and (int(value["attempt"]) < int(previous["state"]["attempt"]) \
		or int(message["tick"]) < int(previous["tick"]) or value["rules"] != previous["state"]["rules"] \
		or not MissionState.run_follows(run, previous["state"].get("run"))):
		return MissionState.INVALID
	var party: Dictionary = {}
	var ready: bool = true
	for member: Variant in value["party"]:
		if not member is Dictionary or member.size() != 5 or not MissionState._uuid(member.get("id")) \
			or party.has(member["id"]) or not member.get("name") is String \
			or member["name"].is_empty() or member["name"].length() > 48 \
			or not member.get("ready") is bool or not member.get("alive") is bool or not member.get("aboard") is bool \
			or (member["aboard"] and (not member["alive"] or not member["ready"] or value["phase"] == "briefing")):
			return MissionState.INVALID
		party[member["id"]] = member
		ready = ready and member["alive"] and member["aboard"]
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not prompt is Dictionary or prompt.size() != 2 or not MissionState._uuid(prompt.get("player_id")) \
			or not party.has(prompt["player_id"]) or not party[prompt["player_id"]]["alive"] \
			or not party[prompt["player_id"]]["ready"] \
			or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	for key: String in ["m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15"]:
		if value.has(key) and value[key] != null:
			return MissionState.INVALID
	var facts: Variant = value.get("m16")
	if facts == null:
		return MissionState.INVALID
	var problem: String = facts_error(facts, value["phase"], int(message["tick"]))
	if not problem.is_empty():
		return problem
	return MissionState.late_contract_error(message, geometry, previous, "m16", {"checkpoint_lifted": "checkpoint_lifted", "doors_open": "doors_open"})
