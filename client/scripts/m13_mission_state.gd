class_name M13MissionState
extends RefCounted

## Foundry facts are accepted server receipts, never local outcomes.
const MAP_ID: int = 1013
const OBJECTIVES: Array[String] = ["foundry_entered", "machine_hall_cleared", "rocket_found", "freight_loop_secured", "relay_disabled", "upper_gallery_secured", "lift_boarded"]
const RESPONSES: Array[String] = ["volunteered", "departed_independently", "declined_and_kept_working"]
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty():
		return MissionState.INVALID
	if info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 or info.get("mission") != null or info.get("m02_objectives") != null or not MapGeometry._number(info.get("half_extent")) or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array or not info.get("solids") is Array:
		return MissionState.INVALID
	for key: String in ["m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"]):
		return MissionState.INVALID
	return map_value_error(info.get("m13"), float(info["half_extent"]), info["presentation"]["decorations"], info["solids"])

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M13_ID, "map_id": MAP_ID, "half_extent": float(info["half_extent"]), "m13": info["m13"].duplicate(true), "solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	return first == second

static func _points(value: Variant, half: float) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for feet: Variant in value:
		if not MissionState._point(feet, half):
			return false
	return true

static func departure_objective(g: Dictionary) -> Dictionary:
	return {"id": "party_departed", "action": {"kind": "arrival", "feet": [(float(g["inset_min"][0])+float(g["inset_max"][0]))*0.5, g["lift_top"], (float(g["inset_min"][1])+float(g["inset_max"][1]))*0.5], "region": {"min": [g["inset_min"][0], float(g["lift_top"])-0.06, g["inset_min"][1]], "max": [g["inset_max"][0], float(g["lift_top"])+0.06, g["inset_max"][1]]}}}

static func map_value_error(value: Variant, half: float, decorations: Array, solids: Array) -> String:
	if not M03MissionState._exact(value, ["objectives", "release", "departure", "relay", "protected", "hazard", "bypass", "cycle", "deck", "parked_top", "lift_top", "inset_min", "inset_max", "workers", "worker_destinations", "overseer"]) or not is_finite(half) or half < 2.0 or half > MapGeometry.MAX_HALF:
		return MissionState.INVALID
	if not EquipmentState.integer(value["relay"], solids.size()-1) or not EquipmentState.integer(value["deck"], solids.size()-1) or value["relay"] == value["deck"] or not value["protected"] is Array or value["protected"].is_empty():
		return MissionState.INVALID
	var hosts: Array = [value["relay"], value["deck"]]
	for host: Variant in value["protected"]:
		if not EquipmentState.integer(host, solids.size()-1) or host in hosts:
			return MissionState.INVALID
		hosts.append(host)
	if not M03MissionState._region(value["hazard"], half) or not M03MissionState._region(value["bypass"], half):
		return MissionState.INVALID
	var overlap: bool = true
	for axis: int in range(3):
		overlap = overlap and float(value["hazard"]["min"][axis]) < float(value["bypass"]["max"][axis]) and float(value["bypass"]["min"][axis]) < float(value["hazard"]["max"][axis])
	var cycle: Variant = value["cycle"]
	if overlap or not M03MissionState._exact(cycle, ["period", "warning", "active"]):
		return MissionState.INVALID
	for key: String in ["period", "warning", "active"]:
		if not EquipmentState.integer(cycle[key], 400) or int(cycle[key]) == 0:
			return MissionState.INVALID
	if int(cycle["warning"])+int(cycle["active"]) >= int(cycle["period"]):
		return MissionState.INVALID
	var deck: Dictionary = solids[int(value["deck"])]
	if not MapGeometry._number(value["parked_top"]) or not MapGeometry._number(value["lift_top"]) or float(value["lift_top"]) <= float(value["parked_top"]) or float(value["lift_top"]) > 512.0 or absf(float(deck["top"])-float(value["parked_top"])) > 0.001:
		return MissionState.INVALID
	for key: String in ["inset_min", "inset_max"]:
		if not value[key] is Array or value[key].size() != 2 or not MapGeometry._number(value[key][0]) or not MapGeometry._number(value[key][1]):
			return MissionState.INVALID
		if float(value[key][0]) < float(deck["min_x"]) or float(value[key][0]) > float(deck["max_x"]) or float(value[key][1]) < float(deck["min_z"]) or float(value[key][1]) > float(deck["max_z"]):
			return MissionState.INVALID
	if float(value["inset_min"][0]) >= float(value["inset_max"][0]) or float(value["inset_min"][1]) >= float(value["inset_max"][1]) or not _points(value["workers"], half) or not _points(value["worker_destinations"], half) or value["workers"][2] != value["worker_destinations"][2] or not MissionState._point(value["overseer"], half):
		return MissionState.INVALID
	if not M04MissionState._control(value["release"], decorations, half, ["terminal"]) or not M04MissionState._control(value["departure"], decorations, half, ["lift_control"]) or value["release"]["decoration"] == value["departure"]["decoration"] or decorations[int(value["departure"]["decoration"])].get("solid") != value["deck"]:
		return MissionState.INVALID
	if not value["objectives"] is Array or value["objectives"].size() != 7:
		return MissionState.INVALID
	for index: int in range(7):
		var objective: Variant = value["objectives"][index]
		if index == 6:
			if objective != {"id": OBJECTIVES[index], "action": {"kind": "use", "target": value["departure"]}}:
				return MissionState.INVALID
		elif index == 4:
			if not M03MissionState._exact(objective, ["id", "action"]) or objective["id"] != OBJECTIVES[index] or not M03MissionState._exact(objective["action"], ["kind", "solid", "approach", "aim"]) or objective["action"]["kind"] != "shoot" or objective["action"]["solid"] != value["relay"] or not MissionState._point(objective["action"]["approach"], half) or not MissionState._point(objective["action"]["aim"], half):
				return MissionState.INVALID
		elif not M06MissionState._arrival(objective, OBJECTIVES[index], half):
			return MissionState.INVALID
	return ""

static func challenge_error(value: Variant) -> String:
	var keys: Array[String] = ["workers_arrived", "hazard_hurt", "supports_cleared"]
	if value is Dictionary and value.has("workers"):
		keys.append("workers")
	if not M03MissionState._exact(value, keys) or not EquipmentState.integer(value["hazard_hurt"], EquipmentState.MAX_EXACT_INTEGER) or not value["supports_cleared"] is bool or not value["workers_arrived"] is Array or value["workers_arrived"].size() != 3 or (value.has("workers") and value["workers"] != RESPONSES):
		return MissionState.INVALID
	for arrived: Variant in value["workers_arrived"]:
		if not arrived is bool or (arrived and not value.has("workers")):
			return MissionState.INVALID
	return MissionState.INVALID if value["workers_arrived"][2] else ""

static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value.has("workers") and (difficulty == "assisted" or value["supports_cleared"]) and (difficulty != "severe" or int(value["hazard_hurt"]) == 0)

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "relay_disabled", "overseer_surrendered", "worker_feet", "lift", "hazard_phase"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if phase not in PHASES or not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) or not M03MissionState._exact(value, keys) or not value["completed"] is Array or not challenge_error(value["challenges"]).is_empty() or not value["relay_disabled"] is bool or not value["overseer_surrendered"] is bool or not _points(value["worker_feet"], 512.0) or not M03MissionState._exact(value["lift"], ["phase", "top", "tick", "returning"]) or value["lift"]["phase"] not in ["parked", "moving", "blocked", "returning", "arrived"] or not value["lift"]["returning"] is bool or (value["lift"]["phase"] == "returning" and not value["lift"]["returning"]) or (value["lift"]["phase"] in ["parked", "moving", "arrived"] and value["lift"]["returning"]) or value["lift"]["tick"] != tick or not MapGeometry._number(value["lift"]["top"]) or float(value["lift"]["top"]) < 0.0 or float(value["lift"]["top"]) > 512.0 or value["hazard_phase"] not in ["idle", "warning", "active"]:
		return MissionState.INVALID
	var n: int = value["completed"].size()
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append("party_departed")
	if n > 8 or (phase == "departed") != (n == 8) or value.has("current") != (n < 8) or value["relay_disabled"] != (n >= 5) or value["challenges"]["supports_cleared"] != (n >= 6) or (value["challenges"].has("workers") and not value["overseer_surrendered"]) or (n >= 3 and not value["overseer_surrendered"]) or (n < 7 and value["lift"]["phase"] != "parked") or (n == 8 and value["lift"]["phase"] != "arrived"):
		return MissionState.INVALID
	for index: int in range(n):
		if value["completed"][index] != order[index]:
			return MissionState.INVALID
	if n < 8 and (not M03MissionState._exact(value["current"], ["id", "action"]) or value["current"]["id"] != order[n]):
		return MissionState.INVALID
	var challenges: Dictionary = value["challenges"]
	if phase == "briefing" and (n != 0 or value["overseer_surrendered"] or challenges.has("workers") or true in challenges["workers_arrived"] or int(challenges["hazard_hurt"]) != 0 or challenges["supports_cleared"]):
		return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m13"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M13_ID or geometry.get("id") != MissionState.M13_ID or not geometry.get("m13") is Dictionary or not MissionState.valid_rules(value["rules"]) or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 or not EquipmentState.integer(value["changed_at"], int(message["tick"])) or not value["party"] is Array or value["party"].size() > 4 or not value["prompts"] is Array or value["prompts"].size() > value["party"].size() or not facts_error(value["m13"], str(value["phase"]), int(message["tick"])).is_empty():
		return MissionState.INVALID
	var g: Dictionary = geometry["m13"]
	var p: Dictionary = value["m13"]
	var n: int = p["completed"].size()
	if n < 7 and p["current"] != g["objectives"][n]:
		return MissionState.INVALID
	if n == 7 and not _same_departure(p["current"], g):
		return MissionState.INVALID
	var cycle: Dictionary = g["cycle"]
	var place: int = int(message["tick"]) % int(cycle["period"])
	var idle: int = int(cycle["period"])-int(cycle["warning"])-int(cycle["active"])
	var hazard_phase: String = "idle" if place < idle else "warning" if place < idle+int(cycle["warning"]) else "active"
	if p["hazard_phase"] != hazard_phase:
		return MissionState.INVALID
	var top: float = float(p["lift"]["top"])
	if top < float(g["parked_top"])-0.001 or top > float(g["lift_top"])+0.001 or (p["lift"]["phase"] == "parked" and absf(top-float(g["parked_top"])) > 0.001) or (p["lift"]["phase"] == "arrived" and absf(top-float(g["lift_top"])) > 0.001):
		return MissionState.INVALID
	for index: int in range(3):
		if not MissionState._point(p["worker_feet"][index],float(geometry["half_extent"])):
			return MissionState.INVALID
		if (not p["challenges"].has("workers") or index == 2) and p["worker_feet"][index] != g["workers"][index]:
			return MissionState.INVALID
		if _worker_progress(p["worker_feet"][index], g["workers"][index], g["worker_destinations"][index]) < 0.0:
			return MissionState.INVALID
		if p["challenges"]["workers_arrived"][index]:
			for axis: int in range(3):
				if absf(float(p["worker_feet"][index][axis])-float(g["worker_destinations"][index][axis])) > 0.05:
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
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" or value["phase"] != "in_progress" or not party.has(prompt["player_id"]) or prompt["player_id"] in prompted or not party[prompt["player_id"]]["alive"] or not party[prompt["player_id"]]["ready"] or not ((p["overseer_surrendered"] and not p["challenges"].has("workers")) or (n in [6,7] and p["lift"]["phase"] == "parked" and all_aboard)):
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M13_ID or int(message["tick"]) < int(previous["tick"]) or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		if value["attempt"] == old["attempt"]:
			var before: Dictionary = old["m13"]
			var rise: float = top-float(before["lift"]["top"])
			var travel_limit: float = 1.5*MoveStep.DT_LIVE*float(int(message["tick"])-int(previous["tick"]))+0.001
			# Sparse delivery may skip an entire change of direction. Bound actual
			# displacement; each sample already validates its own phase/direction.
			if absf(rise) > travel_limit:
				return MissionState.INVALID
			if n < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) or int(value["changed_at"]) < int(old["changed_at"]) or int(p["challenges"]["hazard_hurt"]) < int(before["challenges"]["hazard_hurt"]) or (before["overseer_surrendered"] and not p["overseer_surrendered"]) or (before["challenges"].has("workers") and p["challenges"].get("workers") != before["challenges"]["workers"]):
				return MissionState.INVALID
			for index: int in range(3):
				if before["challenges"]["workers_arrived"][index] and not p["challenges"]["workers_arrived"][index]:
					return MissionState.INVALID
				if _worker_progress(p["worker_feet"][index], g["workers"][index], g["worker_destinations"][index])+0.05 < _worker_progress(before["worker_feet"][index], g["workers"][index], g["worker_destinations"][index]):
					return MissionState.INVALID
	return ""

static func _worker_progress(feet: Array, start: Array, finish: Array) -> float:
	if start == finish:
		for axis: int in range(3):
			if absf(float(feet[axis])-float(start[axis])) > 0.05:
				return -1.0
		return 0.0
	return M04MissionState.route_progress(feet, [start, finish])

static func _same_departure(value: Dictionary, g: Dictionary) -> bool:
	if not M06MissionState._arrival(value,"party_departed",MapGeometry.MAX_HALF):
		return false
	var expected: Dictionary = departure_objective(g)["action"]
	for index: int in range(3):
		if absf(float(value["action"]["feet"][index])-float(expected["feet"][index])) > 0.001:
			return false
		for key: String in ["min","max"]:
			if absf(float(value["action"]["region"][key][index])-float(expected["region"][key][index])) > 0.001:
				return false
	return true

static func deck_at(geometry: Dictionary, top: float) -> Dictionary:
	var solid: Dictionary = geometry["solids"][int(geometry["m13"]["deck"])].duplicate()
	var height: float = float(solid["top"])-float(solid["bottom"])
	solid["top"] = top
	solid["bottom"] = top-height
	return solid
