class_name M14MissionState
extends RefCounted

## Launch-work facts bind the moving boss and the accepted fallen world.
const MAP_ID: int = 1014
const OBJECTIVES: Array[String] = ["arrival", "depot_secured", "road_secured", "approach_secured", "walker_disabled", "gantry_secured"]
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const FALLEN_MIN: Array[Vector3] = [Vector3(5,0,24), Vector3(4.4,0,23.4), Vector3(4.4,0,27.4), Vector3(9.8,0,23.4), Vector3(9.8,0,27.4)]
const FALLEN_MAX: Array[Vector3] = [Vector3(11,1.6,28), Vector3(6.2,0.55,24.6), Vector3(6.2,0.55,28.6), Vector3(11.6,0.55,24.6), Vector3(11.6,0.55,28.6)]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("m14")
	if not M03MissionState._exact(g, ["objectives", "departure", "boarding", "jeep", "walker_solids", "fallen"]) or not g["fallen"] is bool or not g["objectives"] is Array or g["objectives"].size() != OBJECTIVES.size() or not g["walker_solids"] is Array or g["walker_solids"].size() != 5:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	for index: int in range(OBJECTIVES.size()):
		if not M06MissionState._arrival(g["objectives"][index], OBJECTIVES[index], half):
			return MissionState.INVALID
	if not M03MissionState._region(g["boarding"], half) or not M04MissionState._control(g["departure"], info["presentation"]["decorations"], half, ["terminal", "lift_control"]) or not M03MissionState._inside(g["departure"]["approach"], g["boarding"]):
		return MissionState.INVALID
	if not M03MissionState._exact(g["jeep"], ["feet", "yaw"]) or not MissionState._point(g["jeep"]["feet"], half) or not MapGeometry._number(g["jeep"]["yaw"]) or float(g["jeep"]["yaw"]) < 0.0 or float(g["jeep"]["yaw"]) >= TAU:
		return MissionState.INVALID
	var seen: Array[int] = []
	for index: Variant in g["walker_solids"]:
		if not EquipmentState.integer(index, info["solids"].size()-1) or int(index) in seen:
			return MissionState.INVALID
		seen.append(int(index))
		var solid: Dictionary = info["solids"][int(index)]
		if g["fallen"] and (float(solid.get("bottom", 0.0)) != 0.0 or float(solid.get("top", MoveStep.WALL_TOP)) > 2.0):
			return MissionState.INVALID
	for decoration: Dictionary in info["presentation"]["decorations"]:
		if int(decoration["solid"]) in seen:
			return MissionState.INVALID
	if g["fallen"]:
		if info.has("walker") or not _fallen_shape(info["solids"], g["walker_solids"]):
			return MissionState.INVALID
	elif not info.get("walker") is Dictionary or info["walker"]["solids"] != g["walker_solids"]:
		return MissionState.INVALID
	return ""

static func _fallen_shape(solids: Array, indices: Array) -> bool:
	var origin: Dictionary = solids[int(indices[0])]
	var offset := Vector3(float(origin["min_x"]), float(origin.get("bottom", 0.0)), float(origin["min_z"])) - FALLEN_MIN[0]
	if absf(offset.y) > 0.0001:
		return false
	for index: int in range(5):
		var solid: Dictionary = solids[int(indices[index])]
		var low := Vector3(float(solid["min_x"]), float(solid.get("bottom", 0.0)), float(solid["min_z"]))
		var high := Vector3(float(solid["max_x"]), float(solid.get("top", MoveStep.WALL_TOP)), float(solid["max_z"]))
		if (low - FALLEN_MIN[index] - offset).length() > 0.0001 or (high - FALLEN_MAX[index] - offset).length() > 0.0001:
			return false
	return true

static func geometry_for(info: Dictionary) -> Dictionary:
	var result: Dictionary = {"id": MissionState.M14_ID, "map_id": MAP_ID, "half_extent": float(info["half_extent"]), "m14": info["m14"].duplicate(true), "solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}
	if info.get("walker") is Dictionary:
		result["walker"] = info["walker"].duplicate(true)
	return result

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M14_ID or second.get("id") != MissionState.M14_ID or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") or first.get("presentation") != second.get("presentation"):
		return false
	var a: Dictionary = first["m14"].duplicate(true)
	var b: Dictionary = second["m14"].duplicate(true)
	var changed: bool = a["fallen"] != b["fallen"]
	a.erase("fallen")
	b.erase("fallen")
	if a != b or first["solids"].size() != second["solids"].size():
		return false
	if not changed:
		return first["solids"] == second["solids"] and first.get("walker") == second.get("walker")
	var indices: Array[int] = []
	for index: Variant in a["walker_solids"]:
		indices.append(int(index))
	for index: int in range(first["solids"].size()):
		if index not in indices and first["solids"][index] != second["solids"][index]:
			return false
	return true

static func challenge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, ["depot_secured", "walker_disabled", "jeep_preserved", "on_foot"]):
		return MissionState.INVALID
	for key: String in value:
		if not value[key] is bool:
			return MissionState.INVALID
	return MissionState.INVALID if value["walker_disabled"] and not value["depot_secured"] else ""

static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value["depot_secured"] and (difficulty == "assisted" or (value["walker_disabled"] and value["jeep_preserved"] and (difficulty != "severe" or value["on_foot"])))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "jeep_id", "support_stage", "first_cycle_complete", "machine_fallen"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if phase not in PHASES or not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) or not M03MissionState._exact(value, keys) or not value["completed"] is Array or not challenge_error(value["challenges"]).is_empty() or not EquipmentState.integer(value["jeep_id"], 1) or value["jeep_id"] != 1 or not EquipmentState.integer(value["support_stage"], 2) or not value["first_cycle_complete"] is bool or not value["machine_fallen"] is bool:
		return MissionState.INVALID
	var n: int = value["completed"].size()
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append("party_departed")
	var c: Dictionary = value["challenges"]
	if n < 4 and (value["first_cycle_complete"] or value["support_stage"] > 0 or not c["on_foot"]):
		return MissionState.INVALID
	if n > 7 or (phase == "departed") != (n == 7) or value.has("current") != (n < 7) or c["depot_secured"] != (n >= 2) or (c["walker_disabled"] and n < 4) or (value["machine_fallen"] and not c["walker_disabled"]) or (n >= 5 and (not value["machine_fallen"] or value["support_stage"] != 2)) or (value["support_stage"] > 0 and not value["first_cycle_complete"] and not c["walker_disabled"]):
		return MissionState.INVALID
	for index: int in range(n):
		if value["completed"][index] != order[index]:
			return MissionState.INVALID
	if n < 7:
		if n < 6:
			if not M06MissionState._arrival(value["current"], order[n], 512.0):
				return MissionState.INVALID
		elif not M03MissionState._exact(value["current"], ["id", "action"]) or value["current"]["id"] != order[n] or not M03MissionState._exact(value["current"]["action"], ["kind", "target"]) or value["current"]["action"]["kind"] != "use":
			return MissionState.INVALID
	if phase == "briefing" and (n != 0 or c != {"depot_secured": false, "walker_disabled": false, "jeep_preserved": true, "on_foot": true} or value["support_stage"] != 0 or value["first_cycle_complete"] or value["machine_fallen"]):
		return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m14"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M14_ID or geometry.get("id") != MissionState.M14_ID or not geometry.get("m14") is Dictionary or not MissionState.valid_rules(value["rules"]) or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 or not EquipmentState.integer(value["changed_at"], int(message["tick"])) or not value["party"] is Array or value["party"].size() > 4 or not value["prompts"] is Array or value["prompts"].size() > value["party"].size() or not facts_error(value["m14"], str(value["phase"]), int(message["tick"])).is_empty():
		return MissionState.INVALID
	var g: Dictionary = geometry["m14"]
	var p: Dictionary = value["m14"]
	var n: int = p["completed"].size()
	if p["machine_fallen"] != g["fallen"]:
		return MissionState.INVALID
	if n < 7:
		var expected: Dictionary = g["objectives"][n] if n < 6 else {"id": "party_departed", "action": {"kind": "use", "target": g["departure"]}}
		if p["current"] != expected:
			return MissionState.INVALID
	var party: Dictionary = {}
	for member: Variant in value["party"]:
		if not M03MissionState._exact(member, ["id", "name", "ready", "alive", "aboard"]) or not MissionState._uuid(member["id"]) or party.has(member["id"]) or not member["name"] is String or member["name"].is_empty() or member["name"].length() > 48 or not member["ready"] is bool or not member["alive"] is bool or not member["aboard"] is bool or (member["aboard"] and (not member["ready"] or not member["alive"] or value["phase"] == "briefing")):
			return MissionState.INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return MissionState.INVALID
		party[member["id"]] = member
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	var all_aboard: bool = not party.is_empty()
	for member: Dictionary in party.values():
		all_aboard = all_aboard and member["ready"] and member["alive"] and member["aboard"]
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" or value["phase"] != "in_progress" or n != 6 or not all_aboard or not party.has(prompt["player_id"]) or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M14_ID or int(message["tick"]) < int(previous["tick"]) or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		if value["attempt"] == old["attempt"]:
			var before: Dictionary = old["m14"]
			if n < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) or int(value["changed_at"]) < int(old["changed_at"]) or p["support_stage"] < before["support_stage"]:
				return MissionState.INVALID
			for key: String in ["first_cycle_complete", "machine_fallen"]:
				if before[key] and not p[key]:
					return MissionState.INVALID
			for key: String in ["depot_secured", "walker_disabled"]:
				if before["challenges"][key] and not p["challenges"][key]:
					return MissionState.INVALID
			for key: String in ["jeep_preserved", "on_foot"]:
				if not before["challenges"][key] and p["challenges"][key]:
					return MissionState.INVALID
				if before["challenges"]["walker_disabled"] and before["challenges"][key] != p["challenges"][key]:
					return MissionState.INVALID
	return ""
