class_name M06MissionState
extends RefCounted

## Lunar mission facts are authoritative; this only validates the presentation.
const MAP_ID: int = 1006
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const OBJECTIVES: Array[String] = ["freight_cleared", "rail_lane_cleared", "loading_cleared",
	"turret_cleared", "customs_cleared", "exit_cleared"]
const DEPARTURE: String = "party_departed"
const SERVICE: String = "prisoner_route_marked"
const RETAINED: Array[String] = ["carried_recall_cars", "carried_patients", "carried_photos",
	"carried_released_workers", "carried_evacuated_workers"]

static func _arrival(value: Variant, id: String, half: float) -> bool:
	return M03MissionState._exact(value, ["id", "action"]) and value["id"] == id \
		and M03MissionState._exact(value["action"], ["kind", "region", "feet"]) \
		and value["action"]["kind"] == "arrival" \
		and M03MissionState._region(value["action"]["region"], half) \
		and MissionState._point(value["action"]["feet"], half) \
		and M03MissionState._inside(value["action"]["feet"], value["action"]["region"])

static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("m06")
	if not M03MissionState._exact(value, ["objectives", "service", "departure", "boarding", "companion_start"]) \
		or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null \
		or info.has("m03") or info.has("m04") or info.has("m05") \
		or (info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"])) \
		or not MapGeometry._number(info.get("half_extent")) \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	if half < 2.0 or half > MapGeometry.MAX_HALF or not value["objectives"] is Array \
		or value["objectives"].size() != OBJECTIVES.size() \
		or not _arrival(value["service"], SERVICE, half) \
		or not M03MissionState._region(value["boarding"], half) \
		or not M04MissionState._control(value["departure"], info["presentation"]["decorations"], half,
			["lift_control", "m06_transit_departure"]) \
		or not M03MissionState._inside(value["departure"]["approach"], value["boarding"]) \
		or not MissionState._point(value["companion_start"], half):
		return MissionState.INVALID
	for index: int in range(OBJECTIVES.size()):
		if not _arrival(value["objectives"][index], OBJECTIVES[index], half):
			return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M06_ID, "map_id": int(info["map_id"]),
		"half_extent": float(info["half_extent"]), "m06": info["m06"].duplicate(true),
		"solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	return first.get("id") == MissionState.M06_ID and second.get("id") == MissionState.M06_ID \
		and first.get("map_id") == second.get("map_id") and first.get("half_extent") == second.get("half_extent") \
		and first.get("m06") is Dictionary and second.get("m06") is Dictionary and first["m06"] == second["m06"] \
		and first.get("solids") == second.get("solids") and first.get("presentation") == second.get("presentation")

static func _ids(value: Variant, maximum: int, whitelist: Array[String] = []) -> bool:
	if not value is Array or value.size() > maximum:
		return false
	var seen: Array[String] = []
	for id: Variant in value:
		if not MissionState.valid_objective_id(id) or id in seen or (not whitelist.is_empty() and id not in whitelist):
			return false
		seen.append(id)
	return true

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m06"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M06_ID \
		or geometry.get("id") != MissionState.M06_ID or not geometry.get("m06") is Dictionary \
		or not MissionState.valid_rules(value["rules"]) or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m06"]
	var progress: Variant = value["m06"]
	var departed: bool = value["phase"] == "departed"
	var progress_keys: Array[String] = RETAINED.duplicate()
	progress_keys.append_array(["completed", "prisoner_route_marked"])
	if not departed:
		progress_keys.append("current")
	if not M03MissionState._exact(progress, progress_keys) or not progress["completed"] is Array \
		or not progress["prisoner_route_marked"] is bool \
		or not _ids(progress["carried_recall_cars"], 4) or not _ids(progress["carried_patients"], 4) \
		or not EquipmentState.integer(progress["carried_photos"], 1000000) \
		or not _ids(progress["carried_released_workers"], 3, M05MissionState.WORKERS) \
		or not _ids(progress["carried_evacuated_workers"], 3, M05MissionState.WORKERS) \
		or progress["carried_released_workers"].size() not in [0, 3]:
		return MissionState.INVALID
	for id: String in progress["carried_evacuated_workers"]:
		if id not in progress["carried_released_workers"]:
			return MissionState.INVALID
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append(DEPARTURE)
	var completed: Array = progress["completed"]
	if completed.size() > order.size() or departed != (completed.size() == order.size()) \
		or (progress["prisoner_route_marked"] and completed.size() < 3):
		return MissionState.INVALID
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return MissionState.INVALID
	if not departed:
		var expected: Dictionary = bound["objectives"][completed.size()] if completed.size() < OBJECTIVES.size() else {
			"id": DEPARTURE, "action": {"kind": "use", "target": bound["departure"]}}
		if progress["current"] != expected:
			return MissionState.INVALID
	if value["phase"] == "briefing" and (not completed.is_empty() or progress["prisoner_route_marked"]):
		return MissionState.INVALID
	var party: Dictionary = {}
	var aboard: bool = not value["party"].is_empty()
	for member: Variant in value["party"]:
		if not M03MissionState._exact(member, ["id", "name", "ready", "alive", "aboard"]) \
			or not MissionState._uuid(member["id"]) or party.has(member["id"]) \
			or not member["name"] is String or member["name"].is_empty() or member["name"].length() > 48 \
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
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or value["phase"] != "in_progress" or not party.has(prompt["player_id"]) \
			or prompt["player_id"] in prompted or not aboard or completed.size() != OBJECTIVES.size():
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M06_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		var before: Dictionary = old["m06"]
		for retained: String in RETAINED:
			if progress[retained] != before[retained]:
				return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			if completed.size() < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]) \
				or (before["prisoner_route_marked"] and not progress["prisoner_route_marked"]):
				return MissionState.INVALID
	return ""
