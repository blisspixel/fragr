class_name M18MissionState
extends RefCounted

## All Systems Normal facts bind the connected Episode V Recovery Square, diagnostic rupture, maintenance ascent, Upper Overlook, and Evacuation Concourse departure.
const MAP_ID: int = 1018
const OBJECTIVES: Array[String] = [
	"aid_checkin",
	"square_defense",
	"collector_breach",
	"service_ascent",
	"overlook_recon",
	"concourse_evac",
]
const DEPARTURE_OBJECTIVE_ID: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15", "m16", "m17"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("m18")
	if not M03MissionState._exact(g, ["objectives", "departure", "boarding", "depot_station", "overlook_console", "roadblock_active", "concourse_evac_completed"]) \
		or not g["roadblock_active"] is bool or not g["concourse_evac_completed"] is bool \
		or not g["objectives"] is Array or g["objectives"].size() != OBJECTIVES.size():
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	# Objective 0: aid_checkin (Use depot_station)
	if not _use(g["objectives"][0], OBJECTIVES[0], g["depot_station"], decorations, half, ["terminal", "lift_control", "union_seal", "records_sign"]):
		return MissionState.INVALID
	# Objective 4: overlook_recon (Use overlook_console)
	if not _use(g["objectives"][4], OBJECTIVES[4], g["overlook_console"], decorations, half, ["terminal", "lift_control", "union_seal", "records_sign"]):
		return MissionState.INVALID
	# Objectives 1, 2, 3, 5: Arrival
	for idx: int in [1, 2, 3, 5]:
		if not M06MissionState._arrival(g["objectives"][idx], OBJECTIVES[idx], half):
			return MissionState.INVALID
	if not M03MissionState._region(g["boarding"], half) \
		or not M04MissionState._control(g["departure"], decorations, half, ["terminal", "lift_control", "union_seal", "records_sign"]) \
		or not M03MissionState._inside(g["departure"]["approach"], g["boarding"]):
		return MissionState.INVALID
	if not M04MissionState._control(g["depot_station"], decorations, half, ["terminal", "lift_control", "union_seal", "records_sign"]) \
		or not M04MissionState._control(g["overlook_console"], decorations, half, ["terminal", "lift_control", "union_seal", "records_sign"]):
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
		"id": MissionState.M18_ID,
		"map_id": MAP_ID,
		"half_extent": float(info["half_extent"]),
		"m18": info["m18"].duplicate(true),
		"solids": info["solids"].duplicate(true),
		"presentation": info["presentation"].duplicate(true)
	}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M18_ID or second.get("id") != MissionState.M18_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m18") is Dictionary or not second.get("m18") is Dictionary:
		return false
	var before: Dictionary = first["m18"].duplicate(true)
	var after: Dictionary = second["m18"].duplicate(true)
	for flag: String in ["roadblock_active", "concourse_evac_completed"]:
		before.erase(flag)
		after.erase(flag)
	return before == after

static func challenge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, ["aid_delivered", "square_defended", "collector_neutralized", "overlook_witnessed", "concourse_secured"]):
		return MissionState.INVALID
	for key: String in value:
		if not value[key] is bool:
			return MissionState.INVALID
	if value["concourse_secured"] and not value["square_defended"]:
		return MissionState.INVALID
	if value["overlook_witnessed"] and not value["square_defended"]:
		return MissionState.INVALID
	return ""

static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value["square_defended"] and (difficulty == "assisted" or (value["concourse_secured"] and (difficulty != "severe" or (value["aid_delivered"] and value["collector_neutralized"] and value["overlook_witnessed"]))))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "roadblock_active", "aid_delivered", "overlook_witnessed", "concourse_secured", "brief_completed", "turn_started"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if not M03MissionState._exact(value, keys):
		return MissionState.INVALID
	if not MissionState.ordered_facts_error(value, OBJECTIVES, [0, 4], phase, tick).is_empty():
		return MissionState.INVALID
	for key: String in ["roadblock_active", "aid_delivered", "overlook_witnessed", "concourse_secured", "brief_completed"]:
		if not value[key] is bool:
			return MissionState.INVALID
	# The delivery begins the turn on its own tick; a turn never runs ahead of the clock.
	var turn: Variant = value["turn_started"]
	if turn != null and not EquipmentState.integer(turn, tick):
		return MissionState.INVALID
	if (turn != null) != value["aid_delivered"]:
		return MissionState.INVALID
	var challenge_problem: String = challenge_error(value.get("challenges"))
	if not challenge_problem.is_empty():
		return challenge_problem
	var n: int = value["completed"].size()
	if (n >= 1) != value["challenges"]["aid_delivered"] or value["aid_delivered"] != value["challenges"]["aid_delivered"] or (n >= 2) != value["challenges"]["square_defended"] \
		or (n >= 3) != value["challenges"]["collector_neutralized"] or (n >= 3) != value["roadblock_active"] \
		or (n >= 5) != value["overlook_witnessed"] or value["overlook_witnessed"] != value["challenges"]["overlook_witnessed"] \
		or (n >= 6) != value["concourse_secured"] or value["concourse_secured"] != value["challenges"]["concourse_secured"]:
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
		if not value["concourse_secured"] or tick == 0:
			return MissionState.INVALID
	elif phase == "briefing":
		if not value["completed"].is_empty() or value["roadblock_active"] or value["overlook_witnessed"] or value["concourse_secured"]:
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
	if geometry.get("id") != MissionState.M18_ID or value.get("id") != MissionState.M18_ID \
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
	for key: String in ["m02", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15", "m16", "m17"]:
		if value.has(key) and value[key] != null:
			return MissionState.INVALID
	var facts: Variant = value.get("m18")
	if facts == null:
		return MissionState.INVALID
	var problem: String = facts_error(facts, value["phase"], int(message["tick"]))
	if not problem.is_empty():
		return problem
	if facts["brief_completed"] != brief_completed(facts["challenges"], value["rules"]["difficulty"]):
		return MissionState.INVALID
	return MissionState.late_contract_error(message, geometry, previous, "m18", {"roadblock_active": "roadblock_active", "concourse_secured": "concourse_evac_completed"})
