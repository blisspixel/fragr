class_name M10MissionState
extends RefCounted

## Working ship facts are authoritative; this validates their presentation.
const MAP_ID: int = 1010
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const OBJECTIVES: Array[String] = ["forward_secured", "service_secured", "aft_secured", "passengers_secured"]
const DEPARTURE: String = "party_departed"
const RETAINED: Array[String] = ["transit", "pilot", "passengers"]
const CREW: Array[String] = ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"]
const PASSENGERS: Array[String] = ["berth_crew_a", "berth_crew_b", "edda", "splice"]
static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("m10")
	if not M03MissionState._exact(value, ["objectives", "departure", "boarding", "pilot", "companion_start", "passengers"]) \
		or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null \
		or info.has("m03") or info.has("m04") or info.has("m05") or info.has("m06") or info.has("m08") or info.has("m07") or info.has("m09") \
		or (info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"])) \
		or not MapGeometry._number(info.get("half_extent")) \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	if half < 2.0 or half > MapGeometry.MAX_HALF or not value["objectives"] is Array \
		or value["objectives"].size() != OBJECTIVES.size() \
		or not M03MissionState._region(value["boarding"], half) \
		or not M04MissionState._control(value["departure"], info["presentation"]["decorations"], half,
			["m10_ship_confirmation"]) \
		or not M03MissionState._inside(value["departure"]["approach"], value["boarding"]) \
		or not MissionState._point(value["pilot"], half) or not MissionState._point(value["companion_start"], half):
		return MissionState.INVALID
	if not value["passengers"] is Array or value["passengers"].size() != PASSENGERS.size():
		return MissionState.INVALID
	for i: int in range(PASSENGERS.size()):
		var person: Variant = value["passengers"][i]
		if not M03MissionState._exact(person, ["id", "feet"]) or person["id"] != PASSENGERS[i] or not MissionState._point(person["feet"], half):
			return MissionState.INVALID
	for index: int in range(OBJECTIVES.size()):
		if not M06MissionState._arrival(value["objectives"][index], OBJECTIVES[index], half):
			return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M10_ID, "map_id": int(info["map_id"]),
		"half_extent": float(info["half_extent"]), "m10": info["m10"].duplicate(true),
		"solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	return first.get("id") == MissionState.M10_ID and second.get("id") == MissionState.M10_ID \
		and first.get("map_id") == second.get("map_id") and first.get("half_extent") == second.get("half_extent") \
		and first.get("m10") is Dictionary and second.get("m10") is Dictionary and first["m10"] == second["m10"] \
		and first.get("solids") == second.get("solids") and first.get("presentation") == second.get("presentation")

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m10"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M10_ID \
		or geometry.get("id") != MissionState.M10_ID or not geometry.get("m10") is Dictionary \
		or not MissionState.valid_rules(value["rules"]) or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m10"]
	var progress: Variant = value["m10"]
	var departed: bool = value["phase"] == "departed"
	var progress_keys: Array[String] = RETAINED.duplicate()
	progress_keys.append("completed")
	if not departed:
		progress_keys.append("current")
	if progress is Dictionary and progress.has("carried_archive"):
		progress_keys.append("carried_archive")
	if not M03MissionState._exact(progress, progress_keys) or not progress["completed"] is Array or not _transit(progress["transit"]) \
		or progress["pilot"] != bound["pilot"] or (progress.has("carried_archive") and not M09MissionState._archive(progress["carried_archive"])):
		return MissionState.INVALID
	var expected_people: Array[Dictionary] = []
	for person: Dictionary in bound["passengers"]:
		if progress["transit"].get("arrived_crew", []).has(person["id"]):
			expected_people.append(person)
	if progress["passengers"] != expected_people:
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
	if value["phase"] == "briefing" and not completed.is_empty():
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
		if old.get("id") != MissionState.M10_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		var before: Dictionary = old["m10"]
		if progress.get("carried_archive") != before.get("carried_archive"):
			return MissionState.INVALID
		for retained: String in RETAINED:
			if progress[retained] != before[retained]:
				return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			if completed.size() < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]):
				return MissionState.INVALID
	return ""

static func _transit(value: Variant) -> bool:
	if M03MissionState._exact(value, ["kind"]) and value["kind"] == "historical_unrecorded":
		return true
	if not M03MissionState._exact(value, ["kind", "arrived_crew"]) or value["kind"] != "recorded" \
		or not value["arrived_crew"] is Array or value["arrived_crew"].size() < 3 or value["arrived_crew"].size() > 5:
		return false
	var arrivals: Array = value["arrived_crew"]
	if arrivals.slice(0, 3) != CREW.slice(0, 3):
		return false
	var next: int = 0
	for id: Variant in arrivals:
		if not id is String:
			return false
		var found: int = CREW.find(id, next)
		if found < 0:
			return false
		next = found + 1
	return true