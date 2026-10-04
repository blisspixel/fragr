class_name M09MissionState
extends RefCounted

## The berth server owns gates, crew feet and departure. This checks their shape.
const MAP_ID: int = 1009
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const OBJECTIVES: Array[String] = ["loading_cleared", "lesson_cleared", "crew_freed", "gantry_one_cleared", "gantry_two_cleared", "gantry_three_cleared", "clamps_released", "hatch_cleared"]
const CREW: Array[String] = ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"]
const ARRIVALS: Array[int] = [0, 1, 3, 4, 5, 6, 7]
const GEOMETRY: Array[String] = ["objectives", "crew_release", "crew", "departure", "boarding", "companion_start", "hatch", "hatch_open"]

static func step(bound: Dictionary, index: int) -> Dictionary:
	if index == 2 or index == 8:
		return {"id": "crew_freed" if index == 2 else "party_departed", "action": {"kind": "use", "target": bound["crew_release" if index == 2 else "departure"]}}
	if index in ARRIVALS:
		return bound["objectives"][ARRIVALS.find(index)]
	return {}

static func map_error(info: Dictionary) -> String:
	var raw: Variant = info.get("m09")
	if not MapGeometry.validation_error(info).is_empty() or not M03MissionState._exact(raw, GEOMETRY) \
		or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["m03", "m04", "m05", "m06", "m07", "m08"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"]):
		return MissionState.INVALID
	var bound: Dictionary = raw
	var half: float = float(info["half_extent"])
	var details: Array = info["presentation"]["decorations"]
	if not bound["objectives"] is Array or bound["objectives"].size() != 7 \
		or not bound["crew"] is Array or bound["crew"].size() != CREW.size() \
		or not MissionState._point(bound["companion_start"], half) \
		or not M03MissionState._region(bound["boarding"], half) \
		or not bound["hatch_open"] is bool or not EquipmentState.integer(bound["hatch"], info["solids"].size() - 1):
		return MissionState.INVALID
	for index: int in range(ARRIVALS.size()):
		if not M06MissionState._arrival(bound["objectives"][index], OBJECTIVES[ARRIVALS[index]], half):
			return MissionState.INVALID
	for key: String in ["crew_release", "departure"]:
		if not M04MissionState._control(bound[key], details, half, ["lift_control"]) \
			or details[int(bound[key]["decoration"])]["solid"] == bound["hatch"]:
			return MissionState.INVALID
	if bound["crew_release"] == bound["departure"] or not M03MissionState._inside(bound["departure"]["approach"], bound["boarding"]):
		return MissionState.INVALID
	var hatch: Dictionary = info["solids"][int(bound["hatch"])]
	if (bound["hatch_open"] and float(hatch["bottom"]) < float(bound["boarding"]["max"][1]) + MoveStep.BODY_HEIGHT) \
		or (not bound["hatch_open"] and (float(hatch["bottom"]) > float(bound["departure"]["approach"][1]) \
			or float(hatch["top"]) < float(bound["departure"]["approach"][1]) + MoveStep.BODY_HEIGHT)):
		return MissionState.INVALID
	for index: int in range(CREW.size()):
		var crew: Variant = bound["crew"][index]
		if not M03MissionState._exact(crew, ["id", "route", "held_until"]) or crew["id"] != CREW[index] \
			or not crew["route"] is Array or crew["route"].size() < 2 or crew["route"].size() > 32 \
			or not crew["held_until"] is Array or crew["held_until"].size() != crew["route"].size():
			return MissionState.INVALID
		for point: int in range(crew["route"].size()):
			if not MissionState._point(crew["route"][point], half) or not EquipmentState.integer(crew["held_until"][point], 8) \
				or (point == 0 and crew["held_until"][point] != 0) \
				or (point > 0 and (crew["held_until"][point] < 3 or crew["held_until"][point] < crew["held_until"][point - 1])):
				return MissionState.INVALID
		if crew["held_until"][-1] < 7 or not M03MissionState._inside(crew["route"][-1], bound["boarding"]):
			return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M09_ID, "map_id": MAP_ID, "half_extent": float(info["half_extent"]), "m09": info["m09"].duplicate(true), "solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M09_ID or second.get("id") != MissionState.M09_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m09") is Dictionary or not second.get("m09") is Dictionary \
		or first.get("presentation") != second.get("presentation") or not first.get("solids") is Array \
		or not second.get("solids") is Array or first["solids"].size() != second["solids"].size():
		return false
	var before: Dictionary = first["m09"].duplicate(true)
	before["hatch_open"] = second["m09"]["hatch_open"]
	if before != second["m09"]:
		return false
	for index: int in range(first["solids"].size()):
		if index != int(before["hatch"]) and first["solids"][index] != second["solids"][index]:
			return false
		if index == int(before["hatch"]):
			for key: String in ["min_x", "max_x", "min_z", "max_z"]:
				if first["solids"][index][key] != second["solids"][index][key]:
					return false
	return true

static func _archive(value: Variant) -> bool:
	if M03MissionState._exact(value, ["kind"]) and value["kind"] == "historical_unrecorded":
		return true
	return M03MissionState._exact(value, ["kind", "custody_released", "recovered_mind_secured", "captives_evacuated"]) \
		and value["kind"] == "recorded" and value["custody_released"] is bool \
		and value["recovered_mind_secured"] is bool and value["captives_evacuated"] is bool \
		and (value["custody_released"] or not value["captives_evacuated"])

static func _crew_position(crew: Dictionary, bound: Dictionary, completed: int) -> bool:
	var route: Dictionary = {}
	for candidate: Dictionary in bound["crew"]:
		if candidate["id"] == crew["id"]:
			route = candidate
	if route.is_empty() or (completed < 3 and crew["feet"] != route["route"][0]) \
		or crew["aboard"] != (completed >= 3 and M03MissionState._inside(crew["feet"], bound["boarding"])):
		return false
	var point: Vector3 = Vector3(float(crew["feet"][0]), float(crew["feet"][1]), float(crew["feet"][2]))
	for index: int in range(route["route"].size() - 1):
		if crew["feet"] != route["route"][0] and int(route["held_until"][index + 1]) > completed:
			continue
		var a: Array = route["route"][index]
		var b: Array = route["route"][index + 1]
		var from: Vector2 = Vector2(float(a[0]), float(a[2]))
		var delta: Vector2 = Vector2(float(b[0]), float(b[2])) - from
		var actual: Vector2 = Vector2(point.x, point.z)
		var fraction: float = clampf((actual - from).dot(delta) / delta.length_squared(), 0.0, 1.0) if delta.length_squared() > 0.000001 else 0.0
		if actual.distance_to(from + delta * fraction) <= 0.01 and point.y >= minf(float(a[1]), float(b[1])) - 0.01 and point.y <= maxf(float(a[1]), float(b[1])) + 0.01:
			return true
	return false

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var raw: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m09"]
	if raw is Dictionary and raw.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(raw, keys) or raw["id"] != MissionState.M09_ID \
		or geometry.get("id") != MissionState.M09_ID or not geometry.get("m09") is Dictionary \
		or not MissionState.valid_rules(raw["rules"]) or raw["phase"] not in PHASES \
		or not EquipmentState.integer(raw["attempt"], 4294967295) or raw["attempt"] < 1 \
		or not EquipmentState.integer(raw["changed_at"], int(message["tick"])) \
		or not raw["party"] is Array or raw["party"].size() > 4 or not raw["prompts"] is Array or raw["prompts"].size() > raw["party"].size():
		return MissionState.INVALID
	var value: Dictionary = raw
	var bound: Dictionary = geometry["m09"]
	var progress: Variant = value["m09"]
	var departed: bool = value["phase"] == "departed"
	var facts: Array[String] = ["completed", "crew_released", "crew", "hatch_open", "charge_falls"]
	if not departed:
		facts.append("current")
	if progress is Dictionary and progress.has("carried_archive"):
		facts.append("carried_archive")
	if not M03MissionState._exact(progress, facts) or not progress["completed"] is Array \
		or not progress["crew_released"] is bool or not progress["hatch_open"] is bool \
		or not EquipmentState.integer(progress["charge_falls"], 7) or not progress["crew"] is Array or progress["crew"].size() not in [3, 4, 5] \
		or (progress.has("carried_archive") and not _archive(progress["carried_archive"])):
		return MissionState.INVALID
	var completed: Array = progress["completed"]
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append("party_departed")
	if completed.size() > order.size() or departed != (completed.size() == order.size()) \
		or progress["crew_released"] != (completed.size() >= 3) or progress["hatch_open"] != (completed.size() >= 7) \
		or progress["hatch_open"] != bound["hatch_open"] \
		or (value["phase"] == "briefing" and (not completed.is_empty() or progress["charge_falls"] > 0)):
		return MissionState.INVALID
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return MissionState.INVALID
	if not departed and progress["current"] != step(bound, completed.size()):
		return MissionState.INVALID
	for index: int in range(progress["crew"].size()):
		var crew: Variant = progress["crew"][index]
		if not M03MissionState._exact(crew, ["id", "feet", "aboard"]) \
			or (index < 3 and crew["id"] != CREW[index]) \
			or (index == 3 and crew["id"] not in ["edda", "splice"]) \
			or (index == 4 and (progress["crew"][3]["id"] != "edda" or crew["id"] != "splice")) \
			or not MissionState._point(crew["feet"], float(geometry["half_extent"])) or not crew["aboard"] is bool \
			or not _crew_position(crew, bound, completed.size()):
			return MissionState.INVALID
	var party: Dictionary = {}
	var all_aboard: bool = not value["party"].is_empty()
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
		all_aboard = all_aboard and member["ready"] and member["alive"] and member["aboard"]
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or value["phase"] != "in_progress" or not party.has(prompt["player_id"]) \
			or not party[prompt["player_id"]]["ready"] or not party[prompt["player_id"]]["alive"] or prompt["player_id"] in prompted \
			or (completed.size() != 2 and (completed.size() != 8 or not all_aboard \
				or (value["rules"]["difficulty"] == "severe" and progress["charge_falls"] == 0))):
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M09_ID or int(message["tick"]) < int(previous["tick"]) \
			or value["attempt"] < old["attempt"] or value["rules"] != old["rules"] or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		var before: Dictionary = old["m09"]
		if before.get("carried_archive") != progress.get("carried_archive") or before["crew"].size() != progress["crew"].size():
			return MissionState.INVALID
		for index: int in range(before["crew"].size()):
			if before["crew"][index]["id"] != progress["crew"][index]["id"]:
				return MissionState.INVALID
		if value["attempt"] == old["attempt"] and (completed.size() < before["completed"].size() \
			or progress["charge_falls"] < before["charge_falls"] or int(value["changed_at"]) < int(old["changed_at"]) \
			or PHASES.find(value["phase"]) < PHASES.find(old["phase"])):
			return MissionState.INVALID
	return ""
