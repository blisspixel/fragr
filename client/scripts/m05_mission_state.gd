class_name M05MissionState
extends RefCounted

const MAP_ID: int = 1005
const OBJECTIVES: Array[String] = ["roof_crossed", "grenade_lesson_cleared", "workshop_cleared", "trench_cleared", "heavy_cleared", "freight_secured"]
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const TRAM_PHASES: Array[String] = ["parked", "boarding", "moving", "blocked", "arrived"]
const DEPARTURE: String = "party_departed"
const WORKERS: Array[String] = ["splice", "workshop_agent_a", "workshop_agent_b"]

static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("m05")
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID \
		or info.get("geometry_version") != MapGeometry.VERSION or info.has("m04") or info.has("m03") \
		or info.get("mission") != null or info.get("m02_objectives") != null or info.get("m02_side_ward", false) != false \
		or not M03MissionState._exact(value, ["freight_open", "rescue", "objectives", "departure", "boarding", "companion_start", "tram"]):
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	if not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	var decorations: Array = info["presentation"]["decorations"]
	if not value["freight_open"] is bool or not M03MissionState._exact(value["rescue"], ["release", "captives"]) \
		or not M03MissionState._region(value["rescue"]["release"], half) or not M03MissionState._region(value["boarding"], half) \
		or not M04MissionState._control(value["departure"], decorations, half, ["lift_control", "m05_ship_departure"]) \
		or not M03MissionState._inside(value["departure"]["approach"], value["boarding"]) \
		or not MissionState._point(value["companion_start"], half) \
		or not value["objectives"] is Array or value["objectives"].size() != OBJECTIVES.size() \
		or not value["rescue"]["captives"] is Array or value["rescue"]["captives"].size() != 3 \
		or not M03MissionState._exact(value["tram"], ["solid", "start", "end", "speed", "activation"]):
		return MissionState.INVALID
	var tram: Dictionary = value["tram"]
	if decorations[int(value["departure"]["decoration"])]["solid"] == tram["solid"]:
		return MissionState.INVALID
	if not EquipmentState.integer(tram["solid"], info["solids"].size() - 1) or not MissionState._point(tram["start"], half) \
		or not MissionState._point(tram["end"], half) or not MapGeometry._number(tram["speed"]) \
		or float(tram["speed"]) < 0.1 or float(tram["speed"]) > 1.5 or not M03MissionState._region(tram["activation"], half) \
		or tram["start"][0] != tram["end"][0] or tram["start"][1] != tram["end"][1] \
		or absf(float(tram["end"][2]) - float(tram["start"][2])) < 2.0 or absf(float(tram["end"][2]) - float(tram["start"][2])) > 24.0:
		return MissionState.INVALID
	var solid: Dictionary = info["solids"][int(tram["solid"])]
	if absf(float(tram["start"][0]) - (float(solid["min_x"]) + float(solid["max_x"])) * 0.5) > 0.001 \
		or absf(float(tram["start"][1]) - float(solid.get("bottom", MoveStep.GROUND_Y))) > 0.001 \
		or absf(float(tram["start"][2]) - (float(solid["min_z"]) + float(solid["max_z"])) * 0.5) > 0.001:
		return MissionState.INVALID
	var offset: float = float(tram["end"][2]) - float(tram["start"][2])
	if maxf(absf(float(solid["min_z"]) + offset), absf(float(solid["max_z"]) + offset)) > half:
		return MissionState.INVALID
	for index: int in range(OBJECTIVES.size()):
		var goal: Variant = value["objectives"][index]
		if not M03MissionState._exact(goal, ["id", "action"]) or goal["id"] != OBJECTIVES[index] \
			or not M03MissionState._exact(goal["action"], ["kind", "region", "feet"]) or goal["action"]["kind"] != "arrival" \
			or not M03MissionState._region(goal["action"]["region"], half) or not MissionState._point(goal["action"]["feet"], half) \
			or not M03MissionState._inside(goal["action"]["feet"], goal["action"]["region"]):
			return MissionState.INVALID
	var seen: Array[String] = []
	for index: int in range(WORKERS.size()):
		var captive: Variant = value["rescue"]["captives"][index]
		if not M03MissionState._exact(captive, ["id", "held", "route"]) or not MissionState.valid_objective_id(captive["id"]) \
			or captive["id"] != WORKERS[index] or captive["id"] in seen or not MissionState._point(captive["held"], half) \
			or not M03MissionState._inside(captive["held"], value["rescue"]["release"]) \
			or not captive["route"] is Array or captive["route"].size() < 2 or captive["route"].size() > 16:
			return MissionState.INVALID
		seen.append(captive["id"])
		for point: Variant in captive["route"]:
			if not MissionState._point(point, half) or absf(float(point[1]) - float(captive["held"][1])) > 0.01:
				return MissionState.INVALID
		if captive["held"] != captive["route"][0] or not M03MissionState._inside(captive["route"].back(), value["boarding"]) or not M04MissionState._unambiguous_route(captive["route"]):
			return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M05_ID, "map_id": int(info["map_id"]), "half_extent": float(info["half_extent"]),
		"m05": info["m05"].duplicate(true), "tram_solid": info["solids"][int(info["m05"]["tram"]["solid"])].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M05_ID or second.get("id") != MissionState.M05_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or first.get("tram_solid") != second.get("tram_solid") or not first.get("m05") is Dictionary or not second.get("m05") is Dictionary:
		return false
	var before: Dictionary = first["m05"].duplicate(true)
	var after: Dictionary = second["m05"].duplicate(true)
	before.erase("freight_open")
	after.erase("freight_open")
	return before == after

static func tram_valid(value: Variant, bound: Dictionary, tick: int) -> bool:
	if not M03MissionState._exact(value, ["phase", "feet", "tick"]) or value["phase"] not in TRAM_PHASES \
		or not EquipmentState.integer(value["tick"], tick) or not MissionState._point(value["feet"], MapGeometry.MAX_HALF):
		return false
	var feet: Array = value["feet"]
	var start: Array = bound["start"]
	var end: Array = bound["end"]
	if absf(float(feet[0]) - float(start[0])) > 0.001 or absf(float(feet[1]) - float(start[1])) > 0.001 \
		or float(feet[2]) < minf(float(start[2]), float(end[2])) - 0.001 or float(feet[2]) > maxf(float(start[2]), float(end[2])) + 0.001:
		return false
	return (value["phase"] not in ["parked", "boarding"] or absf(float(feet[2]) - float(start[2])) <= 0.001) \
		and (value["phase"] != "arrived" or absf(float(feet[2]) - float(end[2])) <= 0.001)

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m05"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) or not M03MissionState._exact(value, keys) \
		or value["id"] != MissionState.M05_ID or geometry.get("id") != MissionState.M05_ID \
		or not geometry.get("m05") is Dictionary or not MissionState.valid_rules(value["rules"]) or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 or not value["prompts"] is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m05"]
	var progress: Variant = value["m05"]
	var departed: bool = value["phase"] == "departed"
	var progress_keys: Array[String] = ["completed", "workshop_secured", "group_released", "captives", "freight_open", "tram", "carried_recall_cars", "carried_patients", "carried_photos"]
	if not departed:
		progress_keys.append("current")
	if not M03MissionState._exact(progress, progress_keys) or not progress["completed"] is Array \
		or not progress["workshop_secured"] is bool or not progress["group_released"] is bool \
		or (progress["group_released"] and not progress["workshop_secured"]) or not progress["freight_open"] is bool \
		or progress["freight_open"] != bound["freight_open"] or not progress["captives"] is Array \
		or progress["captives"].size() != bound["rescue"]["captives"].size() or not EquipmentState.integer(progress["carried_photos"], 1000000) \
		or not tram_valid(progress["tram"], bound["tram"], int(message["tick"])) \
		or (not progress["group_released"] and progress["tram"]["phase"] != "parked"):
		return MissionState.INVALID
	for field: String in ["carried_recall_cars", "carried_patients"]:
		if not progress[field] is Array or progress[field].size() > 4:
			return MissionState.INVALID
		var ids: Array[String] = []
		for id: Variant in progress[field]:
			if not MissionState.valid_objective_id(id) or id in ids:
				return MissionState.INVALID
			ids.append(id)
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append(DEPARTURE)
	var completed: Array = progress["completed"]
	if completed.size() > order.size() or departed != (completed.size() == order.size()) \
		or (completed.size() >= 3 and not progress["workshop_secured"]) or (progress["group_released"] and completed.size() < 2) \
		or (progress["freight_open"] and completed.size() < 5):
		return MissionState.INVALID
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return MissionState.INVALID
	if not departed:
		var expected: Dictionary = bound["objectives"][completed.size()] if completed.size() < 6 else {"id": DEPARTURE, "action": {"kind": "use", "target": bound["departure"]}}
		if progress["current"] != expected:
			return MissionState.INVALID
	if value["phase"] == "briefing" and (not completed.is_empty() or progress["workshop_secured"] or progress["group_released"] or progress["freight_open"]):
		return MissionState.INVALID
	for index: int in range(progress["captives"].size()):
		var captive: Variant = progress["captives"][index]
		var authored: Dictionary = bound["rescue"]["captives"][index]
		if not M03MissionState._exact(captive, ["id", "feet"]) or captive["id"] != authored["id"] \
			or not MissionState._point(captive["feet"], float(geometry["half_extent"])) \
			or (not progress["group_released"] and not M03MissionState._same_point(captive["feet"], authored["held"])) \
			or (progress["group_released"] and M04MissionState.route_progress(captive["feet"], authored["route"]) < 0.0):
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
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or value["phase"] != "in_progress" \
			or prompt["kind"] != "objective_use" or not party.has(prompt["player_id"]) or prompt["player_id"] in prompted \
			or not aboard or completed.size() != 6 or not progress["freight_open"]:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M05_ID or int(message["tick"]) < int(previous["tick"]) or int(value["attempt"]) < int(old["attempt"]) \
			or value["rules"] != old["rules"] or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		var before: Dictionary = old["m05"]
		for retained: String in ["carried_recall_cars", "carried_patients", "carried_photos"]:
			if progress[retained] != before[retained]:
				return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			if completed.size() < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]) or int(progress["tram"]["tick"]) < int(before["tram"]["tick"]):
				return MissionState.INVALID
			for flag: String in ["workshop_secured", "group_released", "freight_open"]:
				if before[flag] and not progress[flag]:
					return MissionState.INVALID
			var direction: float = signf(float(bound["tram"]["end"][2]) - float(bound["tram"]["start"][2]))
			var maximum_travel: float = float(bound["tram"]["speed"]) * float(int(progress["tram"]["tick"]) - int(before["tram"]["tick"])) * MoveStep.DT_LIVE + 0.001
			if direction * (float(progress["tram"]["feet"][2]) - float(before["tram"]["feet"][2])) < -0.001 \
				or absf(float(progress["tram"]["feet"][2]) - float(before["tram"]["feet"][2])) > maximum_travel \
				or (before["tram"]["phase"] in ["moving", "blocked", "arrived"] and progress["tram"]["phase"] in ["parked", "boarding"]) \
				or (before["tram"]["phase"] == "arrived" and progress["tram"]["phase"] != "arrived"):
				return MissionState.INVALID
			if before["group_released"] and progress["group_released"]:
				for index: int in range(progress["captives"].size()):
					var route: Array = bound["rescue"]["captives"][index]["route"]
					if M04MissionState.route_progress(progress["captives"][index]["feet"], route) + 0.05 < M04MissionState.route_progress(before["captives"][index]["feet"], route):
						return MissionState.INVALID
	return ""
